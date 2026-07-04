import Foundation
#if canImport(MetalKit)
import MetalKit
import os

// MARK: - Metal KPI ring renderer
//
// Metal rendering gives the Dashboard rings a smooth animated visual while
// keeping projection values in Swift. The renderer receives only resolution,
// fraction, time, and semantic color from SwiftUI.
private struct DeploymentKPIRingUniforms {
    var resolution: SIMD2<Float>
    var fraction: Float
    var time: Float
    var color: SIMD4<Float>
}

final class DeploymentKPIRingRenderer: NSObject, MTKViewDelegate {
    // Device, command queue, and pipeline are shared so each ring view does not
    // rebuild Metal state independently.
    static let sharedDevice: MTLDevice? = MTLCreateSystemDefaultDevice()

    static let sharedCommandQueue: MTLCommandQueue? = {
        sharedDevice?.makeCommandQueue()
    }()

    static let sharedPipelineState: MTLRenderPipelineState? = {
        guard let device = sharedDevice else {
            lastInitError = "MTLCreateSystemDefaultDevice() returned nil"
            return nil
        }

        do {
            let library = try device.makeLibrary(source: shaderSource, options: nil)
            guard let vertex = library.makeFunction(name: "deploymentKPIRingVertex"),
                  let fragment = library.makeFunction(name: "deploymentKPIRingFragment")
            else {
                let message = "Deployment KPI ring shader functions were not found."
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
            lastInitError = error.localizedDescription
            logger.error("Deployment KPI ring pipeline failed: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }()

    nonisolated(unsafe) static var lastInitError: String?
    private static let logger = Logger(subsystem: "com.jamfdashboard.app", category: "DeploymentKPIRingRenderer")

    private let stateLock = NSLock()
    private var fraction: Float
    private var color: SIMD4<Float>

    init?(projection: DeploymentKPIProjection) {
        guard Self.sharedDevice != nil,
              Self.sharedCommandQueue != nil,
              Self.sharedPipelineState != nil
        else {
            return nil
        }
        self.fraction = Float(projection.fraction)
        let components = projection.color.floatComponents
        self.color = SIMD4<Float>(components[0], components[1], components[2], components[3])
        super.init()
    }

    func setProjection(_ projection: DeploymentKPIProjection) {
        let components = projection.color.floatComponents
        stateLock.lock()
        fraction = Float(projection.fraction)
        color = SIMD4<Float>(components[0], components[1], components[2], components[3])
        stateLock.unlock()
    }

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

        stateLock.lock()
        let localFraction = fraction
        let localColor = color
        stateLock.unlock()

        var uniforms = DeploymentKPIRingUniforms(
            resolution: SIMD2<Float>(
                Float(max(view.drawableSize.width, 1)),
                Float(max(view.drawableSize.height, 1))
            ),
            fraction: localFraction,
            time: 0,
            color: localColor
        )

        encoder.setRenderPipelineState(pipeline)
        encoder.setFragmentBytes(&uniforms, length: MemoryLayout<DeploymentKPIRingUniforms>.stride, index: 0)
        encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
        encoder.endEncoding()
        commandBuffer.present(drawable)
        commandBuffer.commit()
    }

    private static let shaderSource = """
    #include <metal_stdlib>
    using namespace metal;

    struct DeploymentKPIRingUniforms {
        float2 resolution;
        float fraction;
        float time;
        float4 color;
    };

    struct VertexOut {
        float4 position [[position]];
        float2 uv;
    };

    vertex VertexOut deploymentKPIRingVertex(uint vertexID [[vertex_id]]) {
        const float2 positions[3] = {
            float2(-1.0, -1.0),
            float2( 3.0, -1.0),
            float2(-1.0,  3.0)
        };
        VertexOut out;
        out.position = float4(positions[vertexID], 0.0, 1.0);
        out.uv = positions[vertexID] * 0.5 + 0.5;
        return out;
    }

    fragment float4 deploymentKPIRingFragment(
        VertexOut input [[stage_in]],
        constant DeploymentKPIRingUniforms& uniforms [[buffer(0)]]
    ) {
        float2 p = input.uv * 2.0 - 1.0;
        p.x *= uniforms.resolution.x / max(uniforms.resolution.y, 1.0);
        float radius = length(p);
        float ringRadius = 0.64;
        float halfTube = 0.075;
        float distanceToTube = abs(radius - ringRadius) - halfTube;
        float edge = fwidth(distanceToTube);
        float alpha = 1.0 - smoothstep(-edge, edge, distanceToTube);
        if (alpha <= 0.0) {
            return float4(0.0);
        }

        float angle = atan2(p.y, p.x) + 1.57079632679;
        if (angle < 0.0) {
            angle += 6.28318530718;
        }
        float progress = clamp(uniforms.fraction, 0.0, 1.0) * 6.28318530718;
        float4 track = float4(0.58, 0.62, 0.68, 0.22);
        float4 color = angle <= progress ? uniforms.color : track;
        return float4(color.rgb, color.a * alpha);
    }
    """
}
#endif
