import Foundation

nonisolated enum DeploymentTrackerRuntimeMode: String, Codable, Equatable, Sendable {
    case demo
    case productionDisabled

    var isDemoMode: Bool {
        self == .demo
    }

    var demoMode: DeploymentTrackerDemoMode? {
        self == .demo ? .installedDefault : nil
    }
}

nonisolated struct DeploymentTrackerDemoConfiguration: Codable, Equatable, Sendable {
    var runtimeMode: DeploymentTrackerRuntimeMode
    var showDemoRibbon: Bool
    var allowLiveJamfActions: Bool
    var allowLiveABMActions: Bool
    var allowLiveSDPlusActions: Bool
    var allowExternalNetworkActions: Bool
    var seedDummyDataOnLaunch: Bool
    var resetDummyDataOnLaunch: Bool

    static let installedDemo = DeploymentTrackerDemoConfiguration(
        runtimeMode: .demo,
        showDemoRibbon: true,
        allowLiveJamfActions: false,
        allowLiveABMActions: false,
        allowLiveSDPlusActions: false,
        allowExternalNetworkActions: false,
        seedDummyDataOnLaunch: true,
        resetDummyDataOnLaunch: true
    )
}
