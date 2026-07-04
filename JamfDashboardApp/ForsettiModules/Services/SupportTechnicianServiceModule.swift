import ForsettiCore
import Foundation

final class SupportTechnicianServiceModule: ForsettiModule {
    enum Constants {
        static let entryPoint = "SupportTechnicianServiceModule"
    }

    private let definition = JamfDashboardModuleIDs.supportTechnicianDefinition

    var descriptor: ModuleDescriptor { definition.descriptor }
    var manifest: ModuleManifest { definition.manifest }

    func start(context: any ForsettiModuleContext) throws {
        try JamfDashboardModuleLifecycle.start(
            definition: definition,
            context: context,
            requiredServices: [.networking, .secureStorage, .diagnostics, .api, .security, .fileExport]
        )
    }

    func stop(context: any ForsettiModuleContext) {
        JamfDashboardModuleLifecycle.stop(definition: definition, context: context)
    }
}
