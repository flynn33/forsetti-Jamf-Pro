import Foundation

/// A named, persistable collection of inventory field keys that the user has selected for a computer search.
///
/// Search profiles let users save their preferred field configurations so they can quickly
/// switch between different search scopes (e.g. "Hardware Audit" vs. "User Lookup") without
/// manually re-selecting fields each time. Profiles are persisted to disk as JSON via
/// `ComputerSearchProfileStore`.
struct ComputerSearchProfile: Identifiable, Codable, Hashable, Sendable {
    /// A stable UUID that uniquely identifies this profile across persistence cycles.
    let id: UUID

    /// The user-chosen display name for the profile (e.g. "Security Audit Fields").
    var name: String

    /// An alphabetically sorted list of inventory field keys (e.g. `["general.name", "hardware.serialNumber"]`)
    /// that define which columns are included when this profile is active.
    var fieldKeys: [String]

    /// The timestamp when this profile was originally created, used for sorting and display purposes.
    var createdAt: Date

    /// Creates a new search profile with the given name and field keys.
    ///
    /// The `fieldKeys` array is automatically sorted on initialization to ensure
    /// consistent ordering regardless of the order the user selected the fields.
    ///
    /// - Parameters:
    ///   - id: A unique identifier. Defaults to a new UUID.
    ///   - name: The human-readable profile name.
    ///   - fieldKeys: The inventory field keys to include in this profile.
    ///   - createdAt: The creation date. Defaults to the current date/time.
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
