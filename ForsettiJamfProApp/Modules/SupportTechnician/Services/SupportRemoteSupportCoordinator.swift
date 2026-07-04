import Foundation
import Combine

/// Orchestrates the Apple-native Remote Support state machine for the selected Mac.
///
/// The coordinator owns the canonical `state` and the workflow `session`. It performs **no**
/// Jamf networking and parses **no** payloads — the view model calls the existing API service
/// and feeds the outcomes here (`enableQueued`, `fail`, …). Every transition is guarded so the
/// state machine can only advance along valid edges, and the key invariants hold:
///
/// - queueing the enable command never moves straight to `readyToOpen`,
/// - a `vnc://` launch requires an explicit `requestLaunch()` from `readyToOpen`,
/// - cleanup availability persists after launch until disable is queued or cleanup is skipped.
@MainActor
final class SupportRemoteSupportCoordinator: ObservableObject {
    /// The canonical live state of the workflow.
    @Published private(set) var state: SupportRemoteSupportState = .readyToPrepare
    /// The workflow instance for the selected device (audit/context record).
    @Published private(set) var session: SupportRemoteSupportSession?

    private let resolver: SupportRemoteSupportTargetResolver

    /// Where `retry()` returns after a failure. A cleanup (disable) failure resumes cleanup so the
    /// Disable control stays available; all other failures re-prepare. Reset after each retry.
    private var retryResumeState: SupportRemoteSupportState = .readyToPrepare

    init(resolver: SupportRemoteSupportTargetResolver = SupportRemoteSupportTargetResolver()) {
        self.resolver = resolver
    }

    // MARK: - Setup

    /// Establishes eligibility and the initial state for `detail`. `now` is injectable for tests.
    func configure(for detail: SupportDeviceDetail, now: Date = Date()) {
        let summary = detail.summary

        guard summary.assetType == .computer else {
            session = nil
            state = .unsupported(reason: "Remote Support is available for Macs only.")
            return
        }

        let managementID = summary.managementID?.trimmingCharacters(in: .whitespacesAndNewlines)
        var newSession = SupportRemoteSupportSession(
            inventoryID: summary.inventoryID,
            managementID: managementID,
            serialNumber: summary.serialNumber,
            displayName: summary.displayName,
            startedAt: now
        )
        let resolution = resolver.resolve(detail: detail)
        newSession.connectionTarget = resolution.target
        newSession.connectionTargetSource = resolution.target?.source
        session = newSession

        guard let managementID, managementID.isEmpty == false else {
            state = .needsManagementID
            return
        }
        state = .readyToPrepare
    }

    // MARK: - Enable

    /// readyToPrepare → queueingEnableCommand
    func beginEnable() {
        guard case .readyToPrepare = state else { return }
        state = .queueingEnableCommand
    }

    /// queueingEnableCommand → queuedWaitingForCheckIn (Jamf accepted — NOT "ready").
    func enableQueued(commandID: String?) {
        guard case .queueingEnableCommand = state else { return }
        session?.enableCommandID = commandID
        state = .queuedWaitingForCheckIn(commandID: commandID)
    }

    // MARK: - Readiness

    /// queuedWaitingForCheckIn → readinessUnknown (status could not be confirmed).
    func markReadinessUnknown() {
        guard case let .queuedWaitingForCheckIn(commandID) = state else { return }
        state = .readinessUnknown(commandID: commandID)
    }

    /// queuedWaitingForCheckIn | readinessUnknown → readyToOpen (a usable target is available).
    func markReadyToOpen(target: SupportRemoteSupportTarget) {
        switch state {
        case .queuedWaitingForCheckIn, .readinessUnknown:
            session?.connectionTarget = target
            session?.connectionTargetSource = target.source
            state = .readyToOpen(target: target)
        default:
            break
        }
    }

    // MARK: - Launch

    /// readyToOpen → launchRequested (explicit technician action — the only `vnc://` trigger).
    func requestLaunch() {
        guard case let .readyToOpen(target) = state else { return }
        state = .launchRequested(target: target)
    }

    /// launchRequested → cleanupAvailable (the launch attempt was recorded).
    func launchRecorded() {
        guard case let .launchRequested(target) = state else { return }
        state = .cleanupAvailable(target: target)
    }

    // MARK: - Cleanup / Disable

    /// cleanupAvailable → queueingDisableCommand
    func beginDisable() {
        guard case .cleanupAvailable = state else { return }
        state = .queueingDisableCommand
    }

    /// queueingDisableCommand → ended (Disable Remote Management accepted by Jamf).
    func disableQueued(commandID: String? = nil, now: Date = Date()) {
        guard case .queueingDisableCommand = state else { return }
        session?.disableCommandID = commandID
        session?.endedAt = now
        state = .ended
    }

    /// cleanupAvailable → ended, recording that cleanup was intentionally skipped.
    func endSkippingCleanup(reason: String, now: Date = Date()) {
        guard case .cleanupAvailable = state else { return }
        session?.reason = reason
        session?.endedAt = now
        state = .ended
    }

    // MARK: - Failure / retry

    /// Any non-terminal state → failed, preserving retry guidance. A failure while disabling (or
    /// while cleanup was available) records cleanup as the resume point so retrying does not
    /// discard the still-needed cleanup.
    func fail(_ failure: SupportRemoteSupportFailure) {
        guard state.isTerminal == false else { return }
        switch state {
        case .queueingDisableCommand, .cleanupAvailable:
            retryResumeState = .cleanupAvailable(target: session?.connectionTarget)
        default:
            retryResumeState = .readyToPrepare
        }
        state = .failed(failure)
    }

    /// failed → resume point (cleanup for a cleanup failure, else readyToPrepare), only when the
    /// failure was marked safe to retry.
    func retry() {
        guard case let .failed(failure) = state, failure.isSafeToRetry else { return }
        let resume = retryResumeState
        retryResumeState = .readyToPrepare
        state = resume
    }

    // MARK: - Target editing

    /// Records a re-resolved target (e.g. after a manual-override edit) on the session without
    /// changing state. The view model decides whether to also move to `readyToOpen`.
    func updateResolvedTarget(_ resolution: SupportRemoteSupportTargetResolution) {
        session?.connectionTarget = resolution.target
        session?.connectionTargetSource = resolution.target?.source
    }
}

//endofline
