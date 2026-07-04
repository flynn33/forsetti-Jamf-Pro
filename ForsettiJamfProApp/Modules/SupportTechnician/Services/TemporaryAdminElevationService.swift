import Foundation

// MARK: - Diagnostics constants

/// Diagnostic source and categories for the Temporary Admin Elevation feature.
/// Centralized so the service, view model, and tests agree on the strings.
nonisolated enum TemporaryAdminDiagnostics {
    static let source = "support.temporary-admin"

    enum Category {
        static let request = "support.temporary-admin.request"
        static let validation = "support.temporary-admin.validation"
        static let scope = "support.temporary-admin.scope"
        static let status = "support.temporary-admin.status"
        static let elevated = "support.temporary-admin.elevated"
        static let demote = "support.temporary-admin.demote"
        static let timeout = "support.temporary-admin.timeout"
        static let permission = "support.temporary-admin.permission"
        static let cleanup = "support.temporary-admin.cleanup"
        static let audit = "support.temporary-admin.audit"
    }
}

// MARK: - Inventory reload abstraction

/// Reloads a computer's inventory detail so freshly-reported extension
/// attributes can be parsed. `SupportTechnicianAPIService` conforms using its
/// existing `fetchDeviceDetail` path — no new networking is introduced.
protocol SupportTechnicianInventoryReloading: Sendable {
    func reloadDetail(for detail: SupportDeviceDetail, bypassCache: Bool) async throws -> SupportDeviceDetail
}

extension SupportTechnicianAPIService: SupportTechnicianInventoryReloading {
    func reloadDetail(for detail: SupportDeviceDetail, bypassCache: Bool) async throws -> SupportDeviceDetail {
        try await fetchDeviceDetail(for: detail.summary, bypassCache: bypassCache)
    }
}

// MARK: - Validation

/// Pure validation for a temporary-admin request. Shared by the service (which
/// throws on invalid input) and the UI (which gates the Request button), so
/// both agree on exactly one rule set.
nonisolated enum TemporaryAdminElevationValidator {
    static func validate(
        assetType: SupportAssetType,
        isManaged: Bool,
        inventoryID: String,
        duration: TemporaryAdminDuration?,
        hasConfiguredScope: Bool,
        reason: String,
        ticketReference: String,
        requiresTicket: Bool
    ) -> TemporaryAdminValidationResult {
        var messages: [String] = []

        if assetType != .computer {
            messages.append("Temporary Admin Elevation is available for managed Macs only.")
        }
        if isManaged == false {
            messages.append("This computer does not appear to be managed by Jamf Pro.")
        }
        if inventoryID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            messages.append("A Jamf computer inventory ID is required.")
        }
        if duration == nil {
            messages.append("Select an approved elevation duration.")
        } else if hasConfiguredScope == false {
            messages.append("No request scope is configured for the selected duration.")
        }
        if reason.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            messages.append("A reason is required.")
        }
        if requiresTicket, ticketReference.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            messages.append("A ticket or reference is required.")
        }

        return messages.isEmpty ? .valid : .invalid(messages)
    }
}

// MARK: - Poll result

/// The outcome of one poll cycle against the selected Mac's reported state.
nonisolated struct TemporaryAdminPollResult: Equatable, Sendable {
    /// The latest parsed Mac snapshot.
    let snapshot: TemporaryAdminElevationSnapshot
    /// Whether this request reached a terminal outcome (the caller stops polling).
    let isComplete: Bool
    /// Whether the request exceeded the confirmation timeout without confirmation.
    let didTimeout: Bool
    /// Whether request-scope cleanup was attempted but could not be confirmed.
    let cleanupFailed: Bool
}

// MARK: - Service protocol

protocol TemporaryAdminElevationServicing: Sendable {
    /// Parses the Mac's currently-reported snapshot from an already-loaded
    /// device detail. No networking; returns `.notConfigured` when the feature
    /// is not configured.
    func loadSnapshot(for detail: SupportDeviceDetail) async throws -> TemporaryAdminElevationSnapshot

    /// Reloads the computer's inventory and parses a fresh snapshot. Used by the
    /// manual Refresh Status action when no request is in flight.
    func refreshSnapshot(for detail: SupportDeviceDetail) async throws -> TemporaryAdminElevationSnapshot

    /// Validates inputs, blocks duplicates, and adds the computer to the
    /// configured duration request scope. Returns the app-side request handle
    /// used for polling.
    func requestElevation(
        for detail: SupportDeviceDetail,
        duration: TemporaryAdminDuration,
        reason: String,
        ticketReference: String?
    ) async throws -> TemporaryAdminElevationRequest

    /// Reloads inventory, parses the snapshot, and — when the request reaches a
    /// fresh terminal state or exceeds the timeout — removes the computer from
    /// its request scope. Safe to call repeatedly.
    func pollElevation(
        for detail: SupportDeviceDetail,
        request: TemporaryAdminElevationRequest
    ) async throws -> TemporaryAdminPollResult

    /// Removes the computer from every configured elevation scope, then adds it
    /// to the demote-now scope. Returns a request handle for polling demotion.
    func requestDemotionNow(
        for detail: SupportDeviceDetail,
        reason: String,
        ticketReference: String?
    ) async throws -> TemporaryAdminElevationRequest
}

// MARK: - Service

/// The Temporary Admin Elevation feature service.
///
/// An actor so its only mutable state — the set of in-flight requests used to
/// block duplicates — is concurrency-safe. It performs no networking directly:
/// Jamf writes go through `JamfComputerRequestScopeServicing`, inventory reloads
/// go through `SupportTechnicianInventoryReloading`, and every material event is
/// reported through the shared diagnostics reporter.
actor TemporaryAdminElevationService: TemporaryAdminElevationServicing {
    private let configuration: TemporaryAdminElevationConfiguration
    private let requestScopeService: JamfComputerRequestScopeServicing
    private let diagnostics: any DiagnosticsReporting
    private let inventoryReloader: SupportTechnicianInventoryReloading
    private let dateProvider: @Sendable () -> Date

    /// In-flight requests keyed by computer inventory ID, used to block a
    /// duplicate active request for the same Mac from this app session.
    private var activeRequests: [String: TemporaryAdminElevationRequest] = [:]

    /// Tolerance (seconds) for treating a reported state as belonging to this
    /// request despite app/Mac clock skew.
    private let freshnessToleranceSeconds: TimeInterval = 120

    init(
        configuration: TemporaryAdminElevationConfiguration,
        requestScopeService: JamfComputerRequestScopeServicing,
        diagnostics: any DiagnosticsReporting,
        inventoryReloader: SupportTechnicianInventoryReloading,
        dateProvider: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.configuration = configuration
        self.requestScopeService = requestScopeService
        self.diagnostics = diagnostics
        self.inventoryReloader = inventoryReloader
        self.dateProvider = dateProvider
    }

    // MARK: loadSnapshot

    func loadSnapshot(for detail: SupportDeviceDetail) async throws -> TemporaryAdminElevationSnapshot {
        guard configuration.isFullyConfigured else {
            return TemporaryAdminElevationSnapshot(
                state: .notConfigured(reason: Self.notConfiguredReason),
                statusRawValue: nil,
                user: nil,
                expiresAt: nil,
                lastChange: nil,
                runId: nil
            )
        }
        return parseSnapshot(from: detail)
    }

    func refreshSnapshot(for detail: SupportDeviceDetail) async throws -> TemporaryAdminElevationSnapshot {
        guard configuration.isFullyConfigured else {
            return TemporaryAdminElevationSnapshot(
                state: .notConfigured(reason: Self.notConfiguredReason),
                statusRawValue: nil,
                user: nil,
                expiresAt: nil,
                lastChange: nil,
                runId: nil
            )
        }
        let fresh = try await inventoryReloader.reloadDetail(for: detail, bypassCache: true)
        return parseSnapshot(from: fresh)
    }

    // MARK: requestElevation

    func requestElevation(
        for detail: SupportDeviceDetail,
        duration: TemporaryAdminDuration,
        reason: String,
        ticketReference: String?
    ) async throws -> TemporaryAdminElevationRequest {
        guard configuration.isFullyConfigured else {
            throw TemporaryAdminElevationError.notConfigured
        }

        let summary = detail.summary
        let scope = configuration.scope(for: duration)
        let validation = TemporaryAdminElevationValidator.validate(
            assetType: summary.assetType,
            isManaged: Self.isManaged(summary),
            inventoryID: summary.inventoryID,
            duration: duration,
            hasConfiguredScope: scope?.isConfigured ?? false,
            reason: reason,
            ticketReference: ticketReference ?? "",
            requiresTicket: configuration.requireTicketReference
        )

        guard validation.isValid else {
            await report(
                category: TemporaryAdminDiagnostics.Category.validation,
                severity: .warning,
                message: "Temporary admin request failed validation.",
                metadata: baseMetadata(for: summary, duration: duration)
            )
            throw TemporaryAdminElevationError.validationFailed(messages: validation.messages)
        }

        guard let scope, scope.isConfigured else {
            throw TemporaryAdminElevationError.missingRequestScope(duration: duration.rawValue)
        }

        guard activeRequests[summary.inventoryID] == nil else {
            throw TemporaryAdminElevationError.duplicateActiveRequest
        }

        let request = TemporaryAdminElevationRequest(
            computerId: summary.inventoryID,
            serialNumber: summary.serialNumber,
            requestedAt: dateProvider(),
            duration: duration,
            reasonPresent: reason.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false,
            ticketReferencePresent: (ticketReference ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false,
            requestScope: scope
        )

        var metadata = baseMetadata(for: summary, duration: duration)
        metadata["request_scope_id"] = scope.id
        metadata["request_scope_name"] = scope.name
        metadata["app_request_id"] = request.id.uuidString
        metadata["reason_present"] = String(request.reasonPresent)
        metadata["ticket_reference_present"] = String(request.ticketReferencePresent)

        await report(
            category: TemporaryAdminDiagnostics.Category.request,
            severity: .info,
            message: "Submitting temporary admin elevation request to a Jamf request scope.",
            metadata: metadata
        )

        do {
            try await requestScopeService.addComputer(summary.inventoryID, toScope: scope)
        } catch {
            metadata["jamf_scope_changed"] = "false"
            metadata["safe_to_retry"] = String((error as? JamfFrameworkError).map { _ in true } ?? true)
            await report(
                category: error.isJamfInvalidPrivilege
                    ? TemporaryAdminDiagnostics.Category.permission
                    : TemporaryAdminDiagnostics.Category.scope,
                severity: .error,
                message: "Failed adding computer to temporary admin request scope.",
                metadata: metadata,
                errorDescription: error.localizedDescription
            )
            throw error
        }

        activeRequests[summary.inventoryID] = request
        metadata["jamf_scope_changed"] = "true"
        await report(
            category: TemporaryAdminDiagnostics.Category.scope,
            severity: .info,
            message: "Computer added to temporary admin request scope.",
            metadata: metadata
        )

        return request
    }

    // MARK: pollElevation

    func pollElevation(
        for detail: SupportDeviceDetail,
        request: TemporaryAdminElevationRequest
    ) async throws -> TemporaryAdminPollResult {
        let fresh = try await inventoryReloader.reloadDetail(for: detail, bypassCache: true)
        let snapshot = parseSnapshot(from: fresh)
        let now = dateProvider()

        let isFresh = isFreshForRequest(snapshot, requestedAt: request.requestedAt)
        if isTerminalMacState(snapshot.state), isFresh {
            let cleanupFailed = await cleanup(request, category: TemporaryAdminDiagnostics.Category.elevated)
            let finalSnapshot = cleanupFailed
                ? snapshot.with(state: .cleanupWarning(
                    message: Self.cleanupWarningMessage,
                    underlyingState: describe(snapshot.state)
                ))
                : snapshot
            return TemporaryAdminPollResult(snapshot: finalSnapshot, isComplete: true, didTimeout: false, cleanupFailed: cleanupFailed)
        }

        let timeoutInterval = TimeInterval(configuration.confirmationTimeoutMinutes * 60)
        if now.timeIntervalSince(request.requestedAt) > timeoutInterval {
            var cleanupFailed = false
            if configuration.cleanupAfterTimeout {
                cleanupFailed = await cleanup(request, category: TemporaryAdminDiagnostics.Category.timeout)
            } else {
                activeRequests[request.computerId] = nil
            }
            await report(
                category: TemporaryAdminDiagnostics.Category.timeout,
                severity: .warning,
                message: "Temporary admin request timed out before the Mac confirmed the policy ran.",
                metadata: pollMetadata(for: request)
            )
            let timedOutSnapshot = cleanupFailed
                ? snapshot.with(state: .cleanupWarning(message: Self.cleanupWarningMessage, underlyingState: "timedOut"))
                : snapshot.with(state: .timedOut)
            return TemporaryAdminPollResult(snapshot: timedOutSnapshot, isComplete: true, didTimeout: true, cleanupFailed: cleanupFailed)
        }

        // Still pending — keep the request marked waiting.
        return TemporaryAdminPollResult(
            snapshot: snapshot.with(state: .waitingForCheckIn(requestedAt: request.requestedAt)),
            isComplete: false,
            didTimeout: false,
            cleanupFailed: false
        )
    }

    // MARK: requestDemotionNow

    func requestDemotionNow(
        for detail: SupportDeviceDetail,
        reason: String,
        ticketReference: String?
    ) async throws -> TemporaryAdminElevationRequest {
        guard configuration.isFullyConfigured else {
            throw TemporaryAdminElevationError.notConfigured
        }

        let summary = detail.summary
        guard summary.assetType == .computer, summary.inventoryID.isEmpty == false else {
            throw TemporaryAdminElevationError.notEligible(reason: "Demotion is available for managed Macs only.")
        }

        let demoteScope = configuration.demoteNowScope
        guard demoteScope.isConfigured else {
            throw TemporaryAdminElevationError.missingRequestScope(duration: 0)
        }

        // Best-effort: remove from every configured elevation scope first so the
        // elevation policy stops re-running while demotion is requested.
        for duration in TemporaryAdminDuration.allCases {
            guard let scope = configuration.scope(for: duration), scope.isConfigured else { continue }
            do {
                try await requestScopeService.removeComputer(summary.inventoryID, fromScope: scope)
            } catch {
                await report(
                    category: TemporaryAdminDiagnostics.Category.cleanup,
                    severity: .warning,
                    message: "Best-effort removal from an elevation scope failed during demote-now.",
                    metadata: baseMetadata(for: summary, duration: duration),
                    errorDescription: error.localizedDescription
                )
            }
        }
        activeRequests[summary.inventoryID] = nil

        let request = TemporaryAdminElevationRequest(
            computerId: summary.inventoryID,
            serialNumber: summary.serialNumber,
            requestedAt: dateProvider(),
            duration: .five, // placeholder; demotion does not use a duration scope
            reasonPresent: reason.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false,
            ticketReferencePresent: (ticketReference ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false,
            requestScope: demoteScope
        )

        var metadata = baseMetadata(for: summary, duration: nil)
        metadata["request_scope_id"] = demoteScope.id
        metadata["request_scope_name"] = demoteScope.name
        metadata["app_request_id"] = request.id.uuidString

        await report(
            category: TemporaryAdminDiagnostics.Category.demote,
            severity: .info,
            message: "Submitting demote-now request to a Jamf request scope.",
            metadata: metadata
        )

        do {
            try await requestScopeService.addComputer(summary.inventoryID, toScope: demoteScope)
        } catch {
            metadata["jamf_scope_changed"] = "false"
            await report(
                category: error.isJamfInvalidPrivilege
                    ? TemporaryAdminDiagnostics.Category.permission
                    : TemporaryAdminDiagnostics.Category.demote,
                severity: .error,
                message: "Failed adding computer to demote-now request scope.",
                metadata: metadata,
                errorDescription: error.localizedDescription
            )
            throw error
        }

        // Track the demote request so its scope is cleaned up on completion.
        activeRequests[summary.inventoryID] = request
        metadata["jamf_scope_changed"] = "true"
        await report(
            category: TemporaryAdminDiagnostics.Category.demote,
            severity: .info,
            message: "Computer added to demote-now request scope.",
            metadata: metadata
        )

        return request
    }

    // MARK: - Cleanup

    /// Removes the computer from the request's scope and clears the active
    /// request. Returns `true` when cleanup could not be confirmed.
    private func cleanup(_ request: TemporaryAdminElevationRequest, category: String) async -> Bool {
        do {
            try await requestScopeService.removeComputer(request.computerId, fromScope: request.requestScope)
            activeRequests[request.computerId] = nil
            await report(
                category: TemporaryAdminDiagnostics.Category.cleanup,
                severity: .info,
                message: "Removed computer from temporary admin request scope.",
                metadata: pollMetadata(for: request)
            )
            return false
        } catch {
            // Keep the active marker so the UI can keep showing a cleanup
            // warning, but surface the failure.
            await report(
                category: TemporaryAdminDiagnostics.Category.cleanup,
                severity: .error,
                message: "Could not confirm removal of computer from temporary admin request scope.",
                metadata: pollMetadata(for: request),
                errorDescription: error.localizedDescription
            )
            return true
        }
    }

    // MARK: - Snapshot helpers

    private func parseSnapshot(from detail: SupportDeviceDetail) -> TemporaryAdminElevationSnapshot {
        TemporaryAdminElevationSnapshotParser.parse(
            extensionAttributes: detail.extensionAttributes,
            names: configuration.extensionAttributeNames,
            now: dateProvider()
        )
    }

    private func isTerminalMacState(_ state: TemporaryAdminElevationState) -> Bool {
        switch state {
        case .elevated, .alreadyAdmin, .demoted, .failed:
            return true
        default:
            return false
        }
    }

    private func isFreshForRequest(_ snapshot: TemporaryAdminElevationSnapshot, requestedAt: Date) -> Bool {
        guard let lastChange = snapshot.lastChange else {
            // Without a reported change time we cannot prove the state belongs
            // to this request, so we treat it as not-yet-fresh and keep waiting
            // (the timeout still bounds the wait).
            return false
        }
        return lastChange >= requestedAt.addingTimeInterval(-freshnessToleranceSeconds)
    }

    private func describe(_ state: TemporaryAdminElevationState) -> String {
        switch state {
        case .elevated: return "elevated"
        case .alreadyAdmin: return "alreadyAdmin"
        case .demoted: return "demoted"
        case .failed: return "failed"
        case .timedOut: return "timedOut"
        default: return "pending"
        }
    }

    // MARK: - Managed heuristic

    /// A computer is treated as managed when Jamf reports a management ID for
    /// it — managed (enrolled) Macs are the only ones a policy can run on.
    nonisolated static func isManaged(_ summary: SupportSearchResult) -> Bool {
        let managementID = summary.managementID?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let clientManagementID = summary.clientManagementID?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return managementID.isEmpty == false || clientManagementID.isEmpty == false
    }

    // MARK: - Diagnostics helpers

    private func report(
        category: String,
        severity: DiagnosticSeverity,
        message: String,
        metadata: [String: String],
        errorDescription: String? = nil
    ) async {
        var enriched = metadata
        if let errorDescription {
            enriched["error_description"] = errorDescription
        }
        await diagnostics.report(
            source: TemporaryAdminDiagnostics.source,
            category: category,
            severity: severity,
            message: message,
            metadata: enriched
        )
    }

    private func baseMetadata(for summary: SupportSearchResult, duration: TemporaryAdminDuration?) -> [String: String] {
        var metadata: [String: String] = [
            "module": "support-technician",
            "feature": "temporary-admin-elevation",
            "computer_id": summary.inventoryID,
            "serial_number": summary.serialNumber,
            "device_name": summary.displayName
        ]
        if let duration {
            metadata["duration_minutes"] = String(duration.rawValue)
        }
        return metadata
    }

    private func pollMetadata(for request: TemporaryAdminElevationRequest) -> [String: String] {
        [
            "module": "support-technician",
            "feature": "temporary-admin-elevation",
            "computer_id": request.computerId,
            "serial_number": request.serialNumber,
            "duration_minutes": String(request.duration.rawValue),
            "request_scope_id": request.requestScope.id,
            "request_scope_name": request.requestScope.name,
            "app_request_id": request.id.uuidString
        ]
    }

    // MARK: - Copy

    nonisolated static let notConfiguredReason = """
    Temporary Admin Elevation is not configured. A Jamf administrator must create the required request groups, policies, scripts, and Computer Extension Attributes before this action can be used.

    No Mac permissions were changed.
    """

    nonisolated static let cleanupWarningMessage = "The Mac state was updated, but request-scope cleanup could not be confirmed. Remove the Mac from the temporary admin request group in Jamf Pro."
}

// MARK: - Snapshot mutation

extension TemporaryAdminElevationSnapshot {
    /// Returns a copy with a replaced state, preserving the parsed fields.
    nonisolated func with(state: TemporaryAdminElevationState) -> TemporaryAdminElevationSnapshot {
        TemporaryAdminElevationSnapshot(
            state: state,
            statusRawValue: statusRawValue,
            user: user,
            expiresAt: expiresAt,
            lastChange: lastChange,
            runId: runId
        )
    }
}
