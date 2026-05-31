import CryptoKit
import Foundation

// MARK: - SD+ export service
//
// Export service wraps rendering with persistence, hashing, versioning, and
// diagnostics. It records local export history only; SD+ uploads or external
// mutations remain outside this module.
actor SDPlusExportService {
    private let store: any DeploymentTrackerStore
    private let diagnosticsReporter: (any DiagnosticsReporting)?

    init(
        store: any DeploymentTrackerStore,
        diagnosticsReporter: (any DiagnosticsReporting)? = nil
    ) {
        self.store = store
        self.diagnosticsReporter = diagnosticsReporter
    }

    func preview(
        devices: [DeploymentDevice],
        template: SDPlusExportTemplate,
        fieldDefinitions: [DeploymentFieldDefinition],
        referenceValues: [DeploymentReferenceValue]
    ) -> SDPlusRenderedExport {
        // Preview deliberately skips persistence so technicians can inspect CSV
        // output without creating an export history entry.
        SDPlusCSVRenderer(fieldDefinitions: fieldDefinitions, referenceValues: referenceValues)
            .render(devices: devices, template: template)
    }

    func export(
        devices: [DeploymentDevice],
        template: SDPlusExportTemplate,
        fieldDefinitions: [DeploymentFieldDefinition],
        referenceValues: [DeploymentReferenceValue],
        projectId: String?,
        exportedBy: String?,
        exportedAt: Date = Date()
    ) async throws -> SDPlusExportResult {
        let renderedExport = preview(
            devices: devices,
            template: template,
            fieldDefinitions: fieldDefinitions,
            referenceValues: referenceValues
        )
        let nextVersion = try await nextExportVersion(projectId: projectId, templateId: template.id)
        let fileName = fileName(projectId: projectId, exportedAt: exportedAt, version: nextVersion)
        let hasBlockingIssues = !renderedExport.validation.isValid

        let job = SDPlusExportJob(
            projectId: projectId,
            templateId: template.id,
            exportedAt: exportedAt,
            exportedBy: exportedBy,
            deviceCount: renderedExport.includedDeviceIds.count,
            fileName: fileName,
            fileHash: sha256Hex(renderedExport.csv),
            exportVersion: nextVersion,
            exportState: hasBlockingIssues ? .failed : .exported,
            validationSummary: validationSummary(for: renderedExport.validation),
            includedDeviceIds: renderedExport.includedDeviceIds,
            failedDeviceIds: renderedExport.failedDeviceIds
        )

        try await store.createSDPlusExportJob(job)

        if renderedExport.validation.isValid {
            for var device in devices {
                device.sdPlusExportState = .exported
                device.sdPlusExportTemplateId = template.id
                device.sdPlusLastExportedAt = exportedAt
                device.sdPlusExportVersion = nextVersion
                _ = try await store.saveDevice(device)
                try await store.appendAuditEvent(DeploymentAuditEvent(
                    eventType: "sdplus.exported",
                    entityType: "DeploymentDevice",
                    entityId: device.id,
                    fieldKey: "device.sdPlusExportState",
                    oldValue: nil,
                    newValue: DeploymentIntegrationState.exported.rawValue,
                    actor: exportedBy,
                    metadata: [
                        "sdPlusExportJobId": job.id,
                        "templateId": template.id,
                        "exportVersion": String(nextVersion)
                    ]
                ))
            }
        }

        if hasBlockingIssues {
            await diagnosticsReporter?.report(
                source: "deployment-tracker.sdplus",
                category: "deployment-tracker.sdplus.export",
                severity: .warning,
                message: "SD+ export validation failed.",
                metadata: [
                    "templateId": template.id,
                    "blockingIssueCount": "\(renderedExport.validation.blockingIssues.count)"
                ]
            )
        }

        return SDPlusExportResult(renderedExport: renderedExport, job: job)
    }

    private func nextExportVersion(projectId: String?, templateId: String) async throws -> Int {
        let jobs = try await store.fetchSDPlusExportJobs()
        let matchingVersions = jobs
            .filter { $0.projectId == projectId && $0.templateId == templateId }
            .map(\.exportVersion)
        return (matchingVersions.max() ?? 0) + 1
    }

    private func fileName(projectId: String?, exportedAt: Date, version: Int) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withDashSeparatorInDate, .withColonSeparatorInTime]
        let timestamp = formatter.string(from: exportedAt)
            .replacingOccurrences(of: ":", with: "")
        let projectComponent = projectId?.isEmpty == false ? projectId! : "all-projects"
        return "SDPlusExport-\(projectComponent)-v\(version)-\(timestamp).csv"
    }

    private func validationSummary(for validation: SDPlusExportValidationResult) -> String {
        if validation.isValid {
            return "Valid"
        }
        return "\(validation.blockingIssues.count) blocking issue(s), \(validation.warningIssues.count) warning(s)"
    }

    private func sha256Hex(_ value: String) -> String {
        let digest = SHA256.hash(data: Data(value.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }
}
