import SwiftUI
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

/// The central design-system theme providing layout constants, semantic colors,
/// gradients, and background builders for the entire Forsetti Jamf Pro app.
///
/// All visual tokens -- corner radii, spacing values, surface colors, borders,
/// shadows, and gradients -- live here so that every screen draws from one
/// source of truth. Platform-specific adaptations (iOS vs macOS) are handled
/// internally via conditional compilation.
enum DashboardTheme {

    // MARK: - Layout Tokens

    enum Radius {
        static let small: CGFloat = 8
        static let medium: CGFloat = 12
        static let card: CGFloat = 18
        static let panel: CGFloat = 22
        static let large: CGFloat = 28
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
        static let screenPaddingRegular: CGFloat = 28
        static let screenPaddingCompact: CGFloat = 16
        static let cardPaddingDense: CGFloat = 12
        static let cardPaddingStandard: CGFloat = 18
        static let cardPaddingRoomy: CGFloat = 24

        static let section = xl
        static let item = md
        static let compact = sm
    }

    enum Opacity {
        static let glassFill = 0.78
        static let railFill = 0.92
        static let toolbarFill = 0.86
        static let border = 0.28
        static let borderStrong = 0.72
        static let hoverFill = 0.16
        static let selectedFill = 0.24
        static let disabled = 0.42
    }

    enum Layout {
        static let navigationRailWidth: CGFloat = 240
        static let navigationRailCollapsedWidth: CGFloat = 72
        static let rightInspectorWidth: CGFloat = 340
        static let commandStreamHeight: CGFloat = 52
        static let dataTableRowHeight: CGFloat = 48
        static let metricCardHeight: CGFloat = 166
        static let moduleCardHeight: CGFloat = 160
        static let supportTileHeight: CGFloat = 112
        static let minimumDesktopContentWidth: CGFloat = 1080
        static let compactBreakpoint: CGFloat = 960
        static let inspectorBreakpoint: CGFloat = 1480
    }

    enum Typography {
        static let largeTitle = Font.system(size: 34, weight: .bold)
        static let screenTitle = Font.system(size: 30, weight: .bold)
        static let sectionTitle = Font.system(size: 18, weight: .semibold)
        static let cardTitle = Font.system(size: 15, weight: .semibold)
        static let tableBody = Font.system(size: 13, weight: .regular)
        static let caption = Font.system(size: 11, weight: .semibold)

        static func numeric(size: CGFloat = 28) -> Font {
            .system(size: size, weight: .semibold, design: .monospaced)
        }
    }

    // MARK: - Semantic Colors

    static let accent = DashboardColors.bluePrimary

    static var surface: Color {
        DashboardColors.backgroundPanelGlass.opacity(Opacity.glassFill)
    }

    static var groupedSurface: Color {
        DashboardColors.backgroundElevated
    }

    static let border = DashboardColors.separator.opacity(Opacity.border)
    static let strongBorder = DashboardColors.accentCyan.opacity(Opacity.borderStrong)
    static let shadowColor = DashboardColors.accentCyan.opacity(0.12)
    static let shadowColorStrong = DashboardColors.backgroundVignette.opacity(0.52)
    static let buttonTextOnPrimary = DashboardColors.textInverse
    static let successText = DashboardColors.success

    // MARK: - Gradients

    static var primaryButtonGradient: LinearGradient {
        LinearGradient(
            colors: [
                DashboardColors.accentCyanSoft,
                DashboardColors.accentCyan,
                DashboardColors.accentBlue
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    static var appBackdropGradient: LinearGradient {
        LinearGradient(
            colors: [
                DashboardColors.backgroundRoot,
                DashboardColors.backgroundPanel,
                DashboardColors.backgroundVignette
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    // MARK: - Background Builder

    /// Constructs the standard app background by layering the backdrop gradient
    /// on top of the grouped surface color inside a `ZStack`.
    ///
    /// - Returns: A composited `View` suitable for use as a full-screen background.
    @ViewBuilder
    static func appBackground() -> some View {
        ZStack {
            DashboardColors.backgroundRoot
            appBackdropGradient
            RadialGradient(
                colors: [
                    DashboardColors.accentCyan.opacity(0.18),
                    DashboardColors.accentViolet.opacity(0.08),
                    .clear
                ],
                center: .topTrailing,
                startRadius: 24,
                endRadius: 760
            )
        }
    }
}

//endofline
