import Foundation

final class ReportsServiceModule: ForsettiModule {
    enum Constants {
        static let entryPoint = "ReportsServiceModule"
    }

    private let definition = JamfDashboardModuleIDs.reportsDefinition

    var descriptor: ModuleDescriptor { definition.descriptor }
    var manifest: ModuleManifest { definition.manifest }

    func start(context: any ForsettiModuleContext) throws {
        try JamfDashboardModuleLifecycle.start(
            definition: definition,
            context: context,
            requiredServices: [.networking, .storage, .diagnostics, .api, .fileExport]
        )
    }

    func stop(context: any ForsettiModuleContext) {
        JamfDashboardModuleLifecycle.stop(definition: definition, context: context)
    }
}
