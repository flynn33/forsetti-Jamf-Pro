import Foundation

final class PrestageDirectorServiceModule: ForsettiModule {
    enum Constants {
        static let entryPoint = "PrestageDirectorServiceModule"
    }

    private let definition = JamfDashboardModuleIDs.prestageDirectorDefinition

    var descriptor: ModuleDescriptor { definition.descriptor }
    var manifest: ModuleManifest { definition.manifest }

    func start(context: any ForsettiModuleContext) throws {
        try JamfDashboardModuleLifecycle.start(
            definition: definition,
            context: context,
            requiredServices: [.networking, .diagnostics, .api, .fileExport]
        )
    }

    func stop(context: any ForsettiModuleContext) {
        JamfDashboardModuleLifecycle.stop(definition: definition, context: context)
    }
}
