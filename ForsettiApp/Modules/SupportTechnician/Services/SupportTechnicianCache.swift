import CryptoKit
import Foundation

/// Persistent local cache for the Support Technician module.
///
/// Keeps encrypted disk-backed copies of fetched device-detail payloads,
/// tenant-wide policy lists, and extension-attribute catalogs. The module hits
/// this cache before going to Jamf Pro so repeated visits to the same device
/// don't hammer the server. Refresh / Clear Cache toolbar buttons drive forced
/// re-fetches and total purges.
///
/// Cache location:
///   `<sandbox-Caches>/SupportTechnician/`
/// inside the sandboxed `~/Library/Containers/com.ravenforge.forsetti`
/// container. Files are written atomically so a crash mid-write can't
/// leave partial JSON behind.
actor SupportTechnicianCache {
    private let folderURL: URL
    private let fileManager: FileManager
    private let secureStore: SecureDataStore
    private static let encryptionKeyIdentifier = "support-technician-cache-key-v1"
    private static let detailPrefix = "device-detail-"
    private static let policiesFilename = "tenant-policies.cache"
    private static let extensionAttributePrefix = "extension-attributes-"
    /// Default cache age — entries younger than this are considered fresh
    /// enough to skip the network. Beyond it, fetchers will re-fetch and
    /// overwrite. The user can still bypass entirely via the Refresh
    /// button (which forces `bypassCache: true`) or Clear Cache.
    private let defaultMaxAge: TimeInterval

    init(
        maxAge: TimeInterval = 300,
        secureStore: SecureDataStore = KeychainSecureStore(service: "\(ForsettiAppIdentity.bundleIdentifier).support-cache"),
        folderURL: URL? = nil
    ) {
        self.fileManager = FileManager.default
        self.defaultMaxAge = maxAge
        self.secureStore = secureStore

        // Caches dir is the right place for regenerable data; macOS may
        // purge it under disk pressure, which is fine — we'll just re-
        // fetch on next access.
        let cachesRoot = fileManager.urls(for: .cachesDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
        self.folderURL = folderURL ?? cachesRoot.appendingPathComponent("SupportTechnician", isDirectory: true)
        try? fileManager.createDirectory(at: self.folderURL, withIntermediateDirectories: true)
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
        guard let data = try? Data(contentsOf: url) else {
            return nil
        }
        guard let decrypted = decryptCachedPayload(data) else {
            try? fileManager.removeItem(at: url)
            return nil
        }
        return String(data: decrypted, encoding: .utf8)
    }

    /// Persists a freshly-fetched payload to disk. Writes encrypted bytes atomically.
    func storePayload(_ rawJSON: String, forDeviceID id: String) {
        let url = detailURL(forDeviceID: id)
        guard let encrypted = encryptCachedPayload(Data(rawJSON.utf8)) else {
            return
        }
        try? encrypted.write(to: url, options: .atomic)
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
        guard let data = try? Data(contentsOf: url) else {
            return nil
        }
        guard let decrypted = decryptCachedPayload(data) else {
            try? fileManager.removeItem(at: url)
            return nil
        }
        return decrypted
    }

    func storePolicies(_ data: Data) {
        let url = folderURL.appendingPathComponent(Self.policiesFilename)
        guard let encrypted = encryptCachedPayload(data) else {
            return
        }
        try? encrypted.write(to: url, options: .atomic)
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
        guard let data = try? Data(contentsOf: url) else {
            return nil
        }
        guard let decrypted = decryptCachedPayload(data) else {
            try? fileManager.removeItem(at: url)
            return nil
        }
        return decrypted
    }

    func storeExtensionAttributeCatalog(_ data: Data, key: String) {
        let url = extensionAttributeCatalogURL(forKey: key)
        guard let encrypted = encryptCachedPayload(data) else {
            return
        }
        try? encrypted.write(to: url, options: .atomic)
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
        return folderURL.appendingPathComponent("\(Self.detailPrefix)\(safeID).cache")
    }

    private func encryptionKey() throws -> SymmetricKey {
        if let data = try secureStore.loadData(for: Self.encryptionKeyIdentifier) {
            return SymmetricKey(data: data)
        }

        let key = SymmetricKey(size: .bits256)
        let data = key.withUnsafeBytes { Data($0) }
        try secureStore.save(data: data, for: Self.encryptionKeyIdentifier)
        return key
    }

    private func encryptCachedPayload(_ data: Data) -> Data? {
        guard let key = try? encryptionKey(),
              let combined = try? AES.GCM.seal(data, using: key).combined
        else {
            return nil
        }
        return combined
    }

    private func decryptCachedPayload(_ data: Data) -> Data? {
        guard let key = try? encryptionKey(),
              let sealedBox = try? AES.GCM.SealedBox(combined: data),
              let opened = try? AES.GCM.open(sealedBox, using: key)
        else {
            return nil
        }
        return opened
    }

    private func extensionAttributeCatalogURL(forKey key: String) -> URL {
        let safeKey = key
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: ":", with: "_")
        return folderURL.appendingPathComponent("\(Self.extensionAttributePrefix)\(safeKey).cache")
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
