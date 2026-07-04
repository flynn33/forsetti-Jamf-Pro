import Foundation

// "Klatu-barada-Nikto"

/// An actor-isolated store responsible for reading and writing `ComputerSearchProfile` instances to disk.
///
/// Profiles are serialized as a JSON array and stored in the app's Application Support directory
/// under `JamfDashboard/computer-search-profiles.json`. The actor isolation guarantees that
/// concurrent reads and writes from different tasks are safely serialized, preventing data races.
actor ComputerSearchProfileStore {
    /// The file manager used for directory creation and file existence checks.
    private let fileManager: FileManager

    /// The fully-resolved file URL where the JSON profile array is persisted.
    private let fileURL: URL

    /// Creates a new profile store, resolving the storage path from the system's Application Support directory.
    ///
    /// Falls back to the Documents directory, then to the temporary directory, if Application Support
    /// is unavailable. Ensures a `JamfDashboard` subdirectory is used to keep files organized.
    ///
    /// - Parameter fileManager: The file manager to use for filesystem operations. Defaults to `.default`.
    init(fileManager: FileManager = .default) {
        self.fileManager = fileManager

        // Resolve the best available base directory for persistent storage
        let appSupportURL = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? fileManager.urls(for: .documentDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory())

        let directoryURL = appSupportURL.appending(path: "JamfDashboard", directoryHint: .isDirectory)
        self.fileURL = directoryURL.appending(path: "computer-search-profiles.json")
    }

    /// Loads all saved search profiles from disk.
    ///
    /// If the profile file does not yet exist (first launch), an empty array is returned.
    /// The JSON is decoded using ISO 8601 date formatting to match the encoding strategy.
    ///
    /// - Returns: An array of previously saved `ComputerSearchProfile` instances.
    /// - Throws: An error if the file exists but cannot be read or decoded.
    func loadProfiles() throws -> [ComputerSearchProfile] {
        // Make sure the parent directory is in place before attempting to read
        try ensureDirectoryExists()

        guard fileManager.fileExists(atPath: fileURL.path) else {
            return []
        }

        let data = try Data(contentsOf: fileURL)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        return try decoder.decode([ComputerSearchProfile].self, from: data)
    }

    /// Persists the given array of search profiles to disk, replacing any previously saved data.
    ///
    /// The JSON output is pretty-printed with sorted keys for human readability and
    /// deterministic diffs. The write is atomic to prevent partial-write corruption.
    ///
    /// - Parameter profiles: The complete list of profiles to save.
    /// - Throws: An error if the directory cannot be created or the data cannot be written.
    func saveProfiles(_ profiles: [ComputerSearchProfile]) throws {
        try ensureDirectoryExists()

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601

        let data = try encoder.encode(profiles)
        // Atomic write prevents data loss if the app crashes mid-write
        try data.write(to: fileURL, options: [.atomic])
    }

    /// Creates the parent directory for the profile file if it does not already exist.
    ///
    /// Uses `withIntermediateDirectories: true` so nested paths are created in one call.
    ///
    /// - Throws: An error if the directory cannot be created.
    private func ensureDirectoryExists() throws {
        let directoryURL = fileURL.deletingLastPathComponent()

        if fileManager.fileExists(atPath: directoryURL.path) == false {
            try fileManager.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        }
    }
}

//endofline
