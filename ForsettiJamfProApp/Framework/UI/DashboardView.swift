import SwiftUI

/// The app's Command Center home screen.
struct DashboardView: View {
    private enum ActiveSheet: String, Identifiable {
        case settings
        case diagnostics

        var id: String { rawValue }
    }

    @ObservedObject var appServices: ForsettiJamfProAppServices
    @State private var activeSheet: ActiveSheet?

    private var hasCredentials: Bool {
        appServices.credentialsStore.hasStoredCredentials
    }

    private var appVersion: String {
        (Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String) ?? ""
    }

    private var moduleNavigationItems: [ForsettiNavigationItem] {
        JamfDashboardRoute.allCases.map { route in
            ForsettiNavigationItem(
                id: route.id,
                title: route.title,
                subtitle: moduleSubtitle(for: route),
                systemImage: route.iconSystemName
            )
        }
    }

    private var routes: [JamfDashboardRoute] {
        JamfDashboardRoute.allCases
    }

    var body: some View {
        NavigationStack {
            ForsettiWorkspaceShell(
                navigation: { isCompact in
                    navigationRail(isCompact: isCompact)
                },
                commandStream: {
                    commandStream
                },
                content: {
                    commandCenterContent
                },
                inspector: {
                    commandCenterInspector
                },
                bottomDrawer: {
                    EmptyView()
                }
            )
            .sheet(item: $activeSheet) { activeSheet in
                switch activeSheet {
                case .settings:
                    SettingsView(
                        credentialsStore: appServices.credentialsStore,
                        diagnosticsReporter: appServices.diagnosticsCenter
                    )
                    .dashboardSheetSizing(
                        minWidth: 720, idealWidth: 820, maxWidth: 1000,
                        minHeight: 520, idealHeight: 600, maxHeight: 820,
                        fitVertically: false
                    )
                case .diagnostics:
                    DiagnosticsView(
                        viewModel: DiagnosticsViewModel(
                            diagnosticsReporter: appServices.diagnosticsCenter,
                            apiGateway: appServices.apiGateway
                        )
                    )
                    .dashboardSheetSizing(
                        minWidth: 860, idealWidth: 900, maxWidth: 1100,
                        minHeight: 620, idealHeight: 680, maxHeight: 900,
                        fitVertically: false
                    )
                }
            }
            .navigationDestination(for: JamfDashboardRoute.self) { route in
                route.makeRootView(context: appServices.viewContext)
                    .navigationTitle(route.title)
                    .dashboardInlineNavigationTitle()
#if os(macOS)
                    .frame(minWidth: 1200, minHeight: 820)
#endif
            }
            .navigationDestination(for: String.self) { routeID in
                if let route = JamfDashboardRoute(rawValue: routeID) {
                    route.makeRootView(context: appServices.viewContext)
                        .navigationTitle(route.title)
                        .dashboardInlineNavigationTitle()
#if os(macOS)
                        .frame(minWidth: 1200, minHeight: 820)
#endif
                } else {
                    ContentUnavailableView(
                        "Module Unavailable",
                        systemImage: "exclamationmark.triangle",
                        description: Text("The selected module could not be loaded.")
                    )
                }
            }
            .onAppear {
                appServices.credentialsStore.refreshState()
            }
        }
    }

    private func navigationRail(isCompact: Bool) -> some View {
        ForsettiNavigationRail(
            appTitle: "Jamf",
            appSubtitle: "Forsetti Pro",
            items: moduleNavigationItems,
            activeItemID: nil,
            utilityActions: [
                ForsettiNavigationAction(
                    id: "diagnostics",
                    title: "Diagnostics",
                    systemImage: "stethoscope",
                    action: { activeSheet = .diagnostics }
                ),
                ForsettiNavigationAction(
                    id: "settings",
                    title: "Settings",
                    systemImage: "gearshape",
                    action: { activeSheet = .settings }
                )
            ],
            userLabel: "Operator",
            tenantLabel: hasCredentials ? "Jamf Pro connected" : "Jamf Pro setup needed",
            mode: isCompact ? .compactTop : .regular
        )
    }

    private var commandStream: some View {
        ForsettiCommandStreamBar(
            state: hasCredentials ? .idle : .blocked,
            message: hasCredentials
                ? "Ready for Jamf Pro operations"
                : "Credentials required before live Jamf Pro calls",
            progress: hasCredentials ? 1 : 0,
            trailingText: hasCredentials ? "READY" : "BLOCKED"
        )
    }

    private var commandCenterContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DashboardTheme.Spacing.xl) {
                commandCenterHeader
                kpiGrid

                activityAndMixSection

                diagnosticsSummaryStrip
                moduleWorkspaceSection
            }
            .padding(.bottom, DashboardTheme.Spacing.xl)
        }
    }

    private var activityAndMixSection: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .top, spacing: DashboardTheme.Spacing.lg) {
                recentActivityPanel
                    .frame(minWidth: 560)
                deviceMixPanel
                    .frame(width: 300)
            }

            VStack(alignment: .leading, spacing: DashboardTheme.Spacing.lg) {
                recentActivityPanel
                deviceMixPanel
                    .frame(maxWidth: 360, alignment: .leading)
            }
        }
    }

    private var commandCenterHeader: some View {
        HStack(alignment: .center, spacing: DashboardTheme.Spacing.lg) {
            VStack(alignment: .leading, spacing: DashboardTheme.Spacing.sm) {
                HStack(spacing: DashboardTheme.Spacing.sm) {
                    Text("Jamf Command Center")
                        .font(DashboardTheme.Typography.screenTitle)
                        .foregroundStyle(DashboardColors.textPrimary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.72)
                    ForsettiStatusPill(status: hasCredentials ? .connected : .blocked)
                }

                Text("Operations cockpit for Jamf Pro inventory, deployment, reports, permissions, and technician workflows.")
                    .font(.subheadline)
                    .foregroundStyle(DashboardColors.textSecondary)
                    .lineLimit(2)
            }

            Spacer(minLength: DashboardTheme.Spacing.lg)

            Button {
                activeSheet = .settings
            } label: {
                Label("Customize", systemImage: "slider.horizontal.3")
            }
            .buttonStyle(.dashboardSecondary)
        }
        .forsettiGlassPanel(padding: .roomy, isActive: true)
    }

    private var kpiGrid: some View {
        LazyVGrid(
            columns: [GridItem(.adaptive(minimum: 190), spacing: DashboardTheme.Spacing.lg)],
            alignment: .leading,
            spacing: DashboardTheme.Spacing.lg
        ) {
            ForsettiMetricCard(
                title: "Fleet Health",
                value: hasCredentials ? "Ready" : "Blocked",
                subtitle: hasCredentials ? "gateway available" : "credential setup",
                systemImage: "heart.text.square.fill",
                status: hasCredentials ? .healthy : .blocked,
                trend: hasCredentials ? [0.62, 0.70, 0.74, 0.82, 0.88, 0.92] : []
            )
            ForsettiMetricCard(
                title: "Modules",
                value: "\(routes.count)",
                subtitle: "registered workspaces",
                systemImage: "square.grid.2x2.fill",
                status: routes.isEmpty ? .warning : .ready,
                trend: [0.4, 0.48, 0.56, 0.66, 0.78, 0.88]
            )
            ForsettiMetricCard(
                title: "Pending Commands",
                value: "0",
                subtitle: "global queue",
                systemImage: "paperplane.fill",
                status: .queued
            )
            ForsettiMetricCard(
                title: "Alerts",
                value: hasCredentials ? "0" : "1",
                subtitle: hasCredentials ? "no blockers" : "connection blocked",
                systemImage: "bell.badge.fill",
                status: hasCredentials ? .succeeded : .warning
            )
        }
    }

    private var recentActivityPanel: some View {
        VStack(alignment: .leading, spacing: DashboardTheme.Spacing.lg) {
            sectionHeader(title: "Recent Command Activity", systemImage: "bolt.horizontal.circle.fill")

            ScrollView(.horizontal, showsIndicators: true) {
                ForsettiDataTable(
                    rows: recentActivities,
                    selectedID: Optional<CommandCenterActivity.ID>.none,
                    onSelect: nil,
                    header: {
                        HStack(spacing: DashboardTheme.Spacing.md) {
                            Text("Command").frame(maxWidth: .infinity, alignment: .leading)
                            Text("Target").frame(width: 150, alignment: .leading)
                            Text("Status").frame(width: 132, alignment: .leading)
                            Text("Progress").frame(width: 112, alignment: .leading)
                            Text("Time").frame(width: 68, alignment: .trailing)
                        }
                    },
                    rowContent: { row in
                        HStack(spacing: DashboardTheme.Spacing.md) {
                            Text(row.command)
                                .font(DashboardTheme.Typography.tableBody)
                                .foregroundStyle(DashboardColors.textPrimary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .lineLimit(1)
                            Text(row.target)
                                .font(DashboardTheme.Typography.tableBody)
                                .foregroundStyle(DashboardColors.textSecondary)
                                .frame(width: 150, alignment: .leading)
                                .lineLimit(1)
                                .truncationMode(.middle)
                            ForsettiStatusPill(status: row.status)
                                .frame(width: 132, alignment: .leading)
                            Text(row.progress)
                                .font(.caption.monospacedDigit().weight(.semibold))
                                .foregroundStyle(DashboardColors.textSecondary)
                                .frame(width: 112, alignment: .leading)
                                .lineLimit(1)
                            Text(row.time)
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(DashboardColors.textTertiary)
                                .frame(width: 68, alignment: .trailing)
                        }
                    },
                    emptyContent: {
                        Text("No command activity yet.")
                            .foregroundStyle(DashboardColors.textSecondary)
                    }
                )
                .frame(minWidth: 680)
            }
        }
        .forsettiGlassPanel(padding: .standard)
    }

    private var deviceMixPanel: some View {
        VStack(alignment: .leading, spacing: DashboardTheme.Spacing.lg) {
            sectionHeader(title: "Device Platform Mix", systemImage: "chart.pie.fill")

            ForsettiProgressRing(
                segments: [
                    .init(value: 42, color: DashboardColors.accentCyan),
                    .init(value: 28, color: DashboardColors.accentBlue),
                    .init(value: 19, color: DashboardColors.accentViolet),
                    .init(value: 11, color: DashboardColors.accentMagenta)
                ],
                centerValue: hasCredentials ? "Live" : "Setup",
                subtitle: "Jamf data"
            )
            .frame(width: 160, height: 160)
            .frame(maxWidth: .infinity)

            VStack(spacing: DashboardTheme.Spacing.sm) {
                legendRow("Mac", color: DashboardColors.accentCyan, value: "Computers")
                legendRow("iPad", color: DashboardColors.accentBlue, value: "Mobile")
                legendRow("iPhone", color: DashboardColors.accentViolet, value: "Mobile")
                legendRow("Other", color: DashboardColors.accentMagenta, value: "Reports")
            }
        }
        .forsettiGlassPanel(padding: .standard)
    }

    private var diagnosticsSummaryStrip: some View {
        LazyVGrid(
            columns: [GridItem(.adaptive(minimum: 154), spacing: DashboardTheme.Spacing.md)],
            alignment: .leading,
            spacing: DashboardTheme.Spacing.md
        ) {
            diagnosticsChip(title: "Credentials", status: hasCredentials ? .connected : .blocked)
            diagnosticsChip(title: "Runtime", status: .healthy)
            diagnosticsChip(title: "Modules", status: routes.isEmpty ? .warning : .ready)
            diagnosticsChip(title: "Diagnostics", status: .active)
        }
        .forsettiGlassPanel(padding: .dense)
    }

    private var moduleWorkspaceSection: some View {
        VStack(alignment: .leading, spacing: DashboardTheme.Spacing.lg) {
            sectionHeader(title: "Available Workspaces", systemImage: "square.grid.2x2.fill")

            if routes.isEmpty {
                Text("No modules are installed.")
                    .foregroundStyle(DashboardColors.textSecondary)
                    .forsettiGlassPanel()
            } else {
                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: 220), spacing: DashboardTheme.Spacing.lg)],
                    alignment: .leading,
                    spacing: DashboardTheme.Spacing.lg
                ) {
                    ForEach(routes) { route in
                        NavigationLink(value: route) {
                            ModuleCard(
                                moduleID: route.moduleID,
                                title: route.title,
                                subtitle: route.subtitle,
                                iconSystemName: route.iconSystemName
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private var commandCenterInspector: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DashboardTheme.Spacing.lg) {
                ForsettiInspectorSection(title: "Quick Actions", systemImage: "bolt.fill") {
                    ForsettiQuickActionRow(
                        title: "Open Settings",
                        subtitle: "Connection and framework options",
                        systemImage: "gearshape.fill",
                        tint: DashboardColors.accentCyan,
                        action: { activeSheet = .settings }
                    )
                    ForsettiQuickActionRow(
                        title: "View Diagnostics",
                        subtitle: "Events, exports, and status",
                        systemImage: "stethoscope",
                        tint: DashboardColors.accentBlue,
                        action: { activeSheet = .diagnostics }
                    )
                }

                ForsettiInspectorSection(title: "Tenant Status", systemImage: "building.2.crop.circle") {
                    ForsettiKeyValueRow(key: "Jamf Pro", value: hasCredentials ? "Connected" : "Required", status: hasCredentials ? .connected : .blocked)
                    ForsettiKeyValueRow(key: "Modules", value: "\(routes.count)")
                    ForsettiKeyValueRow(key: "Runtime", value: "Forsetti active", status: .healthy)
                    if appVersion.isEmpty == false {
                        ForsettiKeyValueRow(key: "Version", value: appVersion)
                    }
                }

                ForsettiInspectorSection(title: "Technician Activity", systemImage: "person.crop.circle.badge.checkmark") {
                    VStack(spacing: DashboardTheme.Spacing.sm) {
                        ForEach(recentActivities.prefix(3)) { activity in
                            HStack(spacing: DashboardTheme.Spacing.sm) {
                                Image(systemName: activity.status.symbolName)
                                    .foregroundStyle(activity.status.color)
                                    .frame(width: 18)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(activity.command)
                                        .font(.caption.weight(.semibold))
                                        .foregroundStyle(DashboardColors.textPrimary)
                                        .lineLimit(1)
                                    Text(activity.target)
                                        .font(.caption2)
                                        .foregroundStyle(DashboardColors.textTertiary)
                                        .lineLimit(1)
                                }
                                Spacer(minLength: 0)
                            }
                        }
                    }
                }
            }
            .padding(.bottom, DashboardTheme.Spacing.xl)
        }
    }

    private func sectionHeader(title: String, systemImage: String) -> some View {
        Label(title, systemImage: systemImage)
            .font(DashboardTheme.Typography.sectionTitle)
            .foregroundStyle(DashboardColors.textPrimary)
            .accessibilityAddTraits(.isHeader)
    }

    private func legendRow(_ title: String, color: Color, value: String) -> some View {
        HStack(spacing: DashboardTheme.Spacing.sm) {
            Circle()
                .fill(color)
                .frame(width: 8, height: 8)
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(DashboardColors.textSecondary)
            Spacer(minLength: DashboardTheme.Spacing.sm)
            Text(value)
                .font(.caption2)
                .foregroundStyle(DashboardColors.textTertiary)
                .lineLimit(1)
        }
    }

    private func diagnosticsChip(title: String, status: ForsettiSemanticStatus) -> some View {
        HStack(spacing: DashboardTheme.Spacing.sm) {
            Image(systemName: status.symbolName)
                .foregroundStyle(status.color)
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(DashboardColors.textTertiary)
                Text(status.displayText)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(DashboardColors.textPrimary)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, DashboardTheme.Spacing.md)
        .padding(.vertical, DashboardTheme.Spacing.sm)
        .frame(maxWidth: .infinity)
        .background(RoundedRectangle(cornerRadius: DashboardTheme.Radius.medium, style: .continuous).fill(status.color.opacity(0.10)))
        .overlay(RoundedRectangle(cornerRadius: DashboardTheme.Radius.medium, style: .continuous).stroke(status.color.opacity(0.32), lineWidth: 1))
        .accessibilityElement(children: .combine)
    }

    private var recentActivities: [CommandCenterActivity] {
        [
            CommandCenterActivity(
                command: "Credential state",
                target: "Jamf Pro",
                status: hasCredentials ? .connected : .blocked,
                progress: hasCredentials ? "Ready" : "Setup",
                time: "Now"
            ),
            CommandCenterActivity(
                command: "Module registry",
                target: "Forsetti runtime",
                status: routes.isEmpty ? .warning : .succeeded,
                progress: "\(routes.count) loaded",
                time: "Now"
            ),
            CommandCenterActivity(
                command: "Diagnostics stream",
                target: "Framework",
                status: .active,
                progress: "Listening",
                time: "Live"
            ),
            CommandCenterActivity(
                command: "Workspace shell",
                target: "Command Center",
                status: .completed,
                progress: "Rendered",
                time: "Live"
            )
        ]
    }

    private func moduleSubtitle(for route: JamfDashboardRoute) -> String? {
        if route.moduleID.contains("computer") { return "Inventory" }
        if route.moduleID.contains("mobile") { return "Mobile" }
        if route.moduleID.contains("prestage") { return "Enrollment" }
        if route.moduleID.contains("reports") { return "Reports" }
        if route.moduleID.contains("permissions") { return "Security" }
        if route.moduleID.contains("deployment") { return "Workflow" }
        if route.moduleID.contains("support") { return "Technician" }
        return nil
    }
}

private struct CommandCenterActivity: Identifiable {
    let id = UUID()
    let command: String
    let target: String
    let status: ForsettiSemanticStatus
    let progress: String
    let time: String
}

//endofline
