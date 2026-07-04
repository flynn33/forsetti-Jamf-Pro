import Foundation
import Security

/// A comprehensive error type covering all failure modes in the Jamf Dashboard framework.
///
/// Each case maps to a specific category of failure -- from authentication and
/// network issues to keychain operations and persistence failures. The
/// `errorDescription` property provides a user-facing message suitable for
/// display in alerts or error views.
enum JamfFrameworkError: LocalizedError {

    /// The Jamf Pro server URL could not be parsed or is empty.
    case invalidServerURL
    /// No credentials were found when an authenticated request was attempted.
    case missingCredentials
    /// The stored credentials are incomplete for the selected sign-in method.
    case invalidCredentials
    /// The server rejected the authentication attempt (e.g., 401 Unauthorized).
    case authenticationFailed
    /// A caller attempted to build a request with invalid local parameters.
    /// - Parameter message: A description of the invalid request input.
    case invalidRequest(message: String)
    /// An HTTP request returned a non-success status code.
    /// - Parameters:
    ///   - statusCode: The HTTP status code received.
    ///   - message: A human-readable description of the failure.
    case networkFailure(statusCode: Int, message: String)
    /// The server response could not be decoded into the expected model.
    case decodingFailure
    /// A Keychain Services operation failed.
    /// - Parameter status: The `OSStatus` code returned by the Security framework.
    case keychainFailure(status: OSStatus)
    /// A local persistence operation (e.g., file write, UserDefaults) failed.
    /// - Parameter message: A description of what went wrong.
    case persistenceFailure(message: String)
    /// The server responded with 429 Too Many Requests. The client should back off and retry.
    /// - Parameter retryAfter: Optional number of seconds to wait before retrying (from Retry-After header).
    case rateLimited(retryAfter: Int?)
    /// The server returned 403 Forbidden — the authenticated user lacks required privileges.
    case forbidden(message: String)
    /// The requested resource was not found (404).
    case notFound(message: String)
    /// A resource conflict occurred (409), typically from stale data or duplicate operations.
    case conflict(message: String)
    /// The server encountered an internal error (500/502/503).
    case serverError(statusCode: Int, message: String)
    /// A double-401 occurred: credentials themselves appear to be invalid, not just an expired token.
    case credentialsRejected

    // "End of Line"

    /// A localized description of the error suitable for displaying in the UI.
    var errorDescription: String? {
        switch self {
        case .invalidServerURL:
            return "The Jamf Pro URL is invalid."
        case .missingCredentials:
            return "Jamf credentials are missing."
        case .invalidCredentials:
            return "Credentials are incomplete for the selected sign-in method."
        case .authenticationFailed:
            return "Authentication with the Jamf Pro server failed."
        case let .invalidRequest(message):
            return "Invalid request: \(message)"
        case let .networkFailure(statusCode, message):
            return "Request failed with status \(statusCode): \(message)"
        case let .rateLimited(retryAfter):
            if let seconds = retryAfter {
                return "Rate limited by Jamf Pro. Retry after \(seconds) seconds."
            }
            return "Rate limited by Jamf Pro. Please wait before retrying."
        case let .forbidden(message):
            return "Access denied: \(message)"
        case let .notFound(message):
            return "Resource not found: \(message)"
        case let .conflict(message):
            return "Conflict: \(message)"
        case let .serverError(statusCode, message):
            return "Server error (\(statusCode)): \(message)"
        case .credentialsRejected:
            return "Credentials were rejected by the Jamf Pro server. Please verify your credentials."
        case .decodingFailure:
            return "The server response format is not supported."
        case let .keychainFailure(status):
            return "Keychain operation failed with status \(status)."
        case let .persistenceFailure(message):
            return "Local persistence failed: \(message)"
        }
    }
}

//endofline
