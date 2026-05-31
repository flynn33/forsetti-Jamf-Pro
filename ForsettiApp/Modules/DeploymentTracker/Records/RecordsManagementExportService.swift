import CryptoKit
import Foundation

// MARK: - Records Management export service
//
// Creates a local JSON records package that captures devices, projects,
// references, layouts, events, exceptions, snapshots, and export history before
// deletion review or external archival.
actor RecordsManagementExportService {
    private let store: any DeploymentTrackerStore
    private let encoder: JSONEncoder

    init(store: any DeploymentTrackerStore) {
        self.store = store
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        self.encoder = encoder
    }

    func makeExportPackage(
        createdBy: String?,
        createdAt: Date = Date()
    ) async throws -> RecordsExportPackage {
        // Build a complete archive package from includeArchived fetches so the
        // export represents operational history, not only active records.
        let packageName = "DeploymentTracker-RecordsExport-\(timestamp(createdAt))"
        let devices = try await store.fetchDevices(includeArchived: true)
        let projects = try await store.fetchProjects(includeArchived: true)
        let referenceValues = try await store.fetchReferenceValues(categoryId: nil)
        let layouts = try await store.fetchWorkbenchLayouts()
        let fieldCatalog = try await store.fetchFieldDefinitions()
        let workflowEvents = try await store.fetchWorkflowEvents(deviceId: nil)
        let auditEvents = try await store.fetchAuditEvents(entityId: nil)
        let exceptions = try await store.fetchExceptions(deviceId: nil, projectId: nil, includeResolved: true)
        let abmSnapshots = try await store.fetchAppleBusinessSnapshots()
        let jamfPreloadSnapshots = try await store.fetchJamfPreloadSnapshots()
        let jamfInventorySnapshots = try await store.fetchJamfInventorySnapshots()
        let jamfPreloadSubmissions = try await store.fetchJamfPreloadSubmissions()
        let sdPlusExportJobs = try await store.fetchSDPlusExportJobs()
        let appleCatalog = try await store.fetchAppleCatalogEntries(includeArchived: true)

        let deviceFiles: [RecordsExportFile] = [
            RecordsExportFile(path: "devices.csv", contents: devicesCSV(devices)),
            RecordsExportFile(path: "devices.json", contents: try json(devices))
        ]
        let projectFiles: [RecordsExportFile] = [
            RecordsExportFile(path: "projects.csv", contents: projectsCSV(projects)),
            RecordsExportFile(path: "projects.json", contents: try json(projects))
        ]
        let configurationFiles: [RecordsExportFile] = [
            RecordsExportFile(path: "reference-data.json", contents: try json(referenceValues)),
            RecordsExportFile(path: "workbench-layouts.json", contents: try json(layouts)),
            RecordsExportFile(path: "field-catalog.json", contents: try json(fieldCatalog))
        ]
        let eventFiles: [RecordsExportFile] = [
            RecordsExportFile(path: "workflow-events.csv", contents: workflowEventsCSV(workflowEvents)),
            RecordsExportFile(path: "audit-events.csv", contents: auditEventsCSV(auditEvents)),
            RecordsExportFile(path: "exceptions.csv", contents: exceptionsCSV(exceptions))
        ]
        let snapshotFiles: [RecordsExportFile] = [
            RecordsExportFile(path: "abm-snapshots.json", contents: try json(abmSnapshots)),
            RecordsExportFile(path: "jamf-preload-snapshots.json", contents: try json(jamfPreloadSnapshots)),
            RecordsExportFile(path: "jamf-inventory-snapshots.json", contents: try json(jamfInventorySnapshots))
        ]
        let exportHistoryFiles: [RecordsExportFile] = [
            RecordsExportFile(path: "jamf-preload-submissions.json", contents: try json(jamfPreloadSubmissions)),
            RecordsExportFile(path: "sdplus-export-history.json", contents: try json(sdPlusExportJobs)),
            RecordsExportFile(path: "apple-catalog.json", contents: try json(appleCatalog))
        ]
        var files = deviceFiles + projectFiles + configurationFiles + eventFiles + snapshotFiles + exportHistoryFiles

        let inventoryRecordCount = devices.count + projects.count + referenceValues.count
        let configurationRecordCount = layouts.count + fieldCatalog.count + appleCatalog.count
        let eventRecordCount = workflowEvents.count + auditEvents.count + exceptions.count
        let snapshotRecordCount = abmSnapshots.count + jamfPreloadSnapshots.count + jamfInventorySnapshots.count
        let exportRecordCount = jamfPreloadSubmissions.count + sdPlusExportJobs.count
        let includedRecordCount = inventoryRecordCount + configurationRecordCount + eventRecordCount + snapshotRecordCount + exportRecordCount

        let manifest = RecordsExportManifest(
            packageName: packageName,
            createdAt: createdAt,
            createdBy: createdBy,
            exportFormats: ["CSV", "JSON", "ZIP package"],
            includedRecordCount: includedRecordCount,
            files: files.map(\.path).sorted()
        )
        files.insert(RecordsExportFile(path: "manifest.json", contents: try json(manifest)), at: 0)

        let packageHash = sha256Hex(files.map { $0.path + "\n" + $0.contents }.joined(separator: "\n"))
        let job = RecordsExportJob(
            createdAt: createdAt,
            createdBy: createdBy,
            exportFormat: "ZIP package",
            packageName: packageName,
            fileName: "\(packageName).zip",
            fileHash: packageHash,
            includedRecordCount: includedRecordCount
        )
        try await store.createRecordsExportJob(job)

        return RecordsExportPackage(packageName: packageName, files: files, job: job)
    }

    nonisolated func validateHardDelete(
        review: RecordsDeletionReview,
        recordLifecycleState: DeploymentRecordLifecycleState,
        policy: RecordsManagementPolicy = .deploymentTrackerDefault
    ) -> RecordsHardDeleteValidationResult {
        var messages: [String] = []

        if policy.hardDeleteScope != "RecordsManagementOnly" {
            messages.append("Hard delete is not scoped to Records Management.")
        }
        if recordLifecycleState != .archived && recordLifecycleState != .pendingDeletion {
            messages.append("Record must be archived before hard delete review.")
        }
        if review.impactSummary.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            messages.append("Impact analysis must be completed before hard delete.")
        }
        if policy.exportBeforeDeleteDefault && !review.exportPolicySatisfied {
            messages.append("Export-before-delete policy has not been satisfied.")
        }
        if !review.finalConfirmationSatisfied {
            messages.append("Final confirmation is required before hard delete.")
        }
        if review.recordType == "DeploymentAuditEvent" && !policy.auditEventsHardDeletableByDefault {
            messages.append("Audit events are not hard-deletable by default.")
        }

        return RecordsHardDeleteValidationResult(allowed: messages.isEmpty, blockingMessages: messages)
    }

    private func json<T: Encodable>(_ value: T) throws -> String {
        String(decoding: try encoder.encode(value), as: UTF8.self)
    }

    private func devicesCSV(_ devices: [DeploymentDevice]) -> String {
        csv(
            headers: ["id", "serialNumber", "assetTag", "projectId", "workflowStatusId", "lifecycleState"],
            rows: devices.map {
                [$0.id, $0.serialNumber, $0.assetTag ?? "", $0.projectId ?? "", $0.workflowStatusId ?? "", $0.recordLifecycleState.rawValue]
            }
        )
    }

    private func projectsCSV(_ projects: [DeploymentProject]) -> String {
        csv(
            headers: ["id", "projectName", "projectCode", "ticketNumber", "lifecycleState"],
            rows: projects.map {
                [$0.id, $0.projectName, $0.projectCode ?? "", $0.ticketNumber ?? "", $0.recordLifecycleState.rawValue]
            }
        )
    }

    private func workflowEventsCSV(_ events: [DeploymentWorkflowEvent]) -> String {
        csv(
            headers: ["id", "deviceId", "fromStatusId", "toStatusId", "transitionedAt", "transitionedBy"],
            rows: events.map {
                [$0.id, $0.deviceId, $0.fromStatusId ?? "", $0.toStatusId, $0.transitionedAt.ISO8601Format(), $0.transitionedBy ?? ""]
            }
        )
    }

    private func auditEventsCSV(_ events: [DeploymentAuditEvent]) -> String {
        csv(
            headers: ["id", "occurredAt", "eventType", "entityType", "entityId", "fieldKey", "actor"],
            rows: events.map {
                [$0.id, $0.occurredAt.ISO8601Format(), $0.eventType, $0.entityType, $0.entityId, $0.fieldKey ?? "", $0.actor ?? ""]
            }
        )
    }

    private func exceptionsCSV(_ exceptions: [DeploymentException]) -> String {
        csv(
            headers: ["id", "deviceId", "projectId", "reasonCode", "severity", "status", "summary"],
            rows: exceptions.map {
                [$0.id, $0.deviceId ?? "", $0.projectId ?? "", $0.reasonCode, $0.severity.rawValue, $0.status.rawValue, $0.summary]
            }
        )
    }

    private func csv(headers: [String], rows: [[String]]) -> String {
        ([headers] + rows)
            .map { row in row.map(csvEscape).joined(separator: ",") }
            .joined(separator: "\n")
    }

    private func csvEscape(_ value: String) -> String {
        if value.contains(",") || value.contains("\"") || value.contains("\n") || value.contains("\r") {
            return "\"\(value.replacingOccurrences(of: "\"", with: "\"\""))\""
        }
        return value
    }

    private func timestamp(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withDashSeparatorInDate, .withColonSeparatorInTime]
        return formatter.string(from: date)
            .replacingOccurrences(of: ":", with: "")
    }

    private func sha256Hex(_ value: String) -> String {
        let digest = SHA256.hash(data: Data(value.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }
}
