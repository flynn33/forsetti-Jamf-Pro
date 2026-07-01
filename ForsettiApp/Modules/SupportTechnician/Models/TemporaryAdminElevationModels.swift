import Foundation

// MARK: - Duration

/// The bounded set of temporary-admin durations a technician may request.
///
/// Phase 1 allows only these four values; the Mac-side elevation script refuses
/// any other duration, so the app and the script agree on the same closed set.
nonisolated enum TemporaryAdminDuration: Int, CaseIterable, Identifiable, Codable, Sendable {
    case five = 5
    case fifteen = 15
    case thirty = 30
    case sixty = 60

    var id: Int { rawValue }

    /// Key used to look the duration up in the configuration's `requestScopes`
    /// map (the manifest/config encodes the map with string keys).
    var configurationKey: String { String(rawValue) }

    var displayName: String { "\(rawValue) minutes" }

    var accessibilityLabel: String { "\(rawValue) minutes" }
}

// MARK: - Request scope

/// A dedicated Jamf request scope (a static computer group) used only by this
/// workflow. The app changes a Mac's membership in one of these groups to
/// request a pre-created policy run; it never creates groups, policies, or
/// scripts.
nonisolated struct JamfComputerRequestScope: Codable, Hashable, Sendable {
    let id: String
    let name: String
    let kind: String

    /// A request scope is usable only when it has a configured Jamf object ID.
    var isConfigured: Bool {
        id.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
    }
}

// MARK: - Extension attribute names

/// The display names of the five Computer Extension Attributes the Mac-side
/// scripts populate. The snapshot parser matches reported EAs by these names.
nonisolated struct TemporaryAdminExtensionAttributeNames: Codable, Equatable, Sendable {
    let status: String
    let user: String
    let expiresAt: String
    let lastChange: String
    let runId: String
}

// MARK: - Configuration

/// Tenant configuration for Temporary Admin Elevation.
///
/// Tenant object IDs are never hardcoded in views. The configuration is decoded
/// from the module manifest / bundled defaults; when no tenant has been
/// configured the bundled default is `disabled`, which keeps the feature off
/// and surfaces an actionable "not configured" message instead of any control.
nonisolated struct TemporaryAdminElevationConfiguration: Codable, Equatable, Sendable {
    let enabled: Bool
    let requireTicketReference: Bool
    let pollIntervalSeconds: Int
    let confirmationTimeoutMinutes: Int
    let cleanupAfterTimeout: Bool
    let allowedDurationsMinutes: [Int]
    let requestScopes: [String: JamfComputerRequestScope]
    let demoteNowScope: JamfComputerRequestScope
    let extensionAttributeNames: TemporaryAdminExtensionAttributeNames

    enum CodingKeys: String, CodingKey {
        case enabled
        case requireTicketReference
        case pollIntervalSeconds
        case confirmationTimeoutMinutes
        case cleanupAfterTimeout
        case allowedDurationsMinutes
        case requestScopes
        case demoteNowScope
        case extensionAttributeNames
    }

    init(
        enabled: Bool,
        requireTicketReference: Bool,
        pollIntervalSeconds: Int,
        confirmationTimeoutMinutes: Int,
        cleanupAfterTimeout: Bool,
        allowedDurationsMinutes: [Int],
        requestScopes: [String: JamfComputerRequestScope],
        demoteNowScope: JamfComputerRequestScope,
        extensionAttributeNames: TemporaryAdminExtensionAttributeNames
    ) {
        self.enabled = enabled
        self.requireTicketReference = requireTicketReference
        self.pollIntervalSeconds = pollIntervalSeconds
        self.confirmationTimeoutMinutes = confirmationTimeoutMinutes
        self.cleanupAfterTimeout = cleanupAfterTimeout
        self.allowedDurationsMinutes = allowedDurationsMinutes
        self.requestScopes = requestScopes
        self.demoteNowScope = demoteNowScope
        self.extensionAttributeNames = extensionAttributeNames
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        enabled = try container.decode(Bool.self, forKey: .enabled)
        requireTicketReference = try container.decode(Bool.self, forKey: .requireTicketReference)
        pollIntervalSeconds = try container.decode(Int.self, forKey: .pollIntervalSeconds)
        confirmationTimeoutMinutes = try container.decode(Int.self, forKey: .confirmationTimeoutMinutes)
        // Backward-compatible: absent means "clean up after timeout".
        cleanupAfterTimeout = try container.decodeIfPresent(Bool.self, forKey: .cleanupAfterTimeout) ?? true
        allowedDurationsMinutes = try container.decodeIfPresent([Int].self, forKey: .allowedDurationsMinutes)
            ?? TemporaryAdminDuration.allCases.map(\.rawValue)
        requestScopes = try container.decode([String: JamfComputerRequestScope].self, forKey: .requestScopes)
        demoteNowScope = try container.decode(JamfComputerRequestScope.self, forKey: .demoteNowScope)
        extensionAttributeNames = try container.decode(
            TemporaryAdminExtensionAttributeNames.self,
            forKey: .extensionAttributeNames
        )
    }

    /// The configured request scope for a duration, if present.
    func scope(for duration: TemporaryAdminDuration) -> JamfComputerRequestScope? {
        requestScopes[duration.configurationKey]
    }

    /// The durations that are both in the approved set and have a configured,
    /// usable request scope.
    var availableDurations: [TemporaryAdminDuration] {
        TemporaryAdminDuration.allCases.filter { duration in
            allowedDurationsMinutes.contains(duration.rawValue)
                && (scope(for: duration)?.isConfigured ?? false)
        }
    }

    /// Whether the configuration is enabled and fully wired (every approved
    /// duration has a configured scope, the demote-now scope is configured, and
    /// every extension-attribute name is non-empty). When this is false the UI
    /// shows the "not configured" message rather than any control.
    var isFullyConfigured: Bool {
        guard enabled else { return false }
        guard demoteNowScope.isConfigured else { return false }
        let durations = TemporaryAdminDuration.allCases.filter { allowedDurationsMinutes.contains($0.rawValue) }
        guard durations.isEmpty == false else { return false }
        for duration in durations where (scope(for: duration)?.isConfigured ?? false) == false {
            return false
        }
        let names = [
            extensionAttributeNames.status,
            extensionAttributeNames.user,
            extensionAttributeNames.expiresAt,
            extensionAttributeNames.lastChange,
            extensionAttributeNames.runId
        ]
        return names.allSatisfy { $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false }
    }

    /// The bundled, disabled-by-default configuration. The feature ships off
    /// until a Jamf administrator supplies the dedicated request-group IDs.
    static let disabledDefault = TemporaryAdminElevationConfiguration(
        enabled: false,
        requireTicketReference: true,
        pollIntervalSeconds: 30,
        confirmationTimeoutMinutes: 25,
        cleanupAfterTimeout: true,
        allowedDurationsMinutes: TemporaryAdminDuration.allCases.map(\.rawValue),
        requestScopes: [
            "5": JamfComputerRequestScope(id: "", name: "Forsetti - Temp Admin Requests - 5m", kind: "staticComputerGroup"),
            "15": JamfComputerRequestScope(id: "", name: "Forsetti - Temp Admin Requests - 15m", kind: "staticComputerGroup"),
            "30": JamfComputerRequestScope(id: "", name: "Forsetti - Temp Admin Requests - 30m", kind: "staticComputerGroup"),
            "60": JamfComputerRequestScope(id: "", name: "Forsetti - Temp Admin Requests - 60m", kind: "staticComputerGroup")
        ],
        demoteNowScope: JamfComputerRequestScope(id: "", name: "Forsetti - Temp Admin Demote Now", kind: "staticComputerGroup"),
        extensionAttributeNames: TemporaryAdminExtensionAttributeNames(
            status: "Forsetti - Temporary Admin Status",
            user: "Forsetti - Temporary Admin User",
            expiresAt: "Forsetti - Temporary Admin Expires At",
            lastChange: "Forsetti - Temporary Admin Last Change",
            runId: "Forsetti - Temporary Admin Run ID"
        )
    )
}

// MARK: - Status raw values

/// The status values the Mac-side scripts write into the status extension
/// attribute. Kept in one place so the parser and the scripts agree.
nonisolated enum TemporaryAdminStatusValue {
    static let notRequested = "not_requested"
    static let elevated = "elevated"
    static let alreadyAdmin = "already_admin"
    static let demoted = "demoted"
    static let expiredPendingDemotion = "expired_pending_demotion"
    static let failed = "failed"
    /// Default emitted by the EA scripts when no state file exists.
    static let notReported = "not reported"
}

// MARK: - State

/// The app-facing state of temporary admin for the selected Mac.
///
/// The frame switches over this exhaustively, so every case must remain
/// represented in the view.
nonisolated enum TemporaryAdminElevationState: Equatable, Sendable {
    case unavailable(reason: String)
    case notConfigured(reason: String)
    case ready
    case validating
    case requesting
    case waitingForCheckIn(requestedAt: Date)
    case elevated(user: String, expiresAt: Date?, runId: String?)
    case alreadyAdmin(user: String, runId: String?)
    case demotionRequested(requestedAt: Date)
    case demoted(user: String?, runId: String?)
    case timedOut
    case failed(message: String)
    case permissionDenied(requiredPrivileges: [String])
    case cleanupWarning(message: String, underlyingState: String)
}

// MARK: - Request

/// App-side correlation metadata for an in-flight elevation request.
///
/// Request-scope membership does not pass a per-request ID to the Mac, so this
/// ID is app-side only. Correlation back to the Mac uses computer ID, serial,
/// `requestedAt`, status, user, expiration, and run-ID freshness.
nonisolated struct TemporaryAdminElevationRequest: Identifiable, Equatable, Sendable {
    let id: UUID
    let computerId: String
    let serialNumber: String
    let requestedAt: Date
    let duration: TemporaryAdminDuration
    let reasonPresent: Bool
    let ticketReferencePresent: Bool
    let requestScope: JamfComputerRequestScope

    init(
        id: UUID = UUID(),
        computerId: String,
        serialNumber: String,
        requestedAt: Date,
        duration: TemporaryAdminDuration,
        reasonPresent: Bool,
        ticketReferencePresent: Bool,
        requestScope: JamfComputerRequestScope
    ) {
        self.id = id
        self.computerId = computerId
        self.serialNumber = serialNumber
        self.requestedAt = requestedAt
        self.duration = duration
        self.reasonPresent = reasonPresent
        self.ticketReferencePresent = ticketReferencePresent
        self.requestScope = requestScope
    }
}

// MARK: - Snapshot

/// A parsed snapshot of the Mac's reported temporary-admin state, derived from
/// the five Computer Extension Attributes.
nonisolated struct TemporaryAdminElevationSnapshot: Equatable, Sendable {
    let state: TemporaryAdminElevationState
    let statusRawValue: String?
    let user: String?
    let expiresAt: Date?
    let lastChange: Date?
    let runId: String?

    /// A snapshot for a Mac that has never reported (no state file yet).
    static let notReported = TemporaryAdminElevationSnapshot(
        state: .ready,
        statusRawValue: nil,
        user: nil,
        expiresAt: nil,
        lastChange: nil,
        runId: nil
    )
}

// MARK: - Validation

/// The result of validating a request before it is sent.
nonisolated struct TemporaryAdminValidationResult: Equatable, Sendable {
    let isValid: Bool
    let messages: [String]

    static let valid = TemporaryAdminValidationResult(isValid: true, messages: [])

    static func invalid(_ messages: [String]) -> TemporaryAdminValidationResult {
        TemporaryAdminValidationResult(isValid: false, messages: messages)
    }
}

// MARK: - User-facing error

/// A normalized, technician-readable error. Distinguishes whether local Mac
/// state or Jamf scope membership changed, lists required privileges, and
/// carries a diagnostics correlation reference.
nonisolated struct TemporaryAdminUserFacingError: Identifiable, Equatable, Sendable {
    let id: UUID
    let title: String
    let summary: String
    let technicalCause: String
    let requiredJamfPrivileges: [String]
    let localMacStateChanged: Bool?
    let jamfScopeChanged: Bool?
    let safeToRetry: Bool
    let recommendedAction: String
    let diagnosticsCategory: String
    let diagnosticsCorrelationId: String?

    init(
        id: UUID = UUID(),
        title: String,
        summary: String,
        technicalCause: String,
        requiredJamfPrivileges: [String] = [],
        localMacStateChanged: Bool? = nil,
        jamfScopeChanged: Bool? = nil,
        safeToRetry: Bool,
        recommendedAction: String,
        diagnosticsCategory: String,
        diagnosticsCorrelationId: String? = nil
    ) {
        self.id = id
        self.title = title
        self.summary = summary
        self.technicalCause = technicalCause
        self.requiredJamfPrivileges = requiredJamfPrivileges
        self.localMacStateChanged = localMacStateChanged
        self.jamfScopeChanged = jamfScopeChanged
        self.safeToRetry = safeToRetry
        self.recommendedAction = recommendedAction
        self.diagnosticsCategory = diagnosticsCategory
        self.diagnosticsCorrelationId = diagnosticsCorrelationId
    }
}

// MARK: - Thrown error

/// Errors thrown by the temporary-admin feature service before/around Jamf
/// calls. Gateway/network errors are surfaced as their own framework errors and
/// mapped to `TemporaryAdminUserFacingError` at the view-model boundary.
nonisolated enum TemporaryAdminElevationError: Error, Equatable, Sendable {
    case notConfigured
    case notEligible(reason: String)
    case validationFailed(messages: [String])
    case missingRequestScope(duration: Int)
    case duplicateActiveRequest
}
