import Combine
import Foundation
import SwiftUI

/// The top-level sections of the Permissions Matrix module UI.
enum PermissionsMatrixSection: String, CaseIterable, Identifiable {
    case commands = "Commands"
    case endpoints = "Endpoints"
    case privileges = "Privileges"
    case runtime = "Runtime Check"

    var id: String { rawValue }

    var systemImage: String {
        switch self {
        case .commands: return "command"
        case .endpoints: return "network"
        case .privileges: return "key.fill"
        case .runtime: return "checkmark.shield"
        }
    }
}

/// Endpoint catalog surface filter.
enum PermissionsMatrixEndpointSurfaceFilter: String, CaseIterable, Identifiable {
    case all = "All"
    case modern = "Modern /api"
    case classic = "Classic /JSSResource"
    var id: String { rawValue }
}

/// Drives the Permissions Matrix module UI. Owns the decoded document, all search
/// and filter state, and the optional runtime comparison. Pure view-model logic —
/// no raw JSON or networking lives here.
@MainActor
final class PermissionsMatrixViewModel: ObservableObject {
    // Loaded data / load state
    @Published private(set) var document: PermissionsMatrixDocument?
    @Published private(set) var loadError: PermissionsMatrixUserFacingError?
    @Published private(set) var isLoading = false

    // Navigation
    @Published var selectedSection: PermissionsMatrixSection = .commands

    // Command explorer state
    @Published var commandSearchText: String = ""
    @Published var selectedActionID: String?
    @Published var moduleFilter: String?
    @Published var deviceFamilyFilter: String?
    @Published var destructiveOnly: Bool = false
    @Published var tenantVerificationOnly: Bool = false

    // Endpoint catalog state
    @Published var endpointSearchText: String = ""
    @Published var endpointSurfaceFilter: PermissionsMatrixEndpointSurfaceFilter = .all
    @Published var endpointTenantVerificationOnly: Bool = false
    @Published var endpointDeprecatedOnly: Bool = false

    // Privilege catalog state
    @Published var privilegeSearchText: String = ""
    @Published var selectedPrivilege: String?

    // Runtime verification state
    @Published private(set) var runtimeState: PermissionsMatrixRuntimeState = .readyToCheck
    @Published private(set) var comparisonResult: PermissionsMatrixComparisonResult?

    // Visual hierarchy (diagram) state — derived from the current selection.
    @Published private(set) var graphSnapshot: PermissionGraphSceneSnapshot?
    @Published var selectedGraphNodeID: String?

    private let sceneBuilder = PermissionGraphSceneBuilder()
    private var graphCancellables = Set<AnyCancellable>()

    private let resourceLoader: PermissionsMatrixResourceLoader
    private let runtimeVerifier: PermissionsMatrixRuntimeVerifier
    private let credentialsStore: JamfCredentialsStore
    private let diagnosticsReporter: any DiagnosticsReporting

    init(
        resourceLoader: PermissionsMatrixResourceLoader,
        runtimeVerifier: PermissionsMatrixRuntimeVerifier,
        credentialsStore: JamfCredentialsStore,
        diagnosticsReporter: any DiagnosticsReporting
    ) {
        self.resourceLoader = resourceLoader
        self.runtimeVerifier = runtimeVerifier
        self.credentialsStore = credentialsStore
        self.diagnosticsReporter = diagnosticsReporter
        self.runtimeState = credentialsStore.hasStoredCredentials ? .readyToCheck : .notAuthenticated

        // Rebuild the visual matrix scene whenever the active selection, section,
        // or runtime comparison changes. `receive(on:)` defers to the next runloop
        // tick so the @Published stored values are settled before we read them.
        Publishers.CombineLatest4($selectedSection, $selectedActionID, $selectedPrivilege, $comparisonResult)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.rebuildGraphScene() }
            .store(in: &graphCancellables)
    }

    var hasCredentials: Bool { credentialsStore.hasStoredCredentials }

    // MARK: - Loading

    func load() async {
        // Idempotent: don't reload if we already have data.
        guard document == nil, isLoading == false else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            let loaded = try await resourceLoader.loadMatrix()
            document = loaded
            loadError = nil
            rebuildGraphScene()
        } catch let error as PermissionsMatrixLoadError {
            switch error {
            case .resourceNotFound(let name):
                loadError = PermissionsMatrixDiagnosticsPresenter.resourceNotFound(resourceName: name)
            case .decodeFailed(let underlying):
                loadError = PermissionsMatrixDiagnosticsPresenter.decodeFailure(
                    resourceName: PermissionsMatrixResourceLoader.resourceName,
                    underlying: underlying
                )
            }
        } catch {
            loadError = PermissionsMatrixDiagnosticsPresenter.decodeFailure(
                resourceName: PermissionsMatrixResourceLoader.resourceName,
                underlying: error.localizedDescription
            )
        }
    }

    // MARK: - Visual matrix

    /// Rebuilds `graphSnapshot` from the active selection. Cheap and
    /// presentation-only — it reads matrix records and the comparison result but
    /// mutates nothing. The panel fits the camera when `selectedItemID` changes.
    func rebuildGraphScene() {
        switch selectedSection {
        case .commands, .runtime:
            if let action = selectedAction {
                graphSnapshot = sceneBuilder.snapshot(for: action, overlays: mdmOverlays, comparison: comparisonResult)
            } else {
                graphSnapshot = nil
            }
        case .privileges:
            if let privilege = selectedPrivilege {
                graphSnapshot = sceneBuilder.snapshot(
                    forPrivilege: privilege,
                    actions: actions(requiring: privilege),
                    endpoints: endpoints(requiring: privilege),
                    comparison: comparisonResult
                )
            } else {
                graphSnapshot = nil
            }
        case .endpoints:
            graphSnapshot = nil
        }
        selectedGraphNodeID = nil
    }

    /// Reports (once) that the Metal visual layer was unavailable and the
    /// accessible fallback is being shown, through the shared diagnostics path.
    func reportVisualMatrixUnavailable() {
        Task {
            await diagnosticsReporter.report(
                source: PermissionsMatrixDiagnostics.source,
                category: PermissionsMatrixDiagnostics.Category.visualMatrix,
                severity: .warning,
                message: "Visual matrix renderer unavailable; showing accessible fallback.",
                metadata: ["reason": "metal_unavailable"]
            )
        }
    }

    // MARK: - Derived metadata

    var verificationSummary: VerificationSummary? { document?.verificationSummary }

    var uncoveredSourceEndpointCount: Int {
        document?.sourceCoverage?.uncoveredSourceEndpointCount
            ?? document?.verificationSummary?.uncoveredSourceEndpoints
            ?? 0
    }

    // MARK: - Command explorer

    var availableModules: [String] {
        guard let document else { return [] }
        return Set(document.actions.compactMap { $0.module }).sorted()
    }

    var availableDeviceFamilies: [String] {
        guard let document else { return [] }
        return Set(document.actions.compactMap { $0.assetScope }).sorted()
    }

    var filteredActions: [PermissionsMatrixAction] {
        guard let document else { return [] }
        return document.actions.filter { action in
            PermissionsMatrixActionFilter.matches(
                action,
                query: commandSearchText,
                module: moduleFilter,
                deviceFamily: deviceFamilyFilter,
                destructiveOnly: destructiveOnly,
                tenantVerificationOnly: tenantVerificationOnly
            )
        }
        .sorted { $0.resolvedDisplayName.localizedCaseInsensitiveCompare($1.resolvedDisplayName) == .orderedAscending }
    }

    var selectedAction: PermissionsMatrixAction? {
        guard let selectedActionID else { return nil }
        return document?.actions.first { $0.commandID == selectedActionID }
    }

    func deviceFamilyLabel(_ assetScope: String) -> String {
        PermissionsMatrixAction.deviceFamilyLabel(for: assetScope)
    }

    // MARK: - Endpoint catalog

    var allCatalogEntries: [EndpointPrivilegeEntry] {
        guard let document else { return [] }
        return document.endpointCatalog.modernJamfProAPI + document.endpointCatalog.classicAPI
    }

    var filteredEndpoints: [EndpointPrivilegeEntry] {
        let query = endpointSearchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return allCatalogEntries.filter { entry in
            switch endpointSurfaceFilter {
            case .all: break
            case .modern: if entry.isClassic { return false }
            case .classic: if entry.isClassic == false { return false }
            }
            if endpointTenantVerificationOnly, entry.needsTenantVerification == false { return false }
            if endpointDeprecatedOnly, entry.deprecationNote == nil { return false }
            guard query.isEmpty == false else { return true }
            return endpointMatches(entry, query: query)
        }
    }

    private func endpointMatches(_ entry: EndpointPrivilegeEntry, query: String) -> Bool {
        if entry.method.lowercased().contains(query) { return true }
        if entry.path.lowercased().contains(query) { return true }
        if let family = entry.family?.lowercased(), family.contains(query) { return true }
        if let purpose = entry.purpose?.lowercased(), purpose.contains(query) { return true }
        if entry.requiredPrivileges.contains(where: { $0.lowercased().contains(query) }) { return true }
        return false
    }

    var mdmOverlays: [MDMCommandOverlay] {
        document?.endpointCatalog.mdmCommandTypeOverlays ?? []
    }

    // MARK: - Privilege catalog

    var filteredPrivileges: [String] {
        guard let document else { return [] }
        let query = privilegeSearchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard query.isEmpty == false else { return document.privileges }
        return document.privileges.filter { $0.lowercased().contains(query) }
    }

    func actions(requiring privilege: String) -> [PermissionsMatrixAction] {
        guard let document else { return [] }
        return document.actions.filter { $0.allPrivilegeNames.contains(privilege) }
    }

    func endpoints(requiring privilege: String) -> [EndpointPrivilegeEntry] {
        allCatalogEntries.filter { $0.requiredPrivileges.contains(privilege) }
    }

    // MARK: - Runtime verification

    func runComparison() async {
        guard let action = selectedAction else {
            runtimeState = .comparisonUnavailable
            return
        }
        guard hasCredentials else {
            runtimeState = .notAuthenticated
            comparisonResult = .notAuthenticated()
            return
        }
        runtimeState = .checkingAuth
        await diagnosticsReporter.report(
            source: PermissionsMatrixDiagnostics.source,
            category: PermissionsMatrixDiagnostics.Category.uiAction,
            severity: .info,
            message: "Started runtime privilege comparison.",
            metadata: ["action_id": action.commandID]
        )
        let result = await runtimeVerifier.compare(action: action, hasCredentials: hasCredentials)
        comparisonResult = result
        runtimeState = result.state
    }

    func refreshAuthenticationState() {
        credentialsStore.refreshState()
        if hasCredentials == false {
            runtimeState = .notAuthenticated
        } else if runtimeState == .notAuthenticated {
            runtimeState = .readyToCheck
        }
    }

    // MARK: - Copy helpers

    func copyRequiredPrivileges(for action: PermissionsMatrixAction) {
        let names = action.allPrivilegeNames
        DashboardClipboard.copy(names.joined(separator: "\n"))
        reportUIAction("copy_privileges", metadata: ["action_id": action.commandID, "count": String(names.count)])
    }

    func copyEndpointList(for action: PermissionsMatrixAction) {
        let lines = action.endpoints.map { "\($0.method) \($0.path)" }
        DashboardClipboard.copy(lines.joined(separator: "\n"))
        reportUIAction("copy_endpoints", metadata: ["action_id": action.commandID, "count": String(lines.count)])
    }

    func copyPrivilegeName(_ name: String) {
        DashboardClipboard.copy(name)
        reportUIAction("copy_privilege_name", metadata: ["privilege": name])
    }

    func copyAllPrivileges(for privilege: String) {
        // Copy the privilege plus every action's privilege bundle that includes it.
        DashboardClipboard.copy(privilege)
        reportUIAction("copy_privilege_name", metadata: ["privilege": privilege])
    }

    private func reportUIAction(_ action: String, metadata: [String: String]) {
        var merged = metadata
        merged["ui_action"] = action
        Task {
            await diagnosticsReporter.report(
                source: PermissionsMatrixDiagnostics.source,
                category: PermissionsMatrixDiagnostics.Category.uiAction,
                severity: .info,
                message: "Permissions Matrix UI action: \(action).",
                metadata: merged
            )
        }
    }
}

//endofline
