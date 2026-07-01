import SwiftUI

/// Composition root for the Permissions Matrix module.
///
/// The user-facing title is "Permissions Helper"; the stable module ID/type
/// remain `com.forsetti.jamfpro.feature.permissions-matrix` / `permissions-matrix`.
///
/// The module consumes shared framework services through `ModuleContext` — it
/// never creates its own Jamf API client, auth/token service, credential store,
/// or diagnostics stack. Everything is namespaced and UI-free below the views so
/// a future framework release can relocate the same loader/verifier/view models
/// into framework-owned UI with minimal rework.
final class PermissionsMatrixModule: JamfModule {
    let id: String
    let title: String
    let subtitle: String
    let iconSystemName: String

    init(
        id: String = "com.forsetti.jamfpro.feature.permissions-matrix",
        title: String = "Permissions Helper",
        subtitle: String = "Look up Jamf Pro privileges required for Forsetti actions and API endpoints.",
        iconSystemName: String = "checklist.checked"
    ) {
        self.id = id
        self.title = title
        self.subtitle = subtitle
        self.iconSystemName = iconSystemName
    }

    func makeRootView(context: ModuleContext) -> AnyView {
        let loader = PermissionsMatrixResourceLoader(
            bundle: .main,
            diagnosticsReporter: context.diagnosticsReporter
        )
        let verifier = PermissionsMatrixRuntimeVerifier(
            apiGateway: context.apiGateway,
            diagnosticsReporter: context.diagnosticsReporter
        )
        let viewModel = PermissionsMatrixViewModel(
            resourceLoader: loader,
            runtimeVerifier: verifier,
            credentialsStore: context.credentialsStore,
            diagnosticsReporter: context.diagnosticsReporter
        )
        return AnyView(PermissionsMatrixView(viewModel: viewModel))
    }
}

//endofline
