import CryptoKit
import Foundation

// MARK: - Jamf Inventory Preload service
//
// This service coordinates validation, CSV rendering, Jamf API calls, local
// submission history, lookup caching, reconciliation, and structured permission
// errors. It is the only tracker service that should perform Jamf Inventory
// Preload network actions.
nonisolated struct JamfInventoryPreloadLookupResult: Equatable, Sendable {
    let records: [JamfInventoryPreloadRecord]
    let requestedSerialCount: Int
    let cachedRecordCount: Int
    let cachedMissCount: Int
    let jamfFetchedRecordCount: Int
    let jamfLookupMissCount: Int
    let jamfRequestBatchCount: Int
    let forceRefresh: Bool

    var matchedRecordCount: Int {
        records.count
    }

    var missingRecordCount: Int {
        max(0, requestedSerialCount - matchedRecordCount)
    }
}

// Narrow API client abstraction around the shared Jamf gateway. Keeping the
// service behind this protocol makes upload and lookup behavior testable without
// constructing a full app context.
nonisolated protocol JamfInventoryPreloadAPIClient: Sendable {
    func submitMultipart(path: String, parts: [JamfMultipartFormPart]) async throws -> Data
    func fetchPreloadRecords(filter: String) async throws -> [JamfInventoryPreloadRecord]
}

nonisolated struct JamfInventoryPreloadGatewayClient: JamfInventoryPreloadAPIClient {
    let apiGateway: JamfAPIGateway

    func submitMultipart(path: String, parts: [JamfMultipartFormPart]) async throws -> Data {
        try await apiGateway.uploadMultipart(path: path, parts: parts)
    }

    func fetchPreloadRecords(filter: String) async throws -> [JamfInventoryPreloadRecord] {
        let result = try await apiGateway.pagedRequest(
            path: JamfInventoryPreloadEndpoint.records,
            pageSize: JamfPaginationPolicy.defaultPageSize,
            queryItems: [
                URLQueryItem(name: "filter", value: filter)
            ],
            decodePage: { data in
                try JamfAPIGateway.decodePagedCollection(JamfInventoryPreloadRecord.self, from: data)
            }
        )
        return result.items
    }
}

actor JamfInventoryPreloadService {
    nonisolated static let preloadLookupCacheTTL: TimeInterval = 15 * 60
    nonisolated private static let lookupMissPayloadValue = "notFound"

    private struct CachedPreloadRecord: Sendable {
        let record: JamfInventoryPreloadRecord
        let cachedAt: Date
    }

    private let apiClient: any JamfInventoryPreloadAPIClient
    private let store: any DeploymentTrackerStore
    private let diagnosticsReporter: any DiagnosticsReporting
    private let renderer: JamfInventoryPreloadCSVRenderer
    private let validator: JamfInventoryPreloadValidator
    private let reconciliationService: JamfInventoryPreloadReconciliationService
    private var cachedRecordsBySerial: [String: CachedPreloadRecord] = [:]
    private var cachedMissesBySerial: [String: Date] = [:]

    init(
        apiGateway: JamfAPIGateway,
        store: any DeploymentTrackerStore,
        diagnosticsReporter: any DiagnosticsReporting,
        renderer: JamfInventoryPreloadCSVRenderer = JamfInventoryPreloadCSVRenderer(),
        validator: JamfInventoryPreloadValidator = JamfInventoryPreloadValidator(),
        reconciliationService: JamfInventoryPreloadReconciliationService = JamfInventoryPreloadReconciliationService()
    ) {
        self.apiClient = JamfInventoryPreloadGatewayClient(apiGateway: apiGateway)
        self.store = store
        self.diagnosticsReporter = diagnosticsReporter
        self.renderer = renderer
        self.validator = validator
        self.reconciliationService = reconciliationService
    }

    init(
        apiClient: any JamfInventoryPreloadAPIClient,
        store: any DeploymentTrackerStore,
        diagnosticsReporter: any DiagnosticsReporting,
        renderer: JamfInventoryPreloadCSVRenderer = JamfInventoryPreloadCSVRenderer(),
        validator: JamfInventoryPreloadValidator = JamfInventoryPreloadValidator(),
        reconciliationService: JamfInventoryPreloadReconciliationService = JamfInventoryPreloadReconciliationService()
    ) {
        self.apiClient = apiClient
        self.store = store
        self.diagnosticsReporter = diagnosticsReporter
        self.renderer = renderer
        self.validator = validator
        self.reconciliationService = reconciliationService
    }

    func validateSelectedDevices(
        deviceIds: [String],
        template: JamfInventoryPreloadTemplate = DeploymentTrackerSeedData.jamfInventoryPreloadStandardTemplate
    ) async throws -> JamfInventoryPreloadValidationResult {
        let devices = try await selectedDevices(deviceIds)
        let referenceValues = try await store.fetchReferenceValues(categoryId: nil)
        let exceptions = try await exceptions(for: devices)
        let result = validator.validate(
            devices: devices,
            template: template,
            referenceValues: referenceValues,
            exceptions: exceptions
        )

        await diagnosticsReporter.report(
            source: "deployment-tracker",
            category: "jamf-preload.validation",
            severity: result.isReadyForUpload ? .info : .warning,
            message: "Validated devices for Jamf Inventory Preload.",
            metadata: [
                "selected_count": String(deviceIds.count),
                "ready_count": String(result.readyDeviceIds.count),
                "blocked_count": String(result.blockedIssues.count),
                "warning_count": String(result.warningIssues.count),
                "required_privileges": result.requiredPrivileges.joined(separator: ", ")
            ]
        )

        return result
    }

    func renderCSVForSelectedDevices(
        deviceIds: [String],
        template: JamfInventoryPreloadTemplate = DeploymentTrackerSeedData.jamfInventoryPreloadStandardTemplate
    ) async throws -> String {
        let devices = try await selectedDevices(deviceIds)
        let referenceValues = try await store.fetchReferenceValues(categoryId: nil)
        return renderer.renderCSV(devices: devices, template: template, referenceValues: referenceValues)
    }

    func uploadSelectedDevices(
        deviceIds: [String],
        template: JamfInventoryPreloadTemplate = DeploymentTrackerSeedData.jamfInventoryPreloadStandardTemplate,
        actor: String? = nil
    ) async throws -> JamfInventoryPreloadSubmission {
        let devices = try await selectedDevices(deviceIds)
        let referenceValues = try await store.fetchReferenceValues(categoryId: nil)
        let exceptions = try await self.exceptions(for: devices)
        let validation = validator.validate(
            devices: devices,
            template: template,
            referenceValues: referenceValues,
            exceptions: exceptions
        )

        guard validation.isReadyForUpload else {
            await diagnosticsReporter.report(
                source: "deployment-tracker",
                category: "jamf-preload.validation",
                severity: .warning,
                message: "Jamf Inventory Preload upload blocked by local validation.",
                metadata: [
                    "selected_count": String(deviceIds.count),
                    "blocked_count": String(validation.blockedIssues.count),
                    "required_privileges": template.requiredPrivileges.joined(separator: ", ")
                ]
            )
            throw JamfFrameworkError.invalidRequest(message: "Local Jamf Inventory Preload validation failed.")
        }

        let csv = renderer.renderCSV(devices: devices, template: template, referenceValues: referenceValues)
        let csvData = Data(csv.utf8)
        let correlationId = UUID().uuidString
        let payloadHash = Self.sha256Hex(csvData)
        do {
            let response = try await apiClient.submitMultipart(
                path: JamfInventoryPreloadEndpoint.csvUpload,
                parts: [
                    JamfMultipartFormPart(
                        name: "file",
                        filename: "inventory-preload.csv",
                        contentType: "text/csv",
                        data: csvData
                    )
                ]
            )

            let submission = JamfInventoryPreloadSubmission(
                submittedBy: actor,
                deviceIds: devices.map(\.id),
                payloadHash: payloadHash,
                state: .submitted,
                diagnosticsCorrelationId: correlationId,
                responseSummary: String(data: response, encoding: .utf8)
            )
            try await store.createJamfPreloadSubmission(submission)

            for var device in devices {
                device.jamfPreloadState = .submitted
                device.latestPreloadSubmissionId = submission.id
                try await store.saveDevice(device)
                try await store.appendAuditEvent(
                    DeploymentAuditEvent(
                        eventType: "jamf-preload.submission",
                        entityType: "DeploymentDevice",
                        entityId: device.id,
                        fieldKey: "device.jamfPreloadState",
                        oldValue: nil,
                        newValue: DeploymentIntegrationState.submitted.rawValue,
                        actor: actor,
                        metadata: [
                            "submission_id": submission.id,
                            "payload_hash": payloadHash,
                            "diagnostics_correlation_id": correlationId
                        ]
                    )
                )
            }

            await diagnosticsReporter.report(
                source: "deployment-tracker",
                category: "jamf-preload.submission",
                severity: .info,
                message: "Submitted Jamf Inventory Preload CSV.",
                metadata: [
                    "device_count": String(devices.count),
                    "payload_hash": payloadHash,
                    "diagnostics_correlation_id": correlationId,
                    "required_privileges": template.requiredPrivileges.joined(separator: ", ")
                ]
            )

            return submission
        } catch {
            let failedSubmission = JamfInventoryPreloadSubmission(
                submittedBy: actor,
                deviceIds: devices.map(\.id),
                payloadHash: payloadHash,
                state: .failed,
                diagnosticsCorrelationId: correlationId,
                failedDeviceIds: devices.map(\.id),
                responseSummary: error.localizedDescription
            )
            try await store.createJamfPreloadSubmission(failedSubmission)
            await diagnosticsReporter.reportError(
                source: "deployment-tracker",
                category: "jamf-preload.submission",
                message: "Jamf Inventory Preload upload failed.",
                errorDescription: error.localizedDescription,
                metadata: [
                    "device_count": String(devices.count),
                    "diagnostics_correlation_id": correlationId,
                    "required_privileges": template.requiredPrivileges.joined(separator: ", "),
                    "safe_to_retry": "true"
                ]
            )
            throw error
        }
    }

    func validateCSVWithJamf(_ csv: String) async throws -> Data {
        try await apiClient.submitMultipart(
            path: JamfInventoryPreloadEndpoint.csvValidate,
            parts: [
                JamfMultipartFormPart(
                    name: "file",
                    filename: "inventory-preload.csv",
                    contentType: "text/csv",
                    data: Data(csv.utf8)
                )
            ]
        )
    }

    func lookupRecords(
        serialNumbers: [String],
        forceRefresh: Bool = false,
        cacheTTL: TimeInterval = JamfInventoryPreloadService.preloadLookupCacheTTL
    ) async throws -> [JamfInventoryPreloadRecord] {
        try await lookupRecordResult(
            serialNumbers: serialNumbers,
            forceRefresh: forceRefresh,
            cacheTTL: cacheTTL
        ).records
    }

    func lookupRecordResult(
        serialNumbers: [String],
        forceRefresh: Bool = false,
        cacheTTL: TimeInterval = JamfInventoryPreloadService.preloadLookupCacheTTL
    ) async throws -> JamfInventoryPreloadLookupResult {
        let normalizedSerials = Array(Set(serialNumbers.map(DeploymentDevice.normalizeSerial(_:))).filter { !$0.isEmpty }).sorted()
        guard !normalizedSerials.isEmpty else {
            return JamfInventoryPreloadLookupResult(
                records: [],
                requestedSerialCount: 0,
                cachedRecordCount: 0,
                cachedMissCount: 0,
                jamfFetchedRecordCount: 0,
                jamfLookupMissCount: 0,
                jamfRequestBatchCount: 0,
                forceRefresh: forceRefresh
            )
        }

        let lookupStartedAt = Date()
        let deviceBySerial = try await localDevicesByNormalizedSerial()
        var recordsBySerial: [String: JamfInventoryPreloadRecord] = [:]
        var cachedRecordCount = 0
        var cachedMissCount = 0

        if !forceRefresh, cacheTTL > 0 {
            let cached = try await cachedLookupRecords(
                for: normalizedSerials,
                now: lookupStartedAt,
                cacheTTL: cacheTTL
            )
            recordsBySerial.merge(cached.recordsBySerial) { _, new in new }
            cachedRecordCount = cached.recordsBySerial.count
            cachedMissCount = cached.missedSerials.count
        }

        let cachedMissSerials = Set(
            normalizedSerials.filter { serial in
                recordsBySerial[serial] == nil && isCachedMiss(serial, now: lookupStartedAt, cacheTTL: cacheTTL)
            }
        )
        cachedMissCount = max(cachedMissCount, cachedMissSerials.count)

        let serialsToFetch = normalizedSerials.filter {
            recordsBySerial[$0] == nil && !cachedMissSerials.contains($0)
        }
        var jamfFetchedRecordCount = 0
        var jamfLookupMissCount = 0
        var jamfRequestBatchCount = 0

        do {
            for batch in Self.serialLookupBatches(serialsToFetch) where !batch.isEmpty {
                jamfRequestBatchCount += 1
                let fetchedRecords = try await apiClient.fetchPreloadRecords(
                    filter: Self.serialLookupFilter(for: batch)
                )
                let fetchedSerials = Set(fetchedRecords.map { DeploymentDevice.normalizeSerial($0.serialNumber) })
                let missedSerials = batch.filter { !fetchedSerials.contains($0) }
                jamfFetchedRecordCount += fetchedRecords.count
                jamfLookupMissCount += missedSerials.count

                for record in fetchedRecords {
                    let normalizedSerial = DeploymentDevice.normalizeSerial(record.serialNumber)
                    recordsBySerial[normalizedSerial] = record
                }

                try await cacheFetchedLookup(
                    records: fetchedRecords,
                    missedSerials: missedSerials,
                    deviceBySerial: deviceBySerial,
                    capturedAt: lookupStartedAt
                )
            }
        } catch {
            await diagnosticsReporter.reportError(
                source: "deployment-tracker",
                category: "jamf-preload.lookup",
                message: "Jamf Inventory Preload lookup failed before changing local or Jamf data.",
                errorDescription: error.localizedDescription,
                metadata: [
                    "requested_serial_count": String(normalizedSerials.count),
                    "cache_hit_count": String(cachedRecordCount),
                    "cached_miss_count": String(cachedMissCount),
                    "jamf_request_batch_count": String(jamfRequestBatchCount),
                    "local_data_changed": "false",
                    "external_data_changed": "false",
                    "required_privileges": JamfInventoryPreloadPrivilege.lookup.joined(separator: ", ")
                ]
            )
            throw error
        }

        let records = normalizedSerials.compactMap { recordsBySerial[$0] }
        let result = JamfInventoryPreloadLookupResult(
            records: records,
            requestedSerialCount: normalizedSerials.count,
            cachedRecordCount: cachedRecordCount,
            cachedMissCount: cachedMissCount,
            jamfFetchedRecordCount: jamfFetchedRecordCount,
            jamfLookupMissCount: jamfLookupMissCount,
            jamfRequestBatchCount: jamfRequestBatchCount,
            forceRefresh: forceRefresh
        )

        await diagnosticsReporter.report(
            source: "deployment-tracker",
            category: "jamf-preload.lookup",
            severity: .info,
            message: "Completed Jamf Inventory Preload lookup using the local Deployment Tracker cache before Jamf API reads.",
            metadata: [
                "requested_serial_count": String(result.requestedSerialCount),
                "matched_record_count": String(result.matchedRecordCount),
                "missing_record_count": String(result.missingRecordCount),
                "cache_hit_count": String(result.cachedRecordCount),
                "cached_miss_count": String(result.cachedMissCount),
                "jamf_fetched_record_count": String(result.jamfFetchedRecordCount),
                "jamf_lookup_miss_count": String(result.jamfLookupMissCount),
                "jamf_request_batch_count": String(result.jamfRequestBatchCount),
                "force_refresh": String(result.forceRefresh),
                "cache_ttl_seconds": String(Int(cacheTTL)),
                "required_privileges": JamfInventoryPreloadPrivilege.lookup.joined(separator: ", ")
            ]
        )

        return result
    }

    func reconcileSelectedDevices(deviceIds: [String]) async throws -> [JamfInventoryPreloadSnapshot] {
        let devices = try await selectedDevices(deviceIds)
        let records = try await lookupRecords(serialNumbers: devices.map(\.serialNumber))
        let snapshots = reconciliationService.reconcile(devices: devices, records: records)
        for snapshot in snapshots {
            try await store.appendJamfPreloadSnapshot(snapshot)
            if var device = devices.first(where: { $0.id == snapshot.deploymentDeviceId }) {
                device.jamfPreloadState = .reconciled
                device.jamfReconciliationState = .reconciled
                try await store.saveDevice(device)
            }
        }
        return snapshots
    }

    nonisolated func failedOnlyRetryDeviceIds(from submission: JamfInventoryPreloadSubmission) -> [String] {
        submission.failedDeviceIds.isEmpty ? submission.deviceIds : submission.failedDeviceIds
    }

    nonisolated func makePermissionError(
        technicalCause: String,
        diagnosticsCorrelationId: String? = nil
    ) -> DeploymentUserFacingIntegrationError {
        DeploymentUserFacingIntegrationError(
            title: "Jamf Inventory Preload permission failure",
            summary: "Jamf Pro rejected the Inventory Preload request because the API role is missing required privileges.",
            technicalCause: technicalCause,
            requiredJamfPrivileges: JamfInventoryPreloadPrivilege.upload,
            localDataChanged: false,
            externalDataChanged: false,
            safeToRetry: true,
            recommendedAction: "Update the Jamf Pro API role, refresh the saved token, and retry the failed submission.",
            diagnosticsCategory: "deployment-tracker.jamf-preload.permission",
            diagnosticsCorrelationId: diagnosticsCorrelationId,
            relatedGuideTopicId: "jamf-permissions"
        )
    }

    private func selectedDevices(_ deviceIds: [String]) async throws -> [DeploymentDevice] {
        let ids = Set(deviceIds)
        return try await store.fetchDevices(includeArchived: true).filter { ids.contains($0.id) }
    }

    private func exceptions(for devices: [DeploymentDevice]) async throws -> [DeploymentException] {
        var allExceptions: [DeploymentException] = []
        for device in devices {
            let exceptions = try await store.fetchExceptions(
                deviceId: device.id,
                projectId: device.projectId,
                includeResolved: false
            )
            allExceptions.append(contentsOf: exceptions)
        }
        return allExceptions
    }

    private func localDevicesByNormalizedSerial() async throws -> [String: DeploymentDevice] {
        let devices = try await store.fetchDevices(includeArchived: true)
        let grouped = Dictionary(grouping: devices, by: \.normalizedSerialNumber)
        return grouped.compactMapValues { devices in
            devices.first { $0.recordLifecycleState == .active } ?? devices.first
        }
    }

    private func cachedLookupRecords(
        for normalizedSerials: [String],
        now: Date,
        cacheTTL: TimeInterval
    ) async throws -> (recordsBySerial: [String: JamfInventoryPreloadRecord], missedSerials: Set<String>) {
        let requested = Set(normalizedSerials)
        var recordsBySerial = cachedRecordsBySerial.reduce(into: [String: JamfInventoryPreloadRecord]()) { partial, element in
            guard requested.contains(element.key), Self.isCacheDate(element.value.cachedAt, freshAt: now, ttl: cacheTTL) else {
                return
            }
            partial[element.key] = element.value.record
        }
        var missedSerials = Set(
            cachedMissesBySerial.compactMap { serial, cachedAt in
                requested.contains(serial) && Self.isCacheDate(cachedAt, freshAt: now, ttl: cacheTTL) ? serial : nil
            }
        )

        let snapshots = try await store.fetchJamfPreloadSnapshots()
        var latestSnapshotsBySerial: [String: JamfInventoryPreloadSnapshot] = [:]
        for snapshot in snapshots where requested.contains(DeploymentDevice.normalizeSerial(snapshot.serialNumber)) {
            let normalizedSerial = DeploymentDevice.normalizeSerial(snapshot.serialNumber)
            guard Self.isCacheDate(snapshot.capturedAt, freshAt: now, ttl: cacheTTL) else {
                continue
            }
            if let current = latestSnapshotsBySerial[normalizedSerial], current.capturedAt > snapshot.capturedAt {
                continue
            }
            latestSnapshotsBySerial[normalizedSerial] = snapshot
        }

        for (serial, snapshot) in latestSnapshotsBySerial {
            if Self.isLookupMissSnapshot(snapshot) {
                cachedMissesBySerial[serial] = snapshot.capturedAt
                missedSerials.insert(serial)
                continue
            }
            guard let record = Self.preloadRecord(from: snapshot) else {
                continue
            }
            cachedRecordsBySerial[serial] = CachedPreloadRecord(record: record, cachedAt: snapshot.capturedAt)
            recordsBySerial[serial] = record
        }

        return (recordsBySerial, missedSerials)
    }

    private func isCachedMiss(_ serial: String, now: Date, cacheTTL: TimeInterval) -> Bool {
        guard cacheTTL > 0, let cachedAt = cachedMissesBySerial[serial] else {
            return false
        }
        return Self.isCacheDate(cachedAt, freshAt: now, ttl: cacheTTL)
    }

    private func cacheFetchedLookup(
        records: [JamfInventoryPreloadRecord],
        missedSerials: [String],
        deviceBySerial: [String: DeploymentDevice],
        capturedAt: Date
    ) async throws {
        for record in records {
            let normalizedSerial = DeploymentDevice.normalizeSerial(record.serialNumber)
            cachedRecordsBySerial[normalizedSerial] = CachedPreloadRecord(record: record, cachedAt: capturedAt)

            guard let device = deviceBySerial[normalizedSerial] else {
                continue
            }
            try await store.appendJamfPreloadSnapshot(
                JamfInventoryPreloadSnapshot(
                    id: UUID().uuidString,
                    deploymentDeviceId: device.id,
                    serialNumber: device.serialNumber,
                    capturedAt: capturedAt,
                    rawRecordHash: Self.recordHash(record),
                    payloadSummary: Self.payloadSummary(for: record)
                )
            )
        }

        for serial in missedSerials {
            cachedMissesBySerial[serial] = capturedAt

            guard let device = deviceBySerial[serial] else {
                continue
            }
            try await store.appendJamfPreloadSnapshot(
                JamfInventoryPreloadSnapshot(
                    id: UUID().uuidString,
                    deploymentDeviceId: device.id,
                    serialNumber: device.serialNumber,
                    capturedAt: capturedAt,
                    rawRecordHash: nil,
                    payloadSummary: [
                        "lookupStatus": Self.lookupMissPayloadValue,
                        "message": "No Jamf Inventory Preload record matched this serial during lookup."
                    ]
                )
            )
        }
    }

    nonisolated private static func sha256Hex(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    nonisolated private static func isCacheDate(_ cachedAt: Date, freshAt now: Date, ttl: TimeInterval) -> Bool {
        now.timeIntervalSince(cachedAt) <= ttl
    }

    nonisolated private static func payloadSummary(for record: JamfInventoryPreloadRecord) -> [String: String] {
        [
            "recordId": record.id,
            "deviceType": record.deviceType ?? "",
            "username": record.username ?? "",
            "emailAddress": record.emailAddress ?? "",
            "building": record.building ?? "",
            "room": record.room ?? "",
            "assetTag": record.assetTag ?? "",
            "department": record.department ?? "",
            "poNumber": record.poNumber ?? ""
        ]
    }

    nonisolated private static func preloadRecord(from snapshot: JamfInventoryPreloadSnapshot) -> JamfInventoryPreloadRecord? {
        guard !isLookupMissSnapshot(snapshot) else {
            return nil
        }
        return JamfInventoryPreloadRecord(
            id: snapshot.payloadSummary["recordId"] ?? snapshot.id,
            serialNumber: snapshot.serialNumber,
            deviceType: nilIfEmpty(snapshot.payloadSummary["deviceType"]),
            username: nilIfEmpty(snapshot.payloadSummary["username"]),
            emailAddress: nilIfEmpty(snapshot.payloadSummary["emailAddress"]),
            building: nilIfEmpty(snapshot.payloadSummary["building"]),
            room: nilIfEmpty(snapshot.payloadSummary["room"]),
            assetTag: nilIfEmpty(snapshot.payloadSummary["assetTag"]),
            department: nilIfEmpty(snapshot.payloadSummary["department"]),
            poNumber: nilIfEmpty(snapshot.payloadSummary["poNumber"])
        )
    }

    nonisolated private static func isLookupMissSnapshot(_ snapshot: JamfInventoryPreloadSnapshot) -> Bool {
        snapshot.payloadSummary["lookupStatus"] == lookupMissPayloadValue
    }

    nonisolated private static func nilIfEmpty(_ value: String?) -> String? {
        guard let value, !value.isEmpty else {
            return nil
        }
        return value
    }

    nonisolated private static func recordHash(_ record: JamfInventoryPreloadRecord) -> String? {
        guard let data = try? JSONEncoder().encode(record) else {
            return nil
        }
        return sha256Hex(data)
    }

    nonisolated static func serialLookupFilter(for serialNumbers: [String]) -> String {
        let parts = serialNumbers
            .map(DeploymentDevice.normalizeSerial(_:))
            .filter { !$0.isEmpty }
            .map { JamfRSQLFilter.equality(field: "serialNumber", value: $0) }
        return parts.count == 1 ? parts[0] : "(\(parts.joined(separator: ",")))"
    }

    nonisolated static func serialLookupBatches(_ serialNumbers: [String], batchSize: Int = 50) -> [[String]] {
        guard batchSize > 0 else {
            return [serialNumbers]
        }
        var batches: [[String]] = []
        var current: [String] = []
        for serial in serialNumbers {
            current.append(serial)
            if current.count == batchSize {
                batches.append(current)
                current = []
            }
        }
        if !current.isEmpty {
            batches.append(current)
        }
        return batches
    }
}
