import ForsettiCore
import Foundation

final class ScannerServiceModule: ForsettiModule {
    enum Constants {
        static let entryPoint = "ScannerServiceModule"
    }

    private let definition = JamfDashboardModuleIDs.scannerDefinition

    var descriptor: ModuleDescriptor { definition.descriptor }
    var manifest: ModuleManifest { definition.manifest }

    func start(context: any ForsettiModuleContext) throws {
        try JamfDashboardModuleLifecycle.start(
            definition: definition,
            context: context,
            requiredServices: [.storage, .diagnostics]
        )
    }

    func stop(context: any ForsettiModuleContext) {
        JamfDashboardModuleLifecycle.stop(definition: definition, context: context)
    }
}
