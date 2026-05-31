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
struct ForsettiPrimaryButtonStyle: ButtonStyle {
    /// Tracks whether the button is currently enabled in the environment.
    @Environment(\.isEnabled) private var isEnabled

    /// Builds the button body by layering text, gradient/background, border stroke,
    /// shadow, and press animation on top of the label.
    func makeBody(configuration: Configuration) -> some View {
        let shape = RoundedRectangle(cornerRadius: ForsettiTheme.Radius.button, style: .continuous)
        configuration.label
            .font(.system(.headline, design: .rounded).weight(.semibold))
            .foregroundStyle(ForsettiTheme.buttonTextOnPrimary)
            .padding(.vertical, 11)
            .padding(.horizontal, 16)
            .background {
                if isEnabled {
                    shape.fill(ForsettiTheme.primaryButtonGradient)
                } else {
                    // Disabled state uses a neutral gray background
                    shape.fill(ForsettiPlatformColors.disabledPrimaryBackground)
                }
            }
            .overlay(
                shape
                    .stroke(ForsettiTheme.strongBorder.opacity(isEnabled ? 0.65 : 0.25), lineWidth: 1)
            )
            .shadow(
                color: isEnabled ? ForsettiTheme.shadowColor : .clear,
                radius: configuration.isPressed ? 2 : 7,   // Shrink shadow on press
                x: 0,
                y: configuration.isPressed ? 1 : 4
            )
            .scaleEffect(configuration.isPressed ? 0.985 : 1.0) // Subtle press-down feel
            .animation(.easeOut(duration: 0.14), value: configuration.isPressed)
    }
}

// MARK: - Secondary Button Style

/// A lighter, outlined button style used for secondary actions.
///
/// It uses a transparent or lightly tinted background with a blue-tinted border
/// stroke. The text color matches the primary blue when enabled, falling back to
/// the system secondary color when disabled.
struct ForsettiSecondaryButtonStyle: ButtonStyle {
    /// Tracks whether the button is currently enabled in the environment.
    @Environment(\.isEnabled) private var isEnabled

    /// Builds the button body with a surface-colored background, subtle border,
    /// and press animation matching the primary style's timing.
    func makeBody(configuration: Configuration) -> some View {
        let shape = RoundedRectangle(cornerRadius: ForsettiTheme.Radius.button, style: .continuous)
        configuration.label
            .font(.system(.headline, design: .rounded).weight(.semibold))
            .foregroundStyle(isEnabled ? ForsettiColors.bluePrimary : Color.secondary)
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
                color: isEnabled ? ForsettiTheme.shadowColor.opacity(0.65) : .clear,
                radius: configuration.isPressed ? 1 : 4,
                x: 0,
                y: configuration.isPressed ? 0 : 2
            )
            .scaleEffect(configuration.isPressed ? 0.985 : 1.0)
            .animation(.easeOut(duration: 0.14), value: configuration.isPressed)
    }

    /// The border color -- blue-tinted when enabled, system separator when disabled.
    private var borderColor: Color {
        isEnabled ? ForsettiColors.bluePrimary.opacity(0.35) : ForsettiPlatformColors.separator
    }

    /// Returns the background fill color based on enabled and pressed states.
    /// - Parameter isPressed: Whether the button is currently being pressed.
    /// - Returns: A `Color` appropriate for the current interaction state.
    private func backgroundColor(isPressed: Bool) -> Color {
        if isEnabled == false {
            return ForsettiPlatformColors.tertiaryFill
        }

        // Show a light blue tint when the user presses down
        return isPressed ? ForsettiColors.blueSecondary.opacity(0.22) : ForsettiTheme.surface
    }
}

// MARK: - Danger Button Style

/// A red-themed button style for destructive or dangerous actions (e.g., delete, sign out).
///
/// It mirrors the secondary button's structure but swaps blue tones for red,
/// signalling caution to the user.
struct ForsettiDangerButtonStyle: ButtonStyle {
    /// Tracks whether the button is currently enabled in the environment.
    @Environment(\.isEnabled) private var isEnabled

    /// Builds the button body with a red text/border treatment and matching
    /// press animation.
    func makeBody(configuration: Configuration) -> some View {
        let shape = RoundedRectangle(cornerRadius: ForsettiTheme.Radius.button, style: .continuous)
        configuration.label
            .font(.system(.headline, design: .rounded).weight(.semibold))
            .foregroundStyle(isEnabled ? Color.red : Color.secondary)
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
                color: isEnabled ? ForsettiTheme.shadowColor.opacity(0.60) : .clear,
                radius: configuration.isPressed ? 1 : 4,
                x: 0,
                y: configuration.isPressed ? 0 : 2
            )
            .scaleEffect(configuration.isPressed ? 0.985 : 1.0)
            .animation(.easeOut(duration: 0.14), value: configuration.isPressed)
    }

    /// The border color -- red-tinted when enabled, system separator when disabled.
    private var borderColor: Color {
        isEnabled ? Color.red.opacity(0.35) : ForsettiPlatformColors.separator
    }

    /// Returns the background fill color based on enabled and pressed states.
    /// - Parameter isPressed: Whether the button is currently being pressed.
    /// - Returns: A `Color` appropriate for the current interaction state.
    private func backgroundColor(isPressed: Bool) -> Color {
        if isEnabled == false {
            return ForsettiPlatformColors.tertiaryFill
        }

        // Show a light red tint when the user presses down
        return isPressed ? Color.red.opacity(0.16) : ForsettiTheme.surface
    }
}

// MARK: - Platform Colors

/// Centralized platform-dependent semantic colors used by button styles.
///
/// Each property resolves to the appropriate UIKit, AppKit, or fallback color
/// so that button styles don't need their own `#if canImport` branches.
private enum ForsettiPlatformColors {
    /// The background color used for disabled primary buttons.
    static var disabledPrimaryBackground: Color {
#if canImport(UIKit)
        Color(uiColor: .systemGray3)
#elseif canImport(AppKit)
        Color(nsColor: .systemGray)
#else
        Color.gray.opacity(0.35)
#endif
    }

    /// A thin line separator color matching the platform convention.
    static var separator: Color {
#if canImport(UIKit)
        Color(uiColor: .separator)
#elseif canImport(AppKit)
        Color(nsColor: .separatorColor)
#else
        Color.gray.opacity(0.3)
#endif
    }

    /// A very light fill color used for disabled button backgrounds.
    static var tertiaryFill: Color {
#if canImport(UIKit)
        Color(uiColor: .tertiarySystemFill)
#elseif canImport(AppKit)
        Color(nsColor: .controlBackgroundColor)
#else
        Color.gray.opacity(0.2)
#endif
    }

}

// MARK: - Convenience Extensions

/// Provides a `.forsettiPrimary` shorthand for applying the primary button style.
extension ButtonStyle where Self == ForsettiPrimaryButtonStyle {
    static var forsettiPrimary: ForsettiPrimaryButtonStyle { .init() }
}

/// Provides a `.forsettiSecondary` shorthand for applying the secondary button style.
extension ButtonStyle where Self == ForsettiSecondaryButtonStyle {
    static var forsettiSecondary: ForsettiSecondaryButtonStyle { .init() }
}

/// Provides a `.forsettiDanger` shorthand for applying the danger button style.
extension ButtonStyle where Self == ForsettiDangerButtonStyle {
    static var forsettiDanger: ForsettiDangerButtonStyle { .init() }
}

//endofline
