import Foundation

/// Makes `SupportDeviceDetail` exportable through the shared `RecordMarkdown` pipeline.
///
/// SupportTechnician has no field catalog (unlike the search modules), so the shareable fields
/// are enumerated by hand: the support-relevant **identity** fields plus the **network**
/// identifiers, populated values only. `nonisolated` to match `SupportDeviceDetail`.
extension SupportDeviceDetail: ShareableRecord {
    nonisolated var shareTitle: String { summary.displayName }

    nonisolated var shareFields: [ShareField] {
        var pairs: [(String, String?)] = [
            ("Device Name", summary.displayName),
            ("Device Type", summary.assetType.title),
            ("Serial Number", summary.serialNumber),
            ("Inventory ID", summary.inventoryID),
            ("Assigned User", summary.username),
            ("User Email", summary.email),
            ("Model", summary.model),
            ("Operating System", summary.osVersion),
            ("Management ID", summary.managementID),
            ("PreStage Enrollment", summary.prestageEnrollment),
            ("Last Inventory Update", summary.lastInventoryUpdate)
        ]

        if let net = networkInfo {
            pairs += [
                ("IP Address", net.ipAddress),
                ("Last Reported IP", net.lastReportedIp),
                ("Hostname", net.hostname),
                ("Wi-Fi MAC Address", net.wifiMacAddress),
                ("Bluetooth MAC Address", net.bluetoothMacAddress),
                ("Phone Number", net.phoneNumber)
            ]
        }

        return pairs.compactMap { label, value in
            guard let value, value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false else {
                return nil
            }
            return ShareField(label: label, value: value)
        }
    }
}

//endofline
