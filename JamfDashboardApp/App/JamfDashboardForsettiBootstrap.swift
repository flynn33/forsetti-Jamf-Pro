import Combine
import ForsettiCore
import ForsettiHostTemplate
import ForsettiPlatform
import Foundation

@MainActor
final class JamfDashboardForsettiBootstrap: ObservableObject {
    enum ProductionBootState: Equatable {
        case idle
        case booting
        case ready
        case failed(String)
    }

    let appServices: JamfDashboardAppServices
    let controller: ForsettiHostController
    let injectionRegistry: ForsettiViewInjectionRegistry

    @Published private(set) var productionState: ProductionBootState = .idle

    convenience init() {
        self.init(appServices: JamfDashboardAppServices())
    }

    init(appServices: JamfDashboardAppServices) {
        self.appServices = appServices

        let registry = ModuleRegistry()
        do {
            try JamfDashboardModuleRegistry.registerAll(into: registry)
        } catch {
            assertionFailure("Failed to register Jamf Dashboard Forsetti modules: \(error.localizedDescription)")
        }

        let serviceContainer = JamfDashboardServiceComposition.makeForsettiServiceContainer(appServices: appServices)
        let entitlementProvider = AllowAllEntitlementProvider()
        let uiSurfaceManager = UISurfaceManager()
        let router = ForsettiHostOverlayRouter(
            uiSurfaceManager: uiSurfaceManager,
            baseDestinationIDs: BaseDestinationCatalog.all,
            slotIDs: SlotCatalog.all
        )

        let runtime = ForsettiRuntime(
            services: serviceContainer,
            entitlementProvider: entitlementProvider,
            capabilityPolicy: AllowAllCapabilityPolicy(),
            activationStore: UserDefaultsActivationStore(
                key: "com.forsetti.jamfdashboard.activation.state"
            ),
            logger: OSLogForsettiLogger(
                subsystem: "com.forsetti.jamfdashboard",
                category: "runtime"
            ),
            router: router,
            moduleRegistry: registry,
            uiSurfaceManager: uiSurfaceManager
        )

        controller = ForsettiHostController(
            runtime: runtime,
            entitlementProvider: entitlementProvider,
            manifestsBundle: .main,
            manifestsSubdirectory: "ForsettiManifests",
            slotCatalog: SlotCatalog.all
        )
        injectionRegistry = JamfDashboardViewInjectionRegistry.makeRegistry(appServices: appServices)
    }

    func bootForProduction() async {
        guard productionState != .ready, productionState != .booting else {
            return
        }

        productionState = .booting
        await controller.bootIfNeeded(
            restoreActivationState: false,
            activationStrategy: .activate(moduleIDs: JamfDashboardModuleIDs.productionModuleIDs)
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
            productionState = .failed("Jamf Dashboard UI activation failed.")
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
}
