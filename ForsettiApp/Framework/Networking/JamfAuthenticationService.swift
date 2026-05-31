import CryptoKit
import Foundation

/// An actor-isolated service that obtains, caches, and refreshes bearer tokens for Jamf Pro API access.
///
/// Supports two authentication methods:
/// - **API Client** (OAuth 2.0 client credentials flow via `/api/v1/oauth/token`)
/// - **Username/Password** (Basic auth token exchange via `/api/v1/auth/token`)
///
/// Tokens are cached in memory and automatically refreshed when they expire (with a 60-second
/// safety margin). If the stored credentials change, the cache is invalidated so a fresh token
/// is fetched on the next call. All token state is actor-isolated to prevent data races.
actor JamfAuthenticationService {
    /// A locally cached bearer token along with its expiration date.
    private struct CachedToken: Sendable {
        /// The raw bearer token string.
        let value: String
        /// The absolute date when this token expires.
        let expirationDate: Date

        /// Returns `true` if the token is still usable at the given reference date.
        ///
        /// Includes a 60-second safety margin so the token is considered expired slightly
        /// before its actual expiration, avoiding edge-case failures during in-flight requests.
        func isValid(at referenceDate: Date = Date()) -> Bool {
            expirationDate > referenceDate.addingTimeInterval(60)
        }
    }


    /// The decoded response from a Jamf Pro token endpoint.
    ///
    /// Handles two different response shapes:
    /// - OAuth flow: `access_token` + `expires_in` (seconds)
    /// - Account flow: `token` + `expires` (ISO 8601 string or Unix timestamp)
    ///
    /// Falls back to a 15-minute expiration if the `expires` field is missing or unparseable.
    private struct TokenResponse: Decodable {
        /// The bearer token string.
        let accessToken: String
        /// When the token expires as an absolute date.
        let expirationDate: Date
        /// How many seconds until the token expires (used for diagnostics).
        let expiresInSeconds: Int

        /// Maps the two possible response shapes to a unified set of coding keys.
        enum CodingKeys: String, CodingKey {
            case oauthAccessToken = "access_token"
            case oauthExpiresIn = "expires_in"
            case accountToken = "token"
            case accountExpires = "expires"
        }

        /// Fallback expiration interval (20 minutes) matching Jamf Pro's default token lifetime.
        private static let defaultExpirationInterval: TimeInterval = 1200
        /// ISO 8601 parse style that accepts fractional seconds (e.g., ".000").
        ///
        /// `Date.ISO8601FormatStyle` is a `Sendable` value type, unlike
        /// `ISO8601DateFormatter` (an `NSObject` with mutable `formatOptions`).
        /// Using the format style lets these `static let`s pass Swift 6 strict
        /// concurrency checks without `nonisolated(unsafe)`.
        private static let isoStyleWithFractionalSeconds = Date.ISO8601FormatStyle(includingFractionalSeconds: true)
        /// Standard ISO 8601 parse style without fractional seconds.
        private static let isoStyle = Date.ISO8601FormatStyle()

        /// Decodes a token response, handling both OAuth and account-based response formats.
        ///
        /// Tries the OAuth shape first (`access_token` + `expires_in`), then falls back to
        /// the account shape (`token` + `expires`). The `expires` field is parsed as an
        /// ISO 8601 string first, then as a Unix timestamp, with a 15-minute default fallback.
        init(from decoder: any Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)

            // Try OAuth response shape first
            if let oauthAccessToken = try container.decodeIfPresent(String.self, forKey: .oauthAccessToken) {
                let expiresIn = try container.decode(TimeInterval.self, forKey: .oauthExpiresIn)
                accessToken = oauthAccessToken
                expirationDate = Date().addingTimeInterval(expiresIn)
                expiresInSeconds = Int(expiresIn)
                return
            }

            // Fall back to account-based token response shape
            if let accountToken = try container.decodeIfPresent(String.self, forKey: .accountToken) {
                accessToken = accountToken

                // Try parsing "expires" as an ISO 8601 date string
                if let expires = try? container.decode(String.self, forKey: .accountExpires),
                   let parsedDate = Self.parseExpirationDate(rawValue: expires) {
                    expirationDate = parsedDate
                    expiresInSeconds = max(Int(parsedDate.timeIntervalSinceNow), 0)
                    return
                }

                // Try parsing "expires" as a Unix timestamp
                if let unixTimestamp = try? container.decode(TimeInterval.self, forKey: .accountExpires) {
                    let parsedDate = Date(timeIntervalSince1970: unixTimestamp)
                    expirationDate = parsedDate
                    expiresInSeconds = max(Int(parsedDate.timeIntervalSinceNow), 0)
                    return
                }

                // Neither format worked; use the default 15-minute expiration
                expirationDate = Date().addingTimeInterval(Self.defaultExpirationInterval)
                expiresInSeconds = Int(Self.defaultExpirationInterval)
                return
            }

            throw DecodingError.dataCorruptedError(
                forKey: .oauthAccessToken,
                in: container,
                debugDescription: "Token response was missing a supported token field."
            )
        }

        /// Attempts to parse a date string using ISO 8601, trying fractional seconds first.
        ///
        /// - Parameter rawValue: The raw date string from the token response.
        /// - Returns: A parsed `Date`, or `nil` if neither formatter succeeds.
        private static func parseExpirationDate(rawValue: String) -> Date? {
            (try? isoStyleWithFractionalSeconds.parse(rawValue))
                ?? (try? isoStyle.parse(rawValue))
        }
    }

    /// The URL session used for token requests.
    private let session: URLSession
    /// An optional diagnostics reporter for logging authentication events and errors.
    private let diagnosticsReporter: (any DiagnosticsReporting)?
    /// The most recently obtained bearer token, if any.
    private var cachedToken: CachedToken?
    /// A fingerprint of the credentials used to obtain the cached token, used to detect credential changes.
    private var cachedCredentialSignature: String?

    /// Creates a new authentication service.
    ///
    /// - Parameters:
    ///   - session: The URL session for network requests; defaults to `.shared`.
    ///   - diagnosticsReporter: Optional reporter for authentication diagnostics.
    init(
        session: URLSession = .shared,
        diagnosticsReporter: (any DiagnosticsReporting)? = nil
    ) {
        self.session = session
        self.diagnosticsReporter = diagnosticsReporter
    }

    /// Returns a valid bearer token for the given credentials, refreshing if needed.
    ///
    /// The method first checks whether the cached token is still valid and was obtained
    /// with the same credentials. If not, it requests a fresh token from the appropriate
    /// Jamf Pro endpoint based on the authentication method (API client or username/password).
    ///
    /// - Parameter credentials: The Jamf Pro server credentials to authenticate with.
    /// - Returns: A valid bearer token string.
    /// - Throws: `JamfFrameworkError` variants for invalid URLs, incomplete credentials,
    ///   network failures, or decoding issues.
    func accessToken(for credentials: JamfCredentials) async throws -> String {
        let credentialSignature = signature(for: credentials)
        // Invalidate cache if credentials have changed since the last token was obtained
        if cachedCredentialSignature != credentialSignature {
            cachedToken = nil
            cachedCredentialSignature = credentialSignature
        }

        // Return the cached token if it is still valid (with 60-second safety margin)
        if let cachedToken, cachedToken.isValid() {
            return cachedToken.value
        }

        guard let baseURL = credentials.normalizedServerURL else {
            await diagnosticsReporter?.reportError(
                source: "framework.authentication",
                category: "configuration",
                message: "Cannot request access token because server URL is invalid."
            )
            throw JamfFrameworkError.invalidServerURL
        }

        guard credentials.selectedAuthenticationCredentialsAreComplete else {
            await diagnosticsReporter?.reportError(
                source: "framework.authentication",
                category: "configuration",
                message: "Cannot request access token because credentials are incomplete.",
                metadata: [
                    "auth_method": credentials.authenticationMethod.rawValue
                ]
            )
            throw JamfFrameworkError.invalidCredentials
        }

        // Build the token request based on the chosen authentication method
        let tokenURL: URL
        var request: URLRequest
        switch credentials.authenticationMethod {
        case .apiClient:
            // OAuth 2.0 client credentials flow
            tokenURL = baseURL.appending(path: "api/v1/oauth/token")
            request = URLRequest(url: tokenURL)
            request.httpMethod = "POST"
            request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
            request.setValue("application/json", forHTTPHeaderField: "Accept")

            // Encode client credentials as form-urlencoded body
            var formComponents = URLComponents()
            formComponents.queryItems = [
                URLQueryItem(name: "grant_type", value: "client_credentials"),
                URLQueryItem(
                    name: "client_id",
                    value: credentials.clientID.trimmingCharacters(in: .whitespacesAndNewlines)
                ),
                URLQueryItem(
                    name: "client_secret",
                    value: credentials.clientSecret.trimmingCharacters(in: .whitespacesAndNewlines)
                )
            ]
                // Include optional OAuth scope if specified in credentials
                if !credentials.oauthScope.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    formComponents.queryItems?.append(
                        URLQueryItem(
                            name: "scope",
                            value: credentials.oauthScope.trimmingCharacters(in: .whitespacesAndNewlines)
                        )
                    )
                }
            request.httpBody = formComponents.percentEncodedQuery?.data(using: .utf8)
        case .usernamePassword:
            // Basic auth token exchange
            tokenURL = baseURL.appending(path: "api/v1/auth/token")
            request = URLRequest(url: tokenURL)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Accept")

            // Encode username:password as a Base64 Basic auth header
            let authSource = "\(credentials.accountUsername):\(credentials.accountPassword)"
            let authData = Data(authSource.utf8).base64EncodedString()
            request.setValue("Basic \(authData)", forHTTPHeaderField: "Authorization")
        }

        let data = try await performTokenRequest(request: request, endpoint: tokenURL)
        let payload = try await decodeTokenResponse(data: data)

        let token = CachedToken(value: payload.accessToken, expirationDate: payload.expirationDate)

        // Cache the token and record which credentials were used
        cachedToken = token
        cachedCredentialSignature = credentialSignature
        await diagnosticsReporter?.report(
            source: "framework.authentication",
            category: "token",
            severity: .info,
            message: "Successfully refreshed Jamf access token.",
            metadata: [
                "auth_method": credentials.authenticationMethod.rawValue,
                "expires_in_seconds": String(payload.expiresInSeconds)
            ]
        )
        return token.value
    }

    /// Clears the cached token and credential signature, forcing a fresh token on the next call.
    func invalidateToken() {
        cachedToken = nil
        cachedCredentialSignature = nil
    }

    /// Invalidates the current token on the Jamf Pro server and clears the local cache.
    ///
    /// Calls `POST /api/v1/auth/invalidate-token` with the cached Bearer token.
    /// Jamf Pro returns 204 on success. The local cache is cleared regardless of
    /// whether the server call succeeds, to ensure the client can recover.
    ///
    /// - Parameter credentials: The credentials containing the server URL.
    func invalidateTokenOnServer(for credentials: JamfCredentials) async {
        defer {
            cachedToken = nil
            cachedCredentialSignature = nil
        }

        guard let token = cachedToken?.value,
              let baseURL = credentials.normalizedServerURL else {
            return
        }

        let url = baseURL.appending(path: "api/v1/auth/invalidate-token")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        do {
            let (_, response) = try await session.data(for: request)
            let status = (response as? HTTPURLResponse)?.statusCode ?? -1
            if status == 204 {
                await diagnosticsReporter?.report(
                    source: "framework.authentication",
                    category: "token",
                    severity: .info,
                    message: "Successfully invalidated token on Jamf Pro server.",
                    metadata: [:]
                )
            } else {
                await diagnosticsReporter?.report(
                    source: "framework.authentication",
                    category: "token",
                    severity: .warning,
                    message: "Token invalidation returned unexpected status.",
                    metadata: ["status_code": String(status)]
                )
            }
        } catch {
            await diagnosticsReporter?.report(
                source: "framework.authentication",
                category: "token",
                severity: .warning,
                message: "Token invalidation request failed (token cleared locally).",
                metadata: ["error": describe(error)]
            )
        }
    }

    /// Refreshes the current token via the Jamf Pro keep-alive endpoint.
    ///
    /// Calls `POST /api/v1/auth/keep-alive` which invalidates the current token
    /// and returns a new one. This is the preferred way to extend a session
    /// without re-authenticating from scratch.
    ///
    /// - Parameter credentials: The credentials containing the server URL.
    /// - Returns: The new bearer token string.
    /// - Throws: Network or decoding errors if the keep-alive fails.
    func keepAlive(for credentials: JamfCredentials) async throws -> String {
        guard let token = cachedToken?.value,
              let baseURL = credentials.normalizedServerURL else {
            // No token to keep alive — fall back to normal token acquisition
            return try await accessToken(for: credentials)
        }

        let url = baseURL.appending(path: "api/v1/auth/keep-alive")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let data = try await performTokenRequest(request: request, endpoint: url)
        let payload = try await decodeTokenResponse(data: data)

        let newToken = CachedToken(value: payload.accessToken, expirationDate: payload.expirationDate)
        cachedToken = newToken
        await diagnosticsReporter?.report(
            source: "framework.authentication",
            category: "token",
            severity: .info,
            message: "Token refreshed via keep-alive.",
            metadata: ["expires_in_seconds": String(payload.expiresInSeconds)]
        )
        return newToken.value
    }

    // MARK: - Private Helpers

    /// Executes the HTTP token request and validates the response status code.
    ///
    /// Reports detailed diagnostics on failure, including the endpoint URL and error description.
    ///
    /// - Parameters:
    ///   - request: The fully configured token request.
    ///   - endpoint: The token endpoint URL (used for diagnostic metadata).
    /// - Returns: The raw response body data on success.
    /// - Throws: Network errors or `JamfFrameworkError` for non-2xx responses.
    private func performTokenRequest(request: URLRequest, endpoint: URL) async throws -> Data {
        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            await diagnosticsReporter?.reportError(
                source: "framework.authentication",
                category: "network",
                message: "Token request failed while contacting Jamf Pro.",
                errorDescription: describe(error),
                metadata: [
                    "endpoint": endpoint.absoluteString
                ]
            )
            throw error
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            await diagnosticsReporter?.reportError(
                source: "framework.authentication",
                category: "response",
                message: "Token response from Jamf Pro was not an HTTP response."
            )
            throw JamfFrameworkError.authenticationFailed
        }

        guard (200 ... 299).contains(httpResponse.statusCode) else {
            let message = String(data: data, encoding: .utf8) ?? "Unknown server response"
            await diagnosticsReporter?.reportError(
                source: "framework.authentication",
                category: "response",
                message: "Token request returned an unsuccessful status code.",
                errorDescription: message,
                metadata: [
                    "status_code": String(httpResponse.statusCode),
                    "endpoint": endpoint.absoluteString
                ]
            )
            throw JamfFrameworkError.networkFailure(statusCode: httpResponse.statusCode, message: message)
        }

        return data
    }

    /// Decodes the raw token response data into a `TokenResponse` struct.
    ///
    /// Reports a diagnostic error if decoding fails.
    ///
    /// - Parameter data: The raw JSON data from the token endpoint.
    /// - Returns: A decoded `TokenResponse` containing the token and expiration info.
    /// - Throws: `JamfFrameworkError.decodingFailure` if the JSON cannot be parsed.
    private func decodeTokenResponse(data: Data) async throws -> TokenResponse {
        do {
            return try JSONDecoder().decode(TokenResponse.self, from: data)
        } catch {
            await diagnosticsReporter?.reportError(
                source: "framework.authentication",
                category: "decoding",
                message: "Failed to decode Jamf token response.",
                errorDescription: describe(error)
            )
            throw JamfFrameworkError.decodingFailure
        }
    }

    /// Produces a SHA256 hash fingerprint for the given credentials.
    ///
    /// Used to detect when credentials have changed, so the cached token can be invalidated.
    /// The signature hashes the auth method, server URL, and relevant credential fields
    /// so that plaintext secrets are never stored in memory as signature strings.
    ///
    /// - Parameter credentials: The credentials to fingerprint.
    /// - Returns: A hex-encoded SHA256 hash uniquely identifying these credentials.
    private func signature(for credentials: JamfCredentials) -> String {
        var components: [String]
        switch credentials.authenticationMethod {
        case .apiClient:
            components = [
                credentials.authenticationMethod.rawValue,
                credentials.serverURL.trimmingCharacters(in: .whitespacesAndNewlines),
                credentials.clientID.trimmingCharacters(in: .whitespacesAndNewlines),
                credentials.clientSecret
            ]
        case .usernamePassword:
            components = [
                credentials.authenticationMethod.rawValue,
                credentials.serverURL.trimmingCharacters(in: .whitespacesAndNewlines),
                credentials.accountUsername.trimmingCharacters(in: .whitespacesAndNewlines),
                credentials.accountPassword
            ]
        }
        let input = components.joined(separator: "|")
        let digest = SHA256.hash(data: Data(input.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    /// Extracts a human-readable error description, preferring `LocalizedError.errorDescription`.
    ///
    /// - Parameter error: The error to describe.
    /// - Returns: A string suitable for diagnostic metadata.
    private func describe(_ error: any Error) -> String {
        (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
    }
}

//endofline
