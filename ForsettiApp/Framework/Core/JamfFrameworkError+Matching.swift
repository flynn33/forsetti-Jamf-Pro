import Foundation

/// Shared helpers for classifying `JamfFrameworkError` values against HTTP
/// status codes.
///
/// The gateway can raise errors in two shapes:
///
/// 1. **Typed cases** (`.forbidden`, `.notFound`, `.conflict`, `.rateLimited`,
///    `.serverError`) — emitted when the gateway has enough metadata to
///    classify the response (parseable body, recognizable status).
/// 2. **Untyped** `.networkFailure(statusCode, message)` — emitted when the
///    body is opaque or the status code doesn't map to a typed case.
///
/// Every fallback chain (version fallback, payload fallback, endpoint
/// fallback) needs to match BOTH shapes. A helper that only checks one
/// silently misses half the error space, so the retry loop goes dark and
/// the first failure escapes as-is.
///
/// Prior to this extension the classification pattern was duplicated —
/// and slightly drifted — across `ComputerSearchViewModel`,
/// `MobileDeviceSearchViewModel`, `PrestageDirectorViewModel`,
/// `SupportTechnicianViewModel`, and three helpers inside
/// `SupportTechnicianAPIService`. This extension consolidates the
/// matching logic so every caller uses the same status-code semantics
/// and `.conflict` / `.rateLimited` are never missed.
// All methods and properties in this extension are `nonisolated`
// because the module's default actor isolation is `MainActor`. Without
// the marker, extensions on `JamfFrameworkError` (a non-actor value type)
// would inherit main-actor isolation from the module default, which
// blocks the two primary call sites:
//
// 1. `actor SupportTechnicianAPIService` and its synchronous helpers
//    run in an actor isolation domain that is NOT the main actor.
// 2. The gateway raises these errors from arbitrary concurrent contexts
//    (URLSession callback queues, task continuations).
//
// Pure classification over an enum has no shared state, so nonisolated
// is the correct isolation for every member.
extension JamfFrameworkError {
    /// Returns `true` when the error represents any of the given HTTP
    /// status codes, whether the gateway raised a typed case or fell
    /// back to `.networkFailure(code, _)`.
    ///
    /// Usage: `error.matches(status: 403, 404, 405)` to detect any
    /// "endpoint unavailable to this caller" response.
    nonisolated func matches(status codes: Int...) -> Bool {
        matches(statusSet: Set(codes))
    }

    /// Set-based variant of `matches(status:)` — used internally and by
    /// the `Error` bridge to avoid rebuilding the Set on every call.
    nonisolated func matches(statusSet codes: Set<Int>) -> Bool {
        if let typed = typedStatusCode, codes.contains(typed) {
            return true
        }
        if case let .networkFailure(statusCode, _) = self, codes.contains(statusCode) {
            return true
        }
        if case let .serverError(statusCode, _) = self, codes.contains(statusCode) {
            return true
        }
        return false
    }

    /// The HTTP status code implied by a typed case, or `nil` for cases
    /// that don't map cleanly to a single status (e.g., `.authenticationFailed`,
    /// `.decodingFailure`).
    nonisolated var typedStatusCode: Int? {
        switch self {
        case .forbidden: return 403
        case .notFound: return 404
        case .conflict: return 409
        case .rateLimited: return 429
        default: return nil
        }
    }

    /// `true` when the error represents a 403 privilege denial — either
    /// a typed `.forbidden(message)` or an untyped `.networkFailure(403, _)`.
    /// Used to drive privilege-fallback paths (e.g., retry with a minimal
    /// inventory-section set, force a token refresh, etc.).
    nonisolated var isInvalidPrivilege: Bool {
        matches(status: 403)
    }

    /// `true` when the error indicates the endpoint is not available to
    /// this caller — 403 (privilege missing), 404 (path not found), or
    /// 405 (method not allowed). Used by version/path fallback chains
    /// to decide whether the next candidate is worth trying.
    nonisolated var isEndpointUnavailable: Bool {
        matches(status: 403, 404, 405)
    }

    /// `true` when the error represents a rate-limit response (429).
    /// The `retryAfter` value (when present) lives on the typed case.
    nonisolated var isRateLimited: Bool {
        matches(status: 429)
    }

    /// `true` when the error represents a resource conflict (409),
    /// typically optimistic-lock failure or a duplicate write.
    nonisolated var isConflict: Bool {
        matches(status: 409)
    }

    /// `true` when the error represents a transient server-side failure
    /// (500/502/503/504) that a backoff-and-retry strategy would benefit
    /// from. Matches both typed `.serverError` and the raw networkFailure.
    nonisolated var isTransientServerError: Bool {
        matches(status: 500, 502, 503, 504)
    }
}

/// Bridge helpers on `Error` so call sites holding an `any Error` don't
/// each have to cast to `JamfFrameworkError` before classifying. Returns
/// `false` for non-Jamf errors — callers that want to surface non-Jamf
/// transport errors distinctly should handle them explicitly before
/// reaching the classification helper.
///
/// All members are `nonisolated` — see the rationale on the
/// `JamfFrameworkError` extension above. Error classification must be
/// callable from any actor, including the `JamfAPIGateway` and
/// `SupportTechnicianAPIService` actors whose isolation is not the
/// module-default main actor.
extension Error {
    /// Convenience: checks whether this error is a `JamfFrameworkError`
    /// whose status matches any of the given codes.
    nonisolated func matchesJamf(status codes: Int...) -> Bool {
        (self as? JamfFrameworkError)?.matches(statusSet: Set(codes)) ?? false
    }

    /// Convenience: `true` when this error is a Jamf 403 privilege denial.
    nonisolated var isJamfInvalidPrivilege: Bool {
        (self as? JamfFrameworkError)?.isInvalidPrivilege ?? false
    }

    /// Convenience: `true` when this error is a Jamf 403/404/405 — the
    /// endpoint is not available to this caller.
    nonisolated var isJamfEndpointUnavailable: Bool {
        (self as? JamfFrameworkError)?.isEndpointUnavailable ?? false
    }

    /// Convenience: `true` when this error is a Jamf 429 rate-limit.
    nonisolated var isJamfRateLimited: Bool {
        (self as? JamfFrameworkError)?.isRateLimited ?? false
    }

    /// Convenience: `true` when this error is a Jamf 409 conflict.
    nonisolated var isJamfConflict: Bool {
        (self as? JamfFrameworkError)?.isConflict ?? false
    }

    /// Convenience: `true` when this error is a Jamf 500/502/503/504 —
    /// a transient server error worth backing off and retrying.
    nonisolated var isJamfTransientServerError: Bool {
        (self as? JamfFrameworkError)?.isTransientServerError ?? false
    }
}

//endofline
