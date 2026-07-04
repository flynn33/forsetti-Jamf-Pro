import XCTest
import Combine
@testable import ForsettiJamfProApp

/// Verifies the view-facing `SupportRemoteSupportController`: it drives the pure coordinator in
/// response to technician actions and performs the actual work through its injected closures
/// (enable/disable command, native URL launch, clipboard) without ever opening Screen Sharing
/// implicitly. The closures are mocked so the controller is exercised in isolation.
@MainActor
final class SupportRemoteSupportControllerTests: XCTestCase {

    /// Records closure invocations and supplies canned results/errors. Reference type so the
    /// escaping controller closures can mutate it; MainActor-isolated to match the controller.
    @MainActor
    private final class CallRecorder {
        var enableManagementIDs: [String] = []
        var disableManagementIDs: [String] = []
        var launchedURLs: [URL] = []
        var copiedStrings: [String] = []
        var enableResult: String? = "enable-cmd"
        var disableResult: String? = "disable-cmd"
        var enableError: Error?
        var disableError: Error?
    }

    private struct StubError: LocalizedError {
        let errorDescription: String?
    }

    private let target = SupportRemoteSupportTarget(host: "10.0.0.5", source: .currentIPAddress)

    private func makeController(
        _ rec: CallRecorder,
        fetch: @escaping (SupportDeviceDetail) async throws -> [SupportMDMCommandRecord] = { _ in [] },
        reach: @escaping (SupportRemoteSupportTarget) async -> SupportRemoteSupportReachability = { _ in .unknown }
    ) -> SupportRemoteSupportController {
        SupportRemoteSupportController(
            enableCommand: { id in
                rec.enableManagementIDs.append(id)
                if let error = rec.enableError { throw error }
                return rec.enableResult
            },
            disableCommand: { id in
                rec.disableManagementIDs.append(id)
                if let error = rec.disableError { throw error }
                return rec.disableResult
            },
            launchURL: { rec.launchedURLs.append($0) },
            copyToClipboard: { rec.copiedStrings.append($0) },
            fetchCommandRecords: fetch,
            probeReachability: reach
        )
    }

    private func enableRecord(
        uuid: String = "enable-cmd",
        status: String,
        errorReasons: [String] = []
    ) -> SupportMDMCommandRecord {
        SupportMDMCommandRecord(
            uuid: uuid,
            commandType: "ENABLE_REMOTE_DESKTOP",
            status: status,
            dateSent: nil,
            dateCompleted: nil,
            errorReasons: errorReasons,
            source: .modern
        )
    }

    /// Drives a fresh controller to `queuedWaitingForCheckIn` with `enableCommandID == "enable-cmd"`
    /// and a usable manual target, ready for a readiness check.
    private func waitingController(
        _ rec: CallRecorder,
        fetch: @escaping (SupportDeviceDetail) async throws -> [SupportMDMCommandRecord] = { _ in [] },
        reach: @escaping (SupportRemoteSupportTarget) async -> SupportRemoteSupportReachability = { _ in .unknown }
    ) -> SupportRemoteSupportController {
        let controller = makeController(rec, fetch: fetch, reach: reach)
        controller.configure(for: makeDetail())
        controller.coordinator.beginEnable()
        controller.coordinator.enableQueued(commandID: "enable-cmd")
        controller.manualTargetOverride = "10.0.0.5"
        return controller
    }

    private func makeDetail(
        assetType: SupportAssetType = .computer,
        inventoryID: String = "1",
        managementID: String? = "mgmt-1",
        displayName: String = "Lab Mac"
    ) -> SupportDeviceDetail {
        let summary = SupportSearchResult(
            assetType: assetType,
            inventoryID: inventoryID,
            managementID: managementID,
            clientManagementID: nil,
            displayName: displayName,
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

    /// Yields the main actor until `predicate` holds or the iteration bound is hit, letting the
    /// controller's internal `Task` (which runs on the main actor) advance the coordinator.
    private func waitUntil(_ predicate: () -> Bool, iterations: Int = 2000) async {
        var n = 0
        while predicate() == false && n < iterations {
            await Task.yield()
            n += 1
        }
    }

    // MARK: - Frame visibility

    func test_shouldDisplayFrame_trueForMac_falseForMobile() {
        let rec = CallRecorder()
        let controller = makeController(rec)
        controller.configure(for: makeDetail(assetType: .computer))
        XCTAssertTrue(controller.shouldDisplayFrame)
        controller.configure(for: makeDetail(assetType: .mobileDevice, inventoryID: "2"))
        XCTAssertFalse(controller.shouldDisplayFrame)
    }

    // MARK: - Enable

    func test_enableRemoteManagement_queuesCommandAndAdvances() async {
        let rec = CallRecorder()
        let controller = makeController(rec)
        controller.configure(for: makeDetail())
        XCTAssertEqual(controller.state, .readyToPrepare)

        controller.enableRemoteManagement()
        await waitUntil { controller.state == .queuedWaitingForCheckIn(commandID: "enable-cmd") }

        XCTAssertEqual(rec.enableManagementIDs, ["mgmt-1"])
        XCTAssertEqual(controller.state, .queuedWaitingForCheckIn(commandID: "enable-cmd"))
        // Queue acceptance is NOT readiness — Open must remain unavailable.
        XCTAssertFalse(controller.state.canOpenScreenSharing)
        XCTAssertTrue(rec.launchedURLs.isEmpty)
    }

    func test_enableRemoteManagement_failure_movesToFailed_thenRetry() async {
        let rec = CallRecorder()
        rec.enableError = StubError(errorDescription: "Network unreachable")
        let controller = makeController(rec)
        controller.configure(for: makeDetail())

        controller.enableRemoteManagement()
        await waitUntil { controller.state.allowsRetry }

        if case .failed = controller.state {} else { XCTFail("expected failed, got \(controller.state)") }
        XCTAssertTrue(controller.state.allowsRetry)
        controller.retry()
        XCTAssertEqual(controller.state, .readyToPrepare)
    }

    func test_enableRemoteManagement_noopWhenNotReady() async {
        let rec = CallRecorder()
        let controller = makeController(rec)
        controller.configure(for: makeDetail(managementID: nil))   // needsManagementID
        XCTAssertEqual(controller.state, .needsManagementID)

        controller.enableRemoteManagement()
        await Task.yield()
        XCTAssertTrue(rec.enableManagementIDs.isEmpty)
        XCTAssertEqual(controller.state, .needsManagementID)
    }

    func test_enableRemoteManagement_noopForMobileUnsupported() async {
        let rec = CallRecorder()
        let controller = makeController(rec)
        controller.configure(for: makeDetail(assetType: .mobileDevice, inventoryID: "9"))
        if case .unsupported = controller.state {} else { return XCTFail("expected unsupported") }

        controller.enableRemoteManagement()
        await Task.yield()
        XCTAssertTrue(rec.enableManagementIDs.isEmpty, "An unsupported mobile device must never queue a command.")
        XCTAssertFalse(controller.shouldDisplayFrame)
    }

    // MARK: - Open Screen Sharing

    func test_openScreenSharing_requiresReadyToOpen_andLaunchesURL() {
        let rec = CallRecorder()
        let controller = makeController(rec)
        controller.configure(for: makeDetail())
        controller.coordinator.beginEnable()
        controller.coordinator.enableQueued(commandID: "cmd")
        controller.coordinator.markReadyToOpen(target: target)
        XCTAssertTrue(controller.state.canOpenScreenSharing)

        controller.openScreenSharing()

        XCTAssertEqual(rec.launchedURLs.count, 1)
        XCTAssertEqual(rec.launchedURLs.first, target.screenSharingURL)
        XCTAssertTrue(rec.launchedURLs.first?.absoluteString.hasPrefix("vnc://") ?? false)
        XCTAssertEqual(controller.state, .cleanupAvailable(target: target))
    }

    func test_openScreenSharing_noopBeforeReady() {
        let rec = CallRecorder()
        let controller = makeController(rec)
        controller.configure(for: makeDetail())
        controller.coordinator.beginEnable()
        controller.coordinator.enableQueued(commandID: "cmd")   // queuedWaitingForCheckIn

        controller.openScreenSharing()

        XCTAssertTrue(rec.launchedURLs.isEmpty)
        XCTAssertEqual(controller.state, .queuedWaitingForCheckIn(commandID: "cmd"))
    }

    // MARK: - Disable / cleanup

    func test_disableRemoteManagement_queuesDisableAndEnds() async {
        let rec = CallRecorder()
        let controller = makeController(rec)
        controller.configure(for: makeDetail())
        controller.coordinator.beginEnable()
        controller.coordinator.enableQueued(commandID: "cmd")
        controller.coordinator.markReadyToOpen(target: target)
        controller.coordinator.requestLaunch()
        controller.coordinator.launchRecorded()
        XCTAssertEqual(controller.state, .cleanupAvailable(target: target))

        controller.disableRemoteManagement()
        await waitUntil { controller.state == .ended }

        XCTAssertEqual(rec.disableManagementIDs, ["mgmt-1"])
        XCTAssertEqual(controller.state, .ended)
        XCTAssertEqual(controller.session?.disableCommandID, "disable-cmd")
    }

    // MARK: - Target override / copy

    func test_applyTargetOverride_advancesToReadyToOpenWhenWaiting() {
        let rec = CallRecorder()
        let controller = makeController(rec)
        controller.configure(for: makeDetail())
        controller.coordinator.beginEnable()
        controller.coordinator.enableQueued(commandID: "cmd")   // queuedWaitingForCheckIn

        controller.manualTargetOverride = "10.1.2.3"
        controller.applyTargetOverride()

        guard case let .readyToOpen(t) = controller.state else {
            return XCTFail("expected readyToOpen, got \(controller.state)")
        }
        XCTAssertEqual(t.host, "10.1.2.3")
        XCTAssertEqual(t.source, .manualOverride)
        XCTAssertTrue(controller.state.canOpenScreenSharing)
    }

    func test_copyConnectionTarget_copiesResolvedHost() {
        let rec = CallRecorder()
        let controller = makeController(rec)
        controller.configure(for: makeDetail())
        controller.manualTargetOverride = "10.9.9.9"
        controller.applyTargetOverride()   // records target on session (state stays readyToPrepare)

        controller.copyConnectionTarget()

        XCTAssertEqual(rec.copiedStrings, ["10.9.9.9"])
    }

    // MARK: - Diagnostics callback

    func test_viewDiagnostics_invokesCallback() {
        let rec = CallRecorder()
        let controller = makeController(rec)
        var invoked = false
        controller.onViewDiagnostics = { invoked = true }
        controller.viewDiagnostics()
        XCTAssertTrue(invoked)
    }

    // MARK: - Configure lifecycle

    func test_configure_sameDevice_preservesState_differentDevice_resets() {
        let rec = CallRecorder()
        let controller = makeController(rec)
        controller.configure(for: makeDetail(inventoryID: "1"))
        controller.coordinator.beginEnable()
        XCTAssertEqual(controller.state, .queueingEnableCommand)

        // Re-rendering the same device must not reset in-progress state.
        controller.configure(for: makeDetail(inventoryID: "1"))
        XCTAssertEqual(controller.state, .queueingEnableCommand)

        // Selecting a different device resets the workflow.
        controller.configure(for: makeDetail(inventoryID: "2"))
        XCTAssertEqual(controller.state, .readyToPrepare)
    }

    // MARK: - Readiness (Phase 5)

    func test_checkReadiness_commandConfirmed_andReachable_advancesToReadyToOpen() async {
        let rec = CallRecorder()
        let controller = waitingController(
            rec,
            fetch: { [self] _ in [enableRecord(status: "Acknowledged")] },
            reach: { _ in .reachable }
        )
        controller.checkReadiness()
        await waitUntil { controller.readinessReport != nil && controller.isCheckingReadiness == false }

        XCTAssertEqual(controller.readinessReport?.commandReadiness, .confirmed)
        XCTAssertEqual(controller.readinessReport?.reachability, .reachable)
        guard case .readyToOpen = controller.state else {
            return XCTFail("expected readyToOpen, got \(controller.state)")
        }
        XCTAssertTrue(controller.state.canOpenScreenSharing)
    }

    func test_checkReadiness_commandPending_staysWaiting() async {
        let rec = CallRecorder()
        let controller = waitingController(
            rec,
            fetch: { [self] _ in [enableRecord(status: "Pending")] },
            reach: { _ in .unknown }
        )
        controller.checkReadiness()
        await waitUntil { controller.readinessReport != nil && controller.isCheckingReadiness == false }

        XCTAssertEqual(controller.readinessReport?.commandReadiness, .pending)
        XCTAssertEqual(controller.state, .queuedWaitingForCheckIn(commandID: "enable-cmd"))
        XCTAssertFalse(controller.state.canOpenScreenSharing)
    }

    func test_checkReadiness_commandFailed_movesToFailed() async {
        let rec = CallRecorder()
        let controller = waitingController(
            rec,
            fetch: { [self] _ in [enableRecord(status: "Error - device offline", errorReasons: ["device offline"])] },
            reach: { _ in .unknown }
        )
        controller.checkReadiness()
        await waitUntil { controller.state.allowsRetry }

        if case .failed = controller.state {} else { XCTFail("expected failed, got \(controller.state)") }
        XCTAssertEqual(controller.readinessReport?.commandReadiness, .failed(reason: "device offline"))
    }

    /// A reachability failure must never be reported as a Jamf command failure, and must not block
    /// the attempt: an acknowledged command with an unreachable target still reaches readyToOpen.
    func test_checkReadiness_unreachable_doesNotFail_andStillReady() async {
        let rec = CallRecorder()
        let controller = waitingController(
            rec,
            fetch: { [self] _ in [enableRecord(status: "Acknowledged")] },
            reach: { _ in .unreachable }
        )
        controller.checkReadiness()
        await waitUntil { controller.readinessReport != nil && controller.isCheckingReadiness == false }

        XCTAssertEqual(controller.readinessReport?.reachability, .unreachable)
        XCTAssertEqual(controller.readinessReport?.commandReadiness, .confirmed)
        guard case .readyToOpen = controller.state else {
            return XCTFail("expected readyToOpen despite unreachable, got \(controller.state)")
        }
    }

    /// A command-status lookup failure (e.g. missing "View MDM command information" privilege) is
    /// uncertainty, not a command failure — the workflow stays usable and reports unknown.
    func test_checkReadiness_statusLookupThrows_isUnknownNotFailure() async {
        let rec = CallRecorder()
        struct LookupError: Error {}
        let controller = waitingController(
            rec,
            fetch: { _ in throw LookupError() },
            reach: { _ in .reachable }
        )
        controller.checkReadiness()
        await waitUntil { controller.readinessReport != nil && controller.isCheckingReadiness == false }

        XCTAssertEqual(controller.readinessReport?.commandReadiness, .unknown)
        if case .failed = controller.state { XCTFail("lookup failure must not fail the workflow") }
        guard case .readyToOpen = controller.state else {
            return XCTFail("expected readyToOpen (unknown + target), got \(controller.state)")
        }
    }
}

//endofline
