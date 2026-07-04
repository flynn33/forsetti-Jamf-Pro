import Foundation

// "End of Line"

/// Actor-isolated persistence for saved computer-search `SmartFilter` instances.
///
/// Mirrors `SmartFilterStore` (mobile) and `ComputerSearchProfileStore`: a JSON
/// file in Application Support, atomic writes, ISO-8601 dates, sorted keys for
/// diffable output. Uses a distinct file name (`computer-smart-filters.json`)
/// so the computer and mobile smart-filter stores never collide and neither
/// needs to migrate when the other changes.
///
/// The persisted model is the shared `SmartFilter` type — it is field-agnostic
/// (key strings only), so the same struct serves both search modules.
actor ComputerSmartFilterStore {
    private let fileManager: FileManager
    private let fileURL: URL

    init(fileManager: FileManager = .default) {
        self.fileManager = fileManager

        let appSupportURL = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? fileManager.urls(for: .documentDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory())

        let directoryURL = appSupportURL.appending(path: "JamfDashboard", directoryHint: .isDirectory)
        self.fileURL = directoryURL.appending(path: "computer-smart-filters.json")
    }

    /// Loads all saved smart filters. Returns an empty array on first run
    /// rather than throwing — same convention as the profile store.
    func loadFilters() throws -> [SmartFilter] {
        try ensureDirectoryExists()

        guard fileManager.fileExists(atPath: fileURL.path) else {
            return []
        }

        let data = try Data(contentsOf: fileURL)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode([SmartFilter].self, from: data)
    }

    /// Persists the filters atomically. Replaces the file content; callers
    /// pass the full sorted list.
    func saveFilters(_ filters: [SmartFilter]) throws {
        try ensureDirectoryExists()

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(filters)
        try data.write(to: fileURL, options: [.atomic])
    }

    private func ensureDirectoryExists() throws {
        let directoryURL = fileURL.deletingLastPathComponent()
        if fileManager.fileExists(atPath: directoryURL.path) == false {
            try fileManager.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        }
    }
}

//endofline
