import Combine
import Foundation

@MainActor
final class ForsettiJamfProAppServices: ObservableObject {
    let diagnosticsCenter: DiagnosticsCenter
    let credentialsStore: JamfCredentialsStore
    let authenticationService: JamfAuthenticationService
    let apiGateway: JamfAPIGateway

    convenience init() {
        self.init(
            diagnosticsCenter: DiagnosticsCenter(),
            credentialsStore: JamfCredentialsStore()
        )
    }

    init(
        diagnosticsCenter: DiagnosticsCenter,
        credentialsStore: JamfCredentialsStore,
        authenticationService: JamfAuthenticationService? = nil
    ) {
        self.diagnosticsCenter = diagnosticsCenter
        self.credentialsStore = credentialsStore

        let resolvedAuthenticationService = authenticationService
            ?? JamfAuthenticationService(diagnosticsReporter: diagnosticsCenter)
        self.authenticationService = resolvedAuthenticationService
        self.apiGateway = JamfAPIGateway(
            credentialsStore: credentialsStore,
            authenticationService: resolvedAuthenticationService,
            diagnosticsReporter: diagnosticsCenter,
            session: JamfURLSessionFactory.make(diagnosticsReporter: diagnosticsCenter)
        )
    }

    var viewContext: JamfDashboardViewContext {
        JamfDashboardViewContext(
            apiGateway: apiGateway,
            credentialsStore: credentialsStore,
            diagnosticsReporter: diagnosticsCenter
        )
    }
}

struct JamfDashboardViewContext {
    let apiGateway: JamfAPIGateway
    let credentialsStore: JamfCredentialsStore
    let diagnosticsReporter: any DiagnosticsReporting
}
