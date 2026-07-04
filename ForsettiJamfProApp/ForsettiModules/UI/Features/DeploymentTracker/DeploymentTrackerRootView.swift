import Combine
import SwiftUI

// MARK: - Deployment Tracker UI composition
//
// Developed by Jim Daley, FSD, FSE.
//
// This file owns the Deployment Tracker view model and SwiftUI root surface.
// The Forsetti service entry point for this feature lives in
// `ForsettiModules/Services/DeploymentTrackerServiceModule.swift`.
//
// Keep this layer focused on orchestration. Business rules should continue to
// live in the tracker services, workflow engine, validators, renderers, and
// persistence adapters so the module remains testable and does not grow hidden
// dependencies on other dashboard modules.
// MARK: - View model
//
// The view model is the module's main UI state coordinator. It translates user
// intent from SwiftUI controls into persistence operations, validations, export
// rendering, Jamf Inventory Preload calls, and diagnostics events. The view
// model is MainActor-isolated because most properties are SwiftUI-observed state.
@MainActor
final class DeploymentTrackerViewModel: ObservableObject {
    // Shared app services are passed in by the dedicated UI route catalog so
    // this surface does not construct parallel service stacks.
    let apiGateway: JamfAPIGateway
    let credentialsStore: JamfCredentialsStore
    let diagnosticsReporter: any DiagnosticsReporting
    private(set) var store: any DeploymentTrackerStore
    let runtimeMode: DeploymentTrackerRuntimeMode
    let demoConfiguration: DeploymentTrackerDemoConfiguration

    // Domain snapshots loaded from the tracker store. Most properties are
    // private(set) so views can render them but must use view-model actions to
    // change state, keeping audit, validation, and projection refresh behavior
    // centralized.
    @Published private(set) var fieldDefinitions: [DeploymentFieldDefinition]
    @Published private(set) var workbenchLayout: WorkbenchLayout
    @Published private(set) var workflowStatuses: [DeploymentWorkflowStatusDefinition]
    @Published private(set) var devices: [DeploymentDevice]
    @Published private(set) var projects: [DeploymentProject]
    @Published private(set) var referenceValues: [DeploymentReferenceValue]
    @Published private(set) var workbenchLayouts: [WorkbenchLayout]
    @Published private(set) var auditEvents: [DeploymentAuditEvent]
    @Published private(set) var workflowEvents: [DeploymentWorkflowEvent]
    @Published private(set) var exceptions: [DeploymentException]
    @Published private(set) var appleCatalogEntries: [DeploymentAppleHardwareCatalogEntry]
    @Published private(set) var preloadSubmissions: [JamfInventoryPreloadSubmission]
    @Published private(set) var sdPlusExportJobs: [SDPlusExportJob]
    @Published private(set) var recordsExportJobs: [RecordsExportJob]
    @Published private(set) var projection: DeploymentWorkbenchProjection
    @Published private(set) var dashboardProjection: DeploymentDashboardProjection
    @Published private(set) var loadErrorMessage: String?
    @Published private(set) var userFacingError: DeploymentUserFacingIntegrationError?
    @Published private(set) var actionMessage: String?
    @Published private(set) var exportPreview: String?
    @Published private(set) var preloadValidationResult: JamfInventoryPreloadValidationResult?
    @Published private(set) var preloadCSVPreview: String?
    @Published private(set) var sdPlusPreview: String?
    @Published private(set) var demoSimulationResult: DeploymentDemoSimulationResult?
    @Published private(set) var activeDemoScenario: DeploymentDemoScenario?
    @Published private(set) var activeDemoScenarioStepIndex: Int
    @Published private(set) var isDemoScenarioPaused: Bool
    @Published private(set) var completedDemoScenario: DeploymentDemoScenario?
    @Published private(set) var isLoading: Bool

    // User interface state. These values do not belong in persistence because
    // they represent the current session's selection, visible panels, filters,
    // and guide navigation.
    @Published var selectedDeviceID: String?
    @Published var isFieldCatalogPresented: Bool
    @Published var filterText: String
    @Published var selectedWorkspace: DeploymentTrackerWorkspace
    @Published var preloadSerialInput: String
    @Published var preloadBatchInput: String
    @Published var isGuidePresented: Bool
    @Published var selectedGuideTopicID: String?
    @Published var guideSearchText: String

    // Services stay private to keep all write paths in this view model explicit.
    // When a view needs a new behavior, prefer adding a small intent method here
    // rather than reaching into service objects from SwiftUI.
    private let projectionService: DeploymentWorkbenchProjectionService
    private var preloadService: JamfInventoryPreloadService
    private var sdPlusService: SDPlusExportService
    private var recordsService: RecordsManagementExportService
    private let demoIntegrationSimulator: DeploymentTrackerDemoIntegrationSimulator

    // Store resolution allows the module to fall back to in-memory storage if
    // the local database cannot be opened. That fallback is intentionally noisy:
    // the operator gets a structured warning and diagnostics get a correlation
    // trail because changes may not persist after app shutdown.
    private struct StoreResolution {
        let store: any DeploymentTrackerStore
        let startupIssue: DeploymentUserFacingIntegrationError?
    }

    init(
        apiGateway: JamfAPIGateway,
        credentialsStore: JamfCredentialsStore,
        diagnosticsReporter: any DiagnosticsReporting,
        runtimeMode: DeploymentTrackerRuntimeMode = .demo,
        demoConfiguration: DeploymentTrackerDemoConfiguration = .installedDemo,
        store: (any DeploymentTrackerStore)? = nil,
        preloadAPIClient: (any JamfInventoryPreloadAPIClient)? = nil
    ) {
        let demoSeed = runtimeMode.isDemoMode && store == nil ? DeploymentTrackerDemoDataFactory.makeSeed() : nil
        let storeResolution = Self.resolveStore(store, runtimeMode: runtimeMode, demoSeed: demoSeed)
        let resolvedStore = storeResolution.store
        let selectedPreloadClient: (any JamfInventoryPreloadAPIClient)?
        if let preloadAPIClient {
            selectedPreloadClient = preloadAPIClient
        } else if runtimeMode.isDemoMode || demoConfiguration.allowLiveJamfActions == false {
            selectedPreloadClient = DeploymentDemoJamfInventoryPreloadClient(
                records: demoSeed?.jamfPreloadRecords ?? DeploymentTrackerDemoDataFactory.makePreloadRecords()
            )
        } else {
            selectedPreloadClient = nil
        }
        self.apiGateway = apiGateway
        self.credentialsStore = credentialsStore
        self.diagnosticsReporter = diagnosticsReporter
        self.runtimeMode = runtimeMode
        self.demoConfiguration = demoConfiguration
        self.store = resolvedStore
        self.fieldDefinitions = DeploymentTrackerSeedData.fieldDefinitions
        self.workbenchLayout = DeploymentTrackerSeedData.workbookDefaultLayout
        self.workflowStatuses = DeploymentTrackerSeedData.workflowStatuses
        self.devices = []
        self.projects = []
        self.workbenchLayouts = [DeploymentTrackerSeedData.workbookDefaultLayout]
        self.auditEvents = []
        self.workflowEvents = []
        self.exceptions = []
        self.appleCatalogEntries = []
        self.preloadSubmissions = []
        self.sdPlusExportJobs = []
        self.recordsExportJobs = []
        self.referenceValues = Self.combinedReferenceValues(
            referenceValues: DeploymentTrackerSeedData.referenceValues,
            workflowStatuses: DeploymentTrackerSeedData.workflowStatuses
        )
        self.projectionService = DeploymentWorkbenchProjectionService()
        if let selectedPreloadClient {
            self.preloadService = JamfInventoryPreloadService(
                apiClient: selectedPreloadClient,
                store: resolvedStore,
                diagnosticsReporter: diagnosticsReporter
            )
        } else {
            self.preloadService = JamfInventoryPreloadService(
                apiGateway: apiGateway,
                store: resolvedStore,
                diagnosticsReporter: diagnosticsReporter
            )
        }
        self.sdPlusService = SDPlusExportService(store: resolvedStore, diagnosticsReporter: diagnosticsReporter)
        self.recordsService = RecordsManagementExportService(store: resolvedStore)
        self.demoIntegrationSimulator = DeploymentTrackerDemoIntegrationSimulator(configuration: demoConfiguration)
        self.projection = projectionService.makeProjection(
            devices: [],
            fieldDefinitions: DeploymentTrackerSeedData.fieldDefinitions,
            layout: DeploymentTrackerSeedData.workbookDefaultLayout,
            referenceValues: DeploymentTrackerSeedData.referenceValues
        )
        self.dashboardProjection = DeploymentDashboardProjection.empty
        self.loadErrorMessage = nil
        self.userFacingError = storeResolution.startupIssue
        self.actionMessage = nil
        self.exportPreview = nil
        self.preloadValidationResult = nil
        self.preloadCSVPreview = nil
        self.sdPlusPreview = nil
        self.demoSimulationResult = nil
        self.activeDemoScenario = nil
        self.activeDemoScenarioStepIndex = 0
        self.isDemoScenarioPaused = false
        self.completedDemoScenario = nil
        self.isLoading = false
        self.selectedDeviceID = nil
        self.isFieldCatalogPresented = false
        self.filterText = ""
        self.selectedWorkspace = .dashboard
        self.preloadSerialInput = ""
        self.preloadBatchInput = ""
        self.isGuidePresented = false
        self.selectedGuideTopicID = "start-here"
        self.guideSearchText = ""

        // Surface startup storage problems immediately. The view model has
        // already selected a temporary store at this point, so the UI remains
        // usable while making the persistence risk explicit.
        if let startupIssue = storeResolution.startupIssue {
            Task {
                await diagnosticsReporter.report(
                    source: "deployment-tracker",
                    category: startupIssue.diagnosticsCategory,
                    severity: .warning,
                    message: startupIssue.title,
                    metadata: startupIssue.diagnosticsMetadata
                )
            }
        }
    }

    // The Workbench inspector renders the currently selected projection row.
    // Projection rows are derived from devices plus field definitions, so this
    // getter intentionally reads from the latest projection rather than the raw
    // device array.
    var selectedRow: DeploymentWorkbenchRowProjection? {
        guard let selectedDeviceID else {
            return nil
        }
        return projection.rows.first { $0.id == selectedDeviceID }
    }

    // Current batch actions operate on the selected row when one exists. When
    // no row is selected, they operate on the filtered projection rows so users
    // can filter a set and act on that visible working set.
    var selectedDeviceIDs: [String] {
        if let selectedDeviceID {
            return [selectedDeviceID]
        }
        guard runtimeMode.isDemoMode else {
            return []
        }
        return projection.rows.map(\.id)
    }

    var demoMode: DeploymentTrackerDemoMode? {
        runtimeMode.demoMode
    }

    var isDemoMode: Bool {
        runtimeMode.isDemoMode
    }

    var activeDemoScenarioStepText: String? {
        activeDemoScenarioStep?.title
    }

    var activeDemoScenarioStep: DeploymentDemoStep? {
        guard let activeDemoScenario,
              activeDemoScenario.steps.indices.contains(activeDemoScenarioStepIndex) else {
            return nil
        }
        return activeDemoScenario.steps[activeDemoScenarioStepIndex]
    }

    // Guide search stays local and deterministic. It searches in-memory guide
    // topics and never depends on network state or another module.
    var filteredGuideTopics: [DeploymentTrackerGuideTopic] {
        DeploymentTrackerGuideContent.topics(matching: guideSearchText)
    }

    // If the currently selected topic is filtered away, the guide detail falls
    // back to the first filtered result instead of rendering an empty pane.
    var selectedGuideTopic: DeploymentTrackerGuideTopic? {
        if let selectedGuideTopicID,
           let topic = DeploymentTrackerGuideContent.topic(id: selectedGuideTopicID) {
            return topic
        }
        return filteredGuideTopics.first
    }

    // Full refresh path used when the module opens and when actions need a clean
    // copy of persistence-backed state. Every field that contributes to the
    // Workbench or Dashboard projections is loaded before refreshProjection().
    func loadWorkbench() async {
        isLoading = true
        loadErrorMessage = nil

        do {
            fieldDefinitions = try await store.fetchFieldDefinitions()
            let layouts = try await store.fetchWorkbenchLayouts()
            workbenchLayouts = layouts
            workbenchLayout = layouts.first { $0.isDefault } ?? DeploymentTrackerSeedData.workbookDefaultLayout
            workflowStatuses = try await store.fetchWorkflowStatuses(includeArchived: false)
            devices = try await store.fetchDevices(includeArchived: false)
            projects = try await store.fetchProjects(includeArchived: false)
            auditEvents = try await store.fetchAuditEvents(entityId: nil)
            workflowEvents = try await store.fetchWorkflowEvents(deviceId: nil)
            exceptions = try await store.fetchExceptions(deviceId: nil, projectId: nil, includeResolved: false)
            appleCatalogEntries = try await store.fetchAppleCatalogEntries(includeArchived: false)
            preloadSubmissions = try await store.fetchJamfPreloadSubmissions()
            sdPlusExportJobs = try await store.fetchSDPlusExportJobs()
            recordsExportJobs = try await store.fetchRecordsExportJobs()
            referenceValues = Self.combinedReferenceValues(
                referenceValues: try await store.fetchReferenceValues(categoryId: nil),
                workflowStatuses: workflowStatuses
            )
            refreshProjection()
        } catch {
            await reportActionError(error, category: "deployment-tracker.persistence.load", title: "Deployment Tracker load failed")
        }

        isLoading = false
    }

    // Opens the searchable catalog panel. Column visibility, width, order, and
    // pinning still flow through the view model so layout persistence and
    // projection refresh remain consistent.
    func showFieldCatalog() {
        isFieldCatalogPresented = true
    }

    // Opens the Tracker Guide at either the explicit topic or the default topic
    // for the originating workspace. This also records diagnostics so support
    // can see whether users were guided from an error, validation drawer, or
    // normal workspace context.
    func openGuide(topicID: String? = nil, sourceWorkspace: DeploymentTrackerWorkspace? = nil) {
        selectedGuideTopicID = topicID ?? sourceWorkspace?.guideTopicID ?? selectedWorkspace.guideTopicID
        isGuidePresented = true
        reportDiagnostic(
            category: "deployment-tracker.guide.open",
            severity: .info,
            message: "Deployment Tracker guide opened.",
            metadata: [
                "topic_id": selectedGuideTopicID ?? "unknown",
                "workspace": sourceWorkspace?.rawValue ?? selectedWorkspace.rawValue
            ]
        )
    }

    func closeGuide() {
        isGuidePresented = false
    }

    func resetDemoData() {
        guard runtimeMode.isDemoMode else {
            presentUnavailableFeature(
                title: "COMING SOON: production reset is not available",
                summary: "Reset Demo is only available in the Deployment Tracker Demo interactive preview.",
                category: "deployment-tracker.demo.reset"
            )
            return
        }

        let seed = DeploymentTrackerDemoDataFactory.makeSeed()
        let demoStore = DeploymentTrackerDemoDataFactory.makeStore(seed: seed)
        store = demoStore
        preloadService = JamfInventoryPreloadService(
            apiClient: DeploymentDemoJamfInventoryPreloadClient(records: seed.jamfPreloadRecords),
            store: demoStore,
            diagnosticsReporter: diagnosticsReporter
        )
        sdPlusService = SDPlusExportService(store: demoStore, diagnosticsReporter: diagnosticsReporter)
        recordsService = RecordsManagementExportService(store: demoStore)

        fieldDefinitions = seed.fieldDefinitions
        workbenchLayouts = seed.workbenchLayouts
        workbenchLayout = seed.workbenchLayouts.first { $0.isDefault } ?? DeploymentTrackerSeedData.workbookDefaultLayout
        workflowStatuses = seed.workflowStatuses
        devices = seed.devices
        projects = seed.projects
        auditEvents = seed.auditEvents
        workflowEvents = seed.workflowEvents
        exceptions = seed.exceptions
        appleCatalogEntries = seed.appleCatalogEntries
        preloadSubmissions = seed.jamfPreloadSubmissions
        sdPlusExportJobs = seed.sdPlusExportJobs
        recordsExportJobs = seed.recordsExportJobs
        referenceValues = Self.combinedReferenceValues(referenceValues: seed.referenceValues, workflowStatuses: seed.workflowStatuses)
        exportPreview = nil
        preloadValidationResult = nil
        preloadCSVPreview = nil
        sdPlusPreview = nil
        userFacingError = nil
        demoSimulationResult = DeploymentDemoSimulationResult(
            id: "demo-reset-\(seed.seedVersion)",
            title: "Reset Demo data",
            summary: "Deployment Tracker Demo reset to deterministic seed data. Dummy data only. No live Jamf actions.",
            simulatedSystem: "Deployment Tracker Demo",
            affectedDemoRecordCount: seed.devices.count,
            externalDataChanged: false,
            productionEquivalent: "Production reset workflows are not available from this demo.",
            nextRecommendedDemoAction: "Run Interactive Demo",
            diagnosticsCategory: "deployment-tracker.demo.reset",
            createdAt: DeploymentTrackerDemoDataFactory.baseDate
        )
        activeDemoScenario = nil
        activeDemoScenarioStepIndex = 0
        isDemoScenarioPaused = false
        completedDemoScenario = nil
        selectedWorkspace = .dashboard
        selectedDeviceID = seed.devices.first?.id
        preloadSerialInput = "DEMO-MAC-0007"
        preloadBatchInput = "DEMO-MAC-0007\nDEMO-IPAD-0021\nDEMO-IPHONE-0001"
        actionMessage = "Reset Demo data to \(seed.seedVersion). Dummy data only. No live Jamf actions."
        refreshProjection()
        reportDiagnostic(
            category: "deployment-tracker.demo.reset",
            severity: .info,
            message: "Deployment Tracker Demo seed reset.",
            metadata: [
                "seed_version": seed.seedVersion,
                "device_count": "\(seed.devices.count)",
                "external_data_changed": "false"
            ]
        )
    }

    func startDemoScenario(_ scenario: DeploymentDemoScenario) {
        activeDemoScenario = scenario
        activeDemoScenarioStepIndex = 0
        isDemoScenarioPaused = false
        completedDemoScenario = nil
        selectedWorkspace = scenario.workspace
        actionMessage = "Run Interactive Demo: \(scenario.title). Dummy data only. No live Jamf actions."
        demoSimulationResult = DeploymentDemoSimulationResult(
            id: "demo-scenario-\(scenario.id)",
            title: scenario.title,
            summary: "\(scenario.summary) Dummy data only. No live Jamf actions.",
            simulatedSystem: "Deployment Tracker Demo",
            affectedDemoRecordCount: devices.count,
            externalDataChanged: false,
            productionEquivalent: scenario.productionEquivalent,
            nextRecommendedDemoAction: scenario.steps.first?.title,
            diagnosticsCategory: "deployment-tracker.demo.scenario",
            createdAt: DeploymentTrackerDemoDataFactory.baseDate
        )
        reportDiagnostic(
            category: "deployment-tracker.demo.scenario",
            severity: .info,
            message: "Deployment Tracker Demo scenario started.",
            metadata: [
                "scenario_id": scenario.id,
                "scenario_title": scenario.title,
                "external_data_changed": "false"
            ]
        )
    }

    func startDemoScenario(id: String) {
        guard let scenario = DeploymentDemoScenarioCatalog.scenario(id: id) else {
            return
        }
        startDemoScenario(scenario)
    }

    func startDemoScenario(for workspace: DeploymentTrackerWorkspace) {
        guard let scenario = DeploymentDemoScenarioCatalog.scenario(for: workspace) else {
            return
        }
        startDemoScenario(scenario)
    }

    func advanceDemoScenarioStep() {
        guard let activeDemoScenario else {
            return
        }
        if activeDemoScenarioStepIndex >= activeDemoScenario.steps.count - 1 {
            finishDemoScenario()
        } else {
            activeDemoScenarioStepIndex += 1
        }
    }

    func rewindDemoScenarioStep() {
        activeDemoScenarioStepIndex = max(0, activeDemoScenarioStepIndex - 1)
    }

    func pauseDemoScenario() {
        guard activeDemoScenario != nil else {
            return
        }
        isDemoScenarioPaused = true
        actionMessage = "Paused the guided Demo. Dummy data only. No live Jamf actions."
    }

    func resumeDemoScenario() {
        guard activeDemoScenario != nil else {
            return
        }
        isDemoScenarioPaused = false
        actionMessage = "Resumed the guided Demo. Dummy data only. No live Jamf actions."
    }

    func finishDemoScenario() {
        guard let scenario = activeDemoScenario else {
            return
        }
        completedDemoScenario = scenario
        activeDemoScenario = nil
        activeDemoScenarioStepIndex = 0
        isDemoScenarioPaused = false
        actionMessage = "Finished guided Demo: \(scenario.title). Dummy data only. No live Jamf actions."
        demoSimulationResult = DeploymentDemoSimulationResult(
            id: "demo-scenario-complete-\(scenario.id)",
            title: "Completed \(scenario.title)",
            summary: "\(scenario.expectedResult) Dummy data only. No live Jamf actions.",
            simulatedSystem: "Deployment Tracker Demo",
            affectedDemoRecordCount: devices.count,
            externalDataChanged: false,
            productionEquivalent: scenario.productionEquivalent,
            nextRecommendedDemoAction: "Open Guide",
            diagnosticsCategory: "deployment-tracker.demo.scenario.complete",
            createdAt: DeploymentTrackerDemoDataFactory.baseDate
        )
        reportDiagnostic(
            category: "deployment-tracker.demo.scenario.complete",
            severity: .info,
            message: "Deployment Tracker Demo scenario completed.",
            metadata: [
                "scenario_id": scenario.id,
                "scenario_title": scenario.title,
                "external_data_changed": "false"
            ]
        )
    }

    func dismissCompletedDemoScenario() {
        completedDemoScenario = nil
    }

    func openActiveDemoScenarioGuide() {
        let topicID = activeDemoScenario?.relatedGuideTopicID ?? completedDemoScenario?.relatedGuideTopicID ?? selectedWorkspace.guideTopicID
        openGuide(topicID: topicID, sourceWorkspace: activeDemoScenario?.workspace ?? selectedWorkspace)
    }

    func skipDemoScenario() {
        activeDemoScenario = nil
        activeDemoScenarioStepIndex = 0
        isDemoScenarioPaused = false
        actionMessage = "Skipped the interactive Demo scenario. Dummy data only. No live Jamf actions."
    }

    func runActiveDemoScenarioAction() {
        let scenario = activeDemoScenario ?? DeploymentDemoScenarioCatalog.scenarios.first
        guard let scenario else {
            return
        }
        if activeDemoScenario == nil {
            startDemoScenario(scenario)
        }
        switch scenario.id {
        case "jamf-preload-initial":
            selectedWorkspace = .jamfPreload
            demoSimulationResult = demoIntegrationSimulator.simulateJamfPreload(recordCount: selectedDeviceIDs.count)
            validateSelectedForPreload()
        case "jamf-preload-update":
            selectedWorkspace = .jamfPreload
            preloadSerialInput = "DEMO-IPAD-0021"
            demoSimulationResult = demoIntegrationSimulator.simulateJamfPreload(recordCount: selectedDeviceIDs.count)
            lookupSinglePreloadSerial()
        case "abm-verification-simulation":
            selectedWorkspace = .abmVerification
            demoSimulationResult = demoIntegrationSimulator.simulateABMVerification(recordCount: selectedDeviceIDs.count)
            verifySelectedWithABM()
        case "sdplus-export-simulation":
            selectedWorkspace = .sdPlusExport
            demoSimulationResult = demoIntegrationSimulator.simulateSDPlusExport(recordCount: selectedDeviceIDs.count)
            previewSDPlusExport()
        case "shipping-returns-simulation":
            selectedWorkspace = .shipments
            demoSimulationResult = demoIntegrationSimulator.simulateShippingReturns(recordCount: devices.count)
        case "records-management-archive":
            selectedWorkspace = .recordsManagement
            demoSimulationResult = demoIntegrationSimulator.simulateRecordsArchive(recordCount: devices.count)
            exportRecordsPackage()
        case "intake-import-preview":
            selectedWorkspace = .intakeImports
            demoSimulationResult = demoIntegrationSimulator.simulateImportPreview(recordCount: devices.count)
            stageVendorImportPreview()
        case "exceptions-validation-recovery":
            selectedWorkspace = .inProgress
            demoSimulationResult = demoIntegrationSimulator.simulateValidationRecovery(recordCount: selectedDeviceIDs.count)
            validateSelectedForPreload()
        case "administration-field-catalog", "customize-columns-layouts":
            selectedWorkspace = scenario.workspace
            demoSimulationResult = demoIntegrationSimulator.simulateAdministrationReview(recordCount: referenceValues.count)
        default:
            selectedWorkspace = scenario.workspace
            demoSimulationResult = DeploymentDemoSimulationResult(
                id: "demo-run-\(scenario.id)",
                title: "Run Demo: \(scenario.title)",
                summary: "\(scenario.expectedResult) Dummy data only. No live Jamf actions.",
                simulatedSystem: "Deployment Tracker Demo",
                affectedDemoRecordCount: devices.count,
                externalDataChanged: false,
                productionEquivalent: scenario.productionEquivalent,
                nextRecommendedDemoAction: scenario.steps.dropFirst(activeDemoScenarioStepIndex + 1).first?.title,
                diagnosticsCategory: "deployment-tracker.demo.scenario.run",
                createdAt: DeploymentTrackerDemoDataFactory.baseDate
            )
        }
    }

    // Topic selection is separated from guide presentation so the sidebar Guide
    // workspace and the modal guide sheet can share one current topic.
    func selectGuideTopic(_ topicID: String) {
        selectedGuideTopicID = topicID
    }

    // Search changes are diagnostic-worthy because repeated searches for the
    // same wording can expose missing instructions or unclear task labels.
    // Empty searches are ignored to avoid noisy diagnostics when clearing text.
    func updateGuideSearchText(_ query: String) {
        guideSearchText = query
        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmedQuery.isEmpty == false else {
            return
        }
        reportDiagnostic(
            category: "deployment-tracker.guide.search",
            severity: .info,
            message: "Deployment Tracker guide searched.",
            metadata: [
                "query": trimmedQuery,
                "result_count": "\(filteredGuideTopics.count)"
            ]
        )
    }

    // Row selection is intentionally id-based so projections can be rebuilt
    // without keeping stale row object references in SwiftUI state.
    func selectRow(id: String) {
        selectedDeviceID = id
    }

    // Rebuilds the projection after a user changes the workbench filter. The
    // projection service owns matching semantics so this layer only stores the
    // current query string and publishes the new derived view.
    func updateFilterText(_ filterText: String) {
        self.filterText = filterText
        refreshProjection()
    }

    // Column visibility changes are layout edits, not device edits. They are
    // persisted immediately and the projection updates locally so the UI responds
    // without waiting for the store write to complete.
    func setColumnVisible(_ fieldKey: String, isVisible: Bool) {
        let service = DeploymentFieldCatalogService(definitions: fieldDefinitions)
        workbenchLayout = service.layoutWithColumnVisibility(fieldKey, isVisible: isVisible, in: workbenchLayout)
        persistWorkbenchLayout()
        refreshProjection()
    }

    // Arrow-button column movement used by the Field Catalog. Drag-and-drop uses
    // the target-field overload below; both paths go through the catalog service
    // so ordering, bounds, and hidden-column behavior remain consistent.
    func moveVisibleColumn(_ fieldKey: String, offset: Int) {
        guard let currentIndex = projection.columns.firstIndex(where: { $0.field.fieldKey == fieldKey }) else {
            return
        }

        let service = DeploymentFieldCatalogService(definitions: fieldDefinitions)
        workbenchLayout = service.layoutByMovingColumn(
            fieldKey: fieldKey,
            toVisibleIndex: currentIndex + offset,
            in: workbenchLayout
        )
        persistWorkbenchLayout()
        refreshProjection()
    }

    // Width changes are layout-only and do not touch device data. The field
    // catalog service applies the module's column width rules.
    func resizeColumn(_ fieldKey: String, by delta: Double) {
        guard let column = workbenchLayout.columns.first(where: { $0.fieldKey == fieldKey }) else {
            return
        }

        let service = DeploymentFieldCatalogService(definitions: fieldDefinitions)
        workbenchLayout = service.layoutByResizingColumn(fieldKey: fieldKey, width: column.width + delta, in: workbenchLayout)
        persistWorkbenchLayout()
        refreshProjection()
    }

    // Pinning lets key identity fields stay visually anchored while technicians
    // scroll wide deployment data sets.
    func setColumnPinned(_ fieldKey: String, isPinned: Bool) {
        let service = DeploymentFieldCatalogService(definitions: fieldDefinitions)
        workbenchLayout = service.layoutByPinningColumn(fieldKey: fieldKey, isPinned: isPinned, in: workbenchLayout)
        persistWorkbenchLayout()
        refreshProjection()
    }

    // Restores the seeded workbook-inspired layout. This does not import workbook
    // formulas or workbook automation; it only restores column layout metadata.
    func resetWorkbookDefaultLayout() {
        workbenchLayout = DeploymentTrackerSeedData.workbookDefaultLayout
        persistWorkbenchLayout()
        refreshProjection()
    }

    // Sidebar and Dashboard task-card navigation converge here. Workspace views
    // decide their own content and actions once selected.
    func selectWorkspace(_ workspace: DeploymentTrackerWorkspace) {
        selectedWorkspace = workspace
    }

    // Switches to a saved layout without writing it back. Persistence happens
    // when the user explicitly saves or changes layout properties.
    func selectLayout(id: String) {
        guard let layout = workbenchLayouts.first(where: { $0.id == id }) else {
            return
        }
        workbenchLayout = layout
        refreshProjection()
    }

    // Saves the active layout and records diagnostics so layout customizations
    // can be verified from the diagnostics center without inspecting local data.
    func saveCurrentLayout() {
        persistWorkbenchLayout()
        actionMessage = "Saved layout \(workbenchLayout.displayName)."
        reportDiagnostic(
            category: "deployment-tracker.workbench.layout-save",
            severity: .info,
            message: "Deployment Tracker workbench layout saved.",
            metadata: [
                "layout_id": workbenchLayout.id,
                "layout_name": workbenchLayout.displayName
            ]
        )
    }

    // Creates a user-owned copy of the current layout. The new id prevents a
    // personal layout save from overwriting the system workbook default.
    func savePersonalLayoutCopy() {
        var layout = workbenchLayout
        layout = WorkbenchLayout(
            id: "workbench-layout-personal-\(UUID().uuidString)",
            displayName: "Personal Layout \(workbenchLayouts.filter { $0.ownerScope == "Personal" }.count + 1)",
            ownerScope: "Personal",
            isDefault: false,
            isSystem: false,
            columns: layout.columns,
            notes: "User-saved layout."
        )
        workbenchLayout = layout
        workbenchLayouts.append(layout)
        persistWorkbenchLayout()
        actionMessage = "Saved a personal workbench layout."
    }

    // Drag-and-drop column movement. The header sends the dragged field and the
    // target field; the service converts that into a normalized visible order.
    func moveVisibleColumn(_ fieldKey: String, before targetFieldKey: String) {
        guard fieldKey != targetFieldKey,
              let targetIndex = projection.columns.firstIndex(where: { $0.field.fieldKey == targetFieldKey }) else {
            return
        }

        let service = DeploymentFieldCatalogService(definitions: fieldDefinitions)
        workbenchLayout = service.layoutByMovingColumn(fieldKey: fieldKey, toVisibleIndex: targetIndex, in: workbenchLayout)
        persistWorkbenchLayout()
        refreshProjection()
        reportDiagnostic(
            category: "deployment-tracker.workbench.column-reorder",
            severity: .info,
            message: "Deployment Tracker workbench column reordered.",
            metadata: [
                "field_key": fieldKey,
                "target_field_key": targetFieldKey
            ]
        )
    }

    // Direct width setter used by the header resize gesture. Drag gestures report
    // absolute movement from the gesture start, so the view passes a target width.
    func setColumnWidth(_ fieldKey: String, width: Double) {
        let service = DeploymentFieldCatalogService(definitions: fieldDefinitions)
        workbenchLayout = service.layoutByResizingColumn(fieldKey: fieldKey, width: width, in: workbenchLayout)
        persistWorkbenchLayout()
        refreshProjection()
    }

    // Resolves active reference options for editable reference fields. Reference
    // data remains in the tracker store so dropdown labels stay data-driven.
    func referenceOptions(for field: DeploymentFieldDefinition) -> [DeploymentReferenceValue] {
        guard let categoryId = field.referenceCategoryId else {
            return []
        }
        return referenceValues
            .filter { $0.categoryId == categoryId && $0.lifecycleState == .active }
            .sorted {
                if $0.sortOrder == $1.sortOrder {
                    return $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending
                }
                return $0.sortOrder < $1.sortOrder
            }
    }

    // Writes a local editable field and audits the change. External snapshots,
    // catalog values, and derived values are blocked before any mutation so
    // Tracker never edits upstream source-of-truth data through inline controls.
    func updateDeviceField(deviceId: String, field: DeploymentFieldDefinition, rawValue: String) {
        guard field.editable, field.sourceOfTruth == .deploymentTracker else {
            presentUserFacingIssue(DeploymentUserFacingIntegrationError(
                title: "Field is read-only",
                summary: "\(field.displayName) comes from \(field.sourceOfTruth.rawValue) and cannot be edited in Deployment Tracker.",
                technicalCause: "Attempted edit for read-only field \(field.fieldKey).",
                affectedSystem: field.sourceOfTruth.rawValue,
                requiredJamfPrivileges: [],
                localDataChanged: false,
                externalDataChanged: false,
                safeToRetry: false,
                recommendedAction: "Edit the upstream system if this value is incorrect, then refresh the Deployment Tracker snapshot.",
                diagnosticsCategory: "deployment-tracker.workbench.readonly",
                relatedGuideTopicId: "workbench"
            ))
            return
        }

        if field.fieldKey == "device.workflowStatusId" {
            transitionDeviceStatus(deviceId: deviceId, to: rawValue)
            return
        }

        Task {
            do {
                guard var device = devices.first(where: { $0.id == deviceId }) else {
                    throw DeploymentTrackerStoreError.missingRecord(id: deviceId)
                }
                let oldValue = projectionService.displayValue(
                    for: field.fieldKey,
                    device: device,
                    referenceValuesById: Dictionary(uniqueKeysWithValues: referenceValues.map { ($0.id, $0.displayName) })
                )
                apply(rawValue: rawValue, to: &device, fieldKey: field.fieldKey)
                let saved = try await store.saveDevice(device)
                try await store.appendAuditEvent(
                    DeploymentAuditEvent(
                        eventType: "workbench.inline-edit",
                        entityType: "DeploymentDevice",
                        entityId: deviceId,
                        fieldKey: field.fieldKey,
                        oldValue: oldValue,
                        newValue: rawValue,
                        actor: nil,
                        metadata: ["source": "In-Progress Workbench"]
                    )
                )
                if let index = devices.firstIndex(where: { $0.id == saved.id }) {
                    devices[index] = saved
                }
                auditEvents = try await store.fetchAuditEvents(entityId: nil)
                refreshProjection()
                actionMessage = "Saved \(field.displayName)."
            } catch {
                await reportActionError(error, category: "deployment-tracker.workbench.edit", title: "Workbench edit failed")
            }
        }
    }

    // Workflow status edits run through the workflow engine so transition gates,
    // allowed paths, and issue reporting are applied consistently.
    func transitionDeviceStatus(deviceId: String, to statusId: String) {
        Task {
            do {
                let result = try await DeploymentWorkflowEngine(store: store).transitionDevice(deviceId: deviceId, to: statusId)
                workflowEvents = try await store.fetchWorkflowEvents(deviceId: nil)
                auditEvents = try await store.fetchAuditEvents(entityId: nil)
                devices = try await store.fetchDevices(includeArchived: false)
                refreshProjection()

                if result.allowed {
                    actionMessage = "Workflow status updated."
                } else {
                    presentUserFacingIssue(DeploymentUserFacingIntegrationError(
                        title: "Workflow transition blocked",
                        summary: result.issues.map(\.message).joined(separator: " "),
                        technicalCause: "WorkflowEngine rejected transition to \(statusId).",
                        affectedSystem: "Deployment Tracker",
                        requiredJamfPrivileges: [],
                        localDataChanged: false,
                        externalDataChanged: false,
                        safeToRetry: true,
                        recommendedAction: "Resolve the listed gate issues or choose an allowed status transition.",
                        diagnosticsCategory: "deployment-tracker.workflow",
                        relatedGuideTopicId: "exceptions-validation"
                    ))
                }
            } catch {
                await reportActionError(error, category: "deployment-tracker.workflow", title: "Workflow transition failed")
            }
        }
    }

    // Manual creation intentionally captures only the minimum safe identity data:
    // normalized serial, optional asset tag, and the default workflow status.
    // Additional enrichment happens through imports, catalog review, or edits.
    func createDevice(serialNumber: String, assetTag: String? = nil) {
        let trimmedSerial = serialNumber.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedSerial.isEmpty else { return }
        Task {
            do {
                var device = DeploymentDevice(serialNumber: trimmedSerial)
                if let assetTag, !assetTag.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    device.assetTag = assetTag
                }
                if let defaultStatus = workflowStatuses.first(where: \.isDefault) {
                    device = device.withWorkflowStatus(defaultStatus.id)
                }
                let saved = try await store.saveDevice(device)
                try await store.appendAuditEvent(
                    DeploymentAuditEvent(
                        eventType: "device.create",
                        entityType: "DeploymentDevice",
                        entityId: saved.id,
                        fieldKey: "device.serialNumber",
                        oldValue: nil,
                        newValue: saved.serialNumber
                    )
                )
                await loadWorkbench()
                selectedDeviceID = saved.id
            } catch {
                await reportActionError(error, category: "deployment-tracker.devices", title: "Device create failed")
            }
        }
    }

    func archiveDevice(id: String) {
        // Archive is the normal removal path for devices. It preserves history
        // for reporting and records management, then reloads the module state so
        // lists, Workbench projections, and Dashboard totals all agree.
        Task {
            do {
                _ = try await store.archiveDevice(id: id, actor: nil)
                await loadWorkbench()
            } catch {
                await reportActionError(error, category: "deployment-tracker.devices", title: "Device archive failed")
            }
        }
    }

    // Project creation mirrors device creation: accept a small amount of safe
    // user input, persist a Tracker-owned record, audit the creation, then reload
    // projections so Dashboard and Workbench state stay in sync.
    func createProject(name: String, code: String? = nil) {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else { return }
        Task {
            do {
                let project = DeploymentProject(
                    projectName: trimmedName,
                    projectCode: code?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
                )
                let saved = try await store.saveProject(project)
                try await store.appendAuditEvent(
                    DeploymentAuditEvent(
                        eventType: "project.create",
                        entityType: "DeploymentProject",
                        entityId: saved.id,
                        fieldKey: "project.projectName",
                        oldValue: nil,
                        newValue: saved.projectName
                    )
                )
                await loadWorkbench()
            } catch {
                await reportActionError(error, category: "deployment-tracker.projects", title: "Project create failed")
            }
        }
    }

    func archiveProject(id: String) {
        // Projects follow the same archive-first policy as devices. This keeps
        // deployment history available even when the project should no longer
        // appear as an active operational target.
        Task {
            do {
                _ = try await store.archiveProject(id: id, actor: nil)
                await loadWorkbench()
            } catch {
                await reportActionError(error, category: "deployment-tracker.projects", title: "Project archive failed")
            }
        }
    }

    // Jamf Inventory Preload validation is local and safe to run repeatedly. It
    // prepares both the validation result and CSV preview, but it does not mutate
    // Jamf Pro. Any blockers are converted into structured, guide-linked errors.
    func validateSelectedForPreload() {
        Task {
            do {
                let validationResult = try await preloadService.validateSelectedDevices(deviceIds: selectedDeviceIDs)
                preloadValidationResult = validationResult
                preloadCSVPreview = try await preloadService.renderCSVForSelectedDevices(deviceIds: selectedDeviceIDs)
                if validationResult.isReadyForUpload {
                    actionMessage = runtimeMode.isDemoMode
                        ? "Preview Demo validation complete for \(selectedDeviceIDs.count) device(s). Dummy data only. No live Jamf actions."
                        : "Validated \(selectedDeviceIDs.count) device(s) for Jamf Inventory Preload."
                    if runtimeMode.isDemoMode {
                        demoSimulationResult = DeploymentDemoSimulationResult.jamfPreload(
                            id: "demo-validation",
                            title: "Preview Demo Jamf Preload Validation",
                            summary: "Validated deterministic Demo rows and generated a preview CSV.",
                            affectedDemoRecordCount: selectedDeviceIDs.count,
                            productionEquivalent: "Production validation would inspect selected deployment rows before any approved Jamf Inventory Preload action.",
                            nextRecommendedDemoAction: "Simulate Jamf Preload Submission"
                        )
                    }
                } else {
                    presentUserFacingIssue(DeploymentUserFacingIntegrationError(
                        title: runtimeMode.isDemoMode ? "Demo Jamf Preload validation found issues" : "Jamf Preload validation found issues",
                        summary: preloadValidationSummary(validationResult),
                        technicalCause: "Local validation blocked or warned before Jamf Inventory Preload upload.",
                        affectedSystem: "Deployment Tracker",
                        requiredJamfPrivileges: validationResult.requiredPrivileges,
                        localDataChanged: false,
                        externalDataChanged: false,
                        safeToRetry: true,
                        recommendedAction: runtimeMode.isDemoMode
                            ? "Fix the listed Demo values or choose another Demo scenario. No live Jamf actions were run."
                            : "Fix the listed field values or exceptions, then validate again before sending data to Jamf Pro.",
                        diagnosticsCategory: "deployment-tracker.validation.blocked-action",
                        relatedGuideTopicId: "exceptions-validation"
                    ))
                }
            } catch {
                await reportActionError(error, category: "deployment-tracker.validation.blocked-action", title: "Jamf Preload validation failed")
            }
        }
    }

    // Sends selected device data through the shared Jamf API gateway. Permission
    // failures get a specialized structured error that lists required Jamf API
    // role privileges and links the operator to the permission guide topic.
    func sendSelectedInventoryPreload() {
        Task {
            do {
                let submission = try await preloadService.uploadSelectedDevices(deviceIds: selectedDeviceIDs)
                preloadSubmissions = try await store.fetchJamfPreloadSubmissions()
                devices = try await store.fetchDevices(includeArchived: false)
                refreshProjection()
                if runtimeMode.isDemoMode {
                    demoSimulationResult = DeploymentDemoSimulationResult.jamfPreload(
                        id: "demo-preload-submission-\(submission.id)",
                        title: "Simulated Demo Jamf Preload Submission",
                        summary: "Rendered Demo CSV and recorded a simulated submission for \(submission.deviceIds.count) Demo device(s).",
                        affectedDemoRecordCount: submission.deviceIds.count,
                        productionEquivalent: "Production would require approved Jamf Inventory Preload privileges and an explicit non-demo mode.",
                        nextRecommendedDemoAction: "Simulate Reconciliation"
                    )
                    actionMessage = "Simulated Demo Jamf Inventory Preload for \(submission.deviceIds.count) device(s). No live Jamf actions."
                } else {
                    actionMessage = "Submitted Jamf Inventory Preload for \(submission.deviceIds.count) device(s)."
                }
            } catch {
                if let frameworkError = error as? JamfFrameworkError, frameworkError.matches(status: 403) {
                    presentUserFacingIssue(preloadService.makePermissionError(
                        technicalCause: error.localizedDescription,
                        diagnosticsCorrelationId: UUID().uuidString
                    ), severity: .error)
                } else {
                    await reportActionError(error, category: "deployment-tracker.jamf-preload.submission", title: "Jamf Preload submission failed")
                }
            }
        }
    }

    // Update batches currently share validation and preview preparation with the
    // initial preload path. The user-facing message clarifies that review still
    // happens before sending anything to Jamf.
    func createPreloadUpdateBatch() {
        validateSelectedForPreload()
        actionMessage = runtimeMode.isDemoMode
            ? "Preview Demo preload update batch created. Dummy data only. No live Jamf actions."
            : "Created an update batch preview. Review validation before sending to Jamf."
    }

    // Reconciliation captures Jamf's current preload state back into Tracker
    // snapshots and then refreshes device projections so technicians can see
    // whether Jamf agrees with the local workflow record.
    func reconcileSelectedPreload() {
        Task {
            do {
                let snapshots = try await preloadService.reconcileSelectedDevices(deviceIds: selectedDeviceIDs)
                devices = try await store.fetchDevices(includeArchived: false)
                refreshProjection()
                if runtimeMode.isDemoMode {
                    demoSimulationResult = DeploymentDemoSimulationResult.jamfPreload(
                        id: "demo-preload-reconcile",
                        title: "Simulated Demo Jamf Preload Reconciliation",
                        summary: "Created \(snapshots.count) Demo preload snapshot(s) from deterministic local data.",
                        affectedDemoRecordCount: snapshots.count,
                        productionEquivalent: "Production reconciliation would compare approved Jamf reads with local deployment records.",
                        nextRecommendedDemoAction: "Generate Demo SD+ Export Preview"
                    )
                    actionMessage = "Simulated reconciliation for \(snapshots.count) Demo Jamf Inventory Preload snapshot(s). No live Jamf actions."
                } else {
                    actionMessage = "Reconciled \(snapshots.count) Jamf Inventory Preload snapshot(s)."
                }
            } catch {
                await reportActionError(error, category: "deployment-tracker.jamf-preload.reconciliation", title: "Jamf Preload reconciliation failed")
            }
        }
    }

    // Failed-only retry protects successful rows from unnecessary resubmission.
    // The service decides which device ids are safe to retry from submission
    // history, and this view model refreshes the submission table afterward.
    func retryFailedPreloadSubmission(id: String) {
        Task {
            do {
                guard let submission = preloadSubmissions.first(where: { $0.id == id }) else {
                    throw DeploymentTrackerStoreError.missingRecord(id: id)
                }
                let retryIds = preloadService.failedOnlyRetryDeviceIds(from: submission)
                _ = try await preloadService.uploadSelectedDevices(deviceIds: retryIds)
                preloadSubmissions = try await store.fetchJamfPreloadSubmissions()
                actionMessage = runtimeMode.isDemoMode
                    ? "Simulated retry for \(retryIds.count) Demo Jamf Preload device(s). No live Jamf actions."
                    : "Retried \(retryIds.count) failed Jamf Preload device(s)."
            } catch {
                await reportActionError(error, category: "deployment-tracker.jamf-preload.retry", title: "Jamf Preload retry failed")
            }
        }
    }

    // The lookup helpers sanitize single or pasted serial input, then delegate
    // to lookupPreloadSerials(_:forceRefresh:) so cache behavior and permission
    // handling stay in one private path.
    func lookupSinglePreloadSerial() {
        let serial = preloadSerialInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !serial.isEmpty else { return }
        lookupPreloadSerials([serial])
    }

    func refreshSinglePreloadSerial() {
        let serial = preloadSerialInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !serial.isEmpty else { return }
        lookupPreloadSerials([serial], forceRefresh: true)
    }

    func lookupBatchPreloadSerials() {
        let serials = preloadBatchInput
            .split(whereSeparator: \.isNewline)
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        lookupPreloadSerials(serials)
    }

    func refreshBatchPreloadSerials() {
        let serials = preloadBatchInput
            .split(whereSeparator: \.isNewline)
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        lookupPreloadSerials(serials, forceRefresh: true)
    }

    // This intentionally does not test credentials by making a Jamf write. It
    // explains the role requirements in a structured, guide-linked message so
    // operators can correct API role setup before retrying.
    func showPreloadPermissionDiagnostics() {
        presentUserFacingIssue(DeploymentUserFacingIntegrationError(
            title: "Jamf Inventory Preload required privileges",
            summary: runtimeMode.isDemoMode
                ? "Deployment Tracker Demo shows the future Jamf role requirements without contacting Jamf. Dummy data only. No live Jamf actions."
                : "The saved Jamf API role must include lookup and upload privileges before this workflow can run.",
            technicalCause: "Operator requested Inventory Preload permission diagnostics.",
            requiredJamfPrivileges: JamfInventoryPreloadPrivilege.lookup + JamfInventoryPreloadPrivilege.upload,
            localDataChanged: false,
            externalDataChanged: false,
            safeToRetry: true,
            recommendedAction: "Add the listed privileges to the Jamf API role, refresh the token, then retry lookup or upload.",
            diagnosticsCategory: "deployment-tracker.jamf-preload.permission",
            relatedGuideTopicId: "jamf-permissions"
        ))
    }

    func verifySelectedWithABM() {
        // The selected-device ABM action is intentionally local until a
        // read-only ABM provider is connected. It creates reviewable local
        // exceptions instead of attempting any Apple Business mutation.
        createLocalABMExceptionSummary(for: selectedDeviceIDs)
    }

    // Batch ABM verification uses the same read-only local exception path as
    // selected verification. It never attempts to mutate Apple Business records.
    func verifyBatchWithABM() {
        createLocalABMExceptionSummary(for: devices.map(\.id))
    }

    // SD+ preview renders the current selection into CSV without creating an
    // export job. Technicians can inspect the generated values before recording
    // an export or sharing a file outside the app.
    func previewSDPlusExport() {
        let selected = devices.filter { selectedDeviceIDs.contains($0.id) }
        let rendered = SDPlusCSVRenderer(fieldDefinitions: fieldDefinitions, referenceValues: referenceValues)
            .render(devices: selected, template: DeploymentTrackerSeedData.sdPlusAssetImportTemplate)
        sdPlusPreview = rendered.csv
        if runtimeMode.isDemoMode {
            demoSimulationResult = DeploymentDemoSimulationResult(
                id: "demo-sdplus-preview",
                title: "Preview Demo SD+ Export",
                summary: "Generated a Demo ServiceDesk Plus CSV preview. Dummy data only. No SD+ data changed.",
                simulatedSystem: "ServiceDesk Plus",
                affectedDemoRecordCount: rendered.includedDeviceIds.count,
                externalDataChanged: false,
                productionEquivalent: "Production would produce a reviewed CSV for ServiceDesk Plus import.",
                nextRecommendedDemoAction: "Generate Demo SD+ Export Preview",
                diagnosticsCategory: "deployment-tracker.demo.sdplus",
                createdAt: DeploymentTrackerDemoDataFactory.baseDate
            )
            actionMessage = "Prepared Demo SD+ export preview for \(rendered.includedDeviceIds.count) device(s). No SD+ data changed."
        } else {
            actionMessage = "Prepared SD+ preview for \(rendered.includedDeviceIds.count) device(s)."
        }
    }

    // Generates an SD+ export job through the export service. Validation failures
    // are shown as structured errors and explicitly state that no external SD+
    // system data was changed by the local renderer.
    func generateSDPlusExport() {
        Task {
            do {
                let selected = devices.filter { selectedDeviceIDs.contains($0.id) }
                let result = try await sdPlusService.export(
                    devices: selected,
                    template: DeploymentTrackerSeedData.sdPlusAssetImportTemplate,
                    fieldDefinitions: fieldDefinitions,
                    referenceValues: referenceValues,
                    projectId: nil,
                    exportedBy: nil
                )
                sdPlusPreview = result.renderedExport.csv
                sdPlusExportJobs = try await store.fetchSDPlusExportJobs()
                devices = try await store.fetchDevices(includeArchived: false)
                refreshProjection()
                if result.renderedExport.validation.isValid {
                    if runtimeMode.isDemoMode {
                        demoSimulationResult = DeploymentDemoSimulationResult(
                            id: "demo-sdplus-export-\(result.job.id)",
                            title: "Generated Demo SD+ Export Preview",
                            summary: "Recorded a Demo ServiceDesk Plus export job. Dummy data only. No SD+ data changed.",
                            simulatedSystem: "ServiceDesk Plus",
                            affectedDemoRecordCount: result.renderedExport.includedDeviceIds.count,
                            externalDataChanged: false,
                            productionEquivalent: "Production would generate a controlled ServiceDesk Plus CSV for external import.",
                            nextRecommendedDemoAction: "Review Demo shipments",
                            diagnosticsCategory: "deployment-tracker.demo.sdplus",
                            createdAt: DeploymentTrackerDemoDataFactory.baseDate
                        )
                        actionMessage = "Generated Demo SD+ export preview \(result.job.fileName). No SD+ data changed."
                    } else {
                        actionMessage = "Generated SD+ export \(result.job.fileName)."
                    }
                } else {
                    presentUserFacingIssue(DeploymentUserFacingIntegrationError(
                        title: "SD+ export validation blocked the file",
                        summary: sdPlusValidationSummary(result.renderedExport.validation),
                        technicalCause: "SD+ renderer found blocking validation issues and marked export job \(result.job.id) as failed.",
                        affectedSystem: "ServiceDesk Plus",
                        requiredJamfPrivileges: [],
                        localDataChanged: true,
                        externalDataChanged: false,
                        safeToRetry: true,
                        recommendedAction: "Correct the listed device fields and regenerate the SD+ export. No SD+ system data was changed.",
                        diagnosticsCategory: "deployment-tracker.sdplus.export",
                        relatedGuideTopicId: "sdplus-export"
                    ))
                }
            } catch {
                await reportActionError(error, category: "deployment-tracker.sdplus.export", title: "SD+ export failed")
            }
        }
    }

    // Imports the embedded Apple hardware catalog used for local hardware
    // enrichment. This data improves local Tracker records but does not overwrite
    // ABM or Jamf snapshots.
    func importSampleAppleCatalogEntries() {
        Task {
            do {
                let service = DeploymentAppleCatalogService()
                let entries = service.embeddedCatalogEntries(importedAt: Date())
                guard entries.isEmpty == false else {
                    presentUserFacingIssue(DeploymentUserFacingIntegrationError(
                        title: "Apple Catalog import is empty",
                        summary: "Deployment Tracker could not find any embedded Apple hardware catalog entries to import.",
                        technicalCause: "The Deployment Tracker embedded model identifier catalog returned zero entries.",
                        affectedSystem: "Deployment Tracker",
                        requiredJamfPrivileges: [],
                        localDataChanged: false,
                        externalDataChanged: false,
                        safeToRetry: false,
                        recommendedAction: "Verify that the Deployment Tracker module package includes DeploymentAppleDeviceModelCatalog.swift, then rebuild the module.",
                        diagnosticsCategory: "deployment-tracker.apple-catalog.import",
                        relatedGuideTopicId: "apple-catalog"
                    ))
                    return
                }

                for entry in entries {
                    _ = try await store.saveAppleCatalogEntry(entry)
                }
                appleCatalogEntries = try await store.fetchAppleCatalogEntries(includeArchived: false)
                actionMessage = "Imported \(entries.count) embedded Apple Catalog entries for local hardware lookup."
                await diagnosticsReporter.report(
                    source: "deployment-tracker",
                    category: "deployment-tracker.apple-catalog.import",
                    severity: .info,
                    message: "Imported embedded Apple Catalog entries.",
                    metadata: [
                        "entry_count": "\(entries.count)",
                        "source": "embedded-model-identifier"
                    ]
                )
            } catch {
                await reportActionError(error, category: "deployment-tracker.apple-catalog.import", title: "Apple Catalog import failed")
            }
        }
    }

    // Reviews unresolved devices against imported catalog data and locally saved
    // Jamf snapshots. Enrichment is written only to Tracker records, while
    // unresolved or ambiguous matches are surfaced for operator review.
    func reviewUnresolvedCatalogDevices() {
        Task {
            do {
                let service = DeploymentAppleCatalogService()
                let jamfSnapshotsByDeviceId = try await latestJamfInventorySnapshotByDeviceId()
                var enrichedCount = 0
                var unresolvedCount = 0
                var ambiguousCount = 0

                for device in devices {
                    let jamfSnapshot = jamfSnapshotsByDeviceId[device.id]
                    let resolution = service.resolve(
                        device: device,
                        entries: appleCatalogEntries,
                        jamfSnapshot: jamfSnapshot
                    )
                    switch resolution.matchState {
                    case .noMatch, .conflict:
                        unresolvedCount += 1
                    case .ambiguous:
                        ambiguousCount += 1
                    case .exact, .highConfidence, .partial:
                        break
                    }

                    let enriched = service.enrichLocalDevice(device, with: resolution, jamfSnapshot: jamfSnapshot)
                    if enriched != device {
                        _ = try await store.saveDevice(enriched)
                        enrichedCount += 1
                    }
                }

                devices = try await store.fetchDevices(includeArchived: false)
                refreshProjection()

                let reviewedCount = devices.count
                if unresolvedCount > 0 || ambiguousCount > 0 {
                    presentUserFacingIssue(DeploymentUserFacingIntegrationError(
                        title: "Apple Catalog review found unresolved hardware",
                        summary: "\(unresolvedCount) device(s) could not be matched and \(ambiguousCount) device(s) had ambiguous Apple Catalog matches. \(enrichedCount) device(s) were enriched locally from model identifiers or imported catalog entries.",
                        technicalCause: "Deployment Tracker only enriches hardware when a device has a recognized Apple model identifier, Apple part number, vendor SKU, order part number, or a high-confidence imported catalog match.",
                        affectedSystem: "Deployment Tracker",
                        requiredJamfPrivileges: [],
                        localDataChanged: enrichedCount > 0,
                        externalDataChanged: false,
                        safeToRetry: true,
                        recommendedAction: "Import vendor, ABM, or Jamf inventory records that include model identifiers or Apple part numbers, then run Apple Catalog review again.",
                        diagnosticsCategory: "deployment-tracker.apple-catalog.review",
                        relatedGuideTopicId: "apple-catalog"
                    ))
                } else {
                    actionMessage = "Reviewed \(reviewedCount) device(s). \(enrichedCount) device(s) were enriched from the embedded Apple Catalog."
                    await diagnosticsReporter.report(
                        source: "deployment-tracker",
                        category: "deployment-tracker.apple-catalog.review",
                        severity: .info,
                        message: "Apple Catalog review completed.",
                        metadata: [
                            "reviewed_count": "\(reviewedCount)",
                            "enriched_count": "\(enrichedCount)",
                            "unresolved_count": "\(unresolvedCount)",
                            "ambiguous_count": "\(ambiguousCount)"
                        ]
                    )
                }
            } catch {
                await reportActionError(error, category: "deployment-tracker.apple-catalog.review", title: "Apple Catalog review failed")
            }
        }
    }

    // Keeps the newest Jamf inventory snapshot for each local device. This
    // reduces downstream catalog review to one snapshot per device and avoids
    // stale data winning over a newer capture.
    private func latestJamfInventorySnapshotByDeviceId() async throws -> [String: JamfInventoryDeviceSnapshot] {
        let snapshots = try await store.fetchJamfInventorySnapshots()
        return snapshots.reduce(into: [String: JamfInventoryDeviceSnapshot]()) { partial, snapshot in
            if let current = partial[snapshot.deploymentDeviceId], current.capturedAt >= snapshot.capturedAt {
                return
            }
            partial[snapshot.deploymentDeviceId] = snapshot
        }
    }

    // Creates the records package used by archive-first governance. This is a
    // local export operation and does not hard-delete Tracker data.
    func exportRecordsPackage() {
        Task {
            do {
                let package = try await recordsService.makeExportPackage(createdBy: nil)
                recordsExportJobs = try await store.fetchRecordsExportJobs()
                if runtimeMode.isDemoMode {
                    demoSimulationResult = DeploymentDemoSimulationResult(
                        id: "demo-records-export-\(package.job.id)",
                        title: "Generated Demo Records Package",
                        summary: "Created a Demo records export package from deterministic data. Dummy data only. No production records changed.",
                        simulatedSystem: "Deployment Tracker Records",
                        affectedDemoRecordCount: package.job.includedRecordCount,
                        externalDataChanged: false,
                        productionEquivalent: "Production records export would be reviewed before any controlled deletion workflow.",
                        nextRecommendedDemoAction: "Reset Demo",
                        diagnosticsCategory: "deployment-tracker.demo.records",
                        createdAt: DeploymentTrackerDemoDataFactory.baseDate
                    )
                    actionMessage = "Generated Demo records package \(package.packageName). Dummy data only."
                } else {
                    actionMessage = "Created records package \(package.packageName)."
                }
            } catch {
                await reportActionError(error, category: "deployment-tracker.records.export", title: "Records export failed")
            }
        }
    }

    // Hard-delete review is intentionally gated behind a planned workflow. Until
    // dependency impact review and export-before-delete checks exist, the module
    // presents an unavailable feature message instead of pretending to delete.
    func reviewDeletionImpact() {
        presentUnavailableFeature(
            title: "Deletion review is not ready to run",
            summary: "This functionality has not been added yet. Deployment Tracker will require archived or pending-deletion records and a completed export-before-delete check before deletion review can run.",
            category: "deployment-tracker.records.deletion-review"
        )
    }

    // Vendor imports are preview-first. The placeholder preserves the intended
    // safe workflow without committing partial import behavior before duplicate
    // handling and reference validation are complete.
    func stageVendorImportPreview() {
        presentUnavailableFeature(
            title: "Vendor import commit is not ready to run",
            summary: "This functionality has not been added yet. The intended workflow will stage a vendor import preview, identify duplicate serial numbers and unknown references, then require operator review before saving.",
            category: "deployment-tracker.imports.vendor"
        )
    }

    // Workbook migration is explicitly preview-only here. The old workbook's
    // formulas and macro-like behaviors are not imported into Tracker.
    func stageWorkbookMigrationPreview() {
        presentUnavailableFeature(
            title: "Workbook migration commit is not ready to run",
            summary: "This functionality has not been added yet. The intended workflow will stage a workbook migration preview and will not import formulas, Run Sync behavior, or Run Clear behavior.",
            category: "deployment-tracker.imports.workbook"
        )
    }

    // Shared Jamf Inventory Preload lookup path. Cache behavior, force refresh,
    // permission handling, and user-facing messages live here so single-serial
    // and batch controls behave the same way.
    private func lookupPreloadSerials(_ serials: [String], forceRefresh: Bool = false) {
        guard !serials.isEmpty else { return }
        Task {
            do {
                let result = try await preloadService.lookupRecordResult(
                    serialNumbers: serials,
                    forceRefresh: forceRefresh
                )
                let cacheSummary = result.forceRefresh
                    ? (runtimeMode.isDemoMode ? "Forced a fresh Demo simulation lookup." : "Forced a fresh Jamf lookup.")
                    : "Used \(result.cachedRecordCount) cached record(s) and \(result.cachedMissCount) cached miss(es)."
                if runtimeMode.isDemoMode {
                    demoSimulationResult = DeploymentDemoSimulationResult.jamfPreload(
                        id: "demo-preload-lookup",
                        title: "Simulated Demo Jamf Preload Lookup",
                        summary: "Found \(result.matchedRecordCount) deterministic Demo preload record(s) for \(result.requestedSerialCount) serial(s).",
                        affectedDemoRecordCount: result.matchedRecordCount,
                        productionEquivalent: "Production lookup would read Jamf Inventory Preload records with approved permissions.",
                        nextRecommendedDemoAction: "Preview Demo Preload Update Batch"
                    )
                    actionMessage = "Simulated Demo Jamf Inventory Preload lookup for \(result.requestedSerialCount) serial(s). \(cacheSummary) Demo batches: \(result.jamfRequestBatchCount). No live Jamf actions."
                } else {
                    actionMessage = "Found \(result.matchedRecordCount) Jamf Inventory Preload record(s) for \(result.requestedSerialCount) serial(s). \(cacheSummary) Jamf API batches: \(result.jamfRequestBatchCount)."
                }
            } catch {
                if let frameworkError = error as? JamfFrameworkError, frameworkError.matches(status: 403) {
                    presentUserFacingIssue(DeploymentUserFacingIntegrationError(
                        title: "Jamf Inventory Preload lookup permission failure",
                        summary: "Jamf Pro rejected the lookup because the API role is missing Read Inventory Preload Records.",
                        technicalCause: error.localizedDescription,
                        requiredJamfPrivileges: JamfInventoryPreloadPrivilege.lookup,
                        localDataChanged: false,
                        externalDataChanged: false,
                        safeToRetry: true,
                        recommendedAction: "Add Read Inventory Preload Records to the Jamf API role, refresh the token, and retry lookup.",
                        diagnosticsCategory: "deployment-tracker.jamf-preload.permission",
                        relatedGuideTopicId: "jamf-permissions"
                    ), severity: .error)
                } else {
                    await reportActionError(error, category: "deployment-tracker.jamf-preload.lookup", title: "Jamf Preload lookup failed")
                }
            }
        }
    }

    // ABM verification remains read-only in this module. Until an external ABM
    // read provider is wired in, the action queues local exception records for
    // rows that still require verification.
    private func createLocalABMExceptionSummary(for deviceIds: [String]) {
        Task {
            do {
                for device in devices where deviceIds.contains(device.id) && device.abmVerificationState != .assignedToExpectedMDM {
                    try await store.appendException(
                        DeploymentException(
                            deviceId: device.id,
                            projectId: device.projectId,
                            reasonCode: "abm.readonly.verificationRequired",
                            summary: "ABM verification requires a read-only provider result for serial \(device.serialNumber).",
                            severity: .warning
                        )
                    )
                }
                exceptions = try await store.fetchExceptions(deviceId: nil, projectId: nil, includeResolved: false)
                actionMessage = runtimeMode.isDemoMode
                    ? "Run Demo ABM Verification queued local Demo exception review for \(deviceIds.count) device(s). No ABM data changed."
                    : "ABM read-only verification queued local exception review for \(deviceIds.count) device(s)."
            } catch {
                await reportActionError(error, category: "deployment-tracker.abm-verification", title: "ABM verification failed")
            }
        }
    }

    // Maps Workbench editor values back onto mutable fields on DeploymentDevice.
    // This switch is deliberately explicit so unsupported field keys cannot
    // silently write into the wrong model property.
    private func apply(rawValue: String, to device: inout DeploymentDevice, fieldKey: String) {
        let value = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        switch fieldKey {
        case "device.serialNumber":
            device.updateSerialNumber(value)
        case "device.assetTag":
            device.assetTag = value.nilIfEmpty
        case "device.projectId":
            device.projectId = value.nilIfEmpty
        case "device.deviceTypeId":
            device.deviceTypeId = value.nilIfEmpty
        case "device.model":
            device.model = value.nilIfEmpty
        case "device.profileId":
            device.profileId = value.nilIfEmpty
        case "device.assignedUser":
            device.assignedUser = value.nilIfEmpty
        case "device.poNumber":
            device.poNumber = value.nilIfEmpty
        case "device.orderNumber":
            device.orderNumber = value.nilIfEmpty
        case "device.ticketNumber":
            device.ticketNumber = value.nilIfEmpty
        case "device.replacingSerialNumber":
            device.replacementForSerialNumber = value.nilIfEmpty
        case "device.fedExTrackingNumber":
            device.fedExTrackingNumber = value.nilIfEmpty
        case "device.returnTrackingNumber":
            device.returnTrackingNumber = value.nilIfEmpty
        case "device.deliveryConfirmation":
            device.deliveryConfirmation = value.nilIfEmpty
        case "device.gmEmailed":
            device.gmEmailed = ["true", "yes", "1"].contains(value.lowercased())
        case "device.comments":
            device.comments = rawValue.nilIfEmpty
        case "device.notes":
            device.notes = rawValue.nilIfEmpty
        default:
            break
        }
    }

    // Converts thrown errors into both diagnostics and a structured operator
    // message. The related guide topic is derived from the diagnostics category
    // so the user can jump directly to recovery steps.
    private func reportActionError(_ error: Error, category: String, title: String) async {
        let correlationId = UUID().uuidString
        await diagnosticsReporter.reportError(
            source: "deployment-tracker",
            category: category,
            message: title,
            errorDescription: error.localizedDescription,
            metadata: demoDiagnosticMetadata([
                "diagnostics_correlation_id": correlationId,
                "local_data_changed": "false",
                "external_data_changed": "false"
            ])
        )
        userFacingError = DeploymentUserFacingIntegrationError(
            title: title,
            summary: error.localizedDescription,
            technicalCause: String(describing: error),
            affectedSystem: "Deployment Tracker",
            requiredJamfPrivileges: [],
            localDataChanged: false,
            externalDataChanged: false,
            safeToRetry: true,
            recommendedAction: "Review the details, correct the input or permissions, and retry the action.",
            diagnosticsCategory: category,
            diagnosticsCorrelationId: correlationId,
            relatedGuideTopicId: guideTopicID(forDiagnosticsCategory: category)
        )
    }

    // Planned workflows use the same structured error surface as real failures.
    // This avoids fake functionality while still documenting the intended safe
    // workflow and current limitation.
    private func presentUnavailableFeature(title: String, summary: String, category: String) {
        presentUserFacingIssue(DeploymentUserFacingIntegrationError(
            title: title,
            summary: summary,
            technicalCause: "The operator selected a planned Deployment Tracker workflow whose final implementation is not available in this build.",
            affectedSystem: "Deployment Tracker",
            requiredJamfPrivileges: [],
            localDataChanged: false,
            externalDataChanged: false,
            safeToRetry: false,
            recommendedAction: "Use the currently available preview/export controls, or wait for this workflow to be implemented before relying on it operationally.",
            diagnosticsCategory: category,
            relatedGuideTopicId: guideTopicID(forDiagnosticsCategory: category)
        ))
    }

    // Central point for displaying user-facing issues and writing diagnostics.
    // Every structured error should pass through this method so the UI, action
    // banner, and diagnostic stream stay consistent.
    private func presentUserFacingIssue(
        _ issue: DeploymentUserFacingIntegrationError,
        severity: DiagnosticSeverity = .warning
    ) {
        userFacingError = issue
        actionMessage = nil
        Task {
            await diagnosticsReporter.report(
                source: "deployment-tracker",
                category: issue.diagnosticsCategory,
                severity: severity,
                message: issue.title,
                metadata: demoDiagnosticMetadata(issue.diagnosticsMetadata)
            )
        }
    }

    // Lightweight diagnostics helper for user actions that are not errors, such
    // as opening guide topics, searching help, saving layouts, or reordering
    // columns.
    private func reportDiagnostic(
        category: String,
        severity: DiagnosticSeverity,
        message: String,
        metadata: [String: String] = [:]
    ) {
        Task {
            await diagnosticsReporter.report(
                source: "deployment-tracker",
                category: category,
                severity: severity,
                message: message,
                metadata: demoDiagnosticMetadata(metadata)
            )
        }
    }

    private func demoDiagnosticMetadata(_ metadata: [String: String]) -> [String: String] {
        var merged = metadata
        if runtimeMode.isDemoMode || runtimeMode == .productionDisabled {
            merged["runtime_mode"] = runtimeMode.rawValue
            merged["live_action"] = "false"
            merged["external_data_changed"] = merged["external_data_changed"] ?? "false"
            merged["allow_live_jamf_actions"] = String(demoConfiguration.allowLiveJamfActions)
            merged["allow_live_abm_actions"] = String(demoConfiguration.allowLiveABMActions)
            merged["allow_live_sdplus_actions"] = String(demoConfiguration.allowLiveSDPlusActions)
            merged["allow_external_network_actions"] = String(demoConfiguration.allowExternalNetworkActions)
        }
        return merged
    }

    // Maps diagnostics categories to guide topics. This is intentionally a small
    // heuristic instead of a dependency on view code, keeping diagnostics and
    // recovery guidance available from non-UI action paths.
    private func guideTopicID(forDiagnosticsCategory category: String) -> String {
        if category.contains("jamf-preload.permission") {
            return "jamf-permissions"
        }
        if category.contains("jamf-preload") {
            return "jamf-preload"
        }
        if category.contains("validation") || category.contains("workflow") {
            return "exceptions-validation"
        }
        if category.contains("sdplus") {
            return "sdplus-export"
        }
        if category.contains("abm") {
            return "abm-verification"
        }
        if category.contains("apple-catalog") {
            return "apple-catalog"
        }
        if category.contains("records") {
            return "records-management"
        }
        if category.contains("imports") {
            return "imports"
        }
        if category.contains("devices") {
            return "devices"
        }
        if category.contains("projects") {
            return "projects"
        }
        if category.contains("workbench") {
            return "workbench"
        }
        return "diagnostics"
    }

    // Shortens detailed validation results for banner/error display while the
    // full validation drawer remains available for row-by-row issue review.
    private func preloadValidationSummary(_ result: JamfInventoryPreloadValidationResult) -> String {
        let issueMessages = (result.blockedIssues + result.warningIssues)
            .prefix(3)
            .map(\.message)
            .joined(separator: " ")
        let prefix = "\(result.readyDeviceIds.count) ready, \(result.blockedIssues.count) blocked, \(result.warningIssues.count) warning(s)."
        return issueMessages.isEmpty ? prefix : "\(prefix) \(issueMessages)"
    }

    // Mirrors the preload summary behavior for SD+ exports so the structured
    // error can provide a compact summary without hiding the full validation
    // details captured on the export result.
    private func sdPlusValidationSummary(_ result: SDPlusExportValidationResult) -> String {
        let issueMessages = (result.blockingIssues + result.warningIssues)
            .prefix(3)
            .map(\.message)
            .joined(separator: " ")
        let prefix = "\(result.blockingIssues.count) blocking issue(s), \(result.warningIssues.count) warning(s)."
        return issueMessages.isEmpty ? prefix : "\(prefix) \(issueMessages)"
    }

    // Chooses the backing store for the module. Production uses Core Data; tests
    // can inject a store; and startup failures fall back to in-memory storage
    // with a visible warning so the operator understands persistence risk.
    private static func resolveStore(
        _ injectedStore: (any DeploymentTrackerStore)?,
        runtimeMode: DeploymentTrackerRuntimeMode,
        demoSeed: DeploymentTrackerDemoSeedBundle?
    ) -> StoreResolution {
        if let injectedStore {
            return StoreResolution(store: injectedStore, startupIssue: nil)
        }

        if runtimeMode.isDemoMode {
            let seed = demoSeed ?? DeploymentTrackerDemoDataFactory.makeSeed()
            return StoreResolution(store: DeploymentTrackerDemoDataFactory.makeStore(seed: seed), startupIssue: nil)
        }

        do {
            return StoreResolution(store: try CoreDataDeploymentTrackerStore(), startupIssue: nil)
        } catch {
            let correlationId = UUID().uuidString
            return StoreResolution(
                store: InMemoryDeploymentTrackerStore(),
                startupIssue: DeploymentUserFacingIntegrationError(
                    title: "Deployment Tracker is using temporary storage",
                    summary: "Deployment Tracker could not open its local database, so this session is running on temporary in-memory storage. Changes made in this module may not persist after the app closes.",
                    technicalCause: error.localizedDescription,
                    affectedSystem: "Deployment Tracker",
                    requiredJamfPrivileges: [],
                    localDataChanged: false,
                    externalDataChanged: false,
                    safeToRetry: true,
                    recommendedAction: "Check the local database folder permissions and available disk space, then restart Forsetti Jamf Pro. Export diagnostics if this repeats.",
                    diagnosticsCategory: "deployment-tracker.persistence.startup",
                    diagnosticsCorrelationId: correlationId,
                    relatedGuideTopicId: "diagnostics"
                )
            )
        }
    }

    // Query helpers used by Field Catalog toggles and toolbar controls.
    func isFieldVisible(_ fieldKey: String) -> Bool {
        workbenchLayout.columns.first(where: { $0.fieldKey == fieldKey })?.visible ?? false
    }

    func isFieldPinned(_ fieldKey: String) -> Bool {
        workbenchLayout.columns.first(where: { $0.fieldKey == fieldKey })?.pinned ?? false
    }

    // Exports the currently projected Workbench view. This respects visible
    // columns and filters rather than exporting every stored device field.
    func currentViewCSV() -> String {
        let header = projection.columns.map { csvEscape($0.field.displayName) }.joined(separator: ",")
        let body = projection.rows.map { row in
            row.cells.map { csvEscape($0.displayValue) }.joined(separator: ",")
        }
        return ([header] + body).joined(separator: "\n")
    }

    // Generates an in-app preview of the current view export. File saving, if
    // added later, should use the same currentViewCSV() source.
    func generateCurrentViewExportPreview() {
        exportPreview = currentViewCSV()
        actionMessage = runtimeMode.isDemoMode
            ? "Preview Demo current view export generated. Dummy data only. No live Jamf actions."
            : "Prepared current view export preview."
    }

    // Recomputes the Workbench and Dashboard projections from the latest domain
    // state. Call this after any operation that changes devices, fields, layouts,
    // reference values, workflow statuses, or filters.
    private func refreshProjection() {
        let filters: [DeploymentWorkbenchFilter]
        if filterText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            filters = []
        } else {
            filters = [DeploymentWorkbenchFilter(fieldKey: "*", query: filterText)]
        }

        projection = projectionService.makeProjection(
            devices: devices,
            fieldDefinitions: fieldDefinitions,
            layout: workbenchLayout,
            referenceValues: referenceValues,
            filters: filters
        )
        dashboardProjection = DeploymentKPIProjectionService().makeDashboardProjection(
            devices: devices,
            projects: projects,
            statuses: workflowStatuses,
            referenceValues: referenceValues
        )
    }

    // Persists layout edits asynchronously. The UI already reflects the in-memory
    // layout, and any persistence failure is surfaced through loadErrorMessage.
    private func persistWorkbenchLayout() {
        let layout = workbenchLayout
        Task {
            do {
                try await store.saveWorkbenchLayout(layout)
            } catch {
                loadErrorMessage = error.localizedDescription
            }
        }
    }

    // Minimal CSV escaping for Workbench previews and exports.
    private func csvEscape(_ value: String) -> String {
        if value.contains(",") || value.contains("\"") || value.contains("\n") {
            return "\"\(value.replacingOccurrences(of: "\"", with: "\"\""))\""
        }
        return value
    }

    // Adds workflow statuses to normal reference values so reference dropdowns
    // can render workflow status names using the same option resolution path as
    // projects, device types, profiles, and locations.
    private static func combinedReferenceValues(
        referenceValues: [DeploymentReferenceValue],
        workflowStatuses: [DeploymentWorkflowStatusDefinition]
    ) -> [DeploymentReferenceValue] {
        referenceValues + workflowStatuses.map {
            DeploymentReferenceValue(
                id: $0.id,
                categoryId: "workflow-statuses",
                displayName: $0.displayName,
                sortOrder: $0.sortOrder,
                metadata: ["systemBehaviorTag": $0.systemBehaviorTag],
                lifecycleState: $0.lifecycleState
            )
        }
    }
}

struct DeploymentTrackerRootView: View {
    @StateObject private var viewModel: DeploymentTrackerViewModel

    // RootView owns the StateObject lifetime for the tracker view model. The
    // module factory passes in a fully configured view model, and SwiftUI keeps
    // that object stable across root view refreshes.
    init(viewModel: DeploymentTrackerViewModel) {
        _viewModel = StateObject(wrappedValue: viewModel)
    }

    var body: some View {
        NavigationSplitView {
            sidebar
        } detail: {
            ScrollView {
                VStack(alignment: .leading, spacing: DashboardTheme.Spacing.section) {
                    header
                    if let userFacingError = viewModel.userFacingError {
                        DeploymentStructuredErrorView(error: userFacingError) { topicID in
                            viewModel.openGuide(topicID: topicID, sourceWorkspace: viewModel.selectedWorkspace)
                        }
                    }
                    if let actionMessage = viewModel.actionMessage {
                        Label(actionMessage, systemImage: "checkmark.circle")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(12)
                            .dashboardCardSurface()
                    }
                    workspaceView
                }
                .padding(.horizontal, DashboardTheme.Spacing.section)
                .padding(.vertical, DashboardTheme.Spacing.section)
            }
        }
        .background {
            // The tracker uses the shared app backdrop and Metal background so
            // the module visually matches the rest of Forsetti Jamf Pro while still
            // allowing workspace cards to remain legible.
            ZStack {
                DashboardTheme.groupedSurface
                DashboardMetalBackgroundView()
                DashboardTheme.appBackdropGradient.opacity(0.62)
            }
            .ignoresSafeArea()
        }
        .task {
            // Loading happens silently on appearance. The user sees stable
            // module chrome while persistence-backed data and projections are
            // refreshed in the view model.
            await viewModel.loadWorkbench()
            await viewModel.diagnosticsReporter.report(
                source: "deployment-tracker",
                category: viewModel.isDemoMode ? "deployment-tracker.demo.lifecycle" : "module.lifecycle",
                severity: .info,
                message: viewModel.isDemoMode ? "Deployment Tracker Demo opened." : "Deployment Tracker module opened.",
                metadata: [
                    "phase": viewModel.isDemoMode ? "demo" : "remediation",
                    "demo_mode": String(viewModel.isDemoMode),
                    "runtime_mode": viewModel.runtimeMode.rawValue,
                    "live_action": "false",
                    "external_data_changed": "false"
                ]
            )
        }
        .sheet(isPresented: $viewModel.isGuidePresented) {
            DeploymentTrackerGuideView(viewModel: viewModel, showCloseButton: true)
#if os(macOS)
                // Roomy on macOS; on iPhone/iPad the sheet sizes to the device
                // (a hard 840pt minWidth would overflow and clip the screen).
                .frame(minWidth: 840, minHeight: 640)
#endif
        }
        .overlay(alignment: .bottomTrailing) {
            if viewModel.activeDemoScenario != nil {
                DeploymentDemoScenarioOverlayView(viewModel: viewModel)
            } else if let scenario = viewModel.completedDemoScenario {
                DeploymentDemoCompletionCardView(
                    scenario: scenario,
                    close: {
                        viewModel.dismissCompletedDemoScenario()
                    },
                    openGuide: {
                        viewModel.openActiveDemoScenarioGuide()
                    }
                )
            }
        }
    }

    private var header: some View {
        // The header stays outside individual workspace views so the guide entry
        // point and module title remain consistent while the selected workspace
        // changes below.
        HStack(alignment: .top, spacing: DashboardTheme.Spacing.section) {
            VStack(alignment: .leading, spacing: DashboardTheme.Spacing.item) {
                DeploymentDemoRibbonView()
                Label("Deployment Tracker Demo", systemImage: "sparkles.rectangle.stack")
                    .font(.system(.largeTitle, design: .rounded).weight(.bold))
                    .foregroundStyle(.primary)

                Text("DEMO - COMING SOON - Interactive preview. Dummy data only. No live Jamf actions.")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: DashboardTheme.Spacing.item)
            Button {
                viewModel.resetDemoData()
            } label: {
                Label("Reset Demo", systemImage: "arrow.counterclockwise")
            }
            .controlSize(.large)
            .help("Reset Dummy data only. No live Jamf actions.")
            Button {
                viewModel.openGuide(sourceWorkspace: viewModel.selectedWorkspace)
            } label: {
                Label("Guide", systemImage: "questionmark.circle")
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .help("Open step-by-step instructions for using Deployment Tracker.")
            .accessibilityLabel("Tracker Guide")
            .accessibilityHint("Opens step-by-step instructions for using Deployment Tracker features.")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .dashboardCardSurface()
    }

    @ViewBuilder
    private var workspaceView: some View {
        // Workspace routing is explicit to keep each workspace independent. This
        // also makes it obvious which guide topic and view model action surface
        // belong to each operational area.
        switch viewModel.selectedWorkspace {
        case .dashboard:
            DeploymentWorkspaceChrome(
                title: "Deployment Tracker Demo Dashboard",
                subtitle: "DEMO - COMING SOON interactive preview with deterministic data only. No live Jamf actions.",
                workspace: .dashboard,
                activeScenario: viewModel.activeDemoScenario,
                isScenarioPaused: viewModel.isDemoScenarioPaused,
                guideTopicID: "dashboard",
                openGuide: { viewModel.openGuide(topicID: $0, sourceWorkspace: .dashboard) },
                runDemo: { viewModel.startDemoScenario(for: .dashboard) }
            ) {
                DeploymentDemoHeroView(viewModel: viewModel)
                DeploymentDemoSignalFlowMetalView(activeWorkspace: viewModel.selectedWorkspace, activeScenario: viewModel.activeDemoScenario)
                DeploymentDemoScenarioLauncher(viewModel: viewModel)
                if let result = viewModel.demoSimulationResult {
                    DeploymentDemoSimulationResultCard(result: result)
                }
                DeploymentDashboardKPIView(projection: viewModel.dashboardProjection)
                DeploymentDashboardTaskCardsView(viewModel: viewModel)
            }
        case .inProgress:
            DeploymentInProgressWorkbenchView(viewModel: viewModel)
        case .projects:
            DeploymentProjectsWorkspaceView(viewModel: viewModel)
        case .devices:
            DeploymentDevicesWorkspaceView(viewModel: viewModel)
        case .intakeImports:
            DeploymentIntakeWorkspaceView(viewModel: viewModel)
        case .jamfPreload:
            DeploymentJamfPreloadWorkspaceView(viewModel: viewModel)
        case .abmVerification:
            DeploymentABMWorkspaceView(viewModel: viewModel)
        case .sdPlusExport:
            DeploymentSDPlusWorkspaceView(viewModel: viewModel)
        case .shipments:
            DeploymentShipmentsWorkspaceView(viewModel: viewModel)
        case .reports:
            DeploymentReportsWorkspaceView(viewModel: viewModel)
        case .appleCatalog:
            DeploymentAppleCatalogWorkspaceView(viewModel: viewModel)
        case .administration:
            DeploymentAdministrationWorkspaceView(viewModel: viewModel)
        case .recordsManagement:
            DeploymentRecordsWorkspaceView(viewModel: viewModel)
        case .guide:
            DeploymentTrackerGuideView(viewModel: viewModel)
                .frame(minHeight: 640)
        }
    }

    @ViewBuilder
    private var sidebar: some View {
        #if os(iOS)
        // iOS does not expose the same selection-based List initializer as
        // macOS. Buttons update the same selectedWorkspace state without relying
        // on the unavailable API, preserving the single source of navigation
        // truth across platforms.
        List {
            Section("Deployment Tracker Demo") {
                ForEach(DeploymentTrackerWorkspace.allCases) { workspace in
                    Button {
                        viewModel.selectWorkspace(workspace)
                    } label: {
                        HStack {
                            Label(workspace.displayName, systemImage: workspace.iconSystemName)
                            Spacer(minLength: DashboardTheme.Spacing.compact)
                            if viewModel.selectedWorkspace == workspace {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(DashboardTheme.accent)
                            }
                        }
                    }
                    .foregroundStyle(viewModel.selectedWorkspace == workspace ? DashboardTheme.accent : .primary)
                }
            }
        }
        #else
        // macOS keeps the native List selection binding because it gives the
        // sidebar keyboard and pointer behavior expected on desktop.
        List(selection: $viewModel.selectedWorkspace) {
            Section("Deployment Tracker Demo") {
                ForEach(DeploymentTrackerWorkspace.allCases) { workspace in
                    Label(workspace.displayName, systemImage: workspace.iconSystemName)
                        .tag(workspace)
                }
            }
        }
        .navigationSplitViewColumnWidth(min: 220, ideal: 260, max: 320)
        #endif
    }

}

private struct DeploymentStructuredErrorView: View {
    let error: DeploymentUserFacingIntegrationError
    var openGuide: (String) -> Void

    var body: some View {
        // Structured errors are deliberately verbose. They tell the technician
        // what failed, whether any local or external data changed, whether retry
        // is safe, and which guide topic contains recovery steps.
        VStack(alignment: .leading, spacing: DashboardTheme.Spacing.compact) {
            Label(error.title, systemImage: "exclamationmark.octagon")
                .font(.headline)
                .foregroundStyle(.red)
            Text(error.summary)
                .font(.callout)
            Text("Affected system: \(error.affectedSystem)")
                .font(.caption)
                .foregroundStyle(.secondary)
            Text("Technical cause: \(error.technicalCause)")
                .font(.caption)
                .foregroundStyle(.secondary)
            if !error.requiredJamfPrivileges.isEmpty {
                Text("Required privileges: \(error.requiredJamfPrivileges.joined(separator: ", "))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Text("Jamf data changed: \(error.externalDataChanged ? "Yes" : "No") • Local data changed: \(error.localDataChanged ? "Yes" : "No") • Safe to retry: \(error.safeToRetry ? "Yes" : "No")")
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(error.recommendedAction)
                .font(.caption)
                .foregroundStyle(.secondary)
            if let diagnosticsCorrelationId = error.diagnosticsCorrelationId {
                Text("Diagnostics: \(error.diagnosticsCategory) / \(diagnosticsCorrelationId)")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            if let relatedGuideTopicId = error.relatedGuideTopicId {
                Button {
                    openGuide(relatedGuideTopicId)
                } label: {
                    Label("Open Related Guide", systemImage: "questionmark.circle")
                }
                .buttonStyle(.bordered)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .dashboardCardSurface()
    }
}

private extension String {
    var nilIfEmpty: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
