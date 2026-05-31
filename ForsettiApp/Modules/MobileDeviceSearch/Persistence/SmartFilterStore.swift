import Foundation

/// Actor-isolated persistence for saved `SmartFilter` instances.
///
/// Mirrors the shape of `MobileDeviceSearchProfileStore` for consistency:
/// JSON file in Application Support, atomic writes, ISO-8601 dates, sorted
/// keys for diffable output. Distinct file path so neither store needs to
/// migrate when the other changes.
actor SmartFilterStore {
    private let fileManager: FileManager
    private let fileURL: URL

    init(fileManager: FileManager = .default, fileName: String = "mobile-device-smart-filters.json") {
        self.fileManager = fileManager

        let appSupportURL = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? fileManager.urls(for: .documentDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory())

        let directoryURL = appSupportURL.appending(path: ForsettiAppIdentity.applicationSupportFolder, directoryHint: .isDirectory)
        self.fileURL = directoryURL.appending(path: fileName)
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
