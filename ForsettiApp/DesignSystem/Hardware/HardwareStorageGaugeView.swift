import SwiftUI
#if canImport(MetalKit)
import MetalKit
#endif

// "Klatu-barada-Nikto"

/// SwiftUI view that renders the storage usage gauge.
///
/// On Metal-capable hardware this hosts an `MTKView` driven by
/// `HardwareStorageRenderer`. When Metal is unavailable (or shader
/// initialization fails) it falls back to `HardwareStorageFallbackBar`.
/// The numeric labels (total/free) are the caller's responsibility — this
/// view renders only the bar so it can be sized freely by its parent.
///
/// Lifecycle:
/// - `.inline` style runs paused (`isPaused = true`, `enableSetNeedsDisplay = true`)
///   so it only redraws when its `usedFraction` changes. A 100-row search list
///   therefore costs near zero idle GPU.
/// - `.detail` style runs at 30 fps for the full liquid + flowing-light effect.
struct HardwareStorageGaugeView: View {
    /// Fill ratio in 0...1. Values outside the range are clamped on the GPU.
    let usedFraction: Double

    /// Visual presentation mode. Drives both render cadence and shader effects.
    let style: HardwareStorageGaugeStyle

    init(usedFraction: Double, style: HardwareStorageGaugeStyle = .inline) {
        self.usedFraction = usedFraction
        self.style = style
    }

    var body: some View {
#if canImport(MetalKit)
        if HardwareStorageRenderer.sharedDevice != nil,
           HardwareStorageRenderer.sharedPipelineState != nil
        {
            HardwareStorageMetalRepresentable(
                usedFraction: usedFraction,
                style: style
            )
            .accessibilityLabel(accessibilityLabel)
        } else {
            HardwareStorageFallbackBar(
                usedFraction: usedFraction,
                style: style
            )
            .accessibilityLabel(accessibilityLabel)
        }
#else
        HardwareStorageFallbackBar(
            usedFraction: usedFraction,
            style: style
        )
        .accessibilityLabel(accessibilityLabel)
#endif
    }

    /// Reads the percentage as plain text for VoiceOver — the bar is purely
    /// visual otherwise.
    private var accessibilityLabel: Text {
        let percent = Int((max(0, min(1, usedFraction)) * 100).rounded())
        return Text("Storage \(percent) percent used")
    }
}

#if canImport(MetalKit)

/// Cross-platform representable for the Metal storage gauge.
///
/// Keeps the renderer alive for the view's lifetime via the coordinator and
/// pushes new fill values into the renderer through the value-change path so
/// the inline (paused) style still animates one ease-in step on data update.
private struct HardwareStorageMetalRepresentable {
    let usedFraction: Double
    let style: HardwareStorageGaugeStyle

    final class Coordinator {
        var renderer: HardwareStorageRenderer?
    }

    func makeCoordinator() -> Coordinator {
        let coordinator = Coordinator()
        coordinator.renderer = HardwareStorageRenderer(
            style: style,
            initialFraction: Float(usedFraction)
        )
        return coordinator
    }

    /// Configures an `MTKView` for this gauge style. Pulled into a helper so
    /// both `UIViewRepresentable` and `NSViewRepresentable` paths share the
    /// configuration without copy-paste drift.
    func configure(view: MTKView, coordinator: Coordinator) {
        view.device = HardwareStorageRenderer.sharedDevice
        view.delegate = coordinator.renderer
        view.colorPixelFormat = .bgra8Unorm
        view.framebufferOnly = true
        view.clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 0)

        switch style {
        case .inline:
            view.preferredFramesPerSecond = 30
            view.isPaused = true
            view.enableSetNeedsDisplay = true
        case .detail:
            view.preferredFramesPerSecond = 30
            view.isPaused = false
            view.enableSetNeedsDisplay = false
        }

#if canImport(UIKit)
        view.isOpaque = false
        view.backgroundColor = .clear
#elseif canImport(AppKit)
        view.wantsLayer = true
        view.layer?.backgroundColor = NSColor.clear.cgColor
#endif
    }

    /// Pushes a value change through to the renderer and triggers a one-shot
    /// redraw in inline mode (where the view is paused).
    func update(view: MTKView, coordinator: Coordinator) {
        coordinator.renderer?.setUsedFraction(Float(usedFraction))

        if style == .inline {
#if canImport(UIKit)
            view.setNeedsDisplay()
#elseif canImport(AppKit)
            view.needsDisplay = true
#endif
        }
    }
}

#if canImport(UIKit)
extension HardwareStorageMetalRepresentable: UIViewRepresentable {
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
extension HardwareStorageMetalRepresentable: NSViewRepresentable {
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

//endofline
