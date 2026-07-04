import XCTest
@testable import ForsettiJamfProApp

// "End of Line"

/// Exercises the shared `JamfFrameworkError` classification helpers.
///
/// The gateway raises either typed cases (`.forbidden`, `.notFound`,
/// `.conflict`, `.rateLimited`) or untyped `.networkFailure(code, _)`.
/// The matcher extension has to treat both shapes identically — prior
/// to the shared extension, per-module helpers matched only one and
/// silently dropped the other, so fallback chains went dark. These
/// tests lock in that parity.
final class JamfFrameworkErrorMatchingTests: XCTestCase {

    // MARK: - Typed variants

    func test_matches_typedForbidden_matches403() {
        let error: any Error = JamfFrameworkError.forbidden(message: "denied")
        XCTAssertTrue(error.matchesJamf(status: 403))
        XCTAssertTrue(error.isJamfInvalidPrivilege)
        XCTAssertTrue(error.isJamfEndpointUnavailable)
        XCTAssertFalse(error.isJamfConflict)
    }

    func test_matches_typedNotFound_matches404() {
        let error: any Error = JamfFrameworkError.notFound(message: "missing")
        XCTAssertTrue(error.matchesJamf(status: 404))
        XCTAssertTrue(error.isJamfEndpointUnavailable)
        XCTAssertFalse(error.isJamfInvalidPrivilege)
    }

    func test_matches_typedConflict_matches409() {
        let error: any Error = JamfFrameworkError.conflict(message: "stale lock")
        XCTAssertTrue(error.matchesJamf(status: 409))
        XCTAssertTrue(error.isJamfConflict)
        XCTAssertFalse(error.isJamfInvalidPrivilege)
        XCTAssertFalse(error.isJamfEndpointUnavailable)
    }

    func test_matches_typedRateLimited_matches429() {
        let error: any Error = JamfFrameworkError.rateLimited(retryAfter: 30)
        XCTAssertTrue(error.matchesJamf(status: 429))
        XCTAssertTrue(error.isJamfRateLimited)
        XCTAssertFalse(error.isJamfConflict)
    }

    func test_matches_typedServerError_matches500() {
        let error: any Error = JamfFrameworkError.serverError(statusCode: 500, message: "boom")
        XCTAssertTrue(error.matchesJamf(status: 500))
        XCTAssertTrue(error.isJamfTransientServerError)
    }

    // MARK: - Untyped networkFailure variant

    func test_matches_networkFailure403_matchesInvalidPrivilege() {
        let error: any Error = JamfFrameworkError.networkFailure(statusCode: 403, message: "x")
        XCTAssertTrue(error.matchesJamf(status: 403))
        XCTAssertTrue(error.isJamfInvalidPrivilege)
        XCTAssertTrue(error.isJamfEndpointUnavailable)
    }

    func test_matches_networkFailure404_matchesEndpointUnavailable() {
        let error: any Error = JamfFrameworkError.networkFailure(statusCode: 404, message: "x")
        XCTAssertTrue(error.matchesJamf(status: 404))
        XCTAssertTrue(error.isJamfEndpointUnavailable)
    }

    func test_matches_networkFailure409_matchesConflict() {
        let error: any Error = JamfFrameworkError.networkFailure(statusCode: 409, message: "x")
        XCTAssertTrue(error.matchesJamf(status: 409))
        XCTAssertTrue(error.isJamfConflict)
    }

    func test_matches_networkFailure429_matchesRateLimited() {
        let error: any Error = JamfFrameworkError.networkFailure(statusCode: 429, message: "x")
        XCTAssertTrue(error.matchesJamf(status: 429))
        XCTAssertTrue(error.isJamfRateLimited)
    }

    // MARK: - Multi-code matching

    func test_matches_multipleCodes_anyMatchReturnsTrue() {
        let forbidden: any Error = JamfFrameworkError.forbidden(message: "x")
        XCTAssertTrue(forbidden.matchesJamf(status: 400, 403, 404))
    }

    func test_matches_multipleCodes_nonMatchReturnsFalse() {
        let forbidden: any Error = JamfFrameworkError.forbidden(message: "x")
        XCTAssertFalse(forbidden.matchesJamf(status: 400, 409, 429))
    }

    // MARK: - Non-Jamf errors

    func test_matches_nonJamfError_returnsFalse() {
        struct OtherError: Error {}
        let error: any Error = OtherError()
        XCTAssertFalse(error.matchesJamf(status: 403))
        XCTAssertFalse(error.isJamfInvalidPrivilege)
        XCTAssertFalse(error.isJamfEndpointUnavailable)
        XCTAssertFalse(error.isJamfConflict)
        XCTAssertFalse(error.isJamfRateLimited)
        XCTAssertFalse(error.isJamfTransientServerError)
    }

    // MARK: - Typed status code mapping

    func test_typedStatusCode_mapping() {
        XCTAssertEqual(JamfFrameworkError.forbidden(message: "x").typedStatusCode, 403)
        XCTAssertEqual(JamfFrameworkError.notFound(message: "x").typedStatusCode, 404)
        XCTAssertEqual(JamfFrameworkError.conflict(message: "x").typedStatusCode, 409)
        XCTAssertEqual(JamfFrameworkError.rateLimited(retryAfter: nil).typedStatusCode, 429)
        XCTAssertNil(JamfFrameworkError.networkFailure(statusCode: 500, message: "x").typedStatusCode)
        XCTAssertNil(JamfFrameworkError.decodingFailure.typedStatusCode)
    }
}

//endofline
