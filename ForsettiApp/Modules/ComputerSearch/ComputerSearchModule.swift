import SwiftUI


/// A module that provides computer inventory search functionality within the Forsetti.
///
/// `ComputerSearchModule` conforms to `JamfModule` and acts as the entry point for the
/// Computer Search feature. It supplies metadata (title, subtitle, icon) used by the
/// module registry to display this module in the dashboard, and vends the root SwiftUI
/// view that powers the search experience.
final class ComputerSearchModule: JamfModule {
    /// A reverse-DNS style identifier that uniquely distinguishes this module from others in the registry.
    let id: String

    /// The human-readable name displayed in the module list (e.g. "Computer Search").
    let title: String

    /// A short description shown beneath the title to explain what this module does.
    let subtitle: String

    /// The SF Symbols icon name rendered alongside the module title in the dashboard.
    let iconSystemName: String

    /// Creates a new `ComputerSearchModule` with sensible defaults for all metadata fields.
    ///
    /// - Parameters:
    ///   - id: A unique identifier for module registration. Defaults to `"forsetti.feature.computer-search"`.
    ///   - title: The display title. Defaults to `"Computer Search"`.
    ///   - subtitle: A brief feature summary. Defaults to a description of the search and profile capability.
    ///   - iconSystemName: The SF Symbols icon name. Defaults to `"desktopcomputer"`.
    init(
        id: String = "forsetti.feature.computer-search",
        title: String = "Computer Search",
        subtitle: String = "Search computer inventory and create reusable field-based profiles.",
        iconSystemName: String = "desktopcomputer"
    ) {
        self.id = id
        self.title = title
        self.subtitle = subtitle
        self.iconSystemName = iconSystemName
    }

    /// Builds and returns the root SwiftUI view for this module.
    ///
    /// This method wires up the `ComputerSearchViewModel` with the shared API gateway,
    /// diagnostics reporter, and a fresh profile store, then wraps the resulting
    /// `ComputerSearchView` in `AnyView` for type-erased return.
    ///
    /// - Parameter context: The `ModuleContext` that provides shared dependencies like the API gateway and diagnostics reporter.
    /// - Returns: A type-erased `AnyView` containing the fully-configured computer search interface.
    func makeRootView(context: ModuleContext) -> AnyView {
        // Stand up the view model with all required dependencies from the module context
        let viewModel = ComputerSearchViewModel(
            apiGateway: context.apiGateway,
            diagnosticsReporter: context.diagnosticsReporter,
            profileStore: ComputerSearchProfileStore()
        )

        return AnyView(ComputerSearchView(viewModel: viewModel))
    }
}

//endofline
