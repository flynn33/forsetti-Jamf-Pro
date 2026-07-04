import SwiftUI
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

// MARK: - Primary Button Style

/// A bold, gradient-filled button style used for the app's main call-to-action buttons.
///
/// When enabled the button displays a diagonal blue gradient background with a
/// prominent shadow. When disabled it falls back to a flat gray fill. A subtle
/// scale-down animation plays on press to give tactile feedback.
struct DashboardPrimaryButtonStyle: ButtonStyle {
    /// Tracks whether the button is currently enabled in the environment.
    @Environment(\.isEnabled) private var isEnabled

    /// Builds the button body by layering text, gradient/background, border stroke,
    /// shadow, and press animation on top of the label.
    func makeBody(configuration: Configuration) -> some View {
        let shape = RoundedRectangle(cornerRadius: DashboardTheme.Radius.button, style: .continuous)
        configuration.label
            .font(.system(.headline, design: .rounded).weight(.semibold))
            .foregroundStyle(DashboardTheme.buttonTextOnPrimary)
            .padding(.vertical, 11)
            .padding(.horizontal, 16)
            .background {
                if isEnabled {
                    shape.fill(DashboardTheme.primaryButtonGradient)
                } else {
                    shape.fill(DashboardPlatformColors.disabledPrimaryBackground)
                }
            }
            .overlay(
                shape
                    .stroke(DashboardTheme.strongBorder.opacity(isEnabled ? 0.65 : 0.25), lineWidth: 1)
            )
            .shadow(
                color: isEnabled ? DashboardColors.accentCyan.opacity(0.26) : .clear,
                radius: configuration.isPressed ? 2 : 9,
                x: 0,
                y: configuration.isPressed ? 1 : 5
            )
            .scaleEffect(configuration.isPressed ? 0.985 : 1.0)
            .animation(.easeOut(duration: 0.14), value: configuration.isPressed)
    }
}

// MARK: - Secondary Button Style

/// A lighter, outlined button style used for secondary actions.
///
/// It uses a transparent or lightly tinted background with a blue-tinted border
/// stroke. The text color matches the primary blue when enabled, falling back to
/// the system secondary color when disabled.
struct DashboardSecondaryButtonStyle: ButtonStyle {
    /// Tracks whether the button is currently enabled in the environment.
    @Environment(\.isEnabled) private var isEnabled

    /// Builds the button body with a surface-colored background, subtle border,
    /// and press animation matching the primary style's timing.
    func makeBody(configuration: Configuration) -> some View {
        let shape = RoundedRectangle(cornerRadius: DashboardTheme.Radius.button, style: .continuous)
        configuration.label
            .font(.system(.headline, design: .rounded).weight(.semibold))
            .foregroundStyle(isEnabled ? DashboardColors.accentCyan : DashboardColors.textTertiary)
            .padding(.vertical, 11)
            .padding(.horizontal, 16)
            .background(
                shape
                    .fill(backgroundColor(isPressed: configuration.isPressed))
            )
            .overlay(
                shape
                    .stroke(borderColor, lineWidth: 1)
            )
            .shadow(
                color: isEnabled ? DashboardTheme.shadowColor.opacity(0.65) : .clear,
                radius: configuration.isPressed ? 1 : 4,
                x: 0,
                y: configuration.isPressed ? 0 : 2
            )
            .scaleEffect(configuration.isPressed ? 0.985 : 1.0)
            .animation(.easeOut(duration: 0.14), value: configuration.isPressed)
    }

    /// The border color -- blue-tinted when enabled, system separator when disabled.
    private var borderColor: Color {
        isEnabled ? DashboardColors.accentCyan.opacity(0.42) : DashboardPlatformColors.separator
    }

    /// Returns the background fill color based on enabled and pressed states.
    /// - Parameter isPressed: Whether the button is currently being pressed.
    /// - Returns: A `Color` appropriate for the current interaction state.
    private func backgroundColor(isPressed: Bool) -> Color {
        if isEnabled == false {
            return DashboardPlatformColors.tertiaryFill
        }

        return isPressed ? DashboardColors.accentCyan.opacity(0.16) : DashboardColors.backgroundPanelGlass.opacity(DashboardTheme.Opacity.toolbarFill)
    }
}

// MARK: - Danger Button Style

/// A red-themed button style for destructive or dangerous actions (e.g., delete, sign out).
///
/// It mirrors the secondary button's structure but swaps blue tones for red,
/// signalling caution to the user.
struct DashboardDangerButtonStyle: ButtonStyle {
    /// Tracks whether the button is currently enabled in the environment.
    @Environment(\.isEnabled) private var isEnabled

    /// Builds the button body with a red text/border treatment and matching
    /// press animation.
    func makeBody(configuration: Configuration) -> some View {
        let shape = RoundedRectangle(cornerRadius: DashboardTheme.Radius.button, style: .continuous)
        configuration.label
            .font(.system(.headline, design: .rounded).weight(.semibold))
            .foregroundStyle(isEnabled ? DashboardColors.danger : DashboardColors.textTertiary)
            .padding(.vertical, 11)
            .padding(.horizontal, 16)
            .background(
                shape
                    .fill(backgroundColor(isPressed: configuration.isPressed))
            )
            .overlay(
                shape
                    .stroke(borderColor, lineWidth: 1)
            )
            .shadow(
                color: isEnabled ? DashboardTheme.shadowColor.opacity(0.60) : .clear,
                radius: configuration.isPressed ? 1 : 4,
                x: 0,
                y: configuration.isPressed ? 0 : 2
            )
            .scaleEffect(configuration.isPressed ? 0.985 : 1.0)
            .animation(.easeOut(duration: 0.14), value: configuration.isPressed)
    }

    /// The border color -- red-tinted when enabled, system separator when disabled.
    private var borderColor: Color {
        isEnabled ? DashboardColors.danger.opacity(0.45) : DashboardPlatformColors.separator
    }

    /// Returns the background fill color based on enabled and pressed states.
    /// - Parameter isPressed: Whether the button is currently being pressed.
    /// - Returns: A `Color` appropriate for the current interaction state.
    private func backgroundColor(isPressed: Bool) -> Color {
        if isEnabled == false {
            return DashboardPlatformColors.tertiaryFill
        }

        return isPressed ? DashboardColors.danger.opacity(0.16) : DashboardColors.backgroundPanelGlass.opacity(DashboardTheme.Opacity.toolbarFill)
    }
}

// MARK: - Platform Colors

/// Centralized platform-dependent semantic colors used by button styles.
///
/// Each property resolves to the appropriate UIKit, AppKit, or fallback color
/// so that button styles don't need their own `#if canImport` branches.
private enum DashboardPlatformColors {
    /// The background color used for disabled primary buttons.
    static var disabledPrimaryBackground: Color {
#if canImport(UIKit)
        Color(uiColor: .systemGray3)
#elseif canImport(AppKit)
        Color(nsColor: .systemGray)
#else
        DashboardColors.textDisabled.opacity(0.35)
#endif
    }

    /// A thin line separator color matching the platform convention.
    static var separator: Color {
#if canImport(UIKit)
        Color(uiColor: .separator)
#elseif canImport(AppKit)
        Color(nsColor: .separatorColor)
#else
        DashboardColors.separator.opacity(0.45)
#endif
    }

    /// A very light fill color used for disabled button backgrounds.
    static var tertiaryFill: Color {
#if canImport(UIKit)
        Color(uiColor: .tertiarySystemFill)
#elseif canImport(AppKit)
        Color(nsColor: .controlBackgroundColor)
#else
        DashboardColors.backgroundDepth.opacity(0.55)
#endif
    }

}

// MARK: - Convenience Extensions

/// Provides a `.dashboardPrimary` shorthand for applying the primary button style.
extension ButtonStyle where Self == DashboardPrimaryButtonStyle {
    static var dashboardPrimary: DashboardPrimaryButtonStyle { .init() }
}

/// Provides a `.dashboardSecondary` shorthand for applying the secondary button style.
extension ButtonStyle where Self == DashboardSecondaryButtonStyle {
    static var dashboardSecondary: DashboardSecondaryButtonStyle { .init() }
}

/// Provides a `.dashboardDanger` shorthand for applying the danger button style.
extension ButtonStyle where Self == DashboardDangerButtonStyle {
    static var dashboardDanger: DashboardDangerButtonStyle { .init() }
}

//endofline
