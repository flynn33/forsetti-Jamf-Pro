import Foundation

nonisolated struct DeploymentTrackerDemoIntegrationSimulator: Sendable {
    let configuration: DeploymentTrackerDemoConfiguration
    let createdAt: Date

    init(
        configuration: DeploymentTrackerDemoConfiguration = .installedDemo,
        createdAt: Date = DeploymentTrackerDemoDataFactory.baseDate
    ) {
        self.configuration = configuration
        self.createdAt = createdAt
    }

    func simulateJamfPreload(recordCount: Int) -> DeploymentDemoSimulationResult {
        simulation(
            id: "demo-sim-jamf-preload",
            title: "Simulate Jamf Preload",
            summary: "Simulated Jamf Inventory Preload validation, CSV rendering, submission, update, retry, and reconciliation with deterministic Demo records. Dummy data only. No live Jamf actions.",
            simulatedSystem: "Jamf Inventory Preload",
            affectedDemoRecordCount: recordCount,
            productionEquivalent: "Production Jamf Inventory Preload actions require explicit enablement and approved Jamf privileges.",
            nextRecommendedDemoAction: "Open Jamf Preload Guide"
        )
    }

    func simulateABMVerification(recordCount: Int) -> DeploymentDemoSimulationResult {
        simulation(
            id: "demo-sim-abm-verification",
            title: "Simulate ABM Verification",
            summary: "Simulated read-only ABM verification and local exception creation from deterministic Demo snapshots.",
            simulatedSystem: "Apple Business Manager",
            affectedDemoRecordCount: recordCount,
            productionEquivalent: "Production ABM handling consumes governed read-only snapshots and keeps assignment changes outside this module.",
            nextRecommendedDemoAction: "Review Demo Exceptions"
        )
    }

    func simulateSDPlusExport(recordCount: Int) -> DeploymentDemoSimulationResult {
        simulation(
            id: "demo-sim-sdplus-export",
            title: "Simulate SD+ Export",
            summary: "Generated a deterministic ServiceDesk Plus export preview and local export history entry. Dummy data only.",
            simulatedSystem: "ServiceDesk Plus",
            affectedDemoRecordCount: recordCount,
            productionEquivalent: "Production SD+ export produces governed files for import rather than changing SD+ directly.",
            nextRecommendedDemoAction: "Open SD+ Export Guide"
        )
    }

    func simulateShippingReturns(recordCount: Int) -> DeploymentDemoSimulationResult {
        simulation(
            id: "demo-sim-shipping-returns",
            title: "Simulate Shipping and Returns",
            summary: "Reviewed deterministic shipping, delivery, return, and blocked shipment states without carrier access.",
            simulatedSystem: "Shipping",
            affectedDemoRecordCount: recordCount,
            productionEquivalent: "Production shipping integrations require separate carrier authorization and governance.",
            nextRecommendedDemoAction: "Review Shipment Records"
        )
    }

    func simulateRecordsArchive(recordCount: Int) -> DeploymentDemoSimulationResult {
        simulation(
            id: "demo-sim-records-archive",
            title: "Simulate Records Archive",
            summary: "Generated a deterministic records package and deletion impact preview from the local Demo store.",
            simulatedSystem: "Records Management",
            affectedDemoRecordCount: recordCount,
            productionEquivalent: "Production records management enforces export-before-delete and explicit deletion governance.",
            nextRecommendedDemoAction: "Open Records Management Guide"
        )
    }

    func simulateImportPreview(recordCount: Int) -> DeploymentDemoSimulationResult {
        simulation(
            id: "demo-sim-import-preview",
            title: "Simulate Import Preview",
            summary: "Staged deterministic vendor, serial-list, and workbook import previews without committing imported records.",
            simulatedSystem: "Deployment Tracker Intake",
            affectedDemoRecordCount: recordCount,
            productionEquivalent: "Production intake validates files and conflicts before a separate commit path creates tracker records.",
            nextRecommendedDemoAction: "Review Import Guide"
        )
    }

    func simulateValidationRecovery(recordCount: Int) -> DeploymentDemoSimulationResult {
        simulation(
            id: "demo-sim-validation-recovery",
            title: "Simulate Validation Recovery",
            summary: "Reviewed deterministic blockers, warnings, and local recovery guidance. Dummy data only. No live Jamf actions.",
            simulatedSystem: "Deployment Tracker Validation",
            affectedDemoRecordCount: recordCount,
            productionEquivalent: "Production validation blocks integration actions until required fields and exceptions are resolved.",
            nextRecommendedDemoAction: "Open Exceptions Guide"
        )
    }

    func simulateAdministrationReview(recordCount: Int) -> DeploymentDemoSimulationResult {
        simulation(
            id: "demo-sim-administration-review",
            title: "Simulate Administration Review",
            summary: "Reviewed deterministic reference values, workflow statuses, custom field definitions, and field ownership.",
            simulatedSystem: "Deployment Tracker Administration",
            affectedDemoRecordCount: recordCount,
            productionEquivalent: "Production administration changes are governed by explicit admin workflows.",
            nextRecommendedDemoAction: "Open Administration Guide"
        )
    }

    func liveActionBlocked(_ action: String) -> DeploymentDemoSafetyError {
        DeploymentDemoSafetyError.liveActionBlocked(action: action)
    }

    private func simulation(
        id: String,
        title: String,
        summary: String,
        simulatedSystem: String,
        affectedDemoRecordCount: Int,
        productionEquivalent: String,
        nextRecommendedDemoAction: String?
    ) -> DeploymentDemoSimulationResult {
        DeploymentDemoSimulationResult(
            id: id,
            title: title,
            summary: "\(summary) No external data changed.",
            simulatedSystem: simulatedSystem,
            affectedDemoRecordCount: max(affectedDemoRecordCount, 0),
            externalDataChanged: false,
            productionEquivalent: productionEquivalent,
            nextRecommendedDemoAction: nextRecommendedDemoAction,
            diagnosticsCategory: "deployment-tracker.demo.simulation",
            createdAt: createdAt
        )
    }
}
