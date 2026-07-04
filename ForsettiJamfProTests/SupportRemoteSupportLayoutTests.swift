import XCTest
@testable import ForsettiJamfProApp

/// Deterministic presentation/layout tests for the Remote Support frame. The project has no
/// snapshot infrastructure, so these assert the pure status-pill mapping (every state has a
/// non-empty badge and a tone), the spec status labels, and the Reduce-Motion posture (the frame
/// requires no motion to understand state). Manual cross-platform visual verification (iPhone
/// portrait, iPad portrait/landscape, Mac Catalyst, Dynamic Type) is documented in the report.
final class SupportRemoteSupportLayoutTests: XCTestCase {

    private let target = SupportRemoteSupportTarget(host: "10.0.0.5", source: .currentIPAddress)

    private func allStates() -> [SupportRemoteSupportState] {
        [
            .unsupported(reason: "r"),
            .needsManagementID,
            .readyToPrepare,
            .queueingEnableCommand,
            .queuedWaitingForCheckIn(commandID: "c"),
            .readinessUnknown(commandID: "c"),
            .readyToOpen(target: target),
            .launchRequested(target: target),
            .cleanupAvailable(target: target),
            .queueingDisableCommand,
            .ended,
            .failed(SupportRemoteSupportFailure(summary: "s", isSafeToRetry: true, recommendation: "r"))
        ]
    }

    func test_everyStateProducesNonEmptyBadge() {
        for state in allStates() {
            let p = SupportRemoteSupportStatusPresentation.make(for: state)
            XCTAssertFalse(p.badge.isEmpty, "Empty badge for \(state)")
        }
    }

    func test_everyStateAlsoHasNonEmptyHeadlineAndDiagnosticsName() {
        for state in allStates() {
            XCTAssertFalse(state.headline.isEmpty, "Empty headline for \(state)")
            XCTAssertFalse(state.diagnosticsName.isEmpty, "Empty diagnostics name for \(state)")
        }
    }

    func test_specStatusLabels() {
        XCTAssertEqual(SupportRemoteSupportStatusPresentation.make(for: .readyToPrepare).badge, "Ready")
        XCTAssertEqual(SupportRemoteSupportStatusPresentation.make(for: .queuedWaitingForCheckIn(commandID: nil)).badge, "Waiting for Check-In")
        XCTAssertEqual(SupportRemoteSupportStatusPresentation.make(for: .readyToOpen(target: target)).badge, "Ready to Open")
        XCTAssertEqual(SupportRemoteSupportStatusPresentation.make(for: .cleanupAvailable(target: target)).badge, "Cleanup Needed")
        XCTAssertEqual(SupportRemoteSupportStatusPresentation.make(for: .ended).badge, "Ended")
    }

    func test_tones() {
        XCTAssertEqual(SupportRemoteSupportStatusPresentation.make(for: .readyToPrepare).tone, .success)
        XCTAssertEqual(SupportRemoteSupportStatusPresentation.make(for: .readyToOpen(target: target)).tone, .success)
        XCTAssertEqual(SupportRemoteSupportStatusPresentation.make(for: .failed(SupportRemoteSupportFailure(summary: "s", isSafeToRetry: false, recommendation: "r"))).tone, .danger)
        XCTAssertEqual(SupportRemoteSupportStatusPresentation.make(for: .queueingEnableCommand).tone, .active)
        XCTAssertEqual(SupportRemoteSupportStatusPresentation.make(for: .unsupported(reason: "r")).tone, .neutral)
        XCTAssertEqual(SupportRemoteSupportStatusPresentation.make(for: .ended).tone, .neutral)
    }

    func test_frameRequiresNoMotionToUnderstandState() {
        XCTAssertFalse(SupportRemoteSupportFrame.usesRequiredMotion)
    }
}

//endofline
