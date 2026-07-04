import Foundation

final class JamfServiceModule: ForsettiModule {
    enum Constants {
        static let entryPoint = "JamfServiceModule"
    }

    private let definition = JamfDashboardModuleIDs.jamfDefinition

    var descriptor: ModuleDescriptor { definition.descriptor }
    var manifest: ModuleManifest { definition.manifest }

    func start(context: any ForsettiModuleContext) throws {
        try JamfDashboardModuleLifecycle.start(
            definition: definition,
            context: context,
            requiredServices: [.networking, .secureStorage, .authentication, .api, .security, .diagnostics]
        )
    }

    func stop(context: any ForsettiModuleContext) {
        JamfDashboardModuleLifecycle.stop(definition: definition, context: context)
    }
}
