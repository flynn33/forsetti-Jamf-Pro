import SwiftUI

/// Generic activity state for the retail command bar.
enum ForsettiCommandActivityState: Equatable {
    case idle(lastUpdated: Date?)
    case preparing(label: String, progress: Double?)
    case querying(label: String, progress: Double?)
    case sendingCommand(label: String, progress: Double?)
    case waitingForTenant(label: String)
    case waitingForDevice(label: String)
    case waitingForJamf(label: String)
    case pollingStatus(label: String, progress: Double?)
    case validating(label: String, progress: Double?)
    case rendering(label: String, progress: Double?)
    case exporting(label: String, progress: Double?)
    case completed(label: String, completedAt: Date)
    case failed(label: String, message: String, retryAvailable: Bool)
    case permissionDenied(label: String, requiredPrivilege: String?)
    case blocked(label: String, reason: String)
    case cancelled(label: String)
}

extension ForsettiCommandActivityState {
    var lastUpdated: Date? {
        switch self {
        case let .idle(lastUpdated):
            return lastUpdated
        default:
            return nil
        }
    }

    var retryAvailable: Bool {
        switch self {
        case let .failed(_, _, retryAvailable):
            return retryAvailable
        default:
            return false
        }
    }

    var requiredPrivilege: String? {
        switch self {
        case let .permissionDenied(_, requiredPrivilege):
            return requiredPrivilege
        default:
            return nil
        }
    }

    var summaryText: String {
        switch self {
        case .idle:
            return "Ready"
        case let .preparing(label, _),
             let .querying(label, _),
             let .sendingCommand(label, _),
             let .waitingForTenant(label),
             let .waitingForDevice(label),
             let .waitingForJamf(label),
             let .pollingStatus(label, _),
             let .validating(label, _),
             let .rendering(label, _),
             let .exporting(label, _),
             let .completed(label, _),
             let .cancelled(label):
            return label
        case let .failed(label, message, _):
            return "\(label): \(message)"
        case let .permissionDenied(label, _):
            return "\(label): Permission denied"
        case let .blocked(label, reason):
            return "\(label): \(reason)"
        }
    }

    var progress: Double? {
        let value: Double?
        switch self {
        case let .preparing(_, progress),
             let .querying(_, progress),
             let .sendingCommand(_, progress),
             let .pollingStatus(_, progress),
             let .validating(_, progress),
             let .rendering(_, progress),
             let .exporting(_, progress):
            value = progress
        case .completed:
            value = 1.0
        default:
            value = nil
        }

        guard let value else { return nil }
        return min(max(value, 0), 1)
    }

    var tint: Color {
        switch self {
        case .idle:
            return ForsettiColors.accentCyanSoft
        case .preparing, .querying, .sendingCommand, .waitingForTenant, .waitingForDevice, .waitingForJamf, .pollingStatus, .validating, .rendering, .exporting:
            return ForsettiColors.accentCyan
        case .completed:
            return ForsettiColors.success
        case .failed, .blocked:
            return ForsettiColors.critical
        case .permissionDenied, .cancelled:
            return ForsettiColors.warning
        }
    }

    var symbolName: String {
        switch self {
        case .idle:
            return "shield.lefthalf.filled"
        case .preparing:
            return "slider.horizontal.3"
        case .querying:
            return "waveform.path.ecg"
        case .sendingCommand:
            return "paperplane.fill"
        case .waitingForTenant, .waitingForDevice:
            return "clock.fill"
        case .waitingForJamf:
            return "network"
        case .pollingStatus:
            return "dot.radiowaves.left.and.right"
        case .validating:
            return "checklist"
        case .rendering:
            return "chart.xyaxis.line"
        case .exporting:
            return "square.and.arrow.up"
        case .completed:
            return "checkmark.circle.fill"
        case .failed:
            return "xmark.octagon.fill"
        case .permissionDenied:
            return "lock.shield.fill"
        case .blocked:
            return "exclamationmark.triangle.fill"
        case .cancelled:
            return "xmark.circle.fill"
        }
    }

    var accessibilityLabel: String { summaryText }

    var accessibilityValue: String {
        if let progress {
            return "\(Int((progress * 100).rounded())) percent"
        }

        switch self {
        case .idle:
            return "Idle"
        case .failed:
            return "Failed"
        case .permissionDenied:
            return "Permission denied"
        case .blocked:
            return "Blocked"
        case .cancelled:
            return "Cancelled"
        case .completed:
            return "Completed"
        default:
            return "Active"
        }
    }

    var isActive: Bool {
        switch self {
        case .idle, .completed, .failed, .permissionDenied, .blocked, .cancelled:
            return false
        default:
            return true
        }
    }

    init(commandLifecycle phase: CommandLifecyclePhase) {
        switch phase {
        case .idle:
            self = .idle(lastUpdated: nil)
        case let .sending(action, _):
            self = .sendingCommand(label: action.title, progress: phase.progress)
        case let .queued(action, _):
            self = .waitingForJamf(label: "\(action.title) queued")
        case let .verifying(action, _, _):
            self = .pollingStatus(label: "Verifying \(action.title)", progress: phase.progress)
        case let .succeeded(action, completedAt):
            self = .completed(label: "\(action.title) confirmed", completedAt: completedAt)
        case let .failed(action, errorDescription):
            self = .failed(label: action.title, message: errorDescription, retryAvailable: true)
        case let .timedOut(action):
            self = .blocked(label: action.title, reason: "Verification timed out")
        }
    }
}

/// SwiftUI command activity bar with a stable fallback path.
struct ForsettiCommandActivityBar: View {
    let state: ForsettiCommandActivityState

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(state: ForsettiCommandActivityState) {
        self.state = state
    }

    var body: some View {
        ZStack(alignment: .leading) {
            Capsule()
                .fill(trackBackground)

            if let progress = state.progress {
                GeometryReader { proxy in
                    Capsule()
                        .fill(state.tint.opacity(0.18))
                        .frame(
                            width: max(0, (proxy.size.width - 8) * progress),
                            height: max(0, proxy.size.height - 8)
                        )
                        .padding(4)
                        .allowsHitTesting(false)
                }
            }

            HStack(spacing: ForsettiTheme.Spacing.item) {
                Image(systemName: state.symbolName)
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(state.tint)
                    .frame(width: 24)

                Text(state.summaryText)
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(ForsettiColors.textPrimary)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(maxWidth: .infinity, alignment: .leading)

                if let progress = state.progress {
                    Text("\(Int((progress * 100).rounded()))%")
                        .font(.caption.monospacedDigit().weight(.semibold))
                        .foregroundStyle(state.tint)
                }

                Circle()
                    .fill(state.tint)
                    .frame(width: 8, height: 8)
                    .shadow(color: state.tint.opacity(reduceMotion ? 0.12 : 0.45), radius: reduceMotion ? 2 : 8)
            }
            .padding(.horizontal, ForsettiTheme.Spacing.section)
        }
        .frame(height: ForsettiTheme.Layout.commandActivityBarHeight)
        .clipShape(Capsule())
        .overlay {
            Capsule()
                .strokeBorder(state.tint.opacity(state.isActive ? 0.72 : 0.30), lineWidth: state.isActive ? 1.4 : 1)
        }
        .shadow(color: state.tint.opacity(reduceMotion ? 0.08 : (state.isActive ? 0.24 : 0.10)), radius: reduceMotion ? 4 : 16)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(state.accessibilityLabel)
        .accessibilityValue(state.accessibilityValue)
    }

    private var trackBackground: LinearGradient {
        LinearGradient(
            colors: [
                ForsettiColors.toolbar.opacity(0.92),
                ForsettiColors.backgroundPanelGlass.opacity(0.78),
                state.tint.opacity(0.14)
            ],
            startPoint: .leading,
            endPoint: .trailing
        )
    }
}
