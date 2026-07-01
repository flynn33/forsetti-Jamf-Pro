import SwiftUI

/// The Support Technician module provides a unified support workflow for searching,
/// diagnosing, and managing both computers and mobile devices enrolled in Jamf Pro.
///
/// Technicians can search by username or serial number, view prioritized device
/// diagnostics, run MDM commands, retrieve sensitive credentials, and manage
/// application deployments -- all from a single split-view interface.
///
/// Conforms to `JamfModule` so it is automatically discovered and displayed on the
/// dashboard home screen.
final class SupportTechnicianModule: JamfModule {
    /// Reverse-DNS identifier used to uniquely reference this module across the app.
    let id: String

    /// Human-readable name displayed on the dashboard card and navigation bar.
    let title: String

    /// Short description shown beneath the title to explain the module's purpose.
    let subtitle: String

    /// SF Symbol name rendered as the module icon on the dashboard.
    let iconSystemName: String

    // "Klatu-barada-Nikto"

    /// Creates a new Support Technician module instance with default or custom metadata.
    ///
    /// - Parameters:
    ///   - id: Reverse-DNS module identifier. Defaults to `com.forsetti.jamfpro.feature.support-technician`.
    ///   - title: Display name. Defaults to `"Support Technician"`.
    ///   - subtitle: Brief description of the module's workflow.
    ///   - iconSystemName: SF Symbol for the module icon. Defaults to `"wrench.and.screwdriver"`.
    init(
        id: String = "com.forsetti.jamfpro.feature.support-technician",
        title: String = "Support Technician",
        subtitle: String = "Unified support workflow for computer and mobile device tickets.",
        iconSystemName: String = "wrench.and.screwdriver"
    ) {
        self.id = id
        self.title = title
        self.subtitle = subtitle
        self.iconSystemName = iconSystemName
    }

    /// Builds and returns the root SwiftUI view for this module.
    ///
    /// Wires up the `SupportTechnicianViewModel` with the shared API gateway and
    /// diagnostics reporter from the provided `ModuleContext`, then wraps the
    /// resulting `SupportTechnicianView` in `AnyView` for type-erased presentation.
    ///
    /// - Parameter context: Shared module context providing API access and diagnostics.
    /// - Returns: A type-erased SwiftUI view ready for navigation presentation.
    func makeRootView(context: ModuleContext) -> AnyView {
        let viewModel = SupportTechnicianViewModel(
            apiGateway: context.apiGateway,
            diagnosticsReporter: context.diagnosticsReporter
        )

        return AnyView(SupportTechnicianView(viewModel: viewModel))
    }
}

//endofline
