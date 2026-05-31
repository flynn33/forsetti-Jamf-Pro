import Foundation

/// An actor-isolated persistence layer for reading and writing module package manifests to disk.
///
/// `ModulePackageStore` serializes all file I/O through Swift's actor model to prevent
/// data races when multiple callers attempt to load or save concurrently. Packages are
/// stored as a JSON array in Application Support under the app support folder.
/// Falls back to the Documents directory or the system temp directory if Application Support
/// is unavailable.
actor ModulePackageStore {
    /// The file manager used for directory creation and existence checks.
    private let fileManager: FileManager
    /// The resolved file URL where the package manifest array is persisted.
    private let fileURL: URL

    /// Creates a new store, resolving the storage file URL from the system's standard directories by default.
    ///
    /// The directory hierarchy is created lazily (on first load or save), not at init time.
    /// Tests may pass an explicit file URL so package-manager scenarios never touch
    /// the user's real Application Support package list.
    init(fileURL: URL? = nil, fileManager: FileManager = .default) {
        self.fileManager = fileManager
        if let fileURL {
            self.fileURL = fileURL
            return
        }

        // Prefer Application Support, fall back to Documents, then temp
        let appSupportURL = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
        let documentURL = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first

        let baseDirectoryURL = appSupportURL
            ?? documentURL
            ?? URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)

        let moduleDirectoryURL = baseDirectoryURL.appending(path: ForsettiAppIdentity.applicationSupportFolder, directoryHint: .isDirectory)
        self.fileURL = moduleDirectoryURL.appending(path: "installed-module-packages.json")
    }

    /// Loads all persisted module package manifests from disk.
    ///
    /// Returns an empty array if the file does not exist yet (first launch).
    /// The parent directory is created if it is missing.
    ///
    /// - Returns: An array of decoded `ModulePackageManifest` values.
    /// - Throws: File I/O or JSON decoding errors.
    func loadPackages() throws -> [ModulePackageManifest] {
        try ensureDirectoryExists()

        guard fileManager.fileExists(atPath: fileURL.path) else {
            return []
        }

        let data = try Data(contentsOf: fileURL)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        return try decoder.decode([ModulePackageManifest].self, from: data)
    }

    /// Persists the given array of module package manifests to disk as pretty-printed JSON.
    ///
    /// The write is atomic to prevent partial-file corruption if the app is interrupted.
    ///
    /// - Parameter packages: The complete list of manifests to save.
    /// - Throws: File I/O or JSON encoding errors.
    func savePackages(_ packages: [ModulePackageManifest]) throws {
        try ensureDirectoryExists()

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601

        let data = try encoder.encode(packages)
        try data.write(to: fileURL, options: [.atomic])
    }

    /// Creates the parent directory for the storage file if it does not already exist.
    ///
    /// Uses `withIntermediateDirectories: true` so the full path is created in one call.
    ///
    /// - Throws: File system errors if directory creation fails.
    private func ensureDirectoryExists() throws {
        let directoryURL = fileURL.deletingLastPathComponent()

        if fileManager.fileExists(atPath: directoryURL.path) == false {
            try fileManager.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        }
    }
}

//endofline
