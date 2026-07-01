import Foundation
import Combine

/// View-facing orchestrator for the Apple-native Remote Support workflow.
///
/// Wraps the pure `SupportRemoteSupportCoordinator` (state) and drives it in response to
/// technician actions, performing the actual Jamf work through **injected closures** so the
/// controller stays decoupled from the API service and is unit-testable. Mirrors the existing
/// `TemporaryAdminElevationController` integration pattern.
///
/// Architecture boundaries preserved: the coordinator owns transitions; the closures (supplied
/// by the module view model) reach the existing `SupportTechnicianAPIService`, native URL
/// opening, and clipboard. No networking, credential, or diagnostics stack is created here.
@MainActor
final class SupportRemoteSupportController: ObservableObject {
    /// The pure state machine the view observes (republished below).
    let coordinator: SupportRemoteSupportCoordinator

    /// Editable connection-target override bound to the Edit Target field.
    @Published var manualTargetOverride: String = ""

    /// The most recent readiness check (Jamf command status + local reachability). Nil until the
    /// technician runs Check Readiness; reset when a different device is configured.
    @Published private(set) var readinessReport: SupportRemoteSupportReadinessReport?

    /// True while a readiness check is in flight (drives the Check Readiness progress affordance).
    @Published private(set) var isCheckingReadiness = false

    /// Invoked by `viewDiagnostics()`. Assigned by the owner (the module view model) after init,
    /// so the closure can safely capture the fully-initialized view model.
    var onViewDiagnostics: () -> Void = {}

    private let resolver: SupportRemoteSupportTargetResolver
    private let readinessEvaluator: SupportRemoteSupportReadinessEvaluator
    private let diagnosticMapper: SupportRemoteSupportDiagnosticMapper
    private let enableCommand: (String) async throws -> String?
    private let disableCommand: (String) async throws -> String?
    private let launchURL: (URL) -> Void
    private let copyToClipboard: (String) -> Void
    /// Fetches command-history records for the given device through the existing API service /
    /// gateway (no module-local networking). Defaults to none so the controller stays testable.
    private let fetchCommandRecords: (SupportDeviceDetail) async throws -> [SupportMDMCommandRecord]
    /// Probes TCP reachability of the connection target. Defaults to `.unknown` (no probe).
    private let probeReachability: (SupportRemoteSupportTarget) async -> SupportRemoteSupportReachability
    /// Forwards workflow diagnostics to the shared `DiagnosticsCenter` (via the view model).
    /// Defaults to a no-op so the controller stays testable without a diagnostics stack.
    private let reportDiagnostics: (SupportRemoteSupportDiagnosticEvent) -> Void

    private var detail: SupportDeviceDetail?
    private var cancellables: Set<AnyCancellable> = []

    init(
        resolver: SupportRemoteSupportTargetResolver = SupportRemoteSupportTargetResolver(),
        readinessEvaluator: SupportRemoteSupportReadinessEvaluator = SupportRemoteSupportReadinessEvaluator(),
        diagnosticMapper: SupportRemoteSupportDiagnosticMapper = SupportRemoteSupportDiagnosticMapper(),
        enableCommand: @escaping (String) async throws -> String?,
        disableCommand: @escaping (String) async throws -> String?,
        launchURL: @escaping (URL) -> Void,
        copyToClipboard: @escaping (String) -> Void,
        fetchCommandRecords: @escaping (SupportDeviceDetail) async throws -> [SupportMDMCommandRecord] = { _ in [] },
        probeReachability: @escaping (SupportRemoteSupportTarget) async -> SupportRemoteSupportReachability = { _ in .unknown },
        reportDiagnostics: @escaping (SupportRemoteSupportDiagnosticEvent) -> Void = { _ in }
    ) {
        self.coordinator = SupportRemoteSupportCoordinator(resolver: resolver)
        self.resolver = resolver
        self.readinessEvaluator = readinessEvaluator
        self.diagnosticMapper = diagnosticMapper
        self.enableCommand = enableCommand
        self.disableCommand = disableCommand
        self.launchURL = launchURL
        self.copyToClipboard = copyToClipboard
        self.fetchCommandRecords = fetchCommandRecords
        self.probeReachability = probeReachability
        self.reportDiagnostics = reportDiagnostics
        // Republish nested coordinator changes so views observing the controller update.
        coordinator.objectWillChange
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &cancellables)
    }

    // MARK: - View reads

    var state: SupportRemoteSupportState { coordinator.state }
    var session: SupportRemoteSupportSession? { coordinator.session }

    /// The best target to display: the live state target when present, else the session candidate.
    var resolvedTarget: SupportRemoteSupportTarget? {
        coordinator.state.target ?? coordinator.session?.connectionTarget
    }

    /// The Remote Support frame renders only for managed Macs.
    var shouldDisplayFrame: Bool {
        detail?.summary.assetType == .computer
    }

    // MARK: - Lifecycle

    /// Configures the workflow for `detail`. Re-rendering the same device preserves in-progress
    /// state; selecting a different device resets the workflow.
    func configure(for detail: SupportDeviceDetail) {
        if self.detail?.summary.id == detail.summary.id {
            self.detail = detail
            return
        }
        self.detail = detail
        manualTargetOverride = ""
        readinessReport = nil
        coordinator.configure(for: detail)
        record(action: "eligibility", severity: .info, message: "Evaluated Remote Support eligibility.")
    }

    // MARK: - Actions

    func enableRemoteManagement() {
        guard case .readyToPrepare = coordinator.state,
              let managementID = coordinator.session?.managementID, managementID.isEmpty == false
        else {
            return
        }
        coordinator.beginEnable()
        Task {
            do {
                let commandID = try await enableCommand(managementID)
                coordinator.enableQueued(commandID: commandID)
                record(
                    action: "enable_command",
                    severity: .info,
                    message: "Queued Enable Remote Management.",
                    commandType: "ENABLE_REMOTE_DESKTOP",
                    endpoint: "api/v2/mdm/commands",
                    jamfCommandQueued: true
                )
            } catch {
                let failure = diagnosticMapper.failure(from: error, requiresCommandPrivilege: true)
                record(
                    action: "enable_command",
                    severity: .error,
                    message: "Enable Remote Management failed.",
                    commandType: "ENABLE_REMOTE_DESKTOP",
                    endpoint: "api/v2/mdm/commands",
                    httpStatus: diagnosticMapper.httpStatus(for: error),
                    requiredPrivilege: failure.requiredPrivilege,
                    safeToRetry: failure.isSafeToRetry,
                    jamfCommandQueued: false
                )
                coordinator.fail(failure)
            }
        }
    }

    /// Checks readiness using two independent signals: the Jamf MDM command status (fetched via
    /// the existing gateway) and a local reachability probe. Both are reported honestly — a
    /// reachability failure never claims the Jamf command failed, and command-status uncertainty
    /// never blocks the technician from attempting the connection once a usable target exists.
    func checkReadiness() {
        switch coordinator.state {
        case .queuedWaitingForCheckIn, .readinessUnknown:
            break
        default:
            return
        }
        guard isCheckingReadiness == false else { return }
        isCheckingReadiness = true

        let detail = self.detail
        let enableCommandID = coordinator.session?.enableCommandID
        let target = currentResolution().target

        Task {
            defer { isCheckingReadiness = false }

            // 1. Jamf command status via the existing gateway. A status-lookup failure is NOT a
            //    command failure — report it as unverified rather than failing the workflow.
            var commandReadiness: SupportRemoteSupportCommandReadiness = .unknown
            if let detail {
                do {
                    let records = try await fetchCommandRecords(detail)
                    commandReadiness = readinessEvaluator.evaluateCommand(
                        records: records,
                        enableCommandID: enableCommandID
                    )
                } catch {
                    commandReadiness = .unknown
                }
            }

            // 2. Local reachability — an independent signal, never conflated with command status.
            var reachability: SupportRemoteSupportReachability = .unknown
            if let target {
                reachability = await probeReachability(target)
            }

            let report = SupportRemoteSupportReadinessReport(
                commandReadiness: commandReadiness,
                reachability: reachability,
                checkedAt: Date()
            )
            readinessReport = report
            let readinessSeverity: SupportRemoteSupportDiagnosticEvent.Severity
            switch commandReadiness {
            case .failed:  readinessSeverity = .error
            case .pending: readinessSeverity = .warning
            default:       readinessSeverity = .info
            }
            record(
                action: "readiness",
                severity: readinessSeverity,
                message: "Readiness checked: \(report.summary)",
                endpoint: "api/v2/mdm/commands"
            )

            // 3. Drive state honestly. Reachability colors guidance but never blocks the attempt
            //    and never claims the Jamf command failed.
            switch commandReadiness {
            case let .failed(reason):
                coordinator.fail(SupportRemoteSupportFailure(
                    summary: "Jamf reported the Enable Remote Management command failed: \(reason)",
                    isSafeToRetry: true,
                    recommendation: "Re-queue the command, or confirm the Mac can check in to Jamf, then try again."
                ))
            case .pending:
                // Still waiting — do not advance or claim readiness.
                break
            case .confirmed, .unknown:
                if let target {
                    coordinator.markReadyToOpen(target: target)
                } else {
                    coordinator.markReadinessUnknown()
                }
            }
        }
    }

    func openScreenSharing() {
        guard coordinator.state.canOpenScreenSharing,
              let target = coordinator.state.target,
              let url = target.screenSharingURL
        else {
            return
        }
        coordinator.requestLaunch()
        launchURL(url)
        coordinator.launchRecorded()
        record(
            action: "launch",
            severity: .info,
            message: "Opened native Screen Sharing for the resolved target.",
            localDataChanged: false
        )
    }

    func disableRemoteManagement() {
        guard case .cleanupAvailable = coordinator.state,
              let managementID = coordinator.session?.managementID, managementID.isEmpty == false
        else {
            return
        }
        coordinator.beginDisable()
        Task {
            do {
                let commandID = try await disableCommand(managementID)
                coordinator.disableQueued(commandID: commandID)
                record(
                    action: "disable_command",
                    severity: .info,
                    message: "Queued Disable Remote Management (cleanup).",
                    commandType: "DISABLE_REMOTE_DESKTOP",
                    endpoint: "api/v2/mdm/commands",
                    jamfCommandQueued: true
                )
            } catch {
                let failure = diagnosticMapper.failure(from: error, requiresCommandPrivilege: true)
                record(
                    action: "disable_command",
                    severity: .error,
                    message: "Disable Remote Management (cleanup) failed.",
                    commandType: "DISABLE_REMOTE_DESKTOP",
                    endpoint: "api/v2/mdm/commands",
                    httpStatus: diagnosticMapper.httpStatus(for: error),
                    requiredPrivilege: failure.requiredPrivilege,
                    safeToRetry: failure.isSafeToRetry,
                    jamfCommandQueued: false
                )
                coordinator.fail(failure)
            }
        }
    }

    /// Re-resolves the target using the current manual override and, when waiting, advances to
    /// Ready to Open if the override is usable.
    func applyTargetOverride() {
        let resolution = currentResolution()
        coordinator.updateResolvedTarget(resolution)
        if let target = resolution.target {
            switch coordinator.state {
            case .queuedWaitingForCheckIn, .readinessUnknown:
                coordinator.markReadyToOpen(target: target)
            default:
                break
            }
        }
    }

    func copyConnectionTarget() {
        if let host = resolvedTarget?.host { copyToClipboard(host) }
    }

    func endSkippingCleanup(reason: String) {
        coordinator.endSkippingCleanup(reason: reason)
        record(
            action: "cleanup_skipped",
            severity: .warning,
            message: "Cleanup skipped without queuing Disable Remote Management. Reason: \(reason)"
        )
    }

    func retry() {
        coordinator.retry()
    }

    func viewDiagnostics() {
        onViewDiagnostics()
    }

    // MARK: - Helpers

    private func currentResolution() -> SupportRemoteSupportTargetResolution {
        guard let detail else { return .unresolved(reason: "No device selected.") }
        let override = manualTargetOverride.trimmingCharacters(in: .whitespacesAndNewlines)
        return resolver.resolve(detail: detail, manualOverride: override.isEmpty ? nil : override)
    }

    /// Assembles the full required diagnostics metadata (module, source, action, endpoint,
    /// command type, inventory/management/serial/display, target/source, state, http status,
    /// required privilege, safe-to-retry, local-data-changed, jamf-command-queued) from the
    /// session and current state, and forwards the event to the shared diagnostics reporter.
    private func record(
        action: String,
        severity: SupportRemoteSupportDiagnosticEvent.Severity,
        message: String,
        commandType: String? = nil,
        endpoint: String? = nil,
        httpStatus: Int? = nil,
        requiredPrivilege: String? = nil,
        safeToRetry: Bool? = nil,
        jamfCommandQueued: Bool? = nil,
        localDataChanged: Bool = false
    ) {
        var metadata: [String: String] = [
            "module": "support-technician",
            "source": "module.support-technician",
            "category": "remote-support",
            "action": action,
            "remote_support_state": coordinator.state.diagnosticsName,
            "local_data_changed": localDataChanged ? "true" : "false"
        ]
        if let session = coordinator.session {
            metadata["inventory_id"] = session.inventoryID
            metadata["management_id"] = session.managementID ?? "(none)"
            metadata["serial_number"] = session.serialNumber
            metadata["display_name"] = session.displayName
        }
        if let target = resolvedTarget {
            metadata["connection_target"] = target.host
            metadata["connection_target_source"] = target.source.label
        }
        if let commandType { metadata["command_type"] = commandType }
        if let endpoint { metadata["endpoint"] = endpoint }
        if let httpStatus { metadata["http_status"] = String(httpStatus) }
        if let requiredPrivilege { metadata["required_privilege"] = requiredPrivilege }
        if let safeToRetry { metadata["safe_to_retry"] = safeToRetry ? "true" : "false" }
        if let jamfCommandQueued { metadata["jamf_command_queued"] = jamfCommandQueued ? "true" : "false" }

        reportDiagnostics(SupportRemoteSupportDiagnosticEvent(
            category: "remote-support",
            severity: severity,
            message: message,
            metadata: metadata
        ))
    }
}

//endofline
