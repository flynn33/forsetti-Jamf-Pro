import Foundation

enum JamfDashboardModuleRegistry {
    static func registerAll(into registry: ModuleRegistry) throws {
        try registry.register(entryPoint: JamfDashboardUIModule.Constants.entryPoint) {
            JamfDashboardUIModule()
        }
        try registry.register(entryPoint: JamfServiceModule.Constants.entryPoint) {
            JamfServiceModule()
        }
        try registry.register(entryPoint: DiagnosticsServiceModule.Constants.entryPoint) {
            DiagnosticsServiceModule()
        }
        try registry.register(entryPoint: ScannerServiceModule.Constants.entryPoint) {
            ScannerServiceModule()
        }
        try registry.register(entryPoint: ComputerSearchServiceModule.Constants.entryPoint) {
            ComputerSearchServiceModule()
        }
        try registry.register(entryPoint: MobileDeviceSearchServiceModule.Constants.entryPoint) {
            MobileDeviceSearchServiceModule()
        }
        try registry.register(entryPoint: SupportTechnicianServiceModule.Constants.entryPoint) {
            SupportTechnicianServiceModule()
        }
        try registry.register(entryPoint: PrestageDirectorServiceModule.Constants.entryPoint) {
            PrestageDirectorServiceModule()
        }
        try registry.register(entryPoint: ReportsServiceModule.Constants.entryPoint) {
            ReportsServiceModule()
        }
        try registry.register(entryPoint: PermissionsMatrixServiceModule.Constants.entryPoint) {
            PermissionsMatrixServiceModule()
        }
    }
}
