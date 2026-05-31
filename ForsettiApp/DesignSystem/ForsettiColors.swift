import SwiftUI

/// Central color tokens for the Forsetti retail visual system.
enum ForsettiColors {
    static let backgroundRoot = rgb(0x05070C)
    static let backgroundElevated = rgb(0x0A1018)
    static let backgroundPanel = rgb(0x0E1622)
    static let backgroundPanelGlass = rgb(0x0C1622)
    static let backgroundDepth = rgb(0x071B26)
    static let backgroundVignette = rgb(0x02070C)
    static let toolbar = rgb(0x060C14)

    static let accentCyan = rgb(0x00E5FF)
    static let accentCyanSoft = rgb(0x5FF4FF)
    static let accentTeal = rgb(0x00F0D0)
    static let accentBlue = rgb(0x2196FF)
    static let accentIndigo = rgb(0x6D5DFF)
    static let accentViolet = rgb(0x9A6CFF)

    static let success = rgb(0x3EF2A3)
    static let warning = rgb(0xFFCC66)
    static let critical = rgb(0xFF5A7A)
    static let offline = rgb(0x7C8794)
    static let info = rgb(0x5FD9FF)

    static let textPrimary = rgb(0xF4FAFF)
    static let textSecondary = rgb(0xB7C6D8)
    static let textTertiary = rgb(0x7D8FA6)
    static let textDisabled = rgb(0x4B5867)
    static let textInverse = rgb(0x001018)

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
