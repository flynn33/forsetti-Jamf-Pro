import SwiftUI
#if canImport(MetalKit)
import MetalKit
#endif

// MARK: - KPI ring selector
//
// The public KPI ring view chooses the Metal renderer when the platform and
// device support it, then falls back to a pure SwiftUI ring if Metal is
// unavailable. This keeps Dashboard KPIs visible on every supported platform.
struct DeploymentKPIRingView: View {
    let projection: DeploymentKPIProjection

    var body: some View {
        ZStack {
#if canImport(MetalKit)
            // The renderer exposes shared initialization state. If the device or
            // pipeline could not be created, fallback rendering keeps the UI
            // functional instead of showing an empty KPI.
            if DeploymentKPIRingRenderer.sharedDevice != nil,
               DeploymentKPIRingRenderer.sharedPipelineState != nil {
                DeploymentKPIRingMetalRepresentable(projection: projection)
            } else {
                DeploymentKPIRingFallbackView(projection: projection)
            }
#else
            DeploymentKPIRingFallbackView(projection: projection)
#endif

            VStack(spacing: 2) {
                Text(projection.value.formatted())
                    .font(.system(.title2, design: .rounded).weight(.bold))
                    .monospacedDigit()
                if projection.total > 0 {
                    Text("\(Int((projection.fraction * 100).rounded()))%")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
            }
            .minimumScaleFactor(0.72)
        }
        .aspectRatio(1, contentMode: .fit)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(projection.accessibilitySummary))
    }
}

#if canImport(MetalKit)
private struct DeploymentKPIRingMetalRepresentable {
    let projection: DeploymentKPIProjection

    final class Coordinator {
        var renderer: DeploymentKPIRingRenderer?
    }

    func makeCoordinator() -> Coordinator {
        let coordinator = Coordinator()
        coordinator.renderer = DeploymentKPIRingRenderer(projection: projection)
        return coordinator
    }

    func configure(view: MTKView, coordinator: Coordinator) {
        view.device = DeploymentKPIRingRenderer.sharedDevice
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
        coordinator.renderer?.setProjection(projection)
#if canImport(UIKit)
        view.setNeedsDisplay()
#elseif canImport(AppKit)
        view.needsDisplay = true
#endif
    }
}

#if canImport(UIKit)
extension DeploymentKPIRingMetalRepresentable: UIViewRepresentable {
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
extension DeploymentKPIRingMetalRepresentable: NSViewRepresentable {
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
