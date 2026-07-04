import Foundation

// Module-local value types backing the Apple-native Remote Support workflow. Pure, Sendable,
// and independently testable — no Jamf networking, no view state, no diagnostics side effects.

/// Where a resolved Screen Sharing connection target came from. The source determines how much
/// confidence the UI should communicate about reachability.
nonisolated enum SupportRemoteSupportTargetSource: String, Sendable, Hashable, CaseIterable {
    /// A hostname/IP the technician typed manually.
    case manualOverride
    /// The inventory-reported hostname.
    case inventoryHostname
    /// The last reported IPv4 address.
    case lastReportedIPv4
    /// The current inventory IP address.
    case currentIPAddress
    /// The last reported IP address (v4 or v6).
    case lastReportedIP
    /// The display name, used directly because it is already a valid FQDN or IP.
    case displayNameHost
    /// A Bonjour `displayName.local` fallback, only when the name is Bonjour-safe.
    case bonjourLocal

    /// Human-readable source label for UI and diagnostics.
    var label: String {
        switch self {
        case .manualOverride:   return "Manual override"
        case .inventoryHostname: return "Inventory hostname"
        case .lastReportedIPv4: return "Last reported IPv4"
        case .currentIPAddress: return "Current IP address"
        case .lastReportedIP:   return "Last reported IP"
        case .displayNameHost:  return "Display name"
        case .bonjourLocal:     return "Bonjour (.local)"
        }
    }

    /// How likely the resolved target is to be reachable.
    var confidence: SupportRemoteSupportTargetConfidence {
        switch self {
        case .manualOverride, .inventoryHostname, .lastReportedIPv4, .displayNameHost:
            return .high
        case .currentIPAddress, .lastReportedIP:
            return .medium
        case .bonjourLocal:
            return .low
        }
    }
}

/// Confidence that a resolved target is reachable. Reachability is never guaranteed from
/// inventory data alone, so the UI must communicate this honestly.
nonisolated enum SupportRemoteSupportTargetConfidence: String, Sendable, Hashable {
    case high
    case medium
    case low

    var label: String {
        switch self {
        case .high:   return "High"
        case .medium: return "Medium"
        case .low:    return "Low"
        }
    }
}

/// A usable connection target for native Screen Sharing.
nonisolated struct SupportRemoteSupportTarget: Sendable, Hashable {
    /// The host used to build the `vnc://` URL (hostname, FQDN, or IP). Never a serial number.
    let host: String
    /// Where the host came from.
    let source: SupportRemoteSupportTargetSource

    /// Reachability confidence, derived from the source.
    var confidence: SupportRemoteSupportTargetConfidence { source.confidence }

    /// The native Screen Sharing launch URL, with the host percent-encoded. `nil` if the host
    /// cannot form a valid URL — callers must not open a `vnc://` URL when this is `nil`.
    var screenSharingURL: URL? {
        guard let encoded = host.addingPercentEncoding(withAllowedCharacters: .urlHostAllowed),
              encoded.isEmpty == false
        else {
            return nil
        }
        return URL(string: "vnc://\(encoded)")
    }
}

/// The outcome of resolving a connection target for a device.
nonisolated enum SupportRemoteSupportTargetResolution: Sendable, Hashable {
    /// A usable target was found.
    case resolved(SupportRemoteSupportTarget)
    /// No usable target; `reason` explains why Open Screen Sharing is disabled.
    case unresolved(reason: String)

    /// The resolved target, if any.
    var target: SupportRemoteSupportTarget? {
        if case let .resolved(target) = self { return target }
        return nil
    }

    /// The disabled reason, if unresolved.
    var unresolvedReason: String? {
        if case let .unresolved(reason) = self { return reason }
        return nil
    }

    /// Whether a usable target was resolved.
    var isResolved: Bool { target != nil }
}

// MARK: - Failure

/// A Remote Support failure carrying the retry guidance the UI must preserve. Phase-6
/// diagnostics mapping enriches the privilege/technical detail; this is the minimum the
/// state machine needs to keep failed states actionable.
nonisolated struct SupportRemoteSupportFailure: Sendable, Hashable {
    /// Plain-language summary of what went wrong.
    let summary: String
    /// Whether re-attempting the workflow is safe.
    let isSafeToRetry: Bool
    /// Recommended next action for the technician.
    let recommendation: String
    /// The required Jamf privilege when a 403 was mapped (filled by the Phase-6 mapper).
    let requiredPrivilege: String?

    init(summary: String, isSafeToRetry: Bool, recommendation: String, requiredPrivilege: String? = nil) {
        self.summary = summary
        self.isSafeToRetry = isSafeToRetry
        self.recommendation = recommendation
        self.requiredPrivilege = requiredPrivilege
    }
}

// MARK: - State

/// What the Remote Support workflow knows right now for the selected Mac.
///
/// The states deliberately separate "Jamf accepted the enable command" from "the Mac is ready"
/// and from "Screen Sharing launched" — queue acceptance is never treated as readiness, and a
/// `vnc://` launch only happens on explicit technician action from `readyToOpen`.
nonisolated enum SupportRemoteSupportState: Sendable, Equatable {
    case unsupported(reason: String)
    case needsManagementID
    case readyToPrepare
    case queueingEnableCommand
    case queuedWaitingForCheckIn(commandID: String?)
    case readinessUnknown(commandID: String?)
    case readyToOpen(target: SupportRemoteSupportTarget)
    case launchRequested(target: SupportRemoteSupportTarget)
    case cleanupAvailable(target: SupportRemoteSupportTarget?)
    case queueingDisableCommand
    case ended
    case failed(SupportRemoteSupportFailure)

    /// Open Screen Sharing is permitted ONLY here — never directly after queueing.
    var canOpenScreenSharing: Bool {
        if case .readyToOpen = self { return true }
        return false
    }

    /// The usable target associated with later states, if any.
    var target: SupportRemoteSupportTarget? {
        switch self {
        case let .readyToOpen(target), let .launchRequested(target):
            return target
        case let .cleanupAvailable(target):
            return target
        default:
            return nil
        }
    }

    /// Whether the Enable Remote Management control is available.
    var allowsEnable: Bool {
        if case .readyToPrepare = self { return true }
        return false
    }

    /// Whether the Disable Remote Management (cleanup) control is available.
    var allowsDisable: Bool {
        if case .cleanupAvailable = self { return true }
        return false
    }

    /// Whether a retry is offered (only for safe-to-retry failures).
    var allowsRetry: Bool {
        if case let .failed(failure) = self { return failure.isSafeToRetry }
        return false
    }

    /// Whether a Jamf command is currently being queued (controls should show progress).
    var isBusy: Bool {
        switch self {
        case .queueingEnableCommand, .queueingDisableCommand:
            return true
        default:
            return false
        }
    }

    /// Whether the workflow has reached a terminal state.
    var isTerminal: Bool {
        switch self {
        case .ended, .unsupported, .needsManagementID:
            return true
        default:
            return false
        }
    }

    /// Short status headline for the UI (state is never represented by ad hoc view strings).
    var headline: String {
        switch self {
        case .unsupported:             return "Remote Support unavailable"
        case .needsManagementID:       return "Management ID required"
        case .readyToPrepare:          return "Ready to enable Remote Management"
        case .queueingEnableCommand:   return "Queueing Enable Remote Management…"
        case .queuedWaitingForCheckIn: return "Queued — waiting for the Mac to check in"
        case .readinessUnknown:        return "Readiness not confirmed"
        case .readyToOpen:             return "Ready to open Screen Sharing"
        case .launchRequested:         return "Screen Sharing launch requested"
        case .cleanupAvailable:        return "Cleanup available"
        case .queueingDisableCommand:  return "Queueing Disable Remote Management…"
        case .ended:                   return "Remote Support session ended"
        case .failed:                  return "Remote Support failed"
        }
    }

    /// Stable, machine-readable state token for diagnostics metadata (never localized).
    var diagnosticsName: String {
        switch self {
        case .unsupported:             return "unsupported"
        case .needsManagementID:       return "needs_management_id"
        case .readyToPrepare:          return "ready_to_prepare"
        case .queueingEnableCommand:   return "queueing_enable_command"
        case .queuedWaitingForCheckIn: return "queued_waiting_for_check_in"
        case .readinessUnknown:        return "readiness_unknown"
        case .readyToOpen:             return "ready_to_open"
        case .launchRequested:         return "launch_requested"
        case .cleanupAvailable:        return "cleanup_available"
        case .queueingDisableCommand:  return "queueing_disable_command"
        case .ended:                   return "ended"
        case .failed:                  return "failed"
        }
    }
}

// MARK: - Session

/// A single Remote Support workflow instance for the selected Mac — the audit/context record.
/// The canonical live `state` is owned by `SupportRemoteSupportCoordinator`.
nonisolated struct SupportRemoteSupportSession: Sendable, Identifiable, Equatable {
    let id: UUID
    let inventoryID: String
    let managementID: String?
    let serialNumber: String
    let displayName: String
    let startedAt: Date
    var endedAt: Date?
    var enableCommandID: String?
    var disableCommandID: String?
    var connectionTarget: SupportRemoteSupportTarget?
    var connectionTargetSource: SupportRemoteSupportTargetSource?
    var ticketReference: String?
    var reason: String?

    init(
        id: UUID = UUID(),
        inventoryID: String,
        managementID: String?,
        serialNumber: String,
        displayName: String,
        startedAt: Date,
        ticketReference: String? = nil,
        reason: String? = nil
    ) {
        self.id = id
        self.inventoryID = inventoryID
        self.managementID = managementID
        self.serialNumber = serialNumber
        self.displayName = displayName
        self.startedAt = startedAt
        self.ticketReference = ticketReference
        self.reason = reason
    }
}

// MARK: - Readiness (Phase 5)

/// TCP reachability of the connection target on the Screen Sharing port, as a signal that is
/// **separate** from the Jamf MDM command status. An unreachable target does not mean the Jamf
/// command failed — the Mac may be asleep, off-VPN, behind a firewall, or have stale DNS.
nonisolated enum SupportRemoteSupportReachability: String, Sendable, Equatable {
    case reachable
    case unreachable
    case unknown

    /// Honest, distinct phrasing per the readiness spec.
    var label: String {
        switch self {
        case .reachable:   return "Reachable on the Screen Sharing port"
        case .unreachable: return "Not reachable from this network"
        case .unknown:     return "Connection target not verified"
        }
    }
}

/// Interpretation of the Jamf MDM command status for the Enable Remote Management command.
/// Derived from `SupportMDMCommandRecord.bucket` so it shares the tenant-status normalization
/// already used by the Command History frame.
nonisolated enum SupportRemoteSupportCommandReadiness: Sendable, Equatable {
    /// Jamf acknowledged/completed the command — Remote Management should be applied.
    case confirmed
    /// The command is still pending / NotNow — the Mac has not applied it yet.
    case pending
    /// Jamf reported the command failed (distinct from a reachability failure).
    case failed(reason: String)
    /// Status could not be determined (no record found, status lookup denied, or unparseable).
    case unknown

    var label: String {
        switch self {
        case .confirmed:        return "Remote Management command acknowledged"
        case .pending:          return "Remote Management command queued — still pending"
        case let .failed(why):  return "Remote Management command failed: \(why)"
        case .unknown:          return "Command status not verified"
        }
    }
}

/// A single readiness check result combining the Jamf command status and the local reachability
/// probe, with the time it was taken. The UI presents both signals honestly and never collapses
/// them into a single "ready/not ready" claim.
nonisolated struct SupportRemoteSupportReadinessReport: Sendable, Equatable {
    let commandReadiness: SupportRemoteSupportCommandReadiness
    let reachability: SupportRemoteSupportReachability
    let checkedAt: Date

    /// One-line honest summary describing what was — and was not — confirmed.
    var summary: String {
        switch (commandReadiness, reachability) {
        case (.failed(let why), _):
            return "Jamf reported the enable command failed: \(why)."
        case (.confirmed, .reachable):
            return "Command acknowledged and the target answered on the Screen Sharing port."
        case (.confirmed, .unreachable):
            return "Command acknowledged, but the target is not reachable from this network — you can still attempt to connect."
        case (.confirmed, .unknown):
            return "Command acknowledged. Reachability not verified — ready to attempt."
        case (.pending, _):
            return "Jamf queued the command; the Mac hasn’t applied it yet. Check again after it checks in."
        case (.unknown, .reachable):
            return "Command status not verified, but the target answered on the Screen Sharing port — ready to attempt."
        case (.unknown, _):
            return "Command status not verified. Ready to attempt; reachability is not a guarantee."
        }
    }
}

// MARK: - Status presentation (Phase 7)

/// Visual tone for the status pill, mapped to design-system colors by the view (no new visual
/// language). Kept color-free here so the mapping is pure and unit-testable.
nonisolated enum SupportRemoteSupportStatusTone: String, Sendable, Equatable {
    case neutral
    case active
    case success
    case danger
}

/// Pure presentation mapping for the Remote Support status pill — the badge label and tone for a
/// given state. Extracted from the view so it can be exercised deterministically (the project has
/// no snapshot infrastructure; manual visual verification is documented in the report).
nonisolated struct SupportRemoteSupportStatusPresentation: Sendable, Equatable {
    let badge: String
    let tone: SupportRemoteSupportStatusTone

    static func make(for state: SupportRemoteSupportState) -> SupportRemoteSupportStatusPresentation {
        switch state {
        case .unsupported:
            return .init(badge: "Unsupported", tone: .neutral)
        case .needsManagementID:
            return .init(badge: "Needs Management ID", tone: .active)
        case .readyToPrepare:
            return .init(badge: "Ready", tone: .success)
        case .queueingEnableCommand:
            return .init(badge: "Queueing", tone: .active)
        case .queuedWaitingForCheckIn:
            return .init(badge: "Waiting for Check-In", tone: .active)
        case .readinessUnknown:
            return .init(badge: "Readiness Unknown", tone: .active)
        case .readyToOpen:
            return .init(badge: "Ready to Open", tone: .success)
        case .launchRequested:
            return .init(badge: "Launched", tone: .active)
        case .cleanupAvailable:
            return .init(badge: "Cleanup Needed", tone: .active)
        case .queueingDisableCommand:
            return .init(badge: "Queueing", tone: .active)
        case .ended:
            return .init(badge: "Ended", tone: .neutral)
        case .failed:
            return .init(badge: "Failed", tone: .danger)
        }
    }
}

// MARK: - Diagnostics event (Phase 6)

/// A Remote Support workflow event handed to the framework diagnostics reporter. The controller
/// builds these for eligibility, command queueing, launch, cleanup, readiness, and failures with
/// the full required metadata; the view model forwards them to the shared `DiagnosticsCenter`
/// (no module-local diagnostics stack).
nonisolated struct SupportRemoteSupportDiagnosticEvent: Sendable, Equatable {
    enum Severity: String, Sendable { case info, warning, error }

    let category: String
    let severity: Severity
    let message: String
    let metadata: [String: String]
}

//endofline
