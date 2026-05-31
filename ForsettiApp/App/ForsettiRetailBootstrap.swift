import Combine
import Foundation
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
            schemaVersion: ModuleManifest.supportedSchemaVersion,
            moduleID: moduleID,
            displayName: displayName,
            moduleVersion: SemVer(major: 1, minor: 0, patch: 0),
            moduleType: moduleType,
            supportedPlatforms: [.iOS, .macOS],
            minForsettiVersion: SemVer(major: 0, minor: 1, patch: 0),
            maxForsettiVersion: nil,
            capabilitiesRequested: capabilitiesRequested,
            iapProductID: nil,
            entryPoint: entryPoint
        )
    }
}

@MainActor
final class ForsettiRetailBootstrap: ObservableObject {
    @Published private(set) var isBooted = false
    @Published private(set) var errorMessage: String?

    private var bootTask: Task<Void, Never>?

    nonisolated static let manifestSpecs: [ForsettiRetailManifestSpec] = [
        .init(
            moduleID: "forsetti.retail.ui",
            displayName: "Forsetti Retail UI",
            moduleType: .ui,
            capabilitiesRequested: [.routingOverlay, .toolbarItems, .viewInjection],
            entryPoint: "ForsettiRetailUIModule"
        ),
        .init(
            moduleID: "forsetti.service.jamf",
            displayName: "Jamf Service",
            moduleType: .service,
            capabilitiesRequested: [.networking, .secureStorage, .storage, .telemetry],
            entryPoint: "ForsettiJamfServiceModule"
        ),
        .init(
            moduleID: "forsetti.service.diagnostics",
            displayName: "Diagnostics Service",
            moduleType: .service,
            capabilitiesRequested: [.telemetry, .fileExport],
            entryPoint: "ForsettiDiagnosticsServiceModule"
        ),
        .init(
            moduleID: "forsetti.service.scanner",
            displayName: "Scanner Service",
            moduleType: .service,
            capabilitiesRequested: [],
            entryPoint: "ForsettiScannerServiceModule"
        ),
        .init(
            moduleID: "forsetti.feature.computer-search",
            displayName: "Computer Search",
            moduleType: .service,
            capabilitiesRequested: [.networking, .storage],
            entryPoint: "ForsettiComputerSearchFeatureModule"
        ),
        .init(
            moduleID: "forsetti.feature.mobile-device-search",
            displayName: "Mobile Device Search",
            moduleType: .service,
            capabilitiesRequested: [.networking, .storage],
            entryPoint: "ForsettiMobileDeviceSearchFeatureModule"
        ),
        .init(
            moduleID: "forsetti.feature.support-technician",
            displayName: "Support Technician",
            moduleType: .service,
            capabilitiesRequested: [.networking, .storage, .fileExport],
            entryPoint: "ForsettiSupportTechnicianFeatureModule"
        ),
        .init(
            moduleID: "forsetti.feature.prestage-director",
            displayName: "Prestage Director",
            moduleType: .service,
            capabilitiesRequested: [.networking, .storage],
            entryPoint: "ForsettiPrestageDirectorFeatureModule"
        ),
        .init(
            moduleID: "forsetti.feature.reports",
            displayName: "Reports",
            moduleType: .service,
            capabilitiesRequested: [.networking, .storage, .fileExport],
            entryPoint: "ForsettiReportsFeatureModule"
        ),
        .init(
            moduleID: "forsetti.feature.deployment-tracker",
            displayName: "Deployment Tracker",
            moduleType: .service,
            capabilitiesRequested: [.networking, .storage, .fileExport],
            entryPoint: "ForsettiDeploymentTrackerFeatureModule"
        )
    ]

    let runtime: ForsettiRuntime

    private init(runtime: ForsettiRuntime) {
        self.runtime = runtime
    }

    static func makeController() -> ForsettiRetailBootstrap {
        let platformServices = DefaultForsettiPlatformServices()
        let registry = ForsettiStaticModuleRegistry.buildRegistry { registry in
            for spec in manifestSpecs {
                registry.register(entryPoint: spec.entryPoint) {
                    if spec.moduleType == .ui {
                        return ForsettiRetailUIModule(manifest: spec.manifest)
                    }
                    return ForsettiRetailServiceModule(manifest: spec.manifest)
                }
            }
        }

        let runtime = ForsettiRuntime(
            services: platformServices.container,
            activationStore: UserDefaultsActivationStore(key: "forsetti.retail.activation.state"),
            moduleRegistry: registry
        )
        return ForsettiRetailBootstrap(runtime: runtime)
    }

    func bootIfNeeded() async {
        guard !isBooted else {
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
        guard !isBooted else {
            return
        }

        errorMessage = nil

        do {
            _ = try await runtime.boot(
                bundle: .main,
                manifestsSubdirectory: "ForsettiManifests",
                restoreActivationState: false
            )

            for spec in Self.manifestSpecs where spec.moduleType == .service {
                try await runtime.moduleManager.activateModule(moduleID: spec.moduleID)
            }

            try await runtime.moduleManager.activateModule(moduleID: "forsetti.retail.ui")
            try runtime.moduleManager.setSelectedUIModule(moduleID: "forsetti.retail.ui")
            isBooted = true
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

nonisolated private final class ForsettiRetailServiceModule: ForsettiModule {
    let manifest: ModuleManifest

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

    func start(context: ForsettiContext) throws {
        context.logModule(.info, moduleID: manifest.moduleID, message: "Service module activated")
    }

    func stop(context: ForsettiContext) {
        context.logModule(.info, moduleID: manifest.moduleID, message: "Service module stopped")
    }
}

nonisolated private final class ForsettiRetailUIModule: ForsettiModule, ForsettiUIModule {
    let manifest: ModuleManifest
    let uiContributions = UIContributions.empty

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

    func start(context: ForsettiContext) throws {
        context.logModule(.info, moduleID: manifest.moduleID, message: "Retail UI module activated")
    }

    func stop(context: ForsettiContext) {
        context.logModule(.info, moduleID: manifest.moduleID, message: "Retail UI module stopped")
    }
}
