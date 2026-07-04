import XCTest
@testable import Jamf_Dashboard

/// Verifies the Remote Support state machine: eligibility, the queue/open separation (queueing
/// the enable command never makes the Mac "ready" or opens Screen Sharing), failed-state retry
/// guidance, and cleanup persistence after launch.
@MainActor
final class SupportRemoteSupportStateTests: XCTestCase {

    private let target = SupportRemoteSupportTarget(host: "10.0.0.5", source: .currentIPAddress)

    private func makeDetail(assetType: SupportAssetType = .computer, managementID: String? = "mgmt-1") -> SupportDeviceDetail {
        let summary = SupportSearchResult(
            assetType: assetType,
            inventoryID: "1",
            managementID: managementID,
            clientManagementID: nil,
            displayName: "Lab Mac",
            serialNumber: "C02ABC123",
            username: nil,
            email: nil,
            model: nil,
            osVersion: nil,
            lastInventoryUpdate: nil,
            prestageEnrollment: nil,
            automatedDeviceEnrollment: nil
        )
        return SupportDeviceDetail(summary: summary, diagnostics: [], sections: [], applications: [], rawJSON: "{}")
    }

    // MARK: - Eligibility

    func test_configure_computerWithManagementID_readyToPrepare() {
        let c = SupportRemoteSupportCoordinator()
        c.configure(for: makeDetail())
        XCTAssertEqual(c.state, .readyToPrepare)
        XCTAssertTrue(c.state.allowsEnable)
        XCTAssertNotNil(c.session)
    }

    func test_configure_computerWithoutManagementID_needsManagementID() {
        let c = SupportRemoteSupportCoordinator()
        c.configure(for: makeDetail(managementID: nil))
        XCTAssertEqual(c.state, .needsManagementID)
        XCTAssertFalse(c.state.allowsEnable)
    }

    func test_configure_mobile_unsupported() {
        let c = SupportRemoteSupportCoordinator()
        c.configure(for: makeDetail(assetType: .mobileDevice))
        if case .unsupported = c.state {} else { XCTFail("expected unsupported, got \(c.state)") }
        XCTAssertNil(c.session)
    }

    // MARK: - Queue / open separation

    func test_queueingEnable_doesNotOpenScreenSharing() {
        let c = SupportRemoteSupportCoordinator()
        c.configure(for: makeDetail())
        c.beginEnable()
        XCTAssertEqual(c.state, .queueingEnableCommand)
        c.enableQueued(commandID: "cmd-1")
        XCTAssertEqual(c.state, .queuedWaitingForCheckIn(commandID: "cmd-1"))
        // Jamf accepted the command — that is NOT readiness, and Open must stay disabled.
        XCTAssertFalse(c.state.canOpenScreenSharing)
    }

    func test_fullHappyPath_opensOnlyAtReadyToOpen() {
        let c = SupportRemoteSupportCoordinator()
        c.configure(for: makeDetail())
        c.beginEnable()
        c.enableQueued(commandID: "cmd-1")
        c.markReadinessUnknown()
        XCTAssertEqual(c.state, .readinessUnknown(commandID: "cmd-1"))
        XCTAssertFalse(c.state.canOpenScreenSharing)

        c.markReadyToOpen(target: target)
        XCTAssertEqual(c.state, .readyToOpen(target: target))
        XCTAssertTrue(c.state.canOpenScreenSharing)   // only here

        c.requestLaunch()
        XCTAssertEqual(c.state, .launchRequested(target: target))
        c.launchRecorded()
        XCTAssertEqual(c.state, .cleanupAvailable(target: target))

        c.beginDisable()
        XCTAssertEqual(c.state, .queueingDisableCommand)
        c.disableQueued(commandID: "cmd-2")
        XCTAssertEqual(c.state, .ended)
        XCTAssertEqual(c.session?.enableCommandID, "cmd-1")
        XCTAssertEqual(c.session?.disableCommandID, "cmd-2")
    }

    func test_requestLaunch_isNoopBeforeReadyToOpen() {
        let c = SupportRemoteSupportCoordinator()
        c.configure(for: makeDetail())
        c.beginEnable()
        c.enableQueued(commandID: nil)
        let before = c.state
        c.requestLaunch()   // invalid from queuedWaitingForCheckIn
        XCTAssertEqual(c.state, before)
    }

    // MARK: - Failure / retry

    func test_failure_safeToRetry_returnsToReadyToPrepare() {
        let c = SupportRemoteSupportCoordinator()
        c.configure(for: makeDetail())
        c.beginEnable()
        c.fail(SupportRemoteSupportFailure(summary: "Network blip", isSafeToRetry: true, recommendation: "Try again."))
        XCTAssertTrue(c.state.allowsRetry)
        c.retry()
        XCTAssertEqual(c.state, .readyToPrepare)
    }

    func test_failure_notSafeToRetry_staysFailed() {
        let c = SupportRemoteSupportCoordinator()
        c.configure(for: makeDetail())
        c.beginEnable()
        c.fail(SupportRemoteSupportFailure(summary: "Privilege denied", isSafeToRetry: false, recommendation: "Grant the privilege."))
        XCTAssertFalse(c.state.allowsRetry)
        c.retry()   // no-op
        if case .failed = c.state {} else { XCTFail("expected to stay failed, got \(c.state)") }
    }

    // MARK: - Cleanup persistence

    func test_cleanupAvailable_persistsUntilResolved() {
        let c = SupportRemoteSupportCoordinator()
        c.configure(for: makeDetail())
        c.beginEnable()
        c.enableQueued(commandID: "cmd")
        c.markReadyToOpen(target: target)
        c.requestLaunch()
        c.launchRecorded()
        XCTAssertEqual(c.state, .cleanupAvailable(target: target))
        XCTAssertTrue(c.state.allowsDisable)
        // Spurious transitions must not clear cleanup availability.
        c.markReadyToOpen(target: target)
        c.requestLaunch()
        XCTAssertEqual(c.state, .cleanupAvailable(target: target))
    }

    func test_endSkippingCleanup_recordsReasonAndEnds() {
        let c = SupportRemoteSupportCoordinator()
        c.configure(for: makeDetail())
        c.beginEnable()
        c.enableQueued(commandID: "cmd")
        c.markReadyToOpen(target: target)
        c.requestLaunch()
        c.launchRecorded()
        c.endSkippingCleanup(reason: "User went off VPN; will re-enable later.")
        XCTAssertEqual(c.state, .ended)
        XCTAssertEqual(c.session?.reason, "User went off VPN; will re-enable later.")
        XCTAssertNotNil(c.session?.endedAt)
    }
}

//endofline
