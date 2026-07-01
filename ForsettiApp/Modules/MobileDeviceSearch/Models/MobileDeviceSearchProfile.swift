import Foundation

/// A user-created search profile that stores a named set of field selections.
///
/// `MobileDeviceSearchProfile` allows users to save their preferred field configurations
/// so they can quickly switch between different views of device data without re-selecting
/// fields each time. Profiles are persisted to disk as JSON via `MobileDeviceSearchProfileStore`.
///
/// The `fieldKeys` array is always kept sorted to ensure consistent ordering and to make
/// equality comparisons and diffs deterministic.
struct MobileDeviceSearchProfile: Identifiable, Codable, Hashable, Sendable {
    /// A stable unique identifier for this profile, generated at creation time.
    let id: UUID

    /// The user-provided display name for this profile (e.g. "IT Audit Fields").
    var name: String

    /// The sorted list of `MobileDeviceField.key` values that define which fields
    /// are included when this profile is active.
    var fieldKeys: [String]

    /// The timestamp when this profile was first created, used for display and sorting.
    var createdAt: Date

    // "End of Line"

    /// Creates a new search profile with the given name and field selection.
    ///
    /// - Parameters:
    ///   - id: A unique identifier. Defaults to a new UUID.
    ///   - name: The human-readable name for this profile.
    ///   - fieldKeys: The field keys to include. These are automatically sorted on creation.
    ///   - createdAt: The creation timestamp. Defaults to the current date and time.
    init(
        id: UUID = UUID(),
        name: String,
        fieldKeys: [String],
        createdAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.fieldKeys = fieldKeys.sorted()
        self.createdAt = createdAt
    }
}

//endofline
