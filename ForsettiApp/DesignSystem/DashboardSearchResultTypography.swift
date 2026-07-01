import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

/// Centralized typography tokens for module search results.
///
/// Every search-result view should use these factory methods instead of
/// constructing fonts directly. The fonts are based on the platform's
/// preferred text styles, scaled up by a global `multiplier`, and always
/// use the `.rounded` design for visual consistency.
enum DashboardSearchResultTypography {

    /// Global scale factor applied to every base point size.
    /// Increasing this value uniformly enlarges all search-result text.
    static let multiplier: CGFloat = 1.22

    // MARK: - Public Font Factories

    /// Returns a scaled headline font, commonly used for result titles.
    /// - Parameter weight: The font weight (defaults to `.semibold`).
    static func headline(weight: Font.Weight = .semibold) -> Font {
        scaledFont(token: .headline, weight: weight)
    }

    /// Returns a scaled subheadline font, used for secondary result labels.
    /// - Parameter weight: The font weight (defaults to `.regular`).
    static func subheadline(weight: Font.Weight = .regular) -> Font {
        scaledFont(token: .subheadline, weight: weight)
    }

    /// Returns a scaled caption font for tertiary or metadata text.
    /// - Parameter weight: The font weight (defaults to `.regular`).
    static func caption(weight: Font.Weight = .regular) -> Font {
        scaledFont(token: .caption, weight: weight)
    }

    /// Returns a scaled caption2 font -- the smallest standard text size.
    /// - Parameter weight: The font weight (defaults to `.regular`).
    static func caption2(weight: Font.Weight = .regular) -> Font {
        scaledFont(token: .caption2, weight: weight)
    }

    /// Returns a scaled title3 font for prominent section headers.
    /// - Parameter weight: The font weight (defaults to `.regular`).
    static func title3(weight: Font.Weight = .regular) -> Font {
        scaledFont(token: .title3, weight: weight)
    }

    // MARK: - Private Helpers

    // "End of Line"

    /// Internal enum mapping each public factory to a platform text-style token.
    private enum Token {
        case headline
        case subheadline
        case caption
        case caption2
        case title3
    }

    /// Builds a system font by multiplying the platform base size by the global `multiplier`.
    /// - Parameters:
    ///   - token: The semantic text-style token to resolve.
    ///   - weight: The desired font weight.
    /// - Returns: A `.rounded` system font at the scaled size.
    private static func scaledFont(token: Token, weight: Font.Weight) -> Font {
        let baseSize = basePointSize(for: token)
        // Multiply the platform's preferred size by the global scale factor
        return .system(size: baseSize * multiplier, weight: weight, design: .rounded)
    }

    /// Resolves the platform's preferred point size for a given token.
    ///
    /// On iOS this queries `UIFont.preferredFont(forTextStyle:)` so the result
    /// respects the user's Dynamic Type setting. On other platforms a set of
    /// sensible fallback constants is returned.
    private static func basePointSize(for token: Token) -> CGFloat {
#if canImport(UIKit)
        switch token {
        case .headline:
            UIFont.preferredFont(forTextStyle: .headline).pointSize
        case .subheadline:
            UIFont.preferredFont(forTextStyle: .subheadline).pointSize
        case .caption:
            UIFont.preferredFont(forTextStyle: .caption1).pointSize
        case .caption2:
            UIFont.preferredFont(forTextStyle: .caption2).pointSize
        case .title3:
            UIFont.preferredFont(forTextStyle: .title3).pointSize
        }
#else
        // Hardcoded fallback sizes for non-UIKit platforms (macOS, Linux, etc.)
        switch token {
        case .headline:
            17
        case .subheadline:
            15
        case .caption:
            12
        case .caption2:
            11
        case .title3:
            20
        }
#endif
    }
}

//endofline
