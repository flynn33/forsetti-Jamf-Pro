import Foundation

// MARK: - Apple Business verification service
//
// Verification is intentionally read-only. Implementations may capture an ABM
// snapshot and produce local mismatch results, but they must not assign, release,
// delete, or otherwise mutate ABM records.
nonisolated protocol AppleBusinessVerificationService: Sendable {
    func captureSnapshot(
        for device: DeploymentDevice,
        from record: AppleBusinessDeviceRecord?,
        capturedBy: String?,
        diagnosticsCorrelationId: String?
    ) -> AppleBusinessDeviceSnapshot

    func compareSnapshotToLocalDevice(
        snapshot: AppleBusinessDeviceSnapshot,
        device: DeploymentDevice,
        expectedMDMServiceName: String?
    ) -> AppleBusinessVerificationResult

    func createLocalException(
        from result: AppleBusinessVerificationResult
    ) -> DeploymentException?
}

// Default read-only verification implementation. It converts optional ABM
// records into snapshots, compares those snapshots to local Tracker devices, and
// creates local exceptions when mismatches need technician review.
nonisolated struct AppleBusinessReadOnlyVerificationService: AppleBusinessVerificationService {
    func captureSnapshot(
        for device: DeploymentDevice,
        from record: AppleBusinessDeviceRecord?,
        capturedBy: String? = nil,
        diagnosticsCorrelationId: String? = nil
    ) -> AppleBusinessDeviceSnapshot {
        guard let record else {
            return AppleBusinessDeviceSnapshot(
                deploymentDeviceId: device.id,
                serialNumber: device.serialNumber,
                capturedBy: capturedBy,
                lookupStatus: .notFound,
                diagnosticsCorrelationId: diagnosticsCorrelationId
            )
        }

        return AppleBusinessDeviceSnapshot(
            deploymentDeviceId: device.id,
            serialNumber: device.serialNumber,
            capturedBy: capturedBy,
            lookupStatus: recordLookupStatus(record),
            abmModel: record.model,
            abmSerialNumber: record.serialNumber,
            abmPartNumber: record.partNumber,
            abmOrderNumber: record.orderNumber,
            abmOrderSource: record.orderSource,
            abmStorageSize: record.storageSize,
            abmDeviceSource: record.deviceSource,
            abmDateAdded: record.dateAdded,
            abmReleasedState: record.releasedState,
            abmReleasedDate: record.releasedDate,
            abmAssignedManagementServiceId: record.assignedManagementServiceId,
            abmAssignedManagementServiceName: record.assignedManagementServiceName,
            rawRecordHash: nil,
            diagnosticsCorrelationId: diagnosticsCorrelationId
        )
    }

    func compareSnapshotToLocalDevice(
        snapshot: AppleBusinessDeviceSnapshot,
        device: DeploymentDevice,
        expectedMDMServiceName: String? = nil
    ) -> AppleBusinessVerificationResult {
        var mismatches: [AppleBusinessMismatchKind] = []

        switch snapshot.lookupStatus {
        case .notFound:
            mismatches.append(.missingFromABM)
        case .releasedOrUnavailable:
            mismatches.append(.abmReleasedOrUnavailable)
        case .lookupFailed:
            mismatches.append(.abmLookupFailed)
        default:
            break
        }

        if snapshot.abmAssignedManagementServiceName == nil, snapshot.lookupStatus != .notFound {
            mismatches.append(.unassignedInABM)
        } else if let expectedMDMServiceName,
                  snapshot.abmAssignedManagementServiceName?.caseInsensitiveCompare(expectedMDMServiceName) != .orderedSame {
            mismatches.append(.assignedToWrongMDMService)
        }

        if let abmModel = snapshot.abmModel,
           let localModel = device.model,
           abmModel.caseInsensitiveCompare(localModel) != .orderedSame {
            mismatches.append(.abmModelMismatch)
        }

        if let abmPartNumber = snapshot.abmPartNumber,
           let localPartNumber = device.applePartNumber,
           abmPartNumber.caseInsensitiveCompare(localPartNumber) != .orderedSame {
            mismatches.append(.abmPartNumberMismatch)
        }

        if let abmOrderNumber = snapshot.abmOrderNumber,
           let localOrderNumber = device.orderNumber,
           abmOrderNumber.caseInsensitiveCompare(localOrderNumber) != .orderedSame {
            mismatches.append(.abmOrderMismatch)
        }

        let verificationState = verificationState(
            snapshot: snapshot,
            mismatches: mismatches,
            expectedMDMServiceName: expectedMDMServiceName
        )
        return AppleBusinessVerificationResult(
            deviceId: device.id,
            snapshot: snapshot,
            verificationState: verificationState,
            mismatches: mismatches
        )
    }

    func createLocalException(
        from result: AppleBusinessVerificationResult
    ) -> DeploymentException? {
        guard !result.blockingMismatchKinds.isEmpty else {
            return nil
        }

        return DeploymentException(
            deviceId: result.deviceId,
            reasonCode: "abm-verification",
            summary: "ABM verification mismatch: \(result.blockingMismatchKinds.map(\.rawValue).joined(separator: ", "))",
            severity: .blocking
        )
    }

    nonisolated private func recordLookupStatus(_ record: AppleBusinessDeviceRecord) -> DeploymentABMVerificationState {
        if let releasedState = record.releasedState,
           releasedState.localizedCaseInsensitiveContains("released") {
            return .releasedOrUnavailable
        }
        if record.assignedManagementServiceName == nil {
            return .unassigned
        }
        return .found
    }

    nonisolated private func verificationState(
        snapshot: AppleBusinessDeviceSnapshot,
        mismatches: [AppleBusinessMismatchKind],
        expectedMDMServiceName: String?
    ) -> DeploymentABMVerificationState {
        if mismatches.contains(.missingFromABM) {
            return .notFound
        }
        if mismatches.contains(.abmReleasedOrUnavailable) {
            return .releasedOrUnavailable
        }
        if mismatches.contains(.assignedToWrongMDMService) {
            return .assignedToDifferentMDM
        }
        if mismatches.contains(.unassignedInABM) {
            return .unassigned
        }
        if expectedMDMServiceName != nil {
            return .assignedToExpectedMDM
        }
        return snapshot.lookupStatus == .found ? .found : snapshot.lookupStatus
    }
}
