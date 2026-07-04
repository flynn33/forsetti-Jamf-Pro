import Foundation

final class JamfAPIServiceAdapter: APIService, @unchecked Sendable {
    let apiGateway: JamfAPIGateway

    init(apiGateway: JamfAPIGateway) {
        self.apiGateway = apiGateway
    }
}

final class JamfAuthenticationServiceAdapter: AuthenticationService, @unchecked Sendable {
    let authenticationService: JamfAuthenticationService

    init(authenticationService: JamfAuthenticationService) {
        self.authenticationService = authenticationService
    }
}

final class JamfDiagnosticsServiceAdapter: DiagnosticsService, @unchecked Sendable {
    let diagnosticsCenter: DiagnosticsCenter

    init(diagnosticsCenter: DiagnosticsCenter) {
        self.diagnosticsCenter = diagnosticsCenter
    }
}

final class JamfSecurityServiceAdapter: SecurityService, @unchecked Sendable {
    let credentialsStore: JamfCredentialsStore

    init(credentialsStore: JamfCredentialsStore) {
        self.credentialsStore = credentialsStore
    }
}

final class JamfTelemetryAdapter: TelemetryService, @unchecked Sendable {
    private let diagnosticsCenter: DiagnosticsCenter

    init(diagnosticsCenter: DiagnosticsCenter) {
        self.diagnosticsCenter = diagnosticsCenter
    }

    func track(event: String, properties: [String: String]) {
        Task {
            await diagnosticsCenter.report(
                source: "forsetti.telemetry",
                category: event,
                severity: .info,
                message: "Forsetti telemetry event recorded.",
                metadata: properties
            )
        }
    }
}
