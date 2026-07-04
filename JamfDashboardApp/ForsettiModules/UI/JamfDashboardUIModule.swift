import ForsettiCore
import Foundation

final class JamfDashboardUIModule: ForsettiUIModule {
    enum Constants {
        static let entryPoint = "JamfDashboardUIModule"
    }

    private let definition = JamfDashboardModuleIDs.uiDefinition

    var descriptor: ModuleDescriptor { definition.descriptor }
    var manifest: ModuleManifest { definition.manifest }

    var uiContributions: UIContributions {
        UIContributions(
            themeMask: ThemeMask(
                themeID: "jamf-dashboard",
                tokens: [
                    ThemeToken(key: "accent", value: "bluePrimary"),
                    ThemeToken(key: "surface", value: "groupedSurface")
                ]
            ),
            toolbarItems: [
                ToolbarItemDescriptor(
                    itemID: "jamf-dashboard-home",
                    title: "Jamf Dashboard",
                    systemImageName: "app",
                    action: .navigate(pointerID: "jamf-dashboard-home")
                )
            ],
            viewInjections: [
                ViewInjectionDescriptor(
                    injectionID: "jamf-dashboard-root",
                    slot: "module.workspace",
                    viewID: "jamf-dashboard-root",
                    priority: 100
                )
            ],
            overlaySchema: OverlaySchema(
                schemaID: "jamf-dashboard",
                pointers: [
                    NavigationPointer(
                        pointerID: "jamf-dashboard-home",
                        label: "Jamf Dashboard",
                        target: BaseDestinationRef(destinationID: "home"),
                        presentation: .push
                    )
                ],
                routes: [
                    OverlayRoute(
                        routeID: "jamf-dashboard-home",
                        path: "/jamf-dashboard",
                        destination: .base(destinationID: "home", parameters: nil)
                    )
                ]
            )
        )
    }

    func start(context: any ForsettiModuleContext) throws {
        try JamfDashboardModuleLifecycle.start(
            definition: definition,
            context: context,
            requiredServices: [.fileExport, .telemetry]
        )
    }

    func stop(context: any ForsettiModuleContext) {
        JamfDashboardModuleLifecycle.stop(definition: definition, context: context)
    }
}
