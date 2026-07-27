import Foundation

final class DeploymentTrackerServiceModule: ForsettiModule {
    enum Constants {
        static let entryPoint = "DeploymentTrackerServiceModule"
    }

    private let definition = JamfDashboardModuleIDs.deploymentTrackerDefinition

    var descriptor: ModuleDescriptor { definition.descriptor }
    var manifest: ModuleManifest { definition.manifest }

    func start(context: any ForsettiModuleContext) throws {
        try JamfDashboardModuleLifecycle.start(
            definition: definition,
            context: context,
            requiredServices: [.storage, .diagnostics, .fileExport, .telemetry]
        )
    }

    func stop(context: any ForsettiModuleContext) {
        JamfDashboardModuleLifecycle.stop(definition: definition, context: context)
    }
}
