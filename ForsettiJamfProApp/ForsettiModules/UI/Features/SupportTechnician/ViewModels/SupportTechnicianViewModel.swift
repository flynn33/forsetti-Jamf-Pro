import Foundation
import Combine
#if canImport(AppKit)
import AppKit
#elseif canImport(UIKit)
import UIKit
#endif

@MainActor
/// Drives all state and business logic for the Support Technician view.
///
/// Manages the search workflow, device detail loading, management action execution,
/// application command handling, and diagnostics reporting. All published properties
/// are observed by `SupportTechnicianView` through SwiftUI's `@StateObject` binding.
final class SupportTechnicianViewModel: ObservableObject {
    /// The optional ticket or change request reference for audit trail purposes.
    @Published var ticketReference = ""

    /// The username or serial number search query.
    @Published var query = ""

    /// The selected device type scope for the search.
    @Published var searchScope: SupportSearchScope = .all

    /// The list of search results from the most recent search.
    @Published private(set) var searchResults: [SupportSearchResult] = []

    /// The ID of the currently selected search result, driving detail loading.
    @Published var selectedResultID: String?

    /// The full detail record for the selected device, including diagnostics and sections.
    @Published private(set) var selectedDetail: SupportDeviceDetail?

    /// Whether a search is currently in progress.
    @Published private(set) var isSearching = false

    /// Whether device detail is currently loading.
    @Published private(set) var isLoadingDetail = false

    /// Whether a management action is currently being executed.
    @Published private(set) var isPerformingAction = false

    // MARK: - Application Manager (v3.18+)

    /// Applications currently installed on the selected Mac, sourced from
    /// `GET /api/v1/computers-inventory/{id}?section=APPLICATIONS`.
    ///
    /// The list is cleared whenever the selected device changes (see
    /// `loadSelectedDeviceDetail` and `resetForScopeChange`). It does **not**
    /// auto-load on selection — the Application Manager view triggers the
    /// initial load when it appears, because most technician sessions never
    /// open that view.
    @Published private(set) var installedApplications: [DeviceApplication] = []

    /// Whether `fetchInstalledApplications` is in flight. Drives the spinner
    /// in the Application Manager view.
    @Published private(set) var isLoadingInstalledApplications = false

    /// Whether an install-or-uninstall action is currently being dispatched
    /// against Jamf Pro (script create → policy create → blank push). Drives
    /// the progress banner and the "disable-while-busy" state on every per-row
    /// Uninstall button and the Install form.
    @Published private(set) var isPerformingAppAction = false

    /// Result of the pre-flight privilege check for Application Manager. `nil`
    /// before any check has been attempted (UI treats this as "not yet known,"
    /// defers to the in-flight indicator instead of a missing-privilege
    /// banner). Empty array means every required privilege is present.
    /// Non-empty means the listed privileges must be granted on Jamf Pro
    /// before Install / Uninstall will work.
    @Published private(set) var applicationManagerMissingPrivileges: [String]?

    /// Whether the pre-flight privilege check is in progress.
    @Published private(set) var isCheckingApplicationManagerPrivileges = false

    /// Current verification state for the most recent Application Manager
    /// dispatch. Starts at `.idle`, transitions through `.queued` →
    /// `.checkingIn` → `.verified` / `.timedOut`. The view uses this to
    /// render a state-specific banner.
    @Published private(set) var applicationActionVerification: ApplicationActionVerificationState = .idle

    /// Reference to the verification-polling task so it can be cancelled
    /// when a new action is dispatched (or the user navigates away).
    private var applicationActionVerificationTask: Task<Void, Never>?

    // MARK: - MDM command lifecycle (Technician Module redesign)

    /// Current MDM-command lifecycle phase. Drives the Metal-rendered
    /// `CommandStatusIndicatorView`. Starts `.idle`; transitions to
    /// `.sending` the moment the technician confirms; flips to `.queued`
    /// on Jamf 2xx; for verifying actions transitions to `.verifying` and
    /// polls inventory until `lastInventoryUpdate` advances; ends in
    /// `.succeeded`, `.failed`, or `.timedOut`.
    ///
    /// Terminal states auto-dismiss to `.idle` after a short delay so the
    /// indicator clears between commands.
    @Published private(set) var commandLifecycle: CommandLifecyclePhase = .idle

    /// Polling task driving the verification phase for actions whose
    /// ground-truth completion is reflected in inventory (Restart,
    /// Shutdown, Erase, ClearPasscode, LogOut). Cancelled when a new
    /// command starts, when the user switches devices, or on terminal
    /// state.
    private var commandLifecycleVerificationTask: Task<Void, Never>?

    /// Timer task that resets `commandLifecycle` to `.idle` 8 seconds
    /// after a terminal state. Cancelled on every transition so a fresh
    /// timer accompanies each terminal state.
    private var commandLifecycleAutoDismissTask: Task<Void, Never>?

    /// Maximum number of inventory-verification polls before transitioning
    /// to `.timedOut`. 20 polls × 30 s = 10 minutes — matches the
    /// Application Manager verification budget.
    private let commandVerificationMaxAttempts: Int = 20

    /// Seconds between inventory-verification polls.
    private let commandVerificationIntervalSeconds: UInt64 = 30

    /// Seconds to keep a terminal lifecycle state visible before auto-
    /// dismissing the indicator to `.idle`. Set to 0 to disable auto-
    /// dismiss entirely (user must hit the Dismiss button). The thin
    /// indicator design (v3.22.10) auto-resets after 5 seconds — the
    /// previous persistent-until-dismiss behaviour was paired with the
    /// taller 3-node visual that made the outcome obvious for longer.
    /// Now that the bar is a thin row the persistent state crowds the
    /// detail pane, so terminal states clear themselves after 5 s and
    /// leave a clean header.
    private let commandLifecycleAutoDismissSeconds: UInt64 = 5

    // MARK: - Command history (Technician Module redesign 3.22.1)

    /// The most recent MDM command history fetched from Jamf Pro for the
    /// selected device. Drives the Command History frame's
    /// pending/completed/failed counters and the chronological list.
    @Published private(set) var commandHistory: SupportMDMCommandHistory = .empty

    /// Whether a command-history fetch is currently in flight.
    @Published private(set) var isLoadingCommandHistory: Bool = false

    /// Error description from the most recent command-history fetch.
    /// Surfaced inline inside the Command History frame rather than as
    /// a popup because it's a read-only fetch the user can retry.
    @Published private(set) var commandHistoryError: String?

    /// Verbose failure popup for the most recent MDM-command attempt.
    /// Populated on 403/INVALID_PRIVILEGE and other failures. The View
    /// presents this as an `.alert(item:)` so the technician sees a
    /// clear modal explaining what went wrong, what privilege is likely
    /// missing, and the raw Jamf response for advanced debugging.
    @Published var actionFailurePopup: SupportActionFailure?

    /// The local user the technician tapped "Reset Password" on. When
    /// non-nil, the View presents a typed-confirm sheet bound to this
    /// user; on confirm the view model calls
    /// `executePasswordReset(for:)`. Cleared on cancel or after the
    /// reset request returns.
    ///
    /// Per-row password reset is intentionally outside the
    /// `SupportManagementAction` enum because the action carries a
    /// per-user payload (`username`) that the device-scoped enum
    /// dispatch can't express without a refactor. The orchestration
    /// here mirrors the typed-confirm flow used by destructive
    /// `SupportManagementAction`s.
    @Published var passwordResetCandidate: SupportLocalUser?

    /// Typed-confirmation buffer for the per-row password reset sheet.
    /// The technician must type the lowercase phrase `confirm` (the
    /// same gate every destructive action uses) before the Reset
    /// Password button enables.
    @Published var passwordResetConfirmationText: String = ""

    /// Tenant-wide policies fetched from `/JSSResource/policies`. Used by
    /// the Policy frame; loaded lazily on first appearance.
    @Published private(set) var allPolicies: [SupportPolicy] = []

    /// Whether `fetchAllPolicies` is in flight.
    @Published private(set) var isLoadingAllPolicies: Bool = false

    /// Error description from the most recent `fetchAllPolicies` call.
    @Published private(set) var allPoliciesError: String?

    /// Polling cadence for the post-action verification loop. 30 seconds
    /// balances API load against how long a typical MDM check-in takes to
    /// propagate after a blank push.
    private let applicationActionVerificationInterval: TimeInterval = 30

    /// Maximum number of polls before giving up and transitioning to
    /// `.timedOut`. 20 polls × 30 s = 10 minutes, per the implementation
    /// plan.
    private let applicationActionVerificationMaxAttempts: Int = 20

    /// An informational status message shown in the UI.
    @Published var statusMessage: String?

    /// An error message shown in the error banner.
    @Published var errorMessage: String?

    /// The result of the most recently executed action, retained for command-state diagnostics.
    @Published private(set) var actionResult: SupportActionResult?

    /// Drives the one-time credential popup. Set (non-nil) whenever an action
    /// returns a non-empty `sensitiveValue` — a local admin / LAPS password,
    /// jssmanage password, recovery-lock password, device-lock PIN, or
    /// FileVault recovery key. The View presents a `.sheet(item:)` bound to
    /// this and clears it on dismiss so the secret shows exactly once.
    @Published var presentedCredential: SupportCredentialDisplay?

    /// Drives presentation of the framework Diagnostics view from the Remote Support frame's
    /// "View Diagnostics" control.
    @Published var isRemoteSupportDiagnosticsPresented = false

    /// The non-secret summary of the most recent server response, shown in the
    /// sidebar's scrollable "Server Response" frame. Derived from
    /// `actionResult`, so every reset of `actionResult` clears it for free.
    /// Never carries the secret value — see `SupportActionResultPresentation`.
    var resultSummary: SupportResultSummary? {
        guard let actionResult else { return nil }
        return SupportResultSummary(title: actionResult.title, detail: actionResult.detail)
    }

    /// The shared Jamf Pro API gateway (retained for building the diagnostics view model).
    private let apiGateway: JamfAPIGateway

    /// The API service handling all Jamf Pro network interactions.
    private let apiService: SupportTechnicianAPIService

    /// The diagnostics reporter for audit trail and telemetry events.
    private let diagnosticsReporter: any DiagnosticsReporting

    /// The module source identifier included in all diagnostics events.
    private let moduleSource = "module.support-technician"

    /// Drives the Mac-only Temporary Admin Elevation frame. Ships disabled until
    /// a Jamf administrator configures the dedicated request-group IDs; while
    /// disabled it surfaces an actionable "not configured" message instead of any
    /// control. Owned here so the frame can observe it, but all of its logic
    /// lives in `TemporaryAdminElevationController`.
    let temporaryAdminController: TemporaryAdminElevationController

    /// Drives the Apple-native Remote Support frame for the selected Mac. Wraps the
    /// `SupportRemoteSupportCoordinator` state machine and reaches Jamf through the existing
    /// API service via injected closures. Owned here so the frame can observe it.
    let remoteSupportController: SupportRemoteSupportController

    // "A robot may not injure a human being or, through inaction, allow a human being to come to harm.
    //  A robot must obey the orders given it by human beings except where such orders would conflict with the First Law.
    //  A robot must protect its own existence as long as such protection does not conflict with the First or Second Law."

    /// Creates a new view model wired to the given API gateway and diagnostics reporter.
    ///
    /// - Parameters:
    ///   - apiGateway: The shared Jamf Pro API gateway for network requests.
    ///   - diagnosticsReporter: The shared diagnostics reporter for audit events.
    init(
        apiGateway: JamfAPIGateway,
        diagnosticsReporter: any DiagnosticsReporting
    ) {
        let apiService = SupportTechnicianAPIService(
            apiGateway: apiGateway,
            diagnosticsReporter: diagnosticsReporter
        )
        self.apiService = apiService
        self.apiGateway = apiGateway
        self.diagnosticsReporter = diagnosticsReporter

        // Temporary Admin Elevation wiring. The feature ships disabled by
        // default; a Jamf administrator supplies the dedicated request-group IDs
        // to enable it. Jamf writes go through the gateway-backed request-scope
        // service, and inventory reloads reuse the existing Support Technician
        // API service — no new networking, auth, or diagnostics stack.
        let temporaryAdminConfiguration = TemporaryAdminElevationConfiguration.disabledDefault
        let temporaryAdminService = TemporaryAdminElevationService(
            configuration: temporaryAdminConfiguration,
            requestScopeService: JamfComputerRequestScopeService(performer: apiGateway),
            diagnostics: diagnosticsReporter,
            inventoryReloader: apiService
        )
        self.temporaryAdminController = TemporaryAdminElevationController(
            configuration: temporaryAdminConfiguration,
            service: temporaryAdminService,
            diagnostics: diagnosticsReporter
        )

        // Apple-native Remote Support wiring. The controller wraps the state-machine coordinator
        // and reaches Jamf through the existing API service (focused enable/disable methods) and
        // native URL opening — no new networking, auth, credential, or diagnostics stack.
        self.remoteSupportController = SupportRemoteSupportController(
            enableCommand: { try await apiService.enableRemoteManagement(managementID: $0) },
            disableCommand: { try await apiService.disableRemoteManagement(managementID: $0) },
            launchURL: { url in
#if canImport(AppKit)
                NSWorkspace.shared.open(url)
#elseif canImport(UIKit)
                UIApplication.shared.open(url, options: [:], completionHandler: nil)
#endif
            },
            copyToClipboard: { DashboardClipboard.copy($0) },
            fetchCommandRecords: { try await apiService.fetchCommandHistory(for: $0).records },
            probeReachability: { await SupportRemoteSupportReachabilityProbe().probe(host: $0.host) },
            reportDiagnostics: { event in
                let severity: DiagnosticSeverity
                switch event.severity {
                case .info:    severity = .info
                case .warning: severity = .warning
                case .error:   severity = .error
                }
                Task {
                    await diagnosticsReporter.report(
                        source: "module.support-technician",
                        category: event.category,
                        severity: severity,
                        message: event.message,
                        metadata: event.metadata
                    )
                }
            }
        )
        // Assigned after all stored properties are initialized so the closure can capture self.
        self.remoteSupportController.onViewDiagnostics = { [weak self] in
            self?.isRemoteSupportDiagnosticsPresented = true
        }
    }

    /// Builds a Diagnostics view model for the Remote Support frame's "View Diagnostics" control.
    func makeDiagnosticsViewModel() -> DiagnosticsViewModel {
        DiagnosticsViewModel(diagnosticsReporter: diagnosticsReporter, apiGateway: apiGateway)
    }

    /// The search result matching the currently selected ID, if any.
    var selectedResult: SupportSearchResult? {
        guard let selectedResultID else {
            return nil
        }

        return searchResults.first(where: { $0.id == selectedResultID })
    }

    /// The management actions available for the selected device based on its type
    /// and the presence of required identifiers.
    var availableActions: [SupportManagementAction] {
        guard let selectedDetail else {
            return []
        }

        return Self.resolvedActions(for: selectedDetail)
    }

    // MARK: - Search

    /// Called by the view when the user changes `searchScope`. Clears stale
    /// results from the previous scope so the sidebar doesn't show computer
    /// devices when the user has switched to mobile (and vice versa). The
    /// user still has to tap Search to run the query against the new scope —
    /// this is just a state hygiene step.
    func resetForScopeChange() {
        searchResults = []
        selectedResultID = nil
        selectedDetail = nil
        installedApplications = []
        actionResult = nil
        presentedCredential = nil
        statusMessage = nil
    }

    /// Executes an asset search against Jamf Pro using the current query and scope.
    ///
    /// Clears the previous error, preserves the selected result if it still appears
    /// in the new results, and reports the outcome to diagnostics.
    func executeSearch() async {
        isSearching = true
        defer { isSearching = false }

        do {
            let results = try await apiService.searchAssets(query: query, scope: searchScope)
            searchResults = results
            errorMessage = nil
            actionResult = nil

            // Clear selection if the previously selected result is no longer in results
            if let selectedResultID,
               results.contains(where: { $0.id == selectedResultID }) == false
            {
                self.selectedResultID = nil
                selectedDetail = nil
                installedApplications = []
            }

            statusMessage = "Found \(results.count) matching assets."
            reportEvent(
                severity: .info,
                category: "search",
                message: "Support technician search completed.",
                metadata: [
                    "result_count": String(results.count),
                    "scope": searchScope.rawValue,
                    "ticket_reference": normalizedTicketReference
                ]
            )
        } catch {
            let description = describe(error)
            errorMessage = description
            statusMessage = nil
            reportError(
                category: "search",
                message: "Support technician search failed.",
                errorDescription: description,
                metadata: [
                    "scope": searchScope.rawValue,
                    "ticket_reference": normalizedTicketReference
                ]
            )
        }
    }

    // MARK: - Device Detail

    /// Loads the full device detail for the currently selected search result.
    ///
    /// Skips re-fetching if the detail is already loaded for the selected device.
    /// Resets application state and action results when loading new detail.
    func loadSelectedDeviceDetail(bypassCache: Bool = false) async {
        guard let selectedResult else {
            selectedDetail = nil
            actionResult = nil
            installedApplications = []
            return
        }

        // Skip if already loaded for this device — UNLESS the caller
        // explicitly requested a refresh (Refresh toolbar button).
        if bypassCache == false, selectedDetail?.id == selectedResult.id {
            return
        }

        isLoadingDetail = true
        defer { isLoadingDetail = false }

        do {
            let detail = try await apiService.fetchDeviceDetail(for: selectedResult, bypassCache: bypassCache)
            selectedDetail = detail
            actionResult = nil
            installedApplications = []
            commandHistory = .empty
            commandHistoryError = nil
            errorMessage = nil
            statusMessage = "Loaded \(selectedResult.assetType.title.lowercased()) details for \(selectedResult.serialNumber)."
            reportEvent(
                severity: .info,
                category: "detail",
                message: "Loaded support device detail.",
                metadata: [
                    "asset_type": selectedResult.assetType.rawValue,
                    "inventory_id": selectedResult.inventoryID,
                    "serial_number": selectedResult.serialNumber,
                    "ticket_reference": normalizedTicketReference
                ]
            )
        } catch {
            let description = describe(error)
            errorMessage = "Failed to load device detail. \(description)"
            statusMessage = nil
            reportError(
                category: "detail",
                message: "Failed loading support device detail.",
                errorDescription: description,
                metadata: [
                    "asset_type": selectedResult.assetType.rawValue,
                    "inventory_id": selectedResult.inventoryID,
                    "serial_number": selectedResult.serialNumber,
                    "ticket_reference": normalizedTicketReference
                ]
            )
        }
    }

    /// Forces a full reload of the selected device detail by clearing cached state first.
    /// Bypasses the persistent local cache so a fresh payload is pulled
    /// from Jamf Pro — wired to the Refresh toolbar button.
    func refreshSelectedDeviceDetail() async {
        selectedDetail = nil
        installedApplications = []
        await loadSelectedDeviceDetail(bypassCache: true)
    }

    /// Refreshes the selected detail record without clearing the current pane
    /// or setting the visible loading state. Command verification uses this so
    /// the MDM lifecycle animation remains clean while the inventory timestamp
    /// is polled in the background.
    private func silentlyRefreshSelectedDeviceDetail() async {
        guard let selectedResult,
              let currentDetailID = selectedDetail?.id
        else {
            return
        }

        do {
            let detail = try await apiService.fetchDeviceDetail(for: selectedResult, bypassCache: true)
            guard selectedDetail?.id == currentDetailID,
                  detail.id == currentDetailID
            else {
                return
            }
            selectedDetail = detail
        } catch {
            let description = describe(error)
            reportError(
                category: "detail",
                message: "Silent detail refresh failed.",
                errorDescription: description,
                metadata: [
                    "asset_type": selectedResult.assetType.rawValue,
                    "inventory_id": selectedResult.inventoryID,
                    "serial_number": selectedResult.serialNumber,
                    "ticket_reference": normalizedTicketReference
                ]
            )
        }
    }

    /// Purges every entry from the persistent local cache. Wired to the
    /// Clear Cache toolbar button. After purging, the currently-selected
    /// device's detail is dropped from in-memory state too so the next
    /// view re-fetches.
    func clearLocalCache() async {
        await apiService.cache.clearAll()
        selectedDetail = nil
        installedApplications = []
        commandHistory = .empty
        allPolicies = []
        statusMessage = "Local Support Technician cache cleared."
    }

    // MARK: - Application Manager (v3.18+)

    /// Loads the list of applications currently installed on the selected Mac.
    ///
    /// Called by the Application Manager view on first appearance and from its
    /// "Refresh" control. Mobile devices early-exit — the Application Manager
    /// only supports computers in this release (see the inline note rendered
    /// in the view for mobile).
    ///
    /// Any in-flight call is allowed to complete before a subsequent invocation;
    /// repeated taps during a load are no-ops. On error, the list is left
    /// unchanged and the error is surfaced via `errorMessage`.
    func loadInstalledApplications() async {
        guard isLoadingInstalledApplications == false else {
            return
        }

        guard let selectedDetail else {
            errorMessage = SupportTechnicianError.missingSelection.errorDescription
            return
        }

        guard selectedDetail.summary.assetType == .computer else {
            // Mobile devices are explicitly out of scope for the new
            // Application Manager. The view shows an inline note explaining
            // that mobile app management is handled via Jamf Pro's web console.
            installedApplications = []
            return
        }

        isLoadingInstalledApplications = true
        defer { isLoadingInstalledApplications = false }

        let inventoryID = selectedDetail.summary.inventoryID
        let serialNumber = selectedDetail.summary.serialNumber

        do {
            let applications = try await apiService.fetchInstalledApplications(
                inventoryID: inventoryID
            )

            installedApplications = applications
            errorMessage = nil
            statusMessage = "Loaded \(applications.count) installed application\(applications.count == 1 ? "" : "s") on \(selectedDetail.summary.displayName)."

            reportEvent(
                severity: .info,
                category: "application-manager",
                message: "Loaded installed applications for selected device.",
                metadata: [
                    "inventory_id": inventoryID,
                    "serial_number": serialNumber,
                    "count": String(applications.count),
                    "ticket_reference": normalizedTicketReference
                ]
            )
        } catch {
            let description = describe(error)
            errorMessage = "Failed to load installed applications. \(description)"
            statusMessage = nil

            reportError(
                category: "application-manager",
                message: "Failed loading installed applications.",
                errorDescription: description,
                metadata: [
                    "inventory_id": inventoryID,
                    "serial_number": serialNumber,
                    "ticket_reference": normalizedTicketReference
                ]
            )
        }
    }

    /// Runs the `GET /api/v1/auth` pre-flight check for Application Manager.
    ///
    /// Fires once per Application Manager view appearance (more than once is
    /// harmless but wasteful — a cached result already answers the question).
    /// On success, updates `applicationManagerMissingPrivileges` to the list
    /// of missing privilege names (empty means all present). On failure,
    /// leaves the existing value alone and surfaces a status banner so the
    /// user knows the check couldn't run — the buttons stay enabled in this
    /// case since failure mode = "unknown," not "definitely missing."
    func checkApplicationManagerPrivileges() async {
        guard isCheckingApplicationManagerPrivileges == false else {
            return
        }

        isCheckingApplicationManagerPrivileges = true
        defer { isCheckingApplicationManagerPrivileges = false }

        do {
            let missing = try await apiService.missingApplicationManagerPrivileges()
            applicationManagerMissingPrivileges = missing

            if missing.isEmpty == false {
                reportEvent(
                    severity: .warning,
                    category: "application-manager",
                    message: "Pre-flight privilege check surfaced missing privileges.",
                    metadata: [
                        "missing_count": String(missing.count),
                        "missing_list": missing.joined(separator: ", "),
                        "ticket_reference": normalizedTicketReference
                    ]
                )
            }
        } catch {
            let description = describe(error)
            // Don't clobber the missing-privileges state on transient failure;
            // a previously-observed all-green result should persist. Surface
            // the failure as a status message instead of an error banner,
            // since the user can proceed — the action itself will report a
            // 403 later if privileges are actually wrong.
            statusMessage = "Pre-flight privilege check failed. \(description)"

            reportError(
                category: "application-manager",
                message: "Pre-flight privilege check failed.",
                errorDescription: description,
                metadata: [
                    "ticket_reference": normalizedTicketReference
                ]
            )
        }
    }

    /// Dispatches a single `ApplicationAction` against the currently selected
    /// Mac. Composes script creation, one-shot policy creation, and a blank
    /// push into a single async call; emits diagnostics at every phase.
    ///
    /// Early-exits (with an error banner) if:
    /// - No device is selected.
    /// - The selected device is a mobile device.
    /// - The selected device is missing a management ID (without which the
    ///   blank push can't be delivered).
    ///
    /// On success, refreshes the installed-apps list so the row the user
    /// acted on reflects reality on its next render (e.g. the app no longer
    /// appears after an Uninstall). The post-action refresh is a
    /// best-effort and doesn't fail the action if the follow-up load fails.
    func performAppAction(_ action: ApplicationAction) async {
        guard let selectedDetail else {
            errorMessage = SupportTechnicianError.missingSelection.errorDescription
            return
        }

        guard selectedDetail.summary.assetType == .computer else {
            errorMessage = "Application Manager actions are only supported on computers in this release."
            statusMessage = nil
            return
        }

        guard let managementID = selectedDetail.summary.clientManagementID
                ?? selectedDetail.summary.managementID,
              managementID.isEmpty == false
        else {
            errorMessage = "Cannot dispatch action: the selected device has no management identifier in Jamf Pro."
            statusMessage = nil
            return
        }

        let inventoryID = selectedDetail.summary.inventoryID
        let serialNumber = selectedDetail.summary.serialNumber
        let deviceDisplayName = selectedDetail.summary.displayName

        isPerformingAppAction = true
        defer { isPerformingAppAction = false }

        errorMessage = nil
        statusMessage = "\(action.verb) queuing for \(action.appName) on \(deviceDisplayName)…"

        do {
            let result = try await apiService.triggerAppPolicy(
                action: action,
                inventoryID: inventoryID,
                managementID: managementID,
                serialNumber: serialNumber,
                deviceDisplayName: deviceDisplayName
            )

            errorMessage = nil
            statusMessage = "\(result.action.queuedVerb) queued for \(result.action.appName) on \(serialNumber). The device will run the policy on its next MDM check-in."

            reportEvent(
                severity: .warning,
                category: "application-manager",
                message: "\(action.verb) queued via one-shot Jamf Pro policy.",
                metadata: [
                    "action": action.verb.lowercased(),
                    "app_name": action.appName,
                    "custom_trigger": action.customTrigger,
                    "inventory_id": inventoryID,
                    "serial_number": serialNumber,
                    "script_id": result.scriptID,
                    "policy_id": result.policyID,
                    "ticket_reference": normalizedTicketReference
                ]
            )

            // Refresh the installed-apps list so the user sees updated state
            // after a successful action. Best-effort — a failure here is
            // logged but doesn't shadow the successful dispatch.
            await loadInstalledApplications()

            // Kick off the post-action verification poll. The view renders
            // state transitions via `applicationActionVerification`.
            startApplicationActionVerification(
                action: action,
                serialNumber: serialNumber,
                inventoryID: inventoryID
            )
        } catch {
            let description = describe(error)
            errorMessage = "\(action.verb) failed. \(description)"
            statusMessage = nil

            reportError(
                category: "application-manager",
                message: "\(action.verb) dispatch failed.",
                errorDescription: description,
                metadata: [
                    "action": action.verb.lowercased(),
                    "app_name": action.appName,
                    "inventory_id": inventoryID,
                    "serial_number": serialNumber,
                    "ticket_reference": normalizedTicketReference
                ]
            )
        }
    }

    /// Starts the post-action verification poll for a newly-dispatched
    /// Application Manager action.
    ///
    /// Cancels any previous polling task, transitions the state to
    /// `.queued`, then launches a detached async task that re-fetches the
    /// APPLICATIONS inventory every 30 seconds up to 20 times. Each
    /// observation updates `installedApplications` in place and checks
    /// whether the expected state holds — the app is present (for install)
    /// or absent (for uninstall). On a positive observation, transitions to
    /// `.verified`. On exhaustion, transitions to `.timedOut`.
    ///
    /// Runs independently of the view's lifetime; the task captures the
    /// needed context at start. Task cancellation happens on (a) a new
    /// action dispatch, (b) the view model being deallocated. Cancellation
    /// simply stops the loop — no state transition; the `.queued` /
    /// `.checkingIn` banner just freezes until a subsequent action starts
    /// a fresh verification.
    func startApplicationActionVerification(
        action: ApplicationAction,
        serialNumber: String,
        inventoryID: String
    ) {
        // Cancel any in-flight verification — the newer dispatch supersedes it.
        applicationActionVerificationTask?.cancel()

        applicationActionVerification = .queued(
            action: action,
            serialNumber: serialNumber,
            startedAt: Date()
        )

        applicationActionVerificationTask = Task { [weak self] in
            guard let self else { return }
            await self.runApplicationActionVerificationLoop(
                action: action,
                serialNumber: serialNumber,
                inventoryID: inventoryID
            )
        }
    }

    /// Inner polling loop. Runs up to `applicationActionVerificationMaxAttempts`
    /// iterations, sleeping `applicationActionVerificationInterval` seconds
    /// between each, calling `fetchInstalledApplications` and checking for
    /// the expected state transition. Exits early on success / cancellation
    /// / error.
    private func runApplicationActionVerificationLoop(
        action: ApplicationAction,
        serialNumber: String,
        inventoryID: String
    ) async {
        let startedAt = Date()

        for attempt in 1...applicationActionVerificationMaxAttempts {
            // Respect cancellation at the top of every iteration.
            if Task.isCancelled {
                return
            }

            // Wait the poll interval before the fetch. Sleeping first gives
            // Jamf Pro and the device time to propagate the blank push.
            try? await Task.sleep(nanoseconds: UInt64(applicationActionVerificationInterval * 1_000_000_000))

            if Task.isCancelled {
                return
            }

            // Transition to checkingIn so the banner reflects the poll state
            // rather than staying on "queued" indefinitely.
            applicationActionVerification = .checkingIn(
                action: action,
                serialNumber: serialNumber,
                startedAt: startedAt,
                attempt: attempt
            )

            let applications: [DeviceApplication]
            do {
                applications = try await apiService.fetchInstalledApplications(inventoryID: inventoryID)
            } catch {
                // Log and keep polling — a transient network failure shouldn't
                // abort the whole verification. The final attempt either
                // succeeds or hits the timeout.
                reportError(
                    category: "application-manager",
                    message: "Verification poll fetch failed; continuing.",
                    errorDescription: describe(error),
                    metadata: [
                        "inventory_id": inventoryID,
                        "serial_number": serialNumber,
                        "action": action.verb.lowercased(),
                        "app_name": action.appName,
                        "attempt": String(attempt)
                    ]
                )
                continue
            }

            // Best-effort installed-apps refresh so the user sees fresh
            // state during the wait.
            installedApplications = applications

            let containsApp = applications.contains { app in
                app.displayName.caseInsensitiveCompare(action.appName) == .orderedSame
            }

            let satisfied: Bool = {
                switch action {
                case .install:
                    return containsApp
                case .uninstall:
                    return containsApp == false
                }
            }()

            if satisfied {
                let duration = Date().timeIntervalSince(startedAt)
                applicationActionVerification = .verified(
                    action: action,
                    serialNumber: serialNumber,
                    duration: duration
                )
                statusMessage = "\(action.queuedVerb) verified for \(action.appName) on \(serialNumber) after \(Int(duration)) seconds."

                reportEvent(
                    severity: .info,
                    category: "application-manager",
                    message: "Post-action verification succeeded.",
                    metadata: [
                        "action": action.verb.lowercased(),
                        "app_name": action.appName,
                        "serial_number": serialNumber,
                        "inventory_id": inventoryID,
                        "duration_seconds": String(Int(duration)),
                        "attempt": String(attempt)
                    ]
                )
                return
            }
        }

        // Ran out of attempts. Don't fail the action — just mark as timed out.
        applicationActionVerification = .timedOut(action: action, serialNumber: serialNumber)
        statusMessage = "\(action.queuedVerb) for \(action.appName) on \(serialNumber) wasn't verified within the 10-minute window. The device may still process the policy on its next check-in — verify manually in Jamf Pro."

        reportEvent(
            severity: .warning,
            category: "application-manager",
            message: "Post-action verification timed out.",
            metadata: [
                "action": action.verb.lowercased(),
                "app_name": action.appName,
                "serial_number": serialNumber,
                "inventory_id": inventoryID,
                "attempts": String(applicationActionVerificationMaxAttempts)
            ]
        )
    }

    // MARK: - Management Actions

    /// Executes a management action on the selected device.
    ///
    /// For inventory-refresh and application-discovery actions, automatically
    /// reloads the device detail after a successful command to reflect updated state.
    ///
    /// - Parameter action: The management action to perform.
    func performAction(_ action: SupportManagementAction) async {
        guard let selectedDetail else {
            errorMessage = SupportTechnicianError.missingSelection.errorDescription
            return
        }

        // Reset any in-flight lifecycle state from a previous command so
        // the indicator visibly restarts for this new action.
        commandLifecycleVerificationTask?.cancel()
        commandLifecycleAutoDismissTask?.cancel()

        isPerformingAction = true
        let priorContactTime = selectedDetail.summary.lastInventoryUpdate
        let sendingStartedAt = Date()
        commandLifecycle = .sending(action: action, startedAt: sendingStartedAt)

        do {
            let result = try await apiService.perform(action, for: selectedDetail)
            actionResult = result
            errorMessage = nil
            statusMessage = result.detail

            // Surface any returned secret (LAPS / jssmanage / recovery-lock
            // password, device-lock PIN, FileVault key) in the one-time
            // credential popup. The non-secret summary is derived separately
            // via `resultSummary` for the sidebar frame. Without this the
            // password was fetched and stored on `actionResult` but never
            // shown anywhere.
            presentedCredential = SupportActionResultPresentation.make(from: result).credential

            // Minimum dwell on `.sending` so the indicator's pulse
            // animation is visibly perceptible. Fast API responses
            // (200ms or less) would otherwise flash through
            // sending → queued → succeeded before the user could see
            // any motion, which is why the indicator "didn't appear to
            // do anything" in the prior build.
            let sendingElapsed = Date().timeIntervalSince(sendingStartedAt)
            if sendingElapsed < 0.7 {
                try? await Task.sleep(nanoseconds: UInt64((0.7 - sendingElapsed) * 1_000_000_000))
            }

            commandLifecycle = .queued(action: action, queuedAt: Date())

            reportEvent(
                severity: .warning,
                category: "management",
                message: "Executed support management action.",
                metadata: [
                    "action": action.rawValue,
                    "asset_type": selectedDetail.summary.assetType.rawValue,
                    "inventory_id": selectedDetail.summary.inventoryID,
                    "serial_number": selectedDetail.summary.serialNumber,
                    "ticket_reference": normalizedTicketReference
                ]
            )

            // Verification path: for actions whose ground-truth completion
            // is reflected in inventory, hand off to the polling task. The
            // task transitions the lifecycle to .verifying → .succeeded or
            // .timedOut. Non-verifying actions complete on API return.
            if action.requiresInventoryVerification {
                isPerformingAction = false
                startCommandVerification(for: action, priorContactTime: priorContactTime)
            } else {
                // Hold `.queued` for a beat too so the user perceives the
                // command-queued state before the final `.succeeded`
                // checkmark. Without this the indicator transitions
                // queued → succeeded inside the same display frame and
                // looks like nothing happened.
                try? await Task.sleep(nanoseconds: 600_000_000)
                commandLifecycle = .succeeded(action: action, completedAt: Date())
                isPerformingAction = false
                scheduleLifecycleAutoDismiss()
            }

            // Auto-refresh detail after inventory or discovery commands
            if action == .refreshInventory || action == .discoverApplications {
                await silentlyRefreshSelectedDeviceDetail()
            }

            // Refresh the Command History frame so the colored bucket
            // boxes pick up the just-queued command. /api/v2/mdm/commands
            // reflects new commands immediately after a successful POST,
            // so one shot is enough; fire-and-forget so the action button
            // re-enables on the existing dwell budget and not on whatever
            // the history fetch takes.
            Task { [weak self] in
                await self?.loadCommandHistory()
            }
            return
        } catch {
            let description = describe(error)
            // Shared `isJamfInvalidPrivilege` covers both typed
            // `.forbidden(message)` and untyped `.networkFailure(403, _)`
            // in one expression — the two-case if/else-if chain this
            // replaced was drifting out of sync with the other modules'
            // privilege-denial detection.
            let isPrivilegeDenial = error.isJamfInvalidPrivilege

            // The left-column banner (`errorMessage`) only ever carries
            // graceful, action-oriented text. Raw response bodies, stack
            // dumps, and Jamf's verbose error JSON are not user-facing —
            // they belong in the failure popup's "Raw response" disclosure
            // and the Diagnostics export. The old code wrote a multi-
            // paragraph block containing the raw response into
            // `errorMessage`, which then surfaced as red text in the
            // search-results sidebar.
            errorMessage = gracefulActionErrorMessage(
                action: action,
                error: error,
                isPrivilegeDenial: isPrivilegeDenial
            )
            statusMessage = nil
            commandLifecycle = .failed(action: action, errorDescription: description)
            isPerformingAction = false
            scheduleLifecycleAutoDismiss()

            // The rich failure popup is the primary user-facing surface for
            // command failures — summary + suggestion + per-command likely
            // privilege + collapsible raw response. The left-column banner
            // is just a hint that something failed; tapping the device or
            // re-trying the action opens the popup again via the popup's
            // own presentation logic.
            actionFailurePopup = Self.buildActionFailurePopup(
                action: action,
                description: description,
                isPrivilegeDenial: isPrivilegeDenial
            )

            reportError(
                category: "management",
                message: "Support management action failed.",
                errorDescription: description,
                metadata: [
                    "action": action.rawValue,
                    "asset_type": selectedDetail.summary.assetType.rawValue,
                    "inventory_id": selectedDetail.summary.inventoryID,
                    "serial_number": selectedDetail.summary.serialNumber,
                    "ticket_reference": normalizedTicketReference
                ]
            )
        }
    }

    /// Starts the inventory-polling task that drives the lifecycle from
    /// `.queued` → `.verifying` → `.succeeded` / `.timedOut`. Watches the
    /// device's `lastInventoryUpdate` timestamp — when it advances past the
    /// pre-command value, the device has checked in and the command is
    /// considered confirmed.
    private func startCommandVerification(
        for action: SupportManagementAction,
        priorContactTime: String?
    ) {
        commandLifecycleVerificationTask?.cancel()
        commandLifecycleVerificationTask = Task { [weak self] in
            guard let self else { return }
            let maxAttempts = self.commandVerificationMaxAttempts
            let intervalSeconds = self.commandVerificationIntervalSeconds

            for attempt in 1...maxAttempts {
                try? await Task.sleep(nanoseconds: intervalSeconds * 1_000_000_000)
                if Task.isCancelled { return }

                self.commandLifecycle = .verifying(action: action, startedAt: Date(), attempt: attempt)
                await self.silentlyRefreshSelectedDeviceDetail()
                if Task.isCancelled { return }

                let currentContactTime = self.selectedDetail?.summary.lastInventoryUpdate
                if let currentContactTime,
                   currentContactTime != priorContactTime
                {
                    self.commandLifecycle = .succeeded(action: action, completedAt: Date())
                    self.scheduleLifecycleAutoDismiss()
                    return
                }
            }

            self.commandLifecycle = .timedOut(action: action)
            self.scheduleLifecycleAutoDismiss()
        }
    }

    /// Schedules a single auto-dismiss timer that resets `commandLifecycle`
    /// to `.idle` after `commandLifecycleAutoDismissSeconds` of any terminal
    /// state. When the dismiss interval is 0 the timer is skipped — the
    /// indicator persists until the user dismisses it or starts a new
    /// command.
    private func scheduleLifecycleAutoDismiss() {
        commandLifecycleAutoDismissTask?.cancel()
        guard commandLifecycleAutoDismissSeconds > 0 else {
            return
        }
        commandLifecycleAutoDismissTask = Task { [weak self] in
            guard let self else { return }
            try? await Task.sleep(nanoseconds: self.commandLifecycleAutoDismissSeconds * 1_000_000_000)
            if Task.isCancelled { return }
            if self.commandLifecycle.isTerminal {
                self.commandLifecycle = .idle
            }
        }
    }

    /// User-triggered dismiss for the lifecycle indicator. Called from
    /// the Dismiss button on the indicator's terminal states.
    func dismissCommandLifecycle() {
        commandLifecycleAutoDismissTask?.cancel()
        commandLifecycle = .idle
    }

    // MARK: - Per-row local-user password reset

    /// Entry point from the per-row Reset Password button in the User
    /// Accounts frame. Captures the target user and clears the typed-
    /// confirm buffer; the View observes `passwordResetCandidate` and
    /// presents the typed-confirm sheet bound to this user.
    ///
    /// The actual rotate request runs in `executePasswordReset()`,
    /// which is called after the technician types `confirm` and taps
    /// the sheet's Confirm button.
    func requestPasswordReset(for user: SupportLocalUser) {
        passwordResetCandidate = user
        passwordResetConfirmationText = ""
    }

    /// Dismisses the typed-confirm sheet without rotating. Idempotent
    /// — safe to call from a Cancel button, a backgrounded sheet, or
    /// the device-change `resetForScopeChange` path.
    func cancelPasswordReset() {
        passwordResetCandidate = nil
        passwordResetConfirmationText = ""
    }

    /// Runs the per-row password rotate request for the user the
    /// technician most recently tapped Reset Password on. The View
    /// invokes this only after the typed-confirm sheet has cleared its
    /// `confirm` gate, so the method assumes confirmation has already
    /// happened — no extra gate check is needed.
    ///
    /// Orchestration mirrors `performAction` closely: lifecycle
    /// indicator transitions through `.sending → .queued → .succeeded`
    /// (or `.failed`), the action result populates `actionResult` so
    /// the existing sensitive-value display surfaces the new password
    /// for one-time view + copy, the rich `actionFailurePopup` carries
    /// any failure with the same per-class graceful banner the regular
    /// actions use, and the full error chain reaches the diagnostics
    /// export via `reportError`.
    func executePasswordReset() async {
        guard let user = passwordResetCandidate else { return }
        guard let detail = selectedDetail else {
            // Defensive: should never happen because the per-row button
            // is rendered inside the detail pane, but if the selection
            // races to nil during confirmation the typed-confirm sheet
            // simply dismisses with no command queued.
            passwordResetCandidate = nil
            passwordResetConfirmationText = ""
            return
        }

        // Dismiss the typed-confirm sheet immediately so the technician
        // sees the lifecycle indicator pick up the work.
        passwordResetCandidate = nil
        passwordResetConfirmationText = ""

        // Reset any in-flight lifecycle from a prior command so the
        // indicator visibly restarts. Mirrors `performAction`.
        commandLifecycleVerificationTask?.cancel()
        commandLifecycleAutoDismissTask?.cancel()

        isPerformingAction = true
        let sendingStartedAt = Date()
        commandLifecycle = .sending(action: .rotateLAPSPassword, startedAt: sendingStartedAt)

        do {
            let result = try await apiService.resetLocalUserPassword(
                for: detail,
                username: user.username
            )
            actionResult = result
            errorMessage = nil
            statusMessage = result.detail

            // Surface the newly-rotated password in the one-time credential
            // popup (same treatment as `viewLAPSAccountPassword`).
            presentedCredential = SupportActionResultPresentation.make(from: result).credential

            // Minimum dwells on `.sending` and `.queued` so fast API
            // responses (sub-200ms) don't flash invisibly through the
            // lifecycle phases. Same dwell budget as `performAction`.
            let sendingElapsed = Date().timeIntervalSince(sendingStartedAt)
            if sendingElapsed < 0.7 {
                try? await Task.sleep(nanoseconds: UInt64((0.7 - sendingElapsed) * 1_000_000_000))
            }
            commandLifecycle = .queued(action: .rotateLAPSPassword, queuedAt: Date())
            try? await Task.sleep(nanoseconds: 600_000_000)
            commandLifecycle = .succeeded(action: .rotateLAPSPassword, completedAt: Date())
            isPerformingAction = false
            scheduleLifecycleAutoDismiss()

            reportEvent(
                severity: .warning,
                category: "management",
                message: "Executed per-row password reset.",
                metadata: [
                    "action": "resetLocalUserPassword",
                    "asset_type": detail.summary.assetType.rawValue,
                    "inventory_id": detail.summary.inventoryID,
                    "serial_number": detail.summary.serialNumber,
                    "account_name": user.username,
                    "ticket_reference": normalizedTicketReference
                ]
            )
        } catch {
            let description = describe(error)
            let isPrivilegeDenial = error.isJamfInvalidPrivilege

            // Short graceful banner only — full detail belongs in the
            // `actionFailurePopup` and the diagnostics export. Uses the
            // password-specific wording (account name in the hint, LAPS
            // hint on 404) so the sidebar reads naturally for password
            // reset failures.
            errorMessage = passwordResetBannerMessage(
                username: user.username,
                error: error,
                isPrivilegeDenial: isPrivilegeDenial
            )
            statusMessage = nil
            commandLifecycle = .failed(action: .rotateLAPSPassword, errorDescription: description)
            isPerformingAction = false
            scheduleLifecycleAutoDismiss()

            actionFailurePopup = Self.buildActionFailurePopup(
                action: .rotateLAPSPassword,
                description: description,
                isPrivilegeDenial: isPrivilegeDenial
            )

            reportError(
                category: "management",
                message: "Per-row password reset failed.",
                errorDescription: description,
                metadata: [
                    "action": "resetLocalUserPassword",
                    "asset_type": detail.summary.assetType.rawValue,
                    "inventory_id": detail.summary.inventoryID,
                    "serial_number": detail.summary.serialNumber,
                    "account_name": user.username,
                    "ticket_reference": normalizedTicketReference
                ]
            )
        }
    }

    /// Builds the short, action-oriented sidebar banner shown when the
    /// per-row password reset fails. Detailed remediation lives in the
    /// `actionFailurePopup`; the diagnostics export captures the full
    /// raw response. Banner text is one short sentence — no raw
    /// response bodies, no multi-line blocks.
    private func passwordResetBannerMessage(
        username: String,
        error: any Error,
        isPrivilegeDenial: Bool
    ) -> String {
        let privilege = "Send Local Admin Password Command"

        if isPrivilegeDenial {
            return "Reset Password for \(username) needs the Jamf privilege \"\(privilege)\"."
        }
        if let frameworkError = error as? JamfFrameworkError {
            switch frameworkError {
            case .credentialsRejected, .authenticationFailed:
                return "Reset Password for \(username) needs the Jamf privilege \"\(privilege)\"."
            case .notFound:
                return "Account \"\(username)\" isn't registered with Jamf LAPS — password rotation isn't available."
            case .rateLimited:
                return "Jamf Pro rate-limited the request. Wait a moment and try again."
            case let .serverError(statusCode, _):
                return "Jamf Pro returned a server error (\(statusCode))."
            case let .networkFailure(statusCode, _):
                return "Reset Password for \(username) could not complete (HTTP \(statusCode))."
            default:
                return "Reset Password for \(username) could not complete."
            }
        }
        return "Reset Password for \(username) could not complete."
    }

    /// Builds the short, action-oriented text shown in the left-column
    /// error banner (`errorMessage`) when a `performAction` call throws.
    ///
    /// Strict UX policy: the banner is ONE short sentence. Raw Jamf
    /// response bodies, error JSON dumps, HTTP-protocol detail, and
    /// privilege-gate documentation never reach this string — they
    /// live exclusively in the framework's diagnostics export.
    ///
    /// Per-class wording:
    ///   • 403 INVALID_PRIVILEGE — names the per-command privilege the
    ///     role likely needs, full stop.
    ///   • 401 / credentialsRejected / authenticationFailed — treats
    ///     this as a likely missing-privilege scenario on this codebase
    ///     (modern Jamf Pro sometimes returns 401 instead of 403 when
    ///     a role lacks the per-command privilege), so the banner also
    ///     names the privilege. The popup carries the longer
    ///     remediation copy with the auth-incompatibility caveat.
    ///   • 404 — short "not found" sentence with the action name.
    ///   • 429 — "rate-limited" hint.
    ///   • 5xx — short server-error hint with the status code.
    ///   • generic — "could not complete" with the action name.
    private func gracefulActionErrorMessage(
        action: SupportManagementAction,
        error: any Error,
        isPrivilegeDenial: Bool
    ) -> String {
        let privilege = Self.likelyPrivilege(for: action)

        if isPrivilegeDenial {
            if let privilege {
                return "\(action.title) needs the Jamf privilege \"\(privilege)\"."
            }
            return "\(action.title) is missing a Jamf Pro privilege."
        }

        if let frameworkError = error as? JamfFrameworkError {
            switch frameworkError {
            case .credentialsRejected, .authenticationFailed:
                if let privilege {
                    return "\(action.title) needs the Jamf privilege \"\(privilege)\"."
                }
                return "\(action.title) is missing a Jamf privilege required by Jamf Pro."
            case .notFound:
                return "\(action.title) — Jamf Pro didn't find the target on this tenant."
            case .rateLimited:
                return "Jamf Pro rate-limited the request. Wait a moment and try again."
            case let .serverError(statusCode, _):
                return "Jamf Pro returned a server error (\(statusCode))."
            case let .networkFailure(statusCode, _):
                return "\(action.title) could not complete (HTTP \(statusCode))."
            default:
                return "\(action.title) could not complete."
            }
        }

        return "\(action.title) could not complete."
    }

    /// Maps an MDM commandType / action to the literal Jamf privilege
    /// name the API role needs. Used by `buildActionFailurePopup` to
    /// suggest exactly which privilege to grant when the action 403s.
    /// Returns `nil` for actions whose privilege is unknown — the popup
    /// then says "verify the API role has Send MDM command information
    /// in Jamf Pro API" (the base gate) and includes the raw response.
    private static func likelyPrivilege(for action: SupportManagementAction) -> String? {
        switch action {
        case .refreshInventory:
            return "Send Declarative Management Command"
        case .blankPush:
            return "Send Computer Blank Push (or Send Mobile Device Blank Push)"
        case .discoverApplications:
            return "Send Inventory Requested Command"
        case .restartDevice:
            return "Send Computer Restart Command (or Send Mobile Device Restart Command)"
        case .shutDownDevice:
            return "Send Computer Shut Down Command (or Send Mobile Device Shut Down Command)"
        case .sendDeviceLock:
            return "Send Computer Remote Lock Command (or Send Mobile Device Remote Lock Command)"
        case .logOutUser:
            return "Send Computer Log Out User Command"
        case .clearPasscode:
            return "Send Mobile Device Clear Passcode Command"
        case .eraseDevice:
            return "Send Computer Remote Wipe Command (or Send Mobile Device Remote Wipe Command)"
        case .viewFileVaultPersonalRecoveryKey:
            return "View Disk Encryption Recovery Key"
        case .viewRecoveryLockPassword:
            return "View Recovery Lock"
        case .viewDeviceLockPIN:
            return "View MDM command information in Jamf Pro API"
        case .viewLAPSAccountPassword:
            return "View Local Admin Password"
        case .viewJamfManagementAccountPassword:
            return "View Local Admin Password"
        case .rotateLAPSPassword:
            return "Send Local Admin Password Command"
        case .enableBluetooth, .disableBluetooth:
            return "Send Settings Command"
        case .enableLostMode, .disableLostMode, .playLostModeSound:
            return "Send Mobile Device Lost Mode Command"
        case .requestDeviceLocation:
            return "Send Mobile Device Location Command"
        case .clearRestrictionsPassword:
            return "Send Mobile Device Clear Restrictions Password Command"
        case .refreshCellularPlans:
            return "Send Refresh Cellular Plans Command"
        case .scheduleOSUpdate:
            // ScheduleOSUpdate routes through
            // `POST /api/v1/managed-software-updates/plans` because
            // the tenant has the Managed Software Update Plans toggle
            // enabled, which Jamf uses to disable every variant of
            // the legacy Classic ScheduleOSUpdate command (both URL
            // and XML-body forms return 503). The modern endpoint is
            // gated by the "Create Managed Software Updates"
            // privilege.
            return "Create Managed Software Updates"
        case .settingsSync:
            return "Send Settings Command"
        case .enableWifi, .disableWifi:
            return "Send Settings Command"
        case .enableFileVault, .redeployManagementFramework:
            return "Send Update Inventory Command (or Re-enrol Computer Command)"
        }
    }

    /// Constructs the verbose failure popup payload for the most recent
    /// failed `performAction` call. The popup distinguishes three
    /// classes of failure so the technician sees specific, actionable
    /// remediation rather than the generic "Jamf Pro returned an error"
    /// text:
    ///
    ///   • **403 INVALID_PRIVILEGE** — Jamf accepted the token but the
    ///     role is missing one or more per-command privileges. The
    ///     popup names the likely missing privilege and the base gate.
    ///   • **401 / credentialsRejected** — Jamf rejected the token
    ///     outright on at least one endpoint. Could be a legitimate
    ///     credential issue, but on this codebase it most often surfaces
    ///     when a Classic POST command endpoint refuses Bearer tokens
    ///     on a tenant configuration where the API client has the
    ///     correct privileges but the Classic endpoint requires Basic
    ///     auth. The popup names the likely missing privilege _and_
    ///     calls out the Classic-Bearer-auth incompatibility so the
    ///     admin knows where to look.
    ///   • **other** — generic remediation per HTTP status / message.
    private static func buildActionFailurePopup(
        action: SupportManagementAction,
        description: String,
        isPrivilegeDenial: Bool
    ) -> SupportActionFailure {
        let privilege = likelyPrivilege(for: action)

        if isPrivilegeDenial {
            let suggestion: String
            if let privilege {
                suggestion = "Verify the Jamf Pro API role has the privilege \"\(privilege)\" — and the base \"View MDM command information in Jamf Pro API\" gate. Update the role in Settings → System → Jamf Pro user accounts and groups → Privileges → Jamf Pro Server Actions, then retry the command."
            } else {
                suggestion = "Verify the Jamf Pro API role has \"View MDM command information in Jamf Pro API\" (the base gate) plus the per-command privilege. Update the role in Settings → System → Jamf Pro user accounts and groups → Privileges → Jamf Pro Server Actions, then retry."
            }
            return SupportActionFailure(
                actionTitle: action.title,
                summary: "Jamf Pro rejected the request with 403 INVALID_PRIVILEGE.",
                suggestion: suggestion,
                likelyPrivilege: privilege,
                rawDetail: description,
                isPrivilegeDenial: true
            )
        }

        // Credentials-rejected (double 401) — on this codebase the most
        // common cause is a Classic POST command endpoint refusing the
        // OAuth Bearer token even when the API client has the required
        // privileges. Surface the likely-missing privilege alongside the
        // Classic-Bearer-auth callout so the admin can verify both
        // axes at once.
        if description.lowercased().contains("credentials were rejected")
            || description.lowercased().contains("401")
        {
            let suggestion: String
            if let privilege {
                suggestion = "Jamf Pro returned 401 Unauthorized. Two likely causes:\n  • The API role is missing the privilege \"\(privilege)\" — verify in Settings → System → Jamf Pro user accounts and groups → Privileges → Jamf Pro Server Actions.\n  • The endpoint rejects OAuth Bearer tokens on this tenant (some Classic command endpoints require Basic auth even when reads with the same token succeed). If the privilege is already granted, contact the Jamf Pro admin to confirm Classic API authentication for the command endpoint, or expect the modern v1 endpoint to be used.\nRetry once after granting the privilege; if the failure persists, the second cause is the likely path."
            } else {
                suggestion = "Jamf Pro returned 401 Unauthorized. Verify the API role has the per-command privilege plus the base \"View MDM command information in Jamf Pro API\" gate. If both are present, the endpoint may not accept OAuth Bearer tokens on this tenant (some Classic command endpoints require Basic auth) — contact the Jamf Pro admin."
            }
            return SupportActionFailure(
                actionTitle: action.title,
                summary: "Jamf Pro rejected the request's credentials (HTTP 401).",
                suggestion: suggestion,
                // Surface the likely privilege even for 401 so the popup's
                // dedicated privilege row shows the same hint the 403 path
                // would. The UI distinguishes 401 vs 403 via `summary` /
                // `isPrivilegeDenial`; the privilege itself is the same
                // datum either way.
                likelyPrivilege: privilege,
                rawDetail: description,
                isPrivilegeDenial: false
            )
        }

        // Generic non-privilege failure.
        let suggestion: String
        if description.lowercased().contains("404") {
            suggestion = "Jamf Pro returned 404 — the device may have been removed from inventory, the endpoint may not exist on this Jamf Pro version, or this command type isn't supported on the device's OS version. Re-run a search to refresh the inventory record."
        } else if description.lowercased().contains("405") || description.lowercased().contains("not allowed") {
            suggestion = "Jamf Pro rejected the request with 405 Method Not Allowed — typically means the endpoint was deprecated or the wrong HTTP verb was used. Check the Jamf Pro API release notes for this command type."
        } else if description.lowercased().contains("management identifier")
            || description.lowercased().contains("missing the management identifier")
        {
            suggestion = "The selected device has no management identifier in Jamf Pro. The device may be unmanaged, unenrolled, or only partially enrolled. Refresh the search results, or have the device re-enrol, then try again."
        } else if let privilege {
            // Generic-failure path that still benefits from naming the
            // expected privilege — the technician can at least confirm
            // the role config before forwarding the raw response.
            suggestion = "The command did not complete. Verify the Jamf Pro API role has the privilege \"\(privilege)\" — and the base \"View MDM command information in Jamf Pro API\" gate. If both are present, capture the raw response below and forward to Jamf Support."
        } else {
            suggestion = "Re-run the command, and if it fails again capture the raw response below for Jamf Support. The CHANGELOG explains exactly which privileges each command needs."
        }

        return SupportActionFailure(
            actionTitle: action.title,
            summary: "The command did not complete. Jamf Pro returned an error.",
            suggestion: suggestion,
            likelyPrivilege: privilege,
            rawDetail: description,
            isPrivilegeDenial: false
        )
    }

    /// Fetches every tenant policy from `/JSSResource/policies`. Lazy —
    /// only runs on first appearance of the Policy frame so technicians
    /// who don't need it never pay the cost.
    func loadAllPolicies() async {
        if isLoadingAllPolicies { return }
        isLoadingAllPolicies = true
        defer { isLoadingAllPolicies = false }
        do {
            let policies = try await apiService.fetchAllPolicies()
            allPolicies = policies
            allPoliciesError = nil
        } catch {
            allPoliciesError = describe(error)
        }
    }

    /// Fetches the device's recent MDM command history from Jamf Pro and
    /// publishes it into `commandHistory`. Called by the Command History
    /// frame on first appear and on Refresh. The frame renders an inline
    /// error banner when `commandHistoryError` is populated.
    func loadCommandHistory() async {
        guard let selectedDetail else { return }
        let detailID = selectedDetail.id
        isLoadingCommandHistory = true
        defer { isLoadingCommandHistory = false }
        do {
            let history = try await apiService.fetchCommandHistory(for: selectedDetail)
            guard self.selectedDetail?.id == detailID else { return }
            commandHistory = history
            commandHistoryError = nil
        } catch {
            guard self.selectedDetail?.id == detailID else { return }
            commandHistoryError = describe(error)
        }
    }

    /// Opens the selected device's native Jamf Pro management page using the
    /// shared API service's URL builder. This is a local navigation helper,
    /// not a new API client or command path.
    func openSelectedDeviceInJamf() async {
        guard let selectedDetail else {
            errorMessage = SupportTechnicianError.missingSelection.errorDescription
            return
        }

        do {
            let url = try await apiService.jamfProDeviceManagementURL(
                inventoryID: selectedDetail.summary.inventoryID,
                assetType: selectedDetail.summary.assetType
            )

            #if canImport(AppKit)
            NSWorkspace.shared.open(url)
            #elseif canImport(UIKit)
            await UIApplication.shared.open(url)
            #endif

            errorMessage = nil
            statusMessage = "Opened Jamf Pro management page for \(selectedDetail.summary.displayName)."
            reportEvent(
                severity: .info,
                category: "navigation",
                message: "Opened Jamf Pro device management page.",
                metadata: [
                    "asset_type": selectedDetail.summary.assetType.rawValue,
                    "inventory_id": selectedDetail.summary.inventoryID,
                    "url": url.absoluteString,
                    "ticket_reference": normalizedTicketReference
                ]
            )
        } catch {
            let description = describe(error)
            errorMessage = "Open in Jamf failed. \(description)"
            statusMessage = nil
            reportError(
                category: "navigation",
                message: "Failed to open Jamf Pro device management page.",
                errorDescription: description,
                metadata: [
                    "asset_type": selectedDetail.summary.assetType.rawValue,
                    "inventory_id": selectedDetail.summary.inventoryID,
                    "ticket_reference": normalizedTicketReference
                ]
            )
        }
    }

    /// Clears the displayed action result, typically called when the user navigates away.
    func clearActionResult() {
        actionResult = nil
    }

    // MARK: - Action Resolution

    /// Determines which management actions are available for a given device detail
    /// based on its asset type and the presence of required identifiers.
    ///
    /// Computers get additional credential-retrieval actions (FileVault, Recovery Lock,
    /// Device Lock PIN, LAPS). Actions requiring a management ID are removed when it
    /// is missing, and LAPS actions require a client management ID.
    nonisolated static func resolvedActions(for detail: SupportDeviceDetail) -> [SupportManagementAction] {
        // Start with actions common to all device types
        var actions: [SupportManagementAction] = [
            .refreshInventory,
            .blankPush,
            .discoverApplications,
            .restartDevice,
            .shutDownDevice,
            .sendDeviceLock,
            .eraseDevice
        ]

        // Add computer-specific credential retrieval and Mac-only actions.
        switch detail.summary.assetType {
        case .computer:
            actions.append(contentsOf: [
                .logOutUser,
                .scheduleOSUpdate,
                .enableBluetooth,
                .disableBluetooth,
                .enableWifi,
                .disableWifi,
                .enableFileVault,
                .redeployManagementFramework,
                .settingsSync,
                .viewFileVaultPersonalRecoveryKey,
                .viewRecoveryLockPassword,
                .viewDeviceLockPIN,
                .viewLAPSAccountPassword,
                .viewJamfManagementAccountPassword,
                .rotateLAPSPassword
            ])
        case .mobileDevice:
            // Clear Passcode is a mobile-only MDM command (iOS/iPadOS); on computers
            // the equivalent is handled by LAPS or the device lock PIN flow.
            actions.append(contentsOf: [
                .clearPasscode,
                .clearRestrictionsPassword,
                .enableLostMode,
                .disableLostMode,
                .playLostModeSound,
                .requestDeviceLocation,
                .refreshCellularPlans,
                .enableBluetooth,
                .disableBluetooth,
                .enableWifi,
                .disableWifi,
                .scheduleOSUpdate
            ])
        }

        // Note: actions are NOT pre-removed when management IDs are missing.
        // Per the redesign spec ("All available commands need to be made
        // available to the user/tech"), every applicable command is rendered
        // and disabled clicks surface a verbose error popup that names the
        // exact missing identifier or privilege. The previous wholesale
        // removal hid commands from technicians who genuinely needed them
        // and couldn't tell why.

        return actions
    }

    // MARK: - Helpers

    /// The ticket reference normalized for diagnostics -- "none" when empty.
    private var normalizedTicketReference: String {
        let trimmed = ticketReference.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "none" : trimmed
    }

    /// Extracts a human-readable error description, preferring `LocalizedError.errorDescription`.
    private func describe(_ error: any Error) -> String {
        (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
    }

    /// Reports an informational or warning diagnostic event to the shared reporter.
    private func reportEvent(
        severity: DiagnosticSeverity,
        category: String,
        message: String,
        metadata: [String: String] = [:]
    ) {
        Task {
            await diagnosticsReporter.report(
                source: moduleSource,
                category: category,
                severity: severity,
                message: message,
                metadata: metadata
            )
        }
    }

    /// Reports an error diagnostic event to the shared reporter.
    private func reportError(
        category: String,
        message: String,
        errorDescription: String,
        metadata: [String: String] = [:]
    ) {
        Task {
            await diagnosticsReporter.reportError(
                source: moduleSource,
                category: category,
                message: message,
                errorDescription: errorDescription,
                metadata: metadata
            )
        }
    }
}

//endofline
