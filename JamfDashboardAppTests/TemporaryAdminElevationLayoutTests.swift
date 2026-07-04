import XCTest
@testable import Jamf_Dashboard

/// Deterministic presentation/layout tests for the Temporary Admin Elevation
/// frame. The project has no snapshot infrastructure, so these assert the pure
/// presentation mapping, the Reduce Motion gate, and the adaptive-control data,
/// and the manual visual verification is documented in the implementation report.
final class TemporaryAdminElevationLayoutTests: XCTestCase {

    func test_readyPresentationCopy() {
        let p = TemporaryAdminStatusPresentation.make(for: .ready)
        XCTAssertEqual(p.badge, "Ready")
        XCTAssertEqual(p.tone, .neutral)
        XCTAssertTrue(p.description.contains("temporarily promotes the currently signed-in Mac user"))
    }

    func test_waitingPresentationCopy() {
        let p = TemporaryAdminStatusPresentation.make(for: .waitingForCheckIn(requestedAt: Date()))
        XCTAssertEqual(p.tone, .active)
        XCTAssertTrue(p.description.contains("Waiting for the Mac to check in"))
    }

    func test_timedOutPresentationCopy() {
        let p = TemporaryAdminStatusPresentation.make(for: .timedOut)
        XCTAssertEqual(p.tone, .danger)
        XCTAssertTrue(p.description.contains("could not confirm"))
    }

    func test_elevatedPresentationNamesUser() {
        let p = TemporaryAdminStatusPresentation.make(for: .elevated(user: "alice", expiresAt: nil, runId: nil))
        XCTAssertEqual(p.badge, "Elevated")
        XCTAssertEqual(p.tone, .success)
        XCTAssertTrue(p.description.contains("alice"))
    }

    func test_permissionDeniedPresentationStatesNoMacChange() {
        let p = TemporaryAdminStatusPresentation.make(for: .permissionDenied(requiredPrivileges: ["x"]))
        XCTAssertEqual(p.tone, .danger)
        XCTAssertTrue(p.description.contains("No Mac permissions were changed."))
    }

    func test_everyStateProducesNonEmptyCopy() {
        let states: [TemporaryAdminElevationState] = [
            .unavailable(reason: "r"), .notConfigured(reason: "r"), .ready, .validating, .requesting,
            .waitingForCheckIn(requestedAt: Date()),
            .elevated(user: "u", expiresAt: nil, runId: nil),
            .alreadyAdmin(user: "u", runId: nil),
            .demotionRequested(requestedAt: Date()),
            .demoted(user: "u", runId: nil),
            .timedOut, .failed(message: "m"),
            .permissionDenied(requiredPrivileges: []),
            .cleanupWarning(message: "m", underlyingState: "elevated")
        ]
        for state in states {
            let p = TemporaryAdminStatusPresentation.make(for: state)
            XCTAssertFalse(p.title.isEmpty, "Title empty for \(state)")
            XCTAssertFalse(p.description.isEmpty, "Description empty for \(state)")
            XCTAssertFalse(p.badge.isEmpty, "Badge empty for \(state)")
        }
    }

    func test_reduceMotionDisablesCountdownAnimation() {
        XCTAssertFalse(TemporaryAdminElevationFrame.countdownAnimationEnabled(reduceMotion: true))
        XCTAssertTrue(TemporaryAdminElevationFrame.countdownAnimationEnabled(reduceMotion: false))
    }

    func test_durationDisplayNamesAndAccessibilityLabels() {
        XCTAssertEqual(TemporaryAdminDuration.five.displayName, "5 minutes")
        XCTAssertEqual(TemporaryAdminDuration.sixty.accessibilityLabel, "60 minutes")
    }

    @MainActor
    func test_controllerExposesAdaptiveControlData() {
        let controller = TemporaryAdminElevationController(
            configuration: TemporaryAdminTestSupport.enabledConfiguration(),
            service: MockTemporaryAdminService(),
            diagnostics: RecordingDiagnostics()
        )
        XCTAssertEqual(controller.availableDurations, TemporaryAdminDuration.allCases)
        XCTAssertTrue(controller.requiresTicket)
        XCTAssertFalse(controller.requiredPrivileges.isEmpty)
    }
}
