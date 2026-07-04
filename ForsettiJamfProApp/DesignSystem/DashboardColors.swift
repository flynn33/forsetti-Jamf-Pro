import SwiftUI

/// Centralized color tokens for the app's dark operations cockpit visual system.
enum DashboardColors {
    static let backgroundRoot = Color.dashboardHex(0x020611)
    static let backgroundVignette = Color.dashboardHex(0x01030A)
    static let backgroundElevated = Color.dashboardHex(0x040913)
    static let backgroundPanel = Color.dashboardHex(0x07111F)
    static let backgroundPanelGlass = Color.dashboardHex(0x0B182B)
    static let backgroundDepth = Color.dashboardHex(0x10233B)
    static let railSurface = Color.dashboardHex(0x06101D)
    static let tableRow = Color.dashboardHex(0x061627)
    static let tableRowSelected = Color.dashboardHex(0x082C42)
    static let separator = Color.dashboardHex(0x18334A)

    static let accentCyan = Color.dashboardHex(0x00E5FF)
    static let accentCyanSoft = Color.dashboardHex(0x6CF6FF)
    static let accentBlue = Color.dashboardHex(0x2F7FFF)
    static let accentViolet = Color.dashboardHex(0x7A5CFF)
    static let accentMagenta = Color.dashboardHex(0xFF4FD8)

    static let success = Color.dashboardHex(0x37FFB0)
    static let warning = Color.dashboardHex(0xFFD166)
    static let amber = Color.dashboardHex(0xFF9F1C)
    static let critical = Color.dashboardHex(0xFF5C8A)
    static let danger = Color.dashboardHex(0xFF4D5E)
    static let offline = Color.dashboardHex(0x63879A)

    static let textPrimary = Color.dashboardHex(0xEAFBFF)
    static let textSecondary = Color.dashboardHex(0xA8C7D8)
    static let textTertiary = Color.dashboardHex(0x63879A)
    static let textDisabled = Color.dashboardHex(0x4B5867)
    static let textInverse = Color.dashboardHex(0x020611)

    /// Legacy aliases retained for existing module views while they migrate to semantic tokens.
    static let bluePrimary = accentCyan
    static let greenPrimary = success
    static let blueSecondary = accentBlue

    static func statusColor(named name: String) -> Color {
        switch name {
        case "healthy", "connected", "compliant", "ready", "completed", "succeeded", "enrolled", "supervised":
            return success
        case "inProgress", "querying", "queued", "verifying", "active", "sending", "waiting", "validating", "rendering", "exporting":
            return accentCyan
        case "configured":
            return accentBlue
        case "workflow":
            return accentViolet
        case "pending", "warning":
            return warning
        case "stale":
            return amber
        case "exception", "critical", "blocked":
            return critical
        case "failed", "nonCompliant", "permissionDenied", "danger":
            return danger
        case "offline", "unsupported", "cancelled":
            return offline
        default:
            return accentCyan
        }
    }
}

private extension Color {
    static func dashboardHex(_ hex: UInt32, opacity: Double = 1) -> Color {
        Color(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255.0,
            green: Double((hex >> 8) & 0xFF) / 255.0,
            blue: Double(hex & 0xFF) / 255.0,
            opacity: opacity
        )
    }
}

//endofline
