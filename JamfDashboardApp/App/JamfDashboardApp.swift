import SwiftUI

@main
struct JamfDashboardApp: App {
    @StateObject private var bootstrap = JamfDashboardForsettiBootstrap()

    var body: some Scene {
        WindowGroup {
            JamfDashboardLaunchView(bootstrap: bootstrap)
                .tint(DashboardColors.bluePrimary)
                .dashboardRoundedTypography()
                .dashboardAppBackground()
#if os(macOS)
                .frame(minWidth: 1200, minHeight: 820)
#endif
        }
#if os(macOS)
        .defaultSize(width: 1360, height: 860)
#endif
    }
}
