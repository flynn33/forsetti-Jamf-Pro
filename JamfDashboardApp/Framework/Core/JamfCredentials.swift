import Foundation

/// Holds all credential fields needed to authenticate with a Jamf Pro server.
///
/// `JamfCredentials` supports two authentication flows -- API Client (OAuth
/// client credentials) and Username/Password (basic auth). Only the fields
/// relevant to the selected `authenticationMethod` need to be populated.
///
/// The struct is `Codable` for persistence, `Equatable` for diffing, and
/// `Sendable` for safe cross-isolation transfer.
struct JamfCredentials: Codable, Equatable, Sendable {

    // "Would you like to play a game?"

    /// The supported Jamf Pro authentication methods.
    enum AuthenticationMethod: String, Codable, CaseIterable, Sendable {
        /// OAuth 2.0 client-credentials flow using a client ID and secret.
        case apiClient
        /// Traditional username and password basic authentication.
        case usernamePassword

        /// A human-readable label suitable for display in the UI.
        var displayName: String {
            switch self {
            case .apiClient:
                return "API Client"
            case .usernamePassword:
                return "Username & Password"
            }
        }
    }

    /// The base URL of the Jamf Pro server (e.g., "https://yourorg.jamfcloud.com").
    var serverURL: String
    /// The currently selected authentication method.
    var authenticationMethod: AuthenticationMethod
    /// The OAuth client identifier (used with `.apiClient`).
    var clientID: String
    /// The OAuth client secret (used with `.apiClient`).
    var clientSecret: String
    /// The account username (used with `.usernamePassword`).
    var accountUsername: String
    /// The account password (used with `.usernamePassword`).
    var accountPassword: String
    /// Optional OAuth scope to restrict the token's privilege set (used with `.apiClient`).
    /// When empty, the token includes all roles allowed for the API client.
    var oauthScope: String

    /// Explicit coding keys matching the JSON property names for persistence.
    private enum CodingKeys: String, CodingKey {
        case serverURL
        case authenticationMethod
        case clientID
        case clientSecret
        case accountUsername
        case accountPassword
        case oauthScope
    }

    /// Memberwise initializer providing all credential fields directly.
    nonisolated init(
        serverURL: String,
        authenticationMethod: AuthenticationMethod,
        clientID: String,
        clientSecret: String,
        accountUsername: String,
        accountPassword: String,
        oauthScope: String = ""
    ) {
        self.serverURL = serverURL
        self.authenticationMethod = authenticationMethod
        self.clientID = clientID
        self.clientSecret = clientSecret
        self.accountUsername = accountUsername
        self.accountPassword = accountPassword
        self.oauthScope = oauthScope
    }

    /// Decodes credentials from a persisted representation.
    ///
    /// If `authenticationMethod` is missing from the payload (e.g., older stored
    /// data), the method is inferred from which credential fields are populated.
    nonisolated init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        serverURL = try container.decode(String.self, forKey: .serverURL)
        clientID = try container.decode(String.self, forKey: .clientID)
        clientSecret = try container.decode(String.self, forKey: .clientSecret)
        accountUsername = try container.decode(String.self, forKey: .accountUsername)
        accountPassword = try container.decode(String.self, forKey: .accountPassword)
        oauthScope = (try? container.decodeIfPresent(String.self, forKey: .oauthScope)) ?? ""

        // Attempt to decode the auth method; fall back to inference for legacy data
        if let decodedMethod = try container.decodeIfPresent(AuthenticationMethod.self, forKey: .authenticationMethod) {
            authenticationMethod = decodedMethod
        } else {
            authenticationMethod = Self.inferAuthenticationMethod(
                clientID: clientID,
                clientSecret: clientSecret,
                accountUsername: accountUsername,
                accountPassword: accountPassword
            )
        }
    }

    // MARK: - Computed Helpers

    /// Returns a canonical tenant root URL built from `serverURL`:
    /// scheme + host + optional port, with any path/query/fragment stripped.
    /// Returns `nil` if the string is empty or unparseable.
    ///
    /// Jamf's instance root is documented as scheme+host (e.g.
    /// `https://tenant.jamfcloud.com`), and the Jamf Pro API lives at
    /// `/api/...` under that root. If the stored `serverURL` contains a path
    /// segment (common mistake: an operator saves `https://tenant.jamfcloud.com/api`
    /// because that's what they see in their browser bar), subsequent request
    /// building produced malformed URLs like `.../api/api/v1/...` and every
    /// request silently 404'd. Canonicalizing to scheme + host (+ port)
    /// eliminates that class of configuration error.
    ///
    /// Also rejects non-http(s) schemes so a garbled `file://` or similar
    /// string doesn't produce a URL that `session.data(for:)` will later
    /// throw on in a less actionable way.
    nonisolated var normalizedServerURL: URL? {
        var rawValue = serverURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard rawValue.isEmpty == false else {
            return nil
        }

        // If the operator provided an explicit scheme, it must be
        // http(s). Silently rewriting `file://…` or `ftp://…` to
        // `https://…` — the prior behavior — masked a misconfiguration
        // and produced a URL like `https://file` that failed obscurely
        // at request time. Reject up front.
        if rawValue.contains("://") {
            if rawValue.hasPrefix("http://") == false && rawValue.hasPrefix("https://") == false {
                return nil
            }
        } else {
            // No scheme at all → default to HTTPS.
            rawValue = "https://\(rawValue)"
        }

        guard let parsed = URL(string: rawValue),
              let scheme = parsed.scheme?.lowercased(),
              ["http", "https"].contains(scheme),
              let host = parsed.host,
              host.isEmpty == false
        else {
            return nil
        }

        var components = URLComponents()
        components.scheme = scheme
        components.host = host
        components.port = parsed.port
        // NOTE: deliberately NOT carrying over parsed.path / query / fragment.
        // The canonical Jamf tenant URL is scheme + host (+ port) only; any
        // path segment in the stored URL is a misconfiguration that would
        // compound with the `/api/...` paths the gateway appends per request.
        return components.url
    }

    /// `true` when both the client ID and client secret are non-empty after trimming.
    nonisolated var apiClientCredentialsAreComplete: Bool {
        clientID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false &&
        clientSecret.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
    }

    /// `true` when both the username and password are non-empty after trimming.
    nonisolated var accountCredentialsAreComplete: Bool {
        accountUsername.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false &&
        accountPassword.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
    }

    /// `true` when the credential fields for the *currently selected* authentication
    /// method are fully populated.
    nonisolated var selectedAuthenticationCredentialsAreComplete: Bool {
        switch authenticationMethod {
        case .apiClient:
            return apiClientCredentialsAreComplete
        case .usernamePassword:
            return accountCredentialsAreComplete
        }
    }

    /// `true` when the server URL is non-empty AND the selected auth credentials
    /// are complete -- i.e., enough information to attempt a connection.
    nonisolated var isComplete: Bool {
        serverURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false &&
        selectedAuthenticationCredentialsAreComplete
    }

    /// Returns a copy of this credential set with unused authentication fields
    /// blanked out, suitable for secure storage.
    ///
    /// For example, when `.apiClient` is selected the username and password are
    /// cleared so they are never persisted unnecessarily.
    nonisolated var storageSanitized: JamfCredentials {
        switch authenticationMethod {
        case .apiClient:
            return JamfCredentials(
                serverURL: serverURL,
                authenticationMethod: .apiClient,
                clientID: clientID,
                clientSecret: clientSecret,
                accountUsername: "",
                accountPassword: "",
                oauthScope: oauthScope
            )
        case .usernamePassword:
            return JamfCredentials(
                serverURL: serverURL,
                authenticationMethod: .usernamePassword,
                clientID: "",
                clientSecret: "",
                accountUsername: accountUsername,
                accountPassword: accountPassword,
                oauthScope: ""
            )
        }
    }

    // MARK: - Private Helpers

    /// Infers the authentication method by checking which set of credential
    /// fields is populated. Prefers `.usernamePassword` when only account
    /// fields are filled; defaults to `.apiClient` otherwise.
    nonisolated private static func inferAuthenticationMethod(
        clientID: String,
        clientSecret: String,
        accountUsername: String,
        accountPassword: String
    ) -> AuthenticationMethod {
        let isAPIClientComplete = clientID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false &&
        clientSecret.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
        let isAccountComplete = accountUsername.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false &&
        accountPassword.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false

        // Only pick username/password if account is filled AND API client is not
        if isAccountComplete && isAPIClientComplete == false {
            return .usernamePassword
        }

        return .apiClient
    }
}

//endofline
