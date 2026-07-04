import SwiftUI
#if canImport(MetalKit)
import MetalKit
#endif

struct ReportsDeviceTypeGaugeView: View {
    let aggregate: ReportAggregate

    var body: some View {
        ZStack {
#if canImport(MetalKit)
            if ReportsDeviceTypeGaugeRenderer.sharedDevice != nil,
               ReportsDeviceTypeGaugeRenderer.sharedPipelineState != nil
            {
                ReportsDeviceTypeGaugeMetalRepresentable(segments: aggregate.gaugeSegments)
            } else {
                ReportsDeviceTypeGaugeFallbackView(segments: aggregate.gaugeSegments)
            }
#else
            ReportsDeviceTypeGaugeFallbackView(segments: aggregate.gaugeSegments)
#endif

            VStack(spacing: 3) {
                Text(aggregate.totalCount.formatted())
                    .font(.system(.largeTitle, design: .rounded).weight(.bold))
                    .monospacedDigit()
                Text("Total")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            .minimumScaleFactor(0.72)
        }
        .aspectRatio(1, contentMode: .fit)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilitySummary)
    }

    private var accessibilitySummary: Text {
        let segmentText = aggregate.gaugeSegments.map(\.accessibilityText).joined(separator: ", ")
        return Text("Reports gauge. Total devices \(aggregate.totalCount). \(segmentText)")
    }
}

#if canImport(MetalKit)
private struct ReportsDeviceTypeGaugeMetalRepresentable {
    let segments: [ReportGaugeSegment]

    final class Coordinator {
        var renderer: ReportsDeviceTypeGaugeRenderer?
    }

    func makeCoordinator() -> Coordinator {
        let coordinator = Coordinator()
        coordinator.renderer = ReportsDeviceTypeGaugeRenderer(segments: segments)
        return coordinator
    }

    func configure(view: MTKView, coordinator: Coordinator) {
        view.device = ReportsDeviceTypeGaugeRenderer.sharedDevice
        view.delegate = coordinator.renderer
        view.colorPixelFormat = .bgra8Unorm
        view.framebufferOnly = true
        view.clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 0)
        view.preferredFramesPerSecond = 30
        view.isPaused = true
        view.enableSetNeedsDisplay = true

#if canImport(UIKit)
        view.isOpaque = false
        view.backgroundColor = .clear
#elseif canImport(AppKit)
        view.wantsLayer = true
        view.layer?.backgroundColor = NSColor.clear.cgColor
#endif
    }

    func update(view: MTKView, coordinator: Coordinator) {
        coordinator.renderer?.setSegments(segments)
#if canImport(UIKit)
        view.setNeedsDisplay()
#elseif canImport(AppKit)
        view.needsDisplay = true
#endif
    }
}

#if canImport(UIKit)
extension ReportsDeviceTypeGaugeMetalRepresentable: UIViewRepresentable {
    func makeUIView(context: Context) -> MTKView {
        let view = MTKView()
        configure(view: view, coordinator: context.coordinator)
        return view
    }

    func updateUIView(_ uiView: MTKView, context: Context) {
        update(view: uiView, coordinator: context.coordinator)
    }

    static func dismantleUIView(_ uiView: MTKView, coordinator: Coordinator) {
        uiView.delegate = nil
        coordinator.renderer = nil
    }
}
#elseif canImport(AppKit)
extension ReportsDeviceTypeGaugeMetalRepresentable: NSViewRepresentable {
    func makeNSView(context: Context) -> MTKView {
        let view = MTKView()
        configure(view: view, coordinator: context.coordinator)
        return view
    }

    func updateNSView(_ nsView: MTKView, context: Context) {
        update(view: nsView, coordinator: context.coordinator)
    }

    static func dismantleNSView(_ nsView: MTKView, coordinator: Coordinator) {
        nsView.delegate = nil
        coordinator.renderer = nil
    }
}
#endif
#endif
