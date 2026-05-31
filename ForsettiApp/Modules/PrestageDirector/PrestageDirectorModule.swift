import SwiftUI

/// The Prestage Director module provides a workflow for viewing mobile device prestage enrollment
/// profiles and managing the devices assigned to each profile. Users can move devices between
/// prestages or remove them from the current prestage entirely.
///
/// This class conforms to `JamfModule`, making it discoverable and launchable from the
/// module registry on the dashboard home screen.
final class PrestageDirectorModule: JamfModule {
    /// Reverse-DNS identifier used to uniquely reference this module across the app.
    let id: String

    /// Human-readable name displayed on the dashboard card and navigation bar.
    let title: String

    /// Short description shown beneath the title to explain the module's purpose.
    let subtitle: String

    /// SF Symbol name rendered as the module icon on the dashboard.
    let iconSystemName: String

    /// Creates a new Prestage Director module instance with default or custom metadata.
    ///
    /// - Parameters:
    ///   - id: Reverse-DNS module identifier. Defaults to `forsetti.feature.prestage-director`.
    ///   - title: Display name. Defaults to `"Prestage Director"`.
    ///   - subtitle: Brief description. Defaults to a sentence explaining prestage management.
    ///   - iconSystemName: SF Symbol for the module icon. Defaults to `"arrow.left.arrow.right.square"`.
    init(
        id: String = "forsetti.feature.prestage-director",
        title: String = "Prestage Director",
        subtitle: String = "View prestages and move or remove assigned devices.",
        iconSystemName: String = "arrow.left.arrow.right.square"
    ) {
        self.id = id
        self.title = title
        self.subtitle = subtitle
        self.iconSystemName = iconSystemName
    }

    /// Builds and returns the root SwiftUI view for this module.
    ///
    /// The method wires up the `PrestageDirectorViewModel` with the shared API gateway and
    /// diagnostics reporter from the provided `ModuleContext`, then wraps the resulting
    /// `PrestageDirectorView` in `AnyView` for type-erased module presentation.
    ///
    /// - Parameter context: Shared module context providing API access and diagnostics.
    /// - Returns: A type-erased SwiftUI view ready for navigation presentation.
    func makeRootView(context: ModuleContext) -> AnyView {
        let viewModel = PrestageDirectorViewModel(
            apiGateway: context.apiGateway,
            diagnosticsReporter: context.diagnosticsReporter
        )

        return AnyView(PrestageDirectorView(viewModel: viewModel))
    }
}

//endofline
