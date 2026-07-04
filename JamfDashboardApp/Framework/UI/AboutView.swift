import SwiftUI

/// A read-only informational view that describes the Jamf Dashboard application,
/// its purpose, and step-by-step usage instructions. Displayed from the Settings
/// screen when the user taps "About Jamf Dashboard".
struct AboutView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DashboardTheme.Spacing.section) {
                HStack(spacing: DashboardTheme.Spacing.item) {
                    Image(systemName: "app")
                        .font(.system(size: 28, weight: .semibold, design: .rounded))
                        .foregroundStyle(DashboardColors.bluePrimary)
                        .frame(width: 44, height: 44)
                        .background(DashboardColors.bluePrimary.opacity(0.12))
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .accessibilityHidden(true)

                    Text("Jamf Dashboard")
                        .font(.system(.title2, design: .rounded).weight(.bold))
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel("Jamf Dashboard")

                Text("Jamf Dashboard is a modular support app for Jamf Pro technicians. The framework provides secure credentials storage, centralized Jamf API communication, a module-based dashboard, and diagnostic logging.")
                    .font(.body.weight(.medium))

                Text("How To Use")
                    .font(.system(.headline, design: .rounded).weight(.semibold))

                // Step-by-step usage instructions for first-time users
                VStack(alignment: .leading, spacing: DashboardTheme.Spacing.item) {
                    Text("1. Open Settings, enter your Jamf Pro URL, choose API client or username/password, then verify the connection.")
                    Text("2. Save the verified credentials to Keychain.")
                    Text("3. Return to the dashboard and choose an installed module.")
                    Text("4. Use each module's workflow to search, review, and manage Jamf Pro data.")
                    Text("5. Open Diagnostics to review events and export logs as JSON when needed.")
                }
                .font(.body)

                Divider()

                Text("Developed by Jim Daley")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(DashboardColors.bluePrimary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(20)
            .dashboardCardSurface()
            .padding(16)
        }
        .dashboardAppBackground()
        .navigationTitle("About")
        .dashboardInlineNavigationTitle()
        // Pushed via NavigationLink from Settings; NavigationStack supplies the
        // back button. Do not add a custom one.
    }
}

// "End of Line"

//endofline
