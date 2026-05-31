import SwiftUI

/// A read-only informational view that describes the Forsetti application,
/// its purpose, and step-by-step usage instructions. Displayed from the Settings
/// screen when the user taps "About Forsetti".
struct AboutView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: ForsettiTheme.Spacing.section) {
                ForsettiBrandMark()

                Text("Forsetti is a modular support app for Jamf Pro technicians. The framework provides secure credentials storage, centralized Jamf API communication, a module-based dashboard, and diagnostic logging.")
                    .font(.body.weight(.medium))

                Text("How To Use")
                    .font(.system(.headline, design: .rounded).weight(.semibold))

                // Step-by-step usage instructions for first-time users
                VStack(alignment: .leading, spacing: ForsettiTheme.Spacing.item) {
                    Text("1. Open Settings, enter your Jamf Pro URL, choose API client or username/password, then verify the connection.")
                    Text("2. Save the verified credentials to Keychain.")
                    Text("3. Return to the dashboard and choose an installed module.")
                    Text("4. Use each module's workflow to search, review, and manage Jamf Pro data.")
                    Text("5. Open Diagnostics to review events and export logs as JSON when needed.")
                }
                .font(.body)

            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(20)
            .forsettiCardSurface()
            .padding(16)
        }
        .forsettiAppBackground()
        .navigationTitle("About")
        .forsettiInlineNavigationTitle()
        // Pushed via NavigationLink from Settings; NavigationStack supplies the
        // back button. Do not add a custom one.
    }
}

//endofline
