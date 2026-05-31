import SwiftUI
#if canImport(MetalKit)
import MetalKit
#endif

/// Visual indicator of the MDM command lifecycle. The live animation uses
/// Metal. `CommandStatusFallbackView` is reserved only for machines where
/// Metal or shader compilation is unavailable.
///
/// The view reads from a `CommandLifecyclePhase` value owned by the
/// `SupportTechnicianViewModel`. It is intentionally fixed-height so the
/// surrounding layout doesn't jump when the indicator toggles between
/// idle (transparent) and active states.
struct CommandStatusIndicatorView: View {
    /// The current lifecycle phase. The view re-renders on change.
    let phase: CommandLifecyclePhase

    /// Optional caption shown beneath the bar. Auto-derived from `phase`
    /// when `nil`, so callers can override only when they want to.
    let caption: String?

    init(phase: CommandLifecyclePhase, caption: String? = nil) {
        self.phase = phase
        self.caption = caption
    }

    var body: some View {
        // Thin single-row indicator stretched across the top of the
        // detail pane. The pre-redesign layout used a three-row card
        // (header / 56pt 3-node visual / caption) that consumed ~130pt
        // of vertical real estate even at rest — every detail-pane
        // session paid that cost whether or not a command was in
        // flight. The slim layout puts everything on one row:
        //
        //   [ status icon ]  Sending scheduleOSUpdate…       [Sending] ▓▓▓▓░░░░
        //
        // ~36pt total card height. The Metal-rendered 3-node visual
        // (`CommandStatusMetalRepresentable`) and the SwiftUI
        // `CommandStatusFallbackView` are retained as files but no
        // longer rendered — re-introduce by routing `commandVisual`
        // back into the layout if a "full" mode comes back. The Metal
        // renderer's shader is unchanged.
        HStack(spacing: 10) {
            Image(systemName: headerIconName)
                .font(.footnote.weight(.semibold))
                .foregroundStyle(accentColor)
                .frame(width: 16)

            // Single-line phase text — uses the auto-derived caption so
            // the bar reads naturally for every phase ("Sending …",
            // "Verifying … (attempt 3)", "Confirmed", "Failed. <reason>",
            // etc.). Caller-supplied caption overrides via the `caption`
            // init parameter.
            Text(resolvedCaption ?? "MDM Command Status — ready")
                .font(.footnote)
                .foregroundStyle(captionForeground)
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityLabel(accessibilityLabel)

            if let phaseLabel {
                Text(phaseLabel)
                    .font(.caption2.weight(.semibold))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(accentColor.opacity(0.18))
                    .clipShape(Capsule())
                    .foregroundStyle(accentColor)
            }

            // Thin progress visual on the right edge. Indeterminate
            // spinner while in-flight, fixed accent dot in terminal /
            // idle states. Fixed width so the leading text gets the
            // remaining row space.
            slimProgressVisual
                .frame(width: 28, height: 14)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity)
        .background(ForsettiTheme.surface)
        .clipShape(RoundedRectangle(cornerRadius: ForsettiTheme.Radius.card))
        .overlay(
            RoundedRectangle(cornerRadius: ForsettiTheme.Radius.card)
                .stroke(accentColor.opacity(0.4), lineWidth: 1)
        )
        .animation(.easeInOut(duration: 0.25), value: phase)
    }

    /// Right-aligned thin progress visual. Indeterminate spinner during
    /// in-flight phases; small filled dot in terminal/idle states.
    @ViewBuilder
    private var slimProgressVisual: some View {
        switch phase {
        case .sending, .queued, .verifying:
            ProgressView()
                .controlSize(.mini)
                .tint(accentColor)
        case .succeeded, .failed, .timedOut:
            Image(systemName: terminalGlyph)
                .font(.footnote.weight(.semibold))
                .foregroundStyle(accentColor)
        case .idle:
            Circle()
                .fill(accentColor.opacity(0.35))
                .frame(width: 6, height: 6)
        }
    }

    /// Terminal-state glyph in the right-edge slot. Matches the header
    /// icon's semantics but rendered in the progress slot instead of
    /// the leading position.
    private var terminalGlyph: String {
        switch phase {
        case .succeeded: return "checkmark.circle.fill"
        case .failed:    return "xmark.octagon.fill"
        case .timedOut:  return "clock.badge.exclamationmark.fill"
        default:         return "circle.fill"
        }
    }

    private var accentColor: Color {
        switch phase {
        case .idle:
            return Color.gray
        case .sending, .queued:
            return ForsettiColors.bluePrimary
        case .verifying:
            return .orange
        case .succeeded:
            return ForsettiColors.greenPrimary
        case .failed:
            return .red
        case .timedOut:
            return .orange
        }
    }

    private var headerIconName: String {
        switch phase {
        case .idle:        return "wave.3.right"
        case .sending:     return "paperplane.fill"
        case .queued:      return "clock.fill"
        case .verifying:   return "arrow.triangle.2.circlepath"
        case .succeeded:   return "checkmark.seal.fill"
        case .failed:      return "exclamationmark.octagon.fill"
        case .timedOut:    return "exclamationmark.triangle.fill"
        }
    }

    private var phaseLabel: String? {
        switch phase {
        case .idle:        return "Ready"
        case .sending:     return "Sending"
        case .queued:      return "Queued"
        case .verifying:   return "Verifying"
        case .succeeded:   return "Confirmed"
        case .failed:      return "Failed"
        case .timedOut:    return "Timed Out"
        }
    }

    private var resolvedCaption: String? {
        if let caption {
            return caption
        }
        return Self.defaultCaption(for: phase)
    }

    private var captionForeground: Color {
        switch phase {
        case .succeeded:
            return ForsettiColors.greenPrimary
        case .failed:
            return .red
        case .timedOut:
            return .orange
        default:
            return .secondary
        }
    }

    private var accessibilityLabel: Text {
        Text(Self.defaultCaption(for: phase) ?? "Command status idle")
    }

    static func defaultCaption(for phase: CommandLifecyclePhase) -> String? {
        switch phase {
        case .idle:
            return "Command status — ready. Dispatched MDM commands appear here."
        case let .sending(action, _):
            return "Sending \(action.title)…"
        case let .queued(action, _):
            return "\(action.title) queued. Awaiting device check-in…"
        case let .verifying(action, _, attempt):
            return "Verifying \(action.title) on device (attempt \(attempt))…"
        case let .succeeded(action, _):
            return "\(action.title) confirmed on device."
        case let .failed(action, errorDescription):
            return "\(action.title) failed. \(errorDescription)"
        case let .timedOut(action):
            return "\(action.title) didn't verify within 10 minutes. Check Jamf Pro manually."
        }
    }

    /// Map lifecycle phase → Metal phaseFlag + accent color.
    static func renderPayload(for phase: CommandLifecyclePhase) -> (phase: CommandStatusPhaseFlag, accent: SIMD3<Float>) {
        switch phase {
        case .idle:
            return (.idle, SIMD3<Float>(0.45, 0.50, 0.60))
        case .sending:
            return (.inFlight, SIMD3<Float>(0.22, 0.55, 0.95))
        case .queued:
            return (.queued, SIMD3<Float>(0.22, 0.55, 0.95))
        case .verifying:
            return (.verifying, SIMD3<Float>(0.95, 0.72, 0.18))
        case .succeeded:
            return (.succeeded, SIMD3<Float>(0.18, 0.72, 0.40))
        case .failed:
            return (.failed, SIMD3<Float>(0.92, 0.30, 0.30))
        case .timedOut:
            return (.timedOut, SIMD3<Float>(0.96, 0.62, 0.18))
        }
    }
}

#if canImport(MetalKit)

/// Cross-platform representable hosting an `MTKView` driven by
/// `CommandStatusRenderer`. Keeps the renderer alive for the view's
/// lifetime via the coordinator and pushes phase updates through
/// `update(view:coordinator:)`.
private struct CommandStatusMetalRepresentable {
    let phase: CommandLifecyclePhase

    final class Coordinator {
        var renderer: CommandStatusRenderer?
    }

    func makeCoordinator() -> Coordinator {
        let coordinator = Coordinator()
        let payload = CommandStatusIndicatorView.renderPayload(for: phase)
        coordinator.renderer = CommandStatusRenderer(
            initialPhase: payload.phase,
            initialProgress: Float(phase.progress),
            initialAccent: payload.accent
        )
        return coordinator
    }

    func configure(view: MTKView, coordinator: Coordinator) {
        view.device = CommandStatusRenderer.sharedDevice
        view.delegate = coordinator.renderer
        view.colorPixelFormat = .bgra8Unorm
        view.framebufferOnly = true
        view.clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 0)
        view.preferredFramesPerSecond = 60
        // Continuous animation — the shader animates the pulse on the GPU
        // every frame so we leave the view running even when phase is
        // stable. Idle phase still draws (returning fully transparent
        // pixels), which is cheap and keeps the view alive for the next
        // command.
        view.isPaused = false
        view.enableSetNeedsDisplay = false

#if canImport(UIKit)
        view.isOpaque = false
        view.backgroundColor = .clear
#elseif canImport(AppKit)
        view.wantsLayer = true
        view.layer?.backgroundColor = NSColor.clear.cgColor
#endif
    }

    func update(view: MTKView, coordinator: Coordinator) {
        let payload = CommandStatusIndicatorView.renderPayload(for: phase)
        coordinator.renderer?.update(
            phase: payload.phase,
            progress: Float(phase.progress),
            accent: payload.accent
        )
    }
}

#if canImport(UIKit)
extension CommandStatusMetalRepresentable: UIViewRepresentable {
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
extension CommandStatusMetalRepresentable: NSViewRepresentable {
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
