import Foundation

/// ID → name lookups for buildings and departments.
///
/// Jamf Pro's `api/v1/computers-inventory` response carries numeric
/// `userAndLocation.buildingId` / `departmentId` values, not the
/// human-readable names. This directory is fetched once per report load
/// from `api/v1/buildings` and `api/v1/departments` and used to resolve
/// IDs into names before display and client-side matching.
struct ReportsLocationDirectory: Sendable, Hashable {
    let buildings: [String: String]
    let departments: [String: String]

    nonisolated static let empty = ReportsLocationDirectory(buildings: [:], departments: [:])

    nonisolated func buildingName(for id: String?) -> String? {
        lookup(id, in: buildings)
    }

    nonisolated func departmentName(for id: String?) -> String? {
        lookup(id, in: departments)
    }

    nonisolated private func lookup(_ id: String?, in table: [String: String]) -> String? {
        guard let id else { return nil }
        let trimmed = id.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.isEmpty == false else { return nil }
        return table[trimmed]
    }
}
