import Combine
import Foundation

@MainActor
final class JamfDashboardForsettiBootstrap: ObservableObject {
    enum ProductionBootState: Equatable {
        case idle
        case booting
        case ready
        case failed(String)
    }

    let appServices: ForsettiJamfProAppServices
    let controller: RuntimeController
    let injectionRegistry: ForsettiViewInjectionRegistry

    @Published private(set) var productionState: ProductionBootState = .idle

    convenience init() {
        self.init(appServices: ForsettiJamfProAppServices())
    }

    init(appServices: ForsettiJamfProAppServices) {
        self.appServices = appServices

        let registry = ModuleRegistry()
        do {
            try JamfDashboardModuleRegistry.registerAll(into: registry)
        } catch {
            assertionFailure("Failed to register Forsetti Jamf Pro Forsetti modules: \(error.localizedDescription)")
        }

        let serviceContainer = JamfDashboardServiceComposition.makeForsettiServiceContainer(appServices: appServices)
        controller = RuntimeController(
            registry: registry,
            services: serviceContainer,
            eventBus: EventBus(),
            compatibilityChecker: CompatibilityChecker(appVersion: ForsettiAppVersion.current),
            capabilityPolicy: CapabilityPolicy(),
            activationStore: UserDefaultsActivationStore(
                key: "com.forsetti.jamfpro.activation.state"
            ),
            logger: AppRuntimeLogger(
                subsystem: "com.forsetti.jamfpro",
                category: "runtime"
            )
        )
        injectionRegistry = JamfDashboardViewInjectionRegistry.makeRegistry(appServices: appServices)
    }

    func bootForProduction() async {
        guard productionState != .ready, productionState != .booting else {
            return
        }

        productionState = .booting
        let manifests = loadProductionManifests()
        await controller.boot(
            manifests: manifests,
            activationOrder: JamfDashboardModuleIDs.productionActivationOrder
        )

        if let errorMessage = controller.errorMessage {
            productionState = .failed(errorMessage)
            return
        }

        let requiredServiceIDs = Set(JamfDashboardModuleIDs.productionActivationOrder.dropLast())
        let missingServiceIDs = requiredServiceIDs.subtracting(controller.enabledServiceModuleIDs)
        guard missingServiceIDs.isEmpty else {
            productionState = .failed(
                "Required service modules did not activate: \(missingServiceIDs.sorted().joined(separator: ", "))."
            )
            return
        }

        guard controller.activeUIModuleID == JamfDashboardModuleIDs.ui else {
            productionState = .failed("Forsetti Jamf Pro UI activation failed.")
            return
        }

        productionState = .ready
    }

    func retryProductionBoot() {
        productionState = .idle
        controller.clearError()
        Task {
            await bootForProduction()
        }
    }

    private func loadProductionManifests() -> [ModuleManifest] {
        do {
            return try ManifestLoader().loadManifests(bundle: .main, subdirectory: "ForsettiManifests")
        } catch {
            return JamfDashboardModuleIDs.allDefinitions.map(\.manifest)
        }
    }
}
