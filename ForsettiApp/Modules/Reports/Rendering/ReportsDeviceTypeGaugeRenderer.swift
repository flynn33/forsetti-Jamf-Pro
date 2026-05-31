import Foundation
#if canImport(MetalKit)
import MetalKit
import QuartzCore
import os

private struct ReportsGaugeUniforms {
    var resolution: SIMD2<Float>
    var segmentCount: UInt32
    var time: Float
    var tubeWidth: Float
    var padding: Float
}

private struct ReportsGaugeSegmentUniform {
    var startAngle: Float
    var endAngle: Float
    var padding: SIMD2<Float> = .zero
    var color: SIMD4<Float>
}

final class ReportsDeviceTypeGaugeRenderer: NSObject, MTKViewDelegate {
    static let maxSegments = 8

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
            guard let vertex = library.makeFunction(name: "reportsGaugeVertex"),
                  let fragment = library.makeFunction(name: "reportsGaugeFragment")
            else {
                let message = "Reports gauge shader functions were not found."
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
            logger.error("Reports gauge pipeline failed: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }()

    nonisolated(unsafe) static var lastInitError: String?
    private static let logger = Logger(subsystem: ForsettiAppIdentity.bundleIdentifier, category: "ReportsDeviceTypeGaugeRenderer")

    private let stateLock = NSLock()
    private var segmentUniforms: [ReportsGaugeSegmentUniform]
    private let startTime = CACurrentMediaTime()

    init?(segments: [ReportGaugeSegment]) {
        guard Self.sharedDevice != nil,
              Self.sharedCommandQueue != nil,
              Self.sharedPipelineState != nil
        else {
            return nil
        }
        self.segmentUniforms = Self.makeUniforms(from: segments)
        super.init()
    }

    func setSegments(_ segments: [ReportGaugeSegment]) {
        stateLock.lock()
        segmentUniforms = Self.makeUniforms(from: segments)
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
        let localSegments = segmentUniforms
        stateLock.unlock()

        var uniforms = ReportsGaugeUniforms(
            resolution: SIMD2<Float>(
                Float(max(view.drawableSize.width, 1)),
                Float(max(view.drawableSize.height, 1))
            ),
            segmentCount: UInt32(localSegments.count),
            time: Float(CACurrentMediaTime() - startTime),
            tubeWidth: 0.17,
            padding: 0
        )

        var paddedSegments = localSegments
        while paddedSegments.count < Self.maxSegments {
            paddedSegments.append(ReportsGaugeSegmentUniform(startAngle: 0, endAngle: 0, color: .zero))
        }

        encoder.setRenderPipelineState(pipeline)
        encoder.setFragmentBytes(&uniforms, length: MemoryLayout<ReportsGaugeUniforms>.stride, index: 0)
        paddedSegments.withUnsafeBytes { buffer in
            if let baseAddress = buffer.baseAddress {
                encoder.setFragmentBytes(baseAddress, length: buffer.count, index: 1)
            }
        }
        encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
        encoder.endEncoding()
        commandBuffer.present(drawable)
        commandBuffer.commit()
    }

    private static func makeUniforms(from segments: [ReportGaugeSegment]) -> [ReportsGaugeSegmentUniform] {
        Array(segments.prefix(maxSegments)).map { segment in
            let components = segment.colorRGBA.floatComponents
            return ReportsGaugeSegmentUniform(
                startAngle: Float(segment.startAngle),
                endAngle: Float(segment.endAngle),
                color: SIMD4<Float>(components[0], components[1], components[2], components[3])
            )
        }
    }

    private static let shaderSource = """
    #include <metal_stdlib>
    using namespace metal;

    struct ReportsGaugeUniforms {
        float2 resolution;
        uint segmentCount;
        float time;
        float tubeWidth;
        float padding;
    };

    struct ReportsGaugeSegment {
        float startAngle;
        float endAngle;
        float2 padding;
        float4 color;
    };

    struct VertexOut {
        float4 position [[position]];
        float2 uv;
    };

    vertex VertexOut reportsGaugeVertex(uint vertexID [[vertex_id]]) {
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

    fragment float4 reportsGaugeFragment(
        VertexOut input [[stage_in]],
        constant ReportsGaugeUniforms& uniforms [[buffer(0)]],
        constant ReportsGaugeSegment* segments [[buffer(1)]]
    ) {
        float2 p = input.uv * 2.0 - 1.0;
        // Flip Y so atan2 matches SwiftUI Path's Y-down angle convention,
        // keeping segment orientation identical to the Canvas fallback.
        p.y = -p.y;
        p.x *= uniforms.resolution.x / max(uniforms.resolution.y, 1.0);
        float radius = length(p);
        float ringRadius = 0.62;
        float halfTube = uniforms.tubeWidth * 0.5;
        float distanceToTube = abs(radius - ringRadius) - halfTube;
        float edge = fwidth(distanceToTube);
        float alpha = 1.0 - smoothstep(-edge, edge, distanceToTube);
        if (alpha <= 0.0) {
            return float4(0.0);
        }

        float angle = atan2(p.y, p.x);
        if (angle < -1.57079632679) {
            angle += 6.28318530718;
        }

        float4 track = float4(0.58, 0.62, 0.68, 0.24);
        float4 color = track;
        float gap = 0.014;
        for (uint i = 0; i < uniforms.segmentCount; i++) {
            float start = segments[i].startAngle + gap;
            float end = segments[i].endAngle - gap;
            if (angle >= start && angle <= end) {
                float highlight = smoothstep(ringRadius - halfTube, ringRadius, radius) * 0.13;
                color = segments[i].color + float4(highlight, highlight, highlight, 0.0);
            }
        }

        return float4(color.rgb, color.a * alpha);
    }
    """
}
#endif
