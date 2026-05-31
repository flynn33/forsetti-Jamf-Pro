import SwiftUI
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

/// The central design-system theme providing layout constants, semantic colors,
/// gradients, and background builders for the entire Forsetti app.
///
/// All visual tokens -- corner radii, spacing values, surface colors, borders,
/// shadows, and gradients -- live here so that every screen draws from one
/// source of truth. Platform-specific adaptations (iOS vs macOS) are handled
/// internally via conditional compilation.
enum ForsettiTheme {

    // MARK: - Layout Tokens

    /// Corner-radius tokens used throughout the design system.
    enum Radius {
        /// The standard corner radius applied to card containers.
        static let card: CGFloat = 18

        /// The larger panel radius used for primary glass surfaces.
        static let panel: CGFloat = 22

        /// The corner radius applied to buttons and small interactive elements.
        static let button: CGFloat = 12

        /// A large value used for capsule-shaped controls.
        static let capsule: CGFloat = 999
    }

    /// Spacing tokens that define consistent vertical and horizontal rhythm.
    enum Spacing {
        /// The standard spacing between major page sections.
        static let section: CGFloat = 20

        /// The spacing between individual items within a section.
        static let item: CGFloat = 12

        /// A tighter spacing value used in compact or dense layouts.
        static let compact: CGFloat = 8
    }

    /// Stable sizing tokens for the retail workspace shell.
    enum Layout {
        /// Width for the persistent navigation rail on wide macOS layouts.
        static let navigationRailWidth: CGFloat = 240

        /// Compact rail width selected by the responsive workspace shell.
        static let navigationRailCollapsedWidth: CGFloat = 72

        /// Width for the contextual inspector on wide macOS layouts.
        static let rightInspectorWidth: CGFloat = 340

        /// Preferred height for the top command activity surface.
        static let commandActivityBarHeight: CGFloat = 54
    }

    // MARK: - Semantic Colors

    /// The app-wide accent color, derived from the primary blue in `ForsettiColors`.
    static let accent = ForsettiColors.bluePrimary

    /// The primary surface/background color, adapting to the platform's
    /// system background (light or dark mode).
    static var surface: Color {
#if canImport(UIKit)
        Color(uiColor: .systemBackground)
#elseif canImport(AppKit)
        Color(nsColor: .textBackgroundColor)
#else
        Color.white
#endif
    }

    /// A secondary grouped surface used for table/section backgrounds,
    /// providing visual separation from the primary surface.
    static var groupedSurface: Color {
#if canImport(UIKit)
        Color(uiColor: .secondarySystemGroupedBackground)
#elseif canImport(AppKit)
        Color(nsColor: .controlBackgroundColor)
#else
        Color.gray.opacity(0.16)
#endif
    }

    /// A subtle border color at 30% opacity for standard container outlines.
    static let border = ForsettiColors.blueSecondary.opacity(0.30)

    /// A more prominent border color at 48% opacity for emphasized outlines.
    static let strongBorder = ForsettiColors.blueSecondary.opacity(0.48)

    /// A light drop-shadow color (10% black) for standard elevation.
    static let shadowColor = Color.black.opacity(0.10)

    /// A stronger drop-shadow color (16% black) for elevated or prominent elements.
    static let shadowColorStrong = Color.black.opacity(0.16)

    /// The text color used on top of primary-colored button backgrounds.
    static let buttonTextOnPrimary = Color.white

    // MARK: - Gradients

    /// A diagonal linear gradient blending primary and secondary blues,
    /// used as the fill for primary action buttons.
    static var primaryButtonGradient: LinearGradient {
        LinearGradient(
            colors: [
                ForsettiColors.bluePrimary.opacity(0.95),
                ForsettiColors.bluePrimary,
                ForsettiColors.blueSecondary.opacity(0.90)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    /// A soft diagonal gradient combining blue, green, and the grouped surface
    /// color, applied behind the main app content for a polished backdrop effect.
    static var appBackdropGradient: LinearGradient {
        LinearGradient(
            colors: [
                ForsettiColors.blueSecondary.opacity(0.18),
                ForsettiColors.greenPrimary.opacity(0.08),
                groupedSurface
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
            groupedSurface
            appBackdropGradient
        }
    }
}

//endofline
