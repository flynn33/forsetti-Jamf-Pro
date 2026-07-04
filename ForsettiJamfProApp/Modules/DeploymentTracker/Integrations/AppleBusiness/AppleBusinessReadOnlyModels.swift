import Foundation

// MARK: - Apple Business read-only models
//
// Apple Business Manager data is treated as an upstream read-only source.
// Tracker captures snapshots, compares them to local deployment records, and
// creates local exceptions for mismatches instead of editing ABM.
nonisolated enum AppleBusinessMismatchKind: String, Codable, CaseIterable, Sendable {
    case missingFromABM
    case assignedToWrongMDMService
    case unassignedInABM
    case abmModelMismatch
    case abmPartNumberMismatch
    case abmOrderMismatch
    case abmStorageMismatch
    case abmReleasedOrUnavailable
    case abmLookupFailed
    case abmSnapshotStale
    case abmSourceConflict
}

nonisolated struct AppleBusinessDeviceRecord: Identifiable, Codable, Equatable, Sendable {
    let id: String
    let serialNumber: String
    let model: String?
    let partNumber: String?
    let orderNumber: String?
    let orderSource: String?
    let storageSize: String?
    let deviceSource: String?
    let dateAdded: Date?
    let releasedState: String?
    let releasedDate: Date?
    let assignedManagementServiceId: String?
    let assignedManagementServiceName: String?
}

nonisolated struct AppleBusinessManagementService: Identifiable, Codable, Equatable, Sendable {
    let id: String
    let displayName: String
}

nonisolated struct AppleBusinessVerificationResult: Codable, Equatable, Sendable {
    let deviceId: String
    let snapshot: AppleBusinessDeviceSnapshot
    let verificationState: DeploymentABMVerificationState
    let mismatches: [AppleBusinessMismatchKind]

    var blockingMismatchKinds: [AppleBusinessMismatchKind] {
        mismatches.filter {
            [
                .missingFromABM,
                .assignedToWrongMDMService,
                .unassignedInABM,
                .abmReleasedOrUnavailable,
                .abmLookupFailed,
                .abmSourceConflict
            ].contains($0)
        }
    }
}

nonisolated protocol AppleBusinessDeviceProvider: Sendable {
    func lookupDevice(serialNumber: String) async throws -> AppleBusinessDeviceRecord?
    func lookupDevices(serialNumbers: [String]) async throws -> [AppleBusinessDeviceRecord]
}

nonisolated protocol AppleBusinessManagementServiceProvider: Sendable {
    func listDeviceManagementServices() async throws -> [AppleBusinessManagementService]
    func getAssignedDeviceManagementService(for serialNumber: String) async throws -> AppleBusinessManagementService?
}
