import SwiftUI

final class ReportsModule: JamfModule {
    let id: String
    let title: String
    let subtitle: String
    let iconSystemName: String

    init(
        id: String = "forsetti.feature.reports",
        title: String = "Reports",
        subtitle: String = "Create visual fleet reports from Jamf Pro inventory.",
        iconSystemName: String = "chart.pie.fill"
    ) {
        self.id = id
        self.title = title
        self.subtitle = subtitle
        self.iconSystemName = iconSystemName
    }

    func makeRootView(context: ModuleContext) -> AnyView {
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
    }
}
