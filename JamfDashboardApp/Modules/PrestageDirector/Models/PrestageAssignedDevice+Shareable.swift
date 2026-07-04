import Foundation

/// Makes `PrestageAssignedDevice` exportable through the shared `RecordMarkdown` pipeline,
/// so the technician can share the devices they've selected in the currently-viewed prestage.
///
/// The title is the device name (falling back to its serial); the fields are the device's
/// populated identifiers plus its assigned prestage.
extension PrestageAssignedDevice: ShareableRecord {
    var shareTitle: String {
        deviceName.isEmpty ? (normalizedSerialNumber ?? serialNumber) : deviceName
    }

    var shareFields: [ShareField] {
        let pairs: [(String, String?)] = [
            ("Serial Number", normalizedSerialNumber ?? serialNumber),
            ("Device Name", deviceName),
            ("Model", model),
            ("UDID", udid),
            ("Assigned Prestage", prestageName),
            ("Prestage ID", prestageID)
        ]
        return pairs.compactMap { label, value in
            guard let value, value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false else {
                return nil
            }
            return ShareField(label: label, value: value)
        }
    }
}

//endofline
