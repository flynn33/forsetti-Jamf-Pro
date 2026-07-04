import Foundation


/// An actor-isolated store responsible for reading and writing `MobileDeviceSearchProfile`
/// arrays to a JSON file on disk.
///
/// `MobileDeviceSearchProfileStore` persists profiles to the Application Support directory
/// under `JamfDashboard/mobile-device-search-profiles.json`. It uses `actor` isolation to
/// guarantee thread-safe file access, since profiles may be loaded, saved, or deleted from
/// different async contexts (e.g. view model tasks triggered by user interaction).
///
/// The store lazily creates the parent directory if it does not already exist, and uses
/// atomic writes to prevent data corruption from interrupted save operations.
actor MobileDeviceSearchProfileStore {
    /// The file manager used for directory creation and existence checks.
    private let fileManager: FileManager

    /// The resolved file URL where the profiles JSON is stored.
    private let fileURL: URL

    /// Creates a new profile store.
    ///
    /// The storage path is resolved by looking for the Application Support directory first,
    /// then falling back to Documents, and finally to the temporary directory as a last resort.
    /// A `JamfDashboard` subdirectory is appended to isolate this app's data.
    ///
    /// - Parameter fileManager: The file manager to use. Defaults to `.default`.
    init(fileManager: FileManager = .default) {
        self.fileManager = fileManager

        // Resolve the base directory with a cascading fallback strategy
        let appSupportURL = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? fileManager.urls(for: .documentDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory())

        let directoryURL = appSupportURL.appending(path: "JamfDashboard", directoryHint: .isDirectory)
        self.fileURL = directoryURL.appending(path: "mobile-device-search-profiles.json")
    }

    /// Loads all saved search profiles from disk.
    ///
    /// If the profiles file does not yet exist (first launch), an empty array is returned
    /// rather than throwing an error. The JSON is decoded using ISO 8601 date formatting
    /// to match the encoding strategy used by `saveProfiles(_:)`.
    ///
    /// - Returns: An array of previously saved profiles, or an empty array if none exist.
    /// - Throws: File system or JSON decoding errors if the file exists but cannot be read.
    func loadProfiles() throws -> [MobileDeviceSearchProfile] {
        try ensureDirectoryExists()

        guard fileManager.fileExists(atPath: fileURL.path) else {
            return []
        }

        let data = try Data(contentsOf: fileURL)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        return try decoder.decode([MobileDeviceSearchProfile].self, from: data)
    }

    /// Persists the given array of search profiles to disk as pretty-printed JSON.
    ///
    /// The write uses the `.atomic` option so the file is either fully written or left
    /// unchanged, preventing partial writes from corrupting saved data. Keys are sorted
    /// in the output for stable, diffable JSON.
    ///
    /// - Parameter profiles: The complete list of profiles to save (replaces existing file).
    /// - Throws: File system or JSON encoding errors.
    func saveProfiles(_ profiles: [MobileDeviceSearchProfile]) throws {
        try ensureDirectoryExists()

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601

        let data = try encoder.encode(profiles)
        try data.write(to: fileURL, options: [.atomic])
    }

    /// Creates the parent directory for the profiles file if it does not already exist.
    ///
    /// Called before every read and write to ensure the directory structure is in place,
    /// even on first launch or after the user has cleared app data.
    private func ensureDirectoryExists() throws {
        let directoryURL = fileURL.deletingLastPathComponent()

        if fileManager.fileExists(atPath: directoryURL.path) == false {
            try fileManager.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        }
    }
}

//endofline
