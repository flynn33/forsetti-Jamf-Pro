import SwiftUI

/// The main dashboard view that serves as the app's home screen. It displays the brand header,
/// credential connection status, and a grid of installed Jamf modules. Toolbar buttons provide
/// access to the Settings and Diagnostics sheets.
struct DashboardView: View {
    /// Identifies which modal sheet is currently presented (settings or diagnostics).
    private enum ActiveSheet: String, Identifiable {
        /// The settings/configuration sheet.
        case settings
        /// The diagnostics log viewer sheet.
        case diagnostics

        /// Conforms to `Identifiable` using the raw string value.
        var id: String { rawValue }
    }

    /// The shared framework container providing access to credentials, diagnostics, and modules.
    @ObservedObject var container: ForsettiFrameworkContainer
    /// The module registry observed separately so the grid updates when modules are added/removed.
    @ObservedObject private var moduleRegistry: ModuleRegistry

    /// Tracks which sheet (settings or diagnostics) is currently presented, or nil if none.
    @State private var activeSheet: ActiveSheet?

    /// Initializes the dashboard with the given framework container and extracts
    /// the module registry for direct observation.
    /// - Parameter container: The shared `ForsettiFrameworkContainer` instance.
    init(container: ForsettiFrameworkContainer) {
        self.container = container
        _moduleRegistry = ObservedObject(wrappedValue: container.moduleRegistry)
    }

    /// Adaptive grid columns for the module cards, with a minimum width of 164pt per card.
    private var columns: [GridItem] {
        [GridItem(.adaptive(minimum: 164), spacing: ForsettiTheme.Spacing.item)]
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: ForsettiTheme.Spacing.section) {
                    ForsettiBrandHeader()
                    CredentialStatusCard(hasCredentials: container.credentialsStore.hasStoredCredentials)

                    VStack(alignment: .leading, spacing: ForsettiTheme.Spacing.item) {
                        Text("Installed Modules")
                            .font(.system(.headline, design: .rounded).weight(.semibold))
                            .foregroundStyle(ForsettiColors.textPrimary)

                        if moduleRegistry.modules.isEmpty {
                            Text("No modules are installed.")
                                .foregroundStyle(ForsettiColors.textSecondary)
                        } else {
                            // Lay out module cards in a responsive grid that adapts to screen width
                            LazyVGrid(columns: columns, alignment: .leading, spacing: ForsettiTheme.Spacing.item) {
                                ForEach(moduleRegistry.modules, id: \.id) { module in
                                    NavigationLink(value: module.id) {
                                        ModuleCard(
                                            moduleID: module.id,
                                            title: module.title,
                                            subtitle: module.subtitle,
                                            iconSystemName: module.iconSystemName
                                        )
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }
                    }
                }
                .padding(.horizontal, ForsettiTheme.Spacing.section)
                .padding(.vertical, ForsettiTheme.Spacing.section)
            }
            .background {
                ZStack {
                    ForsettiTheme.appBackground()
                    ForsettiMetalBackgroundView()
                    ForsettiTheme.appBackdropGradient.opacity(0.48)
                }
                .ignoresSafeArea()
            }
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
                // Resolve the module by ID and present its root view, or show an error.
                // Note: NavigationStack provides the system back button automatically.
                // Do NOT add .forsettiBackButtonToolbar() here — it creates a duplicate
                // back button and can dismiss the whole module instead of popping.
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
                // Refresh credential state in case the user saved/cleared while in another view
                container.credentialsStore.refreshState()
            }
        }
    }
}

/// A status card that indicates whether Jamf Pro credentials are configured.
/// Shows a green checkmark seal when connected, or an orange warning when credentials are missing.
private struct CredentialStatusCard: View {
    /// Whether the credential store currently has saved credentials.
    let hasCredentials: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: ForsettiTheme.Spacing.compact) {
            Label(
                hasCredentials ? "Connected credentials configured" : "Credentials required",
                systemImage: hasCredentials ? "checkmark.seal.fill" : "lock.trianglebadge.exclamationmark"
            )
            .font(.system(.headline, design: .rounded).weight(.semibold))
            .foregroundStyle(hasCredentials ? ForsettiColors.success : ForsettiColors.warning)

            Text(hasCredentials ?
                 "Modules can call the Jamf API through the framework gateway." :
                 "Open Settings to add Jamf Pro URL, choose one login method, verify, then save.")
                .font(.subheadline)
                .foregroundStyle(ForsettiColors.textSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .forsettiCardSurface()
    }
}

/// A compact card that represents an installed Jamf module in the dashboard grid.
/// Displays the module's SF Symbol icon, title, and a short subtitle description.
private struct ModuleCard: View {
    /// The module's stable package/module identifier.
    let moduleID: String
    /// The module's display name shown as the card title.
    let title: String
    /// A short description of the module's purpose.
    let subtitle: String
    /// The SF Symbols name for the module's icon.
    let iconSystemName: String

    private var isDeploymentTracker: Bool {
        moduleID == "forsetti.feature.deployment-tracker" || title.localizedCaseInsensitiveContains("Deployment Tracker")
    }

    var body: some View {
        ZStack(alignment: .topTrailing) {
            VStack(alignment: .leading, spacing: ForsettiTheme.Spacing.item) {
                Image(systemName: iconSystemName)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(ForsettiColors.bluePrimary)
                    .frame(width: 34, height: 34)
                    .background(
                        Circle()
                            .fill(ForsettiColors.accentCyan.opacity(0.14))
                    )

                Text(title)
                    .font(.system(.headline, design: .rounded).weight(.semibold))
                    .foregroundStyle(ForsettiColors.textPrimary)

                if isDeploymentTracker {
                    Text("Coming Soon")
                        .font(.system(.title3, design: .rounded).weight(.bold))
                        .foregroundStyle(ForsettiColors.warning)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .accessibilityAddTraits(.isHeader)
                }

                Text(subtitle)
                    .font(.footnote)
                    .foregroundStyle(ForsettiColors.textSecondary)
                    .lineLimit(isDeploymentTracker ? 2 : 3)

                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, minHeight: 152, alignment: .topLeading)
            .padding(16)

            if isDeploymentTracker {
                Text("Demo")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(ForsettiColors.textInverse)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(ForsettiColors.warning)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .stroke(Color.black.opacity(0.16), lineWidth: 1)
                    }
                    .padding(10)
                    .accessibilityLabel("Demo")
            }
        }
        .frame(maxWidth: .infinity, minHeight: 152, alignment: .topLeading)
        .forsettiCardSurface()
    }
}

/// A branded header bar displaying the Forsetti brand mark at the top of the dashboard
/// with the current app version shown on the trailing side.
private struct ForsettiBrandHeader: View {
    /// Marketing version pulled from the bundle's `CFBundleShortVersionString`
    /// (driven by `MARKETING_VERSION` in the Xcode project).
    private var appVersion: String {
        (Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String) ?? ""
    }

    var body: some View {
        HStack(alignment: .center) {
            ForsettiBrandMark()

            Spacer(minLength: ForsettiTheme.Spacing.item)

            if !appVersion.isEmpty {
                Text("v\(appVersion)")
                    .font(.system(.subheadline, design: .rounded).weight(.semibold))
                    .foregroundStyle(ForsettiColors.textSecondary)
                    .monospacedDigit()
                    .accessibilityLabel("App version \(appVersion)")
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .forsettiCardSurface(fill: ForsettiTheme.glassSurface)
    }
}

//endofline
