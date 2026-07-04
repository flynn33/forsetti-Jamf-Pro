import Foundation
#if canImport(MetalKit)
import MetalKit
import QuartzCore
import os
#endif

/// Numeric phase flag mirrored to the MSL shader. Keep in sync with the
/// `phaseFlag` comparisons inside `shaderSource`.
///
/// 0 = idle (controller dim, device dim, no pulse, fully transparent)
/// 1 = in-flight pre-queue (pulse leaving controller)
/// 2 = queued (pulse parked at ~70% along the line, awaiting verification)
/// 3 = verifying (pulse shimmers between queued position and device)
/// 4 = succeeded (both nodes lit accent, line lit accent)
/// 5 = failed (controller lit, device dim, line accent, no pulse)
/// 6 = timedOut (controller lit, device dim warm, dashed look)
enum CommandStatusPhaseFlag: Float {
    case idle = 0
    case inFlight = 1
    case queued = 2
    case verifying = 3
    case succeeded = 4
    case failed = 5
    case timedOut = 6
}

#if canImport(MetalKit)

/// CPU-side mirror of the MSL `CommandStatusUniforms` struct. Field order
/// and padding must match the shader exactly — Metal does not memcpy
/// through a type system so this is fragile to edits.
private struct CommandStatusUniforms {
    /// Drawable resolution in pixels.
    var resolution: SIMD2<Float>
    /// Animation time in seconds since renderer init.
    var time: Float
    /// One of `CommandStatusPhaseFlag.rawValue`.
    var phaseFlag: Float
    /// Pulse position along the track, 0...1 (controller → device).
    var progress: Float
    /// RGB accent color (blue / green / red / amber etc.) — encodes outcome.
    var accentColor: SIMD3<Float>
    /// Padding so the struct sits on a 16-byte boundary.
    var padding: Float = 0
}

/// `MTKViewDelegate` rendering the command-lifecycle "transmission line"
/// — a controller node on the left, a device node on the right, a track
/// between them, and an animated pulse that advances as the command moves
/// through its lifecycle.
///
/// All instances share one `MTLDevice` / `MTLCommandQueue` /
/// `MTLRenderPipelineState`. Per-instance state is just the latest target
/// progress + the latest target phase + a CACurrentMediaTime() start
/// timestamp.
final class CommandStatusRenderer: NSObject, MTKViewDelegate {

    // MARK: - Shared GPU resources

    static let sharedDevice: MTLDevice? = {
        MTLCreateSystemDefaultDevice()
    }()

    static let sharedCommandQueue: MTLCommandQueue? = {
        guard let device = sharedDevice else { return nil }
        return device.makeCommandQueue()
    }()

    static var isAvailable: Bool {
        sharedDevice != nil && sharedCommandQueue != nil && sharedPipelineState != nil
    }

    static let sharedPipelineState: MTLRenderPipelineState? = {
        guard let device = sharedDevice else {
            lastInitError = "MTLCreateSystemDefaultDevice() returned nil"
            return nil
        }

        do {
            let library = try device.makeLibrary(source: shaderSource, options: nil)
            guard let vertex = library.makeFunction(name: "commandStatusVertex"),
                  let fragment = library.makeFunction(name: "commandStatusFragment")
            else {
                let message = "Shader functions commandStatusVertex/Fragment not found"
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

    nonisolated(unsafe) static var lastInitError: String?
    private static let logger = Logger(subsystem: "com.forsetti.jamfpro", category: "CommandStatusRenderer")

    // MARK: - Per-instance state

    private var targetPhase: Float
    private var targetProgress: Float
    private var currentProgress: Float
    private var targetAccent: SIMD3<Float>
    private var currentAccent: SIMD3<Float>
    private let stateLock = NSLock()
    private let startTime = CACurrentMediaTime()

    init?(initialPhase: CommandStatusPhaseFlag, initialProgress: Float, initialAccent: SIMD3<Float>) {
        guard Self.sharedDevice != nil,
              Self.sharedCommandQueue != nil,
              Self.sharedPipelineState != nil
        else {
            return nil
        }

        self.targetPhase = initialPhase.rawValue
        self.targetProgress = max(0, min(1, initialProgress))
        self.currentProgress = self.targetProgress
        self.targetAccent = initialAccent
        self.currentAccent = initialAccent
        super.init()
    }

    /// Pushes new phase / progress / accent values. The renderer eases the
    /// progress and accent toward these on the next draw so transitions
    /// don't look like a hard cut.
    func update(phase: CommandStatusPhaseFlag, progress: Float, accent: SIMD3<Float>) {
        let clamped = max(0, min(1, progress))
        stateLock.lock()
        targetPhase = phase.rawValue
        targetProgress = clamped
        targetAccent = accent
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

        // Ease toward targets. Same lerp pattern as HardwareStorageRenderer
        // for visual consistency — 30 fps × 0.18 ≈ ~300ms to settle a 50%
        // delta, which reads as a smooth animation rather than a hard cut.
        stateLock.lock()
        let phase = targetPhase
        let targetP = targetProgress
        let targetA = targetAccent
        currentProgress += (targetP - currentProgress) * 0.18
        currentAccent.x += (targetA.x - currentAccent.x) * 0.18
        currentAccent.y += (targetA.y - currentAccent.y) * 0.18
        currentAccent.z += (targetA.z - currentAccent.z) * 0.18
        let drawnProgress = currentProgress
        let drawnAccent = currentAccent
        stateLock.unlock()

        encoder.setRenderPipelineState(pipeline)

        var uniforms = CommandStatusUniforms(
            resolution: SIMD2<Float>(
                Float(max(view.drawableSize.width, 1)),
                Float(max(view.drawableSize.height, 1))
            ),
            time: Float(CACurrentMediaTime() - startTime),
            phaseFlag: phase,
            progress: drawnProgress,
            accentColor: drawnAccent
        )
        encoder.setFragmentBytes(&uniforms, length: MemoryLayout<CommandStatusUniforms>.stride, index: 0)

        encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
        encoder.endEncoding()

        commandBuffer.present(drawable)
        commandBuffer.commit()
    }

    // MARK: - Embedded MSL

    /// Fullscreen-triangle vertex + a fragment that paints a three-stage
    /// command path: Technician app -> Jamf Pro -> managed device. The
    /// fragment renders the panel, track, animated packets, glows, and
    /// terminal-state halo entirely on the GPU.
    private static let shaderSource = """
    #include <metal_stdlib>
    using namespace metal;

    struct CommandStatusUniforms {
        float2 resolution;
        float time;
        float phaseFlag;
        float progress;
        float3 accentColor;
        float padding;
    };

    struct CommandStatusVertexOutput {
        float4 position [[position]];
        float2 uv;
    };

    vertex CommandStatusVertexOutput commandStatusVertex(uint vertexID [[vertex_id]]) {
        const float2 positions[3] = {
            float2(-1.0, -1.0),
            float2( 3.0, -1.0),
            float2(-1.0,  3.0)
        };

        CommandStatusVertexOutput output;
        output.position = float4(positions[vertexID], 0.0, 1.0);
        output.uv = positions[vertexID] * 0.5 + 0.5;
        return output;
    }

    float roundedBoxSDF(float2 p, float2 halfSize, float radius) {
        float2 q = abs(p) - halfSize + radius;
        return length(max(q, 0.0)) + min(max(q.x, q.y), 0.0) - radius;
    }

    float circleMask(float2 p, float2 center, float radius, float edge) {
        float d = length(p - center);
        return 1.0 - smoothstep(radius - edge, radius + edge, d);
    }

    float segmentDistance(float2 p, float2 a, float2 b) {
        float2 pa = p - a;
        float2 ba = b - a;
        float h = clamp(dot(pa, ba) / max(dot(ba, ba), 0.0001), 0.0, 1.0);
        return length(pa - ba * h);
    }

    float segmentMask(float2 p, float2 a, float2 b, float radius, float edge) {
        float d = segmentDistance(p, a, b);
        return 1.0 - smoothstep(radius - edge, radius + edge, d);
    }

    float2 pathPoint(float2 a, float2 b, float2 c, float t) {
        t = clamp(t, 0.0, 1.0);
        if (t < 0.5) {
            return mix(a, b, t / 0.5);
        }
        return mix(b, c, (t - 0.5) / 0.5);
    }

    fragment float4 commandStatusFragment(
        CommandStatusVertexOutput input [[stage_in]],
        constant CommandStatusUniforms& u [[buffer(0)]]
    ) {
        float2 uv = input.uv;
        float aspect = u.resolution.x / max(u.resolution.y, 1.0);
        float2 p = (uv - 0.5) * float2(aspect, 1.0);

        float3 base = float3(0.045, 0.055, 0.072);
        float vignette = 1.0 - smoothstep(0.15, 1.35, length((uv - 0.5) * float2(1.25, 1.0)));
        float scan = 0.035 * sin((uv.y * u.resolution.y * 0.65) + u.time * 2.4);
        float3 color = base + u.accentColor * (0.045 + 0.10 * vignette) + scan;
        float alpha = 0.96;

        float panel = 1.0 - smoothstep(-0.008, 0.008, roundedBoxSDF(p, float2(aspect * 0.485, 0.455), 0.13));
        alpha *= panel;

        float x = max(aspect * 0.34, 1.0);
        float2 app = float2(-x, -0.02);
        float2 jamf = float2(0.0, -0.02);
        float2 endpoint = float2(x, -0.02);
        float trackRadius = 0.040;
        float nodeRadius = 0.205;

        float trackA = segmentMask(p, app, jamf, trackRadius, 0.012);
        float trackB = segmentMask(p, jamf, endpoint, trackRadius, 0.012);
        float3 trackBase = float3(0.18, 0.20, 0.25);
        color = mix(color, trackBase, max(trackA, trackB) * 0.88);

        float p1 = clamp(u.progress / 0.45, 0.0, 1.0);
        float p2 = clamp((u.progress - 0.45) / 0.55, 0.0, 1.0);
        float2 appFillEnd = mix(app, jamf, p1);
        float2 jamfFillEnd = mix(jamf, endpoint, p2);
        float fillA = segmentMask(p, app, appFillEnd, trackRadius * 1.08, 0.012) * step(0.01, p1);
        float fillB = segmentMask(p, jamf, jamfFillEnd, trackRadius * 1.08, 0.012) * step(0.01, p2);
        float fill = max(fillA, fillB);
        color = mix(color, mix(u.accentColor * 0.70, float3(1.0), 0.20), fill);

        float3 nodeBase = float3(0.25, 0.28, 0.34);
        float appLit = u.phaseFlag >= 1.0 ? 1.0 : 0.38;
        float jamfLit = u.progress >= 0.42 ? 1.0 : (u.phaseFlag >= 1.0 ? 0.55 : 0.34);
        float deviceLit = u.phaseFlag == 4.0 ? 1.0 : (u.phaseFlag == 3.0 ? 0.72 : (u.phaseFlag >= 5.0 ? 0.55 : 0.32));

        float appHalo = circleMask(p, app, nodeRadius + 0.11 + 0.025 * sin(u.time * 3.0), 0.12) * appLit;
        float jamfHalo = circleMask(p, jamf, nodeRadius + 0.10 + 0.025 * sin(u.time * 3.0 + 1.1), 0.12) * jamfLit;
        float deviceHalo = circleMask(p, endpoint, nodeRadius + 0.13 + 0.030 * sin(u.time * 3.0 + 2.2), 0.13) * deviceLit;
        color += u.accentColor * (appHalo * 0.13 + jamfHalo * 0.15 + deviceHalo * 0.18);

        float appNode = circleMask(p, app, nodeRadius, 0.010);
        float jamfNode = circleMask(p, jamf, nodeRadius, 0.010);
        float deviceNode = circleMask(p, endpoint, nodeRadius, 0.010);
        color = mix(color, mix(nodeBase, u.accentColor, appLit), appNode);
        color = mix(color, mix(nodeBase, u.accentColor, jamfLit), jamfNode);
        color = mix(color, mix(nodeBase, u.accentColor, deviceLit), deviceNode);

        float appCore = circleMask(p, app, nodeRadius * 0.47, 0.010);
        float jamfCore = circleMask(p, jamf, nodeRadius * 0.47, 0.010);
        float deviceCore = circleMask(p, endpoint, nodeRadius * 0.47, 0.010);
        color = mix(color, float3(0.90, 0.94, 1.0), (appCore + jamfCore + deviceCore) * 0.62);

        float packetGate = (u.phaseFlag > 0.5 && u.phaseFlag < 3.5) ? 1.0 : 0.0;
        for (int i = 0; i < 3; i++) {
            float offset = float(i) * 0.31;
            float packetT = fract(u.time * 0.62 + offset);
            if (u.phaseFlag == 2.0) {
                packetT = 0.46 + 0.05 * sin(u.time * 2.2 + float(i));
            } else if (u.phaseFlag == 3.0) {
                packetT = 0.50 + 0.42 * (0.5 + 0.5 * sin(u.time * 1.35 + float(i) * 0.75));
            }
            float2 packet = pathPoint(app, jamf, endpoint, packetT);
            packet.y -= 0.055 * sin(packetT * 6.28318);
            float packetMask = circleMask(p, packet, 0.060, 0.035) * packetGate;
            float packetCore = circleMask(p, packet, 0.027, 0.012) * packetGate;
            color += u.accentColor * packetMask * 0.32;
            color = mix(color, float3(1.0), packetCore);
        }

        if (u.phaseFlag >= 4.0) {
            float terminal = circleMask(p, endpoint, nodeRadius + 0.24 + 0.04 * sin(u.time * 3.4), 0.035);
            color += u.accentColor * terminal * 0.40;
        }

        if (u.phaseFlag == 5.0) {
            float slashA = 1.0 - smoothstep(0.018, 0.032, abs((p.x - endpoint.x) + (p.y - endpoint.y) * 1.8));
            slashA *= circleMask(p, endpoint, nodeRadius + 0.08, 0.02);
            color = mix(color, float3(1.0, 0.20, 0.18), slashA);
        }

        if (u.phaseFlag == 6.0) {
            float dash = step(0.58, fract((p.x + aspect * 0.5) * 8.0 + u.time * 1.4));
            color = mix(color, u.accentColor * 0.85, dash * max(trackA, trackB) * 0.65);
        }

        float border = 1.0 - smoothstep(0.006, 0.020, abs(roundedBoxSDF(p, float2(aspect * 0.485, 0.455), 0.13)));
        color += u.accentColor * border * 0.28;

        if (u.phaseFlag == 0.0) {
            color = mix(color, float3(0.12, 0.13, 0.16), 0.42);
            alpha *= 0.74;
        }

        return float4(saturate(color), alpha);
    }
    """
}

#endif

//endofline
