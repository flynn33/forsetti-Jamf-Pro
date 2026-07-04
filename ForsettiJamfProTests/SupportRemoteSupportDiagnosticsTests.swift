import XCTest
@testable import ForsettiJamfProApp

/// Verifies Phase 6: 403 → exact required-privilege mapping, the HTTP error contract, full
/// diagnostics metadata for workflow events, and cleanup-failure recovery (cleanup is not
/// discarded on retry).
@MainActor
final class SupportRemoteSupportDiagnosticsTests: XCTestCase {

    private let mapper = SupportRemoteSupportDiagnosticMapper()

    private func makeDetail(managementID: String? = "mgmt-1") -> SupportDeviceDetail {
        let summary = SupportSearchResult(
            assetType: .computer,
            inventoryID: "1",
            managementID: managementID,
            clientManagementID: nil,
            displayName: "Lab Mac",
            serialNumber: "C02ABC123",
            username: nil, email: nil, model: nil, osVersion: nil,
            lastInventoryUpdate: nil, prestageEnrollment: nil, automatedDeviceEnrollment: nil
        )
        return SupportDeviceDetail(summary: summary, diagnostics: [], sections: [], applications: [], rawJSON: "{}")
    }

    private func jamf(_ status: Int) -> JamfFrameworkError {
        .networkFailure(statusCode: status, message: "status \(status)")
    }

    private func waitUntil(_ predicate: () -> Bool, iterations: Int = 2000) async {
        var n = 0
        while predicate() == false && n < iterations { await Task.yield(); n += 1 }
    }

    @MainActor
    private final class Recorder {
        var events: [SupportRemoteSupportDiagnosticEvent] = []
        func add(_ event: SupportRemoteSupportDiagnosticEvent) { events.append(event) }
        func events(action: String) -> [SupportRemoteSupportDiagnosticEvent] {
            events.filter { $0.metadata["action"] == action }
        }
    }

    private func makeController(
        record: @escaping (SupportRemoteSupportDiagnosticEvent) -> Void,
        enable: @escaping (String) async throws -> String? = { _ in "cmd" },
        disable: @escaping (String) async throws -> String? = { _ in "cmd" }
    ) -> SupportRemoteSupportController {
        SupportRemoteSupportController(
            enableCommand: enable,
            disableCommand: disable,
            launchURL: { _ in },
            copyToClipboard: { _ in },
            reportDiagnostics: record
        )
    }

    // MARK: - Mapper: 403 privilege naming

    func test_mapper_403_command_listsBothPrivileges() {
        let failure = mapper.failure(from: jamf(403), requiresCommandPrivilege: true)
        let privilege = failure.requiredPrivilege ?? ""
        XCTAssertTrue(privilege.contains("View MDM command information in Jamf Pro API"))
        XCTAssertTrue(privilege.contains("Send Computer Remote Desktop Command"))
        XCTAssertTrue(failure.isSafeToRetry)
    }

    func test_mapper_403_statusLookup_listsOnlyEndpointPrivilege() {
        let failure = mapper.failure(from: jamf(403), requiresCommandPrivilege: false)
        let privilege = failure.requiredPrivilege ?? ""
        XCTAssertTrue(privilege.contains("View MDM command information in Jamf Pro API"))
        XCTAssertFalse(privilege.contains("Send Computer Remote Desktop Command"))
    }

    // MARK: - Mapper: HTTP error contract

    func test_mapper_401_isReauthGuidance_noPrivilege() {
        let failure = mapper.failure(from: jamf(401), requiresCommandPrivilege: true)
        XCTAssertNil(failure.requiredPrivilege)
        XCTAssertTrue(failure.isSafeToRetry)
        XCTAssertTrue(failure.recommendation.lowercased().contains("re-authenticate"))
    }

    func test_mapper_404_isNotSafeToRetry() {
        XCTAssertFalse(mapper.failure(from: jamf(404), requiresCommandPrivilege: true).isSafeToRetry)
    }

    func test_mapper_409_and_429_and_5xx_areSafeToRetry() {
        XCTAssertTrue(mapper.failure(from: jamf(409), requiresCommandPrivilege: true).isSafeToRetry)
        XCTAssertTrue(mapper.failure(from: jamf(429), requiresCommandPrivilege: true).isSafeToRetry)
        XCTAssertTrue(mapper.failure(from: jamf(503), requiresCommandPrivilege: true).isSafeToRetry)
    }

    func test_mapper_httpStatus_extraction() {
        XCTAssertEqual(mapper.httpStatus(for: jamf(403)), 403)
        XCTAssertEqual(mapper.httpStatus(for: jamf(503)), 503)
        struct Other: Error {}
        XCTAssertNil(mapper.httpStatus(for: Other()))
    }

    // MARK: - Controller diagnostics metadata

    func test_configure_recordsEligibilityWithCoreMetadata() {
        let rec = Recorder()
        let controller = makeController(record: { rec.add($0) })
        controller.configure(for: makeDetail())

        let eligibility = rec.events(action: "eligibility")
        XCTAssertEqual(eligibility.count, 1)
        let meta = eligibility[0].metadata
        XCTAssertEqual(meta["module"], "support-technician")
        XCTAssertEqual(meta["source"], "module.support-technician")
        XCTAssertEqual(meta["inventory_id"], "1")
        XCTAssertEqual(meta["management_id"], "mgmt-1")
        XCTAssertEqual(meta["serial_number"], "C02ABC123")
        XCTAssertEqual(meta["remote_support_state"], "ready_to_prepare")
    }

    func test_enableQueued_recordsCommandTypeAndQueuedFlag() async {
        let rec = Recorder()
        let controller = makeController(record: { rec.add($0) })
        controller.configure(for: makeDetail())
        controller.enableRemoteManagement()
        await waitUntil { rec.events(action: "enable_command").isEmpty == false }

        let event = rec.events(action: "enable_command")[0]
        XCTAssertEqual(event.metadata["command_type"], "ENABLE_REMOTE_DESKTOP")
        XCTAssertEqual(event.metadata["endpoint"], "api/v2/mdm/commands")
        XCTAssertEqual(event.metadata["jamf_command_queued"], "true")
        XCTAssertEqual(event.metadata["management_id"], "mgmt-1")
    }

    func test_enableFailure403_recordsPrivilegeMetadata_andFailsWithPrivilege() async throws {
        let rec = Recorder()
        let controller = makeController(
            record: { rec.add($0) },
            enable: { _ in throw JamfFrameworkError.networkFailure(statusCode: 403, message: "INVALID_PRIVILEGE") }
        )
        controller.configure(for: makeDetail())
        controller.enableRemoteManagement()
        await waitUntil { rec.events(action: "enable_command").contains { $0.severity == .error } }

        let event = try XCTUnwrap(rec.events(action: "enable_command").first { $0.severity == .error })
        XCTAssertEqual(event.metadata["http_status"], "403")
        XCTAssertEqual(event.metadata["jamf_command_queued"], "false")
        let privilege = try XCTUnwrap(event.metadata["required_privilege"])
        XCTAssertTrue(privilege.contains("Send Computer Remote Desktop Command"))
        XCTAssertEqual(event.metadata["safe_to_retry"], "true")

        // The user-facing failure carries the privilege too.
        guard case let .failed(failure) = controller.state else {
            return XCTFail("expected failed, got \(controller.state)")
        }
        XCTAssertNotNil(failure.requiredPrivilege)
    }

    func test_cleanupSkipped_recordsReason() {
        let rec = Recorder()
        let controller = makeController(record: { rec.add($0) })
        controller.configure(for: makeDetail())
        controller.coordinator.beginEnable()
        controller.coordinator.enableQueued(commandID: "e")
        let target = SupportRemoteSupportTarget(host: "10.0.0.5", source: .currentIPAddress)
        controller.coordinator.markReadyToOpen(target: target)
        controller.coordinator.requestLaunch()
        controller.coordinator.launchRecorded()

        controller.endSkippingCleanup(reason: "User left the call.")
        let skipped = rec.events(action: "cleanup_skipped")
        XCTAssertEqual(skipped.count, 1)
        XCTAssertTrue(skipped[0].message.contains("User left the call."))
    }

    // MARK: - Cleanup failure recovery (coordinator)

    func test_disableFailure_resumesCleanupOnRetry() {
        let coordinator = SupportRemoteSupportCoordinator()
        coordinator.configure(for: makeDetail())
        coordinator.beginEnable()
        coordinator.enableQueued(commandID: "e")
        let target = SupportRemoteSupportTarget(host: "10.0.0.5", source: .currentIPAddress)
        coordinator.markReadyToOpen(target: target)
        coordinator.requestLaunch()
        coordinator.launchRecorded()
        coordinator.beginDisable()   // queueingDisableCommand

        coordinator.fail(SupportRemoteSupportFailure(summary: "403", isSafeToRetry: true, recommendation: "grant"))
        if case .failed = coordinator.state {} else { return XCTFail("expected failed") }

        coordinator.retry()
        // Cleanup is restored (Disable stays available) instead of jumping back to readyToPrepare.
        XCTAssertEqual(coordinator.state, .cleanupAvailable(target: target))
        XCTAssertTrue(coordinator.state.allowsDisable)
    }

    func test_enableFailure_retryReturnsToReadyToPrepare() {
        let coordinator = SupportRemoteSupportCoordinator()
        coordinator.configure(for: makeDetail())
        coordinator.beginEnable()   // queueingEnableCommand
        coordinator.fail(SupportRemoteSupportFailure(summary: "blip", isSafeToRetry: true, recommendation: "retry"))
        coordinator.retry()
        XCTAssertEqual(coordinator.state, .readyToPrepare)
    }
}

//endofline
