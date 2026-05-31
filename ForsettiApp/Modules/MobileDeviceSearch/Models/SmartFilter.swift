import Foundation

/// A persisted advanced search query the user has saved by name.
///
/// Distinct from `MobileDeviceSearchProfile` (which only persists the field
/// columns shown in results) so the existing on-disk profile JSON does not
/// need to migrate. The two are coordinated in the search view but stored in
/// separate JSON files for clarity.
struct SmartFilter: Identifiable, Codable, Hashable, Sendable {
    let id: UUID

    /// User-supplied name. Saved verbatim; the picker compares case-insensitively
    /// when looking for a same-name overwrite.
    var name: String

    /// The full query that produced the filter.
    var query: AdvancedQuery

    /// Field column keys captured when the smart filter was saved. Loading a
    /// smart filter restores both the query AND these columns so the user
    /// re-sees the same result columns they had at save time.
    var fieldKeys: [String]

    /// Creation timestamp. Used only for stable sorting; not shown in the UI.
    let createdAt: Date

    init(
        id: UUID = UUID(),
        name: String,
        query: AdvancedQuery,
        fieldKeys: [String] = [],
        createdAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.query = query
        self.fieldKeys = fieldKeys.sorted()
        self.createdAt = createdAt
    }
}

//endofline
