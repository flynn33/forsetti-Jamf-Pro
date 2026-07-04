import ForsettiHostTemplate
import SwiftUI

@MainActor
enum JamfDashboardViewInjectionRegistry {
    static func makeRegistry(appServices: JamfDashboardAppServices) -> ForsettiViewInjectionRegistry {
        let registry = ForsettiViewInjectionRegistry()
        registry.register(viewID: "jamf-dashboard-root") {
            JamfDashboardRootView(appServices: appServices)
        }
        return registry
    }
}
