import SwiftUI

struct ObsidianBackground: View {
    var body: some View {
        ZStack {
            DashboardTheme.appBackground()
            MetalDataStreamBackground()
                .opacity(0.42)
        }
        .ignoresSafeArea()
        .accessibilityHidden(true)
    }
}

struct MetalDataStreamBackground: View {
    var body: some View {
        DashboardMetalBackgroundView()
    }
}

struct GlassPanel<Content: View>: View {
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
        ForsettiGlassPanel(padding: padding, isActive: isActive, statusTint: statusTint) {
            content
        }
    }
}

struct CommandCenterHeader: View {
    let title: String
    let subtitle: String
    let status: ForsettiSemanticStatus

    var body: some View {
        HStack(alignment: .center, spacing: DashboardTheme.Spacing.md) {
            VStack(alignment: .leading, spacing: DashboardTheme.Spacing.xs) {
                Text(title)
                    .font(DashboardTheme.Typography.screenTitle)
                    .foregroundStyle(DashboardColors.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(DashboardColors.textSecondary)
                    .lineLimit(2)
            }
            Spacer(minLength: DashboardTheme.Spacing.md)
            StatusPill(status: status)
        }
        .accessibilityElement(children: .combine)
    }
}

struct CredentialAlertCapsule: View {
    let isConnected: Bool

    var body: some View {
        StatusPill(
            status: isConnected ? .connected : .blocked,
            text: isConnected ? "Jamf Pro Connected" : "Credentials Required"
        )
    }
}

struct MetricTile: View {
    let title: String
    let value: String
    let subtitle: String
    let systemImage: String?
    var status: ForsettiSemanticStatus = .ready

    var body: some View {
        ForsettiMetricCard(
            title: title,
            value: value,
            subtitle: subtitle,
            systemImage: systemImage,
            status: status
        )
    }
}

struct ModuleCard: View {
    let moduleID: String?
    let title: String
    let subtitle: String
    let systemImage: String
    let status: ForsettiSemanticStatus

    init(
        moduleID: String,
        title: String,
        subtitle: String,
        iconSystemName: String
    ) {
        self.moduleID = moduleID
        self.title = title
        self.subtitle = subtitle
        self.systemImage = iconSystemName
        self.status = moduleID.contains("deployment-tracker") ? .workflow : .ready
    }

    init(
        title: String,
        subtitle: String,
        systemImage: String,
        status: ForsettiSemanticStatus = .ready
    ) {
        self.moduleID = nil
        self.title = title
        self.subtitle = subtitle
        self.systemImage = systemImage
        self.status = status
    }

    var body: some View {
        VStack(alignment: .leading, spacing: DashboardTheme.Spacing.md) {
            HStack(alignment: .top) {
                Image(systemName: systemImage)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(status.color)
                    .frame(width: 38, height: 38)
                    .background(RoundedRectangle(cornerRadius: DashboardTheme.Radius.medium).fill(status.color.opacity(0.14)))
                Spacer(minLength: 0)
                StatusPill(status: status)
            }
            Text(title)
                .font(DashboardTheme.Typography.cardTitle)
                .foregroundStyle(DashboardColors.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.82)
            Text(subtitle)
                .font(.caption)
                .foregroundStyle(DashboardColors.textSecondary)
                .lineLimit(3)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, minHeight: DashboardTheme.Layout.moduleCardHeight, maxHeight: DashboardTheme.Layout.moduleCardHeight, alignment: .topLeading)
        .forsettiGlassPanel(padding: .dense, statusTint: status.color)
        .accessibilityElement(children: .combine)
    }
}

struct StatusPill: View {
    let status: ForsettiSemanticStatus
    var text: String?

    var body: some View {
        ForsettiStatusPill(status: status, text: text)
    }
}

struct NavigationRail: View {
    let appTitle: String
    let appSubtitle: String
    let items: [ForsettiNavigationItem]
    let activeItemID: String?
    let utilityActions: [ForsettiNavigationAction]
    let userLabel: String
    let tenantLabel: String
    var mode: ForsettiNavigationRailMode = .regular

    var body: some View {
        ForsettiNavigationRail(
            appTitle: appTitle,
            appSubtitle: appSubtitle,
            items: items,
            activeItemID: activeItemID,
            utilityActions: utilityActions,
            userLabel: userLabel,
            tenantLabel: tenantLabel,
            mode: mode
        )
    }
}

struct CompactModuleRibbon: View {
    let modules: [ForsettiNavigationItem]
    let activeItemID: String?

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: DashboardTheme.Spacing.sm) {
                ForEach(modules) { module in
                    Label(module.title, systemImage: module.systemImage)
                        .font(.caption.weight(.semibold))
                        .lineLimit(1)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 8)
                        .background(
                            Capsule()
                                .fill(module.id == activeItemID ? DashboardColors.accentCyan.opacity(0.18) : DashboardColors.backgroundPanelGlass.opacity(0.72))
                        )
                        .foregroundStyle(module.id == activeItemID ? DashboardColors.accentCyan : DashboardColors.textSecondary)
                }
            }
            .padding(.horizontal, DashboardTheme.Spacing.md)
        }
    }
}

struct RightInsightRail<Content: View>: View {
    @ViewBuilder let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DashboardTheme.Spacing.lg) {
                content
            }
            .padding(.bottom, DashboardTheme.Spacing.xl)
        }
    }
}

struct RuntimeBoundaryPills: View {
    let statuses: [(String, ForsettiSemanticStatus)]

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: DashboardTheme.Spacing.sm) {
                ForEach(statuses, id: \.0) { label, status in
                    StatusPill(status: status, text: label)
                }
            }

            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: 132), spacing: DashboardTheme.Spacing.sm)],
                alignment: .leading,
                spacing: DashboardTheme.Spacing.sm
            ) {
                ForEach(statuses, id: \.0) { label, status in
                    StatusPill(status: status, text: label)
                }
            }
        }
        .accessibilityElement(children: .combine)
    }
}

struct ModuleMixCard: View {
    let title: String
    let segments: [ForsettiProgressRing.Segment]
    let centerValue: String
    let subtitle: String

    var body: some View {
        VStack(alignment: .leading, spacing: DashboardTheme.Spacing.lg) {
            ForsettiPanelHeader(title: title, systemImage: "chart.pie.fill")
            ForsettiProgressRing(segments: segments, centerValue: centerValue, subtitle: subtitle)
                .frame(width: 160, height: 160)
                .frame(maxWidth: .infinity)
        }
        .forsettiGlassPanel(padding: .standard)
    }
}

struct ForsettiPrimaryButton<Label: View>: View {
    let action: () -> Void
    @ViewBuilder let label: Label

    init(action: @escaping () -> Void, @ViewBuilder label: () -> Label) {
        self.action = action
        self.label = label()
    }

    var body: some View {
        Button(action: action) {
            label
        }
        .buttonStyle(.dashboardPrimary)
    }
}
