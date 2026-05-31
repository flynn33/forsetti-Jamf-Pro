import SwiftUI
#if canImport(MetalKit)
import MetalKit
import QuartzCore
import os
#endif

/// A SwiftUI view that renders a subtle, animated Metal backdrop for dashboard
/// presentation polish.
///
/// On devices that support Metal, this view displays a GPU-driven animated
/// gradient. On unsupported platforms it gracefully degrades to `Color.clear`.
struct ForsettiMetalBackgroundView: View {
    var body: some View {
#if canImport(MetalKit)
        if MTLCreateSystemDefaultDevice() != nil {
            ForsettiMetalBackgroundRepresentable()
                .allowsHitTesting(false)   // Pass all touches through to content below
                .accessibilityHidden(true) // Decorative only -- hide from VoiceOver
        } else {
            Color.clear
        }
#else
        Color.clear
#endif
    }
}

#if canImport(MetalKit)

/// The uniform buffer layout shared between Swift and the Metal shader.
/// Fields must match the MSL `ForsettiMetalUniforms` struct exactly.
private struct ForsettiMetalUniforms {
    /// The drawable resolution in pixels (width, height).
    var resolution: SIMD2<Float>
    /// Elapsed time in seconds since the renderer was created.
    var time: Float
    /// Padding to align the struct to 16-byte boundaries for Metal.
    var padding: Float = 0
}

/// The core Metal renderer that compiles the gradient shader, manages the
/// pipeline state, and issues draw calls each frame.
///
/// This class owns the `MTLCommandQueue` and `MTLRenderPipelineState` and
/// acts as the `MTKViewDelegate`, receiving `draw(in:)` callbacks at the
/// view's preferred frame rate.
private final class ForsettiMetalBackgroundRenderer: NSObject, MTKViewDelegate {
    private static let logger = Logger(subsystem: ForsettiAppIdentity.bundleIdentifier, category: "MetalRenderer")

    /// The GPU command queue used to submit render work.
    private let commandQueue: MTLCommandQueue
    /// The compiled render pipeline (vertex + fragment functions and blend state).
    private let pipelineState: MTLRenderPipelineState
    /// Timestamp captured at init, used to compute elapsed animation time.
    private let startTime = CACurrentMediaTime()

    /// Initializes the renderer by compiling the embedded shader source and
    /// building the full render pipeline.
    ///
    /// - Parameter device: The Metal device to use for GPU resource allocation.
    /// - Returns: `nil` if any step of pipeline creation fails.
    init?(device: MTLDevice) {
        guard let commandQueue = device.makeCommandQueue() else {
            Self.logger.error("Metal background renderer failed to create command queue.")
            return nil
        }

        // Compile the shader source at runtime (avoids requiring a .metallib build step)
        let library: MTLLibrary
        do {
            library = try device.makeLibrary(source: Self.shaderSource, options: nil)
        } catch {
            Self.logger.error("Metal background renderer shader compilation failed: \(error.localizedDescription)")
            return nil
        }

        guard let vertexFunction = library.makeFunction(name: "forsettiMetalBackgroundVertex") else {
            Self.logger.error("Metal background renderer failed to locate vertex function.")
            return nil
        }

        guard let fragmentFunction = library.makeFunction(name: "forsettiMetalBackgroundFragment") else {
            Self.logger.error("Metal background renderer failed to locate fragment function.")
            return nil
        }

        // Configure the render pipeline descriptor with alpha blending enabled
        // so the gradient composites over whatever is behind it
        let descriptor = MTLRenderPipelineDescriptor()
        descriptor.vertexFunction = vertexFunction
        descriptor.fragmentFunction = fragmentFunction
        descriptor.colorAttachments[0].pixelFormat = .bgra8Unorm
        descriptor.colorAttachments[0].isBlendingEnabled = true
        descriptor.colorAttachments[0].rgbBlendOperation = .add
        descriptor.colorAttachments[0].alphaBlendOperation = .add
        descriptor.colorAttachments[0].sourceRGBBlendFactor = .sourceAlpha
        descriptor.colorAttachments[0].destinationRGBBlendFactor = .oneMinusSourceAlpha
        descriptor.colorAttachments[0].sourceAlphaBlendFactor = .one
        descriptor.colorAttachments[0].destinationAlphaBlendFactor = .oneMinusSourceAlpha

        do {
            self.pipelineState = try device.makeRenderPipelineState(descriptor: descriptor)
        } catch {
            Self.logger.error("Metal background renderer pipeline state creation failed: \(error.localizedDescription)")
            return nil
        }

        self.commandQueue = commandQueue
        super.init()
    }

    /// Embedded Metal Shading Language source compiled at runtime.
    ///
    /// The vertex function generates a fullscreen triangle from three hardcoded
    /// vertices (the "oversized triangle" trick -- only one draw call needed).
    /// The fragment function produces an animated multi-wave color blend with
    /// blue, aqua, and green tones plus a soft vignette.
    private static let shaderSource = """
    #include <metal_stdlib>
    using namespace metal;

    struct ForsettiMetalUniforms {
        float2 resolution;
        float time;
        float padding;
    };

    struct ForsettiMetalVertexOutput {
        float4 position [[position]];
        float2 uv;
    };

    vertex ForsettiMetalVertexOutput forsettiMetalBackgroundVertex(uint vertexID [[vertex_id]]) {
        const float2 positions[3] = {
            float2(-1.0, -1.0),
            float2( 3.0, -1.0),
            float2(-1.0,  3.0)
        };

        ForsettiMetalVertexOutput output;
        output.position = float4(positions[vertexID], 0.0, 1.0);
        output.uv = positions[vertexID] * 0.5 + 0.5;
        return output;
    }

    fragment float4 forsettiMetalBackgroundFragment(
        ForsettiMetalVertexOutput input [[stage_in]],
        constant ForsettiMetalUniforms& uniforms [[buffer(0)]]
    ) {
        float2 uv = input.uv;
        float aspect = uniforms.resolution.x / max(uniforms.resolution.y, 1.0);
        float2 p = (uv - 0.5) * float2(aspect, 1.0);

        float t = uniforms.time * 0.17;
        float waveA = sin((p.x * 2.4 + p.y * 1.7) * 3.0 + t);
        float waveB = cos((p.x * 1.5 - p.y * 2.2) * 4.1 - t * 1.3);

        float2 orbitCenter = float2(0.16 * sin(t * 0.9), -0.12 * cos(t * 0.7));
        float bloom = sin(length(p - orbitCenter) * 8.2 - t * 2.0);

        float mixValue = waveA * 0.48 + waveB * 0.34 + bloom * 0.18;
        mixValue = smoothstep(-0.9, 0.9, mixValue);

        float3 blue = float3(0.06, 0.28, 0.58);
        float3 aqua = float3(0.08, 0.52, 0.66);
        float3 green = float3(0.16, 0.54, 0.38);

        float3 color = mix(blue, aqua, mixValue);
        color = mix(color, green, 0.24 + 0.20 * sin(t + p.x * 2.2 - p.y * 1.0));

        float vignette = smoothstep(1.30, 0.18, length(p));
        float alpha = 0.25 * vignette;

        return float4(color * (0.78 + 0.22 * vignette), alpha);
    }
    """

    /// Called when the drawable size changes (e.g., device rotation).
    /// No action needed -- resolution is passed via uniforms each frame.
    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {
        _ = size
    }

    /// Called every frame to encode and submit the render pass.
    ///
    /// This method grabs the current drawable, builds a uniform buffer with the
    /// latest resolution and elapsed time, draws one fullscreen triangle, and
    /// presents the result.
    func draw(in view: MTKView) {
        guard let descriptor = view.currentRenderPassDescriptor,
              let drawable = view.currentDrawable,
              let commandBuffer = commandQueue.makeCommandBuffer(),
              let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: descriptor) else {
            return
        }

        encoder.setRenderPipelineState(pipelineState)

        // Pack current resolution and elapsed time into the uniform struct
        var uniforms = ForsettiMetalUniforms(
            resolution: SIMD2<Float>(
                Float(max(view.drawableSize.width, 1)),
                Float(max(view.drawableSize.height, 1))
            ),
            time: Float(CACurrentMediaTime() - startTime)
        )
        encoder.setFragmentBytes(&uniforms, length: MemoryLayout<ForsettiMetalUniforms>.stride, index: 0)

        // Draw a single fullscreen triangle (3 vertices, no vertex buffer needed)
        encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
        encoder.endEncoding()

        commandBuffer.present(drawable)
        commandBuffer.commit()
    }
}


/// Coordinator that owns both the `MTKView` and its renderer, keeping their
/// lifetimes tied together and configuring the view's display properties.
private final class ForsettiMetalBackgroundCoordinator {
    /// The Metal renderer driving the animation (nil if GPU init failed).
    let renderer: ForsettiMetalBackgroundRenderer?
    /// The Metal-backed view that displays the rendered content.
    let view: MTKView

    /// Creates the coordinator, initialising the Metal device, renderer, and view.
    /// If Metal is unavailable the view is created in a paused/blank state.
    init() {
        guard let device = MTLCreateSystemDefaultDevice(),
              let renderer = ForsettiMetalBackgroundRenderer(device: device) else {
            self.renderer = nil
            self.view = MTKView(frame: .zero, device: nil)
            self.view.isPaused = true
            return
        }

        self.renderer = renderer
        self.view = MTKView(frame: .zero, device: device)
        self.view.delegate = renderer
        self.view.clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 0)
        self.view.colorPixelFormat = .bgra8Unorm
        self.view.framebufferOnly = true
        self.view.preferredFramesPerSecond = 30  // 30 fps is sufficient for a subtle backdrop
        self.view.enableSetNeedsDisplay = false
        self.view.isPaused = false
#if canImport(UIKit)
        self.view.isOpaque = false
        self.view.backgroundColor = .clear
#elseif canImport(AppKit)
        self.view.wantsLayer = true
        self.view.layer?.backgroundColor = NSColor.clear.cgColor
#endif
    }
}

#if canImport(UIKit)
/// A `UIViewRepresentable` wrapper that bridges the Metal `MTKView` into SwiftUI on iOS.
private struct ForsettiMetalBackgroundRepresentable: UIViewRepresentable {
    /// Creates the coordinator that owns the Metal view and renderer.
    func makeCoordinator() -> ForsettiMetalBackgroundCoordinator {
        ForsettiMetalBackgroundCoordinator()
    }

    /// Returns the pre-configured `MTKView` from the coordinator.
    func makeUIView(context: Context) -> MTKView {
        context.coordinator.view
    }

    /// No dynamic updates needed -- the renderer drives itself via `MTKViewDelegate`.
    func updateUIView(_ uiView: MTKView, context: Context) {
        _ = context
        _ = uiView
    }
}
#elseif canImport(AppKit)
/// An `NSViewRepresentable` wrapper that bridges the Metal `MTKView` into SwiftUI on macOS.
private struct ForsettiMetalBackgroundRepresentable: NSViewRepresentable {
    /// Creates the coordinator that owns the Metal view and renderer.
    func makeCoordinator() -> ForsettiMetalBackgroundCoordinator {
        ForsettiMetalBackgroundCoordinator()
    }

    /// Returns the pre-configured `MTKView` from the coordinator.
    func makeNSView(context: Context) -> MTKView {
        context.coordinator.view
    }

    /// No dynamic updates needed -- the renderer drives itself via `MTKViewDelegate`.
    func updateNSView(_ nsView: MTKView, context: Context) {
        _ = context
        _ = nsView
    }
}
#endif
#endif

//endofline
