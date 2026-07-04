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
    func dashboardRoundedTypography() -> some View {
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
    func dashboardAppBackground() -> some View {
        background {
            ZStack {
                DashboardTheme.appBackground()
                DashboardMetalBackgroundView()
                    .opacity(0.55)
            }
            .ignoresSafeArea()
        }
    }

    /// Applies a shared elevated card surface style with a rounded rectangle background,
    /// a thin border stroke, and a subtle drop shadow. Used for dashboard cards,
    /// status cards, and other elevated content containers.
    /// - Parameter fill: The card background color. Defaults to `DashboardTheme.surface`.
    /// - Returns: The view wrapped in the card surface treatment.
    func dashboardCardSurface(fill: Color = DashboardTheme.surface) -> some View {
        let shape = RoundedRectangle(cornerRadius: DashboardTheme.Radius.card, style: .continuous)
        return self
            .background(shape.fill(fill))
            .overlay(alignment: .top) {
                shape
                    .stroke(
                        LinearGradient(
                            colors: [
                                DashboardColors.accentCyan.opacity(0.36),
                                DashboardColors.separator.opacity(0.24)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 1
                    )
            }
            .shadow(color: DashboardColors.accentCyan.opacity(0.10), radius: 16, x: 0, y: 8)
            .shadow(color: Color.black.opacity(0.34), radius: 20, x: 0, y: 14)
    }

    /// Applies a bottom bar surface treatment with a top divider and upward shadow.
    /// Used for sticky action bars at the bottom of scrollable content.
    func dashboardBottomBarSurface() -> some View {
        self
            .background(DashboardColors.backgroundPanelGlass.opacity(DashboardTheme.Opacity.toolbarFill))
            .overlay(alignment: .top) {
                Divider()
                    .overlay(DashboardTheme.border)
            }
            .shadow(color: DashboardTheme.shadowColorStrong.opacity(0.55), radius: 9, x: 0, y: -2)
    }

    /// Sets the navigation bar title display mode to `.inline` on iOS.
    /// No-op on macOS where inline mode is not applicable.
    @ViewBuilder
    func dashboardInlineNavigationTitle() -> some View {
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
    func dashboardInsetGroupedListStyle() -> some View {
#if os(iOS)
        if #available(iOS 16.0, *) {
            listStyle(.insetGrouped)
                .scrollContentBackground(.hidden)
                .dashboardAppBackground()
        } else {
            listStyle(.insetGrouped)
        }
#else
        if #available(macOS 13.0, *) {
            listStyle(.inset)
                .scrollContentBackground(.hidden)
                .dashboardAppBackground()
        } else {
            listStyle(.inset)
        }
#endif
    }

    /// Applies the grouped **form** style for `Form`-based screens (credential
    /// entry, settings forms). This is the correct treatment for `Form` —
    /// `dashboardInsetGroupedListStyle()` applies a *list* style which on macOS
    /// (`.inset`) renders form sections as ungrouped inline text and pushes
    /// field labels into a clipped leading column. `.formStyle(.grouped)`
    /// gives proper grouped sections with headers and aligned label/field rows
    /// on both platforms. Keeps the app backdrop and hides the default
    /// scroll background to match the rest of the UI.
    @ViewBuilder
    func dashboardGroupedFormStyle() -> some View {
        if #available(iOS 16.0, macOS 13.0, *) {
            formStyle(.grouped)
                .scrollContentBackground(.hidden)
                .dashboardAppBackground()
        } else {
            self
        }
    }

    /// Reliable cross-platform sizing for a sheet's root content view.
    ///
    /// On macOS a sheet does NOT adopt the content's `minWidth` — AppKit sizes
    /// the sheet from the content's *ideal* size negotiated against the parent
    /// window, so `idealWidth` / `idealHeight` are load-bearing while min/max
    /// only bound interactive resize. (This is why `minWidth:` alone presented
    /// the sheet at ~710pt.) On macOS 15+ we additionally adopt
    /// `.presentationSizing(.form…)` so the sheet no longer depends on frame
    /// heuristics: `.form` gives a comfortably wide, landscape form width, and
    /// `fitVertically` trims dead vertical height to hug the content.
    ///
    /// No-op on iOS, where the system page sheet already presents sensibly and
    /// `.presentationSizing` requires iOS 18+ (the page sheet is preferred).
    /// `.presentationDetents` is intentionally not used — it does not exist on
    /// macOS and the iOS default is already correct.
    @ViewBuilder
    func dashboardSheetSizing(
        minWidth: CGFloat,
        idealWidth: CGFloat,
        maxWidth: CGFloat,
        minHeight: CGFloat,
        idealHeight: CGFloat,
        maxHeight: CGFloat,
        fitVertically: Bool = true
    ) -> some View {
#if os(macOS)
        let sized = frame(
            minWidth: minWidth, idealWidth: idealWidth, maxWidth: maxWidth,
            minHeight: minHeight, idealHeight: idealHeight, maxHeight: maxHeight
        )
        if #available(macOS 15.0, *) {
            if fitVertically {
                sized.presentationSizing(.form.fitted(horizontal: false, vertical: true))
            } else {
                sized.presentationSizing(.form)
            }
        } else {
            sized
        }
#else
        self
#endif
    }

    /// Disables auto-correction and automatic capitalization on iOS text inputs.
    /// No-op on macOS where these input behaviors are not applicable.
    @ViewBuilder
    func dashboardNoAutoCorrectionTextInput() -> some View {
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
    func dashboardURLKeyboard() -> some View {
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
    static var dashboardTopBarLeading: ToolbarItemPlacement {
#if os(iOS)
        .topBarLeading
#else
        .cancellationAction
#endif
    }

    /// Resolves to `.topBarTrailing` on iOS or `.primaryAction` on macOS,
    /// providing a consistent trailing toolbar position across platforms.
    static var dashboardTopBarTrailing: ToolbarItemPlacement {
#if os(iOS)
        .topBarTrailing
#else
        .primaryAction
#endif
    }
}

/// A cross-platform clipboard helper that abstracts `UIPasteboard` (iOS) and
/// `NSPasteboard` (macOS) behind a single static API.
enum DashboardClipboard {
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
