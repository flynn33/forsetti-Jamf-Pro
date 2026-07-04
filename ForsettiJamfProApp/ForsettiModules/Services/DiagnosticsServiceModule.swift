import Foundation

final class DiagnosticsServiceModule: ForsettiModule {
    enum Constants {
        static let entryPoint = "DiagnosticsServiceModule"
    }

    private let definition = JamfDashboardModuleIDs.diagnosticsDefinition

    var descriptor: ModuleDescriptor { definition.descriptor }
    var manifest: ModuleManifest { definition.manifest }

    func start(context: any ForsettiModuleContext) throws {
        try JamfDashboardModuleLifecycle.start(
            definition: definition,
            context: context,
            requiredServices: [.diagnostics, .telemetry, .fileExport, .storage]
        )
    }

    func stop(context: any ForsettiModuleContext) {
        JamfDashboardModuleLifecycle.stop(definition: definition, context: context)
    }
}
