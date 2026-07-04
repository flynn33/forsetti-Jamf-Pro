import Foundation

enum JamfDashboardModuleIDs {
    static let diagnostics = "com.forsetti.jamfpro.service.diagnostics"
    static let jamf = "com.forsetti.jamfpro.service.jamf"
    static let scanner = "com.forsetti.jamfpro.service.scanner"
    static let computerSearch = "com.forsetti.jamfpro.feature.computer-search"
    static let mobileDeviceSearch = "com.forsetti.jamfpro.feature.mobile-device-search"
    static let supportTechnician = "com.forsetti.jamfpro.feature.support-technician"
    static let prestageDirector = "com.forsetti.jamfpro.feature.prestage-director"
    static let reports = "com.forsetti.jamfpro.feature.reports"
    static let deploymentTracker = "com.forsetti.jamfpro.feature.deployment-tracker"
    static let permissionsMatrix = "com.forsetti.jamfpro.feature.permissions-matrix"
    static let ui = "com.forsetti.jamfpro.ui.workspace"

    static let productionActivationOrder: [String] = [
        diagnostics,
        jamf,
        scanner,
        computerSearch,
        mobileDeviceSearch,
        supportTechnician,
        prestageDirector,
        reports,
        deploymentTracker,
        permissionsMatrix,
        ui
    ]

    static let productionModuleIDs = Set(productionActivationOrder)

    static let allDefinitions: [JamfDashboardModuleDefinition] = [
        diagnosticsDefinition,
        jamfDefinition,
        scannerDefinition,
        computerSearchDefinition,
        mobileDeviceSearchDefinition,
        supportTechnicianDefinition,
        prestageDirectorDefinition,
        reportsDefinition,
        deploymentTrackerDefinition,
        permissionsMatrixDefinition,
        uiDefinition
    ]

    static func definition(moduleID: String) -> JamfDashboardModuleDefinition {
        guard let definition = allDefinitions.first(where: { $0.moduleID == moduleID }) else {
            preconditionFailure("Unknown Forsetti Jamf Pro Forsetti module ID: \(moduleID)")
        }
        return definition
    }

    static let uiDefinition = JamfDashboardModuleDefinition(
        moduleID: ui,
        displayName: "Forsetti Jamf Pro UI",
        moduleType: .ui,
        entryPoint: JamfDashboardUIModule.Constants.entryPoint,
        defaultModuleRole: .ui,
        capabilitiesRequested: [
            .routingOverlay,
            .uiThemeMask,
            .toolbarItems,
            .viewInjection,
            .fileExport,
            .telemetry
        ],
        runtimeRequirements: ModuleRuntimeRequirements(
            io: [
                io("jamf-dashboard-ui.file-export", .fileExport, .write, required: true),
                io("jamf-dashboard-ui.telemetry", .telemetry, .emit, required: false)
            ],
            ui: ModuleUIRequirements(
                themeIDs: ["forsetti-obsidian-data-stream"],
                viewIDs: ["jamf-dashboard-root"],
                slotIDs: ["module.workspace"],
                toolbarItemIDs: ["jamf-dashboard-home"],
                routeIDs: ["jamf-dashboard-home"],
                pointerIDs: ["jamf-dashboard-home"]
            ),
            dataIsolation: ModuleDataIsolation(mode: .privateToModule, ownedStoreIDs: ["jamf-dashboard-ui"])
        )
    )

    static let jamfDefinition = JamfDashboardModuleDefinition(
        moduleID: jamf,
        displayName: "Jamf Service",
        moduleType: .service,
        entryPoint: JamfServiceModule.Constants.entryPoint,
        defaultModuleRole: .api,
        capabilitiesRequested: [.networking, .secureStorage, .authentication, .api, .security, .diagnostics],
        runtimeRequirements: serviceRequirements(
            ownedStoreID: "jamf-service",
            io: [
                io("jamf-service.networking", .networking, .readWrite, required: true),
                io("jamf-service.secure-storage", .secureStorage, .readWrite, required: true),
                io("jamf-service.authentication", .authentication, .consume, required: true),
                io("jamf-service.api", .api, .consume, required: true),
                io("jamf-service.security", .security, .consume, required: true),
                io("jamf-service.diagnostics", .diagnostics, .emit, required: false)
            ]
        )
    )

    static let diagnosticsDefinition = JamfDashboardModuleDefinition(
        moduleID: diagnostics,
        displayName: "Diagnostics Service",
        moduleType: .service,
        entryPoint: DiagnosticsServiceModule.Constants.entryPoint,
        defaultModuleRole: .diagnostics,
        capabilitiesRequested: [.diagnostics, .telemetry, .fileExport, .storage],
        runtimeRequirements: serviceRequirements(
            ownedStoreID: "diagnostics-service",
            io: [
                io("diagnostics-service.diagnostics", .diagnostics, .emit, required: true),
                io("diagnostics-service.telemetry", .telemetry, .emit, required: false),
                io("diagnostics-service.file-export", .fileExport, .write, required: true),
                io("diagnostics-service.storage", .storage, .readWrite, required: false)
            ]
        )
    )

    static let scannerDefinition = JamfDashboardModuleDefinition(
        moduleID: scanner,
        displayName: "Scanner Service",
        moduleType: .service,
        entryPoint: ScannerServiceModule.Constants.entryPoint,
        capabilitiesRequested: [.storage, .diagnostics],
        runtimeRequirements: serviceRequirements(
            ownedStoreID: "scanner-service",
            io: [
                io("scanner-service.storage", .storage, .readWrite, required: false),
                io("scanner-service.diagnostics", .diagnostics, .emit, required: false)
            ]
        )
    )

    static let computerSearchDefinition = JamfDashboardModuleDefinition(
        moduleID: computerSearch,
        displayName: "Computer Search Feature Service",
        moduleType: .service,
        entryPoint: ComputerSearchServiceModule.Constants.entryPoint,
        capabilitiesRequested: [.networking, .storage, .diagnostics, .api, .fileExport],
        runtimeRequirements: featureServiceRequirements(ownedStoreID: "computer-search")
    )

    static let mobileDeviceSearchDefinition = JamfDashboardModuleDefinition(
        moduleID: mobileDeviceSearch,
        displayName: "Mobile Device Search Feature Service",
        moduleType: .service,
        entryPoint: MobileDeviceSearchServiceModule.Constants.entryPoint,
        capabilitiesRequested: [.networking, .storage, .diagnostics, .api, .fileExport],
        runtimeRequirements: featureServiceRequirements(ownedStoreID: "mobile-device-search")
    )

    static let supportTechnicianDefinition = JamfDashboardModuleDefinition(
        moduleID: supportTechnician,
        displayName: "Support Technician Feature Service",
        moduleType: .service,
        entryPoint: SupportTechnicianServiceModule.Constants.entryPoint,
        capabilitiesRequested: [.networking, .secureStorage, .diagnostics, .api, .security, .fileExport],
        runtimeRequirements: serviceRequirements(
            ownedStoreID: "support-technician",
            io: [
                io("support-technician.networking", .networking, .readWrite, required: true),
                io("support-technician.secure-storage", .secureStorage, .readWrite, required: true),
                io("support-technician.diagnostics", .diagnostics, .emit, required: false),
                io("support-technician.api", .api, .consume, required: true),
                io("support-technician.security", .security, .consume, required: true),
                io("support-technician.file-export", .fileExport, .write, required: false)
            ]
        )
    )

    static let prestageDirectorDefinition = JamfDashboardModuleDefinition(
        moduleID: prestageDirector,
        displayName: "PreStage Director Feature Service",
        moduleType: .service,
        entryPoint: PrestageDirectorServiceModule.Constants.entryPoint,
        capabilitiesRequested: [.networking, .diagnostics, .api, .fileExport],
        runtimeRequirements: serviceRequirements(
            ownedStoreID: "prestage-director",
            io: [
                io("prestage-director.networking", .networking, .readWrite, required: true),
                io("prestage-director.diagnostics", .diagnostics, .emit, required: false),
                io("prestage-director.api", .api, .consume, required: true),
                io("prestage-director.file-export", .fileExport, .write, required: false)
            ]
        )
    )

    static let reportsDefinition = JamfDashboardModuleDefinition(
        moduleID: reports,
        displayName: "Reports Feature Service",
        moduleType: .service,
        entryPoint: ReportsServiceModule.Constants.entryPoint,
        capabilitiesRequested: [.networking, .storage, .diagnostics, .api, .fileExport],
        runtimeRequirements: featureServiceRequirements(ownedStoreID: "reports")
    )

    static let deploymentTrackerDefinition = JamfDashboardModuleDefinition(
        moduleID: deploymentTracker,
        displayName: "Deployment Tracker Feature Service",
        moduleType: .service,
        entryPoint: DeploymentTrackerServiceModule.Constants.entryPoint,
        capabilitiesRequested: [.storage, .diagnostics, .fileExport, .telemetry],
        runtimeRequirements: serviceRequirements(
            ownedStoreID: "deployment-tracker",
            io: [
                io("deployment-tracker.storage", .storage, .readWrite, required: false),
                io("deployment-tracker.diagnostics", .diagnostics, .emit, required: false),
                io("deployment-tracker.file-export", .fileExport, .write, required: false),
                io("deployment-tracker.telemetry", .telemetry, .emit, required: false)
            ]
        )
    )

    static let permissionsMatrixDefinition = JamfDashboardModuleDefinition(
        moduleID: permissionsMatrix,
        displayName: "Permissions Helper Feature Service",
        moduleType: .service,
        entryPoint: PermissionsMatrixServiceModule.Constants.entryPoint,
        capabilitiesRequested: [.storage, .diagnostics, .fileExport],
        runtimeRequirements: serviceRequirements(
            ownedStoreID: "permissions-matrix",
            io: [
                io("permissions-matrix.storage", .storage, .readWrite, required: false),
                io("permissions-matrix.diagnostics", .diagnostics, .emit, required: false),
                io("permissions-matrix.file-export", .fileExport, .write, required: false)
            ]
        )
    )

    private static func featureServiceRequirements(ownedStoreID: String) -> ModuleRuntimeRequirements {
        serviceRequirements(
            ownedStoreID: ownedStoreID,
            io: [
                io("\(ownedStoreID).networking", .networking, .readWrite, required: true),
                io("\(ownedStoreID).storage", .storage, .readWrite, required: false),
                io("\(ownedStoreID).diagnostics", .diagnostics, .emit, required: false),
                io("\(ownedStoreID).api", .api, .consume, required: true),
                io("\(ownedStoreID).file-export", .fileExport, .write, required: false)
            ]
        )
    }

    private static func serviceRequirements(
        ownedStoreID: String,
        io: [ModuleIORequirement]
    ) -> ModuleRuntimeRequirements {
        ModuleRuntimeRequirements(
            io: io,
            ui: nil,
            dataIsolation: ModuleDataIsolation(mode: .privateToModule, ownedStoreIDs: [ownedStoreID])
        )
    }

    private static func io(
        _ requirementID: String,
        _ kind: ModuleIOKind,
        _ access: ModuleIOAccess,
        required: Bool
    ) -> ModuleIORequirement {
        ModuleIORequirement(
            requirementID: requirementID,
            kind: kind,
            access: access,
            required: required
        )
    }
}

struct JamfDashboardModuleDefinition: Sendable {
    let moduleID: String
    let displayName: String
    let moduleType: ModuleType
    let entryPoint: String
    let defaultModuleRole: DefaultModuleRole?
    let capabilitiesRequested: [Capability]
    let runtimeRequirements: ModuleRuntimeRequirements

    init(
        moduleID: String,
        displayName: String,
        moduleType: ModuleType,
        entryPoint: String,
        defaultModuleRole: DefaultModuleRole? = nil,
        capabilitiesRequested: [Capability],
        runtimeRequirements: ModuleRuntimeRequirements
    ) {
        self.moduleID = moduleID
        self.displayName = displayName
        self.moduleType = moduleType
        self.entryPoint = entryPoint
        self.defaultModuleRole = defaultModuleRole
        self.capabilitiesRequested = capabilitiesRequested
        self.runtimeRequirements = runtimeRequirements
    }

    var descriptor: ModuleDescriptor {
        ModuleDescriptor(
            moduleID: moduleID,
            displayName: displayName,
            moduleVersion: Self.moduleVersion,
            moduleType: moduleType
        )
    }

    var manifest: ModuleManifest {
        ModuleManifest(
            schemaVersion: ModuleManifest.currentSchemaVersion,
            manifestTemplateVersion: .current,
            moduleID: moduleID,
            displayName: displayName,
            moduleVersion: Self.moduleVersion,
            moduleType: moduleType,
            supportedPlatforms: [.iOS, .macOS],
            minForsettiVersion: SemVer(major: 0, minor: 1, patch: 0),
            capabilitiesRequested: capabilitiesRequested,
            entryPoint: entryPoint,
            defaultModuleRole: defaultModuleRole,
            runtimeRequirements: runtimeRequirements
        )
    }

    private static let moduleVersion = ForsettiAppVersion.moduleSemVer
}
