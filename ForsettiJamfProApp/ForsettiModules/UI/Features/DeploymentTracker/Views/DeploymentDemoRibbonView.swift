import SwiftUI

struct DeploymentDemoRibbonView: View {
    var compact = false

    var body: some View {
        HStack(spacing: compact ? 6 : DashboardTheme.Spacing.compact) {
            Label("DEMO", systemImage: "sparkles")
                .font(.caption.weight(.bold))
            Text("COMING SOON")
                .font(.caption.weight(.bold))
            if !compact {
                Text("Interactive preview")
                    .font(.caption.weight(.semibold))
            }
            Text("DUMMY DATA ONLY")
                .font(.caption.weight(.semibold))
            Text("NO LIVE JAMF ACTIONS")
                .font(.caption.weight(.semibold))
        }
        .foregroundStyle(DashboardTheme.accent)
        .lineLimit(1)
        .minimumScaleFactor(0.74)
        .padding(.horizontal, compact ? 8 : 10)
        .padding(.vertical, compact ? 5 : 6)
        .background(DashboardTheme.accent.opacity(0.12))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Deployment Tracker Demo. Coming soon. Dummy data only. No live Jamf actions.")
    }
}
