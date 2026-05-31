import SwiftUI

// MARK: - Workspace routing and shared workspace chrome
//
// Deployment Tracker workspaces are independent UI surfaces that share one view
// model and one persistence boundary. The enum is the navigation contract used
// by the sidebar, Dashboard task cards, guide links, and structured errors.
nonisolated enum DeploymentTrackerWorkspace: String, Codable, CaseIterable, Identifiable, Sendable {
    case dashboard
    case inProgress
    case projects
    case devices
    case intakeImports
    case jamfPreload
    case abmVerification
    case sdPlusExport
    case shipments
    case reports
    case appleCatalog
    case administration
    case recordsManagement
    case guide

    var id: String { rawValue }

    // User-facing names for sidebar rows and navigation labels. Keep these
    // stable because guide topics, user training, and screenshots refer to them.
    var displayName: String {
        switch self {
        case .dashboard: return "Demo Dashboard"
        case .inProgress: return "Demo Workbench"
        case .projects: return "Demo Projects"
        case .devices: return "Demo Devices"
        case .intakeImports: return "Demo Intake / Imports"
        case .jamfPreload: return "Demo Jamf Preload"
        case .abmVerification: return "Demo ABM Verification"
        case .sdPlusExport: return "Demo SD+ Export"
        case .shipments: return "Demo Shipments"
        case .reports: return "Demo Reports"
        case .appleCatalog: return "Demo Apple Catalog"
        case .administration: return "Demo Administration"
        case .recordsManagement: return "Demo Records Management"
        case .guide: return "Demo Guide"
        }
    }

    // SF Symbol names for navigation and guide links. These are presentation
    // details, but keeping them on the enum ensures every workspace has a
    // consistent icon wherever it appears.
    var iconSystemName: String {
        switch self {
        case .dashboard: return "chart.xyaxis.line"
        case .inProgress: return "tablecells"
        case .projects: return "folder.badge.gearshape"
        case .devices: return "macbook.and.iphone"
        case .intakeImports: return "tray.and.arrow.down"
        case .jamfPreload: return "arrow.up.doc"
        case .abmVerification: return "checkmark.shield"
        case .sdPlusExport: return "square.and.arrow.up"
        case .shipments: return "shippingbox"
        case .reports: return "doc.text.magnifyingglass"
        case .appleCatalog: return "apple.logo"
        case .administration: return "slider.horizontal.3"
        case .recordsManagement: return "archivebox"
        case .guide: return "questionmark.circle"
        }
    }

    // Default guide topic for each workspace. This lets any workspace open the
    // correct instructions without duplicating topic ids throughout the views.
    var guideTopicID: String {
        switch self {
        case .dashboard: return "dashboard"
        case .inProgress: return "workbench"
        case .projects: return "projects"
        case .devices: return "devices"
        case .intakeImports: return "imports"
        case .jamfPreload: return "jamf-preload"
        case .abmVerification: return "abm-verification"
        case .sdPlusExport: return "sdplus-export"
        case .shipments: return "shipments"
        case .reports: return "diagnostics"
        case .appleCatalog: return "apple-catalog"
        case .administration: return "glossary"
        case .recordsManagement: return "records-management"
        case .guide: return "start-here"
        }
    }
}

// Shared wrapper for workspace title, subtitle, guide button, and content. It
// keeps the module visually consistent while allowing each workspace to remain a
// small focused view.
struct DeploymentWorkspaceChrome<Content: View>: View {
    let title: String
    let subtitle: String
    var workspace: DeploymentTrackerWorkspace? = nil
    var activeScenario: DeploymentDemoScenario? = nil
    var isScenarioPaused: Bool = false
    var guideTopicID: String? = nil
    var openGuide: ((String) -> Void)? = nil
    var runDemo: (() -> Void)? = nil
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: ForsettiTheme.Spacing.section) {
            DeploymentDemoRibbonView()
            DeploymentDemoWorkspaceAccentStripView(
                workspace: workspace,
                scenario: activeScenario,
                isPaused: isScenarioPaused
            )
            HStack(alignment: .top, spacing: ForsettiTheme.Spacing.item) {
                VStack(alignment: .leading, spacing: ForsettiTheme.Spacing.compact) {
                    Text(title)
                        .font(.system(.title2, design: .rounded).weight(.semibold))
                    Text(subtitle)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: ForsettiTheme.Spacing.item)
                if let runDemo {
                    Button {
                        runDemo()
                    } label: {
                        Label("Run Demo", systemImage: "play.rectangle")
                    }
                    .buttonStyle(.borderedProminent)
                    .help("Run the guided Demo for this workspace.")
                }
                if let guideTopicID, let openGuide {
                    Button {
                        openGuide(guideTopicID)
                    } label: {
                        Label("Guide", systemImage: "questionmark.circle")
                    }
                    .help("Open step-by-step instructions for this workspace.")
                    .accessibilityLabel("Tracker Guide")
                    .accessibilityHint("Opens step-by-step instructions for this Deployment Tracker workspace.")
                }
            }
            content
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(ForsettiTheme.Spacing.section)
    }
}

// MARK: - Project and device workspaces
//
// These simple CRUD surfaces provide safe local record creation and archive
// actions. Rich field editing stays in the Workbench so technicians have one
// primary grid for operational edits.
struct DeploymentProjectsWorkspaceView: View {
    @ObservedObject var viewModel: DeploymentTrackerViewModel
    @State private var projectName = ""
    @State private var projectCode = ""

    var body: some View {
        DeploymentWorkspaceChrome(
            title: "Projects Demo",
            subtitle: "Create, edit, archive, and restore Demo deployment projects. Project policy previews workflow gates for ABM, Jamf Preload, SD+, shipping, and completion.",
            workspace: .projects,
            activeScenario: viewModel.activeDemoScenario,
            isScenarioPaused: viewModel.isDemoScenarioPaused,
            guideTopicID: "projects",
            openGuide: { viewModel.openGuide(topicID: $0, sourceWorkspace: .projects) },
            runDemo: { viewModel.startDemoScenario(for: .projects) }
        ) {
            HStack(alignment: .bottom, spacing: ForsettiTheme.Spacing.item) {
                TextField("Project name", text: $projectName)
                    .textFieldStyle(.roundedBorder)
                TextField("Code", text: $projectCode)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 140)
                Button {
                    viewModel.createProject(name: projectName, code: projectCode)
                    projectName = ""
                    projectCode = ""
                } label: {
                    Label("Create Demo Project", systemImage: "plus")
                }
                .disabled(projectName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            .padding(12)
            .forsettiCardSurface()

            DeploymentSimpleTable(
                rows: viewModel.projects.map {
                    DeploymentSimpleRow(
                        id: $0.id,
                        title: $0.projectName,
                        subtitle: [$0.projectCode, $0.ticketNumber, $0.projectStatus].compactMap { $0 }.joined(separator: " • "),
                        state: $0.recordLifecycleState.rawValue
                    )
                },
                emptyMessage: "No Demo projects have been created."
            ) { id in
                viewModel.archiveProject(id: id)
            }
        }
    }
}

// Device creation captures the minimum reliable identity fields. Enrichment and
// assignment details are handled later through imports, catalog review, Jamf
// snapshots, or Workbench edits.
struct DeploymentDevicesWorkspaceView: View {
    @ObservedObject var viewModel: DeploymentTrackerViewModel
    @State private var serialNumber = ""
    @State private var assetTag = ""

    var body: some View {
        DeploymentWorkspaceChrome(
            title: "Devices Demo",
            subtitle: "Create, edit, archive, and restore Deployment Tracker Demo device records. Serial numbers are normalized and active Demo records remain unique.",
            workspace: .devices,
            activeScenario: viewModel.activeDemoScenario,
            isScenarioPaused: viewModel.isDemoScenarioPaused,
            guideTopicID: "devices",
            openGuide: { viewModel.openGuide(topicID: $0, sourceWorkspace: .devices) },
            runDemo: { viewModel.startDemoScenario(for: .devices) }
        ) {
            HStack(alignment: .bottom, spacing: ForsettiTheme.Spacing.item) {
                TextField("Serial number", text: $serialNumber)
                    .textFieldStyle(.roundedBorder)
                TextField("Asset tag", text: $assetTag)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 160)
                Button {
                    viewModel.createDevice(serialNumber: serialNumber, assetTag: assetTag)
                    serialNumber = ""
                    assetTag = ""
                } label: {
                    Label("Create Demo Device", systemImage: "plus")
                }
                .disabled(serialNumber.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            .padding(12)
            .forsettiCardSurface()

            DeploymentSimpleTable(
                rows: viewModel.devices.map {
                    DeploymentSimpleRow(
                        id: $0.id,
                        title: $0.serialNumber,
                        subtitle: [$0.assetTag, $0.model, $0.assignedUser].compactMap { $0 }.joined(separator: " • "),
                        state: $0.recordLifecycleState.rawValue
                    )
                },
                emptyMessage: "No Demo devices have been created."
            ) { id in
                viewModel.archiveDevice(id: id)
            }
        }
    }
}

// MARK: - Jamf Inventory Preload workspace
//
// Jamf Preload is split into lookup, submission, and diagnostics cards so the
// operator can resolve permissions or data quality problems before sending data
// to Jamf Pro.
struct DeploymentJamfPreloadWorkspaceView: View {
    @ObservedObject var viewModel: DeploymentTrackerViewModel

    var body: some View {
        DeploymentWorkspaceChrome(
            title: "Jamf Preload Demo",
            subtitle: "Simulate lookup, validation, submission, update, retry, and reconciliation for Jamf Inventory Preload. Dummy data only. No live Jamf actions.",
            workspace: .jamfPreload,
            activeScenario: viewModel.activeDemoScenario,
            isScenarioPaused: viewModel.isDemoScenarioPaused,
            guideTopicID: "jamf-preload",
            openGuide: { viewModel.openGuide(topicID: $0, sourceWorkspace: .jamfPreload) },
            runDemo: { viewModel.startDemoScenario(for: .jamfPreload) }
        ) {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 320), spacing: ForsettiTheme.Spacing.section)], alignment: .leading, spacing: ForsettiTheme.Spacing.section) {
                preloadLookupCard
                preloadSubmissionCard
                preloadDiagnosticsCard
            }

            if let result = viewModel.preloadValidationResult {
                DeploymentPreloadValidationView(result: result)
            }

            if let preview = viewModel.preloadCSVPreview {
                DeploymentPreloadPreviewView(title: "Preview Demo Inventory Preload CSV", text: preview)
            }

            DeploymentSimpleTable(
                rows: viewModel.preloadSubmissions.map {
                    DeploymentSimpleRow(
                        id: $0.id,
                        title: "\($0.deviceIds.count) devices • \($0.state.rawValue)",
                        subtitle: $0.responseSummary ?? $0.payloadHash,
                        state: $0.submittedAt.formatted(date: .abbreviated, time: .shortened)
                    )
                },
                emptyMessage: "No Demo Jamf Inventory Preload submissions recorded."
            ) { id in
                viewModel.retryFailedPreloadSubmission(id: id)
            }
        }
    }

    private var preloadLookupCard: some View {
        // Lookup controls support both single serials and pasted batches. Force
        // refresh buttons use the same service path while bypassing local cache.
        VStack(alignment: .leading, spacing: ForsettiTheme.Spacing.item) {
            Label("Simulation Lookup", systemImage: "magnifyingglass")
                .font(.headline)
            TextField("Serial number", text: $viewModel.preloadSerialInput)
                .textFieldStyle(.roundedBorder)
            TextField("Batch serials, one per line", text: $viewModel.preloadBatchInput, axis: .vertical)
                .textFieldStyle(.roundedBorder)
                .lineLimit(4...8)
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Button {
                        viewModel.lookupSinglePreloadSerial()
                    } label: {
                        Label("Simulate Serial Lookup", systemImage: "magnifyingglass")
                    }
                    Button {
                        viewModel.lookupBatchPreloadSerials()
                    } label: {
                        Label("Simulate Batch Lookup", systemImage: "list.bullet.rectangle")
                    }
                }
                HStack {
                    Button {
                        viewModel.refreshSinglePreloadSerial()
                    } label: {
                        Label("Refresh Demo Serial", systemImage: "arrow.clockwise")
                    }
                    Button {
                        viewModel.refreshBatchPreloadSerials()
                    } label: {
                        Label("Refresh Demo Batch", systemImage: "arrow.triangle.2.circlepath")
                    }
                }
            }
        }
        .padding(14)
        .forsettiCardSurface()
    }

    private var preloadSubmissionCard: some View {
        // Submission actions act on the current Workbench selection or filtered
        // row set, matching the batch behavior documented in the guide.
        VStack(alignment: .leading, spacing: ForsettiTheme.Spacing.item) {
            Label("Simulation Actions", systemImage: "arrow.up.doc")
                .font(.headline)
            Text("Selected Demo workbench rows are validated locally and rendered as a Demo Jamf Inventory Preload CSV. No live Jamf actions are run.")
                .font(.callout)
                .foregroundStyle(.secondary)
            Button {
                viewModel.validateSelectedForPreload()
            } label: {
                Label("Preview Demo Validation", systemImage: "checklist")
            }
            Button {
                viewModel.sendSelectedInventoryPreload()
            } label: {
                Label("Simulate Jamf Preload Submission", systemImage: "paperplane")
            }
            Button {
                viewModel.createPreloadUpdateBatch()
            } label: {
                Label("Preview Demo Update Batch", systemImage: "arrow.triangle.2.circlepath")
            }
            Button {
                viewModel.reconcileSelectedPreload()
            } label: {
                Label("Simulate Reconciliation", systemImage: "checkmark.arrow.trianglehead.counterclockwise")
            }
        }
        .padding(14)
        .forsettiCardSurface()
    }

    private var preloadDiagnosticsCard: some View {
        // Permission diagnostics are displayed without making a Jamf write, so a
        // technician can confirm required privileges before retrying a failed
        // lookup or upload.
        VStack(alignment: .leading, spacing: ForsettiTheme.Spacing.item) {
            Label("Permission Diagnostics", systemImage: "lock.shield")
                .font(.headline)
            Text("Demo diagnostics preview the future Jamf privileges: create and update Inventory Preload records, create and update user data, and read Inventory Preload records. No live Jamf actions.")
                .font(.callout)
                .foregroundStyle(.secondary)
            Button {
                viewModel.showPreloadPermissionDiagnostics()
            } label: {
                Label("Show Required Privileges", systemImage: "list.bullet.clipboard")
            }
        }
        .padding(14)
        .forsettiCardSurface()
    }
}

// Read-only ABM workspace. It queues local exception review from current data
// and does not include any ABM edit, release, assignment, or delete controls.
struct DeploymentABMWorkspaceView: View {
    @ObservedObject var viewModel: DeploymentTrackerViewModel

    var body: some View {
        DeploymentWorkspaceChrome(
            title: "ABM Verification Demo",
            subtitle: "Read-only Demo Apple Business verification. Mismatches become local Demo exceptions; no ABM assignment, release, edit, or delete behavior exists.",
            workspace: .abmVerification,
            activeScenario: viewModel.activeDemoScenario,
            isScenarioPaused: viewModel.isDemoScenarioPaused,
            guideTopicID: "abm-verification",
            openGuide: { viewModel.openGuide(topicID: $0, sourceWorkspace: .abmVerification) },
            runDemo: { viewModel.startDemoScenario(for: .abmVerification) }
        ) {
            HStack(spacing: ForsettiTheme.Spacing.item) {
                Button {
                    viewModel.verifySelectedWithABM()
                } label: {
                    Label("Run Demo ABM Check", systemImage: "checkmark.shield")
                }
                Button {
                    viewModel.verifyBatchWithABM()
                } label: {
                    Label("Run Demo ABM Batch Check", systemImage: "list.bullet.rectangle")
                }
            }
            .padding(12)
            .forsettiCardSurface()

            DeploymentSimpleTable(
                rows: viewModel.exceptions.map {
                    DeploymentSimpleRow(id: $0.id, title: $0.summary, subtitle: $0.reasonCode, state: $0.status.rawValue)
                },
                emptyMessage: "No Demo ABM mismatches or exceptions are queued."
            )
        }
    }
}

// SD+ export workspace. Preview and generation are separate so users can inspect
// template output before recording an export job.
struct DeploymentSDPlusWorkspaceView: View {
    @ObservedObject var viewModel: DeploymentTrackerViewModel

    var body: some View {
        DeploymentWorkspaceChrome(
            title: "SD+ Export Demo",
            subtitle: "Template-driven Demo SD+ CSV export with preview, validation, export history, and re-export versioning. No SD+ data changed.",
            workspace: .sdPlusExport,
            activeScenario: viewModel.activeDemoScenario,
            isScenarioPaused: viewModel.isDemoScenarioPaused,
            guideTopicID: "sdplus-export",
            openGuide: { viewModel.openGuide(topicID: $0, sourceWorkspace: .sdPlusExport) },
            runDemo: { viewModel.startDemoScenario(for: .sdPlusExport) }
        ) {
            HStack(spacing: ForsettiTheme.Spacing.item) {
                Button {
                    viewModel.previewSDPlusExport()
                } label: {
                    Label("Preview Demo Export", systemImage: "doc.text.magnifyingglass")
                }
                Button {
                    viewModel.generateSDPlusExport()
                } label: {
                    Label("Generate Demo SD+ Export Preview", systemImage: "square.and.arrow.up")
                }
            }
            .padding(12)
            .forsettiCardSurface()

            if let preview = viewModel.sdPlusPreview {
                DeploymentPreloadPreviewView(title: "Demo SD+ Export Preview", text: preview)
            }

            DeploymentSimpleTable(
                rows: viewModel.sdPlusExportJobs.map {
                    DeploymentSimpleRow(id: $0.id, title: $0.fileName, subtitle: $0.validationSummary, state: "v\($0.exportVersion)")
                },
                emptyMessage: "No Demo SD+ export history recorded."
            )
        }
    }
}

// Apple Catalog workspace for local hardware enrichment. Imported catalog data
// improves Tracker-owned records while preserving read-only Jamf and ABM
// snapshots.
struct DeploymentAppleCatalogWorkspaceView: View {
    @ObservedObject var viewModel: DeploymentTrackerViewModel

    var body: some View {
        DeploymentWorkspaceChrome(
            title: "Apple Catalog Demo",
            subtitle: "Deployment Tracker Demo catalog browser, local import staging, unresolved-device review, and confidence scoring. Catalog enrichment is local and never overwrites ABM or Jamf snapshots.",
            workspace: .appleCatalog,
            activeScenario: viewModel.activeDemoScenario,
            isScenarioPaused: viewModel.isDemoScenarioPaused,
            guideTopicID: "apple-catalog",
            openGuide: { viewModel.openGuide(topicID: $0, sourceWorkspace: .appleCatalog) },
            runDemo: { viewModel.startDemoScenario(for: .appleCatalog) }
        ) {
            HStack(spacing: ForsettiTheme.Spacing.item) {
                Button {
                    viewModel.importSampleAppleCatalogEntries()
                } label: {
                    Label("Import Demo Catalog", systemImage: "tray.and.arrow.down")
                }
                Button {
                    viewModel.reviewUnresolvedCatalogDevices()
                } label: {
                    Label("Review Demo Unresolved", systemImage: "questionmark.folder")
                }
            }
            .padding(12)
            .forsettiCardSurface()

            DeploymentSimpleTable(
                rows: viewModel.appleCatalogEntries.map {
                    DeploymentSimpleRow(
                        id: $0.id,
                        title: $0.marketingName ?? $0.modelIdentifier ?? $0.applePartNumber ?? "Catalog Entry",
                        subtitle: [$0.applePartNumber, $0.vendorSku, $0.deviceType].compactMap { $0 }.joined(separator: " • "),
                        state: "\(Int($0.confidenceScore * 100))%"
                    )
                },
                emptyMessage: "No Demo Apple Catalog entries imported."
            )
        }
    }
}

// Records Management workspace. The available action is archive/export oriented;
// hard-delete review is deliberately gated by the view model until safety checks
// are fully implemented.
struct DeploymentRecordsWorkspaceView: View {
    @ObservedObject var viewModel: DeploymentTrackerViewModel

    var body: some View {
        DeploymentWorkspaceChrome(
            title: "Records Management Demo",
            subtitle: "Archive-first Demo governance, records export, deletion impact review, and export-before-delete enforcement. Production deletion is coming soon and not available from this Demo.",
            workspace: .recordsManagement,
            activeScenario: viewModel.activeDemoScenario,
            isScenarioPaused: viewModel.isDemoScenarioPaused,
            guideTopicID: "records-management",
            openGuide: { viewModel.openGuide(topicID: $0, sourceWorkspace: .recordsManagement) },
            runDemo: { viewModel.startDemoScenario(for: .recordsManagement) }
        ) {
            HStack(spacing: ForsettiTheme.Spacing.item) {
                Button {
                    viewModel.exportRecordsPackage()
                } label: {
                    Label("Generate Demo Records Package", systemImage: "archivebox")
                }
                Button {
                    viewModel.reviewDeletionImpact()
                } label: {
                    Label("Preview Demo Deletion Review", systemImage: "exclamationmark.triangle")
                }
            }
            .padding(12)
            .forsettiCardSurface()

            DeploymentSimpleTable(
                rows: viewModel.recordsExportJobs.map {
                    DeploymentSimpleRow(id: $0.id, title: $0.packageName, subtitle: $0.fileName, state: "\($0.includedRecordCount) records")
                },
                emptyMessage: "No Demo records export packages have been created."
            )
        }
    }
}

// Administration workspace presents reference values and workflow reference data
// for review. Editing these values should remain controlled by dedicated admin
// workflows rather than ad hoc row mutation.
struct DeploymentAdministrationWorkspaceView: View {
    @ObservedObject var viewModel: DeploymentTrackerViewModel

    var body: some View {
        DeploymentWorkspaceChrome(
            title: "Administration Demo",
            subtitle: "Demo reference data, workflow statuses, device types, profiles, locations, GEOs, business units, vendors, and custom field definitions.",
            workspace: .administration,
            activeScenario: viewModel.activeDemoScenario,
            isScenarioPaused: viewModel.isDemoScenarioPaused,
            guideTopicID: "glossary",
            openGuide: { viewModel.openGuide(topicID: $0, sourceWorkspace: .administration) },
            runDemo: { viewModel.startDemoScenario(for: .administration) }
        ) {
            DeploymentSimpleTable(
                rows: viewModel.referenceValues.map {
                    DeploymentSimpleRow(id: $0.id, title: $0.displayName, subtitle: $0.categoryId, state: $0.lifecycleState.rawValue)
                },
                emptyMessage: "No Demo reference values are available."
            )
        }
    }
}

// Intake workspace stages import workflows. Preview-only buttons preserve the
// intended safe import flow until duplicate resolution and commit behavior are
// complete.
struct DeploymentIntakeWorkspaceView: View {
    @ObservedObject var viewModel: DeploymentTrackerViewModel

    var body: some View {
        DeploymentWorkspaceChrome(
            title: "Intake / Imports Demo",
            subtitle: "Demo vendor CSV, serial-list, and workbook-migration imports are staged for preview before commit with conflict handling.",
            workspace: .intakeImports,
            activeScenario: viewModel.activeDemoScenario,
            isScenarioPaused: viewModel.isDemoScenarioPaused,
            guideTopicID: "imports",
            openGuide: { viewModel.openGuide(topicID: $0, sourceWorkspace: .intakeImports) },
            runDemo: { viewModel.startDemoScenario(for: .intakeImports) }
        ) {
            HStack(spacing: ForsettiTheme.Spacing.item) {
                Button {
                    viewModel.stageVendorImportPreview()
                } label: {
                    Label("Preview Demo Vendor Import", systemImage: "doc.badge.plus")
                }
                Button {
                    viewModel.stageWorkbookMigrationPreview()
                } label: {
                    Label("Preview Demo Workbook Migration", systemImage: "tablecells.badge.ellipsis")
                }
            }
            .padding(12)
            .forsettiCardSurface()
        }
    }
}

// Shipment workspace filters the device list to logistics-relevant states. It
// intentionally uses local Tracker shipment fields rather than contacting a
// shipping carrier from this view.
struct DeploymentShipmentsWorkspaceView: View {
    @ObservedObject var viewModel: DeploymentTrackerViewModel

    var body: some View {
        DeploymentWorkspaceChrome(
            title: "Shipments Demo",
            subtitle: "Track Demo ready-to-ship, shipped, delivered, returned, and blocked shipment states with required tracking and delivery confirmation gates.",
            workspace: .shipments,
            activeScenario: viewModel.activeDemoScenario,
            isScenarioPaused: viewModel.isDemoScenarioPaused,
            guideTopicID: "shipments",
            openGuide: { viewModel.openGuide(topicID: $0, sourceWorkspace: .shipments) },
            runDemo: { viewModel.startDemoScenario(for: .shipments) }
        ) {
            DeploymentSimpleTable(
                rows: viewModel.devices
                    .filter { [.ready, .submitted, .complete, .failed].contains($0.shippingState) }
                    .map {
                        DeploymentSimpleRow(
                            id: $0.id,
                            title: $0.serialNumber,
                            subtitle: [$0.fedExTrackingNumber, $0.deliveryConfirmation].compactMap { $0 }.joined(separator: " • "),
                            state: $0.shippingState.rawValue
                        )
                    },
                emptyMessage: "No Demo shipment records are active."
            )
        }
    }
}

// Reports workspace currently exposes dashboard KPI projections in tabular form.
// More specialized reports can be added here without changing Dashboard cards.
struct DeploymentReportsWorkspaceView: View {
    @ObservedObject var viewModel: DeploymentTrackerViewModel

    var body: some View {
        DeploymentWorkspaceChrome(
            title: "Reports Demo",
            subtitle: "Demo operational reporting surfaces for deployment inventory, project status, exceptions, Jamf Preload, SD+, and records exports.",
            workspace: .reports,
            activeScenario: viewModel.activeDemoScenario,
            isScenarioPaused: viewModel.isDemoScenarioPaused,
            guideTopicID: "diagnostics",
            openGuide: { viewModel.openGuide(topicID: $0, sourceWorkspace: .reports) },
            runDemo: { viewModel.startDemoScenario(for: .reports) }
        ) {
            DeploymentSimpleTable(
                rows: viewModel.dashboardProjection.allKPIs.map {
                    DeploymentSimpleRow(id: $0.id, title: $0.displayName, subtitle: $0.category, state: "\($0.value)")
                },
                emptyMessage: "No Demo dashboard metrics are available."
            )
        }
    }
}

// Shared row model for lightweight workspace tables. Larger interactive grids
// should use the Workbench projection types instead.
struct DeploymentSimpleRow: Identifiable {
    let id: String
    let title: String
    let subtitle: String
    let state: String
}

// Reusable table for simple lists throughout the module. The optional archive
// action keeps destructive-looking controls explicit and only appears on
// workspaces that pass an archive handler.
struct DeploymentSimpleTable: View {
    let rows: [DeploymentSimpleRow]
    let emptyMessage: String
    var archiveAction: ((String) -> Void)?

    init(
        rows: [DeploymentSimpleRow],
        emptyMessage: String,
        archiveAction: ((String) -> Void)? = nil
    ) {
        self.rows = rows
        self.emptyMessage = emptyMessage
        self.archiveAction = archiveAction
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if rows.isEmpty {
                Text(emptyMessage)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .padding(16)
            } else {
                ForEach(rows) { row in
                    HStack(spacing: ForsettiTheme.Spacing.item) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(row.title)
                                .font(.callout.weight(.semibold))
                            if !row.subtitle.isEmpty {
                                Text(row.subtitle)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        Spacer()
                        DeploymentStatePill(value: row.state)
                        if let archiveAction {
                            Button {
                                archiveAction(row.id)
                            } label: {
                                Image(systemName: "archivebox")
                            }
                            .buttonStyle(.borderless)
                            .help("Archive Demo Record")
                        }
                    }
                    .padding(12)
                    Divider()
                }
            }
        }
        .forsettiCardSurface()
    }
}

// Visual state indicator for simple rows. It turns common active, blocked,
// warning, shipping, archived, and neutral states into scannable icon pills.
private struct DeploymentStatePill: View {
    let value: String

    var body: some View {
        Label(value, systemImage: systemImage)
            .font(.caption.weight(.medium))
            .foregroundStyle(color)
            .lineLimit(1)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(color.opacity(0.12))
            .clipShape(Capsule())
            .accessibilityElement(children: .combine)
    }

    private var normalizedValue: String {
        value.lowercased()
    }

    private var systemImage: String {
        if normalizedValue.contains("active") || normalizedValue.contains("ready") || normalizedValue.contains("complete") || normalizedValue.contains("valid") {
            return "checkmark.circle"
        }
        if normalizedValue.contains("blocked") || normalizedValue.contains("failed") || normalizedValue.contains("exception") || normalizedValue.contains("missing") {
            return "xmark.octagon"
        }
        if normalizedValue.contains("warning") || normalizedValue.contains("pending") || normalizedValue.contains("review") {
            return "exclamationmark.triangle"
        }
        if normalizedValue.contains("shipped") || normalizedValue.contains("delivered") {
            return "shippingbox"
        }
        if normalizedValue.contains("archived") || normalizedValue.contains("retired") {
            return "archivebox"
        }
        return "circle.fill"
    }

    private var color: Color {
        if normalizedValue.contains("active") || normalizedValue.contains("ready") || normalizedValue.contains("complete") || normalizedValue.contains("valid") {
            return .green
        }
        if normalizedValue.contains("blocked") || normalizedValue.contains("failed") || normalizedValue.contains("exception") || normalizedValue.contains("missing") {
            return .red
        }
        if normalizedValue.contains("warning") || normalizedValue.contains("pending") || normalizedValue.contains("review") {
            return .orange
        }
        return .secondary
    }
}

// Validation summary for Jamf Inventory Preload. Detailed validation issue
// objects are already produced by the validator, so this view focuses on a
// compact operator-readable presentation.
private struct DeploymentPreloadValidationView: View {
    let result: JamfInventoryPreloadValidationResult

    var body: some View {
        VStack(alignment: .leading, spacing: ForsettiTheme.Spacing.compact) {
            Label("Demo Validation Results", systemImage: result.isReadyForUpload ? "checkmark.circle" : "exclamationmark.triangle")
                .font(.headline)
            Text("\(result.readyDeviceIds.count) ready, \(result.blockedIssues.count) blocked, \(result.warningIssues.count) warnings.")
                .font(.callout)
                .foregroundStyle(.secondary)
            ForEach(result.blockedIssues + result.warningIssues) { issue in
                Label(issue.message, systemImage: issue.severity == .warning ? "exclamationmark.triangle" : "xmark.octagon")
                    .font(.callout)
            }
        }
        .padding(14)
        .forsettiCardSurface()
    }
}

// Monospaced preview block used for generated Jamf and SD+ CSV text. It is a
// read-only inspection surface and leaves file writing or upload behavior to the
// corresponding services.
private struct DeploymentPreloadPreviewView: View {
    let title: String
    let text: String

    var body: some View {
        VStack(alignment: .leading, spacing: ForsettiTheme.Spacing.compact) {
            Label(title, systemImage: "doc.plaintext")
                .font(.headline)
            ScrollView([.horizontal, .vertical]) {
                Text(text.isEmpty ? "No Demo output" : text)
                    .font(.system(.caption, design: .monospaced))
                    .textSelection(.enabled)
                    .padding(10)
            }
            .frame(minHeight: 120, maxHeight: 240)
            .background(ForsettiTheme.groupedSurface)
            .clipShape(RoundedRectangle(cornerRadius: ForsettiTheme.Radius.card, style: .continuous))
        }
        .padding(14)
        .forsettiCardSurface()
    }
}
