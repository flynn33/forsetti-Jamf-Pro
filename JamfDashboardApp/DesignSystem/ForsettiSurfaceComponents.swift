import SwiftUI

enum ForsettiPanelPadding {
    case dense
    case standard
    case roomy

    var value: CGFloat {
        switch self {
        case .dense: return DashboardTheme.Spacing.cardPaddingDense
        case .standard: return DashboardTheme.Spacing.cardPaddingStandard
        case .roomy: return DashboardTheme.Spacing.cardPaddingRoomy
        }
    }
}

struct ForsettiGlassPanel<Content: View>: View {
    let padding: ForsettiPanelPadding
    let isActive: Bool
    let statusTint: Color?
    @ViewBuilder let content: Content

    init(
        padding: ForsettiPanelPadding = .standard,
        isActive: Bool = false,
        statusTint: Color? = nil,
        @ViewBuilder content: () -> Content
    ) {
        self.padding = padding
        self.isActive = isActive
        self.statusTint = statusTint
        self.content = content()
    }

    var body: some View {
        content
            .padding(padding.value)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(panelShape.fill(DashboardColors.backgroundPanelGlass.opacity(DashboardTheme.Opacity.glassFill)))
            .overlay(alignment: .top) {
                panelShape
                    .strokeBorder(borderGradient, lineWidth: isActive ? 1.4 : 1)
            }
            .overlay(alignment: .top) {
                panelShape
                    .strokeBorder(DashboardColors.textPrimary.opacity(0.08), lineWidth: 1)
                    .mask(alignment: .top) {
                        Rectangle()
                            .frame(height: 24)
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                    }
            }
            .shadow(color: (statusTint ?? DashboardColors.accentCyan).opacity(isActive ? 0.20 : 0.10), radius: isActive ? 22 : 14, x: 0, y: 8)
            .shadow(color: DashboardColors.backgroundVignette.opacity(0.36), radius: 24, x: 0, y: 16)
    }

    private var panelShape: RoundedRectangle {
        RoundedRectangle(cornerRadius: DashboardTheme.Radius.panel, style: .continuous)
    }

    private var borderGradient: LinearGradient {
        let tint = statusTint ?? DashboardColors.accentCyan
        return LinearGradient(
            colors: [
                tint.opacity(isActive ? 0.72 : 0.38),
                DashboardColors.accentBlue.opacity(0.24),
                DashboardColors.separator.opacity(0.20)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }
}

extension View {
    func forsettiGlassPanel(
        padding: ForsettiPanelPadding = .standard,
        isActive: Bool = false,
        statusTint: Color? = nil
    ) -> some View {
        ForsettiGlassPanel(padding: padding, isActive: isActive, statusTint: statusTint) {
            self
        }
    }
}

enum ForsettiSemanticStatus: String, CaseIterable, Identifiable {
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
    case nonCompliant
    case enrolled
    case supervised
    case active
    case healthy
    case completed
    case inProgress
    case querying
    case sending
    case waiting
    case validating
    case rendering
    case exporting
    case cancelled
    case offline
    case configured
    case workflow
    case exception

    var id: String { rawValue }

    var displayText: String {
        switch self {
        case .permissionDenied: return "Permission Denied"
        case .nonCompliant: return "Non-Compliant"
        case .inProgress: return "In Progress"
        default:
            return rawValue
                .replacingOccurrences(of: "([a-z])([A-Z])", with: "$1 $2", options: .regularExpression)
                .capitalized
        }
    }

    var accessibilityLabel: String {
        "Status: \(displayText)"
    }

    var color: Color {
        DashboardColors.statusColor(named: rawValue)
    }

    var symbolName: String {
        switch self {
        case .connected, .reachable, .trusted, .compliant, .ready, .succeeded, .enrolled, .supervised, .healthy, .completed:
            return "checkmark.seal.fill"
        case .pending, .queued, .waiting:
            return "clock.fill"
        case .stale, .warning:
            return "exclamationmark.triangle.fill"
        case .blocked, .failed, .permissionDenied, .nonCompliant, .exception:
            return "xmark.octagon.fill"
        case .unsupported, .offline, .cancelled:
            return "minus.circle.fill"
        case .verifying, .validating:
            return "arrow.triangle.2.circlepath"
        case .active, .inProgress, .querying, .sending, .rendering, .exporting:
            return "wave.3.right.circle.fill"
        case .configured, .workflow:
            return "slider.horizontal.3"
        }
    }
}

struct ForsettiStatusPill: View {
    let status: ForsettiSemanticStatus
    var text: String?

    var body: some View {
        Label(text ?? status.displayText, systemImage: status.symbolName)
            .font(.system(size: 11, weight: .semibold))
            .lineLimit(1)
            .foregroundStyle(status.color)
            .padding(.horizontal, 9)
            .padding(.vertical, 5)
            .background(Capsule().fill(status.color.opacity(0.14)))
            .overlay(Capsule().stroke(status.color.opacity(0.42), lineWidth: 1))
            .accessibilityLabel(status.accessibilityLabel)
    }
}

struct ForsettiMetricCard: View {
    let title: String
    let value: String
    let subtitle: String
    let systemImage: String?
    var status: ForsettiSemanticStatus = .ready
    var trend: [Double] = []
    var isLoading: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: DashboardTheme.Spacing.md) {
            HStack(alignment: .top, spacing: DashboardTheme.Spacing.md) {
                if let systemImage {
                    Image(systemName: systemImage)
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(status.color)
                        .frame(width: 34, height: 34)
                        .background(RoundedRectangle(cornerRadius: DashboardTheme.Radius.medium, style: .continuous).fill(status.color.opacity(0.14)))
                        .overlay(RoundedRectangle(cornerRadius: DashboardTheme.Radius.medium, style: .continuous).stroke(status.color.opacity(0.36), lineWidth: 1))
                        .accessibilityHidden(true)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text(title.uppercased())
                        .font(DashboardTheme.Typography.caption)
                        .foregroundStyle(DashboardColors.textTertiary)
                    Text(isLoading ? "..." : value)
                        .font(DashboardTheme.Typography.numeric(size: 30))
                        .foregroundStyle(DashboardColors.textPrimary)
                        .monospacedDigit()
                        .lineLimit(1)
                        .minimumScaleFactor(0.72)
                }

                Spacer(minLength: 0)
            }

            HStack(spacing: DashboardTheme.Spacing.sm) {
                ForsettiStatusPill(status: status)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(DashboardColors.textSecondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }

            if trend.isEmpty == false {
                ForsettiSparkline(values: trend, tint: status.color)
                    .frame(height: 30)
                    .accessibilityHidden(true)
            }
        }
        .forsettiGlassPanel(padding: .dense, statusTint: status.color)
    }
}

struct ForsettiKeyValueRow: View {
    let key: String
    let value: String
    var status: ForsettiSemanticStatus?

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: DashboardTheme.Spacing.md) {
            Text(key)
                .font(.caption)
                .foregroundStyle(DashboardColors.textTertiary)
            Spacer(minLength: DashboardTheme.Spacing.md)
            if let status {
                ForsettiStatusPill(status: status, text: value)
            } else {
                Text(value)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(DashboardColors.textPrimary)
                    .multilineTextAlignment(.trailing)
                    .lineLimit(2)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

struct ForsettiInspectorSection<Content: View>: View {
    let title: String
    let systemImage: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: DashboardTheme.Spacing.md) {
            Label(title, systemImage: systemImage)
                .font(DashboardTheme.Typography.cardTitle)
                .foregroundStyle(DashboardColors.textPrimary)
            content
        }
        .forsettiGlassPanel(padding: .dense)
    }
}

struct ForsettiPanelHeader: View {
    let title: String
    let subtitle: String?
    let systemImage: String

    init(title: String, subtitle: String? = nil, systemImage: String) {
        self.title = title
        self.subtitle = subtitle
        self.systemImage = systemImage
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: DashboardTheme.Spacing.sm) {
            Image(systemName: systemImage)
                .font(.caption.weight(.semibold))
                .foregroundStyle(DashboardColors.accentCyan)
                .frame(width: 16)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(DashboardTheme.Typography.cardTitle)
                    .foregroundStyle(DashboardColors.textPrimary)
                if let subtitle, subtitle.isEmpty == false {
                    Text(subtitle)
                        .font(.caption2)
                        .foregroundStyle(DashboardColors.textTertiary)
                        .lineLimit(2)
                }
            }

            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
    }
}

struct ForsettiQuickActionRow: View {
    let title: String
    let subtitle: String?
    let systemImage: String
    let tint: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: DashboardTheme.Spacing.md) {
                Image(systemName: systemImage)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(tint)
                    .frame(width: 28, height: 28)
                    .background(RoundedRectangle(cornerRadius: DashboardTheme.Radius.small, style: .continuous).fill(tint.opacity(0.14)))

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(DashboardColors.textPrimary)
                    if let subtitle {
                        Text(subtitle)
                            .font(.caption2)
                            .foregroundStyle(DashboardColors.textTertiary)
                            .lineLimit(1)
                    }
                }

                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(DashboardColors.textTertiary)
            }
            .padding(.vertical, 6)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(title)
    }
}

struct ForsettiSearchInput: View {
    let placeholder: String
    @Binding var text: String

    var body: some View {
        HStack(spacing: DashboardTheme.Spacing.sm) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(DashboardColors.textTertiary)
                .accessibilityHidden(true)

            TextField(placeholder, text: $text)
                .textFieldStyle(.plain)
                .foregroundStyle(DashboardColors.textPrimary)
                .dashboardNoAutoCorrectionTextInput()
        }
        .padding(.horizontal, DashboardTheme.Spacing.md)
        .frame(minHeight: 38)
        .background(RoundedRectangle(cornerRadius: DashboardTheme.Radius.button, style: .continuous).fill(DashboardColors.backgroundRoot.opacity(0.62)))
        .overlay(RoundedRectangle(cornerRadius: DashboardTheme.Radius.button, style: .continuous).stroke(DashboardColors.accentCyan.opacity(0.28), lineWidth: 1))
        .accessibilityElement(children: .combine)
    }
}

struct ForsettiFilterChip: View {
    let title: String
    var value: String? = nil
    var systemImage: String? = nil
    var tint: Color = DashboardColors.accentCyan

    var body: some View {
        HStack(spacing: DashboardTheme.Spacing.xs) {
            if let systemImage {
                Image(systemName: systemImage)
                    .font(.caption2.weight(.semibold))
                    .accessibilityHidden(true)
            }
            Text(title)
            if let value {
                Text(value)
                    .foregroundStyle(tint)
                    .monospacedDigit()
            }
        }
        .font(.caption.weight(.semibold))
        .foregroundStyle(DashboardColors.textSecondary)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Capsule().fill(DashboardColors.backgroundDepth.opacity(0.52)))
        .overlay(Capsule().stroke(tint.opacity(0.30), lineWidth: 1))
        .accessibilityElement(children: .combine)
    }
}

enum ForsettiCommandStreamState: String, CaseIterable, Identifiable {
    case idle
    case querying
    case sending
    case waiting
    case validating
    case rendering
    case exporting
    case completed
    case failed
    case blocked
    case cancelled
    case permissionDenied

    var id: String { rawValue }

    var status: ForsettiSemanticStatus {
        switch self {
        case .idle: return .ready
        case .querying: return .querying
        case .sending: return .sending
        case .waiting: return .waiting
        case .validating: return .validating
        case .rendering: return .rendering
        case .exporting: return .exporting
        case .completed: return .completed
        case .failed: return .failed
        case .blocked: return .blocked
        case .cancelled: return .cancelled
        case .permissionDenied: return .permissionDenied
        }
    }

    var displayText: String { status.displayText }
}

struct ForsettiCommandStreamBar: View {
    let state: ForsettiCommandStreamState
    let message: String
    var progress: Double?
    var trailingText: String?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: DashboardTheme.Spacing.md) {
            Image(systemName: "shield.lefthalf.filled")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(state.status.color)
                .frame(width: 34, height: 34)
                .background(Circle().fill(state.status.color.opacity(0.16)))

            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(DashboardColors.backgroundRoot.opacity(0.78))
                    Capsule()
                        .fill(state.status.color.opacity(0.16))
                        .frame(width: proxy.size.width * CGFloat(clampedProgress))
                    commandPackets
                        .padding(.horizontal, 12)
                }
            }
            .frame(height: 16)
            .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                Text(message)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(DashboardColors.textPrimary)
                    .lineLimit(1)
                    .truncationMode(.tail)
                Text(state.displayText)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(state.status.color)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            if let trailingText {
                Text(trailingText)
                    .font(.caption.monospacedDigit().weight(.semibold))
                    .foregroundStyle(DashboardColors.textSecondary)
                    .lineLimit(1)
            } else if let progress {
                Text(progress, format: .percent.precision(.fractionLength(0)))
                    .font(.caption.monospacedDigit().weight(.semibold))
                    .foregroundStyle(DashboardColors.textSecondary)
            }
        }
        .padding(.horizontal, DashboardTheme.Spacing.lg)
        .frame(height: DashboardTheme.Layout.commandStreamHeight)
        .background(Capsule().fill(DashboardColors.backgroundPanelGlass.opacity(DashboardTheme.Opacity.toolbarFill)))
        .overlay(Capsule().stroke(state.status.color.opacity(0.44), lineWidth: 1))
        .shadow(color: state.status.color.opacity(0.18), radius: 18, x: 0, y: 8)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Command stream, \(state.displayText), \(message)")
    }

    private var clampedProgress: Double {
        guard let progress else {
            return state == .idle ? 0.08 : 0.52
        }
        return max(0, min(1, progress))
    }

    private var commandPackets: some View {
        HStack(spacing: 8) {
            ForEach(0..<9, id: \.self) { index in
                Capsule()
                    .fill(state.status.color.opacity(packetOpacity(index)))
                    .frame(width: index % 3 == 0 ? 18 : 10, height: 3)
            }
            Spacer(minLength: 0)
        }
    }

    private func packetOpacity(_ index: Int) -> Double {
        if reduceMotion || state == .idle {
            return index.isMultiple(of: 2) ? 0.22 : 0.10
        }
        return 0.18 + Double(index % 4) * 0.10
    }
}

struct ForsettiSparkline: View {
    let values: [Double]
    var tint: Color = DashboardColors.accentCyan

    var body: some View {
        Canvas { context, size in
            guard values.count > 1 else { return }
            let minValue = values.min() ?? 0
            let maxValue = values.max() ?? 1
            let range = max(maxValue - minValue, 0.0001)
            let step = size.width / CGFloat(values.count - 1)
            var path = Path()

            for (index, value) in values.enumerated() {
                let x = CGFloat(index) * step
                let y = size.height - CGFloat((value - minValue) / range) * size.height
                if index == 0 {
                    path.move(to: CGPoint(x: x, y: y))
                } else {
                    path.addLine(to: CGPoint(x: x, y: y))
                }
            }

            context.stroke(path, with: .color(tint.opacity(0.85)), lineWidth: 2)
        }
    }
}

struct ForsettiProgressRing: View {
    struct Segment: Identifiable {
        let id = UUID()
        let value: Double
        let color: Color
    }

    let segments: [Segment]
    let centerValue: String
    let subtitle: String

    var body: some View {
        let total = max(segments.reduce(0) { $0 + max(0, $1.value) }, 0.0001)

        ZStack {
            Circle()
                .stroke(DashboardColors.separator.opacity(0.30), lineWidth: 12)

            ForEach(Array(segments.enumerated()), id: \.element.id) { index, segment in
                let start = segments.prefix(index).reduce(0) { $0 + max(0, $1.value) } / total
                let end = start + max(0, segment.value) / total
                Circle()
                    .trim(from: start, to: end)
                    .stroke(segment.color, style: StrokeStyle(lineWidth: 12, lineCap: .round))
                    .rotationEffect(.degrees(-90))
            }

            VStack(spacing: 2) {
                Text(centerValue)
                    .font(DashboardTheme.Typography.numeric(size: 22))
                    .foregroundStyle(DashboardColors.textPrimary)
                    .monospacedDigit()
                Text(subtitle)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(DashboardColors.textTertiary)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(subtitle), \(centerValue)")
    }
}

struct ForsettiDataTable<Row: Identifiable, Header: View, RowContent: View, EmptyContent: View>: View {
    let rows: [Row]
    let selectedID: Row.ID?
    let onSelect: ((Row) -> Void)?
    @ViewBuilder let header: Header
    @ViewBuilder let rowContent: (Row) -> RowContent
    @ViewBuilder let emptyContent: EmptyContent

    var body: some View {
        VStack(spacing: 0) {
            header
                .font(DashboardTheme.Typography.caption)
                .foregroundStyle(DashboardColors.textTertiary)
                .padding(.horizontal, DashboardTheme.Spacing.md)
                .frame(height: 38)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(DashboardColors.backgroundDepth.opacity(0.36))

            if rows.isEmpty {
                emptyContent
                    .padding(DashboardTheme.Spacing.xl)
                    .frame(maxWidth: .infinity, minHeight: 140)
            } else {
                ForEach(rows) { row in
                    rowContent(row)
                        .padding(.horizontal, DashboardTheme.Spacing.md)
                        .frame(height: DashboardTheme.Layout.dataTableRowHeight)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(rowBackground(row))
                        .overlay(alignment: .bottom) {
                            Rectangle()
                                .fill(DashboardColors.separator.opacity(0.24))
                                .frame(height: 1)
                        }
                        .contentShape(Rectangle())
                        .onTapGesture {
                            onSelect?(row)
                        }
                }
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: DashboardTheme.Radius.card, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: DashboardTheme.Radius.card, style: .continuous).stroke(DashboardColors.separator.opacity(0.30), lineWidth: 1))
    }

    private func rowBackground(_ row: Row) -> Color {
        if row.id == selectedID {
            return DashboardColors.tableRowSelected.opacity(0.86)
        }
        return DashboardColors.tableRow.opacity(0.64)
    }
}

struct ForsettiScannerFrame: View {
    var title: String = "Ready to scan"
    var status: ForsettiSemanticStatus = .ready

    var body: some View {
        VStack(spacing: DashboardTheme.Spacing.md) {
            ZStack {
                RoundedRectangle(cornerRadius: DashboardTheme.Radius.panel, style: .continuous)
                    .stroke(status.color.opacity(0.88), lineWidth: 2)
                    .shadow(color: status.color.opacity(0.46), radius: 16)
                VStack(spacing: DashboardTheme.Spacing.sm) {
                    HStack(spacing: 5) {
                        ForEach(0..<10, id: \.self) { index in
                            RoundedRectangle(cornerRadius: 1)
                                .fill(DashboardColors.textPrimary.opacity(index.isMultiple(of: 3) ? 0.96 : 0.58))
                                .frame(width: index.isMultiple(of: 4) ? 4 : 2, height: 54)
                        }
                    }
                    Text(title)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(DashboardColors.textSecondary)
                }
            }
            .frame(minHeight: 170)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(title)
    }
}

struct ForsettiWizardStepper: View {
    let steps: [String]
    let currentIndex: Int

    var body: some View {
        HStack(spacing: DashboardTheme.Spacing.sm) {
            ForEach(Array(steps.enumerated()), id: \.offset) { index, step in
                let isCurrent = index == currentIndex
                let isComplete = index < currentIndex
                HStack(spacing: DashboardTheme.Spacing.sm) {
                    Circle()
                        .fill((isCurrent || isComplete) ? DashboardColors.accentCyan : DashboardColors.separator)
                        .frame(width: 20, height: 20)
                        .overlay {
                            if isComplete {
                                Image(systemName: "checkmark")
                                    .font(.caption2.weight(.bold))
                                    .foregroundStyle(DashboardColors.textInverse)
                            } else {
                                Text("\(index + 1)")
                                    .font(.caption2.weight(.bold))
                                    .foregroundStyle(isCurrent ? DashboardColors.textInverse : DashboardColors.textSecondary)
                            }
                        }
                    Text(step)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(isCurrent ? DashboardColors.textPrimary : DashboardColors.textTertiary)
                }

                if index < steps.count - 1 {
                    Rectangle()
                        .fill(DashboardColors.separator.opacity(0.54))
                        .frame(height: 1)
                }
            }
        }
        .accessibilityElement(children: .combine)
    }
}

struct ForsettiTabStrip: View {
    let tabs: [String]
    @Binding var selection: String

    var body: some View {
        HStack(spacing: DashboardTheme.Spacing.xs) {
            ForEach(tabs, id: \.self) { tab in
                Button {
                    selection = tab
                } label: {
                    Text(tab)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(selection == tab ? DashboardColors.textInverse : DashboardColors.textSecondary)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 7)
                        .background(Capsule().fill(selection == tab ? DashboardColors.accentCyan : DashboardColors.backgroundDepth.opacity(0.52)))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(4)
        .background(Capsule().fill(DashboardColors.backgroundPanelGlass.opacity(DashboardTheme.Opacity.toolbarFill)))
        .overlay(Capsule().stroke(DashboardColors.separator.opacity(0.34), lineWidth: 1))
    }
}
