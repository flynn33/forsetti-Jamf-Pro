import Foundation

/// A lightweight summary of a single mobile device prestage enrollment profile.
///
/// Contains just enough information to populate picker UI and to perform scope
/// mutations (add/remove devices) against the Jamf Pro API. The `versionLock`
/// field is required by the API for optimistic concurrency control when modifying
/// a prestage's assigned device scope.
struct PrestageSummary: Identifiable, Hashable, Sendable {
    /// The Jamf Pro prestage identifier, used as the unique key for API calls.
    let id: String

    /// The display name of the prestage profile as configured in Jamf Pro.
    let name: String

    /// Optimistic concurrency token required by the Jamf Pro API when mutating scope.
    /// `nil` when the server response did not include a version lock value.
    let versionLock: Int?
}

/// Represents a single device that is currently assigned to a prestage enrollment profile.
///
/// Each device is identified primarily by its serial number, which is normalized
/// (trimmed and uppercased) for reliable comparison and selection tracking.
struct PrestageAssignedDevice: Identifiable, Hashable, Sendable {
    /// The device's Jamf Pro inventory or assignment identifier.
    let id: String

    /// The raw serial number string as returned by the API.
    let serialNumber: String

    /// The human-readable device name shown in list rows.
    let deviceName: String

    /// The device's unique device identifier (UDID), if available.
    let udid: String?

    /// The hardware model string (e.g. "iPad Pro 11-inch"), if available.
    let model: String?

    /// The ID of the pre-stage profile this device is currently assigned to. Populated
    /// at parse time from the URL that produced the response. `nil` only when a legacy
    /// fallback parser path did not have the pre-stage context available.
    let prestageID: String?

    /// The display name of the pre-stage profile this device is currently assigned to.
    /// Shown in the row when the assignment differs from the currently-viewed pre-stage
    /// so users can see where a globally-searched device lives.
    let prestageName: String?

    /// A stable key used for tracking selection state. Prefers the normalized serial
    /// number when available, falling back to the device `id`.
    var selectionKey: String {
        normalizedSerialNumber ?? id
    }

    /// The serial number after trimming whitespace and converting to uppercase.
    /// Returns `nil` if the serial number is empty or whitespace-only, indicating
    /// the device lacks a usable serial number for scope mutations.
    var normalizedSerialNumber: String? {
        let trimmed = serialNumber.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.isEmpty == false else {
            return nil
        }

        return trimmed.uppercased()
    }
}

/// Tracks the progress of a long-running prestage operation (move or remove) so
/// the UI can display a determinate progress bar with contextual messaging.
struct PrestageDirectorOperationProgress: Sendable {
    /// A short label identifying the operation phase, e.g. "Move in progress".
    let title: String

    /// A longer description of the current step, e.g. "Removing selected devices...".
    let detail: String

    /// A value between 0.0 and 1.0 representing how far the operation has progressed.
    let fractionCompleted: Double
}

//endofline
