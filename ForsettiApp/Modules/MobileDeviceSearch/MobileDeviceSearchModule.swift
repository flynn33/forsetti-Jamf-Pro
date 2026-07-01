import SwiftUI

// "Klatu-barada-Nikto"

/// A module that provides mobile device search functionality within the Forsetti.
///
/// `MobileDeviceSearchModule` conforms to `JamfModule` and serves as the entry point
/// for the Mobile Device Search feature. It defines the module's identity (unique ID,
/// display title, subtitle, and SF Symbol icon) and is responsible for constructing
/// the root SwiftUI view hierarchy along with its backing view model and dependencies.
final class MobileDeviceSearchModule: JamfModule {
    /// The unique reverse-DNS identifier for this module, used for registration and routing.
    let id: String

    /// The human-readable title shown in module lists and navigation headers.
    let title: String

    /// A short description displayed beneath the title to summarize what this module does.
    let subtitle: String

    /// The SF Symbols icon name rendered alongside the module title in the UI.
    let iconSystemName: String

    /// Creates a new `MobileDeviceSearchModule` with the given identity properties.
    ///
    /// All parameters have sensible defaults so the module can be instantiated with no arguments
    /// for standard use, or customized for testing and alternate configurations.
    ///
    /// - Parameters:
    ///   - id: Reverse-DNS identifier for the module. Defaults to `"com.forsetti.jamfpro.feature.mobile-device-search"`.
    ///   - title: Display title. Defaults to `"Mobile Device Search"`.
    ///   - subtitle: Brief description. Defaults to a summary of the search and profile features.
    ///   - iconSystemName: SF Symbol name for the module icon. Defaults to `"iphone.gen3"`.
    init(
        id: String = "com.forsetti.jamfpro.feature.mobile-device-search",
        title: String = "Mobile Device Search",
        subtitle: String = "Search inventory and create reusable field-based profiles.",
        iconSystemName: String = "iphone.gen3"
    ) {
        self.id = id
        self.title = title
        self.subtitle = subtitle
        self.iconSystemName = iconSystemName
    }

    /// Builds and returns the root SwiftUI view for this module.
    ///
    /// This method wires together the module's dependencies by creating a
    /// `MobileDeviceSearchViewModel` from the shared `ModuleContext` (API gateway,
    /// diagnostics reporter) and a fresh `MobileDeviceSearchProfileStore`, then
    /// wraps the resulting `MobileDeviceSearchView` in `AnyView` for type erasure.
    ///
    /// - Parameter context: The shared context providing API access and diagnostics.
    /// - Returns: A type-erased SwiftUI view ready to be presented by the module host.
    func makeRootView(context: ModuleContext) -> AnyView {
        let viewModel = MobileDeviceSearchViewModel(
            apiGateway: context.apiGateway,
            diagnosticsReporter: context.diagnosticsReporter,
            profileStore: MobileDeviceSearchProfileStore(),
            smartFilterStore: SmartFilterStore()
        )

        return AnyView(MobileDeviceSearchView(viewModel: viewModel))
    }
}

//endofline
