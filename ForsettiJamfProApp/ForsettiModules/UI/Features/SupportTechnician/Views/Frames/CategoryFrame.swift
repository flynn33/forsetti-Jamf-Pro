import SwiftUI

/// Reusable container card for each category in the redesigned Support
/// Technician detail view.
///
/// Renders a titled, icon-led card with a bounded body that scrolls
/// internally. Callers stack multiple frames inside an outer `ScrollView`
/// so the page scrolls between frames AND each frame scrolls its own
/// contents (per the spec: "All frames inside the main view must be
/// scrollable").
struct CategoryFrame<Content: View, Footer: View>: View {
    /// SF Symbol shown next to the title.
    let iconSystemName: String

    /// Resolved frame title.
    let title: String

    /// Optional subtitle shown beneath the title — useful for counts
    /// (e.g. "12 attributes") or short scope hints.
    let subtitle: String?

    /// Frame content — typically rows of `SupportFieldRow` values or a
    /// specialized layout (gauges, EA list, etc).
    @ViewBuilder let content: () -> Content

    /// Optional footer slot. Frames use this to host the management
    /// action buttons whose `primaryCategory` matches this frame.
    @ViewBuilder let footer: () -> Footer

    /// Bounded body height. The inner ScrollView allows long content to
    /// scroll without expanding the parent layout.
    var bodyMaxHeight: CGFloat = 320

    /// Frames default open, but every frame can collapse so technicians can
    /// quickly reduce noise while they work through a device.
    @State private var isExpanded = true

    /// Category-driven frame (Support Technician detail view). Icon, title, and
    /// ordering are taken from the `SupportDeviceCategory`.
    init(
        category: SupportDeviceCategory,
        titleOverride: String? = nil,
        subtitle: String? = nil,
        bodyMaxHeight: CGFloat = 320,
        @ViewBuilder content: @escaping () -> Content,
        @ViewBuilder footer: @escaping () -> Footer = { EmptyView() }
    ) {
        self.init(
            iconSystemName: category.iconSystemName,
            title: titleOverride ?? category.displayName,
            subtitle: subtitle,
            bodyMaxHeight: bodyMaxHeight,
            content: content,
            footer: footer
        )
    }

    /// Title + icon frame for callers that don't have a `SupportDeviceCategory`
    /// (e.g. Computer Search, whose inventory sections aren't technician
    /// categories). Same chrome, just an explicit symbol and title.
    init(
        iconSystemName: String,
        title: String,
        subtitle: String? = nil,
        bodyMaxHeight: CGFloat = 320,
        @ViewBuilder content: @escaping () -> Content,
        @ViewBuilder footer: @escaping () -> Footer = { EmptyView() }
    ) {
        self.iconSystemName = iconSystemName
        self.title = title
        self.subtitle = subtitle
        self.bodyMaxHeight = bodyMaxHeight
        self.content = content
        self.footer = footer
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Sticky header strip
            Button {
                withAnimation(.easeInOut(duration: 0.18)) {
                    isExpanded.toggle()
                }
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: iconSystemName)
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(DashboardColors.accentCyan)
                        .frame(width: 28, height: 28)
                        .background(RoundedRectangle(cornerRadius: DashboardTheme.Radius.small, style: .continuous).fill(DashboardColors.accentCyan.opacity(0.12)))

                    VStack(alignment: .leading, spacing: 1) {
                        Text(title)
                            .font(DashboardTheme.Typography.cardTitle)
                            .foregroundStyle(DashboardColors.textPrimary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.82)
                        if let subtitle, subtitle.isEmpty == false {
                            Text(subtitle)
                                .font(.caption)
                                .foregroundStyle(DashboardColors.textTertiary)
                                .lineLimit(2)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    Spacer(minLength: 0)

                    Image(systemName: "chevron.down")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(DashboardColors.textTertiary)
                        .rotationEffect(.degrees(isExpanded ? 0 : -90))
                        .frame(width: 24, height: 24)
                }
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(
                LinearGradient(
                    colors: [
                        DashboardColors.accentCyan.opacity(0.12),
                        DashboardColors.accentBlue.opacity(0.05),
                        DashboardColors.backgroundDepth.opacity(0.18)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .overlay(alignment: .bottom) {
                Rectangle()
                    .fill(DashboardColors.accentCyan.opacity(0.16))
                    .frame(height: 1)
            }

            if isExpanded {
                // Independently scrollable body
                ScrollView(.vertical, showsIndicators: true) {
                    VStack(alignment: .leading, spacing: DashboardTheme.Spacing.compact) {
                        content()
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxHeight: bodyMaxHeight)

                // Footer slot — typically command buttons relevant to this category
                footer()
            }
        }
        .background(frameShape.fill(DashboardColors.backgroundPanelGlass.opacity(DashboardTheme.Opacity.glassFill)))
        .clipShape(frameShape)
        .overlay(
            frameShape
                .stroke(
                    LinearGradient(
                        colors: [
                            DashboardColors.accentCyan.opacity(0.38),
                            DashboardColors.accentBlue.opacity(0.22),
                            DashboardColors.separator.opacity(0.24)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1
                )
        )
        .shadow(color: DashboardColors.accentCyan.opacity(0.10), radius: 16, x: 0, y: 8)
        .shadow(color: DashboardColors.backgroundVignette.opacity(0.34), radius: 24, x: 0, y: 14)
    }

    private var frameShape: RoundedRectangle {
        RoundedRectangle(cornerRadius: DashboardTheme.Radius.card, style: .continuous)
    }
}

/// A small card displaying a hardware spec (CPU, RAM) with an icon, label,
/// and the spec value text. Used inside the General frame as the
/// SwiftUI-only counterpart to the Metal storage gauge.
///
/// Static data only — Jamf inventory doesn't expose live CPU% or RAM
/// usage, so there's no gauge fill to animate. The "card" form keeps the
/// General frame visually balanced with the storage gauge next to it.
struct HardwareSpecCard: View {
    let iconSystemName: String
    let label: String
    let primaryValue: String
    let secondaryValue: String?

    init(iconSystemName: String, label: String, primaryValue: String, secondaryValue: String? = nil) {
        self.iconSystemName = iconSystemName
        self.label = label
        self.primaryValue = primaryValue
        self.secondaryValue = secondaryValue
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Image(systemName: iconSystemName)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(DashboardColors.bluePrimary)
                    .frame(width: 22)
                Text(label)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer(minLength: 0)
            }

            Text(primaryValue)
                .font(.title3.weight(.semibold))
                .foregroundStyle(.primary)
                .lineLimit(2)
                .minimumScaleFactor(0.80)
                .multilineTextAlignment(.leading)

            if let secondaryValue, secondaryValue.isEmpty == false {
                Text(secondaryValue)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
            }

            Spacer(minLength: 0)
        }
        .padding(12)
        .frame(maxWidth: .infinity, minHeight: DashboardTheme.Layout.supportTileHeight, maxHeight: DashboardTheme.Layout.supportTileHeight, alignment: .topLeading)
        .background(DashboardTheme.groupedSurface)
        .clipShape(RoundedRectangle(cornerRadius: DashboardTheme.Radius.button))
        .overlay(
            RoundedRectangle(cornerRadius: DashboardTheme.Radius.button)
                .stroke(DashboardTheme.border, lineWidth: 1)
        )
    }

    /// Convenience initialiser for the "Unavailable" state when Jamf
    /// inventory doesn't include a usable value for the given metric.
    /// The card layout is preserved so the General frame stays visually
    /// stable across devices, regardless of which fields are present.
    static func unavailable(iconSystemName: String, label: String) -> HardwareSpecCard {
        HardwareSpecCard(
            iconSystemName: iconSystemName,
            label: label,
            primaryValue: "Unavailable",
            secondaryValue: "Not reported by Jamf inventory."
        )
    }
}

/// Reusable two-column key-value row for category-frame contents. Keeps
/// the value selectable for copy/paste workflows.
struct CategoryFieldRow: View {
    let label: String
    let value: String

    var body: some View {
        let displayValue = value.isEmpty ? "—" : value
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .top, spacing: 12) {
                fieldLabel
                    .frame(width: 150, alignment: .leading)

                fieldValue(displayValue)
            }

            VStack(alignment: .leading, spacing: 4) {
                fieldLabel
                fieldValue(displayValue)
            }
        }
        .padding(.vertical, 2)
    }

    private var fieldLabel: some View {
        Text(label)
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(.secondary)
            .lineLimit(2)
            .minimumScaleFactor(0.84)
            .fixedSize(horizontal: false, vertical: true)
    }

    @ViewBuilder
    private func fieldValue(_ displayValue: String) -> some View {
        if let binaryState = FieldBinaryState(value: displayValue) {
            FieldBinaryIndicator(state: binaryState)
                .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            Text(displayValue)
                .font(.body)
                .textSelection(.enabled)
                .lineLimit(3)
                .truncationMode(.middle)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

private struct FieldBinaryState: Hashable {
    let isOn: Bool
    let label: String

    init?(value: String) {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.isEmpty == false else { return nil }

        let normalized = trimmed
            .lowercased()
            .replacingOccurrences(of: "[_\\-]+", with: " ", options: .regularExpression)
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        let positiveValues: Set<String> = [
            "true", "yes", "enabled", "active", "on", "compliant",
            "capable", "present", "valid", "escrowed", "success",
            "successful", "allowed", "connected", "approved",
            "user approved", "managed", "supervised", "available",
            "reported", "installed", "complete", "completed", "ok",
            "online", "pass", "passed", "verified", "secure"
        ]
        let negativeValues: Set<String> = [
            "false", "no", "disabled", "inactive", "off", "not compliant",
            "not capable", "absent", "not present", "invalid",
            "not escrowed", "failed", "failure", "blocked",
            "disconnected", "not detected", "no ip reported",
            "unapproved", "not approved", "not user approved",
            "unmanaged", "unsupervised", "unavailable", "not reported",
            "not installed", "incomplete", "offline", "fail", "not verified",
            "insecure", "none"
        ]

        if positiveValues.contains(normalized) {
            self.isOn = true
            self.label = Self.readableLabel(for: normalized, fallback: trimmed)
            return
        }
        if negativeValues.contains(normalized) {
            self.isOn = false
            self.label = Self.readableLabel(for: normalized, fallback: trimmed)
            return
        }
        return nil
    }

    private static func readableLabel(for normalized: String, fallback: String) -> String {
        switch normalized {
        case "true": return "Yes"
        case "false": return "No"
        case "not compliant": return "Not compliant"
        case "not capable": return "Not capable"
        case "not present": return "Not present"
        case "not escrowed": return "Not escrowed"
        case "not detected": return "Not detected"
        case "no ip reported": return "No IP reported"
        default:
            return fallback
                .replacingOccurrences(of: "_", with: " ")
                .split(separator: " ")
                .map { word in
                    let lower = word.lowercased()
                    return lower.prefix(1).uppercased() + lower.dropFirst()
                }
                .joined(separator: " ")
        }
    }
}

private struct FieldBinaryIndicator: View {
    let state: FieldBinaryState

    var body: some View {
        HStack(spacing: 10) {
            Circle()
                .fill(tint)
                .frame(width: 12, height: 12)
                .overlay(
                    Circle()
                        .stroke(tint.opacity(0.30), lineWidth: 4)
                )

            Text(state.label)
                .font(.subheadline.weight(.semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.85)
                .truncationMode(.tail)

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(DashboardTheme.groupedSurface)
        .foregroundStyle(.primary)
        .clipShape(RoundedRectangle(cornerRadius: DashboardTheme.Radius.button))
        .overlay(
            RoundedRectangle(cornerRadius: DashboardTheme.Radius.button)
                .stroke(tint.opacity(0.35), lineWidth: 1)
        )
        .accessibilityElement(children: .combine)
    }

    private var tint: Color {
        state.isOn ? DashboardColors.greenPrimary : Color.gray.opacity(0.82)
    }
}

//endofline
