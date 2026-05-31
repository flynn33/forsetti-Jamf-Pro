import XCTest
import SwiftUI
@testable import Forsetti

@MainActor
final class ForsettiRetailUIFoundationTests: XCTestCase {
    func testThemeDefinesRetailWorkspaceTokens() {
        XCTAssertEqual(ForsettiTheme.Layout.navigationRailWidth, 240)
        XCTAssertEqual(ForsettiTheme.Layout.navigationRailCollapsedWidth, 72)
        XCTAssertEqual(ForsettiTheme.Layout.rightInspectorWidth, 340)
        XCTAssertEqual(ForsettiTheme.Layout.commandActivityBarHeight, 54)
        XCTAssertEqual(ForsettiTheme.Radius.panel, 22)
        XCTAssertEqual(ForsettiTheme.Radius.capsule, 999)
    }

    func testStatusBadgeSemanticCoverage() {
        let expected: Set<ForsettiStatusBadge.Kind> = [
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
            .permissionDenied
        ]

        XCTAssertEqual(Set(ForsettiStatusBadge.Kind.allCases), expected)
        XCTAssertEqual(ForsettiStatusBadge(.connected).accessibilityText, "Connected")
        XCTAssertEqual(ForsettiStatusBadge(.permissionDenied).accessibilityText, "Permission denied")
        XCTAssertEqual(ForsettiStatusBadge(.queued, text: "Queued for device").accessibilityText, "Queued for device")
    }

    func testActivityStateProgressClampingAndAccessibilityText() {
        let active = ForsettiCommandActivityState.sendingCommand(
            label: "Sending inventory update",
            progress: 1.4
        )
        let failed = ForsettiCommandActivityState.failed(
            label: "Update inventory",
            message: "Permission denied",
            retryAvailable: false
        )
        let idleDate = Date(timeIntervalSinceReferenceDate: 12)
        let idle = ForsettiCommandActivityState.idle(lastUpdated: idleDate)
        let permissionDenied = ForsettiCommandActivityState.permissionDenied(
            label: "Erase device",
            requiredPrivilege: "Device Management"
        )

        XCTAssertEqual(active.progress, 1.0)
        XCTAssertEqual(active.accessibilityValue, "100 percent")
        XCTAssertEqual(failed.accessibilityLabel, "Update inventory: Permission denied")
        XCTAssertEqual(failed.symbolName, "xmark.octagon.fill")
        XCTAssertFalse(failed.retryAvailable)
        XCTAssertEqual(idle.lastUpdated, idleDate)
        XCTAssertEqual(permissionDenied.requiredPrivilege, "Device Management")

        let commandLifecycle = CommandLifecyclePhase.sending(
            action: .scheduleOSUpdate,
            startedAt: Date(timeIntervalSinceReferenceDate: 0)
        )
        let adapted = ForsettiCommandActivityState(commandLifecycle: commandLifecycle)

        XCTAssertEqual(adapted.progress, 0.25)
        XCTAssertEqual(adapted.label, "Schedule OS Update")
    }

    func testWorkspaceShellAndGlassCardAreConstructible() {
        let shell = ForsettiWorkspaceShell(
            navigation: { Text("Navigation") },
            commandActivityBar: { Text("Activity") },
            header: { Text("Header") },
            content: { Text("Content") },
            inspector: { Text("Inspector") },
            bottomDrawer: { Text("Drawer") }
        )
        let card = ForsettiGlassCard(style: .dense) {
            Text("Card")
        }
        let activityBar = ForsettiCommandActivityBar(
            state: .querying(label: "Querying inventory", progress: nil)
        )

        _ = shell.body
        _ = card.body
        _ = activityBar.body
    }
}
