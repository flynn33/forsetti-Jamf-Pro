import XCTest
@testable import ForsettiJamfProApp

final class DashboardDesignTokenTests: XCTestCase {

    func test_statusPillCoversHandoffSemanticStates() {
        let required: Set<ForsettiSemanticStatus> = [
            .connected,
            .reachable,
            .trusted,
            .compliant,
            .ready,
            .pending,
            .stale,
            .warning,
            .blocked,
            .failed,
            .succeeded,
            .queued,
            .verifying,
            .unsupported,
            .permissionDenied,
            .nonCompliant,
            .enrolled,
            .supervised,
            .active,
            .healthy
        ]

        XCTAssertTrue(Set(ForsettiSemanticStatus.allCases).isSuperset(of: required))
    }

    func test_everyStatusHasDisplaySymbolAndAccessibilityCopy() {
        for status in ForsettiSemanticStatus.allCases {
            XCTAssertFalse(status.displayText.isEmpty, "Missing display text for \(status)")
            XCTAssertFalse(status.symbolName.isEmpty, "Missing symbol for \(status)")
            XCTAssertFalse(status.accessibilityLabel.isEmpty, "Missing accessibility label for \(status)")
        }
    }

    func test_commandStreamCoversRequiredStates() {
        let required: Set<ForsettiCommandStreamState> = [
            .idle,
            .querying,
            .sending,
            .waiting,
            .validating,
            .rendering,
            .exporting,
            .completed,
            .failed,
            .blocked,
            .cancelled,
            .permissionDenied
        ]

        XCTAssertEqual(Set(ForsettiCommandStreamState.allCases), required)
    }

    func test_layoutTokensMatchOperationsCockpitScale() {
        XCTAssertEqual(DashboardTheme.Layout.navigationRailWidth, 240, accuracy: 0.001)
        XCTAssertEqual(DashboardTheme.Layout.rightInspectorWidth, 340, accuracy: 0.001)
        XCTAssertEqual(DashboardTheme.Layout.commandStreamHeight, 52, accuracy: 0.001)
        XCTAssertEqual(DashboardTheme.Layout.dataTableRowHeight, 48, accuracy: 0.001)
        XCTAssertEqual(DashboardTheme.Layout.metricCardHeight, 166, accuracy: 0.001)
        XCTAssertEqual(DashboardTheme.Layout.moduleCardHeight, 160, accuracy: 0.001)
        XCTAssertEqual(DashboardTheme.Layout.supportTileHeight, 112, accuracy: 0.001)
        XCTAssertEqual(DashboardTheme.Layout.compactBreakpoint, 960, accuracy: 0.001)
        XCTAssertEqual(DashboardTheme.Layout.inspectorBreakpoint, 1480, accuracy: 0.001)
    }
}
