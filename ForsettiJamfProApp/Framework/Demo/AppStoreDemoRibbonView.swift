import SwiftUI

/// Persistent orange banner shown while App Store Review demo mode is active.
struct AppStoreDemoRibbonView: View {
    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "sparkles.rectangle.stack.fill")
                .imageScale(.medium)
            Text(AppStoreReviewDemoMode.ribbonMessage)
                .font(.caption.weight(.semibold))
                .lineLimit(2)
                .minimumScaleFactor(0.8)
            Spacer(minLength: 0)
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            LinearGradient(
                colors: [
                    Color.orange.opacity(0.95),
                    Color.orange.opacity(0.80)
                ],
                startPoint: .leading,
                endPoint: .trailing
            )
        )
        .accessibilityIdentifier("appStoreDemoRibbon")
        .accessibilityLabel("App Store demo mode. Sample data only. No live Jamf Pro connection.")
    }
}

/// Settings / credentials controls for entering and leaving demo mode.
struct AppStoreDemoModeControlsView: View {
    @ObservedObject private var demoController = AppStoreReviewDemoController.shared
    var onEnabled: (() -> Void)?
    var onDisabled: (() -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("App Store Demo Mode")
                .font(.headline)

            Text(AppStoreReviewDemoMode.safetyMessage)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            if demoController.isEnabled {
                Label("Demo mode is on — sample data only", systemImage: "checkmark.seal.fill")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.orange)

                Button(role: .destructive) {
                    demoController.disable()
                    onDisabled?()
                } label: {
                    Text("Exit Demo Mode")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.dashboardSecondary)
                .frame(maxWidth: .infinity, minHeight: 44)
                .accessibilityIdentifier("exitAppStoreDemoButton")
            } else {
                Button {
                    demoController.enable()
                    onEnabled?()
                } label: {
                    Text("Explore App Store Demo")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.dashboardPrimary)
                .frame(maxWidth: .infinity, minHeight: 44)
                .accessibilityIdentifier("enterAppStoreDemoButton")
            }
        }
        .padding(16)
        .dashboardCardSurface()
    }
}
