import SwiftUI

// MARK: - Tracker Guide content model
//
// The internal guide is stored as code so it ships with the module, works
// offline, and can be opened from any workspace or structured error. Each topic
// includes enough metadata for search, sidebar navigation, workspace deep links,
// related-topic buttons, and future validation that confirms required topics are
// present.
nonisolated struct DeploymentTrackerGuideTopic: Identifiable, Equatable, Sendable {
    let id: String
    let title: String
    let summary: String
    let keywords: [String]
    let relatedWorkspace: DeploymentTrackerWorkspace?
    let steps: [String]
    let expectedResult: String
    let details: [String]
    let relatedTopicIds: [String]

    // Search uses one normalized text blob so the view model can keep search
    // deterministic and local. This intentionally includes hidden keywords in
    // addition to the visible title, summary, steps, and details.
    var searchableText: String {
        ([id, title, summary, expectedResult] + keywords + steps + details)
            .joined(separator: " ")
            .lowercased()
    }
}

// Central repository for Tracker Guide topics. Keeping the topic definitions in
// one place makes it clear which workflows are documented and gives tests a
// simple target for checking topic coverage.
nonisolated enum DeploymentTrackerGuideContent {
    // Required topic ids describe the minimum guide surface the module expects.
    // If new workspaces or structured errors are added, this list should grow
    // with matching topic definitions below.
    static let requiredTopicIDs: [String] = [
        "start-here",
        "what-this-demo-shows",
        "why-demo-mode",
        "dashboard",
        "workbench",
        "field-catalog",
        "customize-columns",
        "projects",
        "devices",
        "device-detail",
        "imports",
        "jamf-preload",
        "preload-updates",
        "scenario-full-deployment-flow",
        "scenario-jamf-preload-supersedence",
        "scenario-abm-mismatch-handling",
        "scenario-sdplus-export-and-shipping",
        "abm-verification",
        "sdplus-export",
        "shipments",
        "apple-catalog",
        "administration",
        "exceptions-validation",
        "records-management",
        "jamf-permissions",
        "diagnostics",
        "coming-soon-roadmap",
        "glossary"
    ]

    // Topics are ordered for first-use flow: start with orientation, then move
    // through the active workbench, source integrations, exports, records, and
    // troubleshooting. Each topic stays self-contained so it can be opened from
    // a modal sheet, the Guide workspace, or an error recovery link.
    static let topics: [DeploymentTrackerGuideTopic] = [
        topic(
            id: "start-here",
            title: "Start Here",
            summary: "Deployment Tracker Demo is a COMING SOON interactive preview that uses Dummy data only and runs no live Jamf actions.",
            keywords: ["overview", "first time", "workflow", "tracker", "demo", "coming soon"],
            relatedWorkspace: .dashboard,
            steps: [
                "Open Demo Dashboard to review project and inventory totals.",
                "Choose an Interactive Demo scenario.",
                "Open Demo Projects and confirm or create a Demo project.",
                "Open Demo Imports or Demo Devices to add deployment records.",
                "Open Demo Workbench to work active Demo devices.",
                "Preview Demo validation before running simulated Jamf, ABM, or SD+ actions.",
                "Use Demo Jamf Preload to simulate Inventory Preload behavior with no live Jamf actions.",
                "Use Demo SD+ Export to generate preview CSV data.",
                "Use Demo Records Management for archive, restore, export, and controlled deletion preview."
            ],
            expectedResult: "You can see what the upcoming Deployment Tracker will do while staying inside deterministic Demo data.",
            details: [
                "Tracker records in this build are Demo operational records. External ABM and Jamf values are Demo snapshots and remain read-only.",
                "The In-Progress Workbench is the primary place to review rows, edit local Demo values, validate, and run simulated actions.",
                "No live Jamf, ABM, ServiceDesk Plus, shipping, or production records are changed by this Demo."
            ],
            relatedTopicIds: ["what-this-demo-shows", "why-demo-mode", "dashboard"]
        ),
        topic(
            id: "what-this-demo-shows",
            title: "What This Demo Shows",
            summary: "A guided preview of the coming Deployment Tracker workflows using deterministic Dummy data only.",
            keywords: ["demo", "interactive preview", "coming soon", "scenario"],
            relatedWorkspace: .dashboard,
            steps: [
                "Start on Demo Dashboard.",
                "Choose Full Deployment Flow, Jamf Preload Supersedence, ABM Mismatch Handling, or SD+ Export and Shipping.",
                "Use Run Interactive Demo or Run Demo to step through the scenario.",
                "Review result cards after each simulation.",
                "Confirm every result says Dummy data only and no live Jamf actions."
            ],
            expectedResult: "The Demo illustrates the workflow without reaching live systems.",
            details: [
                "The seed includes 120 Demo devices, six Demo projects, 40+ reference values, 20+ workflow statuses, four layouts, snapshots, submissions, export jobs, shipments, exceptions, audit events, and catalog entries.",
                "Serials, emails, tickets, and tracking values use deterministic Demo patterns such as DEMO-MAC-0001 and example.invalid."
            ],
            relatedTopicIds: ["scenario-full-deployment-flow", "why-demo-mode", "glossary"]
        ),
        topic(
            id: "why-demo-mode",
            title: "Why Demo Mode",
            summary: "Demo mode keeps the installed module safe while the production architecture remains under development.",
            keywords: ["safe", "no live jamf", "demo data only", "production equivalent"],
            relatedWorkspace: .dashboard,
            steps: [
                "Open any workspace.",
                "Find the DEMO, COMING SOON, Interactive preview, Dummy data only, and No live Jamf actions labels.",
                "Use Simulate, Preview Demo, Run Demo, Generate Demo, or Reset Demo controls.",
                "Review production-equivalent wording on result cards.",
                "Do not treat Demo output as a live operational change."
            ],
            expectedResult: "Every normal UI path stays in Demo mode and communicates the safety boundary.",
            details: [
                "The installed module defaults to Demo mode.",
                "Live Jamf Inventory Preload reads and writes are replaced by a non-network Demo client.",
                "Production enablement will require explicit future wiring outside this Demo path."
            ],
            relatedTopicIds: ["jamf-preload", "coming-soon-roadmap"]
        ),
        topic(
            id: "dashboard",
            title: "Dashboard",
            summary: "Use the Dashboard to understand totals, integration health, blocked work, and next tasks.",
            keywords: ["kpi", "task cards", "totals", "blocked", "ready"],
            relatedWorkspace: .dashboard,
            steps: [
                "Open Deployment Tracker.",
                "Select Dashboard.",
                "Review inventory totals, project totals, and status indicators.",
                "Use the task cards to open the related workspace.",
                "Use Guide on a task when you need the step-by-step workflow."
            ],
            expectedResult: "The Dashboard gives you a starting point and directs you to the next workspace.",
            details: [
                "Task cards are organized by technician intent, not implementation details.",
                "KPIs show operational health while task cards move you to the work area that can resolve the issue."
            ],
            relatedTopicIds: ["workbench", "projects", "exceptions-validation"]
        ),
        topic(
            id: "workbench",
            title: "In-Progress Workbench",
            summary: "Use the configurable grid to work active deployment devices without leaving Tracker.",
            keywords: ["grid", "active devices", "filter", "inspector", "validate"],
            relatedWorkspace: .inProgress,
            steps: [
                "Open In-Progress Workbench.",
                "Use the filter box to find a serial, project, location, user, or status.",
                "Select a row to open the inspector.",
                "Review validation status and exceptions.",
                "Edit local fields where allowed.",
                "Run actions such as Preview Demo Validation, Run Demo ABM Verification, Simulate Jamf Preload Submission, or Generate Demo SD+ Export Preview."
            ],
            expectedResult: "You can manage active devices without leaving the workbench.",
            details: [
                "Fields from ABM and Jamf snapshots are read-only. You can view them, refresh snapshots, and create exceptions from mismatches, but Tracker does not edit external source-of-truth data.",
                "Column order, width, visibility, and pinned state come from saved Workbench layouts."
            ],
            relatedTopicIds: ["customize-columns", "jamf-preload", "exceptions-validation"]
        ),
        topic(
            id: "customize-columns",
            title: "Customize Workbench Columns",
            summary: "Use the Field Catalog and column headers to make the Workbench match your workflow.",
            keywords: ["field catalog", "columns", "layout", "drag", "pin", "resize"],
            relatedWorkspace: .inProgress,
            steps: [
                "Open In-Progress Workbench.",
                "Click Customize Columns.",
                "Search for a field by name, category, source, or type.",
                "Turn fields on or off.",
                "Drag column headers to reorder visible columns.",
                "Resize, pin, or unpin columns as needed.",
                "Save the layout if you want to keep the change."
            ],
            expectedResult: "Your workbench shows the columns that match your workflow.",
            details: [
                "Arrow buttons remain available in the Field Catalog for precise fallback reordering.",
                "Reset to Workbook Default restores the default order based on the old workbook layout, with Serial first."
            ],
            relatedTopicIds: ["workbench", "dashboard"]
        ),
        topic(
            id: "field-catalog",
            title: "Field Catalog",
            summary: "Use the Demo Field Catalog to inspect available fields, source-of-truth labels, visibility, pinning, and layout behavior.",
            keywords: ["field catalog", "demo", "columns", "source of truth", "layout"],
            relatedWorkspace: .inProgress,
            steps: [
                "Open Demo Workbench.",
                "Click Customize Columns.",
                "Search for fields by display name, key, category, source, or type.",
                "Toggle Demo fields on or off.",
                "Pin or reorder visible Demo fields.",
                "Save or reset the Demo layout."
            ],
            expectedResult: "The Demo grid changes layout without touching live Jamf, ABM, or SD+ systems.",
            details: [
                "Source-of-truth labels identify local Tracker fields, Demo snapshots, and derived values.",
                "Layout changes are local to the Demo store."
            ],
            relatedTopicIds: ["customize-columns", "workbench"]
        ),
        topic(
            id: "projects",
            title: "Projects",
            summary: "Projects organize devices and define the workflow context used by Tracker actions.",
            keywords: ["project", "code", "ticket", "defaults", "gates"],
            relatedWorkspace: .projects,
            steps: [
                "Open Projects.",
                "Enter the project name.",
                "Add a project code or ticket number if needed.",
                "Create the project.",
                "Assign devices to the project from Devices or the Workbench."
            ],
            expectedResult: "The project is available for device assignment.",
            details: [
                "Project changes should not silently overwrite existing device records.",
                "Project policy can drive workflow gates for ABM, Jamf Preload, SD+, shipping, and completion as those controls are enabled."
            ],
            relatedTopicIds: ["devices", "workbench"]
        ),
        topic(
            id: "devices",
            title: "Devices",
            summary: "Devices are local Demo Tracker records for Apple equipment.",
            keywords: ["serial", "asset tag", "manual add", "edit", "demo"],
            relatedWorkspace: .devices,
            steps: [
                "Open Demo Devices or Demo Workbench.",
                "Add a serial number.",
                "Add an asset tag if known.",
                "Save the device.",
                "Select the device in the Demo Workbench to complete project, model, location, user, and notes fields."
            ],
            expectedResult: "The Demo device appears in Tracker and can be validated for simulated workflow actions.",
            details: [
                "Serial numbers are normalized so active records remain unique.",
                "Local Demo changes are audited and used for Tracker workflow, Jamf preload simulation, SD+ preview, and reporting."
            ],
            relatedTopicIds: ["device-detail", "imports", "workbench"]
        ),
        topic(
            id: "device-detail",
            title: "Device Detail",
            summary: "Inspect a selected Demo device in the Workbench inspector and compare editable local fields with read-only Demo snapshots.",
            keywords: ["device detail", "inspector", "demo", "read only"],
            relatedWorkspace: .inProgress,
            steps: [
                "Open Demo Workbench.",
                "Select DEMO-MAC-0001 or another Demo row.",
                "Review the inspector categories.",
                "Edit only Tracker-owned Demo fields.",
                "Use read-only Demo snapshot fields to understand Jamf, ABM, SD+, and catalog context."
            ],
            expectedResult: "You can inspect a Demo device without changing live Jamf or ABM data.",
            details: [
                "Read-only snapshot fields are intentionally not editable.",
                "The Demo inspector supports training and review for the Coming Soon production workflow."
            ],
            relatedTopicIds: ["workbench", "field-catalog", "why-demo-mode"]
        ),
        topic(
            id: "imports",
            title: "Imports",
            summary: "Bring in vendor data, serial lists, catalog files, or workbook migration data through preview-first workflows.",
            keywords: ["vendor", "csv", "serial list", "workbook migration", "preview"],
            relatedWorkspace: .intakeImports,
            steps: [
                "Open Imports.",
                "Choose the import preview that matches the source data.",
                "Review rows before committing data.",
                "Resolve duplicate serials, missing fields, or unknown reference values.",
                "Commit only after the preview is clean."
            ],
            expectedResult: "Tracker creates or updates device records and records an import batch.",
            details: [
                "Workbook migration does not import formulas, Run Sync behavior, or Run Clear behavior.",
                "Imports should be previewed before data is written."
            ],
            relatedTopicIds: ["devices", "workbench", "exceptions-validation"]
        ),
        topic(
            id: "jamf-preload",
            title: "Jamf Inventory Preload",
            summary: "Simulate Inventory Preload behavior in the Deployment Tracker Demo with no live Jamf actions.",
            keywords: ["jamf", "inventory preload", "submit", "direct", "csv", "demo", "simulate"],
            relatedWorkspace: .jamfPreload,
            steps: [
                "Select Demo devices in the Workbench or open Demo Jamf Preload.",
                "Click Preview Demo Validation.",
                "Fix missing Demo fields if validation blocks the request.",
                "Review the Demo preload summary.",
                "Click Simulate Jamf Preload Submission.",
                "Review Demo submission history and simulate reconciliation when needed."
            ],
            expectedResult: "Tracker records a simulated preload submission using Dummy data only. No live Jamf actions.",
            details: [
                "The Demo client does not contact Jamf.",
                "Production equivalent text explains how a future approved workflow would behave after explicit enablement."
            ],
            relatedTopicIds: ["preload-updates", "jamf-permissions", "exceptions-validation"]
        ),
        topic(
            id: "preload-updates",
            title: "Inventory Preload Updates",
            summary: "Preview how existing Jamf preload data would be superseded for matching Demo serial numbers.",
            keywords: ["update", "supersede", "serial", "lookup", "reconcile", "demo"],
            relatedWorkspace: .jamfPreload,
            steps: [
                "Open Demo Jamf Preload.",
                "Choose Simulate Serial Lookup or Simulate Batch Lookup.",
                "Enter DEMO-IPAD-0021 or another Demo serial number.",
                "Review deterministic Demo preload data.",
                "Select Demo devices to update.",
                "Review the supersedence preview.",
                "Run Demo update preview.",
                "Simulate reconciliation."
            ],
            expectedResult: "The Demo shows what would change without changing live Jamf data.",
            details: [
                "Common update reasons include location changes, building or room changes, department changes, user changes, asset tag changes, project reassignment, and certificate-related metadata updates."
            ],
            relatedTopicIds: ["jamf-preload", "jamf-permissions"]
        ),
        topic(
            id: "scenario-full-deployment-flow",
            title: "Scenario: Full Deployment Flow",
            summary: "Run the full Deployment Tracker Demo flow from Dashboard through validation, simulated preload, SD+ preview, shipments, and records.",
            keywords: ["scenario", "full deployment flow", "interactive demo"],
            relatedWorkspace: .dashboard,
            steps: DeploymentDemoScenarioCatalog.scenario(id: "full_deployment_flow")?.stepTitles ?? [],
            expectedResult: "The scenario creates Demo result cards and never changes live Jamf, ABM, SD+, shipping, or production records.",
            details: [
                DeploymentDemoScenarioCatalog.scenario(id: "full_deployment_flow")?.productionEquivalent ?? "Production equivalent is coming soon."
            ],
            relatedTopicIds: ["what-this-demo-shows", "workbench", "jamf-preload"]
        ),
        topic(
            id: "scenario-jamf-preload-supersedence",
            title: "Scenario: Jamf Preload Supersedence",
            summary: "Preview how deterministic Demo preload values compare with proposed Tracker values.",
            keywords: ["scenario", "jamf preload", "supersedence", "demo"],
            relatedWorkspace: .jamfPreload,
            steps: DeploymentDemoScenarioCatalog.scenario(id: "jamf_preload_supersedence")?.stepTitles ?? [],
            expectedResult: "The Demo shows preload differences for matching serials and reports that no live Jamf data changed.",
            details: [
                DeploymentDemoScenarioCatalog.scenario(id: "jamf_preload_supersedence")?.productionEquivalent ?? "Production equivalent is coming soon."
            ],
            relatedTopicIds: ["jamf-preload", "preload-updates"]
        ),
        topic(
            id: "scenario-abm-mismatch-handling",
            title: "Scenario: ABM Mismatch Handling",
            summary: "Review read-only Demo Apple Business mismatch handling and local Demo exceptions.",
            keywords: ["scenario", "abm", "mismatch", "demo"],
            relatedWorkspace: .abmVerification,
            steps: DeploymentDemoScenarioCatalog.scenario(id: "abm_mismatch_handling")?.stepTitles ?? [],
            expectedResult: "The Demo queues local exception review and confirms that no ABM data changed.",
            details: [
                DeploymentDemoScenarioCatalog.scenario(id: "abm_mismatch_handling")?.productionEquivalent ?? "Production equivalent is coming soon."
            ],
            relatedTopicIds: ["abm-verification", "exceptions-validation"]
        ),
        topic(
            id: "scenario-sdplus-export-and-shipping",
            title: "Scenario: SD+ Export and Shipping",
            summary: "Generate a Demo ServiceDesk Plus export preview and inspect seeded Demo shipment state.",
            keywords: ["scenario", "sd+", "shipping", "demo"],
            relatedWorkspace: .sdPlusExport,
            steps: DeploymentDemoScenarioCatalog.scenario(id: "sdplus_export_and_shipping")?.stepTitles ?? [],
            expectedResult: "The Demo generates preview CSV/history and reports that no SD+ or shipping carrier data changed.",
            details: [
                DeploymentDemoScenarioCatalog.scenario(id: "sdplus_export_and_shipping")?.productionEquivalent ?? "Production equivalent is coming soon."
            ],
            relatedTopicIds: ["sdplus-export", "shipments", "records-management"]
        ),
        topic(
            id: "abm-verification",
            title: "ABM Verification",
            summary: "Verify Apple Business data as a read-only upstream source.",
            keywords: ["abm", "apple business", "read only", "mismatch", "exception"],
            relatedWorkspace: .abmVerification,
            steps: [
                "Open ABM Verification or select devices in the Workbench.",
                "Choose Run Demo ABM Verification.",
                "Review the results.",
                "Open any mismatches.",
                "Create, resolve, or waive local exceptions as appropriate."
            ],
            expectedResult: "Tracker captures read-only ABM snapshots and shows mismatches.",
            details: [
                "Tracker never edits ABM records, releases devices, assigns devices to an MDM server, reassigns devices, unassigns devices, or deletes ABM records."
            ],
            relatedTopicIds: ["exceptions-validation", "workbench"]
        ),
        topic(
            id: "sdplus-export",
            title: "SD+ Export",
            summary: "Generate template-driven CSV files for ServiceDesk Plus upload/import.",
            keywords: ["sd+", "servicedesk plus", "csv", "export", "template"],
            relatedWorkspace: .sdPlusExport,
            steps: [
                "Open SD+ Export.",
                "Select a project, device batch, or filtered workbench rows.",
                "Preview the export.",
                "Fix any missing required fields.",
                "Click Generate CSV.",
                "Review the export history."
            ],
            expectedResult: "Tracker creates the CSV and records export history.",
            details: [
                "Validation runs before generated data is treated as exportable.",
                "Failed exports should state whether local Tracker data or external SD+ data changed."
            ],
            relatedTopicIds: ["workbench", "exceptions-validation"]
        ),
        topic(
            id: "shipments",
            title: "Shipments",
            summary: "Track outbound and return logistics.",
            keywords: ["shipping", "fedex", "tracking", "delivery", "return"],
            relatedWorkspace: .shipments,
            steps: [
                "Open Shipments or select devices in the Workbench.",
                "Create or select a shipment batch when that workflow is available.",
                "Add tracking information.",
                "Mark devices as shipped.",
                "Add delivery confirmation when available."
            ],
            expectedResult: "Shipping state appears in the workbench and reports.",
            details: [
                "Tracking and delivery confirmation fields are local Tracker fields and can be reviewed in the Workbench inspector."
            ],
            relatedTopicIds: ["workbench", "records-management"]
        ),
        topic(
            id: "apple-catalog",
            title: "Apple Catalog",
            summary: "Infer hardware information from model identifiers, part numbers, SKUs, and imported reference data.",
            keywords: ["apple catalog", "model identifier", "part number", "hardware", "enrichment"],
            relatedWorkspace: .appleCatalog,
            steps: [
                "Open Apple Catalog.",
                "Import the embedded catalog or vendor catalog data.",
                "Review unresolved devices.",
                "Accept the correct match or create a local catalog entry when available.",
                "Apply enrichment to local editable fields if appropriate."
            ],
            expectedResult: "Local device records become more complete without changing ABM or Jamf snapshots.",
            details: [
                "Catalog enrichment is local and never overwrites ABM or Jamf snapshots."
            ],
            relatedTopicIds: ["devices", "exceptions-validation"]
        ),
        topic(
            id: "exceptions-validation",
            title: "Exceptions and Validation",
            summary: "Resolve blocked records before running workflow actions.",
            keywords: ["blocked", "warning", "missing", "validation", "exception"],
            relatedWorkspace: .inProgress,
            steps: [
                "Open the blocked device from the Workbench or Exceptions view.",
                "Read the validation message.",
                "Review the recommended action.",
                "Fix the missing field, run the required lookup, or create a waiver if allowed.",
                "Revalidate the device."
            ],
            expectedResult: "The device moves from blocked to ready when the issue is resolved or waived.",
            details: [
                "Blocked actions should not partially mutate external systems.",
                "Validation messages are grouped by readiness, missing fields, external mismatches, and permission problems."
            ],
            relatedTopicIds: ["workbench", "jamf-preload", "abm-verification"]
        ),
        topic(
            id: "records-management",
            title: "Records Management",
            summary: "Use archive-first governance for history, restore, export, and hard-delete review.",
            keywords: ["records", "archive", "restore", "delete", "export"],
            relatedWorkspace: .recordsManagement,
            steps: [
                "Open the device, project, or reference value.",
                "Choose Archive for normal removal.",
                "Open Records Management for export or hard-delete review.",
                "Review dependency impact before a hard delete.",
                "Export records first when required."
            ],
            expectedResult: "Hard delete is controlled, audited, and rare.",
            details: [
                "Normal users should archive records instead of hard deleting them.",
                "Archive-first behavior keeps history available for reporting and restore."
            ],
            relatedTopicIds: ["devices", "projects", "diagnostics"]
        ),
        topic(
            id: "jamf-permissions",
            title: "Troubleshooting Jamf Permissions",
            summary: "Understand API role issues for Inventory Preload lookup, upload, and reconciliation.",
            keywords: ["permission", "privilege", "api role", "403", "oauth"],
            relatedWorkspace: .jamfPreload,
            steps: [
                "Read the structured error message.",
                "Note the required Jamf privileges.",
                "Ask a Jamf Pro administrator to update the API role assigned to the API Client.",
                "Refresh the Jamf Dashboard token.",
                "Retry the action."
            ],
            expectedResult: "After the API client has the required privileges, the action should run successfully.",
            details: [
                "Common Inventory Preload privileges are Create Inventory Preload Records, Update Inventory Preload Records, Create User, Update User, and Read Inventory Preload Records for lookup or reconciliation.",
                "Tracker does not grant Jamf permissions locally."
            ],
            relatedTopicIds: ["jamf-preload", "diagnostics"]
        ),
        topic(
            id: "diagnostics",
            title: "Diagnostics",
            summary: "Use diagnostics to troubleshoot technical failures without guessing.",
            keywords: ["diagnostics", "logs", "correlation", "export", "support"],
            relatedWorkspace: .reports,
            steps: [
                "Open Diagnostics from the app when available.",
                "Filter by deployment-tracker.",
                "Find the relevant category, such as deployment-tracker.jamf-preload.permission.",
                "Use the correlation ID from the structured error when available.",
                "Export diagnostics if support or engineering needs them."
            ],
            expectedResult: "Failures are traceable with source, category, severity, message, metadata, and correlation ID.",
            details: [
                "Guide open, guide search, layout save, column reorder, validation blocked-action, and Jamf preload permission problems are reported as deployment-tracker diagnostics."
            ],
            relatedTopicIds: ["jamf-permissions", "exceptions-validation"]
        ),
        topic(
            id: "administration",
            title: "Administration",
            summary: "Review Demo reference data, workflow statuses, layouts, and field definitions that power the interactive preview.",
            keywords: ["administration", "reference data", "workflow status", "demo"],
            relatedWorkspace: .administration,
            steps: [
                "Open Demo Administration.",
                "Review Demo reference categories and values.",
                "Open Demo Workbench and compare reference dropdown values.",
                "Use Reset Demo to restore deterministic seed data.",
                "Confirm no live Jamf, ABM, SD+, shipping, or production records are changed."
            ],
            expectedResult: "You understand the Demo configuration and can reset it safely.",
            details: [
                "Administration in this build is preview-focused.",
                "Production administration workflows are coming soon and will require explicit governance."
            ],
            relatedTopicIds: ["field-catalog", "why-demo-mode"]
        ),
        topic(
            id: "coming-soon-roadmap",
            title: "Coming Soon Roadmap",
            summary: "Production Deployment Tracker capabilities are intentionally separated from this Demo preview.",
            keywords: ["coming soon", "roadmap", "production", "demo"],
            relatedWorkspace: .dashboard,
            steps: [
                "Use Demo scenarios to review planned workflows.",
                "Use production-equivalent descriptions to understand the intended future behavior.",
                "Treat live Jamf, ABM, SD+, shipping, and records mutation as unavailable in this Demo.",
                "Use Reset Demo when you need a clean deterministic state."
            ],
            expectedResult: "The Demo remains safe while showing the future direction.",
            details: [
                "Future production mode must be explicitly enabled and tested before live operations are reachable.",
                "The current installed module defaults to Demo mode."
            ],
            relatedTopicIds: ["what-this-demo-shows", "why-demo-mode", "glossary"]
        ),
        topic(
            id: "glossary",
            title: "Glossary",
            summary: "Definitions for common Deployment Tracker terms.",
            keywords: ["definitions", "abm", "inventory preload", "sd+", "snapshot", "gate"],
            relatedWorkspace: nil,
            steps: [
                "ABM: Apple Business Manager, the upstream Apple device ownership and assignment source.",
                "Inventory Preload: Jamf Pro feature that lets data be preloaded by serial number before inventory collection.",
                "SD+: ServiceDesk Plus CSV export target for asset or ticket workflows.",
                "Workbench: The main configurable grid where technicians work active deployment devices.",
                "Field Catalog: The list of fields that can appear in layouts, reports, imports, and exports.",
                "Snapshot: A read-only copy of external data captured at a point in time.",
                "Gate: A validation checkpoint that controls whether a device can move forward."
            ],
            expectedResult: "You can translate Tracker terms while using the module.",
            details: [],
            relatedTopicIds: ["start-here"]
        )
    ]

    // Exact lookup is used by related-topic buttons and workspace deep links.
    static func topic(id: String) -> DeploymentTrackerGuideTopic? {
        topics.first { $0.id == id }
    }

    // Multi-term search requires every typed term to match the topic text. This
    // keeps broad searches useful while avoiding unrelated results for specific
    // phrases like "preload permission" or "workbook migration".
    static func topics(matching query: String) -> [DeploymentTrackerGuideTopic] {
        let normalizedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard normalizedQuery.isEmpty == false else {
            return topics
        }
        let terms = normalizedQuery
            .split(whereSeparator: \.isWhitespace)
            .map(String.init)
        return topics.filter { topic in
            terms.allSatisfy { topic.searchableText.contains($0) }
        }
    }

    // Builder keeps the topic declarations compact while preserving a single
    // initializer point if the guide model needs additional required fields.
    private static func topic(
        id: String,
        title: String,
        summary: String,
        keywords: [String],
        relatedWorkspace: DeploymentTrackerWorkspace?,
        steps: [String],
        expectedResult: String,
        details: [String],
        relatedTopicIds: [String]
    ) -> DeploymentTrackerGuideTopic {
        DeploymentTrackerGuideTopic(
            id: id,
            title: title,
            summary: summary,
            keywords: keywords,
            relatedWorkspace: relatedWorkspace,
            steps: steps,
            expectedResult: expectedResult,
            details: details,
            relatedTopicIds: relatedTopicIds
        )
    }
}

// MARK: - Tracker Guide UI
//
// The guide view is used in two modes: as a full workspace and as a modal sheet.
// The optional close button is only shown when the sheet presents it, while the
// search/sidebar/detail behavior remains identical in both contexts.
struct DeploymentTrackerGuideView: View {
    @ObservedObject var viewModel: DeploymentTrackerViewModel
    var showCloseButton: Bool

    init(viewModel: DeploymentTrackerViewModel, showCloseButton: Bool = false) {
        self.viewModel = viewModel
        self.showCloseButton = showCloseButton
    }

    var body: some View {
        // NavigationSplitView gives desktop users a persistent searchable topic
        // list and iOS users a native split/navigation adaptation. Selection is
        // stored in the view model so workspace links and modal links stay in
        // sync.
        NavigationSplitView {
            VStack(alignment: .leading, spacing: DashboardTheme.Spacing.item) {
                DeploymentDemoRibbonView()
                HStack {
                    Label("Deployment Tracker Demo Guide", systemImage: "questionmark.circle")
                        .font(.system(.title3, design: .rounded).weight(.semibold))
                    Spacer()
                    if showCloseButton {
                        Button {
                            viewModel.closeGuide()
                        } label: {
                            Image(systemName: "xmark")
                        }
                        .buttonStyle(.borderless)
                        .help("Close Guide")
                    }
                }

                TextField(
                    "Search guide",
                    text: Binding(
                        get: { viewModel.guideSearchText },
                        set: { viewModel.updateGuideSearchText($0) }
                    )
                )
                .textFieldStyle(.roundedBorder)
                .accessibilityLabel("Search Deployment Tracker Demo Guide")

                List(selection: Binding(
                    get: { viewModel.selectedGuideTopicID },
                    set: { topicID in
                        if let topicID {
                            viewModel.selectGuideTopic(topicID)
                        }
                    }
                )) {
                    ForEach(viewModel.filteredGuideTopics) { topic in
                        VStack(alignment: .leading, spacing: 3) {
                            Text(topic.title)
                                .font(.callout.weight(.semibold))
                            Text(topic.summary)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                        }
                        .tag(topic.id)
                    }
                }
                .listStyle(.sidebar)
            }
            .padding(DashboardTheme.Spacing.section)
            .navigationSplitViewColumnWidth(min: 260, ideal: 320, max: 380)
        } detail: {
            ScrollView {
                if let topic = viewModel.selectedGuideTopic {
                    GuideTopicDetailView(topic: topic, viewModel: viewModel)
                        .padding(DashboardTheme.Spacing.section)
                } else {
                    ContentUnavailableView(
                        "No Guide Topic",
                        systemImage: "questionmark.circle",
                        description: Text("Select a topic or clear the search.")
                    )
                    .padding(DashboardTheme.Spacing.section)
                }
            }
            .background(DashboardTheme.groupedSurface)
        }
    }
}

// Detailed topic renderer. It keeps the visible layout consistent across all
// topics while allowing each topic to provide its own steps, expected result,
// supporting details, related workspace, and related topic links.
private struct GuideTopicDetailView: View {
    let topic: DeploymentTrackerGuideTopic
    @ObservedObject var viewModel: DeploymentTrackerViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: DashboardTheme.Spacing.section) {
            DeploymentDemoRibbonView()
            VStack(alignment: .leading, spacing: DashboardTheme.Spacing.compact) {
                Label(topic.title, systemImage: "book")
                    .font(.system(.title2, design: .rounded).weight(.bold))
                Text(topic.summary)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if let workspace = topic.relatedWorkspace {
                // Opening a related workspace also closes the modal guide when
                // one is active. When the guide is embedded as the Guide
                // workspace, closeGuide() is harmless because no sheet is open.
                Button {
                    viewModel.selectWorkspace(workspace)
                    viewModel.closeGuide()
                } label: {
                    Label("Open \(workspace.displayName)", systemImage: workspace.iconSystemName)
                }
                .accessibilityHint("Closes the guide and opens the related Tracker workspace.")
            }

            GuideSection(title: "Steps", systemImage: "list.number") {
                VStack(alignment: .leading, spacing: DashboardTheme.Spacing.compact) {
                    ForEach(Array(topic.steps.enumerated()), id: \.offset) { index, step in
                        HStack(alignment: .top, spacing: DashboardTheme.Spacing.compact) {
                            Text("\(index + 1)")
                                .font(.caption.weight(.bold))
                                .foregroundStyle(.white)
                                .frame(width: 22, height: 22)
                                .background(Circle().fill(DashboardTheme.accent))
                            Text(step)
                                .font(.callout)
                                .fixedSize(horizontal: false, vertical: true)
                            Spacer(minLength: 0)
                        }
                    }
                }
            }

            GuideSection(title: "Expected Result", systemImage: "checkmark.circle") {
                Text(topic.expectedResult)
                    .font(.callout)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if topic.details.isEmpty == false {
                GuideSection(title: "Details", systemImage: "info.circle") {
                    VStack(alignment: .leading, spacing: DashboardTheme.Spacing.compact) {
                        ForEach(topic.details, id: \.self) { detail in
                            Label(detail, systemImage: "circle.fill")
                                .font(.callout)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
            }

            if topic.relatedTopicIds.isEmpty == false {
                GuideSection(title: "Related Topics", systemImage: "link") {
                    FlowButtonRow(topicIds: topic.relatedTopicIds, viewModel: viewModel)
                }
            }
        }
        .frame(maxWidth: 880, alignment: .leading)
    }
}

// Shared card wrapper for guide sections. Keeping this small component local to
// the guide prevents guide-specific visual rules from leaking into other module
// workspaces.
private struct GuideSection<Content: View>: View {
    let title: String
    let systemImage: String
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: DashboardTheme.Spacing.compact) {
            Label(title, systemImage: systemImage)
                .font(.headline)
            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .dashboardCardSurface()
    }
}

// Related topics render as compact buttons so technicians can move through the
// guide by task relationship instead of returning to the sidebar after every
// topic.
private struct FlowButtonRow: View {
    let topicIds: [String]
    @ObservedObject var viewModel: DeploymentTrackerViewModel

    var body: some View {
        // Related-topic buttons scroll horizontally so 2-3 long-titled topics never
        // overflow the iPhone / iPad-portrait detail column.
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: DashboardTheme.Spacing.compact) {
                ForEach(topicIds, id: \.self) { topicId in
                    if let topic = DeploymentTrackerGuideContent.topic(id: topicId) {
                        Button {
                            viewModel.selectGuideTopic(topic.id)
                        } label: {
                            Label(topic.title, systemImage: "arrow.right.circle")
                        }
                        .buttonStyle(.bordered)
                    }
                }
            }
            .padding(.vertical, 2)
        }
    }
}
