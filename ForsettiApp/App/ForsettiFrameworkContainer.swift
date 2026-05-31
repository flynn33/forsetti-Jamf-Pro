import Foundation
import Combine

/// The central service container that bootstraps and owns all framework-level dependencies.
///
/// `ForsettiFrameworkContainer` acts as the composition root for the application. It creates
/// and wires together the diagnostics center, credentials store, API gateway, module registry,
/// and module package manager. As an `ObservableObject` bound to `@MainActor`, it publishes
/// state changes that drive the SwiftUI view hierarchy.
///
/// On initialization, the container immediately kicks off an asynchronous `bootstrap()` call
/// on the package manager to load installed module packages and register their modules.
@MainActor
final class ForsettiFrameworkContainer: ObservableObject {

    /// Centralized diagnostics service for structured event logging and export.
    let diagnosticsCenter: DiagnosticsCenter

    /// Secure credential persistence backed by the system Keychain.
    let credentialsStore: JamfCredentialsStore

    /// The shared HTTP gateway for all Jamf Pro API requests. Handles token injection,
    /// automatic 401 retry, and error reporting to diagnostics.
    let apiGateway: JamfAPIGateway

    /// Registry of available modules displayed on the dashboard grid.
    let moduleRegistry: ModuleRegistry

    /// Manages the lifecycle of module packages — install, remove, bootstrap, and persistence.
    let modulePackageManager: ModulePackageManager

    /// Designated initializer that accepts pre-built services for dependency injection.
    ///
    /// Wires the API gateway from the credentials store, authentication service, and
    /// diagnostics reporter. Creates the module registry and package manager, then
    /// triggers an async bootstrap to load installed packages from disk.
    ///
    /// - Parameters:
    ///   - credentialsStore: The Keychain-backed credential manager.
    ///   - authenticationService: The token management actor for Jamf Pro auth flows.
    ///   - diagnosticsCenter: The structured event reporting actor.
    ///   - modulePackageStore: The file-backed package persistence actor.
    init(
        credentialsStore: JamfCredentialsStore,
        authenticationService: JamfAuthenticationService,
        diagnosticsCenter: DiagnosticsCenter,
        modulePackageStore: ModulePackageStore
    ) {
        self.diagnosticsCenter = diagnosticsCenter
        self.credentialsStore = credentialsStore

        // Build the API gateway with its required dependencies: credentials
        // for server URL, auth service for Bearer tokens, diagnostics for
        // failure reporting, and a Jamf-tuned URLSession (explicit timeouts,
        // matched connection budget, metrics delegate, TLS floor). Running
        // on the shared session left request/resource timeouts unbounded
        // and tail latency invisible — see JamfURLSessionFactory for the
        // full rationale.
        self.apiGateway = JamfAPIGateway(
            credentialsStore: credentialsStore,
            authenticationService: authenticationService,
            diagnosticsReporter: diagnosticsCenter,
            session: JamfURLSessionFactory.make(diagnosticsReporter: diagnosticsCenter)
        )

        self.moduleRegistry = ModuleRegistry()

        // The package manager coordinates between the module registry (what's displayed),
        // the diagnostics reporter (event logging), and the package store (disk persistence).
        self.modulePackageManager = ModulePackageManager(
            moduleRegistry: moduleRegistry,
            diagnosticsReporter: diagnosticsCenter,
            packageStore: modulePackageStore
        )

        // Kick off async bootstrap — loads installed packages from disk, ensures bundled
        // defaults are present, and registers discovered modules into the registry.
        Task { [modulePackageManager] in
            await modulePackageManager.bootstrap()
        }
    }

    /// Convenience initializer that creates all services with default configurations.
    ///
    /// This is the initializer used by `ForsettiApp` at launch. It constructs
    /// the full dependency graph from scratch: diagnostics → credentials → auth → gateway.
    convenience init() {
        let diagnosticsCenter = DiagnosticsCenter()
        let credentialsStore = JamfCredentialsStore()
        let authenticationService = JamfAuthenticationService(diagnosticsReporter: diagnosticsCenter)
        let modulePackageStore = ModulePackageStore()

        self.init(
            credentialsStore: credentialsStore,
            authenticationService: authenticationService,
            diagnosticsCenter: diagnosticsCenter,
            modulePackageStore: modulePackageStore
        )
    }

    /// Builds a `ModuleContext` snapshot for dependency injection into individual modules.
    ///
    /// Each module receives this context when its root view is created, giving it access
    /// to the API gateway, credentials store, and diagnostics reporter without coupling
    /// to the container itself.
    var moduleContext: ModuleContext {
        ModuleContext(
            apiGateway: apiGateway,
            credentialsStore: credentialsStore,
            diagnosticsReporter: diagnosticsCenter
        )
    }

    /// Refreshes dashboard-observed state through the container boundary.
    func refreshDashboardState() {
        credentialsStore.refreshState()
    }
}

//endofline
