import Foundation

@MainActor
enum JamfDashboardServiceComposition {
    static func makeForsettiServiceContainer(appServices: ForsettiJamfProAppServices) -> ForsettiServiceContainer {
        let container = ForsettiServiceContainer()

        container.register(
            NetworkingService.self,
            service: URLSessionNetworkingService(
                session: JamfURLSessionFactory.make(diagnosticsReporter: appServices.diagnosticsCenter)
            )
        )
        container.register(StorageService.self, service: UserDefaultsStorageService())
        container.register(
            SecureStorageService.self,
            service: KeychainSecureStorageService(service: "com.forsetti.jamfpro")
        )
        container.register(FileExportService.self, service: LocalFileExportService())
        container.register(
            TelemetryService.self,
            service: JamfTelemetryAdapter(diagnosticsCenter: appServices.diagnosticsCenter)
        )
        container.register(
            DiagnosticsService.self,
            service: JamfDiagnosticsServiceAdapter(diagnosticsCenter: appServices.diagnosticsCenter)
        )
        container.register(
            AuthenticationService.self,
            service: JamfAuthenticationServiceAdapter(authenticationService: appServices.authenticationService)
        )
        container.register(
            APIService.self,
            service: JamfAPIServiceAdapter(apiGateway: appServices.apiGateway)
        )
        container.register(
            SecurityService.self,
            service: JamfSecurityServiceAdapter(credentialsStore: appServices.credentialsStore)
        )

        return container
    }
}
