import ForsettiCore
import Foundation

final class ComputerSearchServiceModule: ForsettiModule {
    enum Constants {
        static let entryPoint = "ComputerSearchServiceModule"
    }

    private let definition = JamfDashboardModuleIDs.computerSearchDefinition

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
