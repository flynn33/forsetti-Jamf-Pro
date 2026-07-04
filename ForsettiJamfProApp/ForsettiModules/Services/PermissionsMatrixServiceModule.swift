import Foundation

final class PermissionsMatrixServiceModule: ForsettiModule {
    enum Constants {
        static let entryPoint = "PermissionsMatrixServiceModule"
    }

    private let definition = JamfDashboardModuleIDs.permissionsMatrixDefinition

    var descriptor: ModuleDescriptor { definition.descriptor }
    var manifest: ModuleManifest { definition.manifest }

    func start(context: any ForsettiModuleContext) throws {
        try JamfDashboardModuleLifecycle.start(
            definition: definition,
            context: context,
            requiredServices: [.storage, .diagnostics, .fileExport]
        )
    }

    func stop(context: any ForsettiModuleContext) {
        JamfDashboardModuleLifecycle.stop(definition: definition, context: context)
    }
}
