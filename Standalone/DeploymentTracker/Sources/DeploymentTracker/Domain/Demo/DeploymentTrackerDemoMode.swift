import Foundation

nonisolated struct DeploymentTrackerDemoMode: Equatable, Sendable {
    let label: String
    let comingSoonLabel: String
    let safetyMessage: String
    let seedVersion: String
    let ribbonMessage: String

    static let installedDefault = DeploymentTrackerDemoMode(
        label: "DEMO",
        comingSoonLabel: "COMING SOON",
        safetyMessage: "Dummy data only. No live Jamf actions.",
        seedVersion: "deployment-tracker-demo-seed-v1",
        ribbonMessage: "DEMO - COMING SOON - DUMMY DATA ONLY - NO LIVE JAMF ACTIONS"
    )
}

nonisolated struct DeploymentTrackerDemoEnvironment: Sendable {
    let runtimeMode: DeploymentTrackerRuntimeMode
    let seedVersion: String

    static let installedDefault = DeploymentTrackerDemoEnvironment(
        runtimeMode: .demo,
        seedVersion: DeploymentTrackerDemoMode.installedDefault.seedVersion
    )
}

nonisolated enum DeploymentDemoSafetyError: LocalizedError, Equatable, Sendable {
    case liveActionBlocked(action: String)

    var errorDescription: String? {
        switch self {
        case .liveActionBlocked(let action):
            return "Demo mode blocked live action: \(action). No live Jamf actions were run."
        }
    }
}

nonisolated struct DeploymentDemoSimulationResult: Identifiable, Equatable, Sendable {
    let id: String
    let title: String
    let summary: String
    let simulatedSystem: String
    let affectedDemoRecordCount: Int
    let externalDataChanged: Bool
    let productionEquivalent: String
    let nextRecommendedDemoAction: String?
    let diagnosticsCategory: String
    let createdAt: Date

    static func jamfPreload(
        id: String,
        title: String,
        summary: String,
        affectedDemoRecordCount: Int,
        productionEquivalent: String,
        nextRecommendedDemoAction: String?,
        createdAt: Date = Date(timeIntervalSince1970: 1_801_000_000)
    ) -> DeploymentDemoSimulationResult {
        DeploymentDemoSimulationResult(
            id: id,
            title: title,
            summary: "\(summary) No Jamf data was changed.",
            simulatedSystem: "Jamf Inventory Preload",
            affectedDemoRecordCount: affectedDemoRecordCount,
            externalDataChanged: false,
            productionEquivalent: productionEquivalent,
            nextRecommendedDemoAction: nextRecommendedDemoAction,
            diagnosticsCategory: "deployment-tracker.demo.jamf-preload",
            createdAt: createdAt
        )
    }
}
