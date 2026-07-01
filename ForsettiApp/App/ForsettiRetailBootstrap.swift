import Foundation
import Combine
import ForsettiCore
import ForsettiPlatform

nonisolated struct ForsettiRetailManifestSpec: Sendable {
    let moduleID: String
    let displayName: String
    let moduleType: ModuleType
    let capabilitiesRequested: [Capability]
    let entryPoint: String

    nonisolated var manifest: ModuleManifest {
        ModuleManifest(
            schemaVersion: ModuleManifest.currentSchemaVersion,
            manifestTemplateVersion: .v1_1,
            moduleID: moduleID,
            displayName: displayName,
            moduleVersion: moduleType == .ui || moduleID.hasPrefix("com.forsetti.jamfpro.feature.")
                ? SemVer(major: 3, minor: 32, patch: 1)
                : SemVer(major: 1, minor: 0, patch: 0),
            moduleType: moduleType,
            supportedPlatforms: [.iOS, .macOS],
            minForsettiVersion: SemVer(major: 0, minor: 1, patch: 4),
            maxForsettiVersion: nil,
            capabilitiesRequested: capabilitiesRequested,
            iapProductID: nil,
            entryPoint: entryPoint
        )
    }
}

@MainActor
final class ForsettiApplicationServices {
    let dashboardContainer: ForsettiFrameworkContainer

    private init(dashboardContainer: ForsettiFrameworkContainer) {
        self.dashboardContainer = dashboardContainer
    }

    static func makeDefault() -> ForsettiApplicationServices {
        ForsettiApplicationServices(dashboardContainer: ForsettiFrameworkContainer())
    }

    var diagnostics: DiagnosticsCenter {
        dashboardContainer.diagnosticsCenter
    }
}

struct ForsettiModuleCatalog {
    static let uiModuleID = "com.forsetti.jamfpro.retail.ui"

    static let productionServiceModuleIDs = [
        "com.forsetti.jamfpro.service.jamf",
        "com.forsetti.jamfpro.service.diagnostics",
        "com.forsetti.jamfpro.service.scanner",
        "com.forsetti.jamfpro.feature.computer-search",
        "com.forsetti.jamfpro.feature.mobile-device-search",
        "com.forsetti.jamfpro.feature.support-technician",
        "com.forsetti.jamfpro.feature.prestage-director",
        "com.forsetti.jamfpro.feature.reports",
        "com.forsetti.jamfpro.feature.deployment-tracker",
        "com.forsetti.jamfpro.feature.permissions-matrix"
    ]

    nonisolated static let manifestSpecs: [ForsettiRetailManifestSpec] = [
        .init(
            moduleID: "com.forsetti.jamfpro.retail.ui",
            displayName: "Forsetti Retail UI",
            moduleType: .ui,
            capabilitiesRequested: [.routingOverlay, .uiThemeMask, .toolbarItems, .viewInjection, .fileExport, .telemetry],
            entryPoint: "ForsettiRetailUIModule"
        ),
        .init(
            moduleID: "com.forsetti.jamfpro.service.jamf",
            displayName: "Jamf Service",
            moduleType: .service,
            capabilitiesRequested: [.networking, .secureStorage, .authentication, .api, .security, .diagnostics],
            entryPoint: "ForsettiJamfServiceModule"
        ),
        .init(
            moduleID: "com.forsetti.jamfpro.service.diagnostics",
            displayName: "Diagnostics Service",
            moduleType: .service,
            capabilitiesRequested: [.diagnostics, .telemetry, .fileExport, .storage],
            entryPoint: "ForsettiDiagnosticsServiceModule"
        ),
        .init(
            moduleID: "com.forsetti.jamfpro.service.scanner",
            displayName: "Scanner Service",
            moduleType: .service,
            capabilitiesRequested: [.storage, .diagnostics],
            entryPoint: "ForsettiScannerServiceModule"
        ),
        .init(
            moduleID: "com.forsetti.jamfpro.feature.computer-search",
            displayName: "Computer Search",
            moduleType: .service,
            capabilitiesRequested: [.networking, .storage, .diagnostics, .api, .fileExport],
            entryPoint: "ForsettiComputerSearchModule"
        ),
        .init(
            moduleID: "com.forsetti.jamfpro.feature.mobile-device-search",
            displayName: "Mobile Device Search",
            moduleType: .service,
            capabilitiesRequested: [.networking, .storage, .diagnostics, .api, .fileExport],
            entryPoint: "ForsettiMobileDeviceSearchModule"
        ),
        .init(
            moduleID: "com.forsetti.jamfpro.feature.support-technician",
            displayName: "Support Technician",
            moduleType: .service,
            capabilitiesRequested: [.networking, .secureStorage, .diagnostics, .api, .security, .fileExport],
            entryPoint: "ForsettiSupportTechnicianModule"
        ),
        .init(
            moduleID: "com.forsetti.jamfpro.feature.prestage-director",
            displayName: "PreStage Director",
            moduleType: .service,
            capabilitiesRequested: [.networking, .diagnostics, .api, .fileExport],
            entryPoint: "ForsettiPrestageDirectorModule"
        ),
        .init(
            moduleID: "com.forsetti.jamfpro.feature.reports",
            displayName: "Reports",
            moduleType: .service,
            capabilitiesRequested: [.networking, .storage, .diagnostics, .api, .fileExport],
            entryPoint: "ForsettiReportsModule"
        ),
        .init(
            moduleID: "com.forsetti.jamfpro.feature.deployment-tracker",
            displayName: "Deployment Tracker Demo",
            moduleType: .service,
            capabilitiesRequested: [.storage, .diagnostics, .fileExport, .telemetry],
            entryPoint: "ForsettiDeploymentTrackerModule"
        ),
        .init(
            moduleID: "com.forsetti.jamfpro.feature.permissions-matrix",
            displayName: "Permissions Helper",
            moduleType: .service,
            capabilitiesRequested: [.storage, .diagnostics, .fileExport],
            entryPoint: "ForsettiPermissionsMatrixModule"
        )
    ]

    let manifestsByID: [String: ModuleManifest]
    let manifestsByEntryPoint: [String: ModuleManifest]

    init(bundle: Bundle, manifestsSubdirectory: String = "ForsettiManifests") throws {
        let manifestsByID = try ManifestLoader().loadManifests(
            bundle: bundle,
            subdirectory: manifestsSubdirectory
        )
        self.init(manifestsByID: manifestsByID)
    }

    init(manifestsByID: [String: ModuleManifest]) {
        self.manifestsByID = manifestsByID
        self.manifestsByEntryPoint = Dictionary(
            uniqueKeysWithValues: manifestsByID.values.map { ($0.entryPoint, $0) }
        )
    }

    func manifest(entryPoint: String) throws -> ModuleManifest {
        guard let manifest = manifestsByEntryPoint[entryPoint] else {
            throw ModuleCatalogError.missingEntryPoint(entryPoint)
        }
        return manifest
    }

    enum ModuleCatalogError: Error, LocalizedError {
        case missingEntryPoint(String)

        var errorDescription: String? {
            switch self {
            case let .missingEntryPoint(entryPoint):
                return "Missing manifest for module entry point '\(entryPoint)'."
            }
        }
    }
}

@MainActor
final class ForsettiRuntimeBootstrap: ObservableObject {
    enum BootState {
        case notStarted
        case booting
        case ready
        case failed(any Error)
    }

    @Published private(set) var bootState: BootState = .notStarted

    let appServices: ForsettiApplicationServices
    let runtime: ForsettiRuntime

    private let bundle: Bundle
    private let startupError: (any Error)?
    private var didBoot = false
    private var bootTask: Task<Void, Never>?

    nonisolated static let manifestSpecs = ForsettiModuleCatalog.manifestSpecs

    convenience init(bundle: Bundle = .main) {
        self.init(bundle: bundle, appServices: .makeDefault())
    }

    init(bundle: Bundle, appServices: ForsettiApplicationServices) {
        self.bundle = bundle
        self.appServices = appServices

        let serviceContainer = ForsettiServiceContainer()
        Self.registerFrameworkServices(into: serviceContainer)

        let registry = ForsettiCore.ModuleRegistry()
        var capturedStartupError: (any Error)?

        do {
            let catalog = try ForsettiModuleCatalog(bundle: bundle)
            try Self.registerModules(in: registry, catalog: catalog)
        } catch {
            capturedStartupError = error
        }

        self.startupError = capturedStartupError
        self.runtime = ForsettiRuntime(
            services: serviceContainer,
            activationStore: UserDefaultsActivationStore(key: "forsetti.retail.activation.state"),
            moduleRegistry: registry
        )
    }

    static func makeController() -> ForsettiRuntimeBootstrap {
        ForsettiRuntimeBootstrap()
    }

    var isBooted: Bool {
        if case .ready = bootState {
            return true
        }
        return false
    }

    var errorMessage: String? {
        if case let .failed(error) = bootState {
            return (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
        return nil
    }

    func bootIfNeeded() async {
        await bootForProduction()
    }

    func bootForProduction() async {
        guard !didBoot else {
            return
        }

        if let bootTask {
            await bootTask.value
            return
        }

        let task = Task { @MainActor [weak self] in
            guard let self else {
                return
            }
            await self.performBoot()
        }
        bootTask = task
        await task.value
        bootTask = nil
    }

    private func performBoot() async {
        guard !didBoot else {
            return
        }

        if let startupError {
            bootState = .failed(startupError)
            await reportBootFailure(startupError)
            return
        }

        bootState = .booting

        do {
            _ = try await runtime.boot(
                bundle: bundle,
                manifestsSubdirectory: "ForsettiManifests",
                restoreActivationState: false
            )

            for moduleID in ForsettiModuleCatalog.productionServiceModuleIDs {
                try await runtime.moduleManager.activateModule(moduleID: moduleID)
            }

            try await runtime.moduleManager.activateModule(moduleID: ForsettiModuleCatalog.uiModuleID)
            try runtime.moduleManager.setSelectedUIModule(moduleID: ForsettiModuleCatalog.uiModuleID)

            didBoot = true
            bootState = .ready
        } catch {
            bootState = .failed(error)
            await reportBootFailure(error)
        }
    }

    private func reportBootFailure(_ error: any Error) async {
        await appServices.diagnostics.reportError(
            source: "forsetti.runtime",
            category: "bootstrap",
            message: "Runtime boot failed.",
            errorDescription: (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        )
    }

    private static func registerFrameworkServices(into serviceContainer: ForsettiServiceContainer) {
        let platformServices = DefaultForsettiPlatformServices()
        register(NetworkingService.self, from: platformServices.container, into: serviceContainer)
        register(StorageService.self, from: platformServices.container, into: serviceContainer)
        register(SecureStorageService.self, from: platformServices.container, into: serviceContainer)
        register(FileExportService.self, from: platformServices.container, into: serviceContainer)
        register(TelemetryService.self, from: platformServices.container, into: serviceContainer)

        serviceContainer.register(AuthenticationService.self, service: ForsettiAuthenticationMarkerService())
        serviceContainer.register(DiagnosticsService.self, service: ForsettiDiagnosticsMarkerService())
        serviceContainer.register(APIService.self, service: ForsettiAPIMarkerService())
        serviceContainer.register(SecurityService.self, service: ForsettiSecurityMarkerService())
    }

    private static func register<T>(
        _ type: T.Type,
        from source: ForsettiServiceContainer,
        into destination: ForsettiServiceContainer
    ) {
        if let service = source.resolve(type) {
            destination.register(type, service: service)
        }
    }

    private static func registerModules(
        in registry: ForsettiCore.ModuleRegistry,
        catalog: ForsettiModuleCatalog
    ) throws {
        let retailUIManifest = try catalog.manifest(entryPoint: "ForsettiRetailUIModule")
        let jamfServiceManifest = try catalog.manifest(entryPoint: "ForsettiJamfServiceModule")
        let diagnosticsManifest = try catalog.manifest(entryPoint: "ForsettiDiagnosticsServiceModule")
        let scannerManifest = try catalog.manifest(entryPoint: "ForsettiScannerServiceModule")
        let computerSearchManifest = try catalog.manifest(entryPoint: "ForsettiComputerSearchModule")
        let mobileDeviceSearchManifest = try catalog.manifest(entryPoint: "ForsettiMobileDeviceSearchModule")
        let supportTechnicianManifest = try catalog.manifest(entryPoint: "ForsettiSupportTechnicianModule")
        let prestageDirectorManifest = try catalog.manifest(entryPoint: "ForsettiPrestageDirectorModule")
        let reportsManifest = try catalog.manifest(entryPoint: "ForsettiReportsModule")
        let deploymentTrackerManifest = try catalog.manifest(entryPoint: "ForsettiDeploymentTrackerModule")
        let permissionsMatrixManifest = try catalog.manifest(entryPoint: "ForsettiPermissionsMatrixModule")

        try registry.register(entryPoint: "ForsettiRetailUIModule") {
            ForsettiRetailUIModule(manifest: retailUIManifest)
        }
        try registry.register(entryPoint: "ForsettiJamfServiceModule") {
            ForsettiJamfServiceModule(manifest: jamfServiceManifest)
        }
        try registry.register(entryPoint: "ForsettiDiagnosticsServiceModule") {
            ForsettiDiagnosticsServiceModule(manifest: diagnosticsManifest)
        }
        try registry.register(entryPoint: "ForsettiScannerServiceModule") {
            ForsettiScannerServiceModule(manifest: scannerManifest)
        }
        try registry.register(entryPoint: "ForsettiComputerSearchModule") {
            ForsettiComputerSearchModule(manifest: computerSearchManifest)
        }
        try registry.register(entryPoint: "ForsettiMobileDeviceSearchModule") {
            ForsettiMobileDeviceSearchModule(manifest: mobileDeviceSearchManifest)
        }
        try registry.register(entryPoint: "ForsettiSupportTechnicianModule") {
            ForsettiSupportTechnicianModule(manifest: supportTechnicianManifest)
        }
        try registry.register(entryPoint: "ForsettiPrestageDirectorModule") {
            ForsettiPrestageDirectorModule(manifest: prestageDirectorManifest)
        }
        try registry.register(entryPoint: "ForsettiReportsModule") {
            ForsettiReportsModule(manifest: reportsManifest)
        }
        try registry.register(entryPoint: "ForsettiDeploymentTrackerModule") {
            ForsettiDeploymentTrackerModule(manifest: deploymentTrackerManifest)
        }
        try registry.register(entryPoint: "ForsettiPermissionsMatrixModule") {
            ForsettiPermissionsMatrixModule(manifest: permissionsMatrixManifest)
        }
    }
}

typealias ForsettiRetailBootstrap = ForsettiRuntimeBootstrap

nonisolated private final class ForsettiAuthenticationMarkerService: AuthenticationService {}
nonisolated private final class ForsettiDiagnosticsMarkerService: DiagnosticsService {}
nonisolated private final class ForsettiAPIMarkerService: APIService {}
nonisolated private final class ForsettiSecurityMarkerService: SecurityService {}

nonisolated class ForsettiLifecycleModule: ForsettiModule {
    let manifest: ModuleManifest
    private var started = false

    var descriptor: ModuleDescriptor {
        ModuleDescriptor(
            moduleID: manifest.moduleID,
            displayName: manifest.displayName,
            moduleVersion: manifest.moduleVersion,
            moduleType: manifest.moduleType
        )
    }

    init(manifest: ModuleManifest) {
        self.manifest = manifest
    }

    func start(context: any ForsettiModuleContext) throws {
        guard !started else {
            return
        }
        started = true
        context.logger.info("Module activated")
    }

    func stop(context: any ForsettiModuleContext) {
        guard started else {
            return
        }
        started = false
        context.logger.info("Module stopped")
    }
}

nonisolated final class ForsettiRetailUIModule: ForsettiLifecycleModule, ForsettiUIModule {
    let uiContributions = UIContributions.empty
}

nonisolated final class ForsettiJamfServiceModule: ForsettiLifecycleModule {}
nonisolated final class ForsettiDiagnosticsServiceModule: ForsettiLifecycleModule {}
nonisolated final class ForsettiScannerServiceModule: ForsettiLifecycleModule {}
nonisolated final class ForsettiComputerSearchModule: ForsettiLifecycleModule {}
nonisolated final class ForsettiMobileDeviceSearchModule: ForsettiLifecycleModule {}
nonisolated final class ForsettiSupportTechnicianModule: ForsettiLifecycleModule {}
nonisolated final class ForsettiPrestageDirectorModule: ForsettiLifecycleModule {}
nonisolated final class ForsettiReportsModule: ForsettiLifecycleModule {}
nonisolated final class ForsettiDeploymentTrackerModule: ForsettiLifecycleModule {}
nonisolated final class ForsettiPermissionsMatrixModule: ForsettiLifecycleModule {}
