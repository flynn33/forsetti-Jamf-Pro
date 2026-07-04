import ForsettiHostTemplate
import SwiftUI

struct JamfDashboardProductionRootView: View {
    @ObservedObject var bootstrap: JamfDashboardForsettiBootstrap

    var body: some View {
        Group {
            switch bootstrap.productionState {
            case .idle, .booting:
                ProgressView()
                    .controlSize(.large)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .task {
                        await bootstrap.bootForProduction()
                    }
            case .ready:
                JamfDashboardRootView(appServices: bootstrap.appServices)
            case let .failed(message):
                ContentUnavailableView {
                    Label("Jamf Dashboard failed to start", systemImage: "exclamationmark.triangle")
                } description: {
                    Text(message)
                } actions: {
                    Button("Retry") {
                        bootstrap.retryProductionBoot()
                    }
                }
            }
        }
    }
}

struct JamfDashboardLaunchView: View {
    @ObservedObject var bootstrap: JamfDashboardForsettiBootstrap
    private let deploymentMode: JamfDashboardDeploymentMode

    init(
        bootstrap: JamfDashboardForsettiBootstrap,
        deploymentMode: JamfDashboardDeploymentMode = .current
    ) {
        self.bootstrap = bootstrap
        self.deploymentMode = deploymentMode
    }

    var body: some View {
        switch deploymentMode {
        case .production:
            JamfDashboardProductionRootView(bootstrap: bootstrap)
        case .development:
            ForsettiHostRootView(
                controller: bootstrap.controller,
                injectionRegistry: bootstrap.injectionRegistry,
                showDeveloperControls: true,
                launchActivationStrategy: .activate(moduleIDs: JamfDashboardModuleIDs.productionModuleIDs)
            )
        }
    }
}
