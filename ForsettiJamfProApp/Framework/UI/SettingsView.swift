import SwiftUI

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss

    @ObservedObject var credentialsStore: JamfCredentialsStore
    let diagnosticsReporter: (any DiagnosticsReporting)?
    @ObservedObject private var demoController = AppStoreReviewDemoController.shared

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if demoController.isEnabled {
                    AppStoreDemoRibbonView()
                }

                HStack {
                    Button {
                        dismiss()
                    } label: {
                        Label("Home", systemImage: "house.fill")
                            .font(.headline)
                    }
                    .buttonStyle(.dashboardSecondary)

                    Spacer(minLength: 0)
                }
                .padding(.horizontal, DashboardTheme.Spacing.section)
                .padding(.top, DashboardTheme.Spacing.compact)
                .padding(.bottom, 4)

                List {
                    Section {
                        AppStoreDemoModeControlsView(
                            onEnabled: {
                                // Reviewers can leave Settings and immediately use modules.
                                dismiss()
                            }
                        )
                        .listRowInsets(EdgeInsets(top: 8, leading: 12, bottom: 8, trailing: 12))
                        .listRowBackground(Color.clear)
                    } header: {
                        Text("App Store Review")
                    } footer: {
                        Text("Use demo mode when no Jamf Pro tenant is available (including App Review). Live credentials are never required.")
                    }

                    Section("Configuration") {
                        NavigationLink {
                            ServerCredentialsView(
                                credentialsStore: credentialsStore,
                                diagnosticsReporter: diagnosticsReporter
                            )
                        } label: {
                            Label("Jamf Credentials", systemImage: "key.fill")
                        }
                    }

                    Section("About") {
                        NavigationLink {
                            AboutView()
                        } label: {
                            Label("About Forsetti Jamf Pro", systemImage: "info.circle")
                        }
                    }
                }
                .dashboardInsetGroupedListStyle()
            }
            .navigationTitle("Settings")
            .dashboardInlineNavigationTitle()
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
    }
}
