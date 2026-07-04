import XCTest
@testable import Jamf_Dashboard

/// Unit tests for the Temporary Admin Elevation models, configuration decoding,
/// validation, the extension-attribute snapshot parser, and error mapping.
final class TemporaryAdminElevationModelTests: XCTestCase {

    // MARK: - Duration bounds

    func test_allowedDurationsAreExactlyFiveFifteenThirtySixty() {
        XCTAssertEqual(TemporaryAdminDuration.allCases.map(\.rawValue), [5, 15, 30, 60])
    }

    // MARK: - Configuration decoding

    private let fullConfigJSON = """
    {
      "enabled": true,
      "requireTicketReference": true,
      "pollIntervalSeconds": 30,
      "confirmationTimeoutMinutes": 25,
      "cleanupAfterTimeout": true,
      "allowedDurationsMinutes": [5, 15, 30, 60],
      "requestScopes": {
        "5": { "id": "501", "name": "5m", "kind": "staticComputerGroup" },
        "15": { "id": "515", "name": "15m", "kind": "staticComputerGroup" },
        "30": { "id": "530", "name": "30m", "kind": "staticComputerGroup" },
        "60": { "id": "560", "name": "60m", "kind": "staticComputerGroup" }
      },
      "demoteNowScope": { "id": "590", "name": "Demote", "kind": "staticComputerGroup" },
      "extensionAttributeNames": {
        "status": "S", "user": "U", "expiresAt": "E", "lastChange": "L", "runId": "R"
      }
    }
    """

    func test_configurationDecodesWithAllScopes_andIsFullyConfigured() throws {
        let config = try JSONDecoder().decode(TemporaryAdminElevationConfiguration.self, from: Data(fullConfigJSON.utf8))
        XCTAssertTrue(config.enabled)
        XCTAssertTrue(config.isFullyConfigured)
        XCTAssertEqual(config.availableDurations, TemporaryAdminDuration.allCases)
        XCTAssertEqual(config.scope(for: .fifteen)?.id, "515")
    }

    func test_configurationWithEmptyScopeId_isNotFullyConfigured() throws {
        // A required scope without a configured Jamf object ID disables the feature.
        let json = fullConfigJSON.replacingOccurrences(of: "\"id\": \"515\"", with: "\"id\": \"\"")
        let config = try JSONDecoder().decode(TemporaryAdminElevationConfiguration.self, from: Data(json.utf8))
        XCTAssertFalse(config.isFullyConfigured)
        XCTAssertFalse(config.availableDurations.contains(.fifteen))
    }

    func test_disabledDefault_isOffAndNotConfigured() {
        let config = TemporaryAdminElevationConfiguration.disabledDefault
        XCTAssertFalse(config.enabled)
        XCTAssertFalse(config.isFullyConfigured)
        XCTAssertTrue(config.availableDurations.isEmpty)
    }

    // MARK: - Validation

    private func validate(
        assetType: SupportAssetType = .computer,
        managed: Bool = true,
        inventoryID: String = "1",
        duration: TemporaryAdminDuration? = .fifteen,
        hasScope: Bool = true,
        reason: String = "needs admin",
        ticket: String = "TICKET-1",
        requiresTicket: Bool = true
    ) -> TemporaryAdminValidationResult {
        TemporaryAdminElevationValidator.validate(
            assetType: assetType,
            isManaged: managed,
            inventoryID: inventoryID,
            duration: duration,
            hasConfiguredScope: hasScope,
            reason: reason,
            ticketReference: ticket,
            requiresTicket: requiresTicket
        )
    }

    func test_validationAcceptsAGoodManagedMac() {
        XCTAssertTrue(validate().isValid)
    }

    func test_validationRejectsMobileDevices() {
        XCTAssertFalse(validate(assetType: .mobileDevice).isValid)
    }

    func test_validationRejectsUnmanagedMac() {
        XCTAssertFalse(validate(managed: false).isValid)
    }

    func test_validationRejectsMissingComputerID() {
        XCTAssertFalse(validate(inventoryID: "   ").isValid)
    }

    func test_validationRejectsEmptyReason() {
        XCTAssertFalse(validate(reason: "   ").isValid)
    }

    func test_validationRejectsEmptyTicketWhenRequired() {
        XCTAssertFalse(validate(ticket: "", requiresTicket: true).isValid)
    }

    func test_validationAcceptsEmptyTicketWhenNotRequired() {
        XCTAssertTrue(validate(ticket: "", requiresTicket: false).isValid)
    }

    // MARK: - Snapshot parsing

    private func parse(_ eas: [SupportExtensionAttribute], now: Date = Date()) -> TemporaryAdminElevationSnapshot {
        TemporaryAdminElevationSnapshotParser.parse(
            extensionAttributes: eas,
            names: TemporaryAdminTestSupport.standardEANames,
            now: now
        )
    }

    func test_parserMapsElevated() {
        let snap = parse(TemporaryAdminTestSupport.statusEAs(
            status: "elevated",
            user: "alice",
            expiresISO: "2026-06-14T18:00:00Z",
            runId: "20260614T173000Z-alice"
        ))
        guard case .elevated(let user, let expires, let runId) = snap.state else {
            return XCTFail("Expected elevated, got \(snap.state)")
        }
        XCTAssertEqual(user, "alice")
        XCTAssertNotNil(expires)
        XCTAssertEqual(runId, "20260614T173000Z-alice")
    }

    func test_parserMapsAlreadyAdmin() {
        let snap = parse(TemporaryAdminTestSupport.statusEAs(status: "already_admin", user: "bob"))
        guard case .alreadyAdmin(let user, _) = snap.state else {
            return XCTFail("Expected alreadyAdmin, got \(snap.state)")
        }
        XCTAssertEqual(user, "bob")
    }

    func test_parserMapsDemoted() {
        let snap = parse(TemporaryAdminTestSupport.statusEAs(status: "demoted", user: "carol"))
        guard case .demoted = snap.state else {
            return XCTFail("Expected demoted, got \(snap.state)")
        }
    }

    func test_parserMapsExpiredPendingDemotionToElevatedAndPreservesRaw() {
        let snap = parse(TemporaryAdminTestSupport.statusEAs(status: "expired_pending_demotion", user: "dave"))
        guard case .elevated = snap.state else {
            return XCTFail("Expected elevated (still admin pending demotion), got \(snap.state)")
        }
        XCTAssertEqual(snap.statusRawValue, "expired_pending_demotion")
    }

    func test_parserMapsUnknownStatusToFailedWithoutCrashing() {
        let snap = parse(TemporaryAdminTestSupport.statusEAs(status: "banana"))
        guard case .failed = snap.state else {
            return XCTFail("Expected failed, got \(snap.state)")
        }
        XCTAssertEqual(snap.statusRawValue, "banana")
    }

    func test_parserHandlesInvalidDatesWithoutCrashing() {
        let snap = parse(TemporaryAdminTestSupport.statusEAs(
            status: "elevated",
            user: "erin",
            expiresISO: "not-a-date",
            lastChangeISO: "also-bad"
        ))
        XCTAssertNil(snap.expiresAt)
        XCTAssertNil(snap.lastChange)
    }

    func test_parserMapsNotReportedToReady() {
        let snap = parse(TemporaryAdminTestSupport.statusEAs(status: "Not Reported", user: nil))
        guard case .ready = snap.state else {
            return XCTFail("Expected ready, got \(snap.state)")
        }
        XCTAssertNil(snap.user)
    }

    // MARK: - Error mapping

    func test_403MapsToPermissionDeniedWithRequiredPrivileges() {
        let error = JamfFrameworkError.forbidden(message: "no privilege")
        let mapped = TemporaryAdminUserFacingError.map(error)
        XCTAssertEqual(mapped.diagnosticsCategory, TemporaryAdminDiagnostics.Category.permission)
        XCTAssertTrue(mapped.requiredJamfPrivileges.contains("Update Static Computer Groups, or current tenant-supported request-scope equivalent"))
        XCTAssertEqual(mapped.localMacStateChanged, false)
        XCTAssertTrue(mapped.safeToRetry)
    }

    func test_notConfiguredMapsToActionableMessage() {
        let mapped = TemporaryAdminUserFacingError.map(TemporaryAdminElevationError.notConfigured)
        XCTAssertFalse(mapped.safeToRetry)
        XCTAssertEqual(mapped.localMacStateChanged, false)
    }
}
