import SwiftUI

/// A centralized namespace for the design system's core color palette.
///
/// `ForsettiColors` provides static accessors to the primary and secondary brand colors
/// defined in the asset catalog via the `Color.Forsetti` extension. All UI components
/// should reference these tokens rather than hardcoding color literals to ensure
/// consistent theming across the app.
enum ForsettiColors {
    /// The primary blue used for key interactive elements, links, and accents.
    static let bluePrimary = Color.Forsetti.bluePrimary

    /// The primary green used for success states and complementary accents.
    static let greenPrimary = Color.Forsetti.greenPrimary

    /// A lighter or muted blue used for secondary UI elements, borders, and backgrounds.
    static let blueSecondary = Color.Forsetti.blueSecondary
}

//endofline
