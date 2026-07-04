import Foundation

// MARK: - Jamf Inventory Preload CSV renderer
//
// The renderer converts selected Tracker devices into the CSV shape Jamf expects
// for Inventory Preload. It is pure and synchronous so validation, preview, and
// upload can all use the exact same output.
nonisolated struct JamfInventoryPreloadCSVRenderer: Sendable {
    func renderCSV(
        devices: [DeploymentDevice],
        template: JamfInventoryPreloadTemplate,
        referenceValues: [DeploymentReferenceValue]
    ) -> String {
        // Header order is template-driven. Device values are resolved by field
        // key so template changes do not require UI changes.
        let header = template.columns.map { csvEscape($0.jamfColumn) }.joined(separator: ",")
        let rows = devices.map { device in
            template.columns.map { column in
                csvEscape(value(for: column.sourceField, device: device, referenceValues: referenceValues))
            }
            .joined(separator: ",")
        }
        return ([header] + rows).joined(separator: "\n")
    }

    func value(
        for sourceField: String,
        device: DeploymentDevice,
        referenceValues: [DeploymentReferenceValue]
    ) -> String {
        // Keep this switch explicit. Silent fallthrough would create blank CSV
        // cells that are hard to diagnose after Jamf rejects an upload.
        switch sourceField {
        case "device.serialNumber":
            return device.serialNumber
        case "device.deviceType.jamfPreloadDeviceType":
            return jamfPreloadDeviceType(for: device, referenceValues: referenceValues) ?? ""
        case "device.assignedUser":
            return device.assignedUser ?? ""
        case "device.assignedUserEmail":
            return device.assignedUserEmail ?? ""
        case "device.location.building":
            return locationMetadata("building", for: device, referenceValues: referenceValues)
        case "device.location.room":
            return locationMetadata("room", for: device, referenceValues: referenceValues)
        case "device.assetTag":
            return device.assetTag ?? ""
        case "device.department":
            return device.department ?? ""
        case "device.poNumber":
            return device.poNumber ?? ""
        default:
            return ""
        }
    }

    func jamfPreloadDeviceType(
        for device: DeploymentDevice,
        referenceValues: [DeploymentReferenceValue]
    ) -> String? {
        guard let deviceTypeId = device.deviceTypeId else {
            return nil
        }
        return referenceValues
            .first { $0.id == deviceTypeId }?
            .metadata["jamfPreloadDeviceType"]
    }

    nonisolated private func locationMetadata(
        _ key: String,
        for device: DeploymentDevice,
        referenceValues: [DeploymentReferenceValue]
    ) -> String {
        guard let locationId = device.locationId else {
            return ""
        }
        return referenceValues
            .first { $0.id == locationId }?
            .metadata[key] ?? ""
    }

    nonisolated private func csvEscape(_ value: String) -> String {
        let normalized = value.replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
        if normalized.contains(",") || normalized.contains("\"") || normalized.contains("\n") {
            return "\"\(normalized.replacingOccurrences(of: "\"", with: "\"\""))\""
        }
        return normalized
    }
}
