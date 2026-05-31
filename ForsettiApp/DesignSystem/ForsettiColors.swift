import SwiftUI

/// Central color tokens for the Forsetti retail visual system.
enum ForsettiColors {
    static let backgroundRoot = rgb(0x020611)
    static let backgroundElevated = rgb(0x040913)
    static let backgroundPanel = rgb(0x07111F)
    static let backgroundPanelGlass = rgb(0x0B182B)
    static let backgroundDepth = rgb(0x10233B)
    static let backgroundVignette = rgb(0x01030A)
    static let toolbar = rgb(0x06101D)

    static let accentCyan = rgb(0x00E5FF)
    static let accentCyanSoft = rgb(0x6CF6FF)
    static let accentTeal = rgb(0x37FFB0)
    static let accentBlue = rgb(0x2F7FFF)
    static let accentIndigo = rgb(0x7A5CFF)
    static let accentViolet = rgb(0x7A5CFF)
    static let accentMagenta = rgb(0xFF4FD8)

    static let success = rgb(0x37FFB0)
    static let warning = rgb(0xFFD166)
    static let critical = rgb(0xFF5C8A)
    static let offline = rgb(0x63879A)
    static let info = rgb(0x6CF6FF)

    static let textPrimary = rgb(0xEAFBFF)
    static let textSecondary = rgb(0xA8C7D8)
    static let textTertiary = rgb(0x63879A)
    static let textDisabled = rgb(0x4B5867)
    static let textInverse = rgb(0x020611)

    static let bluePrimary = accentCyan
    static let greenPrimary = success
    static let blueSecondary = accentCyanSoft

    private static func rgb(_ value: UInt32) -> Color {
        Color(
            red: Double((value >> 16) & 0xFF) / 255.0,
            green: Double((value >> 8) & 0xFF) / 255.0,
            blue: Double(value & 0xFF) / 255.0
        )
    }
}

//endofline
