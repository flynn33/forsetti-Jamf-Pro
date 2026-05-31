import SwiftUI

/// Central layout, surface, and motion-adjacent tokens for the Forsetti app.
enum ForsettiTheme {
    static let themeName = "Forsetti Cyan Data Stream"

    // MARK: - Layout Tokens

    enum Radius {
        static let small: CGFloat = 8
        static let medium: CGFloat = 12
        static let card: CGFloat = 18
        static let large: CGFloat = 18
        static let panel: CGFloat = 22
        static let button: CGFloat = 12
        static let capsule: CGFloat = 999
    }

    enum Spacing {
        static let xs: CGFloat = 4
        static let sm: CGFloat = 8
        static let md: CGFloat = 12
        static let lg: CGFloat = 16
        static let xl: CGFloat = 24
        static let xxl: CGFloat = 32

        static let section = xl
        static let item = md
        static let compact = sm
    }

    enum Opacity {
        static let glassFill = 0.72
        static let toolbar = 0.82
        static let glassBorder = 0.18
        static let activeGlow = 0.72
        static let disabled = 0.42
    }

    enum Layout {
        static let navigationRailWidth: CGFloat = 240
        static let navigationRailCollapsedWidth: CGFloat = 72
        static let rightInspectorWidth: CGFloat = 340
        static let commandActivityBarHeight: CGFloat = 54
    }

    // MARK: - Semantic Colors

    static let accent = ForsettiColors.accentCyan
    static let surface = ForsettiColors.backgroundPanel
    static let groupedSurface = ForsettiColors.backgroundElevated
    static let glassSurface = ForsettiColors.backgroundPanelGlass.opacity(Opacity.glassFill)
    static let toolbarSurface = ForsettiColors.toolbar.opacity(Opacity.toolbar)
    static let border = ForsettiColors.accentCyan.opacity(Opacity.glassBorder)
    static let strongBorder = ForsettiColors.accentCyan.opacity(Opacity.activeGlow)
    static let warningBorder = ForsettiColors.warning.opacity(0.70)
    static let criticalBorder = ForsettiColors.critical.opacity(0.74)
    static let shadowColor = Color.black.opacity(0.35)
    static let shadowColorStrong = ForsettiColors.accentCyan.opacity(0.22)
    static let buttonTextOnPrimary = ForsettiColors.textInverse

    // MARK: - Gradients

    static var dataStreamGradient: LinearGradient {
        LinearGradient(
            colors: [
                ForsettiColors.accentCyan,
                ForsettiColors.accentBlue,
                ForsettiColors.accentIndigo
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    static var glassPanelGradient: LinearGradient {
        LinearGradient(
            colors: [
                ForsettiColors.backgroundPanel.opacity(0.92),
                ForsettiColors.backgroundPanelGlass.opacity(Opacity.glassFill),
                ForsettiColors.accentBlue.opacity(0.10)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    static var primaryButtonGradient: LinearGradient {
        LinearGradient(
            colors: [
                ForsettiColors.accentCyan,
                ForsettiColors.accentTeal,
                ForsettiColors.accentBlue
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    static var appBackdropGradient: LinearGradient {
        LinearGradient(
            colors: [
                ForsettiColors.backgroundVignette.opacity(0.96),
                ForsettiColors.backgroundRoot,
                ForsettiColors.backgroundDepth.opacity(0.86),
                ForsettiColors.accentBlue.opacity(0.10)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    // MARK: - Background Builder

    @ViewBuilder
    static func appBackground() -> some View {
        ZStack {
            ForsettiColors.backgroundRoot
            appBackdropGradient
            LinearGradient(
                colors: [
                    Color.clear,
                    ForsettiColors.accentCyan.opacity(0.08),
                    Color.clear,
                    ForsettiColors.accentTeal.opacity(0.05)
                ],
                startPoint: .topTrailing,
                endPoint: .bottomLeading
            )
        }
    }
}

//endofline
