import SwiftUI

// Premium design kit for the Permissions Helper module.
//
// A small set of reusable components built on the app's DashboardTheme / DashboardColors tokens
// so every surface in the module reads as one cohesive, premium dashboard rather
// than default-styled SwiftUI controls. Cross-platform (macOS + iOS/iPadOS).
//
// The whole module is pinned to a dark color scheme (see PermissionsMatrixView), so
// these surfaces are tuned for dark and stay consistent with the dark diagram canvas.

enum PHMetrics {
    static let cardRadius: CGFloat = 16     // top-level cards
    static let innerRadius: CGFloat = 12    // cards nested inside a card
    static let rowRadius: CGFloat = 11      // list rows
    static let chipRadius: CGFloat = 9
    static let cardPadding: CGFloat = 16
    static let gap: CGFloat = 14
}

// MARK: - Touch targets

extension View {
    /// Guarantees a >= 44pt hit area on touch platforms while preserving macOS density.
    @ViewBuilder
    func phTouchTarget() -> some View {
#if os(iOS)
        self.frame(minWidth: 44, minHeight: 44).contentShape(Rectangle())
#else
        self.contentShape(Rectangle())
#endif
    }
}

// MARK: - Card surfaces

private struct PHCardSurface: ViewModifier {
    var padding: CGFloat
    var radius: CGFloat
    func body(content: Content) -> some View {
        content
            .padding(padding)
            .background(RoundedRectangle(cornerRadius: radius, style: .continuous).fill(.regularMaterial))
            .overlay(RoundedRectangle(cornerRadius: radius, style: .continuous).strokeBorder(DashboardTheme.border, lineWidth: 1))
            .shadow(color: DashboardTheme.shadowColor, radius: 8, x: 0, y: 3)
    }
}

private struct PHInnerCardSurface: ViewModifier {
    var padding: CGFloat
    func body(content: Content) -> some View {
        content
            .padding(padding)
            .background(RoundedRectangle(cornerRadius: PHMetrics.innerRadius, style: .continuous).fill(Color.primary.opacity(0.05)))
            .overlay(RoundedRectangle(cornerRadius: PHMetrics.innerRadius, style: .continuous).strokeBorder(DashboardTheme.border, lineWidth: 1))
    }
}

extension View {
    /// A premium elevated card (material fill + border + shadow) — for top-level groups.
    func phCard(padding: CGFloat = PHMetrics.cardPadding, radius: CGFloat = PHMetrics.cardRadius) -> some View {
        modifier(PHCardSurface(padding: padding, radius: radius))
    }
    /// A flat inner card (subtle fill + border, no shadow) — for cards nested inside a card.
    func phInnerCard(padding: CGFloat = 12) -> some View {
        modifier(PHInnerCardSurface(padding: padding))
    }
}

// MARK: - Section card (titled)

/// A titled premium card: an icon + title header above arbitrary content.
struct PHSectionCard<Content: View>: View {
    let title: String
    let systemImage: String
    var accent: Color = DashboardColors.bluePrimary
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: systemImage)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(accent)
                Text(title).font(.headline)
                Spacer(minLength: 0)
            }
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .phCard()
    }
}

// MARK: - Stat tile (metadata)

/// A premium metric tile: large value + uppercased label + tinted icon badge.
struct PHStatTile: View {
    let title: String
    let value: String
    var systemImage: String
    var tint: Color = DashboardColors.bluePrimary

    @ScaledMetric(relativeTo: .title3) private var badge: CGFloat = 32

    var body: some View {
        HStack(spacing: 10) {
            RoundedRectangle(cornerRadius: PHMetrics.chipRadius, style: .continuous)
                .fill(tint.opacity(0.16))
                .overlay(Image(systemName: systemImage).font(.caption.weight(.bold)).foregroundStyle(tint))
                .frame(width: badge, height: badge)
            VStack(alignment: .leading, spacing: 0) {
                Text(value).font(.title3.weight(.bold).monospacedDigit()).foregroundStyle(.primary)
                Text(title.uppercased())
                    .font(.caption2.weight(.semibold)).tracking(0.6).foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background(RoundedRectangle(cornerRadius: 13, style: .continuous).fill(.regularMaterial))
        .overlay(RoundedRectangle(cornerRadius: 13, style: .continuous).strokeBorder(tint.opacity(0.22), lineWidth: 1))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title): \(value)")
    }
}

// MARK: - Search field

/// A premium search field: leading magnifier, plain text field, clear button.
struct PHSearchField: View {
    let placeholder: String
    @Binding var text: String
    var accessibilityLabelText: String?

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            TextField(placeholder, text: $text)
                .textFieldStyle(.plain).font(.callout)
            if text.isEmpty == false {
                Button { text = "" } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .phTouchTarget()
                .accessibilityLabel("Clear search")
            }
        }
        .padding(.horizontal, 11)
        .padding(.vertical, 8)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(.regularMaterial))
        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(DashboardTheme.border, lineWidth: 1))
        .accessibilityLabel(accessibilityLabelText ?? placeholder)
    }
}

// MARK: - Status pill

/// A compact status capsule (symbol + label) used for tags, statuses, and badges.
struct PHStatusPill: View {
    let text: String
    var systemImage: String? = nil
    var tint: Color = DashboardColors.bluePrimary

    var body: some View {
        HStack(spacing: 3) {
            if let systemImage { Image(systemName: systemImage).font(.caption2.weight(.bold)) }
            Text(text).font(.caption2.weight(.semibold))
        }
        .foregroundStyle(tint)
        .padding(.horizontal, 7)
        .padding(.vertical, 3)
        .background(Capsule(style: .continuous).fill(tint.opacity(0.16)))
        .overlay(Capsule(style: .continuous).strokeBorder(tint.opacity(0.4), lineWidth: 0.75))
    }
}

// MARK: - Selectable list row

/// A premium, selectable, hover/press-aware list row used in the master lists (no
/// default `List` chrome). Selection highlight + accent rail; announces selection to
/// VoiceOver and supports an optional navigation hint.
struct PHSelectRow<Content: View>: View {
    let isSelected: Bool
    var accessibilityHint: String? = nil
    let action: () -> Void
    @ViewBuilder var content: () -> Content

    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 0) {
                RoundedRectangle(cornerRadius: 2, style: .continuous)
                    .fill(isSelected ? DashboardColors.bluePrimary : .clear)
                    .frame(width: 3)
                content()
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 11)
                    .padding(.vertical, rowVerticalPadding)
            }
        }
        .buttonStyle(.plain)
        .background(RoundedRectangle(cornerRadius: PHMetrics.rowRadius, style: .continuous).fill(rowFill))
        .overlay(
            RoundedRectangle(cornerRadius: PHMetrics.rowRadius, style: .continuous)
                .strokeBorder(isSelected ? DashboardColors.bluePrimary.opacity(0.5) : DashboardTheme.border.opacity(0.7), lineWidth: 1)
        )
        .contentShape(RoundedRectangle(cornerRadius: PHMetrics.rowRadius, style: .continuous))
        .onHover { hovering = $0 }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
        .accessibilityHint(accessibilityHint ?? "")
    }

    private var rowVerticalPadding: CGFloat {
#if os(iOS)
        12
#else
        8
#endif
    }

    private var rowFill: Color {
        if isSelected { return DashboardColors.bluePrimary.opacity(0.16) }
        if hovering { return Color.primary.opacity(0.08) }
        return Color.primary.opacity(0.05)
    }
}

// MARK: - Wrapping flow layout (chip rows / wrapping control bars)

/// A left-to-right flow layout that wraps onto new lines — used for chip rows and the
/// control bar so they never clip or overflow horizontally.
struct FlowLayout: Layout {
    var spacing: CGFloat = 6
    var rowSpacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, rowHeight: CGFloat = 0, widest: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            let w = min(size.width, maxWidth)
            if x > 0, x + w > maxWidth {
                x = 0; y += rowHeight + rowSpacing; rowHeight = 0
            }
            x += w + spacing
            rowHeight = max(rowHeight, size.height)
            widest = max(widest, x - spacing)
        }
        let width = maxWidth.isFinite ? min(maxWidth, widest) : widest
        return CGSize(width: max(width, 0), height: y + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let maxWidth = bounds.width
        var x: CGFloat = 0, y: CGFloat = 0, rowHeight: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            let w = min(size.width, maxWidth)
            if x > 0, x + w > maxWidth {
                x = 0; y += rowHeight + rowSpacing; rowHeight = 0
            }
            subview.place(at: CGPoint(x: bounds.minX + x, y: bounds.minY + y),
                          anchor: .topLeading, proposal: ProposedViewSize(width: w, height: size.height))
            x += w + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}

// MARK: - Toolbar controls (uniform height → aligned)

/// A small bordered icon button for control bars. Uniform with `PHToggleChip`.
struct PHIconButton: View {
    let label: String
    let systemImage: String
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage).frame(width: 16, height: 16)
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
        .phTouchTarget()
        .help(label)
        .accessibilityLabel(label)
    }
}

/// A small toggle rendered as a button chip so it shares the exact height/baseline of
/// `PHIconButton` on every platform (no macOS checkbox / iOS button mismatch).
struct PHToggleChip: View {
    let label: String
    let systemImage: String
    @Binding var isOn: Bool

    var body: some View {
        Toggle(isOn: $isOn) {
            Label(label, systemImage: systemImage)
        }
        .toggleStyle(.button)
        .buttonStyle(.bordered)
        .controlSize(.small)
        .tint(DashboardColors.bluePrimary)
        .phTouchTarget()
        .accessibilityValue(isOn ? "On" : "Off")
    }
}
