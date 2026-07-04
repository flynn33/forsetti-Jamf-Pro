import Foundation

nonisolated enum DeploymentDemoActionKind: String, Codable, CaseIterable, Sendable {
    case navigate
    case inspect
    case preview
    case simulate
    case validate
    case export
    case configure
    case guide
    case complete
}

nonisolated enum DeploymentDemoHighlightTarget: String, Codable, CaseIterable, Sendable {
    case dashboardHero
    case scenarioCards
    case workbenchGrid
    case layoutToolbar
    case intakePreview
    case abmVerification
    case jamfLookup
    case jamfSubmission
    case sdPlusPreview
    case shipmentsTable
    case exceptionDrawer
    case recordsArchive
    case administrationCatalog
    case guidePanel
    case resultCard
}

nonisolated struct DeploymentDemoStep: Identifiable, Codable, Equatable, Sendable {
    let id: String
    let title: String
    let body: String
    let highlightTarget: DeploymentDemoHighlightTarget
    let actionKind: DeploymentDemoActionKind
    let expectedResult: String
}

nonisolated struct DeploymentDemoScenario: Identifiable, Codable, Equatable, Sendable {
    let id: String
    let title: String
    let summary: String
    let workspace: DeploymentTrackerWorkspace
    let systemImage: String
    let steps: [DeploymentDemoStep]
    let expectedResult: String
    let relatedGuideTopicID: String
    let productionEquivalent: String

    var stepTitles: [String] {
        steps.map(\.title)
    }
}

nonisolated enum DeploymentDemoScenarioCatalog {
    static let requiredScenarioIDs: Set<String> = [
        "quick-start-tour",
        "dashboard-operations-overview",
        "in-progress-workbench",
        "customize-columns-layouts",
        "intake-import-preview",
        "abm-verification-simulation",
        "jamf-preload-initial",
        "jamf-preload-update",
        "sdplus-export-simulation",
        "shipping-returns-simulation",
        "exceptions-validation-recovery",
        "records-management-archive",
        "administration-field-catalog",
        "stakeholder-value-tour"
    ]

    static let scenarios: [DeploymentDemoScenario] = [
        DeploymentDemoScenario(
            id: "quick-start-tour",
            title: "Quick Start Tour",
            summary: "Start at the dashboard, read the DEMO safety labels, and run the first guided path with deterministic Dummy data only.",
            workspace: .dashboard,
            systemImage: "play.rectangle",
            steps: [
                step("Confirm Demo boundary", "Find Deployment Tracker Demo, DEMO, COMING SOON, Dummy data only, and No live Jamf actions in the module chrome.", .dashboardHero, .inspect, "The operator can identify the safe installed module before pressing any action."),
                step("Open guided controls", "Select Start Guided Demo from the hero or a scenario card.", .scenarioCards, .navigate, "The overlay opens with progress, Back, Next, Skip, Finish, Pause, Resume, and Open Guide controls."),
                step("Preview the active record set", "Review the deterministic project and device counts without importing external information.", .dashboardHero, .preview, "The demo explains that every visible row is seeded dummy data."),
                step("Finish the tour", "Complete the scenario and review the completion message.", .resultCard, .complete, "The result confirms no live Jamf actions and no external data changes.")
            ],
            expectedResult: "A new user understands the installed Demo boundary and can safely start a guided scenario.",
            relatedGuideTopicID: "start-here",
            productionEquivalent: "Production onboarding will point to governed setup and permission checks after the module is explicitly enabled outside demo mode."
        ),
        DeploymentDemoScenario(
            id: "dashboard-operations-overview",
            title: "Dashboard Operations Overview",
            summary: "Scan operational KPIs, exception counts, preload readiness, and export readiness from the Demo dashboard.",
            workspace: .dashboard,
            systemImage: "chart.xyaxis.line",
            steps: [
                step("Read KPI rings", "Review the dashboard projection for deterministic Demo inventory and project status.", .dashboardHero, .inspect, "The dashboard shows seeded operational totals only."),
                step("Open scenario cards", "Compare the guided scenario cards and choose the next workflow to demonstrate.", .scenarioCards, .navigate, "Scenario cards route to the relevant workspace without starting live work."),
                step("Check safety notice", "Verify the dashboard repeats Dummy data only and No live Jamf actions.", .dashboardHero, .inspect, "The safety boundary remains visible at the point of action."),
                step("Run dashboard action", "Use Run Demo to generate a simulated dashboard result card.", .resultCard, .simulate, "The result card records externalDataChanged as false.")
            ],
            expectedResult: "Stakeholders see the future operational dashboard without any production connection.",
            relatedGuideTopicID: "dashboard",
            productionEquivalent: "Production dashboards will project approved local tracker data and governed integration snapshots."
        ),
        DeploymentDemoScenario(
            id: "in-progress-workbench",
            title: "In-Progress Workbench",
            summary: "Review the main technician grid, row selection, validation drawer, and safe simulated batch actions.",
            workspace: .inProgress,
            systemImage: "tablecells",
            steps: [
                step("Open the workbench", "Navigate to the Demo Workbench from the sidebar or Run Demo.", .workbenchGrid, .navigate, "The workbench renders seeded active Demo devices."),
                step("Select a Demo row", "Select a deterministic serial such as DEMO-MAC-0001 or the first visible row.", .workbenchGrid, .inspect, "The inspector shows local Tracker values and read-only upstream snapshots."),
                step("Preview validation", "Run Preview Demo Validation from the toolbar.", .exceptionDrawer, .validate, "Validation results are local and do not contact Jamf."),
                step("Open guidance", "Use Open Guide from the overlay for the workbench topic.", .guidePanel, .guide, "The guide opens to the workbench instructions.")
            ],
            expectedResult: "Technicians can practice the primary workbench flow safely with dummy data.",
            relatedGuideTopicID: "workbench",
            productionEquivalent: "Production workbench actions will remain gated by validation, audit events, and explicit integration enablement."
        ),
        DeploymentDemoScenario(
            id: "customize-columns-layouts",
            title: "Customize Columns and Layouts",
            summary: "Demonstrate field visibility, width, pinning, ordering, layout save, and layout restore behavior.",
            workspace: .inProgress,
            systemImage: "rectangle.grid.2x2",
            steps: [
                step("Open column tools", "Select Customize Columns from the workbench.", .layoutToolbar, .configure, "The field catalog opens without modifying external systems."),
                step("Toggle a Demo field", "Hide or show a noncritical Demo column.", .administrationCatalog, .configure, "The projection updates locally."),
                step("Save a layout copy", "Save a personal Demo layout copy.", .layoutToolbar, .preview, "The layout is recorded in the local Demo store."),
                step("Restore defaults", "Reset the workbook-inspired layout.", .layoutToolbar, .complete, "The seeded default column order returns.")
            ],
            expectedResult: "Layout management is demonstrated as local tracker configuration only.",
            relatedGuideTopicID: "field-catalog",
            productionEquivalent: "Production layout changes will persist to local tracker storage and will not edit Jamf, ABM, or SD+."
        ),
        DeploymentDemoScenario(
            id: "intake-import-preview",
            title: "Intake Import Preview",
            summary: "Preview vendor, serial list, and workbook migration intake without committing imported records.",
            workspace: .intakeImports,
            systemImage: "tray.and.arrow.down",
            steps: [
                step("Open imports", "Navigate to Intake / Imports Demo.", .intakePreview, .navigate, "The workspace presents preview-only import actions."),
                step("Preview vendor rows", "Run Preview Demo Vendor Import.", .intakePreview, .preview, "A deterministic import summary appears with no external data changes."),
                step("Preview workbook migration", "Run Preview Demo Workbook Migration.", .intakePreview, .preview, "The migration preview describes local staging behavior."),
                step("Review conflicts", "Open the related guide topic for duplicate and conflict handling.", .guidePanel, .guide, "The operator sees how production conflict resolution will be governed.")
            ],
            expectedResult: "Import behavior is demonstrated without committing live or external data.",
            relatedGuideTopicID: "imports",
            productionEquivalent: "Production intake will stage files, validate conflicts, and require an explicit commit path before tracker records are created."
        ),
        DeploymentDemoScenario(
            id: "abm-verification-simulation",
            title: "ABM Verification Simulation",
            summary: "Run read-only Apple Business verification and review local Demo exceptions.",
            workspace: .abmVerification,
            systemImage: "checkmark.shield",
            steps: [
                step("Open ABM verification", "Navigate to Demo ABM Verification.", .abmVerification, .navigate, "Only read-only simulation controls are visible."),
                step("Simulate ABM Verification", "Run Demo ABM Check for selected records.", .abmVerification, .simulate, "Local exceptions are queued from seeded ABM snapshot data."),
                step("Review mismatches", "Inspect MDM assignment or enrollment mismatches.", .exceptionDrawer, .inspect, "The mismatch list remains local to the Demo store."),
                step("Confirm no ABM mutation", "Verify there are no assign, release, edit, or delete ABM controls.", .abmVerification, .validate, "The workspace cannot change ABM data.")
            ],
            expectedResult: "ABM behavior is shown as verification-only and no Apple Business data changes.",
            relatedGuideTopicID: "abm-verification",
            productionEquivalent: "Production ABM verification will consume governed read-only snapshots and send remediation outside this module."
        ),
        DeploymentDemoScenario(
            id: "jamf-preload-initial",
            title: "Jamf Preload Initial",
            summary: "Simulate an initial Jamf Inventory Preload validation and submission path for new Demo devices.",
            workspace: .jamfPreload,
            systemImage: "arrow.up.doc",
            steps: [
                step("Open preload", "Navigate to Jamf Preload Demo.", .jamfLookup, .navigate, "The lookup and submission cards are labeled as simulations."),
                step("Lookup a serial", "Enter a Demo serial and run Simulate Serial Lookup.", .jamfLookup, .simulate, "The demo client returns deterministic preload data."),
                step("Preview validation", "Run Preview Demo Validation.", .jamfSubmission, .validate, "Validation prepares a CSV preview locally."),
                step("Simulate submission", "Run Simulate Jamf Preload Submission.", .jamfSubmission, .simulate, "A local submission record is created; no live Jamf actions are run.")
            ],
            expectedResult: "The initial preload flow creates only local Demo submission history.",
            relatedGuideTopicID: "jamf-preload",
            productionEquivalent: "Production preload submission will require explicit non-demo mode plus approved Jamf Inventory Preload privileges."
        ),
        DeploymentDemoScenario(
            id: "jamf-preload-update",
            title: "Jamf Preload Update",
            summary: "Compare deterministic current preload values with proposed tracker updates and preview supersedence.",
            workspace: .jamfPreload,
            systemImage: "arrow.triangle.2.circlepath",
            steps: [
                step("Choose an update record", "Enter DEMO-IPAD-0021 or select a seeded Demo row.", .jamfLookup, .inspect, "The current and proposed values are deterministic."),
                step("Preview update batch", "Run Preview Demo Update Batch.", .jamfSubmission, .preview, "The batch shows what would supersede in production."),
                step("Simulate reconciliation", "Run Simulate Reconciliation after the preview.", .jamfSubmission, .simulate, "The demo records a reconciliation result locally."),
                step("Confirm safety", "Read the result card and verify No live Jamf actions.", .resultCard, .validate, "No Jamf data was changed.")
            ],
            expectedResult: "Update/supersedence behavior is visible without sending data to Jamf.",
            relatedGuideTopicID: "preload-updates",
            productionEquivalent: "Production update batches will use approved Jamf privileges only after validation and operator review."
        ),
        DeploymentDemoScenario(
            id: "sdplus-export-simulation",
            title: "SD+ Export Simulation",
            summary: "Generate a Demo ServiceDesk Plus export preview and local export history.",
            workspace: .sdPlusExport,
            systemImage: "square.and.arrow.up",
            steps: [
                step("Open SD+ export", "Navigate to SD+ Export Demo.", .sdPlusPreview, .navigate, "The workspace presents preview and generate actions."),
                step("Preview rows", "Run Preview Demo Export.", .sdPlusPreview, .preview, "The CSV preview is generated from seeded rows."),
                step("Generate export history", "Run Generate Demo SD+ Export Preview.", .sdPlusPreview, .export, "A local export job appears in history."),
                step("Review no SD+ change", "Inspect the result text for no SD+ data changed.", .resultCard, .validate, "No ServiceDesk Plus data was changed.")
            ],
            expectedResult: "The export workflow demonstrates template output without contacting SD+.",
            relatedGuideTopicID: "sdplus-export",
            productionEquivalent: "Production SD+ export will generate governed files for import rather than editing SD+ directly."
        ),
        DeploymentDemoScenario(
            id: "shipping-returns-simulation",
            title: "Shipping and Returns Simulation",
            summary: "Review shipment states, return candidates, and local delivery confirmation fields.",
            workspace: .shipments,
            systemImage: "shippingbox",
            steps: [
                step("Open shipments", "Navigate to Shipments Demo.", .shipmentsTable, .navigate, "Seeded shipment records are visible."),
                step("Inspect tracking fields", "Review tracking number, delivery confirmation, and shipping state.", .shipmentsTable, .inspect, "Values are deterministic dummy records."),
                step("Find return states", "Filter or scan for returned and blocked shipment records.", .shipmentsTable, .preview, "Return candidates are visible without carrier calls."),
                step("Open shipping guide", "Open the shipments guide topic.", .guidePanel, .guide, "The guide describes production shipping governance.")
            ],
            expectedResult: "Shipping and returns are demonstrated as local status tracking only.",
            relatedGuideTopicID: "shipments",
            productionEquivalent: "Production shipping integrations, if added, will require separate governed carrier authorization."
        ),
        DeploymentDemoScenario(
            id: "exceptions-validation-recovery",
            title: "Exceptions Validation Recovery",
            summary: "Demonstrate blocked rows, warning rows, local exception review, and retry guidance.",
            workspace: .inProgress,
            systemImage: "exclamationmark.triangle",
            steps: [
                step("Open validation drawer", "Run Preview Demo Validation from the workbench.", .exceptionDrawer, .validate, "Seeded blockers and warnings appear when present."),
                step("Inspect exception details", "Review local exception reason codes and affected records.", .exceptionDrawer, .inspect, "Exception data remains in the local Demo store."),
                step("Open recovery guide", "Use Open Guide to view exception resolution steps.", .guidePanel, .guide, "The guide suggests safe local remediation."),
                step("Retry preview", "Run the preview action again after reviewing the guidance.", .resultCard, .simulate, "The retry remains a local simulation.")
            ],
            expectedResult: "Operators can practice validation recovery without changing upstream systems.",
            relatedGuideTopicID: "exceptions-validation",
            productionEquivalent: "Production validation recovery will continue to block integration actions until required fields and exceptions are resolved."
        ),
        DeploymentDemoScenario(
            id: "records-management-archive",
            title: "Records Management Archive",
            summary: "Preview archive-first governance, records package generation, and deletion impact review.",
            workspace: .recordsManagement,
            systemImage: "archivebox",
            steps: [
                step("Open records", "Navigate to Records Management Demo.", .recordsArchive, .navigate, "Archive and package preview controls are visible."),
                step("Generate package", "Run Generate Demo Records Package.", .recordsArchive, .export, "A deterministic local records package is created."),
                step("Preview deletion review", "Run Preview Demo Deletion Review.", .recordsArchive, .preview, "The impact review explains production deletion is coming soon."),
                step("Confirm archive-first policy", "Read the guide topic for export-before-delete requirements.", .guidePanel, .guide, "The operator sees that hard deletion is not available from the Demo.")
            ],
            expectedResult: "Records governance is demonstrated through local archive/export behavior only.",
            relatedGuideTopicID: "records-management",
            productionEquivalent: "Production records management will require export-before-delete and explicit deletion governance."
        ),
        DeploymentDemoScenario(
            id: "administration-field-catalog",
            title: "Administration Field Catalog",
            summary: "Review reference values, workflow statuses, custom fields, and guide terminology.",
            workspace: .administration,
            systemImage: "slider.horizontal.3",
            steps: [
                step("Open administration", "Navigate to Administration Demo.", .administrationCatalog, .navigate, "Reference values and workflow statuses are visible."),
                step("Review field ownership", "Open the guide and inspect source-of-truth terminology.", .guidePanel, .guide, "Read-only fields are clearly distinguished from Tracker-owned fields."),
                step("Compare workflow statuses", "Scan the workflow status reference values.", .administrationCatalog, .inspect, "Seeded statuses explain the deployment lifecycle."),
                step("Return to workbench", "Navigate back to the workbench and open the field catalog.", .layoutToolbar, .configure, "Administration context connects to layout configuration.")
            ],
            expectedResult: "Administrators see the future configuration surface without production writes.",
            relatedGuideTopicID: "glossary",
            productionEquivalent: "Production administration will govern field definitions and references through explicit admin workflows."
        ),
        DeploymentDemoScenario(
            id: "stakeholder-value-tour",
            title: "Stakeholder Value Tour",
            summary: "Walk a non-technical stakeholder through dashboard value, integrations, exceptions, and reporting.",
            workspace: .dashboard,
            systemImage: "person.3.sequence",
            steps: [
                step("Start on dashboard value", "Show deployment totals, ready counts, blockers, and upcoming integration areas.", .dashboardHero, .inspect, "Stakeholders see the intended operating model."),
                step("Show workbench control", "Open the workbench and highlight row-level readiness.", .workbenchGrid, .navigate, "The operational control plane is visible."),
                step("Show integration safety", "Open Jamf Preload or SD+ Export and point to simulation labels.", .jamfSubmission, .inspect, "Stakeholders see the safety boundary before production enablement."),
                step("Show governance", "Open Records Management and Reports Demo.", .recordsArchive, .complete, "The tour ends on archive, reporting, and audit value.")
            ],
            expectedResult: "Stakeholders understand the product direction while seeing that this installed module is Demo-only.",
            relatedGuideTopicID: "what-this-demo-shows",
            productionEquivalent: "Production stakeholder workflows will connect governed integrations, reporting, and records controls after acceptance."
        )
    ]

    static func scenario(id: String) -> DeploymentDemoScenario? {
        let normalized = legacyScenarioAliases[id] ?? id
        return scenarios.first { $0.id == normalized }
    }

    static func scenario(for workspace: DeploymentTrackerWorkspace) -> DeploymentDemoScenario? {
        switch workspace {
        case .dashboard:
            return scenario(id: "dashboard-operations-overview")
        case .inProgress:
            return scenario(id: "in-progress-workbench")
        case .projects:
            return scenario(id: "stakeholder-value-tour")
        case .devices:
            return scenario(id: "in-progress-workbench")
        case .intakeImports:
            return scenario(id: "intake-import-preview")
        case .jamfPreload:
            return scenario(id: "jamf-preload-initial")
        case .abmVerification:
            return scenario(id: "abm-verification-simulation")
        case .sdPlusExport:
            return scenario(id: "sdplus-export-simulation")
        case .shipments:
            return scenario(id: "shipping-returns-simulation")
        case .reports:
            return scenario(id: "stakeholder-value-tour")
        case .appleCatalog:
            return scenario(id: "administration-field-catalog")
        case .administration:
            return scenario(id: "administration-field-catalog")
        case .recordsManagement:
            return scenario(id: "records-management-archive")
        case .guide:
            return scenario(id: "quick-start-tour")
        }
    }

    private static let legacyScenarioAliases: [String: String] = [
        "full_deployment_flow": "quick-start-tour",
        "jamf_preload_supersedence": "jamf-preload-update",
        "abm_mismatch_handling": "abm-verification-simulation",
        "sdplus_export_and_shipping": "sdplus-export-simulation"
    ]

    private static func step(
        _ title: String,
        _ body: String,
        _ highlightTarget: DeploymentDemoHighlightTarget,
        _ actionKind: DeploymentDemoActionKind,
        _ expectedResult: String
    ) -> DeploymentDemoStep {
        DeploymentDemoStep(
            id: title
                .lowercased()
                .replacingOccurrences(of: " ", with: "-")
                .replacingOccurrences(of: "/", with: "-"),
            title: title,
            body: body,
            highlightTarget: highlightTarget,
            actionKind: actionKind,
            expectedResult: expectedResult
        )
    }
}
