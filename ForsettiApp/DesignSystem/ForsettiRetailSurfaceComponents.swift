import SwiftUI

/// Reusable dark-glass retail card for Forsetti workspace surfaces.
struct ForsettiGlassCard<Content: View>: View {
    enum Style {
        case elevated
        case dense
    }

    private let style: Style
    private let active: Bool
    private let content: Content

    init(style: Style = .elevated, active: Bool = false, @ViewBuilder content: () -> Content) {
        self.style = style
        self.active = active
        self.content = content()
    }

    var body: some View {
        content
            .padding(padding)
            .forsettiCardSurface(
                fill: cardFill,
                border: borderColor,
                shadow: shadowColor,
                shadowRadius: shadowRadius,
                shadowY: shadowY
            )
    }

    private var cardFill: Color {
        ForsettiTheme.groupedSurface.opacity(active ? 0.94 : 0.86)
    }

    private var borderColor: Color {
        active ? ForsettiColors.bluePrimary.opacity(0.78) : ForsettiTheme.border
    }

    private var shadowColor: Color {
        guard style == .elevated else { return .clear }
        return active ? ForsettiColors.bluePrimary.opacity(0.18) : ForsettiTheme.shadowColor
    }

    private var padding: CGFloat {
        switch style {
        case .elevated:
            return ForsettiTheme.Spacing.item + ForsettiTheme.Spacing.compact
        case .dense:
            return ForsettiTheme.Spacing.item
        }
    }

    private var shadowRadius: CGFloat {
        guard style == .elevated else { return 0 }
        return active ? 18 : 10
    }

    private var shadowY: CGFloat {
        guard style == .elevated else { return 0 }
        return active ? 10 : 5
    }
}

/// Compact semantic status chip used by retail workspaces, tables, and inspectors.
struct ForsettiStatusBadge: View {
    enum Kind: String, CaseIterable, Hashable {
        case connected
        case reachable
        case trusted
        case compliant
        case ready
        case pending
        case stale
        case warning
        case blocked
        case failed
        case succeeded
        case queued
        case verifying
        case unsupported
        case permissionDenied

        var displayName: String {
            switch self {
            case .connected: return "Connected"
            case .reachable: return "Reachable"
            case .trusted: return "Trusted"
            case .compliant: return "Compliant"
            case .ready: return "Ready"
            case .pending: return "Pending"
            case .stale: return "Stale"
            case .warning: return "Warning"
            case .blocked: return "Blocked"
            case .failed: return "Failed"
            case .succeeded: return "Succeeded"
            case .queued: return "Queued"
            case .verifying: return "Verifying"
            case .unsupported: return "Unsupported"
            case .permissionDenied: return "Permission denied"
            }
        }

        var symbolName: String {
            switch self {
            case .connected, .reachable, .trusted, .compliant, .ready, .succeeded:
                return "checkmark.circle.fill"
            case .pending, .queued:
                return "clock.fill"
            case .stale, .warning:
                return "exclamationmark.triangle.fill"
            case .blocked:
                return "nosign"
            case .failed:
                return "xmark.octagon.fill"
            case .verifying:
                return "arrow.triangle.2.circlepath"
            case .unsupported:
                return "minus.circle.fill"
            case .permissionDenied:
                return "lock.shield.fill"
            }
        }

        var color: Color {
            switch self {
            case .connected, .reachable, .trusted, .compliant, .ready, .succeeded:
                return ForsettiColors.greenPrimary
            case .pending, .queued, .verifying:
                return ForsettiColors.bluePrimary
            case .stale, .warning, .permissionDenied:
                return .orange
            case .blocked, .failed:
                return .red
            case .unsupported:
                return .secondary
            }
        }
    }

    let kind: Kind
    let text: String?

    init(_ kind: Kind, text: String? = nil) {
        self.kind = kind
        self.text = text
    }

    var body: some View {
        Label(text ?? kind.displayName, systemImage: kind.symbolName)
            .font(.caption.weight(.semibold))
            .lineLimit(1)
            .padding(.horizontal, 9)
            .padding(.vertical, 5)
            .foregroundStyle(kind.color)
            .background(kind.color.opacity(0.14), in: Capsule())
            .overlay {
                Capsule().strokeBorder(kind.color.opacity(0.36), lineWidth: 1)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(accessibilityText)
    }

    var accessibilityText: String { text ?? kind.displayName }
}
