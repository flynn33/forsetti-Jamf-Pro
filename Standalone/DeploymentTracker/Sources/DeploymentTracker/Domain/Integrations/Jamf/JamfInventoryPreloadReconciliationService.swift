import Foundation

// MARK: - Jamf Inventory Preload reconciliation
//
// Reconciliation compares Jamf's current preload records with Tracker devices
// and returns read-only snapshots. The service never edits Jamf or local device
// fields directly; callers decide how and when snapshots are persisted.
nonisolated struct JamfInventoryPreloadReconciliationService: Sendable {
    func reconcile(
        devices: [DeploymentDevice],
        records: [JamfInventoryPreloadRecord]
    ) -> [JamfInventoryPreloadSnapshot] {
        // Normalize serial numbers before matching so formatting differences do
        // not hide a real Jamf preload record.
        let recordsBySerial = Dictionary(
            grouping: records,
            by: { DeploymentDevice.normalizeSerial($0.serialNumber) }
        )

        return devices.compactMap { device in
            guard let record = recordsBySerial[device.normalizedSerialNumber]?.first else {
                return nil
            }

            return JamfInventoryPreloadSnapshot(
                id: UUID().uuidString,
                deploymentDeviceId: device.id,
                serialNumber: device.serialNumber,
                capturedAt: Date(),
                rawRecordHash: nil,
                payloadSummary: [
                    "deviceType": record.deviceType ?? "",
                    "username": record.username ?? "",
                    "emailAddress": record.emailAddress ?? "",
                    "assetTag": record.assetTag ?? "",
                    "department": record.department ?? "",
                    "poNumber": record.poNumber ?? ""
                ]
            )
        }
    }
}
