import SwiftUI
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

/// Shared SwiftUI compatibility helpers for iOS and macOS.
/// These extension methods provide a unified API surface so views can call
/// platform-adaptive modifiers without scattering `#if os(...)` checks everywhere.
extension View {
    /// Applies a rounded font design treatment where the platform and OS version support it.
    /// Falls back to the unmodified view on older OS versions or unsupported platforms.
    @ViewBuilder
    func forsettiRoundedTypography() -> some View {
#if os(iOS)
        if #available(iOS 16.0, *) {
            fontDesign(.rounded)
        } else {
            self
        }
#elseif os(macOS)
        if #available(macOS 13.0, *) {
            fontDesign(.rounded)
        } else {
            self
        }
#else
        self
#endif
    }

    /// Applies the app-wide backdrop background (theme color + gradient) behind the view,
    /// extending into the safe area.
    @ViewBuilder
    func forsettiAppBackground() -> some View {
        background {
            ForsettiTheme.appBackground()
                .ignoresSafeArea()
        }
    }

    /// Applies a shared elevated card surface style with a rounded rectangle background,
    /// a thin border stroke, and a subtle drop shadow. Used for dashboard cards,
    /// status cards, and other elevated content containers.
    /// - Parameter fill: The card background color. Defaults to `ForsettiTheme.surface`.
    /// - Returns: The view wrapped in the card surface treatment.
    func forsettiCardSurface(fill: Color = ForsettiTheme.surface) -> some View {
        let shape = RoundedRectangle(cornerRadius: ForsettiTheme.Radius.card, style: .continuous)
        return self
            .background(shape.fill(fill))
            .overlay(shape.stroke(ForsettiTheme.border, lineWidth: 1))
            .shadow(color: ForsettiTheme.shadowColor, radius: 10, x: 0, y: 5)
    }

    /// Applies a bottom bar surface treatment with a top divider and upward shadow.
    /// Used for sticky action bars at the bottom of scrollable content.
    func forsettiBottomBarSurface() -> some View {
        self
            .background(ForsettiTheme.groupedSurface)
            .overlay(alignment: .top) {
                Divider()
                    .overlay(ForsettiTheme.border)
            }
            .shadow(color: ForsettiTheme.shadowColorStrong.opacity(0.55), radius: 9, x: 0, y: -2)
    }

    /// Sets the navigation bar title display mode to `.inline` on iOS.
    /// No-op on macOS where inline mode is not applicable.
    @ViewBuilder
    func forsettiInlineNavigationTitle() -> some View {
#if os(iOS)
        navigationBarTitleDisplayMode(.inline)
#else
        self
#endif
    }

    /// Applies the appropriate grouped/inset list style for the current platform.
    /// On iOS 16+ and macOS 13+, also hides the default scroll content background
    /// and applies the app backdrop. Falls back to basic list styles on older versions.
    @ViewBuilder
    func forsettiInsetGroupedListStyle() -> some View {
#if os(iOS)
        if #available(iOS 16.0, *) {
            listStyle(.insetGrouped)
                .scrollContentBackground(.hidden)
                .forsettiAppBackground()
        } else {
            listStyle(.insetGrouped)
        }
#else
        if #available(macOS 13.0, *) {
            listStyle(.inset)
                .scrollContentBackground(.hidden)
                .forsettiAppBackground()
        } else {
            listStyle(.inset)
        }
#endif
    }

    /// Disables auto-correction and automatic capitalization on iOS text inputs.
    /// No-op on macOS where these input behaviors are not applicable.
    @ViewBuilder
    func forsettiNoAutoCorrectionTextInput() -> some View {
#if os(iOS)
        textInputAutocapitalization(.never)
            .autocorrectionDisabled()
#else
        self
#endif
    }

    /// Sets the keyboard type to `.URL` on iOS for URL text fields.
    /// No-op on macOS where keyboard type is not applicable.
    @ViewBuilder
    func forsettiURLKeyboard() -> some View {
#if os(iOS)
        keyboardType(.URL)
#else
        self
#endif
    }
}

/// Platform-adaptive toolbar item placement helpers.
extension ToolbarItemPlacement {
    /// Resolves to `.topBarLeading` on iOS or `.cancellationAction` on macOS,
    /// providing a consistent leading toolbar position across platforms.
    ///
    /// On macOS `.cancellationAction` renders a dismiss-style button in the
    /// sheet's toolbar, which matches our intended "Done/Cancel" usage. The
    /// earlier `.navigation` placement could be hidden under a collapsed
    /// toolbar on sheets without a navigation column.
    static var forsettiTopBarLeading: ToolbarItemPlacement {
#if os(iOS)
        .topBarLeading
#else
        .cancellationAction
#endif
    }

    /// Resolves to `.topBarTrailing` on iOS or `.primaryAction` on macOS,
    /// providing a consistent trailing toolbar position across platforms.
    static var forsettiTopBarTrailing: ToolbarItemPlacement {
#if os(iOS)
        .topBarTrailing
#else
        .primaryAction
#endif
    }
}

/// A cross-platform clipboard helper that abstracts `UIPasteboard` (iOS) and
/// `NSPasteboard` (macOS) behind a single static API.
enum ForsettiClipboard {
    /// Copies the given string to the system pasteboard.
    /// Uses `UIPasteboard` on iOS/iPadOS and `NSPasteboard` on macOS.
    /// - Parameter value: The string to place on the clipboard.
    static func copy(_ value: String) {
#if canImport(UIKit)
        UIPasteboard.general.string = value
#elseif canImport(AppKit)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(value, forType: .string)
#endif
    }
}

//endofline
