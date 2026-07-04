import Foundation

enum JamfDashboardModuleStartError: LocalizedError {
    case missingServices(moduleID: String, serviceNames: [String])

    var errorDescription: String? {
        switch self {
        case let .missingServices(moduleID, serviceNames):
            return "Module \(moduleID) could not start because required Forsetti services are missing: \(serviceNames.joined(separator: ", "))."
        }
    }
}

enum JamfDashboardRequiredService {
    case networking
    case storage
    case secureStorage
    case fileExport
    case telemetry
    case authentication
    case diagnostics
    case api
    case security

    var displayName: String {
        switch self {
        case .networking:
            return "NetworkingService"
        case .storage:
            return "StorageService"
        case .secureStorage:
            return "SecureStorageService"
        case .fileExport:
            return "FileExportService"
        case .telemetry:
            return "TelemetryService"
        case .authentication:
            return "AuthenticationService"
        case .diagnostics:
            return "DiagnosticsService"
        case .api:
            return "APIService"
        case .security:
            return "SecurityService"
        }
    }

    func isAvailable(in services: any ForsettiServiceProviding) -> Bool {
        switch self {
        case .networking:
            return services.resolve(NetworkingService.self) != nil
        case .storage:
            return services.resolve(StorageService.self) != nil
        case .secureStorage:
            return services.resolve(SecureStorageService.self) != nil
        case .fileExport:
            return services.resolve(FileExportService.self) != nil
        case .telemetry:
            return services.resolve(TelemetryService.self) != nil
        case .authentication:
            return services.resolve(AuthenticationService.self) != nil
        case .diagnostics:
            return services.resolve(DiagnosticsService.self) != nil
        case .api:
            return services.resolve(APIService.self) != nil
        case .security:
            return services.resolve(SecurityService.self) != nil
        }
    }
}

enum JamfDashboardModuleLifecycle {
    static func start(
        definition: JamfDashboardModuleDefinition,
        context: any ForsettiModuleContext,
        requiredServices: [JamfDashboardRequiredService]
    ) throws {
        let missingServices = requiredServices
            .filter { !$0.isAvailable(in: context.services) }
            .map(\.displayName)

        guard missingServices.isEmpty else {
            throw JamfDashboardModuleStartError.missingServices(
                moduleID: definition.moduleID,
                serviceNames: missingServices
            )
        }

        context.logger.info(
            "Started Forsetti Jamf Pro module.",
            metadata: ["entry_point": definition.entryPoint]
        )
        context.publishEvent(
            type: "com.forsetti.jamfpro.module.started",
            payload: ["module_id": definition.moduleID]
        )
    }

    static func stop(definition: JamfDashboardModuleDefinition, context: any ForsettiModuleContext) {
        context.logger.info(
            "Stopped Forsetti Jamf Pro module.",
            metadata: ["entry_point": definition.entryPoint]
        )
    }
}
