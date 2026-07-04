import Foundation
import Combine


/// An observable store that manages reading, writing, and deleting Jamf Pro credentials
/// in a platform-secure backing store (Keychain by default). The store publishes a
/// `hasStoredCredentials` flag so SwiftUI views can reactively update when credential
/// state changes (e.g. showing "connected" vs "credentials required" on the dashboard).
///
/// All public methods run on the `@MainActor` to guarantee thread-safe `@Published` updates.
@MainActor
final class JamfCredentialsStore: ObservableObject {
    /// Whether the secure store currently contains a saved set of Jamf credentials.
    /// Views observe this to display connection status indicators.
    @Published private(set) var hasStoredCredentials = false

    /// The underlying secure storage backend (Keychain, in-memory mock, etc.).
    private let secureStore: SecureDataStore
    /// The key used to store and retrieve the encoded credentials blob.
    private let credentialsKey = "jamf.credentials"
    /// JSON encoder used to serialize `JamfCredentials` before saving.
    private let encoder = JSONEncoder()
    /// JSON decoder used to deserialize `JamfCredentials` when loading.
    private let decoder = JSONDecoder()

    /// Creates a credentials store backed by the given secure data store.
    /// Immediately checks whether credentials already exist.
    /// - Parameter secureStore: The storage backend to persist credentials in.
    init(secureStore: SecureDataStore) {
        self.secureStore = secureStore
        refreshState()
    }

    /// Convenience initializer that uses the default `KeychainSecureStore` as the backend.
    convenience init() {
        self.init(secureStore: KeychainSecureStore())
    }

    /// Re-checks the secure store and updates `hasStoredCredentials` to reflect
    /// whether a valid credentials blob currently exists. Call this after external
    /// changes that might affect Keychain state (e.g. app returning from background).
    func refreshState() {
        do {
            hasStoredCredentials = try loadCredentials() != nil
        } catch {
            hasStoredCredentials = false
        }
    }

    /// Loads and decodes the stored Jamf credentials from the secure store.
    /// - Returns: The decoded `JamfCredentials`, or `nil` if none are stored.
    /// - Throws: `JamfFrameworkError.keychainFailure` if the Keychain read fails,
    ///           or a `DecodingError` if the stored data is corrupt.
    func loadCredentials() throws -> JamfCredentials? {
        guard let data = try secureStore.loadData(for: credentialsKey) else {
            return nil
        }

        return try decoder.decode(JamfCredentials.self, from: data)
    }

    /// Validates, sanitizes, encodes, and saves credentials to the secure store.
    /// The credentials are stripped of extraneous whitespace via `storageSanitized`
    /// and must pass the `isComplete` check before they are persisted.
    /// - Parameter credentials: The credentials to save.
    /// - Throws: `JamfFrameworkError.invalidCredentials` if the sanitized credentials
    ///           are incomplete, or a Keychain error if the write fails.
    func saveCredentials(_ credentials: JamfCredentials) throws {
        // Trim whitespace from URL and identifiers before validation
        let sanitizedCredentials = credentials.storageSanitized
        guard sanitizedCredentials.isComplete else {
            throw JamfFrameworkError.invalidCredentials
        }

        let payload = try encoder.encode(sanitizedCredentials)
        try secureStore.save(data: payload, for: credentialsKey)
        hasStoredCredentials = true
    }

    /// Removes all stored Jamf credentials from the secure store and resets the published flag.
    /// - Throws: A Keychain error if the deletion fails for a reason other than "item not found".
    func clearCredentials() throws {
        try secureStore.deleteData(for: credentialsKey)
        hasStoredCredentials = false
    }
}

//endofline
