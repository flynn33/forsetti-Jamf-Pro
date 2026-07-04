import XCTest
@testable import Jamf_Dashboard

/// Tests for `TemporaryAdminElevationController`, the `@MainActor` controller
/// that drives the frame. Uses a scriptable mock service.
@MainActor
final class TemporaryAdminElevationViewModelTests: XCTestCase {

    private func makeController(
        config: TemporaryAdminElevationConfiguration,
        service: MockTemporaryAdminService
    ) -> TemporaryAdminElevationController {
        TemporaryAdminElevationController(
            configuration: config,
            service: service,
            diagnostics: RecordingDiagnostics()
        )
    }

    func test_disabledConfigurationShowsNotConfigured() {
        let controller = makeController(config: .disabledDefault, service: MockTemporaryAdminService())
        controller.configure(for: TemporaryAdminTestSupport.makeDetail())
        if case .notConfigured = controller.state {} else { XCTFail("Expected notConfigured, got \(controller.state)") }
    }

    func test_mobileDeviceDoesNotDisplayFrame() {
        let controller = makeController(config: TemporaryAdminTestSupport.enabledConfiguration(), service: MockTemporaryAdminService())
        controller.configure(for: TemporaryAdminTestSupport.makeDetail(assetType: .mobileDevice))
        XCTAssertFalse(controller.shouldDisplayFrame, "Mobile devices must not show the elevation frame.")
        XCTAssertFalse(controller.isEligible)
    }

    func test_eligibleManagedMacIsEligible() {
        let controller = makeController(config: TemporaryAdminTestSupport.enabledConfiguration(), service: MockTemporaryAdminService())
        controller.configure(for: TemporaryAdminTestSupport.makeDetail())
        XCTAssertTrue(controller.shouldDisplayFrame)
        XCTAssertTrue(controller.isEligible)
    }

    func test_requestButtonGatedOnValidation() {
        let controller = makeController(config: TemporaryAdminTestSupport.enabledConfiguration(requireTicket: true), service: MockTemporaryAdminService())
        controller.configure(for: TemporaryAdminTestSupport.makeDetail())

        controller.reason = ""
        controller.ticketReference = ""
        XCTAssertFalse(controller.isRequestEnabled, "Empty reason/ticket should disable the request.")

        controller.reason = "needs admin"
        controller.ticketReference = "TICKET-1"
        XCTAssertTrue(controller.isRequestEnabled)
    }

    func test_confirmRequestEntersWaitingAndBlocksDuplicate() async {
        let service = MockTemporaryAdminService()
        let controller = makeController(config: TemporaryAdminTestSupport.enabledConfiguration(), service: service)
        controller.configure(for: TemporaryAdminTestSupport.makeDetail())
        controller.reason = "needs admin"
        controller.ticketReference = "TICKET-1"

        await controller.confirmRequest()

        if case .waitingForCheckIn = controller.state {} else { XCTFail("Expected waitingForCheckIn, got \(controller.state)") }
        let count = await service.requests()
        XCTAssertEqual(count, 1)
        XCTAssertFalse(controller.isRequestEnabled, "A second request must be blocked while one is active.")
        controller.stop()
    }

    func test_confirmRequestPermissionFailureSurfacesError() async {
        let service = MockTemporaryAdminService(requestError: JamfFrameworkError.forbidden(message: "denied"))
        let controller = makeController(config: TemporaryAdminTestSupport.enabledConfiguration(), service: service)
        controller.configure(for: TemporaryAdminTestSupport.makeDetail())
        controller.reason = "needs admin"
        controller.ticketReference = "TICKET-1"

        await controller.confirmRequest()

        XCTAssertNotNil(controller.userFacingError)
        if case .permissionDenied = controller.state {} else { XCTFail("Expected permissionDenied, got \(controller.state)") }
        controller.stop()
    }

    func test_demoteNowEntersDemotionRequested() async {
        let service = MockTemporaryAdminService()
        let controller = makeController(config: TemporaryAdminTestSupport.enabledConfiguration(), service: service)
        controller.configure(for: TemporaryAdminTestSupport.makeDetail())

        await controller.demoteNow()

        if case .demotionRequested = controller.state {} else { XCTFail("Expected demotionRequested, got \(controller.state)") }
        let count = await service.demotes()
        XCTAssertEqual(count, 1)
        controller.stop()
    }

    func test_refreshWithoutActiveRequestAppliesFreshSnapshot() async {
        let elevated = TemporaryAdminElevationSnapshot(
            state: .elevated(user: "consoleuser", expiresAt: nil, runId: "r1"),
            statusRawValue: "elevated",
            user: "consoleuser",
            expiresAt: nil,
            lastChange: nil,
            runId: "r1"
        )
        let service = MockTemporaryAdminService(refreshSnapshotResult: elevated)
        let controller = makeController(config: TemporaryAdminTestSupport.enabledConfiguration(), service: service)
        controller.configure(for: TemporaryAdminTestSupport.makeDetail())

        await controller.refresh()

        XCTAssertEqual(controller.snapshot?.runId, "r1")
        if case .elevated = controller.state {} else { XCTFail("Expected elevated, got \(controller.state)") }
    }
}
