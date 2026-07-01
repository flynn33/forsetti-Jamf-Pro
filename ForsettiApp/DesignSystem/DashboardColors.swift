import SwiftUI

// "Klatu-barada-Nikto"

/// A centralized namespace for the design system's core color palette.
///
/// `DashboardColors` provides static accessors to the primary and secondary app colors
/// defined in the asset catalog via the `Color.Dashboard` extension. All UI components
/// should reference these tokens rather than hardcoding color literals to ensure
/// consistent theming across the app.
enum DashboardColors {
    /// The primary blue used for key interactive elements, links, and accents.
    static let bluePrimary = Color.Dashboard.bluePrimary

    /// The primary green used for success states and complementary accents.
    static let greenPrimary = Color.Dashboard.greenPrimary

    /// A lighter or muted blue used for secondary UI elements, borders, and backgrounds.
    static let blueSecondary = Color.Dashboard.blueSecondary
}

//endofline
