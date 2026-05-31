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
        active
            ? ForsettiColors.backgroundPanelGlass.opacity(0.84)
            : ForsettiTheme.glassSurface
    }

    private var borderColor: Color {
        active ? ForsettiTheme.strongBorder : ForsettiTheme.border
    }

    private var shadowColor: Color {
        guard style == .elevated else { return .clear }
        return active ? ForsettiColors.accentCyan.opacity(0.30) : ForsettiTheme.shadowColor
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
                return ForsettiColors.success
            case .pending, .queued, .verifying:
                return ForsettiColors.accentCyan
            case .stale, .warning, .permissionDenied:
                return ForsettiColors.warning
            case .blocked, .failed:
                return ForsettiColors.critical
            case .unsupported:
                return ForsettiColors.offline
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

/// Compact diagnostics drawer used by retail workspaces for framework and tenant health.
struct ForsettiDiagnosticsDrawer: View {
    struct Item: Identifiable, Hashable {
        let id = UUID()
        let title: String
        let value: String
        let kind: ForsettiStatusBadge.Kind

        var accessibilityText: String {
            "\(title), \(value)"
        }
    }

    let title: String
    let items: [Item]

    init(title: String = "Diagnostics", items: [Item]) {
        self.title = title
        self.items = items
    }

    var body: some View {
        ForsettiGlassCard(style: .dense) {
            VStack(alignment: .leading, spacing: ForsettiTheme.Spacing.item) {
                HStack(spacing: ForsettiTheme.Spacing.compact) {
                    Image(systemName: "waveform.path.ecg.rectangle")
                        .foregroundStyle(ForsettiColors.accentCyan)
                    Text(title)
                        .font(.system(.headline, design: .rounded).weight(.semibold))
                        .foregroundStyle(ForsettiColors.textPrimary)
                    Spacer(minLength: 0)
                }

                ForEach(items) { item in
                    HStack(alignment: .firstTextBaseline, spacing: ForsettiTheme.Spacing.item) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(item.title)
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(ForsettiColors.textSecondary)
                            Text(item.value)
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(ForsettiColors.textPrimary)
                                .lineLimit(1)
                                .truncationMode(.middle)
                        }
                        Spacer(minLength: ForsettiTheme.Spacing.item)
                        ForsettiStatusBadge(item.kind)
                    }
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(item.accessibilityText)
                }
            }
        }
    }
}
