import SwiftUI


/// A context object passed to every module when its root view is created.
///
/// `ModuleContext` bundles the shared services that modules need to communicate
/// with the Jamf Pro server and report diagnostics, keeping module code
/// decoupled from the specific service implementations.
struct ModuleContext {
    /// The API gateway used to make authenticated requests to the Jamf Pro server.
    let apiGateway: JamfAPIGateway
    /// The credentials store from which the module can read (but not write) credentials.
    let credentialsStore: JamfCredentialsStore
    /// A reporter for logging diagnostic events and performance metrics.
    let diagnosticsReporter: any DiagnosticsReporting
}

/// The contract every dashboard module must satisfy to be registered and displayed.
///
/// Conforming types provide metadata (title, subtitle, icon) for the module
/// list and a factory method that produces the module's root SwiftUI view.
protocol JamfModule {
    /// A unique, stable identifier for the module (e.g., "computers", "policies").
    var id: String { get }
    /// The display title shown in the dashboard module list.
    var title: String { get }
    /// A short description shown beneath the title.
    var subtitle: String { get }
    /// The SF Symbol name used as the module's icon.
    var iconSystemName: String { get }

    /// Creates the module's root SwiftUI view, injecting shared services via the context.
    ///
    /// - Parameter context: The `ModuleContext` containing API gateway, credentials, and diagnostics.
    /// - Returns: A type-erased `AnyView` representing the module's UI.
    func makeRootView(context: ModuleContext) -> AnyView
}

//endofline
