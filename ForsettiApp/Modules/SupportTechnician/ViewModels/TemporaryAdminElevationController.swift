import Foundation
import Combine

/// Drives the Temporary Admin Elevation frame for the selected Mac.
///
/// Owns the feature's UI state, input fields, validation gating, confirmation
/// flow, and the bounded polling loop. It is a separate `ObservableObject` from
/// `SupportTechnicianViewModel` so the feature stays cohesive and unit-testable
/// with a mock `TemporaryAdminElevationServicing`.
@MainActor
final class TemporaryAdminElevationController: ObservableObject {

    /// Whether the controller is showing the elevation flow or the demote-now
    /// flow, used only to choose the correct "waiting" copy.
    enum Mode: Equatable {
        case idle
        case elevation
        case demotion
    }

    // MARK: - Published state

    @Published private(set) var state: TemporaryAdminElevationState = .ready
    @Published private(set) var snapshot: TemporaryAdminElevationSnapshot?
    @Published private(set) var isBusy: Bool = false

    @Published var selectedDuration: TemporaryAdminDuration
    @Published var reason: String = ""
    @Published var ticketReference: String = ""

    /// Presented as an `.alert(item:)` for any actionable failure.
    @Published var userFacingError: TemporaryAdminUserFacingError?
    /// Drives the typed-confirmation sheet for a request.
    @Published var isConfirmationPresented: Bool = false
    @Published var confirmationText: String = ""
    /// Drives the required-privileges sheet.
    @Published var isPrivilegesPresented: Bool = false

    // MARK: - Dependencies

    let configuration: TemporaryAdminElevationConfiguration
    private let service: any TemporaryAdminElevationServicing
    private let diagnostics: any DiagnosticsReporting

    // MARK: - Internal state

    private var detail: SupportDeviceDetail?
    private var configuredDeviceId: String?
    private var activeRequest: TemporaryAdminElevationRequest?
    private var mode: Mode = .idle
    private var pollTask: Task<Void, Never>?

    init(
        configuration: TemporaryAdminElevationConfiguration,
        service: any TemporaryAdminElevationServicing,
        diagnostics: any DiagnosticsReporting
    ) {
        self.configuration = configuration
        self.service = service
        self.diagnostics = diagnostics
        self.selectedDuration = configuration.availableDurations.first ?? .fifteen
    }

    // MARK: - Derived UI properties

    var requiresTicket: Bool { configuration.requireTicketReference }

    var availableDurations: [TemporaryAdminDuration] { configuration.availableDurations }

    var selectedMacName: String? { detail?.summary.displayName }

    var selectedMacSerial: String? { detail?.summary.serialNumber }

    /// A short description of the app-side request state for the details grid.
    var appRequestStateText: String {
        if activeRequest == nil {
            return isInFlight ? "In progress" : "No active request"
        }
        return mode == .demotion ? "Demotion requested" : "Elevation requested"
    }

    /// The selected device is an eligible managed Mac with a Jamf computer ID.
    var isEligible: Bool {
        guard let summary = detail?.summary else { return false }
        return summary.assetType == .computer
            && summary.inventoryID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
    }

    /// Whether the frame should be shown at all for the current selection.
    /// Mobile devices never see an actionable elevation control.
    var shouldDisplayFrame: Bool {
        detail?.summary.assetType == .computer
    }

    var validation: TemporaryAdminValidationResult {
        guard let summary = detail?.summary else {
            return .invalid(["Select a managed Mac."])
        }
        return TemporaryAdminElevationValidator.validate(
            assetType: summary.assetType,
            isManaged: TemporaryAdminElevationService.isManaged(summary),
            inventoryID: summary.inventoryID,
            duration: selectedDuration,
            hasConfiguredScope: configuration.scope(for: selectedDuration)?.isConfigured ?? false,
            reason: reason,
            ticketReference: ticketReference,
            requiresTicket: requiresTicket
        )
    }

    /// Whether the Request button is enabled.
    var isRequestEnabled: Bool {
        configuration.isFullyConfigured
            && isEligible
            && validation.isValid
            && isBusy == false
            && activeRequest == nil
            && isInFlight == false
    }

    /// Whether the End Elevation Now button is enabled.
    var isDemoteEnabled: Bool {
        configuration.isFullyConfigured && isEligible && isBusy == false
    }

    private var isInFlight: Bool {
        switch state {
        case .validating, .requesting, .waitingForCheckIn, .demotionRequested:
            return true
        default:
            return false
        }
    }

    /// The normal-use privileges shown in the confirmation and privileges sheets.
    var requiredPrivileges: [String] { TemporaryAdminUserFacingError.requiredNormalUsePrivileges }

    // MARK: - Lifecycle

    /// Called when the selected device changes or the detail reloads. Resets
    /// input fields only when the device actually changed, then loads the
    /// reported snapshot.
    func configure(for detail: SupportDeviceDetail?) {
        pollTask?.cancel()
        pollTask = nil
        self.detail = detail

        guard configuration.isFullyConfigured else {
            state = .notConfigured(reason: TemporaryAdminElevationService.notConfiguredReason)
            return
        }

        guard let detail else {
            state = .unavailable(reason: "Select a managed Mac to use Temporary Admin Elevation.")
            return
        }

        if detail.summary.assetType != .computer {
            state = .unavailable(reason: "Temporary Admin Elevation is available for managed Macs only.")
            return
        }

        let deviceId = detail.summary.id
        if deviceId != configuredDeviceId {
            configuredDeviceId = deviceId
            reason = ""
            ticketReference = ""
            activeRequest = nil
            mode = .idle
            if availableDurations.contains(selectedDuration) == false {
                selectedDuration = availableDurations.first ?? selectedDuration
            }
        }

        Task { await loadInitialSnapshot(for: detail) }
    }

    private func loadInitialSnapshot(for detail: SupportDeviceDetail) async {
        do {
            let loaded = try await service.loadSnapshot(for: detail)
            applySnapshot(loaded, overlay: nil)
        } catch {
            state = .failed(message: error.localizedDescription)
        }
    }

    // MARK: - Actions

    /// Presents the typed-confirmation sheet for a request.
    func beginRequest() {
        guard isRequestEnabled else { return }
        confirmationText = ""
        isConfirmationPresented = true
    }

    /// Performs the elevation request after confirmation.
    func confirmRequest() async {
        guard let detail else { return }
        isConfirmationPresented = false
        isBusy = true
        mode = .elevation
        state = .requesting
        defer { isBusy = false }

        do {
            let request = try await service.requestElevation(
                for: detail,
                duration: selectedDuration,
                reason: reason,
                ticketReference: requiresTicket ? ticketReference : ticketReference.isEmpty ? nil : ticketReference
            )
            activeRequest = request
            state = .waitingForCheckIn(requestedAt: request.requestedAt)
            startPolling(for: request, mode: .elevation)
        } catch {
            handleOperationError(error)
        }
    }

    /// Requests immediate demotion for the selected Mac.
    func demoteNow() async {
        guard let detail else { return }
        isBusy = true
        mode = .demotion
        state = .demotionRequested(requestedAt: Date())
        defer { isBusy = false }

        do {
            let request = try await service.requestDemotionNow(
                for: detail,
                reason: reason,
                ticketReference: ticketReference.isEmpty ? nil : ticketReference
            )
            activeRequest = request
            state = .demotionRequested(requestedAt: request.requestedAt)
            startPolling(for: request, mode: .demotion)
        } catch {
            handleOperationError(error)
        }
    }

    /// Manually refreshes the reported status.
    func refresh() async {
        guard let detail else { return }
        isBusy = true
        defer { isBusy = false }
        do {
            if let request = activeRequest {
                let result = try await service.pollElevation(for: detail, request: request)
                applyPollResult(result)
            } else {
                let fresh = try await service.refreshSnapshot(for: detail)
                applySnapshot(fresh, overlay: nil)
            }
        } catch {
            handleOperationError(error)
        }
    }

    func showRequiredPrivileges() {
        isPrivilegesPresented = true
    }

    /// Cancels in-flight polling. Call when the frame disappears or the device
    /// changes.
    func stop() {
        pollTask?.cancel()
        pollTask = nil
    }

    // MARK: - Polling

    private func startPolling(for request: TemporaryAdminElevationRequest, mode: Mode) {
        pollTask?.cancel()
        let intervalSeconds = max(15, configuration.pollIntervalSeconds)
        pollTask = Task { @MainActor [weak self] in
            guard let self else { return }
            // Initial delay before the first poll so the Mac has a moment to
            // check in; keeps the first cycle from racing the scope write.
            try? await Task.sleep(nanoseconds: UInt64(intervalSeconds) * 1_000_000_000)
            while Task.isCancelled == false {
                guard let detail = self.detail else { break }
                do {
                    let result = try await self.service.pollElevation(for: detail, request: request)
                    self.applyPollResult(result)
                    if result.isComplete {
                        self.activeRequest = nil
                        break
                    }
                } catch {
                    self.handleOperationError(error)
                    break
                }
                try? await Task.sleep(nanoseconds: UInt64(intervalSeconds) * 1_000_000_000)
            }
        }
    }

    // MARK: - State application

    private func applyPollResult(_ result: TemporaryAdminPollResult) {
        snapshot = result.snapshot
        if result.isComplete {
            state = result.snapshot.state
            mode = .idle
        } else {
            // Keep the contextual waiting copy while pending.
            switch mode {
            case .demotion:
                state = .demotionRequested(requestedAt: activeRequest?.requestedAt ?? Date())
            default:
                state = .waitingForCheckIn(requestedAt: activeRequest?.requestedAt ?? Date())
            }
        }
    }

    private func applySnapshot(_ snapshot: TemporaryAdminElevationSnapshot, overlay state: TemporaryAdminElevationState?) {
        self.snapshot = snapshot
        self.state = state ?? snapshot.state
    }

    private func handleOperationError(_ error: Error) {
        let correlationId = activeRequest?.id.uuidString
        let mapped = TemporaryAdminUserFacingError.map(error, correlationId: correlationId)
        userFacingError = mapped
        activeRequest = nil
        mode = .idle

        switch error {
        case TemporaryAdminElevationError.notConfigured:
            state = .notConfigured(reason: mapped.summary)
        default:
            if error.isJamfInvalidPrivilege {
                state = .permissionDenied(requiredPrivileges: mapped.requiredJamfPrivileges)
            } else if case TemporaryAdminElevationError.duplicateActiveRequest = error {
                // Leave the in-flight state as-is; just surface the alert.
                break
            } else {
                state = .failed(message: mapped.summary)
            }
        }
    }
}
