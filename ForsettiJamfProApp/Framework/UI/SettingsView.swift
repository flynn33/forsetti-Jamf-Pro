import SwiftUI

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss

    @ObservedObject var credentialsStore: JamfCredentialsStore
    let diagnosticsReporter: (any DiagnosticsReporting)?

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
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
