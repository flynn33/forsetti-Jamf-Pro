import Foundation
#if canImport(MetalKit)
import MetalKit
import QuartzCore
import os
#endif

// "A robot may not injure a human being or, through inaction, allow a human being to come to harm.
//  A robot must obey the orders given it by human beings except where such orders would conflict with the First Law.
//  A robot must protect its own existence as long as such protection does not conflict with the First or Second Law."

/// Visual presentation mode for the storage gauge.
///
/// - `.inline`: small bar embedded in a search-result row. Renders paused;
///    redraws only when the fill value or color tier changes. No wave animation,
///    no flowing-light highlight — keeps GPU idle in long lists.
/// - `.detail`: large showcase bar in the device detail card. Renders at 30 fps
///    with a subtle liquid wave plus a flowing-light pass.
enum HardwareStorageGaugeStyle: Sendable, Equatable {
    case inline
    case detail
}

#if canImport(MetalKit)

/// CPU-side mirror of the MSL `HardwareStorageUniforms` struct. Field order and
/// padding must match the shader exactly — Metal does not memcpy through a
/// type system so the struct is fragile to edits.
private struct HardwareStorageUniforms {
    /// Drawable resolution in pixels.
    var resolution: SIMD2<Float>
    /// Animation time in seconds since the renderer started.
    var time: Float
    /// Fill level 0-1, eased on the GPU side toward `usedFraction` for smoothness.
    var usedFraction: Float
    /// 1 = `.detail` (animated wave), 0 = `.inline` (static fill).
    var styleFlag: Float
    /// Padding bytes to pad the struct to a 16-byte boundary. Required by Metal.
    var padding: SIMD3<Float> = .zero
}

/// `MTKViewDelegate` that compiles a small fragment shader and renders the
/// storage gauge into its host view.
///
/// All instances share one `MTLDevice` and one `MTLCommandQueue` via the static
/// helpers below. The renderer keeps a tiny per-instance state (current eased
/// fill value, target fill value, and start time) so multiple gauges can run
/// independent animations without trampling each other's uniforms.
final class HardwareStorageRenderer: NSObject, MTKViewDelegate {

    // MARK: - Shared GPU resources

    /// One Metal device for the whole app. `MTLDevice` construction is heavy
    /// and there is no benefit to multiple devices on the same GPU — every
    /// renderer pulls from this lazy initializer.
    static let sharedDevice: MTLDevice? = {
        MTLCreateSystemDefaultDevice()
    }()

    /// One command queue per shared device. Command encoding is single-threaded
    /// per queue but per-encoder, so all gauges enqueue safely.
    static let sharedCommandQueue: MTLCommandQueue? = {
        guard let device = sharedDevice else {
            return nil
        }
        return device.makeCommandQueue()
    }()

    /// One pipeline state per shared device. Pipeline construction parses MSL
    /// and links shader stages; sharing it across renderers keeps that work
    /// off the per-instance hot path.
    ///
    /// `lastInitError` is set to a one-line description of any failure so the
    /// view-model layer can include it in diagnostic events without anyone
    /// needing to open Console.app for the OSLog stream.
    static let sharedPipelineState: MTLRenderPipelineState? = {
        guard let device = sharedDevice else {
            lastInitError = "MTLCreateSystemDefaultDevice() returned nil"
            return nil
        }

        do {
            let library = try device.makeLibrary(source: shaderSource, options: nil)
            guard let vertex = library.makeFunction(name: "hardwareStorageVertex"),
                  let fragment = library.makeFunction(name: "hardwareStorageFragment")
            else {
                let message = "Shader functions hardwareStorageVertex/Fragment not found in library"
                logger.error("\(message, privacy: .public)")
                lastInitError = message
                return nil
            }

            let descriptor = MTLRenderPipelineDescriptor()
            descriptor.vertexFunction = vertex
            descriptor.fragmentFunction = fragment
            descriptor.colorAttachments[0].pixelFormat = .bgra8Unorm
            descriptor.colorAttachments[0].isBlendingEnabled = true
            descriptor.colorAttachments[0].rgbBlendOperation = .add
            descriptor.colorAttachments[0].alphaBlendOperation = .add
            descriptor.colorAttachments[0].sourceRGBBlendFactor = .sourceAlpha
            descriptor.colorAttachments[0].destinationRGBBlendFactor = .oneMinusSourceAlpha
            descriptor.colorAttachments[0].sourceAlphaBlendFactor = .one
            descriptor.colorAttachments[0].destinationAlphaBlendFactor = .oneMinusSourceAlpha

            return try device.makeRenderPipelineState(descriptor: descriptor)
        } catch {
            let description = error.localizedDescription
            logger.error("Pipeline state creation failed: \(description, privacy: .public)")
            lastInitError = description
            return nil
        }
    }()

    /// Captured by `sharedPipelineState`'s init closure if any step of Metal
    /// setup failed. Read by diagnostics to surface Metal init failures
    /// alongside the rest of the search log.
    nonisolated(unsafe) static var lastInitError: String?

    private static let logger = Logger(subsystem: "com.forsetti.jamfpro", category: "HardwareStorageRenderer")

    // MARK: - Per-instance state

    /// Visual presentation mode set at init.
    let style: HardwareStorageGaugeStyle

    /// Latest target fill, set by the SwiftUI representable each `update*View`.
    /// Atomic write guard keeps the producer (main actor) and consumer (Metal
    /// thread) from racing — Float assignment is already atomic on Apple Silicon
    /// but a queue lock makes the contract explicit.
    private var fillTarget: Float
    private var fillCurrent: Float
    private let stateLock = NSLock()
    private let startTime = CACurrentMediaTime()

    /// Returns nil if the shared GPU resources didn't initialize. The view
    /// layer routes a nil renderer to the SwiftUI fallback.
    init?(style: HardwareStorageGaugeStyle, initialFraction: Float) {
        guard Self.sharedDevice != nil,
              Self.sharedCommandQueue != nil,
              Self.sharedPipelineState != nil
        else {
            return nil
        }

        self.style = style
        self.fillTarget = max(0, min(1, initialFraction))
        self.fillCurrent = self.fillTarget
        super.init()
    }

    /// Pushes a new fill target. The renderer eases `fillCurrent` toward this
    /// value across subsequent frames so swapping records produces a smooth
    /// liquid rise rather than a hard jump.
    func setUsedFraction(_ value: Float) {
        let clamped = max(0, min(1, value))
        stateLock.lock()
        fillTarget = clamped
        stateLock.unlock()
    }

    // MARK: - MTKViewDelegate

    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {
        _ = view
        _ = size
    }

    func draw(in view: MTKView) {
        guard let descriptor = view.currentRenderPassDescriptor,
              let drawable = view.currentDrawable,
              let queue = Self.sharedCommandQueue,
              let pipeline = Self.sharedPipelineState,
              let commandBuffer = queue.makeCommandBuffer(),
              let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: descriptor)
        else {
            return
        }

        // Ease current fill toward target. Uses simple lerp so the framerate
        // controls the perceived speed (30 fps → ~0.4 s to settle on a 50%
        // delta). Inline mode runs paused so this lerp only steps once per
        // value change which is fine — at the small drawable size, even a
        // hard jump reads as "instant" without looking glitchy.
        stateLock.lock()
        let target = fillTarget
        let easing: Float = (style == .inline) ? 0.55 : 0.08
        fillCurrent += (target - fillCurrent) * easing
        let drawnFill = fillCurrent
        stateLock.unlock()

        encoder.setRenderPipelineState(pipeline)

        var uniforms = HardwareStorageUniforms(
            resolution: SIMD2<Float>(
                Float(max(view.drawableSize.width, 1)),
                Float(max(view.drawableSize.height, 1))
            ),
            time: Float(CACurrentMediaTime() - startTime),
            usedFraction: drawnFill,
            styleFlag: (style == .detail) ? 1 : 0
        )
        encoder.setFragmentBytes(&uniforms, length: MemoryLayout<HardwareStorageUniforms>.stride, index: 0)

        encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
        encoder.endEncoding()

        commandBuffer.present(drawable)
        commandBuffer.commit()
    }

    // MARK: - Embedded MSL

    /// MSL source compiled at runtime. Two-function pipeline (fullscreen
    /// vertex + fragment) — the fragment owns all the visual logic.
    ///
    /// Color heatmap: green (low usage) → yellow (mid) → red (full).
    /// Detail mode adds a faint sine wave at the fill front and a horizontal
    /// flowing-light highlight; inline mode renders a flat fill.
    /// Clean progress-bar shader. Renders a pill-shaped track with a
    /// solid-color fill region. Antialiasing uses `fwidth(sdf)` so the
    /// transition band is exactly one pixel regardless of drawable size —
    /// sharp at any height, no resolution-dependent grain.
    ///
    /// Removed from the previous version: wave displacement, flowing-light
    /// highlight, vertical depth gradient. These read as "grainy" or
    /// "noisy" at the small progress-bar sizes the design now uses.
    /// `styleFlag`, `time`, and `padding` are still in the uniform layout
    /// for binary compatibility with the Swift `HardwareStorageUniforms`
    /// struct, but no longer affect the visual output.
    private static let shaderSource = """
    #include <metal_stdlib>
    using namespace metal;

    struct HardwareStorageUniforms {
        float2 resolution;
        float time;
        float usedFraction;
        float styleFlag;
        float3 padding;
    };

    struct HardwareStorageVertexOutput {
        float4 position [[position]];
        float2 uv;
    };

    vertex HardwareStorageVertexOutput hardwareStorageVertex(uint vertexID [[vertex_id]]) {
        const float2 positions[3] = {
            float2(-1.0, -1.0),
            float2( 3.0, -1.0),
            float2(-1.0,  3.0)
        };

        HardwareStorageVertexOutput output;
        output.position = float4(positions[vertexID], 0.0, 1.0);
        output.uv = positions[vertexID] * 0.5 + 0.5;
        return output;
    }

    // Signed distance from a rounded rectangle (used as a pill when
    // radius == halfSize.y).
    float roundedBoxSDF(float2 p, float2 halfSize, float radius) {
        float2 q = abs(p) - halfSize + radius;
        return length(max(q, 0.0)) + min(max(q.x, q.y), 0.0) - radius;
    }

    fragment float4 hardwareStorageFragment(
        HardwareStorageVertexOutput input [[stage_in]],
        constant HardwareStorageUniforms& u [[buffer(0)]]
    ) {
        float2 uv = input.uv;

        // Aspect-corrected coordinates so the rounded ends stay circular
        // regardless of drawable aspect ratio. For a wide thin progress
        // bar (e.g. 200pt × 10pt) the y-extent is much smaller than x,
        // and unscaled SDF math would squish the corners.
        float aspect = u.resolution.x / max(u.resolution.y, 1.0);
        float2 p = (uv - 0.5) * float2(aspect, 1.0);

        // Pill geometry: half-extents in p-space, with a tiny inset so the
        // antialiased edge has room to fade inside the drawable.
        float halfHeight = 0.5 - 0.01;
        float halfWidth  = aspect * 0.5 - 0.01;
        float radius     = halfHeight; // full pill: corner radius == half-height

        // roundedBoxSDF takes the OUTER half-size; it adds `+ radius` internally
        // to shift into inner-rect space. Subtracting radius here would zero
        // halfSize.y (radius == halfHeight in this pill geometry) and collapse
        // the bar to a horizontal line — that was the empty-gauge bug in 3.19.0.
        float sdf = roundedBoxSDF(p, float2(halfWidth, halfHeight), radius);

        // One-pixel-wide antialiasing band. fwidth gives the per-pixel
        // derivative magnitude — using it here means edges look identical
        // at 10pt and 60pt heights (the AA always covers exactly one pixel
        // of transition rather than a fixed UV-space slice).
        float aaPill = fwidth(sdf);
        float mask   = 1.0 - smoothstep(-aaPill, aaPill, sdf);

        // Fill edge with sub-pixel antialiasing as well.
        float fillEdge = u.usedFraction;
        float aaEdge   = fwidth(uv.x) * 0.5;
        float inside   = 1.0 - smoothstep(fillEdge - aaEdge, fillEdge + aaEdge, uv.x);

        // Heatmap by usage level: green → yellow → red.
        float3 green  = float3(0.18, 0.72, 0.40);
        float3 yellow = float3(0.95, 0.78, 0.20);
        float3 red    = float3(0.92, 0.30, 0.30);
        float t = clamp(u.usedFraction, 0.0, 1.0);
        float3 fillColor = (t < 0.5)
            ? mix(green, yellow, t * 2.0)
            : mix(yellow, red,   (t - 0.5) * 2.0);

        // Subtle solid track so the unfilled portion still reads as a
        // container.
        float3 track = float3(0.20, 0.22, 0.28);
        float3 finalColor = mix(track, fillColor, inside);

        return float4(finalColor, mask);
    }
    """
}

#endif

//endofline
