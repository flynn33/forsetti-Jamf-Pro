import Foundation

// MARK: - Records Management models
//
// Records policy keeps Deployment Tracker archive-first. Hard delete must be
// reviewed, exported, confirmed, audited, and isolated from external mutations.
nonisolated struct RecordsManagementPolicy: Codable, Equatable, Sendable {
    var defaultAction: String
    var hardDeleteScope: String
    var exportBeforeDeleteDefault: Bool
    var auditEventsHardDeletableByDefault: Bool
    var hardDeleteRequirements: [String]

    static let deploymentTrackerDefault = RecordsManagementPolicy(
        defaultAction: "archive",
        hardDeleteScope: "RecordsManagementOnly",
        exportBeforeDeleteDefault: true,
        auditEventsHardDeletableByDefault: false,
        hardDeleteRequirements: [
            "recordArchived",
            "impactAnalysisCompleted",
            "exportPolicySatisfied",
            "finalConfirmation",
            "auditEventWritten",
            "noExternalMutation"
        ]
    )
}

nonisolated struct RecordsExportFile: Codable, Equatable, Sendable {
    let path: String
    let contents: String
}

nonisolated struct RecordsExportPackage: Codable, Equatable, Sendable {
    let packageName: String
    let files: [RecordsExportFile]
    let job: RecordsExportJob
}

nonisolated struct RecordsExportManifest: Codable, Equatable, Sendable {
    let packageName: String
    let createdAt: Date
    let createdBy: String?
    let exportFormats: [String]
    let includedRecordCount: Int
    let files: [String]
}

nonisolated struct RecordsHardDeleteValidationResult: Codable, Equatable, Sendable {
    let allowed: Bool
    let blockingMessages: [String]
}
