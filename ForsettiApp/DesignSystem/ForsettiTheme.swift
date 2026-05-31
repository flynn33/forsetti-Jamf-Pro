import SwiftUI

/// Central layout, surface, and motion-adjacent tokens for the Forsetti app.
enum ForsettiTheme {
    static let themeName = "Forsetti Obsidian Data Stream"

    // MARK: - Layout Tokens

    enum Radius {
        static let small: CGFloat = 10
        static let medium: CGFloat = 16
        static let card: CGFloat = 22
        static let large: CGFloat = 22
        static let panel: CGFloat = 28
        static let button: CGFloat = 14
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
        static let glassFill = 0.78
        static let toolbar = 0.86
        static let glassBorder = 0.28
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
    static let shadowColor = Color.black.opacity(0.46)
    static let shadowColorStrong = ForsettiColors.accentCyan.opacity(0.30)
    static let buttonTextOnPrimary = ForsettiColors.textInverse

    // MARK: - Gradients

    static var dataStreamGradient: LinearGradient {
        LinearGradient(
            colors: [
                ForsettiColors.accentCyan,
                ForsettiColors.accentBlue,
                ForsettiColors.accentViolet
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    static var glassPanelGradient: LinearGradient {
        LinearGradient(
            colors: [
                ForsettiColors.backgroundPanel.opacity(0.94),
                ForsettiColors.backgroundPanelGlass.opacity(Opacity.glassFill),
                ForsettiColors.accentViolet.opacity(0.12)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    static var primaryButtonGradient: LinearGradient {
        LinearGradient(
            colors: [
                ForsettiColors.accentCyan,
                ForsettiColors.accentBlue,
                ForsettiColors.accentViolet
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
                ForsettiColors.accentViolet.opacity(0.12)
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
            ForsettiDataStreamGrid()
            LinearGradient(
                colors: [
                    Color.clear,
                    ForsettiColors.accentCyan.opacity(0.10),
                    Color.clear,
                    ForsettiColors.accentViolet.opacity(0.08)
                ],
                startPoint: .topTrailing,
                endPoint: .bottomLeading
            )
        }
    }
}

private struct ForsettiDataStreamGrid: View {
    var body: some View {
        Canvas { context, size in
            let majorSpacing: CGFloat = 64
            let minorSpacing: CGFloat = 16

            var minorPath = Path()
            stride(from: CGFloat.zero, through: size.width, by: minorSpacing).forEach { x in
                minorPath.move(to: CGPoint(x: x, y: 0))
                minorPath.addLine(to: CGPoint(x: x, y: size.height))
            }
            stride(from: CGFloat.zero, through: size.height, by: minorSpacing).forEach { y in
                minorPath.move(to: CGPoint(x: 0, y: y))
                minorPath.addLine(to: CGPoint(x: size.width, y: y))
            }
            context.stroke(minorPath, with: .color(ForsettiColors.accentCyan.opacity(0.025)), lineWidth: 0.5)

            var majorPath = Path()
            stride(from: CGFloat.zero, through: size.width, by: majorSpacing).forEach { x in
                majorPath.move(to: CGPoint(x: x, y: 0))
                majorPath.addLine(to: CGPoint(x: x, y: size.height))
            }
            stride(from: CGFloat.zero, through: size.height, by: majorSpacing).forEach { y in
                majorPath.move(to: CGPoint(x: 0, y: y))
                majorPath.addLine(to: CGPoint(x: size.width, y: y))
            }
            context.stroke(majorPath, with: .color(ForsettiColors.accentBlue.opacity(0.055)), lineWidth: 0.8)
        }
        .allowsHitTesting(false)
    }
}

//endofline
