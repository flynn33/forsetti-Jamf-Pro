import XCTest
import SwiftUI
#if os(macOS)
import AppKit
#endif
@testable import Forsetti

@MainActor
final class ForsettiRetailUIFoundationTests: XCTestCase {
    func testThemeDefinesCyanDataStreamTokens() {
        XCTAssertEqual(ForsettiTheme.themeName, "Forsetti Cyan Data Stream")
        XCTAssertEqual(ForsettiTheme.Opacity.glassFill, 0.72, accuracy: 0.001)
        XCTAssertEqual(ForsettiTheme.Opacity.glassBorder, 0.18, accuracy: 0.001)
        XCTAssertEqual(ForsettiTheme.Opacity.activeGlow, 0.72, accuracy: 0.001)

        assertColor(ForsettiColors.backgroundRoot, equalsHex: "#05070C")
        assertColor(ForsettiColors.backgroundPanel, equalsHex: "#0E1622")
        assertColor(ForsettiColors.accentCyan, equalsHex: "#00E5FF")
        assertColor(ForsettiColors.accentTeal, equalsHex: "#00F0D0")
        assertColor(ForsettiColors.success, equalsHex: "#3EF2A3")
        assertColor(ForsettiColors.warning, equalsHex: "#FFCC66")
        assertColor(ForsettiColors.critical, equalsHex: "#FF5A7A")
        assertColor(ForsettiColors.textPrimary, equalsHex: "#F4FAFF")
    }

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
        XCTAssertEqual(adapted.summaryText, "Schedule OS Update")
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

    private func assertColor(
        _ color: Color,
        equalsHex hex: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
#if os(macOS)
        let expected = Self.components(from: hex)
        guard let actual = NSColor(color).usingColorSpace(.sRGB) else {
            XCTFail("Unable to resolve color in sRGB", file: file, line: line)
            return
        }

        XCTAssertEqual(actual.redComponent, expected.red, accuracy: 0.004, file: file, line: line)
        XCTAssertEqual(actual.greenComponent, expected.green, accuracy: 0.004, file: file, line: line)
        XCTAssertEqual(actual.blueComponent, expected.blue, accuracy: 0.004, file: file, line: line)
#endif
    }

    private static func components(from hex: String) -> (red: CGFloat, green: CGFloat, blue: CGFloat) {
        let raw = hex.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        let value = Int(raw, radix: 16) ?? 0
        return (
            red: CGFloat((value >> 16) & 0xFF) / 255,
            green: CGFloat((value >> 8) & 0xFF) / 255,
            blue: CGFloat(value & 0xFF) / 255
        )
    }
}
