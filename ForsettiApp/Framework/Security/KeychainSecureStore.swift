import Foundation
import Security

/// A protocol that abstracts secure binary data storage, allowing different backends
/// (Keychain, in-memory, or mock stores) to be swapped in for production use or testing.
nonisolated protocol SecureDataStore: Sendable {
    /// Persists a binary `Data` blob under the given key, replacing any existing value.
    /// - Parameters:
    ///   - data: The raw bytes to store.
    ///   - key: A unique string identifier for this item.
    /// - Throws: An error if the storage operation fails.
    func save(data: Data, for key: String) throws

    /// Retrieves the binary data previously stored under the given key.
    /// - Parameter key: The unique string identifier for the item.
    /// - Returns: The stored `Data`, or `nil` if no item exists for the key.
    /// - Throws: An error if the read operation fails (other than "not found").
    func loadData(for key: String) throws -> Data?

    /// Deletes the item stored under the given key.
    /// - Parameter key: The unique string identifier for the item to remove.
    /// - Throws: An error if the deletion fails (other than "item not found").
    func deleteData(for key: String) throws
}

/// A concrete `SecureDataStore` implementation backed by the iOS/macOS Keychain.
/// Items are stored as generic passwords scoped to a service identifier, accessible
/// only when the device is unlocked (`kSecAttrAccessibleWhenUnlockedThisDeviceOnly`),
/// and are not eligible for iCloud Keychain sync.
nonisolated final class KeychainSecureStore: SecureDataStore, @unchecked Sendable {
    /// The Keychain service identifier used to namespace all stored items.
    private let service: String

    /// Creates a Keychain store scoped to the given service identifier.
    /// - Parameter service: The Keychain service string. Defaults to the app bundle identifier.
    init(service: String = ForsettiAppIdentity.bundleIdentifier) {
        self.service = service
    }

    /// Saves binary data to the Keychain under the specified key.
    /// Any pre-existing item with the same key is deleted first (upsert behavior).
    /// - Parameters:
    ///   - data: The raw bytes to persist.
    ///   - key: A unique string key for the Keychain item.
    /// - Throws: `JamfFrameworkError.keychainFailure` if `SecItemAdd` returns a non-success status.
    func save(data: Data, for key: String) throws {
        let query = keychainQuery(for: key)
        // Delete any existing item first to avoid errSecDuplicateItem
        SecItemDelete(query as CFDictionary)

        var attributes = query
        attributes[kSecValueData as String] = data

        let status = SecItemAdd(attributes as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw JamfFrameworkError.keychainFailure(status: status)
        }
    }

    /// Loads binary data from the Keychain for the specified key.
    /// - Parameter key: The unique string key for the Keychain item.
    /// - Returns: The stored `Data`, or `nil` if no matching item exists.
    /// - Throws: `JamfFrameworkError.keychainFailure` for unexpected Keychain errors.
    func loadData(for key: String) throws -> Data? {
        var query = keychainQuery(for: key)
        // Request the data payload and limit to a single match
        query[kSecReturnData as String] = kCFBooleanTrue
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var item: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &item)

        switch status {
        case errSecSuccess:
            return item as? Data
        case errSecItemNotFound:
            return nil
        default:
            throw JamfFrameworkError.keychainFailure(status: status)
        }
    }

    /// Deletes the Keychain item for the specified key.
    /// Silently succeeds if the item does not exist (`errSecItemNotFound` is not an error).
    /// - Parameter key: The unique string key for the Keychain item to remove.
    /// - Throws: `JamfFrameworkError.keychainFailure` for unexpected Keychain errors.
    func deleteData(for key: String) throws {
        let status = SecItemDelete(keychainQuery(for: key) as CFDictionary)

        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw JamfFrameworkError.keychainFailure(status: status)
        }
    }

    /// Builds the base Keychain query dictionary for a given key. All items are stored
    /// as generic passwords (`kSecClassGenericPassword`) scoped to this store's service,
    /// keyed by account name, and restricted to device-only access while unlocked.
    /// - Parameter key: The account/key string to query for.
    /// - Returns: A dictionary suitable for use with Security framework functions.
    private func keychainQuery(for key: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        ]
    }
}

//endofline
