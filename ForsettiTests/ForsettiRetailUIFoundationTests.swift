import XCTest
import SwiftUI
#if os(macOS)
import AppKit
#endif
@testable import Forsetti

@MainActor
final class ForsettiRetailUIFoundationTests: XCTestCase {
    func testThemeDefinesObsidianDataStreamTokens() {
        XCTAssertEqual(ForsettiTheme.themeName, "Forsetti Obsidian Data Stream")
        XCTAssertEqual(ForsettiTheme.Opacity.glassFill, 0.78, accuracy: 0.001)
        XCTAssertEqual(ForsettiTheme.Opacity.glassBorder, 0.28, accuracy: 0.001)
        XCTAssertEqual(ForsettiTheme.Opacity.activeGlow, 0.72, accuracy: 0.001)

        assertColor(ForsettiColors.backgroundRoot, equalsHex: "#020611")
        assertColor(ForsettiColors.backgroundElevated, equalsHex: "#040913")
        assertColor(ForsettiColors.backgroundPanel, equalsHex: "#07111F")
        assertColor(ForsettiColors.backgroundPanelGlass, equalsHex: "#0B182B")
        assertColor(ForsettiColors.accentCyan, equalsHex: "#00E5FF")
        assertColor(ForsettiColors.accentCyanSoft, equalsHex: "#6CF6FF")
        assertColor(ForsettiColors.accentBlue, equalsHex: "#2F7FFF")
        assertColor(ForsettiColors.accentViolet, equalsHex: "#7A5CFF")
        assertColor(ForsettiColors.success, equalsHex: "#37FFB0")
        assertColor(ForsettiColors.warning, equalsHex: "#FFD166")
        assertColor(ForsettiColors.critical, equalsHex: "#FF5C8A")
        assertColor(ForsettiColors.textPrimary, equalsHex: "#EAFBFF")
        assertColor(ForsettiColors.textSecondary, equalsHex: "#A8C7D8")
        assertColor(ForsettiColors.textTertiary, equalsHex: "#63879A")
    }

    func testThemeDefinesRetailWorkspaceTokens() {
        XCTAssertEqual(ForsettiTheme.Layout.navigationRailWidth, 240)
        XCTAssertEqual(ForsettiTheme.Layout.navigationRailCollapsedWidth, 72)
        XCTAssertEqual(ForsettiTheme.Layout.rightInspectorWidth, 340)
        XCTAssertEqual(ForsettiTheme.Layout.commandActivityBarHeight, 54)
        XCTAssertEqual(ForsettiTheme.Radius.small, 10)
        XCTAssertEqual(ForsettiTheme.Radius.medium, 16)
        XCTAssertEqual(ForsettiTheme.Radius.large, 22)
        XCTAssertEqual(ForsettiTheme.Radius.panel, 28)
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

    func testActivityStateCoversObsidianCommandPhases() {
        let preparing = ForsettiCommandActivityState.preparing(
            label: "Preparing command",
            progress: -0.4
        )
        let waitingForJamf = ForsettiCommandActivityState.waitingForJamf(
            label: "Waiting for Jamf Pro response"
        )
        let pollingStatus = ForsettiCommandActivityState.pollingStatus(
            label: "Polling device status",
            progress: 0.42
        )
        let cancelled = ForsettiCommandActivityState.cancelled(label: "Cancelled by operator")

        XCTAssertEqual(preparing.progress, 0)
        XCTAssertEqual(preparing.accessibilityValue, "0 percent")
        XCTAssertTrue(preparing.isActive)
        XCTAssertEqual(preparing.symbolName, "slider.horizontal.3")
        XCTAssertEqual(waitingForJamf.accessibilityValue, "Active")
        XCTAssertEqual(waitingForJamf.symbolName, "network")
        XCTAssertEqual(pollingStatus.progress ?? -1, 0.42, accuracy: 0.001)
        XCTAssertEqual(pollingStatus.summaryText, "Polling device status")
        XCTAssertEqual(pollingStatus.symbolName, "dot.radiowaves.left.and.right")
        XCTAssertFalse(cancelled.isActive)
        XCTAssertEqual(cancelled.accessibilityValue, "Cancelled")
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

    func testDiagnosticsDrawerConstructible() {
        let item = ForsettiDiagnosticsDrawer.Item(
            title: "Framework boundary",
            value: "Retail UI module",
            kind: .ready
        )
        let drawer = ForsettiDiagnosticsDrawer(items: [item])

        XCTAssertEqual(item.accessibilityText, "Framework boundary, Retail UI module")
        _ = drawer.body
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
