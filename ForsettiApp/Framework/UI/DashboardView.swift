import SwiftUI

/// Root command center for the Forsetti app.
@MainActor
struct DashboardView: View {
    private enum ActiveSheet: String, Identifiable {
        case settings
        case diagnostics

        var id: String { rawValue }
    }

    @ObservedObject var container: ForsettiFrameworkContainer
    @ObservedObject private var moduleRegistry: ModuleRegistry
    @State private var activeSheet: ActiveSheet?

    init(container: ForsettiFrameworkContainer) {
        self.container = container
        _moduleRegistry = ObservedObject(wrappedValue: container.moduleRegistry)
    }

    private var hasCredentials: Bool {
        container.credentialsStore.hasStoredCredentials
    }

    private var modules: [DashboardModuleSummary] {
        moduleRegistry.modules.map(DashboardModuleSummary.init(module:))
    }

    private var activityState: ForsettiCommandActivityState {
        hasCredentials
            ? .idle(lastUpdated: nil)
            : .blocked(label: "Jamf Pro connection", reason: "Credentials required")
    }

    private var diagnosticsItems: [ForsettiDiagnosticsDrawer.Item] {
        [
            .init(
                title: "UI module",
                value: "forsetti.retail.ui",
                kind: .ready
            ),
            .init(
                title: "Registered modules",
                value: "\(modules.count)",
                kind: modules.isEmpty ? .warning : .ready
            ),
            .init(
                title: "Jamf Pro connection",
                value: hasCredentials ? "Configured" : "Needs credentials",
                kind: hasCredentials ? .connected : .pending
            )
        ]
    }

    var body: some View {
        NavigationStack {
            ForsettiWorkspaceShell(
                backgroundStyle: .animatedBackdrop,
                navigation: {
                    CommandCenterNavigationRail(
                        modules: modules,
                        showSettings: { activeSheet = .settings },
                        showDiagnostics: { activeSheet = .diagnostics }
                    )
                },
                commandActivityBar: {
                    ForsettiCommandActivityBar(state: activityState)
                },
                header: {
                    CommandCenterHeader(
                        hasCredentials: hasCredentials,
                        moduleCount: modules.count
                    )
                },
                content: {
                    CommandCenterContent(
                        modules: modules,
                        hasCredentials: hasCredentials
                    )
                },
                inspector: {
                    CommandCenterInspector(
                        hasCredentials: hasCredentials,
                        modules: modules,
                        showSettings: { activeSheet = .settings }
                    )
                },
                bottomDrawer: {
                    ForsettiDiagnosticsDrawer(items: diagnosticsItems)
                }
            )
            .navigationTitle("Forsetti")
            .toolbar {
                ToolbarItem(placement: .forsettiTopBarLeading) {
                    Button {
                        activeSheet = .diagnostics
                    } label: {
                        Label("Diagnostics", systemImage: "stethoscope")
                    }
                }

                ToolbarItem(placement: .forsettiTopBarTrailing) {
                    Button {
                        activeSheet = .settings
                    } label: {
                        Label("Settings", systemImage: "gearshape")
                    }
                }
            }
            .sheet(item: $activeSheet) { activeSheet in
                switch activeSheet {
                case .settings:
#if os(macOS)
                    SettingsView(
                        credentialsStore: container.credentialsStore,
                        diagnosticsReporter: container.diagnosticsCenter,
                        modulePackageManager: container.modulePackageManager
                    )
                    .frame(minWidth: 900, minHeight: 650)
#else
                    SettingsView(
                        credentialsStore: container.credentialsStore,
                        diagnosticsReporter: container.diagnosticsCenter,
                        modulePackageManager: container.modulePackageManager
                    )
#endif
                case .diagnostics:
#if os(macOS)
                    DiagnosticsView(
                        viewModel: DiagnosticsViewModel(
                            diagnosticsReporter: container.diagnosticsCenter,
                            apiGateway: container.apiGateway
                        )
                    )
                    .frame(minWidth: 860, minHeight: 620)
#else
                    DiagnosticsView(
                        viewModel: DiagnosticsViewModel(
                            diagnosticsReporter: container.diagnosticsCenter,
                            apiGateway: container.apiGateway
                        )
                    )
#endif
                }
            }
            .navigationDestination(for: String.self) { moduleID in
                if let module = moduleRegistry.module(withID: moduleID) {
                    module.makeRootView(context: container.moduleContext)
                        .navigationTitle(module.title)
                        .forsettiInlineNavigationTitle()
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
                container.refreshDashboardState()
            }
        }
    }
}

struct DashboardModuleSummary: Identifiable, Hashable {
    enum Category: String, Hashable {
        case inventory = "Inventory"
        case operations = "Operations"
        case reporting = "Reporting"
        case deployment = "Deployment"

        var color: Color {
            switch self {
            case .inventory:
                return ForsettiColors.accentCyan
            case .operations:
                return ForsettiColors.accentBlue
            case .reporting:
                return ForsettiColors.accentViolet
            case .deployment:
                return ForsettiColors.success
            }
        }
    }

    let id: String
    let title: String
    let subtitle: String
    let iconSystemName: String
    let category: Category

    var isDemo: Bool {
        title.localizedCaseInsensitiveContains("demo")
            || subtitle.localizedCaseInsensitiveContains("dummy data")
            || subtitle.localizedCaseInsensitiveContains("no live")
    }

    init(module: any JamfModule) {
        id = module.id
        title = module.title
        subtitle = module.subtitle
        iconSystemName = module.iconSystemName
        category = Self.category(for: module.id)
    }

    private static func category(for moduleID: String) -> Category {
        if moduleID == "forsetti.feature.deployment-tracker" {
            return .deployment
        }
        if moduleID.contains("reports") {
            return .reporting
        }
        if moduleID.contains("support") || moduleID.contains("prestage") {
            return .operations
        }
        return .inventory
    }
}

private struct CommandCenterNavigationRail: View {
    @Environment(\.forsettiWorkspaceNavigationPlacement) private var placement

    let modules: [DashboardModuleSummary]
    let showSettings: () -> Void
    let showDiagnostics: () -> Void

    var body: some View {
        switch placement {
        case .side:
            sideRail
        case .top:
            topRail
        }
    }

    private var sideRail: some View {
        VStack(alignment: .leading, spacing: ForsettiTheme.Spacing.section) {
            ForsettiBrandHeader()

            VStack(alignment: .leading, spacing: ForsettiTheme.Spacing.compact) {
                Text("Workspace")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(ForsettiColors.textTertiary)
                    .textCase(.uppercase)

                ForEach(modules) { module in
                    NavigationLink(value: module.id) {
                        RailModuleRow(module: module)
                    }
                    .buttonStyle(.plain)
                }
            }

            sideRailActions
                .frame(maxHeight: .infinity, alignment: .bottom)
        }
        .padding(ForsettiTheme.Spacing.item)
    }

    private var sideRailActions: some View {
        VStack(spacing: ForsettiTheme.Spacing.compact) {
            Button(action: showDiagnostics) {
                Label("Diagnostics", systemImage: "stethoscope")
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.forsettiSecondary)

            Button(action: showSettings) {
                Label("Settings", systemImage: "gearshape")
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.forsettiSecondary)
        }
    }

    private var topRail: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: ForsettiTheme.Spacing.compact) {
                ForsettiBrandHeader()
                    .frame(width: 170)

                ForEach(modules) { module in
                    NavigationLink(value: module.id) {
                        RailModuleRow(module: module, style: .compact)
                    }
                    .buttonStyle(.plain)
                }

                Divider()
                    .frame(height: 28)
                    .overlay(ForsettiTheme.border)

                Button(action: showDiagnostics) {
                    Label("Diagnostics", systemImage: "stethoscope")
                        .labelStyle(.iconOnly)
                        .frame(width: 36, height: 36)
                }
                .buttonStyle(.forsettiSecondary)
                .help("Diagnostics")

                Button(action: showSettings) {
                    Label("Settings", systemImage: "gearshape")
                        .labelStyle(.iconOnly)
                        .frame(width: 36, height: 36)
                }
                .buttonStyle(.forsettiSecondary)
                .help("Settings")
            }
            .padding(.horizontal, ForsettiTheme.Spacing.item)
            .padding(.vertical, ForsettiTheme.Spacing.compact)
        }
        .frame(maxWidth: .infinity, maxHeight: 68, alignment: .leading)
    }
}

private struct RailModuleRow: View {
    enum Style {
        case regular
        case compact
    }

    let module: DashboardModuleSummary
    let style: Style

    init(module: DashboardModuleSummary, style: Style = .regular) {
        self.module = module
        self.style = style
    }

    var body: some View {
        HStack(spacing: ForsettiTheme.Spacing.compact) {
            Image(systemName: module.iconSystemName)
                .font(.callout.weight(.semibold))
                .foregroundStyle(module.category.color)
                .frame(width: 28, height: 28)
                .background(module.category.color.opacity(0.14), in: RoundedRectangle(cornerRadius: 8))

            VStack(alignment: .leading, spacing: 2) {
                Text(module.title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(ForsettiColors.textPrimary)
                    .lineLimit(1)
                Text(module.isDemo ? "Demo" : module.category.rawValue)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(module.isDemo ? ForsettiColors.warning : ForsettiColors.textTertiary)
            }
        }
        .padding(.horizontal, ForsettiTheme.Spacing.compact)
        .padding(.vertical, 7)
        .frame(maxWidth: style == .regular ? .infinity : nil, alignment: .leading)
        .frame(width: style == .compact ? 180 : nil, alignment: .leading)
        .background(ForsettiColors.backgroundPanelGlass.opacity(0.42), in: RoundedRectangle(cornerRadius: 12))
        .overlay {
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(module.category.color.opacity(0.18), lineWidth: 1)
        }
    }
}

private struct CommandCenterHeader: View {
    let hasCredentials: Bool
    let moduleCount: Int

    private var appVersion: String {
        (Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String) ?? ""
    }

    var body: some View {
        ForsettiGlassCard(active: true) {
            HStack(alignment: .center, spacing: ForsettiTheme.Spacing.section) {
                VStack(alignment: .leading, spacing: ForsettiTheme.Spacing.compact) {
                    Text("Command Center")
                        .font(.system(.largeTitle, design: .rounded).weight(.bold))
                        .foregroundStyle(ForsettiColors.textPrimary)
                    Text("Retail operations workspace for Jamf Pro modules, diagnostics, reports, and deployment workflows.")
                        .font(.callout)
                        .foregroundStyle(ForsettiColors.textSecondary)
                        .lineLimit(2)
                }

                Spacer(minLength: ForsettiTheme.Spacing.item)

                VStack(alignment: .trailing, spacing: ForsettiTheme.Spacing.compact) {
                    HStack(spacing: ForsettiTheme.Spacing.compact) {
                        ForsettiStatusBadge(hasCredentials ? .connected : .pending, text: hasCredentials ? "Connected" : "Credentials")
                        ForsettiStatusBadge(.ready, text: "\(moduleCount) modules")
                    }

                    if !appVersion.isEmpty {
                        Text("v\(appVersion)")
                            .font(.caption.monospacedDigit().weight(.semibold))
                            .foregroundStyle(ForsettiColors.textTertiary)
                    }
                }
            }
        }
    }
}

private struct CommandCenterContent: View {
    let modules: [DashboardModuleSummary]
    let hasCredentials: Bool

    private var columns: [GridItem] {
        [GridItem(.adaptive(minimum: 210), spacing: ForsettiTheme.Spacing.item)]
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: ForsettiTheme.Spacing.section) {
                metricStrip

                VStack(alignment: .leading, spacing: ForsettiTheme.Spacing.item) {
                    Text("Modules")
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(ForsettiColors.textPrimary)

                    if modules.isEmpty {
                        ContentUnavailableView(
                            "No Modules Installed",
                            systemImage: "square.grid.2x2",
                            description: Text("Install or enable modules from Settings.")
                        )
                        .forsettiCardSurface(fill: ForsettiTheme.glassSurface)
                    } else {
                        LazyVGrid(columns: columns, alignment: .leading, spacing: ForsettiTheme.Spacing.item) {
                            ForEach(modules) { module in
                                NavigationLink(value: module.id) {
                                    CommandCenterModuleCard(module: module)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
            }
        }
    }

    private var metricStrip: some View {
        LazyVGrid(
            columns: [GridItem(.adaptive(minimum: 170), spacing: ForsettiTheme.Spacing.item)],
            alignment: .leading,
            spacing: ForsettiTheme.Spacing.item
        ) {
            CommandCenterMetricCard(
                title: "Connection",
                value: hasCredentials ? "Ready" : "Setup",
                detail: hasCredentials ? "Credentials configured" : "Open Settings",
                tint: hasCredentials ? ForsettiColors.success : ForsettiColors.warning,
                symbolName: hasCredentials ? "checkmark.seal.fill" : "key.fill"
            )

            CommandCenterMetricCard(
                title: "Modules",
                value: "\(modules.count)",
                detail: "Registered workspaces",
                tint: ForsettiColors.accentCyan,
                symbolName: "square.grid.3x3.fill"
            )

            CommandCenterMetricCard(
                title: "Theme",
                value: "Obsidian",
                detail: "Data Stream active",
                tint: ForsettiColors.accentViolet,
                symbolName: "circle.hexagongrid.fill"
            )

            CommandCenterMetricCard(
                title: "Boundary",
                value: "Retail UI",
                detail: "Single app module",
                tint: ForsettiColors.accentBlue,
                symbolName: "rectangle.3.group.fill"
            )
        }
    }
}

private struct CommandCenterMetricCard: View {
    let title: String
    let value: String
    let detail: String
    let tint: Color
    let symbolName: String

    var body: some View {
        ForsettiGlassCard(style: .dense) {
            HStack(alignment: .center, spacing: ForsettiTheme.Spacing.item) {
                Image(systemName: symbolName)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(tint)
                    .frame(width: 36, height: 36)
                    .background(tint.opacity(0.14), in: RoundedRectangle(cornerRadius: 12))

                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(ForsettiColors.textTertiary)
                    Text(value)
                        .font(.title3.monospacedDigit().weight(.bold))
                        .foregroundStyle(ForsettiColors.textPrimary)
                    Text(detail)
                        .font(.caption)
                        .foregroundStyle(ForsettiColors.textSecondary)
                        .lineLimit(1)
                }
            }
        }
    }
}

private struct CommandCenterModuleCard: View {
    let module: DashboardModuleSummary

    var body: some View {
        ForsettiGlassCard(active: module.category == .deployment) {
            VStack(alignment: .leading, spacing: ForsettiTheme.Spacing.item) {
                HStack(alignment: .center) {
                    Image(systemName: module.iconSystemName)
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(module.category.color)
                        .frame(width: 40, height: 40)
                        .background(module.category.color.opacity(0.16), in: RoundedRectangle(cornerRadius: 12))

                    Spacer(minLength: ForsettiTheme.Spacing.item)

                    if module.isDemo {
                        ForsettiStatusBadge(.warning, text: "Demo")
                    }
                    ForsettiStatusBadge(.ready, text: module.category.rawValue)
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text(module.title)
                        .font(.headline.weight(.semibold))
                        .foregroundStyle(ForsettiColors.textPrimary)
                    Text(module.subtitle)
                        .font(.footnote)
                        .foregroundStyle(ForsettiColors.textSecondary)
                        .lineLimit(3)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 0)

                HStack(spacing: ForsettiTheme.Spacing.compact) {
                    Text("Open")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(module.category.color)
                    Image(systemName: "arrow.right")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(module.category.color)
                }
            }
            .frame(maxWidth: .infinity, minHeight: 176, alignment: .topLeading)
        }
    }
}

private struct CommandCenterInspector: View {
    let hasCredentials: Bool
    let modules: [DashboardModuleSummary]
    let showSettings: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: ForsettiTheme.Spacing.item) {
            ForsettiGlassCard {
                VStack(alignment: .leading, spacing: ForsettiTheme.Spacing.item) {
                    HStack {
                        Label("Tenant State", systemImage: hasCredentials ? "checkmark.shield.fill" : "lock.shield.fill")
                            .font(.headline.weight(.semibold))
                            .foregroundStyle(hasCredentials ? ForsettiColors.success : ForsettiColors.warning)
                        Spacer(minLength: 0)
                    }

                    Text(hasCredentials ? "Jamf Pro credentials are configured for framework gateway use." : "Credentials are required before modules can call Jamf Pro through the framework gateway.")
                        .font(.subheadline)
                        .foregroundStyle(ForsettiColors.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)

                    Button(action: showSettings) {
                        Label(hasCredentials ? "Manage Credentials" : "Configure Credentials", systemImage: "key.fill")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.forsettiPrimary)
                }
            }

            ForsettiGlassCard(style: .dense) {
                VStack(alignment: .leading, spacing: ForsettiTheme.Spacing.item) {
                    Text("Module Mix")
                        .font(.headline.weight(.semibold))
                        .foregroundStyle(ForsettiColors.textPrimary)

                    ForEach(categoryCounts, id: \.category) { item in
                        HStack {
                            Circle()
                                .fill(item.category.color)
                                .frame(width: 8, height: 8)
                            Text(item.category.rawValue)
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(ForsettiColors.textSecondary)
                            Spacer()
                            Text("\(item.count)")
                                .font(.caption.monospacedDigit().weight(.semibold))
                                .foregroundStyle(ForsettiColors.textPrimary)
                        }
                    }
                }
            }

            ForsettiGlassCard(style: .dense) {
                VStack(alignment: .leading, spacing: ForsettiTheme.Spacing.compact) {
                    Text("Runtime Boundaries")
                        .font(.headline.weight(.semibold))
                        .foregroundStyle(ForsettiColors.textPrimary)
                    ForsettiStatusBadge(.ready, text: "SwiftUI rendering")
                    ForsettiStatusBadge(.ready, text: "Metal presentation")
                    ForsettiStatusBadge(.ready, text: "Framework gateway")
                }
            }
        }
    }

    private var categoryCounts: [(category: DashboardModuleSummary.Category, count: Int)] {
        DashboardModuleSummary.Category.allCasesForDashboard.map { category in
            (category, modules.filter { $0.category == category }.count)
        }
    }
}

private extension DashboardModuleSummary.Category {
    static var allCasesForDashboard: [DashboardModuleSummary.Category] {
        [.inventory, .operations, .reporting, .deployment]
    }
}

private struct ForsettiBrandHeader: View {
    var body: some View {
        HStack(alignment: .center, spacing: ForsettiTheme.Spacing.item) {
            ForsettiBrandMark()
            Spacer(minLength: 0)
        }
        .padding(ForsettiTheme.Spacing.compact)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(ForsettiColors.backgroundPanelGlass.opacity(0.58), in: RoundedRectangle(cornerRadius: 16))
        .overlay {
            RoundedRectangle(cornerRadius: 16)
                .strokeBorder(ForsettiTheme.border, lineWidth: 1)
        }
    }
}

//endofline
