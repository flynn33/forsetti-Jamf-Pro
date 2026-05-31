import Foundation
import Combine


@MainActor
/// Drives all state and business logic for the Prestage Director view.
///
/// Owns the list of prestage profiles, the devices scoped to the selected prestage,
/// device selection tracking, serial number search (local filter and cross-prestage
/// global search), and the move/remove scope mutation workflows including progress
/// reporting and rollback handling.
final class PrestageDirectorViewModel: ObservableObject {
    /// All prestage profiles loaded from the Jamf Pro server, sorted alphabetically.
    @Published private(set) var prestages: [PrestageSummary] = []

    /// The ID of the currently selected prestage in the picker.
    @Published var selectedPrestageID: String?

    /// Devices assigned to the currently selected prestage.
    @Published private(set) var scopedDevices: [PrestageAssignedDevice] = []

    /// Devices discovered by the cross-prestage global serial search.
    @Published private(set) var globalSearchDevices: [PrestageAssignedDevice] = []

    /// The user's serial number search query, bound to the search bar.
    @Published var deviceSerialSearchText = ""

    /// The set of device selection keys for devices the user has checked.
    @Published var selectedDeviceKeys: Set<String> = []

    /// Whether the prestage list is currently being fetched.
    @Published private(set) var isLoadingPrestages = false

    /// Whether the scoped device list for the selected prestage is loading.
    @Published private(set) var isLoadingScopedDevices = false

    /// Whether a global cross-prestage serial search is in progress.
    @Published private(set) var isSearchingAcrossPrestages = false

    /// Whether a scope mutation (move or remove) is currently being applied.
    @Published private(set) var isApplyingChanges = false

    /// Controls presentation of the move-destination picker sheet.
    @Published var isMoveDestinationPresented = false

    /// Progress state for long-running operations, displayed as a determinate progress bar.
    @Published private(set) var operationProgress: PrestageDirectorOperationProgress?

    /// A short informational message shown below the prestage picker.
    @Published var statusMessage: String?

    /// An error message shown in the error banner section.
    @Published var errorMessage: String?

    /// The Jamf Pro API gateway used for all network requests.
    private let apiGateway: JamfAPIGateway

    /// The diagnostics reporter for audit-trail and telemetry events.
    private let diagnosticsReporter: any DiagnosticsReporting

    /// The module source identifier included in all diagnostics events.
    private let moduleSource = "module.prestage-director"

    /// The currently running global search task, cancelled when the query changes.
    private var globalSearchTask: Task<Void, Never>?

    /// Creates a new view model wired to the given API gateway and diagnostics reporter.
    ///
    /// - Parameters:
    ///   - apiGateway: The shared Jamf Pro API gateway for network requests.
    ///   - diagnosticsReporter: The shared diagnostics reporter for audit events.
    init(
        apiGateway: JamfAPIGateway,
        diagnosticsReporter: any DiagnosticsReporting
    ) {
        self.apiGateway = apiGateway
        self.diagnosticsReporter = diagnosticsReporter
    }

    deinit {
        // Cancel any in-flight global search when the view model is deallocated
        globalSearchTask?.cancel()
    }

    /// The number of unique serial numbers currently selected for action.
    var selectedCount: Int {
        selectedSerialNumbers.count
    }

    /// Whether the UI is currently displaying cross-pre-stage (global search)
    /// results because the current scope has no matches for the search query.
    ///
    /// Returns `true` only when all of these hold: a query is present, the
    /// current scope has no local matches, and `globalSearchDevices` has
    /// results. Used by the row view to decide whether to show the source
    /// pre-stage badge; selection and bulk actions remain enabled because
    /// the move/remove flows are multi-source-aware.
    ///
    /// A non-empty query alone does NOT activate global mode — if the current
    /// scope contains the searched serial, the user stays in local-filter mode.
    var isGlobalSearchActive: Bool {
        guard normalizedSerialQuery(deviceSerialSearchText) != nil else {
            return false
        }
        return localFilterMatches.isEmpty && globalSearchDevices.isEmpty == false
    }

    /// Whether every visible device in the current list is selected.
    var allDevicesSelected: Bool {
        let visibleDeviceKeys = Set(visibleScopedDevices.map(\.selectionKey))
        guard visibleDeviceKeys.isEmpty == false else {
            return false
        }

        return visibleDeviceKeys.isSubset(of: selectedDeviceKeys)
    }

    /// Whether the remove button should be enabled -- requires a selection and no
    /// in-progress mutation.
    var canRemoveSelection: Bool {
        selectedSerialNumbers.isEmpty == false &&
            isApplyingChanges == false
    }

    /// Whether the move button should be enabled -- requires a selection, at least one
    /// available destination, and no in-progress mutation.
    var canMoveSelection: Bool {
        selectedSerialNumbers.isEmpty == false &&
            moveDestinationPrestages.isEmpty == false &&
            isApplyingChanges == false
    }

    /// All prestages except the currently selected one, available as move destinations.
    var moveDestinationPrestages: [PrestageSummary] {
        prestages.filter { $0.id != selectedPrestageID }
    }

    /// The device list shown in the UI.
    ///
    /// Priority order:
    /// 1. No query -- return the full current-scope list.
    /// 2. Query with matches in the current scope -- return `localFilterMatches`
    ///    (the user is filtering within the selected pre-stage).
    /// 3. Query with no local matches -- return `globalSearchDevices`
    ///    (cross-pre-stage results; each row carries its source pre-stage name
    ///    via `PrestageAssignedDevice.prestageName` so the row view can label
    ///    the assignment, and selection remains enabled for cross-scope moves).
    var filteredScopedDevices: [PrestageAssignedDevice] {
        guard normalizedSerialQuery(deviceSerialSearchText) != nil else {
            return scopedDevices
        }

        let local = localFilterMatches
        if local.isEmpty == false {
            return local
        }

        return globalSearchDevices
    }

    /// Devices in the currently selected pre-stage whose serial matches the
    /// current search query. Returns the full `scopedDevices` list when the
    /// query is empty.
    private var localFilterMatches: [PrestageAssignedDevice] {
        guard let normalizedQuery = normalizedSerialQuery(deviceSerialSearchText) else {
            return scopedDevices
        }

        return scopedDevices.filter { device in
            guard let serial = device.normalizedSerialNumber else {
                return false
            }
            return serial.contains(normalizedQuery)
        }
    }

    // MARK: - Public Actions

    /// Loads the initial module state by refreshing the prestage list.
    func loadInitialState() async {
        await refreshPrestages()
    }

    /// Responds to changes in the device serial search text.
    ///
    /// Cancels any previous global search task. If the query normalizes to a
    /// valid serial fragment, starts a new global search across all prestages.
    /// Otherwise, resets global search state and prunes stale selections.
    func handleDeviceSearchTextChanged() {
        globalSearchTask?.cancel()

        guard let normalizedQuery = normalizedSerialQuery(deviceSerialSearchText) else {
            // No valid query -- exit search mode entirely
            isSearchingAcrossPrestages = false
            globalSearchDevices = []
            // Prune selections to only include devices still in the scope
            selectedDeviceKeys.formIntersection(Set(scopedDevices.map(\.selectionKey)))
            return
        }

        // If the current scope already has matches, stay in local-filter mode.
        // Selection is enabled, and we skip the expensive cross-pre-stage fan-out.
        if localFilterMatches.isEmpty == false {
            isSearchingAcrossPrestages = false
            globalSearchDevices = []
            return
        }

        // No local match -- fall back to searching across every pre-stage
        let querySnapshot = normalizedQuery
        globalSearchTask = Task { [weak self] in
            guard let self else {
                return
            }

            await self.searchAcrossAllPrestages(normalizedSerialQuery: querySnapshot)
        }
    }

    /// Fetches the full prestage list from Jamf Pro, preserving the current selection
    /// if the previously selected prestage still exists.
    func refreshPrestages() async {
        let previousSelection = selectedPrestageID
        isLoadingPrestages = true
        defer { isLoadingPrestages = false }

        do {
            let fetchedPrestages = try await fetchAllPrestages()
            // Sort alphabetically by name for consistent picker ordering
            prestages = fetchedPrestages.sorted {
                $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
            }

            if prestages.isEmpty {
                // Clean up all state when no prestages exist
                globalSearchTask?.cancel()
                selectedPrestageID = nil
                scopedDevices = []
                globalSearchDevices = []
                selectedDeviceKeys = []
                isSearchingAcrossPrestages = false
                statusMessage = "No pre-stages returned by the Jamf Pro server."
                errorMessage = nil

                reportEvent(
                    severity: .warning,
                    category: "prestages",
                    message: "No pre-stages were returned by the server."
                )
                return
            }

            // Restore previous selection if it still exists, otherwise default to first
            if let previousSelection,
               prestages.contains(where: { $0.id == previousSelection })
            {
                selectedPrestageID = previousSelection
            } else {
                selectedPrestageID = prestages.first?.id
            }

            statusMessage = "Loaded \(prestages.count) pre-stage profiles."
            errorMessage = nil
            reportEvent(
                severity: .info,
                category: "prestages",
                message: "Loaded pre-stage profile list.",
                metadata: [
                    "prestage_count": String(prestages.count)
                ]
            )

            await loadDevicesForSelectedPrestage()
            handleDeviceSearchTextChanged()
        } catch {
            // Cancel any in-flight global search so its results can't land after
            // the failed refresh and leave the UI selecting devices that are no
            // longer visible. Reset the spinner flag too for the same reason.
            globalSearchTask?.cancel()
            globalSearchTask = nil
            isSearchingAcrossPrestages = false

            let description = describe(error)
            errorMessage = "Failed to load pre-stages. \(description)"
            statusMessage = nil
            reportError(
                category: "prestages",
                message: "Failed loading pre-stage profile list.",
                errorDescription: description
            )
        }
    }

    /// Loads the device scope for the currently selected prestage.
    ///
    /// Guards against stale responses by comparing the prestage ID at request time
    /// with the current selection when the response arrives.
    func loadDevicesForSelectedPrestage() async {
        guard let selectedPrestageID, selectedPrestageID.isEmpty == false else {
            // No prestage selected -- reset device state
            globalSearchTask?.cancel()
            scopedDevices = []
            globalSearchDevices = []
            selectedDeviceKeys = []
            isSearchingAcrossPrestages = false
            return
        }

        let requestedPrestageID = selectedPrestageID
        isLoadingScopedDevices = true
        defer { isLoadingScopedDevices = false }

        do {
            let devices = try await fetchScopedDevices(for: requestedPrestageID)
            // Discard if the user switched prestages while loading
            guard selectedPrestageID == requestedPrestageID else {
                return
            }

            scopedDevices = devices
            // Prune selections to only include devices still in the scope
            selectedDeviceKeys.formIntersection(Set(scopedDevices.map(\.selectionKey)))
            errorMessage = nil
            statusMessage = "Loaded \(scopedDevices.count) assigned devices."

            reportEvent(
                severity: .info,
                category: "scope",
                message: "Loaded pre-stage scope assignments.",
                metadata: [
                    "prestage_id": requestedPrestageID,
                    "device_count": String(scopedDevices.count)
                ]
            )

            // Re-evaluate the search against the newly loaded scope so the
            // filter mode (local vs. cross-pre-stage) is recomputed correctly.
            // `isGlobalSearchActive` now means "cross-scope results are showing"
            // and would miss the local-filter case here.
            if normalizedSerialQuery(deviceSerialSearchText) != nil {
                handleDeviceSearchTextChanged()
            }
        } catch {
            guard selectedPrestageID == requestedPrestageID else {
                return
            }

            let description = describe(error)
            errorMessage = "Failed to load assigned devices. \(description)"
            statusMessage = nil
            scopedDevices = []
            selectedDeviceKeys = []

            reportError(
                category: "scope",
                message: "Failed loading pre-stage scope assignments.",
                errorDescription: description,
                metadata: [
                    "prestage_id": requestedPrestageID
                ]
            )
        }
    }

    /// Searches for a serial number across every prestage by fetching each scope
    /// individually and filtering for matches.
    ///
    /// Results are deduplicated and sorted by device name. If every prestage fails,
    /// an error message is shown; partial failures are silently logged.
    private func searchAcrossAllPrestages(normalizedSerialQuery: String) async {
        guard prestages.isEmpty == false else {
            globalSearchDevices = []
            return
        }

        isSearchingAcrossPrestages = true
        defer { isSearchingAcrossPrestages = false }

        var matches: [PrestageAssignedDevice] = []
        var failedPrestageCount = 0

        for prestage in prestages {
            // Bail early if the user changed the search query
            if Task.isCancelled {
                return
            }

            do {
                let scoped = try await fetchScopedDevices(for: prestage.id)
                let prestageMatches = scoped.filter { device in
                    guard let serial = device.normalizedSerialNumber else {
                        return false
                    }

                    return serial.contains(normalizedSerialQuery)
                }

                matches.append(contentsOf: prestageMatches)
            } catch {
                failedPrestageCount += 1
                let description = describe(error)
                await diagnosticsReporter.reportError(
                    source: moduleSource,
                    category: "scope-search",
                    message: "Failed searching a pre-stage scope.",
                    errorDescription: description,
                    metadata: [
                        "prestage_id": prestage.id
                    ]
                )
            }
        }

        if Task.isCancelled {
            return
        }

        // Deduplicate and sort by device name, then serial as tiebreaker
        let dedupedMatches = dedupeDevices(matches).sorted {
            let lhsName = $0.deviceName.localizedLowercase
            let rhsName = $1.deviceName.localizedLowercase
            if lhsName == rhsName {
                return $0.serialNumber.localizedLowercase < $1.serialNumber.localizedLowercase
            }
            return lhsName < rhsName
        }

        globalSearchDevices = dedupedMatches
        // Preserve any local selections the user made before typing -- they
        // remain valid (scope hasn't changed) and restore when the search is
        // cleared. Cross-pre-stage results are selectable too; each carries its
        // source `prestageID` so move/remove can dispatch to the right API.

        if failedPrestageCount == prestages.count {
            errorMessage = "Failed searching pre-stage scope assignments."
            statusMessage = nil
            return
        }

        errorMessage = nil
        statusMessage = "Found \(dedupedMatches.count) matching devices across \(prestages.count) pre-stage profiles."
    }

    /// Toggles selection state for a single device.
    ///
    /// - Parameter device: The device whose selection state should be toggled.
    func toggleSelection(for device: PrestageAssignedDevice) {
        let selectionKey = device.selectionKey
        guard selectedDeviceKeys.contains(selectionKey) == false else {
            selectedDeviceKeys.remove(selectionKey)
            return
        }

        selectedDeviceKeys.insert(selectionKey)
    }

    /// Toggles between selecting all visible devices and clearing the selection.
    func toggleSelectAll() {
        let visibleSelectionKeys = Set(visibleScopedDevices.map(\.selectionKey))
        guard visibleSelectionKeys.isEmpty == false else {
            return
        }

        if allDevicesSelected {
            selectedDeviceKeys.subtract(visibleSelectionKeys)
            return
        }

        selectedDeviceKeys.formUnion(visibleSelectionKeys)
    }

    /// Presents the move destination picker sheet after validating preconditions.
    func presentMoveDestinationPicker() {
        guard selectedSerialNumbers.isEmpty == false else {
            errorMessage = "Select one or more devices before moving."
            return
        }

        guard moveDestinationPrestages.isEmpty == false else {
            errorMessage = "No destination pre-stage is available."
            return
        }

        isMoveDestinationPresented = true
    }

    /// Removes the selected devices from their respective pre-stage profiles.
    ///
    /// Selections may span multiple pre-stages when the user has added devices
    /// from cross-pre-stage search results. Each source is handled in a separate
    /// mutation; a mid-sequence failure surfaces partial success in the error
    /// banner so the user knows what still needs attention.
    func confirmRemoval() async {
        let grouped = selectedSerialsGroupedBySource
        guard grouped.isEmpty == false else {
            errorMessage = "No valid serial numbers were selected."
            return
        }

        let allSerials = grouped.values.flatMap { $0 }
        let totalDeviceCount = Set(allSerials).count
        guard totalDeviceCount > 0 else {
            errorMessage = "No valid serial numbers were selected."
            return
        }

        isApplyingChanges = true
        defer { isApplyingChanges = false }

        let sourceIDs = Array(grouped.keys).sorted()
        let sourceDescription = describeSources(sourceIDs)
        setOperationProgress(
            title: "Remove in progress",
            detail: "Removing selected devices from \(sourceDescription)...",
            fractionCompleted: 0.35
        )

        var removedCount = 0
        var firstFailure: (sourceID: String, error: String)?

        for sourceID in sourceIDs {
            guard let serials = grouped[sourceID], serials.isEmpty == false else {
                continue
            }

            do {
                try await applyScopeMutation(
                    .remove,
                    prestageID: sourceID,
                    serialNumbers: serials
                )
                removedCount += serials.count
            } catch {
                firstFailure = (sourceID: sourceID, error: describe(error))
                break
            }
        }

        if let failure = firstFailure {
            clearOperationProgress()
            let sourceLabel = describeSources([failure.sourceID])
            if removedCount > 0 {
                errorMessage = "Removed \(removedCount) of \(totalDeviceCount) devices. Remove from \(sourceLabel) failed: \(failure.error)"
            } else {
                errorMessage = "Device removal failed. \(failure.error)"
            }
            statusMessage = nil

            reportError(
                category: "scope",
                message: "Failed removing devices from pre-stage.",
                errorDescription: failure.error,
                metadata: [
                    "prestage_ids": sourceIDs.joined(separator: ","),
                    "failed_prestage_id": failure.sourceID,
                    "device_count": String(totalDeviceCount),
                    "removed_count": String(removedCount)
                ]
            )

            // Still refresh the viewed pre-stage so any devices that were removed
            // before the failure disappear from the list.
            await loadDevicesForSelectedPrestage()
            return
        }

        setOperationProgress(
            title: "Remove in progress",
            detail: "Refreshing pre-stage assignments...",
            fractionCompleted: 0.80
        )
        selectedDeviceKeys.removeAll()
        errorMessage = nil
        statusMessage = "Removed \(totalDeviceCount) selected devices from their pre-stage profiles."

        reportEvent(
            severity: .warning,
            category: "scope",
            message: "Removed selected devices from a pre-stage.",
            metadata: [
                "prestage_ids": sourceIDs.joined(separator: ","),
                "device_count": String(totalDeviceCount)
            ]
        )

        await loadDevicesForSelectedPrestage()
        setOperationProgress(
            title: "Remove complete",
            detail: "Finished removing selected devices.",
            fractionCompleted: 1.0
        )
    }

    /// Moves the selected devices to a destination prestage.
    ///
    /// Selections may span multiple source pre-stages when the user has added
    /// devices from cross-pre-stage search results. The mutation runs in two
    /// phases: first remove from each source pre-stage, then add the full set
    /// to the destination. If the add phase fails after any successful remove,
    /// each already-removed group is re-added to its original source as a
    /// best-effort rollback.
    ///
    /// - Parameter destination: The prestage to move the selected devices into.
    func moveSelection(to destination: PrestageSummary) async {
        let grouped = selectedSerialsGroupedBySource
        guard grouped.isEmpty == false else {
            errorMessage = "No valid serial numbers were selected."
            return
        }

        let allSerials = grouped.values.flatMap { $0 }
        let deduplicatedSerials = Array(Set(allSerials)).sorted()
        guard deduplicatedSerials.isEmpty == false else {
            errorMessage = "No valid serial numbers were selected."
            return
        }

        guard grouped.keys.contains(destination.id) == false else {
            errorMessage = "Choose a different destination pre-stage."
            return
        }

        isApplyingChanges = true
        defer { isApplyingChanges = false }

        let sourceIDs = Array(grouped.keys).sorted()
        let sourceDescription = describeSources(sourceIDs)
        setOperationProgress(
            title: "Move in progress",
            detail: "Removing selected devices from \(sourceDescription)...",
            fractionCompleted: 0.20
        )

        var removedGroups: [(sourceID: String, serialNumbers: [String])] = []

        do {
            // Phase 1: Remove from each source pre-stage
            for sourceID in sourceIDs {
                guard let serials = grouped[sourceID], serials.isEmpty == false else {
                    continue
                }

                try await applyScopeMutation(
                    .remove,
                    prestageID: sourceID,
                    serialNumbers: serials
                )
                removedGroups.append((sourceID: sourceID, serialNumbers: serials))
            }

            // Phase 2: Add the full set to the destination pre-stage
            setOperationProgress(
                title: "Move in progress",
                detail: "Adding selected devices to \(destination.name)...",
                fractionCompleted: 0.55
            )
            try await applyScopeMutation(
                .add,
                prestageID: destination.id,
                serialNumbers: deduplicatedSerials
            )

            setOperationProgress(
                title: "Move in progress",
                detail: "Refreshing pre-stage assignments...",
                fractionCompleted: 0.85
            )
            selectedDeviceKeys.removeAll()
            errorMessage = nil
            statusMessage = "Moved \(deduplicatedSerials.count) devices to \(destination.name)."

            reportEvent(
                severity: .warning,
                category: "scope",
                message: "Moved selected devices between pre-stages.",
                metadata: [
                    "source_prestage_ids": sourceIDs.joined(separator: ","),
                    "destination_prestage_id": destination.id,
                    "device_count": String(deduplicatedSerials.count)
                ]
            )

            await loadDevicesForSelectedPrestage()
            setOperationProgress(
                title: "Move complete",
                detail: "Finished moving selected devices to \(destination.name).",
                fractionCompleted: 1.0
            )
        } catch {
            let description = describe(error)
            var rollbackDescription: String?

            // Attempt rollback for each group that was already removed from its source
            if removedGroups.isEmpty == false {
                setOperationProgress(
                    title: "Move in progress",
                    detail: "Move failed. Attempting rollback...",
                    fractionCompleted: 0.92
                )

                var rolledBackIDs: [String] = []
                var failedRollbacks: [(sourceID: String, error: String)] = []
                for group in removedGroups {
                    do {
                        try await applyScopeMutation(
                            .add,
                            prestageID: group.sourceID,
                            serialNumbers: group.serialNumbers
                        )
                        rolledBackIDs.append(group.sourceID)
                    } catch {
                        failedRollbacks.append((sourceID: group.sourceID, error: describe(error)))
                    }
                }

                if failedRollbacks.isEmpty {
                    rollbackDescription = "Rollback succeeded and restored the original assignments."
                } else {
                    let failedList = failedRollbacks
                        .map { "\(describeSources([$0.sourceID])): \($0.error)" }
                        .joined(separator: "; ")
                    rollbackDescription = "Rollback partially failed (\(failedList))."
                }
            }

            clearOperationProgress()
            if let rollbackDescription {
                errorMessage = "Move failed. \(description) \(rollbackDescription)"
            } else {
                errorMessage = "Move failed. \(description)"
            }
            statusMessage = nil

            reportError(
                category: "scope",
                message: "Failed moving devices between pre-stages.",
                errorDescription: description,
                metadata: [
                    "source_prestage_ids": sourceIDs.joined(separator: ","),
                    "destination_prestage_id": destination.id,
                    "device_count": String(deduplicatedSerials.count),
                    "rollback_result": rollbackDescription ?? "not_attempted"
                ]
            )
        }
    }

    // MARK: - Derived State

    /// All devices the user could act on, across the currently-viewed scope and any
    /// cross-pre-stage global search results. Current-scope entries win on key
    /// collision so local selection metadata stays authoritative.
    private var allSelectableDevices: [PrestageAssignedDevice] {
        var devicesByKey: [String: PrestageAssignedDevice] = [:]
        for device in globalSearchDevices {
            devicesByKey[device.selectionKey] = device
        }
        for device in scopedDevices {
            devicesByKey[device.selectionKey] = device
        }
        return Array(devicesByKey.values)
    }

    /// The concrete `PrestageAssignedDevice` records the user has checked, resolved
    /// against both local scope and global-search results.
    private var selectedDevices: [PrestageAssignedDevice] {
        allSelectableDevices.filter { selectedDeviceKeys.contains($0.selectionKey) }
    }

    /// The sorted, deduplicated list of normalized serial numbers for all selected devices.
    private var selectedSerialNumbers: [String] {
        let values = selectedDevices.compactMap(\.normalizedSerialNumber)
        return Array(Set(values)).sorted()
    }

    /// Selected serial numbers grouped by their source pre-stage ID. Devices whose
    /// `prestageID` is nil (legacy fallback parser records) are attributed to the
    /// currently-viewed pre-stage. Devices with neither are dropped.
    private var selectedSerialsGroupedBySource: [String: [String]] {
        var grouped: [String: [String]] = [:]
        for device in selectedDevices {
            guard let serial = device.normalizedSerialNumber else {
                continue
            }

            guard let sourceID = device.prestageID ?? selectedPrestageID else {
                continue
            }

            if grouped[sourceID]?.contains(serial) == true {
                continue
            }

            grouped[sourceID, default: []].append(serial)
        }

        for (key, serials) in grouped {
            grouped[key] = serials.sorted()
        }
        return grouped
    }

    /// The display name of the currently selected prestage, used in status messages.
    private var selectedPrestageName: String? {
        guard let selectedPrestageID else {
            return nil
        }

        return prestages.first(where: { $0.id == selectedPrestageID })?.name
    }

    /// Builds a human-readable phrase describing the given source pre-stage IDs.
    /// Used in progress detail strings and error messages when an operation spans
    /// one or many source pre-stages.
    private func describeSources(_ sourceIDs: [String]) -> String {
        let names: [String] = sourceIDs.map { id in
            prestages.first(where: { $0.id == id })?.name ?? id
        }

        switch names.count {
        case 0:
            return "the selected pre-stage"
        case 1:
            return names[0]
        case 2:
            return "\(names[0]) and \(names[1])"
        default:
            let head = names.dropLast().joined(separator: ", ")
            let tail = names.last ?? ""
            return "\(head), and \(tail)"
        }
    }

    // MARK: - Progress Helpers

    /// Updates the operation progress bar with a title, detail message, and fraction.
    /// Clamps the fraction to the [0, 1] range.
    private func setOperationProgress(
        title: String,
        detail: String,
        fractionCompleted: Double
    ) {
        let normalizedFraction = max(0, min(1, fractionCompleted))
        operationProgress = PrestageDirectorOperationProgress(
            title: title,
            detail: detail,
            fractionCompleted: normalizedFraction
        )
    }

    /// Dismisses the operation progress bar.
    private func clearOperationProgress() {
        operationProgress = nil
    }

    // MARK: - API Fetching

    /// Fetches all mobile device prestage profiles from the Jamf Pro API, paginating
    /// through results until no more pages are available.
    ///
    /// - Returns: An array of `PrestageSummary` values, deduplicated by ID.
    private func fetchAllPrestages() async throws -> [PrestageSummary] {
        var page = 0
        let pageSize = 200
        var aggregated: [PrestageSummary] = []
        var seenPrestageIDs = Set<String>()

        while true {
            let data = try await apiGateway.request(
                path: "api/v2/mobile-device-prestages",
                method: .get,
                queryItems: [
                    URLQueryItem(name: "page", value: String(page)),
                    URLQueryItem(name: "page-size", value: String(pageSize))
                ]
            )

            let pagePrestages = parsePrestageSummaries(from: data)
            // Track IDs to avoid duplicates across pages
            let newPrestages = pagePrestages.filter { seenPrestageIDs.insert($0.id).inserted }
            aggregated.append(contentsOf: newPrestages)

            // Stop if the page was empty, under-full, or entirely duplicates
            if pagePrestages.isEmpty || pagePrestages.count < pageSize || newPrestages.isEmpty {
                break
            }

            page += 1
            // Safety valve to prevent infinite pagination
            if page > 200 {
                break
            }
        }

        return dedupePrestages(aggregated)
    }

    /// Fetches devices scoped to a specific prestage, paginating through results.
    ///
    /// - Parameter prestageID: The Jamf Pro prestage identifier.
    /// - Returns: A deduplicated, alphabetically sorted array of assigned devices.
    private func fetchScopedDevices(for prestageID: String) async throws -> [PrestageAssignedDevice] {
        var page = 0
        let pageSize = 500
        var aggregated: [PrestageAssignedDevice] = []
        var seenSelectionKeys = Set<String>()
        // Resolve the owning pre-stage's display name once so every parsed device
        // carries accurate source context for cross-scope UI and move/remove grouping.
        let prestageName = prestages.first(where: { $0.id == prestageID })?.name

        while true {
            let data = try await apiGateway.request(
                path: "api/v2/mobile-device-prestages/\(prestageID)/scope",
                method: .get,
                queryItems: [
                    URLQueryItem(name: "page", value: String(page)),
                    URLQueryItem(name: "page-size", value: String(pageSize))
                ]
            )

            let pageDevices = parseScopedDevices(from: data, prestageID: prestageID, prestageName: prestageName)
            let newDevices = pageDevices.filter { seenSelectionKeys.insert($0.selectionKey).inserted }
            aggregated.append(contentsOf: newDevices)

            if pageDevices.isEmpty || pageDevices.count < pageSize || newDevices.isEmpty {
                break
            }

            page += 1
            if page > 400 {
                break
            }
        }

        return dedupeDevices(aggregated).sorted {
            let lhsName = $0.deviceName.localizedLowercase
            let rhsName = $1.deviceName.localizedLowercase
            if lhsName == rhsName {
                return $0.serialNumber.localizedLowercase < $1.serialNumber.localizedLowercase
            }
            return lhsName < rhsName
        }
    }

    // MARK: - Scope Mutation

    /// Defines whether a scope mutation adds or removes devices from a prestage.
    private enum ScopeMutationAction {
        case add
        case remove

        /// HTTP method for the documented v1 `/scope` endpoint. Add uses
        /// POST; Remove uses DELETE. Both accept a request body
        /// containing `serialNumbers` + `versionLock`.
        var v1Method: HTTPMethod {
            switch self {
            case .add: return .post
            case .remove: return .delete
            }
        }

        /// v2-compatibility suffix used as a fallback when the v1
        /// `/scope` endpoint is unavailable at the target tenant
        /// (response 403/404/405). Existed historically as the only
        /// known path that some older Jamf Pro builds would accept.
        var v2FallbackSuffix: String {
            switch self {
            case .add: return "add-multiple"
            case .remove: return "delete-multiple"
            }
        }

        /// Human-readable verb for log/error messaging.
        var verb: String {
            switch self {
            case .add: return "add"
            case .remove: return "remove"
            }
        }
    }

    /// Applies a scope mutation (add or remove) to a mobile-device prestage.
    ///
    /// The primary path is Jamf Pro's **documented** v1 scope endpoint:
    ///
    /// - `POST   /api/v1/mobile-device-prestages/{id}/scope` — add
    /// - `DELETE /api/v1/mobile-device-prestages/{id}/scope` — remove
    ///
    /// Both accept a body of `{"serialNumbers": [...], "versionLock": N}`
    /// where `versionLock` is the tenant's optimistic-lock value for the
    /// prestage. Jamf returns HTTP 409 when the lock is stale (another
    /// writer mutated the scope between our read and our write); the
    /// caller is expected to refresh the lock and retry.
    ///
    /// This implementation follows that contract:
    /// 1. Resolve the current versionLock (live GET with cache fallback).
    /// 2. Send the documented v1 request. On HTTP 409, refresh the
    ///    versionLock and retry once — exactly as the report recommended.
    /// 3. On HTTP 403/404/405 the v1 endpoint isn't reachable at this
    ///    tenant. Fall back to the legacy v2 `add-multiple` /
    ///    `delete-multiple` compatibility path so existing working
    ///    flows don't regress. A warning-severity event records the
    ///    fallback so operators can see which tenants still need v2.
    /// 4. On any other error — throw. Don't silently eat non-conflict
    ///    failures in a retry loop.
    ///
    /// - Parameters:
    ///   - action: Whether to add or remove devices.
    ///   - prestageID: The target prestage identifier.
    ///   - serialNumbers: The serial numbers to add or remove.
    private func applyScopeMutation(
        _ action: ScopeMutationAction,
        prestageID: String,
        serialNumbers: [String]
    ) async throws {
        let normalizedSerialNumbers = Array(Set(serialNumbers.compactMap(normalizeSerial))).sorted()
        guard normalizedSerialNumbers.isEmpty == false else {
            throw JamfFrameworkError.persistenceFailure(message: "No serial numbers available for scope mutation.")
        }

        let v1Endpoint = "api/v1/mobile-device-prestages/\(prestageID)/scope"
        var versionLock = try await resolveVersionLock(for: prestageID)

        // Primary path: documented v1 POST/DELETE with a single
        // versionLock-refresh retry on HTTP 409.
        for attempt in 0..<2 {
            let payload: [String: Any] = [
                "serialNumbers": normalizedSerialNumbers,
                "versionLock": versionLock
            ]
            let payloadData = try JSONSerialization.data(withJSONObject: payload, options: [])

            do {
                let responseData = try await apiGateway.request(
                    path: v1Endpoint,
                    method: action.v1Method,
                    body: payloadData
                )

                // Jamf returns the updated prestage resource on success.
                // Parse the new versionLock out of it so the next
                // mutation starts from a fresh value without a
                // round-trip.
                if let newVersionLock = parseVersionLock(from: responseData) {
                    updateCachedPrestageVersionLock(id: prestageID, versionLock: newVersionLock)
                }

                await diagnosticsReporter.report(
                    source: moduleSource,
                    category: "prestage-scope-mutation",
                    severity: .info,
                    message: "Applied prestage scope mutation via documented v1 /scope endpoint.",
                    metadata: [
                        "action": action.verb,
                        "prestage_id": prestageID,
                        "endpoint": v1Endpoint,
                        "serial_count": String(normalizedSerialNumbers.count),
                        "version_lock": String(versionLock),
                        "attempt": String(attempt)
                    ]
                )
                return
            } catch {
                if attempt == 0, error.isJamfConflict {
                    // Optimistic-lock failure. Jamf's docs describe
                    // exactly this case: refresh the lock, retry once.
                    let refreshedLock = try await resolveVersionLock(for: prestageID)
                    await diagnosticsReporter.report(
                        source: moduleSource,
                        category: "prestage-scope-mutation",
                        severity: .warning,
                        message: "v1 /scope returned 409 (stale versionLock); refreshing and retrying once.",
                        metadata: [
                            "action": action.verb,
                            "prestage_id": prestageID,
                            "endpoint": v1Endpoint,
                            "stale_version_lock": String(versionLock),
                            "refreshed_version_lock": String(refreshedLock)
                        ]
                    )
                    versionLock = refreshedLock
                    continue
                }

                if error.isJamfEndpointUnavailable {
                    // v1 /scope doesn't exist at this tenant — log
                    // and drop through to the v2 fallback below.
                    await diagnosticsReporter.report(
                        source: moduleSource,
                        category: "prestage-scope-mutation",
                        severity: .warning,
                        message: "v1 /scope endpoint unavailable (403/404/405); falling back to v2 \(action.v2FallbackSuffix).",
                        metadata: [
                            "action": action.verb,
                            "prestage_id": prestageID,
                            "endpoint": v1Endpoint
                        ]
                    )
                    break
                }

                // Any other failure (400, 500, transport error) —
                // don't swallow it in a retry loop. The operator
                // deserves to see the actual cause.
                throw error
            }
        }

        // Fallback path: the legacy v2 compatibility endpoints. Kept
        // because the working flow this replaced used them; still
        // supports both integer and string versionLock encodings
        // because some older Jamf builds rejected one but not the
        // other.
        try await applyScopeMutationViaV2Fallback(
            action,
            prestageID: prestageID,
            serialNumbers: normalizedSerialNumbers,
            versionLock: versionLock
        )
    }

    /// Legacy v2 fallback for scope mutation. Tries
    /// `POST /api/v2/mobile-device-prestages/{id}/scope/{add-multiple|delete-multiple}`,
    /// then the plain `/scope` variant for add (which some Jamf builds
    /// accepted). Preserves the integer-or-string versionLock payload
    /// tolerance from the pre-v1 implementation.
    private func applyScopeMutationViaV2Fallback(
        _ action: ScopeMutationAction,
        prestageID: String,
        serialNumbers: [String],
        versionLock: Int
    ) async throws {
        let payloadCandidates: [[String: Any]] = [
            [
                "serialNumbers": serialNumbers,
                "versionLock": versionLock
            ],
            [
                "serialNumbers": serialNumbers,
                "versionLock": String(versionLock)
            ]
        ]

        let endpointCandidates: [String] = {
            switch action {
            case .add:
                return [
                    "api/v2/mobile-device-prestages/\(prestageID)/scope/\(action.v2FallbackSuffix)",
                    "api/v2/mobile-device-prestages/\(prestageID)/scope"
                ]
            case .remove:
                return [
                    "api/v2/mobile-device-prestages/\(prestageID)/scope/\(action.v2FallbackSuffix)"
                ]
            }
        }()

        var lastError: (any Error)?

        for endpointPath in endpointCandidates {
            for payload in payloadCandidates {
                let payloadData = try JSONSerialization.data(withJSONObject: payload, options: [])

                do {
                    _ = try await apiGateway.request(
                        path: endpointPath,
                        method: .post,
                        body: payloadData
                    )
                    await diagnosticsReporter.report(
                        source: moduleSource,
                        category: "prestage-scope-mutation",
                        severity: .warning,
                        message: "Applied prestage scope mutation via v2 fallback endpoint.",
                        metadata: [
                            "action": action.verb,
                            "prestage_id": prestageID,
                            "endpoint": endpointPath
                        ]
                    )
                    return
                } catch {
                    lastError = error
                    if shouldTryAlternatePayload(after: error) { continue }
                    if shouldTryAlternateEndpoint(after: error) { break }
                    throw error
                }
            }
        }

        if let lastError {
            throw lastError
        }

        throw JamfFrameworkError.persistenceFailure(message: "Unable to apply pre-stage scope mutation via v1 or v2 endpoints.")
    }

    /// Resolves the current version lock for a prestage, falling back to a cached
    /// value if the live fetch fails.
    ///
    /// - Parameter prestageID: The prestage to resolve the version lock for.
    /// - Returns: The resolved integer version lock value.
    private func resolveVersionLock(for prestageID: String) async throws -> Int {
        do {
            let resolvedVersionLock = try await fetchPrestageVersionLock(for: prestageID)
            updateCachedPrestageVersionLock(id: prestageID, versionLock: resolvedVersionLock)
            return resolvedVersionLock
        } catch {
            // Fall back to the cached version lock from the prestage list
            if let cachedVersionLock = prestages.first(where: { $0.id == prestageID })?.versionLock {
                return cachedVersionLock
            }
            throw error
        }
    }

    /// Fetches the current version lock for a specific prestage from the Jamf Pro API.
    private func fetchPrestageVersionLock(for prestageID: String) async throws -> Int {
        let data = try await apiGateway.request(
            path: "api/v2/mobile-device-prestages/\(prestageID)",
            method: .get
        )

        guard let versionLock = parseVersionLock(from: data) else {
            throw JamfFrameworkError.persistenceFailure(
                message: "Unable to resolve versionLock for pre-stage \(prestageID)."
            )
        }

        return versionLock
    }

    /// Updates the in-memory cached version lock for a prestage after a successful
    /// fetch or mutation to keep the local state fresh.
    private func updateCachedPrestageVersionLock(id: String, versionLock: Int) {
        guard let index = prestages.firstIndex(where: { $0.id == id }) else {
            return
        }

        let existing = prestages[index]
        guard existing.versionLock != versionLock else {
            return
        }

        prestages[index] = PrestageSummary(
            id: existing.id,
            name: existing.name,
            versionLock: versionLock
        )
    }

    // MARK: - Error Classification

    /// Returns `true` if the error indicates the payload shape was
    /// rejected (400/415/422), meaning an alternate payload encoding
    /// should be tried. Thin wrapper around the shared
    /// `Error.matchesJamf(status:)` helper — covers both typed
    /// `.networkFailure(code, _)` and any future typed variant that
    /// maps to one of these codes.
    private func shouldTryAlternatePayload(after error: any Error) -> Bool {
        error.matchesJamf(status: 400, 415, 422)
    }

    /// Returns `true` if the error indicates the endpoint path was not
    /// found (404/405), meaning an alternate endpoint suffix should be
    /// tried. Thin wrapper around the shared classification helper.
    private func shouldTryAlternateEndpoint(after error: any Error) -> Bool {
        error.matchesJamf(status: 404, 405)
    }

    // MARK: - JSON Parsing

    /// Parses a page of prestage summaries from raw JSON data.
    ///
    /// Handles multiple response shapes across Jamf Pro versions by probing for
    /// results under various known key names (`results`, `prestages`, `items`, etc.).
    ///
    /// - Parameter data: Raw JSON response data.
    /// - Returns: An array of parsed `PrestageSummary` values.
    private func parsePrestageSummaries(from data: Data) -> [PrestageSummary] {
        let jsonObject: Any
        do {
            jsonObject = try JSONSerialization.jsonObject(with: data)
        } catch {
            reportError(category: "prestage", message: "Failed to parse prestage summaries JSON.", errorDescription: describe(error))
            return []
        }

        let objects: [[String: Any]]

        if let dictionary = jsonObject as? [String: Any] {
            objects =
                dictionaryArray(from: dictionary["results"]) ??
                dictionaryArray(from: dictionary["prestages"]) ??
                dictionaryArray(from: dictionary["mobileDevicePrestages"]) ??
                dictionaryArray(from: dictionary["items"]) ??
                dictionaryArray(from: dictionary["data"]) ??
                []
        } else {
            objects = dictionaryArray(from: jsonObject) ?? []
        }

        return objects.compactMap { item in
            guard let id =
                extractString(from: item["id"]) ??
                extractString(from: item["prestageId"])
            else {
                return nil
            }

            let name =
                extractString(from: item["displayName"]) ??
                extractString(from: item["name"]) ??
                extractString(from: item["profileName"]) ??
                "Pre-Stage \(id)"

            return PrestageSummary(
                id: id,
                name: name,
                versionLock: extractVersionLock(from: item)
            )
        }
    }

    /// Extracts a version lock integer from raw JSON data.
    private func parseVersionLock(from data: Data) -> Int? {
        let jsonObject: Any
        do {
            jsonObject = try JSONSerialization.jsonObject(with: data)
        } catch {
            reportError(category: "prestage", message: "Failed to parse version lock JSON.", errorDescription: describe(error))
            return nil
        }

        return extractVersionLock(from: jsonObject)
    }

    /// Parses scoped device assignments from raw JSON data.
    ///
    /// Handles deeply nested and varied response shapes by probing multiple known
    /// key paths (`assignments`, `results`, `devices`, etc.) and falling back to
    /// flat serial number arrays when structured records are unavailable.
    ///
    /// - Parameter data: Raw JSON response data.
    /// - Returns: A deduplicated array of parsed assigned devices.
    private func parseScopedDevices(
        from data: Data,
        prestageID: String?,
        prestageName: String?
    ) -> [PrestageAssignedDevice] {
        let jsonObject: Any
        do {
            jsonObject = try JSONSerialization.jsonObject(with: data)
        } catch {
            reportError(category: "prestage", message: "Failed to parse scoped devices JSON.", errorDescription: describe(error))
            return []
        }

        if let dictionary = jsonObject as? [String: Any] {
            // Try known container keys first
            let objectCandidates: [Any?] = [
                dictionary["assignments"],
                dictionary["results"],
                dictionary["devices"],
                dictionary["mobileDevices"],
                dictionary["items"],
                dictionary["data"]
            ]

            for candidate in objectCandidates {
                guard let objects = dictionaryArray(from: candidate), objects.isEmpty == false else {
                    continue
                }

                let parsed = objects.compactMap { parseScopedDevice(from: $0, prestageID: prestageID, prestageName: prestageName) }
                if parsed.isEmpty == false {
                    return dedupeDevices(parsed)
                }
            }

            // Try any nested value that looks like an array of device dictionaries
            for nestedValue in dictionary.values {
                guard let objects = dictionaryArray(from: nestedValue), objects.isEmpty == false else {
                    continue
                }

                let parsed = objects.compactMap { parseScopedDevice(from: $0, prestageID: prestageID, prestageName: prestageName) }
                if parsed.isEmpty == false {
                    return dedupeDevices(parsed)
                }
            }

            // Last resort: look for a flat array of serial number strings
            if let serialNumbers =
                extractStringArray(from: dictionary["serialNumbers"]) ??
                extractStringArray(from: (dictionary["assignments"] as? [String: Any])?["serialNumbers"])
            {
                return dedupeDevices(serialNumbers.compactMap { makeScopedDeviceFallback(from: $0, prestageID: prestageID, prestageName: prestageName) })
            }
        }

        if let objects = dictionaryArray(from: jsonObject), objects.isEmpty == false {
            return dedupeDevices(objects.compactMap { parseScopedDevice(from: $0, prestageID: prestageID, prestageName: prestageName) })
        }

        if let serialNumbers = extractStringArray(from: jsonObject) {
            return dedupeDevices(serialNumbers.compactMap { makeScopedDeviceFallback(from: $0, prestageID: prestageID, prestageName: prestageName) })
        }

        return []
    }

    /// Parses a single device dictionary into a `PrestageAssignedDevice`.
    ///
    /// Probes multiple key names at the top level and within nested device objects
    /// to handle the wide variety of response shapes across Jamf Pro versions.
    ///
    /// - Parameters:
    ///   - item: A dictionary representing a single device assignment.
    ///   - prestageID: The Jamf Pro prestage identifier whose scope produced this record.
    ///   - prestageName: The display name of that prestage.
    /// - Returns: A parsed `PrestageAssignedDevice`, or `nil` if both serial and ID are missing.
    private func parseScopedDevice(
        from item: [String: Any],
        prestageID: String?,
        prestageName: String?
    ) -> PrestageAssignedDevice? {
        var serialNumber =
            extractString(from: item["serialNumber"]) ??
            extractString(from: item["serial"]) ??
            extractString(from: item["hardwareSerialNumber"])

        var deviceName =
            extractString(from: item["deviceName"]) ??
            extractString(from: item["name"]) ??
            extractString(from: item["displayName"])

        var udid = extractString(from: item["udid"])
        var model =
            extractString(from: item["model"]) ??
            extractString(from: item["modelIdentifier"])

        var assignmentID =
            extractString(from: item["id"]) ??
            extractString(from: item["assignmentId"]) ??
            extractString(from: item["deviceId"]) ??
            extractString(from: item["mobileDeviceId"])

        // Probe nested device objects for missing values
        let nestedKeys = ["mobileDevice", "device", "inventoryRecord", "inventory", "item"]
        for key in nestedKeys {
            guard let nested = item[key] as? [String: Any] else {
                continue
            }

            serialNumber = serialNumber ??
                extractString(from: nested["serialNumber"]) ??
                extractString(from: nested["serial"])

            deviceName = deviceName ??
                extractString(from: nested["deviceName"]) ??
                extractString(from: nested["name"]) ??
                extractString(from: nested["displayName"])

            udid = udid ?? extractString(from: nested["udid"])

            model = model ??
                extractString(from: nested["model"]) ??
                extractString(from: nested["modelIdentifier"])

            assignmentID = assignmentID ??
                extractString(from: nested["id"]) ??
                extractString(from: nested["deviceId"]) ??
                extractString(from: nested["mobileDeviceId"])
        }

        // Last-resort fuzzy key matching for serial number
        if serialNumber == nil {
            serialNumber = extractValue(matching: "serial", in: item)
        }

        let normalizedSerial = normalizeSerial(serialNumber)
        let resolvedID = assignmentID ?? normalizedSerial ?? UUID().uuidString

        // Must have at least a serial or an assignment ID
        guard normalizedSerial != nil || assignmentID != nil else {
            return nil
        }

        let trimmedName = deviceName?.trimmingCharacters(in: .whitespacesAndNewlines)
        let resolvedName: String
        if let trimmedName, trimmedName.isEmpty == false {
            resolvedName = trimmedName
        } else {
            resolvedName = normalizedSerial ?? "Unknown Device"
        }

        return PrestageAssignedDevice(
            id: resolvedID,
            serialNumber: normalizedSerial ?? "",
            deviceName: resolvedName,
            udid: udid,
            model: model,
            prestageID: prestageID,
            prestageName: prestageName
        )
    }

    /// Creates a minimal device record from just a serial number string, used as a
    /// fallback when the API returns flat serial arrays instead of full device objects.
    private func makeScopedDeviceFallback(
        from serialNumber: String,
        prestageID: String?,
        prestageName: String?
    ) -> PrestageAssignedDevice? {
        guard let normalizedSerial = normalizeSerial(serialNumber) else {
            return nil
        }
        return PrestageAssignedDevice(
            id: normalizedSerial,
            serialNumber: normalizedSerial,
            deviceName: normalizedSerial,
            udid: nil,
            model: nil,
            prestageID: prestageID,
            prestageName: prestageName
        )
    }

    // MARK: - Deduplication

    /// Removes duplicate prestage summaries, preferring entries that have a version lock.
    private func dedupePrestages(_ prestages: [PrestageSummary]) -> [PrestageSummary] {
        var uniqueByID: [String: PrestageSummary] = [:]

        for prestage in prestages {
            guard let existing = uniqueByID[prestage.id] else {
                uniqueByID[prestage.id] = prestage
                continue
            }

            // Prefer the entry with a version lock value
            if existing.versionLock == nil && prestage.versionLock != nil {
                uniqueByID[prestage.id] = prestage
            }
        }

        return Array(uniqueByID.values)
    }

    /// Removes duplicate devices by selection key, keeping the last occurrence.
    private func dedupeDevices(_ devices: [PrestageAssignedDevice]) -> [PrestageAssignedDevice] {
        var uniqueBySelectionKey: [String: PrestageAssignedDevice] = [:]

        for device in devices {
            uniqueBySelectionKey[device.selectionKey] = device
        }

        return Array(uniqueBySelectionKey.values)
    }

    // MARK: - Low-Level Extraction Helpers

    /// Attempts to extract an array of dictionaries from various JSON container shapes.
    private func dictionaryArray(from value: Any?) -> [[String: Any]]? {
        if let dictionaries = value as? [[String: Any]] {
            return dictionaries
        }

        if let array = value as? [Any] {
            let dictionaries = array.compactMap { $0 as? [String: Any] }
            return dictionaries.isEmpty ? nil : dictionaries
        }

        if let dictionary = value as? [String: Any] {
            return
                dictionaryArray(from: dictionary["results"]) ??
                dictionaryArray(from: dictionary["items"]) ??
                dictionaryArray(from: dictionary["assignments"]) ??
                dictionaryArray(from: dictionary["devices"]) ??
                dictionaryArray(from: dictionary["mobileDevices"]) ??
                dictionaryArray(from: dictionary["data"])
        }

        return nil
    }

    /// Attempts to extract an array of strings from various JSON container shapes.
    private func extractStringArray(from value: Any?) -> [String]? {
        if let strings = value as? [String] {
            let cleaned = strings.compactMap { extractString(from: $0) }
            return cleaned.isEmpty ? nil : cleaned
        }

        if let array = value as? [Any] {
            let cleaned = array.compactMap { extractString(from: $0) }
            return cleaned.isEmpty ? nil : cleaned
        }

        if let dictionary = value as? [String: Any] {
            return
                extractStringArray(from: dictionary["serialNumbers"]) ??
                extractStringArray(from: dictionary["serials"]) ??
                extractStringArray(from: dictionary["items"]) ??
                extractStringArray(from: dictionary["values"])
        }

        return nil
    }

    /// Recursively searches a JSON structure for a version lock value using known key names.
    private func extractVersionLock(from value: Any) -> Int? {
        if let dictionary = value as? [String: Any] {
            let priorityKeys = [
                "versionLock",
                "version_lock",
                "lockVersion",
                "optimisticLockVersion"
            ]

            for key in priorityKeys {
                if let resolved = extractInt(from: dictionary[key]) {
                    return resolved
                }
            }

            // Fuzzy match for keys containing "versionlock" (case-insensitive, ignoring underscores)
            for (key, nestedValue) in dictionary {
                let normalizedKey = key.replacingOccurrences(of: "_", with: "").lowercased()
                if normalizedKey.contains("versionlock"),
                   let resolved = extractInt(from: nestedValue)
                {
                    return resolved
                }
            }

            if let resolvedVersion = extractInt(from: dictionary["version"]) {
                return resolvedVersion
            }

            // Recurse into nested containers
            for nestedValue in dictionary.values {
                if let nestedDictionary = nestedValue as? [String: Any],
                   let resolved = extractVersionLock(from: nestedDictionary)
                {
                    return resolved
                }

                if let nestedArray = nestedValue as? [Any],
                   let resolved = extractVersionLock(from: nestedArray)
                {
                    return resolved
                }
            }
            return nil
        }

        if let array = value as? [Any] {
            for item in array {
                if let nestedDictionary = item as? [String: Any],
                   let resolved = extractVersionLock(from: nestedDictionary)
                {
                    return resolved
                }

                if let nestedArray = item as? [Any],
                   let resolved = extractVersionLock(from: nestedArray)
                {
                    return resolved
                }
            }
            return nil
        }

        return nil
    }

    /// Extracts an integer from a JSON value, handling Int, NSNumber, and String representations.
    private func extractInt(from value: Any?) -> Int? {
        switch value {
        case let intValue as Int:
            return intValue
        case let numberValue as NSNumber:
            return numberValue.intValue
        case let stringValue as String:
            let trimmed = stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
            return Int(trimmed)
        default:
            return nil
        }
    }

    /// Extracts a non-empty trimmed string from a JSON value, handling String, Int, and NSNumber.
    private func extractString(from value: Any?) -> String? {
        switch value {
        case let stringValue as String:
            let trimmed = stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        case let intValue as Int:
            return String(intValue)
        case let numberValue as NSNumber:
            return numberValue.stringValue
        default:
            return nil
        }
    }

    /// Recursively searches a dictionary for the first value whose key contains the given
    /// fragment (case-insensitive), useful as a last-resort extraction strategy.
    private func extractValue(matching keyFragment: String, in dictionary: [String: Any]) -> String? {
        for (key, value) in dictionary {
            if key.localizedCaseInsensitiveContains(keyFragment),
               let extracted = extractString(from: value)
            {
                return extracted
            }

            if let nestedDictionary = value as? [String: Any],
               let nestedValue = extractValue(matching: keyFragment, in: nestedDictionary)
            {
                return nestedValue
            }
        }

        return nil
    }

    // MARK: - String Normalization

    /// Normalizes a serial number by trimming whitespace and converting to uppercase.
    /// Returns `nil` if the result is empty.
    private func normalizeSerial(_ value: String?) -> String? {
        guard let value else {
            return nil
        }

        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.isEmpty == false else {
            return nil
        }

        return trimmed.uppercased()
    }

    /// Normalizes a search query to uppercase for serial comparison.
    /// Returns `nil` if the trimmed query is empty.
    private func normalizedSerialQuery(_ query: String) -> String? {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.isEmpty == false else {
            return nil
        }

        return trimmed.uppercased()
    }

    /// The devices currently visible in the list, used for select-all logic.
    private var visibleScopedDevices: [PrestageAssignedDevice] {
        filteredScopedDevices
    }

    // MARK: - Diagnostics

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
