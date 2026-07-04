import Foundation

enum JamfDashboardDeploymentMode {
    case production
    case development

    static var current: JamfDashboardDeploymentMode {
        #if DEBUG
        if ProcessInfo.processInfo.environment["FORSETTI_JAMF_PRO_DEVELOPMENT"] == "1" {
            return .development
        }
        #endif
        return .production
    }
}
