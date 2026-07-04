import Foundation
@testable import ForsettiJamfProApp

// MARK: - Fixtures

enum TemporaryAdminTestSupport {

    /// An enabled, fully-configured feature configuration for tests.
    static func enabledConfiguration(requireTicket: Bool = true) -> TemporaryAdminElevationConfiguration {
        TemporaryAdminElevationConfiguration(
            enabled: true,
            requireTicketReference: requireTicket,
            pollIntervalSeconds: 30,
            confirmationTimeoutMinutes: 25,
            cleanupAfterTimeout: true,
            allowedDurationsMinutes: [5, 15, 30, 60],
            requestScopes: [
                "5": JamfComputerRequestScope(id: "501", name: "Temp Admin 5m", kind: "staticComputerGroup"),
                "15": JamfComputerRequestScope(id: "515", name: "Temp Admin 15m", kind: "staticComputerGroup"),
                "30": JamfComputerRequestScope(id: "530", name: "Temp Admin 30m", kind: "staticComputerGroup"),
                "60": JamfComputerRequestScope(id: "560", name: "Temp Admin 60m", kind: "staticComputerGroup")
            ],
            demoteNowScope: JamfComputerRequestScope(id: "590", name: "Temp Admin Demote Now", kind: "staticComputerGroup"),
            extensionAttributeNames: standardEANames
        )
    }

    static let standardEANames = TemporaryAdminExtensionAttributeNames(
        status: "Forsetti Jamf Pro - Temporary Admin Status",
        user: "Forsetti Jamf Pro - Temporary Admin User",
        expiresAt: "Forsetti Jamf Pro - Temporary Admin Expires At",
        lastChange: "Forsetti Jamf Pro - Temporary Admin Last Change",
        runId: "Forsetti Jamf Pro - Temporary Admin Run ID"
    )

    /// Builds a device detail with the given asset type, management state, and
    /// extension attributes.
    static func makeDetail(
        assetType: SupportAssetType = .computer,
        inventoryID: String = "1234",
        managed: Bool = true,
        serial: String = "C02TESTSERIAL",
        name: String = "Test Mac",
        extensionAttributes: [SupportExtensionAttribute] = []
    ) -> SupportDeviceDetail {
        let summary = SupportSearchResult(
            assetType: assetType,
            inventoryID: inventoryID,
            managementID: managed ? "mgmt-\(inventoryID)" : nil,
            clientManagementID: managed ? "client-\(inventoryID)" : nil,
            displayName: name,
            serialNumber: serial,
            username: "consoleuser",
            email: nil,
            model: "MacBookPro18,1",
            osVersion: "15.0",
            lastInventoryUpdate: nil,
            prestageEnrollment: nil,
            automatedDeviceEnrollment: nil
        )
        return SupportDeviceDetail(
            summary: summary,
            diagnostics: [],
            sections: [],
            applications: [],
            rawJSON: "{}",
            extensionAttributes: extensionAttributes
        )
    }

    /// Builds the five status EAs for a given reported state.
    static func statusEAs(
        status: String,
        user: String? = "consoleuser",
        expiresISO: String? = nil,
        lastChangeISO: String? = nil,
        runId: String? = nil,
        names: TemporaryAdminExtensionAttributeNames = standardEANames
    ) -> [SupportExtensionAttribute] {
        func ea(_ name: String, _ value: String?) -> SupportExtensionAttribute {
            SupportExtensionAttribute(attributeID: name, name: name, value: value ?? "Not Reported", type: "String", category: nil)
        }
        return [
            ea(names.status, status),
            ea(names.user, user),
            ea(names.expiresAt, expiresISO),
            ea(names.lastChange, lastChangeISO),
            ea(names.runId, runId)
        ]
    }

    static func iso(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.string(from: date)
    }
}

// MARK: - Recording diagnostics

/// Records every reported diagnostic event so tests can assert categories.
actor RecordingDiagnostics: DiagnosticsReporting {
    private(set) var events: [DiagnosticEvent] = []

    func report(source: String, category: String, severity: DiagnosticSeverity, message: String, metadata: [String: String]) async {
        events.append(DiagnosticEvent(source: source, category: category, severity: severity, message: message, metadata: metadata))
    }

    func currentEvents() async -> [DiagnosticEvent] { events }
    func renderJSONReportData() async throws -> Data { Data() }
    func renderMarkdownReportData() async throws -> Data { Data() }
    func suggestedExportFileName(extension ext: String) async -> String { "test.\(ext)" }
    func clear() async { events.removeAll() }
    func persistentLogFileURL() async -> URL? { nil }

    func categories() -> [String] { events.map(\.category) }
    func hasCategory(_ category: String) -> Bool { events.contains { $0.category == category } }
}

// MARK: - Mock request-scope service

/// Records scope membership mutations and can be primed to throw.
actor MockRequestScopeService: JamfComputerRequestScopeServicing {
    struct Call: Equatable {
        let action: String      // "add" or "remove"
        let computerId: String
        let scopeId: String
    }

    private(set) var calls: [Call] = []
    private var addError: Error?
    private var removeError: Error?

    init(addError: Error? = nil, removeError: Error? = nil) {
        self.addError = addError
        self.removeError = removeError
    }

    func addComputer(_ computerId: String, toScope scope: JamfComputerRequestScope) async throws {
        calls.append(Call(action: "add", computerId: computerId, scopeId: scope.id))
        if let addError { throw addError }
    }

    func removeComputer(_ computerId: String, fromScope scope: JamfComputerRequestScope) async throws {
        calls.append(Call(action: "remove", computerId: computerId, scopeId: scope.id))
        if let removeError { throw removeError }
    }

    func recordedCalls() -> [Call] { calls }
    func addCalls() -> [Call] { calls.filter { $0.action == "add" } }
    func removeCalls() -> [Call] { calls.filter { $0.action == "remove" } }
}

// MARK: - Mock inventory reloader

/// Returns a sequence of details (one per poll) so tests can model a Mac
/// transitioning through states. The last detail repeats once exhausted.
actor MockInventoryReloader: SupportTechnicianInventoryReloading {
    private var details: [SupportDeviceDetail]
    private var index = 0
    private var error: Error?

    init(details: [SupportDeviceDetail], error: Error? = nil) {
        self.details = details
        self.error = error
    }

    func reloadDetail(for detail: SupportDeviceDetail, bypassCache: Bool) async throws -> SupportDeviceDetail {
        if let error { throw error }
        guard details.isEmpty == false else { return detail }
        let next = details[min(index, details.count - 1)]
        index += 1
        return next
    }
}

// MARK: - Mock request performer (for the request-scope adapter)

/// Minimal `JamfRequestPerforming` mock: returns a canned GET body and records
/// the PUT body so the read-modify-write adapter can be verified.
actor MockRequestPerformer: JamfRequestPerforming {
    private let getResponse: Data
    private(set) var putBodies: [Data] = []
    private(set) var requestedPaths: [String] = []
    private(set) var requestedMethods: [HTTPMethod] = []

    init(getResponse: Data) {
        self.getResponse = getResponse
    }

    func request(path: String, method: HTTPMethod, queryItems: [URLQueryItem], body: Data?, additionalHeaders: [String: String]) async throws -> Data {
        requestedPaths.append(path)
        requestedMethods.append(method)
        if method == .put {
            putBodies.append(body ?? Data())
            return Data()
        }
        return getResponse
    }

    func recordedPutBodies() -> [Data] { putBodies }
    func methods() -> [HTTPMethod] { requestedMethods }
}

// MARK: - Mock feature service (for controller tests)

/// Scriptable `TemporaryAdminElevationServicing` for view-model/controller tests.
actor MockTemporaryAdminService: TemporaryAdminElevationServicing {
    var loadSnapshotResult: TemporaryAdminElevationSnapshot
    var refreshSnapshotResult: TemporaryAdminElevationSnapshot
    var requestError: Error?
    var demoteError: Error?
    var pollResults: [TemporaryAdminPollResult]
    private var pollIndex = 0

    private(set) var requestCount = 0
    private(set) var demoteCount = 0
    private(set) var lastRequestedDuration: TemporaryAdminDuration?

    init(
        loadSnapshotResult: TemporaryAdminElevationSnapshot = .notReported,
        refreshSnapshotResult: TemporaryAdminElevationSnapshot = .notReported,
        requestError: Error? = nil,
        demoteError: Error? = nil,
        pollResults: [TemporaryAdminPollResult] = []
    ) {
        self.loadSnapshotResult = loadSnapshotResult
        self.refreshSnapshotResult = refreshSnapshotResult
        self.requestError = requestError
        self.demoteError = demoteError
        self.pollResults = pollResults
    }

    func loadSnapshot(for detail: SupportDeviceDetail) async throws -> TemporaryAdminElevationSnapshot {
        loadSnapshotResult
    }

    func refreshSnapshot(for detail: SupportDeviceDetail) async throws -> TemporaryAdminElevationSnapshot {
        refreshSnapshotResult
    }

    func requestElevation(for detail: SupportDeviceDetail, duration: TemporaryAdminDuration, reason: String, ticketReference: String?) async throws -> TemporaryAdminElevationRequest {
        requestCount += 1
        lastRequestedDuration = duration
        if let requestError { throw requestError }
        return TemporaryAdminElevationRequest(
            computerId: detail.summary.inventoryID,
            serialNumber: detail.summary.serialNumber,
            requestedAt: Date(),
            duration: duration,
            reasonPresent: reason.isEmpty == false,
            ticketReferencePresent: (ticketReference ?? "").isEmpty == false,
            requestScope: JamfComputerRequestScope(id: "5\(duration.rawValue)", name: "scope", kind: "staticComputerGroup")
        )
    }

    func pollElevation(for detail: SupportDeviceDetail, request: TemporaryAdminElevationRequest) async throws -> TemporaryAdminPollResult {
        guard pollResults.isEmpty == false else {
            return TemporaryAdminPollResult(snapshot: .notReported, isComplete: true, didTimeout: false, cleanupFailed: false)
        }
        let result = pollResults[min(pollIndex, pollResults.count - 1)]
        pollIndex += 1
        return result
    }

    func requestDemotionNow(for detail: SupportDeviceDetail, reason: String, ticketReference: String?) async throws -> TemporaryAdminElevationRequest {
        demoteCount += 1
        if let demoteError { throw demoteError }
        return TemporaryAdminElevationRequest(
            computerId: detail.summary.inventoryID,
            serialNumber: detail.summary.serialNumber,
            requestedAt: Date(),
            duration: .five,
            reasonPresent: reason.isEmpty == false,
            ticketReferencePresent: (ticketReference ?? "").isEmpty == false,
            requestScope: JamfComputerRequestScope(id: "590", name: "demote", kind: "staticComputerGroup")
        )
    }

    func requests() -> Int { requestCount }
    func demotes() -> Int { demoteCount }
    func requestedDuration() -> TemporaryAdminDuration? { lastRequestedDuration }
}
