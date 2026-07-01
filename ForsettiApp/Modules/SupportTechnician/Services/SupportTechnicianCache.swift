import Foundation

/// Persistent local cache for the Support Technician module.
///
/// Keeps a disk-backed copy of every fetched device-detail payload and
/// every fetched tenant-wide policy list, keyed by device id. The module
/// hits this cache before going to Jamf Pro so repeated visits to the
/// same device don't hammer the server. Refresh / Clear Cache toolbar
/// buttons drive forced re-fetches and total purges.
///
/// Cache location:
///   `<sandbox-Caches>/SupportTechnician/`
/// inside the sandboxed `~/Library/Containers/com.forsetti.jamfdashboard`
/// container. Files are written atomically so a crash mid-write can't
/// leave partial JSON behind.
actor SupportTechnicianCache {
    private let folderURL: URL
    private let fileManager: FileManager
    private static let detailPrefix = "device-detail-"
    private static let policiesFilename = "tenant-policies.json"
    private static let extensionAttributePrefix = "extension-attributes-"
    /// Default cache age — entries younger than this are considered fresh
    /// enough to skip the network. Beyond it, fetchers will re-fetch and
    /// overwrite. The user can still bypass entirely via the Refresh
    /// button (which forces `bypassCache: true`) or Clear Cache.
    private let defaultMaxAge: TimeInterval

    init(maxAge: TimeInterval = 300) {
        self.fileManager = FileManager.default
        self.defaultMaxAge = maxAge

        // Caches dir is the right place for regenerable data; macOS may
        // purge it under disk pressure, which is fine — we'll just re-
        // fetch on next access.
        let cachesRoot = fileManager.urls(for: .cachesDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
        self.folderURL = cachesRoot.appendingPathComponent("SupportTechnician", isDirectory: true)
        try? fileManager.createDirectory(at: folderURL, withIntermediateDirectories: true)
    }

    // MARK: - Device-detail payload cache

    /// Returns the cached raw-JSON payload for a device id, or nil if no
    /// fresh entry exists. "Fresh" is governed by `maxAge` — older
    /// entries are treated as cache misses but left on disk for the next
    /// fetch to overwrite.
    func cachedPayload(forDeviceID id: String, maxAge: TimeInterval? = nil) -> String? {
        let url = detailURL(forDeviceID: id)
        guard fileManager.fileExists(atPath: url.path) else { return nil }
        let limit = maxAge ?? defaultMaxAge
        if let attributes = try? fileManager.attributesOfItem(atPath: url.path),
           let modified = attributes[.modificationDate] as? Date,
           Date().timeIntervalSince(modified) > limit
        {
            return nil
        }
        return try? String(contentsOf: url, encoding: .utf8)
    }

    /// Persists a freshly-fetched payload to disk. Writes atomically.
    func storePayload(_ rawJSON: String, forDeviceID id: String) {
        let url = detailURL(forDeviceID: id)
        try? rawJSON.write(to: url, atomically: true, encoding: .utf8)
    }

    /// Returns the on-disk modification date of the cached payload, if
    /// any. Used by the UI to display a "cached at" timestamp next to
    /// the Refresh button.
    func cachedPayloadTimestamp(forDeviceID id: String) -> Date? {
        let url = detailURL(forDeviceID: id)
        guard fileManager.fileExists(atPath: url.path),
              let attributes = try? fileManager.attributesOfItem(atPath: url.path),
              let modified = attributes[.modificationDate] as? Date
        else { return nil }
        return modified
    }

    // MARK: - Tenant policies cache

    /// Cached tenant-wide policy list. Same maxAge semantics as the
    /// per-device payload cache.
    func cachedPolicies(maxAge: TimeInterval? = nil) -> Data? {
        let url = folderURL.appendingPathComponent(Self.policiesFilename)
        guard fileManager.fileExists(atPath: url.path) else { return nil }
        let limit = maxAge ?? defaultMaxAge
        if let attributes = try? fileManager.attributesOfItem(atPath: url.path),
           let modified = attributes[.modificationDate] as? Date,
           Date().timeIntervalSince(modified) > limit
        {
            return nil
        }
        return try? Data(contentsOf: url)
    }

    func storePolicies(_ data: Data) {
        let url = folderURL.appendingPathComponent(Self.policiesFilename)
        try? data.write(to: url, options: .atomic)
    }

    // MARK: - Extension attribute catalog cache

    /// Cached tenant-wide extension-attribute catalogs, separated by asset
    /// type (`computer`, `mobile`, etc.) so advanced-field metadata can be
    /// reused without re-querying Jamf on every device-detail visit.
    func cachedExtensionAttributeCatalog(key: String, maxAge: TimeInterval? = nil) -> Data? {
        let url = extensionAttributeCatalogURL(forKey: key)
        guard fileManager.fileExists(atPath: url.path) else { return nil }
        let limit = maxAge ?? defaultMaxAge
        if let attributes = try? fileManager.attributesOfItem(atPath: url.path),
           let modified = attributes[.modificationDate] as? Date,
           Date().timeIntervalSince(modified) > limit
        {
            return nil
        }
        return try? Data(contentsOf: url)
    }

    func storeExtensionAttributeCatalog(_ data: Data, key: String) {
        let url = extensionAttributeCatalogURL(forKey: key)
        try? data.write(to: url, options: .atomic)
    }

    // MARK: - Wipe

    /// Removes every file in the cache directory. Called by the Clear
    /// Cache toolbar button.
    func clearAll() {
        guard let entries = try? fileManager.contentsOfDirectory(at: folderURL, includingPropertiesForKeys: nil) else {
            return
        }
        for entry in entries {
            try? fileManager.removeItem(at: entry)
        }
    }

    /// Summary used by the UI to render cache state — count + bytes on
    /// disk. Cheap to compute (single directory listing).
    func summary() -> CacheSummary {
        guard let entries = try? fileManager.contentsOfDirectory(
            at: folderURL,
            includingPropertiesForKeys: [.fileSizeKey]
        ) else {
            return CacheSummary(fileCount: 0, totalBytes: 0)
        }
        var bytes = 0
        for entry in entries {
            if let attributes = try? fileManager.attributesOfItem(atPath: entry.path),
               let size = attributes[.size] as? Int
            {
                bytes += size
            }
        }
        return CacheSummary(fileCount: entries.count, totalBytes: bytes)
    }

    // MARK: - Helpers

    private func detailURL(forDeviceID id: String) -> URL {
        let safeID = id.replacingOccurrences(of: "/", with: "_")
        return folderURL.appendingPathComponent("\(Self.detailPrefix)\(safeID).json")
    }

    private func extensionAttributeCatalogURL(forKey key: String) -> URL {
        let safeKey = key
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: ":", with: "_")
        return folderURL.appendingPathComponent("\(Self.extensionAttributePrefix)\(safeKey).json")
    }
}

/// Lightweight summary of what's on disk. Surfaced by the UI in a tooltip
/// on the Clear Cache button so the user knows what they're about to
/// purge.
nonisolated struct CacheSummary: Sendable, Hashable {
    let fileCount: Int
    let totalBytes: Int

    var humanReadableSize: String {
        if totalBytes >= 1_048_576 {
            return String(format: "%.1f MB", Double(totalBytes) / 1_048_576.0)
        }
        if totalBytes >= 1024 {
            return String(format: "%.0f KB", Double(totalBytes) / 1024.0)
        }
        return "\(totalBytes) B"
    }
}

//endofline
