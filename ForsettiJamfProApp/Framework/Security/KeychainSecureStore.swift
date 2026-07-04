import Foundation
import Security

// "A robot may not injure a human being or, through inaction, allow a human being to come to harm.
//  A robot must obey the orders given it by human beings except where such orders would conflict with the First Law.
//  A robot must protect its own existence as long as such protection does not conflict with the First or Second Law."

/// A protocol that abstracts secure binary data storage, allowing different backends
/// (Keychain, in-memory, or mock stores) to be swapped in for production use or testing.
protocol SecureDataStore {
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
final class KeychainSecureStore: SecureDataStore {
    /// The Keychain service identifier used to namespace all stored items.
    private let service: String

    /// Creates a Keychain store scoped to the given service identifier.
    /// - Parameter service: The Keychain service string. Defaults to `"com.forsetti.jamfpro"`.
    init(service: String = "com.forsetti.jamfpro") {
        self.service = service
    }

    /// Saves binary data to the Keychain under the specified key, creating the item if it
    /// does not yet exist and updating it in place if it does (upsert behavior).
    ///
    /// The existing-item lookup uses only the primary-key attributes (class, service,
    /// account). `kSecAttrAccessible` is applied as a *value* on add/update — never as a
    /// search key — because including it in a search query can stop an already-stored item
    /// from matching, which then surfaces as `errSecDuplicateItem` on the add. Adding first
    /// and falling back to `SecItemUpdate` on duplicate is the upsert this method guarantees.
    /// - Parameters:
    ///   - data: The raw bytes to persist.
    ///   - key: A unique string key for the Keychain item.
    /// - Throws: `JamfFrameworkError.keychainFailure` if the add or the update returns a
    ///           non-success status.
    func save(data: Data, for key: String) throws {
        let query = keychainQuery(for: key)

        // Try to add the item first, stamping it with device-only-while-unlocked access.
        var addAttributes = query
        addAttributes[kSecValueData as String] = data
        addAttributes[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly

        let addStatus = SecItemAdd(addAttributes as CFDictionary, nil)

        switch addStatus {
        case errSecSuccess:
            return
        case errSecDuplicateItem:
            // An item already exists for this key — update its stored data in place
            // rather than failing.
            let updateAttributes: [String: Any] = [
                kSecValueData as String: data,
                kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly
            ]
            let updateStatus = SecItemUpdate(query as CFDictionary, updateAttributes as CFDictionary)
            guard updateStatus == errSecSuccess else {
                throw JamfFrameworkError.keychainFailure(status: updateStatus)
            }
        default:
            throw JamfFrameworkError.keychainFailure(status: addStatus)
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

    /// Builds the primary-key Keychain query dictionary for a given key. Items are stored
    /// as generic passwords (`kSecClassGenericPassword`) scoped to this store's service and
    /// keyed by account name — the attributes that uniquely identify an item, so this query
    /// is suitable for lookup, update, and delete.
    ///
    /// `kSecAttrAccessible` is intentionally omitted: it is a value set when an item is added
    /// or updated, not a valid search key. Including it here can stop a lookup, update, or
    /// delete from matching an existing item. The accessibility value is applied in `save`.
    /// - Parameter key: The account/key string to query for.
    /// - Returns: A dictionary suitable for use with Security framework functions.
    private func keychainQuery(for key: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key
        ]
    }
}

//endofline
