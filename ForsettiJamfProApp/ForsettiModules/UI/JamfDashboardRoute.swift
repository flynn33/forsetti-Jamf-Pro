import SwiftUI

enum JamfDashboardRoute: String, CaseIterable, Hashable, Identifiable {
    case computerSearch
    case mobileDeviceSearch
    case supportTechnician
    case prestageDirector
    case reports
    case deploymentTracker
    case permissionsMatrix

    var id: String { rawValue }

    var moduleID: String {
        switch self {
        case .computerSearch:
            return JamfDashboardModuleIDs.computerSearch
        case .mobileDeviceSearch:
            return JamfDashboardModuleIDs.mobileDeviceSearch
        case .supportTechnician:
            return JamfDashboardModuleIDs.supportTechnician
        case .prestageDirector:
            return JamfDashboardModuleIDs.prestageDirector
        case .reports:
            return JamfDashboardModuleIDs.reports
        case .deploymentTracker:
            return JamfDashboardModuleIDs.deploymentTracker
        case .permissionsMatrix:
            return JamfDashboardModuleIDs.permissionsMatrix
        }
    }

    var title: String {
        switch self {
        case .computerSearch:
            return "Computer Search"
        case .mobileDeviceSearch:
            return "Mobile Device Search"
        case .supportTechnician:
            return "Support Technician"
        case .prestageDirector:
            return "PreStage Director"
        case .reports:
            return "Reports"
        case .deploymentTracker:
            return "Deployment Tracker Demo"
        case .permissionsMatrix:
            return "Permissions Helper"
        }
    }

    var subtitle: String {
        switch self {
        case .computerSearch:
            return "Search computer inventory and create reusable field-based profiles."
        case .mobileDeviceSearch:
            return "Search inventory and create reusable field-based profiles."
        case .supportTechnician:
            return "Unified support workflow for computer and mobile device tickets."
        case .prestageDirector:
            return "View prestages and move or remove assigned devices."
        case .reports:
            return "Create visual fleet reports from Jamf Pro inventory."
        case .deploymentTracker:
            return "Interactive preview with dummy data only. No live Jamf actions."
        case .permissionsMatrix:
            return "Look up Jamf Pro privileges required for app actions and API endpoints."
        }
    }

    var iconSystemName: String {
        switch self {
        case .computerSearch:
            return "desktopcomputer"
        case .mobileDeviceSearch:
            return "iphone.gen3"
        case .supportTechnician:
            return "wrench.and.screwdriver"
        case .prestageDirector:
            return "arrow.left.arrow.right.square"
        case .reports:
            return "chart.pie.fill"
        case .deploymentTracker:
            return "sparkles.rectangle.stack"
        case .permissionsMatrix:
            return "checklist.checked"
        }
    }

    @MainActor
    func makeRootView(context: JamfDashboardViewContext) -> AnyView {
        switch self {
        case .computerSearch:
            let viewModel = ComputerSearchViewModel(
                apiGateway: context.apiGateway,
                diagnosticsReporter: context.diagnosticsReporter,
                profileStore: ComputerSearchProfileStore()
            )
            return AnyView(ComputerSearchView(viewModel: viewModel))
        case .mobileDeviceSearch:
            let viewModel = MobileDeviceSearchViewModel(
                apiGateway: context.apiGateway,
                diagnosticsReporter: context.diagnosticsReporter,
                profileStore: MobileDeviceSearchProfileStore(),
                smartFilterStore: SmartFilterStore()
            )
            return AnyView(MobileDeviceSearchView(viewModel: viewModel))
        case .supportTechnician:
            let viewModel = SupportTechnicianViewModel(
                apiGateway: context.apiGateway,
                diagnosticsReporter: context.diagnosticsReporter
            )
            return AnyView(SupportTechnicianView(viewModel: viewModel))
        case .prestageDirector:
            let viewModel = PrestageDirectorViewModel(
                apiGateway: context.apiGateway,
                diagnosticsReporter: context.diagnosticsReporter
            )
            return AnyView(PrestageDirectorView(viewModel: viewModel))
        case .reports:
            let service = ReportsInventoryService(
                apiGateway: context.apiGateway,
                diagnosticsReporter: context.diagnosticsReporter
            )
            let viewModel = ReportsViewModel(
                inventoryService: service,
                credentialsStore: context.credentialsStore,
                diagnosticsReporter: context.diagnosticsReporter
            )
            return AnyView(ReportsView(viewModel: viewModel))
        case .deploymentTracker:
            let viewModel = DeploymentTrackerViewModel(
                apiGateway: context.apiGateway,
                credentialsStore: context.credentialsStore,
                diagnosticsReporter: context.diagnosticsReporter,
                runtimeMode: .demo,
                demoConfiguration: .installedDemo
            )
            return AnyView(DeploymentTrackerRootView(viewModel: viewModel))
        case .permissionsMatrix:
            let loader = PermissionsMatrixResourceLoader(
                bundle: .main,
                diagnosticsReporter: context.diagnosticsReporter
            )
            let verifier = PermissionsMatrixRuntimeVerifier(
                apiGateway: context.apiGateway,
                diagnosticsReporter: context.diagnosticsReporter
            )
            let viewModel = PermissionsMatrixViewModel(
                resourceLoader: loader,
                runtimeVerifier: verifier,
                credentialsStore: context.credentialsStore,
                diagnosticsReporter: context.diagnosticsReporter
            )
            return AnyView(PermissionsMatrixView(viewModel: viewModel))
        }
    }
}
