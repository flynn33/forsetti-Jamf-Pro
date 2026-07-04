import Foundation
import Combine


@MainActor
/// The view model that drives the Computer Search module, coordinating API calls, profile
/// management, search execution, prestage enrollment resolution, and diagnostics reporting.
///
/// This class handles the full lifecycle of a computer inventory search:
/// 1. Loading and saving search profiles from disk.
/// 2. Building RSQL filter expressions from the user's query and selected fields.
/// 3. Issuing paginated requests across multiple API endpoint versions (v3, v2, v1) with
///    automatic fallback when a version returns an error.
/// 4. Decoding the heterogeneous JSON responses into `ComputerRecord` instances.
/// 5. Enriching results with PreStage enrollment data gathered from separate API endpoints.
/// 6. Reporting diagnostics events and errors through the shared reporter.
final class ComputerSearchViewModel: ObservableObject {

    // MARK: - Private Types

    /// A lightweight summary of a computer prestage profile (ID + name), used during
    /// the prestage scope resolution pipeline.
    private struct ComputerPrestageSummary: Sendable {
        let id: String
        let name: String
    }

    /// Associates a serial number with the prestage profile it is scoped to,
    /// allowing the search results to be enriched with enrollment information.
    private struct ComputerPrestageScopeAssociation: Sendable {
        let serialNumber: String
        let profileID: String
        let profileName: String
    }

    /// Enumerates the Jamf Pro computer inventory API endpoint versions, tried in order
    /// from newest (v3) to oldest (v1) until a successful response is received.
    private enum ComputerInventoryEndpointVersion: String, CaseIterable {
        case v3 = "v3"
        case v2 = "v2"
        case v1 = "v1"

        /// The URL path segment for this API version (e.g. `"api/v3/computers-inventory"`).
        var path: String {
            "api/\(rawValue)/computers-inventory"
        }

        /// The set of inventory sections supported by this endpoint version.
        /// v2 and v3 dropped support for plugins and fonts.
        var supportedSections: Set<ComputerInventorySection> {
            switch self {
            case .v1:
                return Set(ComputerInventorySection.allCases)
            case .v2, .v3:
                return Set(ComputerInventorySection.allCases).subtracting([.plugins, .fonts])
            }
        }
    }

    // MARK: - Published State

    /// The raw search query entered by the user (computer name, serial, username, email, etc.).
    @Published var query = ""

    /// The list of saved search profiles loaded from disk, sorted alphabetically by name.
    @Published private(set) var profiles: [ComputerSearchProfile] = []

    /// The UUID of the currently selected search profile, or `nil` for no profile.
    @Published var selectedProfileID: UUID?

    /// The set of inventory field keys currently toggled on, either from a profile or manual selection.
    @Published var selectedFieldKeys: Set<String> = []

    /// The array of computer records returned by the most recent search.
    @Published private(set) var searchResults: [ComputerRecord] = []

    /// Whether a search request is currently in flight, used to show a loading indicator.
    @Published private(set) var isSearching = false

    /// Controls presentation of the field catalog sheet.
    @Published var isFieldCatalogPresented = false

    /// Controls presentation of the "Save Profile" alert dialog.
    @Published var isSaveProfilePromptPresented = false

    /// The text entered into the profile name field in the save alert.
    @Published var pendingProfileName = ""

    /// A user-facing error message displayed when a search or profile operation fails.
    @Published var errorMessage: String?

    /// A non-fatal notice surfaced when the search succeeded but had to use a degraded
    /// code path (e.g. fell back to bare-array decoding because the server omitted the
    /// `results` wrapper). Displayed in amber below results so operators know the
    /// response format wasn't the expected one.
    @Published var decodingNoticeMessage: String?

    /// Controls presentation of the Advanced Search builder sheet.
    @Published var isAdvancedSearchPresented = false

    /// Saved Smart Filters loaded from disk, sorted alphabetically by name.
    /// Distinct from `profiles` (which only persist display columns) — a Smart
    /// Filter persists a full `AdvancedQuery` plus the columns active at save.
    @Published private(set) var smartFilters: [SmartFilter] = []

    /// Tenant-published Computer Extension Attributes, sorted alphabetically by
    /// name. Loaded once per module appearance via `loadExtensionAttributes()`
    /// and merged into `allCatalogFields` as synthetic `cea_<id>` fields so they
    /// flow into the field catalog, result rows, detail view, and the
    /// client-side Advanced Search matcher.
    @Published private(set) var extensionAttributes: [ComputerExtensionAttribute] = []

    /// Non-fatal message set only when every EA endpoint variant failed. Search
    /// still works against built-in fields; surfaced so the picker can note that
    /// EAs are unavailable rather than silently missing.
    @Published private(set) var extensionAttributeLoadError: String?

    /// Whether an EA load has been attempted this session (regardless of
    /// success). Lets the UI distinguish "not loaded yet" from "loaded, none
    /// published".
    @Published private(set) var hasAttemptedExtensionAttributeLoad = false

    // MARK: - Dependencies

    /// The API gateway used to issue authenticated HTTP requests to Jamf Pro.
    private let apiGateway: JamfAPIGateway

    /// The diagnostics reporter for logging events and errors.
    private let diagnosticsReporter: any DiagnosticsReporting

    /// The persistence store for reading and writing search profiles.
    private let profileStore: ComputerSearchProfileStore

    /// The persistence store for reading and writing saved Smart Filters.
    private let smartFilterStore: ComputerSmartFilterStore

    /// A shared JSON decoder instance for all response parsing.
    private let decoder = JSONDecoder()

    /// The diagnostics source identifier for all events emitted by this module.
    private let moduleSource = "module.computer-search"

    /// Display label for enrolled prestage status.
    private let enrolledStatusLabel = "Enrolled"

    /// Display label for not-enrolled prestage status.
    private let notEnrolledStatusLabel = "Not Enrolled"

    /// An in-memory cache mapping prestage profile IDs to their display names,
    /// avoiding redundant API calls during a single search session.
    private var computerPrestageNameCache: [String: String] = [:]

    /// The complete set of field keys that the Jamf Pro API supports in inventory filter expressions.
    /// Fields not in this set cannot be used in RSQL queries and are silently excluded.
    /// L3: These allowlists must be updated when targeting newer Jamf Pro API versions.
    /// Last verified against: Jamf Pro API v1 computers-inventory (Jamf Pro 11.x)
    private let supportedInventoryFilterKeys: Set<String> = [
        "general.name",
        "udid",
        "id",
        "general.assetTag",
        "general.barcode1",
        "general.barcode2",
        "general.enrolledViaAutomatedDeviceEnrollment",
        "general.lastIpAddress",
        "general.jamfBinaryVersion",
        "general.lastContactTime",
        "general.lastEnrolledDate",
        "general.lastCloudBackupDate",
        "general.reportDate",
        "general.lastReportedIp",
        "general.lastReportedIpV4",
        "general.lastReportedIpV6",
        "general.managementId",
        "general.remoteManagement.managed",
        "general.mdmCapable.capable",
        "general.mdmCertificateExpiration",
        "general.platform",
        "general.supervised",
        "general.userApprovedMdm",
        "general.declarativeDeviceManagementEnabled",
        "general.lastLoggedInUsernameSelfService",
        "general.lastLoggedInUsernameSelfServiceTimestamp",
        "general.lastLoggedInUsernameBinary",
        "general.lastLoggedInUsernameBinaryTimestamp",
        "hardware.bleCapable",
        "hardware.macAddress",
        "hardware.make",
        "hardware.model",
        "hardware.modelIdentifier",
        "hardware.serialNumber",
        "hardware.supportsIosAppInstalls",
        "hardware.appleSilicon",
        "operatingSystem.activeDirectoryStatus",
        "operatingSystem.fileVault2Status",
        "operatingSystem.build",
        "operatingSystem.supplementalBuildVersion",
        "operatingSystem.rapidSecurityResponse",
        "operatingSystem.name",
        "operatingSystem.version",
        "security.activationLockEnabled",
        "security.recoveryLockEnabled",
        "security.firewallEnabled",
        "userAndLocation.buildingId",
        "userAndLocation.departmentId",
        "userAndLocation.email",
        "userAndLocation.realname",
        "userAndLocation.phone",
        "userAndLocation.position",
        "userAndLocation.room",
        "userAndLocation.username",
        "diskEncryption.fileVault2Enabled",
        "purchasing.appleCareId",
        "purchasing.lifeExpectancy",
        "purchasing.purchased",
        "purchasing.leased",
        "purchasing.vendor",
        "purchasing.warrantyDate"
    ]

    /// Field keys that accept boolean filter values (true/false).
    private let booleanInventoryFilterKeys: Set<String> = [
        "general.enrolledViaAutomatedDeviceEnrollment",
        "general.remoteManagement.managed",
        "general.mdmCapable.capable",
        "general.supervised",
        "general.userApprovedMdm",
        "general.declarativeDeviceManagementEnabled",
        "hardware.bleCapable",
        "hardware.supportsIosAppInstalls",
        "hardware.appleSilicon",
        "security.activationLockEnabled",
        "security.recoveryLockEnabled",
        "security.firewallEnabled",
        "diskEncryption.fileVault2Enabled",
        "purchasing.purchased",
        "purchasing.leased"
    ]

    /// Field keys that accept numeric filter values.
    private let numericInventoryFilterKeys: Set<String> = [
        "id",
        "userAndLocation.buildingId",
        "userAndLocation.departmentId",
        "purchasing.lifeExpectancy"
    ]

    /// Field keys that accept free-text (string) filter values with optional wildcard wrapping.
    private let textualInventoryFilterKeys: Set<String> = [
        "general.name",
        "udid",
        "general.assetTag",
        "general.barcode1",
        "general.barcode2",
        "general.lastIpAddress",
        "general.jamfBinaryVersion",
        "general.lastReportedIp",
        "general.lastReportedIpV4",
        "general.lastReportedIpV6",
        "general.managementId",
        "general.platform",
        "general.lastLoggedInUsernameSelfService",
        "general.lastLoggedInUsernameBinary",
        "hardware.macAddress",
        "hardware.make",
        "hardware.model",
        "hardware.modelIdentifier",
        "hardware.serialNumber",
        "operatingSystem.activeDirectoryStatus",
        "operatingSystem.fileVault2Status",
        "operatingSystem.build",
        "operatingSystem.supplementalBuildVersion",
        "operatingSystem.rapidSecurityResponse",
        "operatingSystem.name",
        "operatingSystem.version",
        "userAndLocation.email",
        "userAndLocation.realname",
        "userAndLocation.phone",
        "userAndLocation.position",
        "userAndLocation.room",
        "userAndLocation.username",
        "purchasing.appleCareId",
        "purchasing.vendor"
    ]

    /// A minimal set of field keys used as a last-resort fallback when the primary fields
    /// are rejected by the API (e.g. due to privilege restrictions).
    private let privilegeFallbackFilterFieldKeys: [String] = [
        "general.name",
        "hardware.serialNumber",
        "udid",
        "general.assetTag",
        "general.barcode1",
        "general.barcode2",
        "general.lastIpAddress",
        "userAndLocation.username",
        "userAndLocation.email",
        "userAndLocation.realname"
    ]

    // MARK: - Initialization

    /// Creates a new view model with the required dependencies.
    ///
    /// - Parameters:
    ///   - apiGateway: The gateway for authenticated Jamf Pro API requests.
    ///   - diagnosticsReporter: The reporter for logging events and errors.
    ///   - profileStore: The persistence layer for search profiles. Defaults to a new store instance.
    ///   - smartFilterStore: The persistence layer for saved Smart Filters. Defaults to a new store instance.
    init(
        apiGateway: JamfAPIGateway,
        diagnosticsReporter: any DiagnosticsReporting,
        profileStore: ComputerSearchProfileStore = ComputerSearchProfileStore(),
        smartFilterStore: ComputerSmartFilterStore = ComputerSmartFilterStore()
    ) {
        self.apiGateway = apiGateway
        self.diagnosticsReporter = diagnosticsReporter
        self.profileStore = profileStore
        self.smartFilterStore = smartFilterStore
    }

    // MARK: - Computed Properties

    /// The currently selected profile object, resolved from `selectedProfileID`.
    /// Returns `nil` if no profile is selected or the ID does not match any loaded profile.
    var selectedProfile: ComputerSearchProfile? {
        guard let selectedProfileID else {
            return nil
        }

        return profiles.first(where: { $0.id == selectedProfileID })
    }

    /// The resolved catalog fields for the active selection, used by result rows to
    /// render columns dynamically. Mirrors the key resolution in `executeSearch`
    /// (profile keys, else manual selection, else the default field set) so the
    /// displayed columns match what was actually requested from the API.
    var resultFields: [ComputerField] {
        let selectedKeys = selectedProfile?.fieldKeys ?? Array(selectedFieldKeys).sorted()
        return resolvedCatalogFields(from: selectedKeys)
    }

    /// The merged catalog used by the field catalog picker, result rows, detail
    /// view, and Advanced Search: the built-in `ComputerField.catalog` plus any
    /// tenant-published Extension Attribute fields. The EA fields are synthetic
    /// (`cea_<id>`) and non-server-filterable, so EA criteria flow into the
    /// composer's client-side matcher without any other call site changing.
    var allCatalogFields: [ComputerField] {
        ComputerField.catalog + extensionAttributes.map { $0.makeField() }
    }

    /// Lookup dictionary over `allCatalogFields`. Used by the composer so
    /// every key the user can pick — including EAs — resolves to a field.
    var mergedFieldLookup: [String: ComputerField] {
        Dictionary(allCatalogFields.map { ($0.key, $0) }, uniquingKeysWith: { first, _ in first })
    }

    // MARK: - Advanced Search

    /// Builds a fresh `ComputerAdvancedSearchViewModel` seeded from the current
    /// field selection. Sheet presentations call this so each open starts from
    /// the user's current column choices without retaining stale state.
    func makeAdvancedSearchViewModel(initialQuery: AdvancedQuery? = nil) -> ComputerAdvancedSearchViewModel {
        ComputerAdvancedSearchViewModel(
            initialQuery: initialQuery ?? AdvancedQuery(groups: [AdvancedQueryGroup()]),
            initialFieldKeys: selectedFieldKeys,
            availableFields: allCatalogFields,
            fieldLookup: mergedFieldLookup
        )
    }

    /// Loads a saved smart filter as the live state of the Advanced sheet AND
    /// applies its captured field columns to the result list. Returns the
    /// prepared sheet view model so the caller can present it.
    func loadSmartFilterIntoAdvancedSearch(_ filter: SmartFilter) -> ComputerAdvancedSearchViewModel {
        if filter.fieldKeys.isEmpty == false {
            selectedFieldKeys = Set(filter.fieldKeys)
        }
        return ComputerAdvancedSearchViewModel(
            initialQuery: filter.query,
            initialFieldKeys: selectedFieldKeys,
            availableFields: allCatalogFields,
            fieldLookup: mergedFieldLookup
        )
    }

    // MARK: - Smart Filter Management

    /// Loads saved smart filters from disk and sorts them alphabetically.
    /// Called on first appearance; safe to call repeatedly.
    func loadSmartFilters() async {
        do {
            let loaded = try await smartFilterStore.loadFilters()
            smartFilters = loaded.sorted {
                $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
            }
        } catch {
            let description = describe(error)
            errorMessage = "Failed to load smart filters. \(description)"
            reportError(
                category: "smartFilters",
                message: "Failed to load smart filters.",
                errorDescription: description
            )
        }
    }

    /// Saves a new smart filter, or updates the existing one if a filter with
    /// the same (case-insensitive) name already exists. Persists before
    /// returning so the UI sees a consistent post-save state.
    func saveOrUpdateSmartFilter(_ filter: SmartFilter) async {
        if let index = smartFilters.firstIndex(where: {
            $0.name.localizedCaseInsensitiveCompare(filter.name) == .orderedSame
        }) {
            // Preserve original id + createdAt so timeline ordering and any
            // pinned-by-id references stay stable across overwrites.
            smartFilters[index] = SmartFilter(
                id: smartFilters[index].id,
                name: filter.name,
                query: filter.query,
                fieldKeys: filter.fieldKeys,
                createdAt: smartFilters[index].createdAt
            )
        } else {
            smartFilters.append(filter)
        }
        smartFilters.sort {
            $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }

        do {
            try await smartFilterStore.saveFilters(smartFilters)
            errorMessage = nil
            reportEvent(
                severity: .info,
                category: "smartFilters",
                message: "Saved smart filter.",
                metadata: ["filter_name": filter.name]
            )
        } catch {
            let description = describe(error)
            errorMessage = "Failed to save smart filter. \(description)"
            reportError(
                category: "smartFilters",
                message: "Failed to save smart filter.",
                errorDescription: description,
                metadata: ["filter_name": filter.name]
            )
        }
    }

    /// Deletes smart filters at the given list-row offsets and persists the
    /// truncation. Called from the SwiftUI `onDelete` row modifier.
    func deleteSmartFilters(at offsets: IndexSet) {
        for index in offsets.sorted(by: >) {
            guard smartFilters.indices.contains(index) else { continue }
            smartFilters.remove(at: index)
        }

        Task {
            do {
                try await smartFilterStore.saveFilters(smartFilters)
                reportEvent(
                    severity: .warning,
                    category: "smartFilters",
                    message: "Deleted one or more smart filters."
                )
            } catch {
                let description = describe(error)
                errorMessage = "Failed to persist smart filter deletion. \(description)"
                reportError(
                    category: "smartFilters",
                    message: "Failed to persist smart filter deletion.",
                    errorDescription: description
                )
            }
        }
    }

    // MARK: - Profile Management

    /// Loads saved search profiles from disk and selects the first one if nothing is currently selected.
    ///
    /// On failure, sets an error message and reports the error through diagnostics.
    func loadProfiles() async {
        do {
            let loaded = try await profileStore.loadProfiles()
            // Sort profiles alphabetically for consistent display order
            profiles = loaded.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }

            if selectedProfileID == nil {
                selectedProfileID = profiles.first?.id
            }

            applySelectedProfileFields()
        } catch {
            let description = describe(error)
            errorMessage = "Failed to load saved profiles. \(description)"
            reportError(
                category: "profiles",
                message: "Failed to load saved search profiles.",
                errorDescription: description
            )
        }
    }

    /// Copies the field keys from the currently selected profile into `selectedFieldKeys`.
    ///
    /// Does nothing if no profile is selected, preserving any manual field selections.
    func applySelectedProfileFields() {
        guard let selectedProfile else {
            return
        }

        selectedFieldKeys = Set(selectedProfile.fieldKeys)
    }

    /// Presents the save-profile alert if at least one field is selected.
    ///
    /// If no fields are selected, sets a warning error message instead.
    func presentSaveProfilePrompt() {
        guard selectedFieldKeys.isEmpty == false else {
            errorMessage = "Select at least one field before saving a profile."
            reportEvent(
                severity: .warning,
                category: "profiles",
                message: "Profile save requested without selected fields."
            )
            return
        }

        pendingProfileName = ""
        isSaveProfilePromptPresented = true
    }

    /// Validates the pending profile name and saves (or updates) a profile with the current field selection.
    ///
    /// If a profile with the same name already exists (case-insensitive), its fields are updated
    /// in place. Otherwise, a new profile is created and inserted into the sorted list.
    func saveProfileFromPrompt() async {
        let profileName = pendingProfileName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard profileName.isEmpty == false else {
            errorMessage = "Provide a name for the profile."
            reportEvent(
                severity: .warning,
                category: "profiles",
                message: "Profile save attempted without a profile name."
            )
            return
        }

        let sortedFieldKeys = Array(selectedFieldKeys).sorted()

        // Check for an existing profile with the same name to update in place
        if let index = profiles.firstIndex(where: { $0.name.localizedCaseInsensitiveCompare(profileName) == .orderedSame }) {
            profiles[index].fieldKeys = sortedFieldKeys
            selectedProfileID = profiles[index].id
        } else {
            let profile = ComputerSearchProfile(name: profileName, fieldKeys: sortedFieldKeys)
            profiles.append(profile)
            profiles.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
            selectedProfileID = profile.id
        }

        do {
            try await profileStore.saveProfiles(profiles)
            isSaveProfilePromptPresented = false
            errorMessage = nil
            reportEvent(
                severity: .info,
                category: "profiles",
                message: "Saved search profile.",
                metadata: [
                    "profile_name": profileName,
                    "field_count": String(sortedFieldKeys.count)
                ]
            )
        } catch {
            let description = describe(error)
            errorMessage = "Failed to save profile. \(description)"
            reportError(
                category: "profiles",
                message: "Failed to save search profile.",
                errorDescription: description,
                metadata: [
                    "profile_name": profileName
                ]
            )
        }
    }

    /// Deletes profiles at the given index offsets and persists the updated list.
    ///
    /// If the currently selected profile is deleted, automatically selects the first remaining profile.
    /// Deletion is persisted asynchronously; failures are reported but do not block the UI.
    ///
    /// - Parameter offsets: The index set of profiles to remove from the list.
    func deleteProfiles(at offsets: IndexSet) {
        // Remove from highest index first to avoid shifting issues
        for index in offsets.sorted(by: >) {
            guard profiles.indices.contains(index) else {
                continue
            }

            profiles.remove(at: index)
        }

        // Re-select if the active profile was just deleted
        if let selectedProfileID, profiles.contains(where: { $0.id == selectedProfileID }) == false {
            self.selectedProfileID = profiles.first?.id
            applySelectedProfileFields()
        }

        Task {
            do {
                try await profileStore.saveProfiles(profiles)
                await diagnosticsReporter.report(
                    source: moduleSource,
                    category: "profiles",
                    severity: .warning,
                    message: "Deleted one or more search profiles.",
                    metadata: [:]
                )
            } catch {
                let description = describe(error)
                errorMessage = "Failed to persist profile deletion. \(description)"
                await diagnosticsReporter.reportError(
                    source: moduleSource,
                    category: "profiles",
                    message: "Failed to persist profile deletion.",
                    errorDescription: description
                )
            }
        }
    }

    // MARK: - Search Execution

    // "A robot may not injure a human being or, through inaction, allow a human being to come to harm.
    //  A robot must obey the orders given it by human beings except where such orders would conflict with the First Law.
    //  A robot must protect its own existence as long as such protection does not conflict with the First or Second Law."

    /// Executes a computer inventory search against the Jamf Pro API.
    ///
    /// The search pipeline:
    /// 1. Resolves the active field set from the selected profile or manual toggles.
    /// 2. Determines which inventory sections to request based on the fields.
    /// 3. Issues the API request with wildcard RSQL filtering.
    /// 4. On a 400 error, retries with exact-match filtering, then with default fields as a final fallback.
    /// 5. Decodes the response and enriches results with prestage enrollment data.
    func executeSearch() async {
        isSearching = true
        decodingNoticeMessage = nil
        defer { isSearching = false }

        let selectedKeys = selectedProfile?.fieldKeys ?? Array(selectedFieldKeys).sorted()
        let activeFields = resolvedCatalogFields(from: selectedKeys)
        // Always request the identity sections (general/hardware/userAndLocation) so the
        // basic-search filter can match name/serial/username/email regardless of which
        // columns the active profile selects — mirrors the Support Technician module.
        let sections = resolvedSections(from: activeFields + privilegeFallbackFields())
        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)

        do {
            let decodedResults = try await requestAllInventoryPages(
                sections: sections,
                query: trimmedQuery,
                fields: activeFields,
                useWildcardFilter: true,
                displayFields: activeFields
            )

            searchResults = await resolvePrestageEnrollment(for: decodedResults, query: trimmedQuery)
            errorMessage = nil
            reportEvent(
                severity: .info,
                category: "search",
                message: "Computer search completed.",
                metadata: [
                    "result_count": String(searchResults.count),
                    "has_query": trimmedQuery.isEmpty ? "false" : "true",
                    "field_count": String(activeFields.count),
                    "section_count": String(sections.count)
                ]
            )
        } catch {
            // If the wildcard search returned a 400, try progressively
            // simpler strategies. Uses the shared status-matching helper
            // so a typed `.networkFailure(400, _)` reaches this path
            // identically to an untyped one.
            if error.matchesJamf(status: 400),
               trimmedQuery.isEmpty == false
            {
                do {
                    // Fallback 1: exact-match filter (no wildcards)
                    let fallbackResults = try await requestAllInventoryPages(
                        sections: sections,
                        query: trimmedQuery,
                        fields: activeFields,
                        useWildcardFilter: false,
                        displayFields: activeFields
                    )

                    searchResults = await resolvePrestageEnrollment(for: fallbackResults, query: trimmedQuery)
                    errorMessage = nil
                    reportEvent(
                        severity: .warning,
                        category: "search",
                        message: "Computer search completed using exact-match fallback.",
                        metadata: [
                            "result_count": String(searchResults.count),
                            "has_query": "true",
                            "field_count": String(activeFields.count),
                            "section_count": String(sections.count)
                        ]
                    )
                    return
                } catch {
                    if error.matchesJamf(status: 400) {
                        // Fallback 2: default field set (most basic searchable fields)
                        let defaultFields = ComputerField.defaultRSQLQueryFieldKeys.compactMap { ComputerField.keyLookup[$0] }

                        do {
                            let defaultResults = try await requestAllInventoryPages(
                                sections: resolvedSections(from: defaultFields),
                                query: trimmedQuery,
                                fields: defaultFields,
                                useWildcardFilter: false,
                                displayFields: defaultFields
                            )

                            searchResults = await resolvePrestageEnrollment(for: defaultResults, query: trimmedQuery)
                            errorMessage = nil
                            reportEvent(
                                severity: .warning,
                                category: "search",
                                message: "Computer search completed using default-field fallback.",
                                metadata: [
                                    "result_count": String(searchResults.count),
                                    "has_query": "true",
                                    "field_count": String(defaultFields.count)
                                ]
                            )
                            return
                        } catch {
                            self.errorMessage = describe(error)
                            reportError(
                                category: "search",
                                message: "Computer search failed after all fallback strategies.",
                                errorDescription: describe(error),
                                metadata: [
                                    "has_query": "true",
                                    "field_count": String(activeFields.count)
                                ]
                            )
                            return
                        }
                    }

                    self.errorMessage = describe(error)
                    reportError(
                        category: "search",
                        message: "Computer search failed after exact-match fallback.",
                        errorDescription: describe(error),
                        metadata: [
                            "has_query": "true",
                            "field_count": String(activeFields.count)
                        ]
                    )
                    return
                }
            }

            let description = describe(error)
            errorMessage = userFacingSearchErrorMessage(for: error)
            reportError(
                category: "search",
                message: "Computer search failed.",
                errorDescription: description,
                metadata: [
                    "has_query": trimmedQuery.isEmpty ? "false" : "true",
                    "field_count": String(activeFields.count),
                    "section_count": String(sections.count)
                ]
            )
        }
    }

    // MARK: - API Request Construction

    /// Issues inventory requests across all endpoint versions (v3 -> v2 -> v1), returning
    /// the first successful response. If a version fails with a privilege error, it retries
    /// that version with a minimal fallback field set before moving on.
    ///
    /// - Parameters:
    ///   - sections: The inventory sections to request.
    ///   - query: The user's trimmed search string.
    ///   - fields: The resolved catalog fields to use for RSQL filtering.
    ///   - useWildcardFilter: Whether to wrap the query in wildcards for contains-style matching.
    /// - Returns: The raw response `Data` from the first successful endpoint.
    /// - Throws: The last error encountered if all versions fail.
    /// Fetches ONE page of computer inventory. Version-fallback aware: tries
    /// v3 → v2 → v1 until one returns a page, and retries with minimum-section
    /// / default-fields on privilege denial. Returns raw JSON bytes for the
    /// page so the caller can decode incrementally.
    private func requestInventory(
        sections: [ComputerInventorySection],
        query: String,
        fields: [ComputerField],
        useWildcardFilter: Bool,
        page: Int = 0
    ) async throws -> Data {
        var lastError: (any Error)?

        for endpointVersion in ComputerInventoryEndpointVersion.allCases {
            // Filter sections to only those supported by this API version
            let versionSections = sections
                .filter { endpointVersion.supportedSections.contains($0) }
                .sorted { $0.rawValue < $1.rawValue }

            do {
                return try await requestInventory(
                    endpointVersion: endpointVersion,
                    sections: versionSections,
                    query: query,
                    fields: fields,
                    useWildcardFilter: useWildcardFilter,
                    page: page
                )
            } catch {
                lastError = error

                // On privilege errors, try again with minimal fields before giving up on this version
                if isInvalidPrivilegeError(error) {
                    do {
                        return try await requestInventory(
                            endpointVersion: endpointVersion,
                            sections: [],
                            query: query,
                            fields: privilegeFallbackFields(),
                            useWildcardFilter: false,
                            page: page
                        )
                    } catch {
                        lastError = error
                    }
                }

                // Only try the next version for retryable status codes (400, 403, 404)
                if shouldTryNextEndpointVersion(for: error) == false {
                    throw error
                }
            }
        }

        throw lastError ?? JamfFrameworkError.authenticationFailed
    }

    /// Stop predicate for the inventory pagination loops, delegating to the
    /// shared `JamfPaginationPolicy` with this module's page size. Exposed as a
    /// pure, `nonisolated` seam so `ComputerSearchPaginationTests` can assert the
    /// short-page / empty-page / safety-cap behavior without a live gateway.
    nonisolated static func shouldStopPaginating(pageRecordCount: Int, page: Int) -> Bool {
        JamfPaginationPolicy.shouldStop(
            pageRecordCount: pageRecordCount,
            page: page,
            pageSize: computerInventoryPageSize,
            safetyPageLimit: JamfPaginationPolicy.safetyPageLimit
        )
    }

    /// Orders the basic-search filter keys so the core identity fields are searched
    /// first and can never be dropped by the condition cap, then appends any additional
    /// selected display fields (de-duplicated). Falls back to `fallbackKeys` only when
    /// both inputs are empty. Exposed as a pure, `nonisolated` seam so the
    /// identity-first / cap / de-dup contract — the guarantee that "search by username"
    /// works under any profile — can be unit-tested without a live gateway.
    nonisolated static func prioritizedFilterFieldKeys(
        identityKeys: [String],
        candidateKeys: [String],
        fallbackKeys: [String],
        cap: Int
    ) -> [String] {
        var ordered: [String] = []
        for key in identityKeys + candidateKeys where ordered.contains(key) == false {
            ordered.append(key)
        }
        return Array((ordered.isEmpty ? fallbackKeys : ordered).prefix(cap))
    }

    /// Loops `requestInventory` across pages until a page returns fewer
    /// records than the page size (the standard Jamf "last page" signal).
    /// Decodes each page into `[ComputerRecord]` and accumulates.
    ///
    /// Previously the app requested only page 0, which silently truncated any
    /// search returning more than `computerInventoryPageSize` records — a
    /// false-negative search bug on tenants with large fleets.
    ///
    /// - Parameters identical to single-page `requestInventory` except `page`.
    /// - Returns: Combined decoded records across all pages.
    private func requestAllInventoryPages(
        sections: [ComputerInventorySection],
        query: String,
        fields: [ComputerField],
        useWildcardFilter: Bool,
        displayFields: [ComputerField]
    ) async throws -> [ComputerRecord] {
        var allRecords: [ComputerRecord] = []
        var page = 0

        while true {
            let data = try await requestInventory(
                sections: sections,
                query: query,
                fields: fields,
                useWildcardFilter: useWildcardFilter,
                page: page
            )
            let pageRecords = try decodeSearchResults(from: data, displayFields: displayFields)
            allRecords.append(contentsOf: pageRecords)

            // Delegates the end-of-results / safety-cap decision to the shared,
            // unit-tested `JamfPaginationPolicy` (via `shouldStopPaginating`).
            // The predicate is evaluated at the current page index, mirroring
            // the previous inline `page += 1` then `page >= cap` ordering.
            if Self.shouldStopPaginating(pageRecordCount: pageRecords.count, page: page) {
                // A full page that still trips the predicate can only mean the
                // safety cap fired — no single technician search should
                // legitimately pull this many pages. Warn so we don't silently
                // drop results under a runaway loop. A short/empty page is the
                // normal end-of-results and stops without a warning.
                if pageRecords.count >= Self.computerInventoryPageSize {
                    reportEvent(
                        severity: .warning,
                        category: "search",
                        message: "Computer search paginated to safety cap of \(JamfPaginationPolicy.safetyPageLimit) pages (\(JamfPaginationPolicy.safetyPageLimit * Self.computerInventoryPageSize) records); stopping. Narrow the query if more results are expected.",
                        metadata: [
                            "accumulated_count": String(allRecords.count),
                            "page_size": String(Self.computerInventoryPageSize)
                        ]
                    )
                }
                break
            }

            page += 1
        }

        return allRecords
    }

    // MARK: - Advanced Search Execution

    /// Runs a search composed by the Advanced Search sheet.
    ///
    /// The composer's `serverFilter` is sent verbatim to Jamf via the same
    /// version-fallback pagination pipeline that `executeSearch` uses.
    /// `clientCriteria` (entries the server can't filter — fields whose
    /// `isServerFilterable == false`) are applied in-memory after the usual
    /// prestage enrichment. The `referencedSections` are unioned with the
    /// active profile's sections so the response carries every value the
    /// post-filter pass needs to evaluate.
    ///
    /// Unlike `executeSearch`, this path does NOT auto-rewrite to exact-match
    /// on a 400 response. Wildcard semantics in advanced search are authored by
    /// the user; silently swapping operators would change the meaning of their
    /// criteria. Failures surface a clean message via the error banner so the
    /// user can correct the query (the RSQL grammar is never shown).
    func executeAdvancedSearch(
        _ composeResult: JamfRSQLComposer.ComputerComposeResult,
        fieldKeys: Set<String>
    ) async {
        isSearching = true
        decodingNoticeMessage = nil
        defer { isSearching = false }

        if fieldKeys.isEmpty == false {
            selectedFieldKeys = fieldKeys
        }

        let selectedKeys = selectedProfile?.fieldKeys ?? Array(selectedFieldKeys).sorted()
        let activeFields = resolvedCatalogFields(from: selectedKeys)
        let baseSections = Set(resolvedSections(from: activeFields))
        let unionedSections = Array(baseSections.union(composeResult.referencedSections))
            .sorted { $0.rawValue < $1.rawValue }

        do {
            let rawResults = try await requestAllInventoryPagesWithRawFilter(
                sections: unionedSections,
                rawFilter: composeResult.serverFilter,
                displayFields: activeFields
            )

            // Resolve prestage enrollment exactly as executeSearch does so the
            // result rows render the Pre-Stage column and any client criterion
            // referencing a prestage field has a value to match against.
            let enriched = await resolvePrestageEnrollment(for: rawResults, query: "")
            let postFiltered = applyClientCriteria(composeResult.clientCriteria, to: enriched)
            searchResults = postFiltered
            errorMessage = nil

            reportEvent(
                severity: .info,
                category: "advancedSearch",
                message: "Advanced computer search completed.",
                metadata: [
                    "result_count": String(postFiltered.count),
                    // Presence + length only — never the raw RSQL, which
                    // embeds user-typed values (serials, usernames, …).
                    "server_filter_present": composeResult.serverFilter == nil ? "false" : "true",
                    "server_filter_length": String(composeResult.serverFilter?.count ?? 0),
                    "client_criteria_count": String(composeResult.clientCriteria.count),
                    "field_count": String(activeFields.count),
                    "section_count": String(unionedSections.count)
                ]
            )
        } catch {
            let description = describe(error)
            errorMessage = userFacingSearchErrorMessage(for: error)
            reportError(
                category: "advancedSearch",
                message: "Advanced computer search failed.",
                errorDescription: description,
                metadata: [
                    "server_filter_present": composeResult.serverFilter == nil ? "false" : "true",
                    "server_filter_length": String(composeResult.serverFilter?.count ?? 0),
                    "field_count": String(activeFields.count),
                    "section_count": String(unionedSections.count)
                ]
            )
        }
    }

    /// Pagination wrapper mirroring `requestAllInventoryPages` but taking a
    /// pre-composed RSQL filter string (instead of building one from a
    /// query+wildcard pair). Reuses the same v3 → v2 → v1 version-fallback
    /// chain and the same end-of-results / safety-cap logic.
    private func requestAllInventoryPagesWithRawFilter(
        sections: [ComputerInventorySection],
        rawFilter: String?,
        displayFields: [ComputerField]
    ) async throws -> [ComputerRecord] {
        var allRecords: [ComputerRecord] = []
        var page = 0

        while true {
            let data = try await requestInventoryWithRawFilter(
                sections: sections,
                rawFilter: rawFilter,
                page: page
            )
            let pageRecords = try decodeSearchResults(from: data, displayFields: displayFields)
            allRecords.append(contentsOf: pageRecords)

            // Same shared stop predicate as the query-based loop; see
            // `requestAllInventoryPages` for the full-page vs short-page
            // rationale behind the safety-cap warning.
            if Self.shouldStopPaginating(pageRecordCount: pageRecords.count, page: page) {
                if pageRecords.count >= Self.computerInventoryPageSize {
                    reportEvent(
                        severity: .warning,
                        category: "advancedSearch",
                        message: "Advanced computer search paginated to safety cap of \(JamfPaginationPolicy.safetyPageLimit) pages (\(JamfPaginationPolicy.safetyPageLimit * Self.computerInventoryPageSize) records); stopping. Narrow the query if more results are expected.",
                        metadata: [
                            "accumulated_count": String(allRecords.count),
                            "page_size": String(Self.computerInventoryPageSize)
                        ]
                    )
                }
                break
            }

            page += 1
        }
        return allRecords
    }

    /// Single page fetch using a raw RSQL filter, version-fallback aware.
    /// Tries v3 → v2 → v1 until one returns a page, and retries the current
    /// version with no sections on a privilege denial (the usual cause is a
    /// section the API client can't read). Mirrors the query-based
    /// `requestInventory(sections:query:…)` fallback shape.
    private func requestInventoryWithRawFilter(
        sections: [ComputerInventorySection],
        rawFilter: String?,
        page: Int = 0
    ) async throws -> Data {
        var lastError: (any Error)?

        for endpointVersion in ComputerInventoryEndpointVersion.allCases {
            let versionSections = sections
                .filter { endpointVersion.supportedSections.contains($0) }
                .sorted { $0.rawValue < $1.rawValue }

            do {
                return try await requestInventoryWithRawFilter(
                    endpointVersion: endpointVersion,
                    sections: versionSections,
                    rawFilter: rawFilter,
                    page: page
                )
            } catch {
                lastError = error

                if isInvalidPrivilegeError(error) {
                    do {
                        return try await requestInventoryWithRawFilter(
                            endpointVersion: endpointVersion,
                            sections: [],
                            rawFilter: rawFilter,
                            page: page
                        )
                    } catch {
                        lastError = error
                    }
                }

                if shouldTryNextEndpointVersion(for: error) == false {
                    throw error
                }
            }
        }

        throw lastError ?? JamfFrameworkError.authenticationFailed
    }

    /// Builds and issues a single raw-filter inventory request for a specific
    /// endpoint version. Identical query-parameter construction to the
    /// query-based variant except the `filter` value is the opaque RSQL string
    /// rather than one assembled from the user's free-text query.
    private func requestInventoryWithRawFilter(
        endpointVersion: ComputerInventoryEndpointVersion,
        sections: [ComputerInventorySection],
        rawFilter: String?,
        page: Int = 0
    ) async throws -> Data {
        var queryItems: [URLQueryItem] = [
            URLQueryItem(name: "page", value: String(page)),
            URLQueryItem(name: "page-size", value: String(Self.computerInventoryPageSize)),
            URLQueryItem(name: "sort", value: "general.name:asc")
        ]

        for section in sections {
            queryItems.append(URLQueryItem(name: "section", value: section.rawValue))
        }

        if let rawFilter, rawFilter.isEmpty == false {
            queryItems.append(URLQueryItem(name: "filter", value: rawFilter))
        }

        return try await apiGateway.request(
            path: endpointVersion.path,
            method: .get,
            queryItems: queryItems
        )
    }

    // MARK: - Extension Attributes

    /// Fetches the tenant's computer extension attribute list and merges it into
    /// `extensionAttributes` (and therefore `allCatalogFields`).
    ///
    /// Tries the documented Modern API path first; if that's unsupported on the
    /// user's Jamf Pro version, falls back to v1, then to the Classic API.
    /// Failure is reported to diagnostics but doesn't surface a fatal error —
    /// search still works against built-in fields, and a retry happens whenever
    /// the user reopens the module. `extensionAttributeLoadError` holds the last
    /// error only if every variant failed, so a successful fallback doesn't leave
    /// a stale error visible.
    func loadExtensionAttributes() async {
        defer { hasAttemptedExtensionAttributeLoad = true }

        let attempts: [(label: String, fetch: () async throws -> [ComputerExtensionAttribute])] = [
            ("api/v2/computer-extension-attributes", { try await self.fetchModernExtensionAttributes(version: "v2") }),
            ("api/v1/computer-extension-attributes", { try await self.fetchModernExtensionAttributes(version: "v1") }),
            ("JSSResource/computerextensionattributes", { try await self.fetchClassicExtensionAttributes() })
        ]

        var lastError: String?
        for attempt in attempts {
            do {
                let loaded = try await attempt.fetch()
                extensionAttributes = loaded.sorted {
                    $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
                }
                extensionAttributeLoadError = nil
                reportEvent(
                    severity: .info,
                    category: "extensionAttributes",
                    message: "Loaded computer extension attributes.",
                    metadata: [
                        "ea_count": String(extensionAttributes.count),
                        "endpoint": attempt.label
                    ]
                )
                return
            } catch {
                let description = describe(error)
                lastError = "\(attempt.label) — \(description)"
                reportEvent(
                    severity: .warning,
                    category: "extensionAttributes",
                    message: "Extension attribute fetch attempt failed.",
                    metadata: [
                        "endpoint": attempt.label,
                        "error": description
                    ]
                )
            }
        }

        extensionAttributeLoadError = lastError ?? "Unknown error"
        reportError(
            category: "extensionAttributes",
            message: "Failed to load computer extension attributes from any endpoint.",
            errorDescription: lastError ?? "Unknown"
        )
    }

    /// Fetches EAs from a Modern API endpoint with pagination. `version` selects
    /// between `v1` and `v2`. Same 50-page safety cap as inventory pagination.
    private func fetchModernExtensionAttributes(version: String) async throws -> [ComputerExtensionAttribute] {
        var all: [ComputerExtensionAttribute] = []
        var page = 0
        let pageSize = 200

        while true {
            let queryItems = [
                URLQueryItem(name: "page", value: String(page)),
                URLQueryItem(name: "page-size", value: String(pageSize))
            ]
            let data = try await apiGateway.request(
                path: "api/\(version)/computer-extension-attributes",
                method: .get,
                queryItems: queryItems
            )

            let pageResults = try decodeExtensionAttributePage(data: data)
            all.append(contentsOf: pageResults)

            // Shared stop predicate (see `shouldStopPaginating`); the EA list
            // endpoint uses its own page size but the same safety cap.
            if JamfPaginationPolicy.shouldStop(
                pageRecordCount: pageResults.count,
                page: page,
                pageSize: pageSize,
                safetyPageLimit: JamfPaginationPolicy.safetyPageLimit
            ) {
                if pageResults.count >= pageSize {
                    reportEvent(
                        severity: .warning,
                        category: "extensionAttributes",
                        message: "Modern extension attribute pagination hit safety cap.",
                        metadata: ["accumulated": String(all.count), "version": version]
                    )
                }
                break
            }
            page += 1
        }
        return all
    }

    /// Fetches EAs from the Classic API. The Classic list endpoint returns just
    /// `{id, name}` per entry — full metadata (data type, input type, popup
    /// choices) would need an N+1 detail fetch per EA. For usability we accept
    /// the lightweight list and treat every EA as a `string` data type with text
    /// input; the client matcher is permissive about value shape, so
    /// integer/date EAs still match.
    private func fetchClassicExtensionAttributes() async throws -> [ComputerExtensionAttribute] {
        let data = try await apiGateway.request(
            path: "JSSResource/computerextensionattributes",
            method: .get,
            queryItems: []
        )

        struct ClassicEntry: Decodable {
            let id: Int
            let name: String
        }
        struct ClassicWrapper: Decodable {
            let computer_extension_attributes: [ClassicEntry]
        }

        let decoder = JSONDecoder()
        let wrapper = try decoder.decode(ClassicWrapper.self, from: data)
        return wrapper.computer_extension_attributes.map { entry in
            ComputerExtensionAttribute(
                id: String(entry.id),
                name: entry.name,
                description: nil,
                dataType: .string,
                inputType: .text,
                popupChoices: nil
            )
        }
    }

    /// Decodes either of the two response shapes the Modern API uses:
    /// 1) Wrapper: `{"results": [...], "totalCount": N}`
    /// 2) Bare array at the top level (older builds)
    ///
    /// Throws when neither shape decodes — the fallback chain in
    /// `loadExtensionAttributes` relies on a thrown error to advance to the next
    /// endpoint. Swallowing the failure with `?? []` would make a
    /// 200-with-malformed-payload look like a successful empty result and
    /// short-circuit the v2 → v1 → Classic fallback.
    private func decodeExtensionAttributePage(data: Data) throws -> [ComputerExtensionAttribute] {
        let decoder = JSONDecoder()
        if let wrapper = try? decoder.decode(ExtensionAttributePageWrapper.self, from: data) {
            return wrapper.results
        }
        if let bareArray = try? decoder.decode([ComputerExtensionAttribute].self, from: data) {
            return bareArray
        }
        throw JamfFrameworkError.decodingFailure
    }

    private struct ExtensionAttributePageWrapper: Decodable {
        let results: [ComputerExtensionAttribute]
    }

    // MARK: - Detail Refresh

    /// Targeted single-computer fetch backing `ComputerDetailView`. Re-runs the
    /// same v3 → v2 → v1 inventory pipeline filtered to this one record across
    /// the detail sections (GENERAL, HARDWARE, STORAGE, OPERATING_SYSTEM,
    /// SECURITY, DISK_ENCRYPTION, USER_AND_LOCATION, EXTENSION_ATTRIBUTES), then
    /// merges the freshly decoded values into the matching `searchResults` row so
    /// the detail view's binding picks them up. The wider section set feeds the
    /// hardware card, the security indicator grid, and the Extension Attributes
    /// panel — all of which the narrower search profile may not have requested.
    ///
    /// Merges rather than replaces: a detail fetch sometimes returns a narrower
    /// payload than the original search row (or a tenant's privileges trim a
    /// section), and a wholesale replacement would discard fields the search
    /// response already populated. `ComputerRecord.merging(_:)` keeps every
    /// populated field from either source — refresh values win on collision,
    /// existing row values win where the refresh is empty — and guards record
    /// identity so a synthetic fallback id can't overwrite the real Jamf id the
    /// detail route looks up.
    ///
    /// Synthetic prestage-scope rows carry composite ids (not a Jamf numeric id)
    /// and have no live inventory detail to fetch, so they're skipped.
    func refreshComputerHardware(id: String) async throws {
        // Only genuine inventory records (numeric Jamf id) can be re-fetched via
        // an `id==` filter. Scope-only synthetic rows have nothing to refresh.
        // The numeric guard also means the value interpolated into the RSQL
        // filter is pure digits — no quoting/escaping required.
        guard Int(id) != nil else { return }

        let detailSections: Set<ComputerInventorySection> = [
            .general, .hardware, .storage, .operatingSystem,
            .security, .diskEncryption, .userAndLocation, .extensionAttributes
        ]
        let detailFields = ComputerField.catalog.filter { detailSections.contains($0.section) }
        let sections = Array(detailSections)

        let refreshedRecords = try await requestAllInventoryPagesWithRawFilter(
            sections: sections,
            rawFilter: "id==\(id)",
            displayFields: detailFields
        )

        guard let refreshed = refreshedRecords.first(where: { $0.id == id }) ?? refreshedRecords.first else {
            // No inventory row returned (deleted device, or the id filter isn't
            // honored on this tenant). Keep the cached row; the detail view
            // shows a soft notice rather than blanking the screen.
            reportEvent(
                severity: .warning,
                category: "detailRefresh",
                message: "Computer hardware refresh returned no inventory record.",
                metadata: ["has_match": "false"]
            )
            return
        }

        guard let index = searchResults.firstIndex(where: { $0.id == id }) else {
            // The row scrolled out of the result set; nothing to merge into.
            return
        }

        let existing = searchResults[index]
        let merged = existing.merging(refreshed)
        searchResults[index] = merged

        // Presence/counts only — never the raw hardware payload, serials, or
        // user fields. Enough to answer "did the refresh reach the card?".
        reportEvent(
            severity: .info,
            category: "detailRefresh",
            message: "Merged single-computer detail into search-result row.",
            metadata: [
                "existing_field_count": String(existing.fieldValues.filter { $0.value.isEmpty == false }.count),
                "refreshed_field_count": String(refreshed.fieldValues.filter { $0.value.isEmpty == false }.count),
                "merged_field_count": String(merged.fieldValues.filter { $0.value.isEmpty == false }.count),
                "merged_has_model_identifier": merged.modelIdentifier == nil ? "false" : "true",
                "merged_has_total_storage": merged.totalStorageMb == nil ? "false" : "true",
                "merged_has_ram": merged.totalRamMb == nil ? "false" : "true",
                "merged_has_battery": merged.batteryCapacityPercent == nil ? "false" : "true"
            ]
        )
    }

    // MARK: - Client-Side Criteria

    /// Applies in-memory criteria over enriched results. Each criterion is
    /// matched against the record's `value(for:)` lookup using the same
    /// case-insensitive semantics the server uses for RSQL strings.
    private func applyClientCriteria(
        _ criteria: [AdvancedQueryCriterion],
        to records: [ComputerRecord]
    ) -> [ComputerRecord] {
        guard criteria.isEmpty == false else { return records }
        return records.filter { record in
            criteria.allSatisfy { matches(criterion: $0, record: record) }
        }
    }

    /// Lowercased substring/prefix/suffix/equality semantics for client-side
    /// criterion matching. Numeric / date / boolean operators are best-effort:
    /// the client filter only receives fields whose `isServerFilterable` is
    /// false, which in the computer catalog are string-typed. If a future
    /// non-string client-only field is added, extend this switch.
    private func matches(criterion: AdvancedQueryCriterion, record: ComputerRecord) -> Bool {
        let recordValue = (record.value(for: criterion.fieldKey) ?? "").lowercased()

        switch criterion.op {
        case .equals:
            if case .string(let value) = criterion.value { return recordValue == value.lowercased() }
        case .notEquals:
            if case .string(let value) = criterion.value { return recordValue != value.lowercased() }
        case .contains:
            if case .string(let value) = criterion.value { return recordValue.contains(value.lowercased()) }
        case .notContains:
            if case .string(let value) = criterion.value { return recordValue.contains(value.lowercased()) == false }
        case .startsWith:
            if case .string(let value) = criterion.value { return recordValue.hasPrefix(value.lowercased()) }
        case .endsWith:
            if case .string(let value) = criterion.value { return recordValue.hasSuffix(value.lowercased()) }
        case .includedIn:
            if case .list(let values) = criterion.value {
                let lowered = values.map { $0.lowercased() }
                return lowered.contains(recordValue)
            }
        case .excludedFrom:
            if case .list(let values) = criterion.value {
                let lowered = values.map { $0.lowercased() }
                return lowered.contains(recordValue) == false
            }
        default:
            return true
        }
        return true
    }

    /// Builds and issues a single inventory API request for a specific endpoint version.
    ///
    /// Constructs query parameters for pagination, section selection, sorting, and RSQL filtering,
    /// then delegates to the API gateway for the authenticated HTTP call.
    ///
    /// - Parameters:
    ///   - endpointVersion: Which API version path to target (v1, v2, or v3).
    ///   - sections: The inventory sections to include as query parameters.
    ///   - query: The user's search string.
    ///   - fields: The catalog fields used to construct the RSQL filter.
    ///   - useWildcardFilter: Whether to wrap the query value in `*` wildcards.
    /// - Returns: The raw response `Data`.
    /// - Throws: Network or authentication errors from the API gateway.
    /// Page size used when fetching computer inventory search results.
    /// Set to 200 to balance response size against Jamf's recommended ≤ 5
    /// concurrent connection posture — larger pages mean fewer round trips.
    nonisolated private static let computerInventoryPageSize = 200

    private func requestInventory(
        endpointVersion: ComputerInventoryEndpointVersion,
        sections: [ComputerInventorySection],
        query: String,
        fields: [ComputerField],
        useWildcardFilter: Bool,
        page: Int = 0
    ) async throws -> Data {
        var queryItems: [URLQueryItem] = [
            URLQueryItem(name: "page", value: String(page)),
            URLQueryItem(name: "page-size", value: String(Self.computerInventoryPageSize)),
            URLQueryItem(name: "sort", value: "general.name:asc")
        ]

        // Append each requested section as a separate query parameter
        for section in sections {
            queryItems.append(URLQueryItem(name: "section", value: section.rawValue))
        }

        // Build the RSQL filter expression from the query and allowed fields
        let allowedSections = sections.isEmpty
            ? Set(ComputerInventorySection.allCases)
            : Set(sections)
        if query.isEmpty == false,
           let filter = buildFilterExpression(
               for: query,
               fields: fields,
               useWildcard: useWildcardFilter,
               allowedSections: allowedSections
           )
        {
            queryItems.append(URLQueryItem(name: "filter", value: filter))
        }

        return try await apiGateway.request(
            path: endpointVersion.path,
            method: .get,
            queryItems: queryItems
        )
    }

    // MARK: - Field & Section Resolution

    /// Resolves the user's selected field keys into full `ComputerField` objects from the catalog.
    ///
    /// Resolves against `mergedFieldLookup` (built-in catalog + tenant Extension
    /// Attributes) so a selected synthetic `cea_<id>` column resolves to its
    /// field and surfaces in result rows and section scoping. Falls back to the
    /// default RSQL query fields if the selection is empty or none of the
    /// selected keys match entries in the catalog.
    ///
    /// - Parameter selectedKeys: The sorted array of field key strings from the active profile.
    /// - Returns: An array of `ComputerField` instances ready for filter construction.
    private func resolvedCatalogFields(from selectedKeys: [String]) -> [ComputerField] {
        if selectedKeys.isEmpty {
            return ComputerField.defaultRSQLQueryFieldKeys.compactMap { ComputerField.keyLookup[$0] }
        }

        let lookup = mergedFieldLookup
        let resolved = selectedKeys.compactMap { lookup[$0] }
        if resolved.isEmpty {
            return ComputerField.defaultRSQLQueryFieldKeys.compactMap { ComputerField.keyLookup[$0] }
        }

        return resolved
    }

    /// Derives the set of inventory sections needed to satisfy the given fields.
    ///
    /// Always includes `.general` since it contains core identification fields.
    /// The resulting array is sorted by raw value for deterministic query parameter ordering.
    ///
    /// - Parameter fields: The resolved catalog fields for the current search.
    /// - Returns: A sorted array of unique inventory sections.
    private func resolvedSections(from fields: [ComputerField]) -> [ComputerInventorySection] {
        var sections = Set(fields.map(\.section))
        sections.insert(.general)
        return sections.sorted { $0.rawValue < $1.rawValue }
    }

    // MARK: - RSQL Filter Construction

    /// Builds an RSQL filter expression string from the user's query and the active fields.
    ///
    /// Only fields that support RSQL search, belong to an allowed section, and are in the
    /// supported filter key set are included. If no candidate fields produce valid conditions,
    /// a fallback set of basic fields is tried. The conditions are OR-joined (comma-separated
    /// in RSQL syntax) and wrapped in parentheses.
    ///
    /// - Parameters:
    ///   - query: The user's search string.
    ///   - fields: The resolved catalog fields.
    ///   - useWildcard: Whether to wrap the value in `*` wildcards.
    ///   - allowedSections: The sections that were requested in the API call.
    /// - Returns: An RSQL filter string, or `nil` if no valid conditions could be built.
    private func buildFilterExpression(
        for query: String,
        fields: [ComputerField],
        useWildcard: Bool,
        allowedSections: Set<ComputerInventorySection>
    ) -> String? {
        let candidateKeys = fields
            .filter { field in
                field.supportsRSQLSearch &&
                allowedSections.contains(field.section) &&
                supportedInventoryFilterKeys.contains(field.key)
            }
            .map(\.key)

        // Always search the core identity fields (name, serial, username, email, …)
        // regardless of which columns the active profile selects, so "search by
        // username" works under any profile — mirrors the Support Technician module's
        // fixed identity filter rather than scoping the filter to display columns.
        let identityKeys = privilegeFallbackFilterFieldKeys.filter { key in
            guard let field = ComputerField.keyLookup[key] else { return false }
            return allowedSections.contains(field.section) &&
                supportedInventoryFilterKeys.contains(field.key)
        }

        // Identity keys first so the 12-condition cap can never drop them.
        let prioritizedKeys = Self.prioritizedFilterFieldKeys(
            identityKeys: identityKeys,
            candidateKeys: candidateKeys,
            fallbackKeys: privilegeFallbackFilterFieldKeys,
            cap: 12
        )
        let conditions = filterConditions(
            for: prioritizedKeys,
            query: query,
            useWildcard: useWildcard
        )

        if conditions.isEmpty == false {
            return "(\(conditions.joined(separator: ",")))"
        }

        // If the candidate fields produced nothing, try the privilege fallback keys
        if candidateKeys.isEmpty == false {
            let fallbackConditions = filterConditions(
                for: Array(privilegeFallbackFilterFieldKeys.prefix(12)),
                query: query,
                useWildcard: useWildcard
            )

            if fallbackConditions.isEmpty == false {
                return "(\(fallbackConditions.joined(separator: ",")))"
            }
        }

        return nil
    }

    /// Returns the minimal set of `ComputerField` instances used when the API rejects
    /// the primary field set due to insufficient privileges.
    private func privilegeFallbackFields() -> [ComputerField] {
        privilegeFallbackFilterFieldKeys.compactMap { ComputerField.keyLookup[$0] }
    }

    // MARK: - Response Decoding

    /// Decodes raw API response data into an array of `ComputerRecord` instances.
    ///
    /// First attempts to decode as a `ComputerSearchResponse` (wrapped format), then falls
    /// back to decoding as a bare `[ComputerRecord]` array. Reports diagnostics for both
    /// the primary error and any fallback errors.
    ///
    /// - Parameter data: The raw JSON response data.
    /// - Returns: An array of decoded computer records.
    /// - Throws: `JamfFrameworkError.decodingFailure` if neither format succeeds.
    private func decodeSearchResults(
        from data: Data,
        displayFields: [ComputerField]
    ) throws -> [ComputerRecord] {
        var primaryError: (any Error)?
        var typedRecords: [ComputerRecord]?

        do {
            let payload = try decoder.decode(ComputerSearchResponse.self, from: data)
            typedRecords = payload.results
        } catch {
            primaryError = error
        }

        // Fallback: try decoding as a bare array (some endpoints omit the wrapper)
        if typedRecords == nil {
            do {
                let records = try decoder.decode([ComputerRecord].self, from: data)
                reportEvent(
                    severity: .warning,
                    category: "decoding",
                    message: "Computer search results decoded using fallback format.",
                    metadata: ["primary_error": describe(primaryError!)]
                )
                decodingNoticeMessage = "Search succeeded, but the server response used an older format. Results may be incomplete; consider updating the Jamf Pro server."
                typedRecords = records
            } catch {
                reportError(
                    category: "decoding",
                    message: "Failed to decode computer search results.",
                    errorDescription: describe(primaryError!),
                    metadata: ["fallback_error": describe(error)]
                )
                throw JamfFrameworkError.decodingFailure
            }
        }

        guard let records = typedRecords else {
            throw JamfFrameworkError.decodingFailure
        }

        // Layer dynamic `fieldValues` onto the typed records so result rows and
        // the detail view can render arbitrary user-selected columns. The typed
        // Decodable pass (above) is preserved verbatim — this only adds data, so
        // pagination, prestage resolution, and the bare-array fallback are
        // unaffected.
        return enrichWithFieldValues(records, from: data, displayFields: displayFields)
    }

    /// Attaches dynamically-parsed `fieldValues` to each typed record by re-parsing
    /// the same response bytes as loosely-typed dictionaries and index-zipping them
    /// onto the decoded records.
    ///
    /// If the raw dictionary count doesn't match the typed record count (an
    /// unexpected wrapper, or the bare-array fallback fired on a shape we don't
    /// recognize), enrichment is skipped rather than risk zipping values onto the
    /// wrong record — the typed records still render via `value(for:)`'s
    /// first-class fallbacks.
    private func enrichWithFieldValues(
        _ records: [ComputerRecord],
        from data: Data,
        displayFields: [ComputerField]
    ) -> [ComputerRecord] {
        guard records.isEmpty == false else {
            return records
        }

        guard let rawDictionaries = rawRecordDictionaries(from: data),
              rawDictionaries.count == records.count
        else {
            return records
        }

        return zip(records, rawDictionaries).map { record, dictionary in
            let extracted = extractFieldValues(from: dictionary, displayFields: displayFields)
            return extracted.isEmpty ? record : record.withFieldValues(extracted)
        }
    }

    /// Builds the `fieldValues` dictionary for one raw record by resolving each
    /// display field's `responsePaths`, then unconditionally resolving a small set
    /// of hardware/storage "display-essential" keys so the hardware card and inline
    /// storage gauge populate even when the active column profile doesn't request
    /// them. Explicitly-selected fields win on key collisions (resolved first).
    private func extractFieldValues(
        from dictionary: [String: Any],
        displayFields: [ComputerField]
    ) -> [String: String] {
        var fieldValues: [String: String] = [:]

        for field in displayFields {
            if let resolved = extractValue(using: field.responsePaths, from: dictionary),
               resolved.isEmpty == false
            {
                fieldValues[field.key] = resolved
            }
        }

        for key in Self.displayEssentialFieldKeys {
            if fieldValues[key] != nil { continue }
            guard let field = ComputerField.keyLookup[key] else { continue }
            if let resolved = extractValue(using: field.responsePaths, from: dictionary),
               resolved.isEmpty == false
            {
                fieldValues[key] = resolved
            }
        }

        extractExtensionAttributeValues(from: dictionary, into: &fieldValues)

        return fieldValues
    }

    /// Flattens the inventory response's Extension Attribute arrays into
    /// `cea_<id>` keys on `fieldValues`, so synthetic EA fields resolve through
    /// `ComputerRecord.value(for:)` just like first-class fields.
    ///
    /// Computer inventory returns EAs as a top-level `extensionAttributes` array
    /// (the EXTENSION_ATTRIBUTES section), but some versions also mirror them
    /// under individual section objects. Each entry identifies its definition by
    /// `definitionId` on modern builds or `id` on older ones, and carries the
    /// value as a `values` array (multi-value EAs) or a scalar `value`. First
    /// write wins, so an explicitly-selected column value is never clobbered.
    private func extractExtensionAttributeValues(
        from dictionary: [String: Any],
        into fieldValues: inout [String: String]
    ) {
        let scanLocations: [Any?] = [
            dictionary["extensionAttributes"],
            (dictionary["general"] as? [String: Any])?["extensionAttributes"],
            (dictionary["hardware"] as? [String: Any])?["extensionAttributes"],
            (dictionary["operatingSystem"] as? [String: Any])?["extensionAttributes"],
            (dictionary["userAndLocation"] as? [String: Any])?["extensionAttributes"],
            (dictionary["purchasing"] as? [String: Any])?["extensionAttributes"],
            (dictionary["security"] as? [String: Any])?["extensionAttributes"]
        ]

        for location in scanLocations {
            guard let array = location as? [[String: Any]] else { continue }
            for eaDict in array {
                let rawID: String?
                if let definitionID = eaDict["definitionId"] as? Int {
                    rawID = String(definitionID)
                } else if let definitionID = eaDict["definitionId"] as? String,
                          definitionID.isEmpty == false
                {
                    rawID = definitionID
                } else if let intValue = eaDict["id"] as? Int {
                    rawID = String(intValue)
                } else if let stringValue = eaDict["id"] as? String,
                          stringValue.isEmpty == false
                {
                    rawID = stringValue
                } else {
                    rawID = nil
                }

                guard let eaID = rawID else { continue }
                let key = ComputerExtensionAttribute.keyPrefix + eaID
                guard fieldValues[key] == nil else { continue } // first wins

                // EA value is an array of strings in modern responses, a single
                // scalar in older shapes. Try the common shapes in order.
                let formatted: String?
                if let valueArray = eaDict["values"] as? [Any] {
                    formatted = stringifyEAArray(valueArray)
                } else if let valueArray = eaDict["value"] as? [Any] {
                    formatted = stringifyEAArray(valueArray)
                } else if let single = eaDict["value"] as? String, single.isEmpty == false {
                    formatted = single
                } else if let intValue = eaDict["value"] as? Int {
                    formatted = String(intValue)
                } else if let dblValue = eaDict["value"] as? Double {
                    formatted = String(dblValue)
                } else if let boolValue = eaDict["value"] as? Bool {
                    formatted = boolValue ? "true" : "false"
                } else {
                    formatted = nil
                }

                if let formatted, formatted.isEmpty == false {
                    fieldValues[key] = formatted
                }
            }
        }
    }

    /// Joins an EA value array into a single comma-separated string for in-memory
    /// matching and display. Multi-value EAs come from LDAP-fed or script
    /// attributes. Empty entries are dropped.
    private func stringifyEAArray(_ array: [Any]) -> String? {
        let parts: [String] = array.compactMap { element in
            if let s = element as? String { return s }
            if let i = element as? Int { return String(i) }
            if let d = element as? Double { return String(d) }
            if let b = element as? Bool { return b ? "true" : "false" }
            return nil
        }
        let joined = parts
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { $0.isEmpty == false }
            .joined(separator: ", ")
        return joined.isEmpty ? nil : joined
    }

    /// Hardware/storage field keys that back the result-row gauge and the detail
    /// hardware card. Always extracted regardless of the active column profile so
    /// these visuals populate from data already present in the response payload.
    private static let displayEssentialFieldKeys = [
        "hardware.model",
        "hardware.modelIdentifier",
        "hardware.processorType",
        "hardware.coreCount",
        "hardware.totalRamMegabytes",
        "hardware.batteryCapacityPercent",
        "hardware.appleSilicon",
        "storage.totalSizeMegabytes",
        "storage.bootDriveAvailableSpaceMegabytes",
        "storage.percentUsed"
    ]

    /// Re-parses the response bytes as a loosely-typed array of record dictionaries,
    /// mirroring `ComputerSearchResponse`'s wrapper-key priority (`results` →
    /// `computers` → `items`) so the array order matches the typed decode for
    /// index-zipped enrichment. Falls back to a top-level array (the bare-array
    /// decode shape) and finally the generic `dictionaryArray` unwrapper.
    private func rawRecordDictionaries(from data: Data) -> [[String: Any]]? {
        guard let json = try? JSONSerialization.jsonObject(with: data) else {
            return nil
        }

        if let wrapper = json as? [String: Any] {
            for key in ["results", "computers", "items"] {
                if let array = wrapper[key] as? [[String: Any]] {
                    return array
                }
            }
        }

        if let topLevelArray = json as? [[String: Any]] {
            return topLevelArray
        }

        return dictionaryArray(from: json)
    }

    /// Tries each dot-separated path in order, returning the first non-empty string
    /// value found.
    private func extractValue(using paths: [String], from dictionary: [String: Any]) -> String? {
        for path in paths {
            guard let resolved = resolveValue(atPath: path, in: dictionary),
                  let stringValue = extractString(from: resolved)
            else {
                continue
            }

            return stringValue
        }

        return nil
    }

    /// Resolves a dot-separated key path against a JSON dictionary, traversing nested
    /// objects and arrays. When a component lands on an array, the next component is
    /// mapped across all elements; if those elements are themselves arrays they are
    /// flattened one level first, so doubly-nested inventory paths such as
    /// `storage.disks.partitions.percentUsed` (disks[] → partitions[]) resolve
    /// instead of dead-ending at the inner array.
    private func resolveValue(atPath path: String, in dictionary: [String: Any]) -> Any? {
        let components = path
            .split(separator: ".")
            .map(String.init)

        guard components.isEmpty == false else {
            return nil
        }

        var current: Any = dictionary
        for component in components {
            if let currentDictionary = current as? [String: Any] {
                guard let next = currentDictionary[component] else {
                    return nil
                }
                current = next
                continue
            }

            if let currentArray = current as? [Any] {
                // Flatten one level of array nesting before mapping the key so
                // disks[].partitions[] style paths don't dead-end on the inner array.
                let flattened = currentArray.flatMap { element -> [Any] in
                    if let nestedArray = element as? [Any] {
                        return nestedArray
                    }
                    return [element]
                }

                let mappedValues = flattened.compactMap { element -> Any? in
                    (element as? [String: Any])?[component]
                }

                guard mappedValues.isEmpty == false else {
                    return nil
                }

                current = mappedValues.count == 1 ? mappedValues[0] : mappedValues
                continue
            }

            return nil
        }

        return current
    }

    // MARK: - PreStage Enrollment Resolution

    /// Enriches search results with PreStage enrollment information gathered from separate API endpoints.
    ///
    /// For each record, this method cross-references the serial number against prestage scope
    /// assignments to populate the enrollment status, profile name, and profile ID. It also
    /// appends "scope-only" records for serials that appear in prestage scopes but not in
    /// the inventory results (devices awaiting enrollment).
    ///
    /// - Parameters:
    ///   - records: The decoded computer records from the inventory search.
    ///   - query: The original search query, used to find additional scope matches.
    /// - Returns: The enriched array of computer records.
    private func resolvePrestageEnrollment(
        for records: [ComputerRecord],
        query: String
    ) async -> [ComputerRecord] {
        let normalizedQuerySerial = normalizeSerial(query)
        let inventorySerials = Set(records.compactMap { normalizeSerial($0.serialNumber) })
        let scopeAssociations = await fetchComputerPrestageScopeAssociations(
            targetSerials: inventorySerials,
            querySerial: normalizedQuerySerial
        )

        var resolvedRecords: [ComputerRecord] = []
        resolvedRecords.reserveCapacity(records.count + scopeAssociations.count)
        var existingSerials = Set<String>()

        for record in records {
            let normalizedSerial = normalizeSerial(record.serialNumber)
            if let normalizedSerial {
                existingSerials.insert(normalizedSerial)
            }

            // Look up the prestage scope association for this serial
            let association = normalizedSerial.flatMap { scopeAssociations[$0] }
            let resolvedRecord = await resolvePrestageEnrollment(for: record, scopeAssociation: association)
            resolvedRecords.append(resolvedRecord)
        }

        // Append scope-only records for serials found in prestage scopes but not in inventory
        if let normalizedQuerySerial {
            let scopeOnlyAssociations = scopeAssociations.values
                .filter { association in
                    existingSerials.contains(association.serialNumber) == false &&
                        association.serialNumber.contains(normalizedQuerySerial)
                }
                .sorted { $0.serialNumber < $1.serialNumber }

            for association in scopeOnlyAssociations {
                resolvedRecords.append(makeScopeOnlyRecord(from: association))
            }
        }

        return resolvedRecords
    }

    /// Resolves prestage enrollment details for a single computer record.
    ///
    /// Merges data from the record's own fields with scope association data, and performs
    /// a name lookup for profile IDs that lack a display name.
    ///
    /// - Parameters:
    ///   - record: The computer record to enrich.
    ///   - scopeAssociation: The scope association for this serial, if one exists.
    /// - Returns: An updated record with resolved prestage fields.
    private func resolvePrestageEnrollment(
        for record: ComputerRecord,
        scopeAssociation: ComputerPrestageScopeAssociation?
    ) async -> ComputerRecord {
        let resolvedStatus = normalizePrestageStatus(record.prestageEnrollmentStatus) ?? enrolledStatusLabel
        var resolvedName = normalizePrestageComponent(record.prestageEnrollmentProfileName)
        var resolvedID = normalizePrestageComponent(record.prestageEnrollmentProfileID)

        // Supplement missing data from the scope association
        if let scopeAssociation {
            resolvedName = resolvedName ?? scopeAssociation.profileName
            resolvedID = resolvedID ?? scopeAssociation.profileID
        }

        // If we have an ID but no name, look up the profile name via API
        if resolvedName == nil, let resolvedID, resolvedID.isEmpty == false {
            resolvedName = await resolveComputerPrestageName(forProfileID: resolvedID)
        }

        return record.withPrestageEnrollment(
            status: resolvedStatus,
            profileName: resolvedName,
            profileID: resolvedID
        )
    }

    /// Creates a synthetic computer record for a device that exists in a prestage scope
    /// but was not found in the inventory search results.
    ///
    /// These records use the serial number as the computer name and display "Not Enrolled"
    /// status, since the device has not yet enrolled through its assigned prestage profile.
    ///
    /// - Parameter association: The scope association containing the serial, profile ID, and profile name.
    /// - Returns: A `ComputerRecord` representing the scope-only device.
    private func makeScopeOnlyRecord(from association: ComputerPrestageScopeAssociation) -> ComputerRecord {
        ComputerRecord(
            id: "prestage-scope-\(association.serialNumber)-\(association.profileID)",
            computerName: association.serialNumber,
            serialNumber: association.serialNumber,
            udid: nil,
            model: nil,
            modelIdentifier: nil,
            osVersion: nil,
            osBuild: nil,
            lastIpAddress: nil,
            username: nil,
            email: nil,
            assetTag: nil,
            departmentID: nil,
            buildingID: nil,
            prestageEnrollmentStatus: notEnrolledStatusLabel,
            prestageEnrollmentProfileName: association.profileName,
            prestageEnrollmentProfileID: association.profileID
        )
    }

    // MARK: - PreStage API Integration

    /// Fetches scope associations for all prestage profiles, mapping serial numbers to their
    /// assigned prestage profile ID and name.
    ///
    /// Iterates through all computer prestages and their scope assignments, collecting
    /// associations for serials that match either the inventory results or the query serial.
    /// Errors on individual prestage scopes are logged but do not halt the overall resolution.
    ///
    /// - Parameters:
    ///   - targetSerials: Serial numbers from the inventory search results.
    ///   - querySerial: The normalized query string treated as a potential serial number.
    /// - Returns: A dictionary keyed by normalized serial number.
    private func fetchComputerPrestageScopeAssociations(
        targetSerials: Set<String>,
        querySerial: String?
    ) async -> [String: ComputerPrestageScopeAssociation] {
        guard targetSerials.isEmpty == false || querySerial != nil else {
            return [:]
        }

        do {
            let prestages = try await fetchAllComputerPrestages()
            var associations: [String: ComputerPrestageScopeAssociation] = [:]

            try await withThrowingTaskGroup(of: (String, String, Set<String>).self) { group in
                var inFlight = 0
                for prestage in prestages {
                    if inFlight >= 5 {
                        if let (profileID, profileName, scopedSerials) = try await group.next() {
                            for serial in scopedSerials {
                                let matchesTarget = targetSerials.contains(serial)
                                let matchesQuery = querySerial.map { serial.contains($0) } ?? false
                                guard matchesTarget || matchesQuery else { continue }
                                if associations[serial] == nil {
                                    associations[serial] = ComputerPrestageScopeAssociation(
                                        serialNumber: serial,
                                        profileID: profileID,
                                        profileName: profileName
                                    )
                                }
                            }
                        }
                        inFlight -= 1
                    }
                    group.addTask {
                        let serials = try await self.fetchComputerPrestageScopeSerials(forPrestageID: prestage.id)
                        return (prestage.id, prestage.name, serials)
                    }
                    inFlight += 1
                }
                for try await (profileID, profileName, scopedSerials) in group {
                    for serial in scopedSerials {
                        let matchesTarget = targetSerials.contains(serial)
                        let matchesQuery = querySerial.map { serial.contains($0) } ?? false
                        guard matchesTarget || matchesQuery else { continue }
                        if associations[serial] == nil {
                            associations[serial] = ComputerPrestageScopeAssociation(
                                serialNumber: serial,
                                profileID: profileID,
                                profileName: profileName
                            )
                        }
                    }
                }
            }

            return associations
        } catch {
            let description = describe(error)
            await diagnosticsReporter.reportError(
                source: moduleSource,
                category: "prestage",
                message: "Failed reading computer pre-stage inventory.",
                errorDescription: description
            )
            return [:]
        }
    }

    /// Prestage API versions to try, in order of preference.
    ///
    /// Jamf Pro 11.26+ serves `computer-prestages` at `/api/v3`; older servers
    /// used `/api/v2` and `/api/v1`. Falling back across versions keeps the
    /// feature working regardless of the server's major version.
    private static let computerPrestageAPIVersions: [String] = ["api/v3", "api/v2", "api/v1"]

    /// Sends a prestage request trying v3 → v2 → v1 in turn, falling back when
    /// a version responds with 400/403/404/405 (i.e. the version isn't available).
    ///
    /// - Parameters:
    ///   - subpath: The path fragment after `computer-prestages` (may be empty or start with `/`).
    ///   - queryItems: Optional query parameters applied to every attempt.
    /// - Returns: The raw response data from the first version that succeeds.
    private func prestageRequest(
        subpath: String,
        queryItems: [URLQueryItem] = []
    ) async throws -> Data {
        var lastError: (any Error)?

        for version in Self.computerPrestageAPIVersions {
            let path: String
            if subpath.isEmpty {
                path = "\(version)/computer-prestages"
            } else if subpath.hasPrefix("/") {
                path = "\(version)/computer-prestages\(subpath)"
            } else {
                path = "\(version)/computer-prestages/\(subpath)"
            }

            do {
                return try await apiGateway.request(
                    path: path,
                    method: .get,
                    queryItems: queryItems
                )
            } catch {
                lastError = error

                if isPrestageVersionUnavailable(error: error) {
                    continue
                }

                throw error
            }
        }

        throw lastError ?? JamfFrameworkError.authenticationFailed
    }

    /// Returns `true` when the error signals the prestage API at this
    /// version is absent, which is the signal to try the next version.
    /// Thin wrapper around the shared `Error.matchesJamf(status:)` helper.
    private func isPrestageVersionUnavailable(error: any Error) -> Bool {
        error.matchesJamf(status: 400, 403, 404, 405)
    }

    /// Fetches all computer prestage profiles using paginated requests.
    ///
    /// Deduplicates by profile ID and stops when a page returns fewer items than the page size,
    /// returns an empty page, or yields no new unique IDs.
    ///
    /// - Returns: An array of prestage summaries (ID + name).
    private func fetchAllComputerPrestages() async throws -> [ComputerPrestageSummary] {
        let pageSize = 100
        var page = 0
        var prestages: [ComputerPrestageSummary] = []
        var seenIDs = Set<String>()
        var totalFetched = 0

        while true {
            let data = try await prestageRequest(
                subpath: "",
                queryItems: [
                    URLQueryItem(name: "page", value: String(page)),
                    URLQueryItem(name: "page-size", value: String(pageSize))
                ]
            )

            // Extract totalCount from the response envelope
            let totalCount: Int? = {
                guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let count = json["totalCount"] as? Int else { return nil }
                return count
            }()

            let pagePrestages = parseComputerPrestageSummaries(from: data)
            let uniquePrestages = pagePrestages.filter { seenIDs.insert($0.id).inserted }
            prestages.append(contentsOf: uniquePrestages)
            totalFetched += pagePrestages.count

            // Stop when the page is empty, under-full, entirely duplicates, or we've fetched all items
            if pagePrestages.isEmpty || pagePrestages.count < pageSize || uniquePrestages.isEmpty {
                break
            }
            if let totalCount, totalFetched >= totalCount {
                break
            }

            page += 1
        }

        return prestages
    }

    /// Fetches the set of serial numbers scoped to a specific prestage profile, using pagination.
    ///
    /// Serial numbers are normalized (trimmed, uppercased) and deduplicated across pages.
    ///
    /// - Parameter prestageID: The ID of the prestage profile to query.
    /// - Returns: A set of normalized serial numbers.
    private func fetchComputerPrestageScopeSerials(forPrestageID prestageID: String) async throws -> Set<String> {
        let pageSize = 100
        var page = 0
        var serials = Set<String>()

        while true {
            let data = try await prestageRequest(
                subpath: "\(prestageID)/scope",
                queryItems: [
                    URLQueryItem(name: "page", value: String(page)),
                    URLQueryItem(name: "page-size", value: String(pageSize))
                ]
            )

            let pageSerials = parseComputerScopeSerials(from: data)
            let previousCount = serials.count
            serials.formUnion(pageSerials.compactMap(normalizeSerial))
            let appendedCount = serials.count - previousCount

            // Stop when the page is empty, under-full, or added no new serials
            if pageSerials.isEmpty || pageSerials.count < pageSize || appendedCount == 0 {
                break
            }

            page += 1
        }

        return serials
    }

    // MARK: - JSON Parsing Helpers (Prestage)

    /// Parses prestage summary objects from raw JSON data, trying multiple known response formats.
    ///
    /// The Jamf Pro prestage API may wrap results in `results`, `prestages`, `computerPrestages`,
    /// `items`, or `data` keys. This method tries each in order, then falls back to scanning
    /// all dictionary values for arrays of objects that look like prestage summaries.
    ///
    /// - Parameter data: Raw JSON data from the prestages endpoint.
    /// - Returns: An array of parsed summaries, or empty if parsing fails.
    private func parseComputerPrestageSummaries(from data: Data) -> [ComputerPrestageSummary] {
        let jsonObject: Any
        do {
            jsonObject = try JSONSerialization.jsonObject(with: data)
        } catch {
            reportError(category: "prestage", message: "Failed to parse computer prestage summaries JSON.", errorDescription: describe(error))
            return []
        }

        if let dictionary = jsonObject as? [String: Any] {
            // Try well-known array key names first
            let candidateArrays: [Any?] = [
                dictionary["results"],
                dictionary["prestages"],
                dictionary["computerPrestages"],
                dictionary["items"],
                dictionary["data"]
            ]

            for candidate in candidateArrays {
                guard let objects = dictionaryArray(from: candidate), objects.isEmpty == false else {
                    continue
                }

                let parsed = objects.compactMap(parseComputerPrestageSummary(from:))
                if parsed.isEmpty == false {
                    return parsed
                }
            }

            // Scan all values for any array that contains parseable summaries
            for nestedValue in dictionary.values {
                guard let objects = dictionaryArray(from: nestedValue), objects.isEmpty == false else {
                    continue
                }

                let parsed = objects.compactMap(parseComputerPrestageSummary(from:))
                if parsed.isEmpty == false {
                    return parsed
                }
            }
        }

        // Try parsing the root as a bare array
        guard let objects = dictionaryArray(from: jsonObject) else {
            return []
        }

        return objects.compactMap(parseComputerPrestageSummary(from:))
    }

    /// Extracts a prestage summary from a single JSON dictionary object.
    ///
    /// Requires at least an `id` (or `prestageId`) field. The display name is resolved from
    /// `displayName`, `name`, or `profileName`, falling back to `"Pre-Stage <id>"`.
    ///
    /// - Parameter item: A dictionary representing a single prestage profile.
    /// - Returns: A summary, or `nil` if no ID could be extracted.
    private func parseComputerPrestageSummary(from item: [String: Any]) -> ComputerPrestageSummary? {
        guard let id = extractString(from: item["id"]) ?? extractString(from: item["prestageId"]) else {
            return nil
        }

        let name =
            extractString(from: item["displayName"]) ??
            extractString(from: item["name"]) ??
            extractString(from: item["profileName"]) ??
            "Pre-Stage \(id)"

        return ComputerPrestageSummary(id: id, name: name)
    }

    /// Parses serial numbers from a prestage scope API response, handling multiple JSON formats.
    ///
    /// Tries extracting from `assignments`, `results`, `devices`, `computers`, `items`, and `data`
    /// arrays, then falls back to flat `serialNumbers` arrays or bare object/string arrays.
    ///
    /// - Parameter data: Raw JSON data from the prestage scope endpoint.
    /// - Returns: An array of serial number strings.
    private func parseComputerScopeSerials(from data: Data) -> [String] {
        let jsonObject: Any
        do {
            jsonObject = try JSONSerialization.jsonObject(with: data)
        } catch {
            reportError(category: "prestage", message: "Failed to parse computer scope serials JSON.", errorDescription: describe(error))
            return []
        }

        if let dictionary = jsonObject as? [String: Any] {
            // Try known object-array keys containing individual assignment records
            let objectCandidates: [Any?] = [
                dictionary["assignments"],
                dictionary["results"],
                dictionary["devices"],
                dictionary["computers"],
                dictionary["items"],
                dictionary["data"]
            ]

            for candidate in objectCandidates {
                guard let objects = dictionaryArray(from: candidate), objects.isEmpty == false else {
                    continue
                }

                let serials = objects.compactMap(parseComputerScopeSerial(from:))
                if serials.isEmpty == false {
                    return serials
                }
            }

            // Scan all values for parseable arrays
            for nestedValue in dictionary.values {
                guard let objects = dictionaryArray(from: nestedValue), objects.isEmpty == false else {
                    continue
                }

                let serials = objects.compactMap(parseComputerScopeSerial(from:))
                if serials.isEmpty == false {
                    return serials
                }
            }

            // Try flat string arrays under known keys
            if let serialNumbers =
                extractStringArray(from: dictionary["serialNumbers"]) ??
                extractStringArray(from: (dictionary["assignments"] as? [String: Any])?["serialNumbers"])
            {
                return serialNumbers.compactMap(normalizeSerial)
            }
        }

        // Try parsing as a bare array of objects or strings
        if let objects = dictionaryArray(from: jsonObject), objects.isEmpty == false {
            return objects.compactMap(parseComputerScopeSerial(from:))
        }

        if let serialNumbers = extractStringArray(from: jsonObject) {
            return serialNumbers.compactMap(normalizeSerial)
        }

        return []
    }

    /// Extracts a serial number from a single scope assignment dictionary.
    ///
    /// Checks `serialNumber`, `serial`, and `hardwareSerialNumber` keys directly, then
    /// looks inside nested objects (`computer`, `device`, `inventoryRecord`, etc.), and
    /// finally performs a fuzzy key-fragment search for any key containing "serial".
    ///
    /// - Parameter item: A dictionary representing a single scope assignment.
    /// - Returns: A normalized serial number string, or `nil`.
    private func parseComputerScopeSerial(from item: [String: Any]) -> String? {
        var serial =
            extractString(from: item["serialNumber"]) ??
            extractString(from: item["serial"]) ??
            extractString(from: item["hardwareSerialNumber"])

        // Check nested objects that might contain the serial
        let nestedKeys = ["computer", "device", "inventoryRecord", "inventory", "item"]
        for key in nestedKeys {
            guard let nested = item[key] as? [String: Any] else {
                continue
            }

            serial = serial ??
                extractString(from: nested["serialNumber"]) ??
                extractString(from: nested["serial"])
        }

        // Last resort: fuzzy search for any key containing "serial"
        if serial == nil {
            serial = extractValue(matching: "serial", in: item)
        }

        return normalizeSerial(serial)
    }

    /// Resolves the display name of a prestage profile by its ID, using an in-memory cache
    /// to avoid redundant API calls within the same search session.
    ///
    /// - Parameter profileID: The prestage profile ID to look up.
    /// - Returns: The profile's display name, or `nil` if the lookup fails.
    private func resolveComputerPrestageName(forProfileID profileID: String) async -> String? {
        if let cached = computerPrestageNameCache[profileID] {
            return cached
        }

        do {
            let profileData = try await prestageRequest(subpath: profileID)

            if let profileName = extractProfileName(fromPrestageDetails: profileData) {
                computerPrestageNameCache[profileID] = profileName
                return profileName
            }
        } catch {
            let description = describe(error)
            await diagnosticsReporter.reportError(
                source: moduleSource,
                category: "prestage",
                message: "Failed reading computer pre-stage profile details.",
                errorDescription: description,
                metadata: [
                    "prestage_profile_id": profileID
                ]
            )
        }

        return nil
    }

    // MARK: - RSQL Filter Condition Builders

    /// Generates RSQL condition strings for each field key, matching the query value type
    /// (textual with optional wildcards, boolean literal, or numeric literal) to the field type.
    ///
    /// - Parameters:
    ///   - keys: The field keys to generate conditions for.
    ///   - query: The user's search string.
    ///   - useWildcard: Whether to wrap textual values in `*` wildcards.
    /// - Returns: An array of RSQL condition strings (e.g. `"general.name==\"*foo*\""`).
    private func filterConditions(
        for keys: [String],
        query: String,
        useWildcard: Bool
    ) -> [String] {
        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmedQuery.isEmpty == false else {
            return []
        }

        let escapedQuery = escapeRSQLString(trimmedQuery)
        let queryValue = useWildcard ? "*\(escapedQuery)*" : escapedQuery
        let booleanLiteral = booleanLiteral(from: trimmedQuery)
        let numericLiteral = numericLiteral(from: trimmedQuery)

        return keys.compactMap { key in
            // Match the query to the appropriate field type
            if textualInventoryFilterKeys.contains(key) {
                return "\(key)==\"\(queryValue)\""
            }

            if booleanInventoryFilterKeys.contains(key),
               let booleanLiteral
            {
                return "\(key)==\(booleanLiteral)"
            }

            if numericInventoryFilterKeys.contains(key),
               let numericLiteral
            {
                return "\(key)==\(numericLiteral)"
            }

            return nil
        }
    }

    /// Escapes backslashes and double quotes in a string for safe inclusion in RSQL expressions.
    private func escapeRSQLString(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
    }

    /// Converts a user query string to a boolean literal if it matches known truthy/falsy values.
    ///
    /// - Returns: `"true"` or `"false"`, or `nil` if the value is not boolean-like.
    private func booleanLiteral(from value: String) -> String? {
        switch value.lowercased() {
        case "true", "yes", "1":
            return "true"
        case "false", "no", "0":
            return "false"
        default:
            return nil
        }
    }

    /// Returns the value unchanged if it consists entirely of digits, otherwise `nil`.
    ///
    /// Used to detect when the query can be safely used as a numeric filter value.
    private func numericLiteral(from value: String) -> String? {
        guard value.isEmpty == false,
              value.allSatisfy({ $0.isNumber }) else {
            return nil
        }

        return value
    }

    // MARK: - Normalization Helpers

    /// Trims whitespace from a prestage component string, returning `nil` for blank values.
    private func normalizePrestageComponent(_ value: String?) -> String? {
        guard let value else {
            return nil
        }

        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    /// Normalizes raw prestage status values into canonical "Enrolled" / "Not Enrolled" labels.
    ///
    /// Handles boolean strings, management labels, and enrollment labels from the API.
    private func normalizePrestageStatus(_ value: String?) -> String? {
        guard let normalized = normalizePrestageComponent(value) else {
            return nil
        }

        switch normalized.lowercased() {
        case "true", "managed", "enrolled":
            return enrolledStatusLabel
        case "false", "unmanaged", "not enrolled":
            return notEnrolledStatusLabel
        default:
            if normalized.lowercased().contains("not enrolled") ||
                normalized.lowercased().contains("unmanaged")
            {
                return notEnrolledStatusLabel
            }

            if normalized.lowercased().contains("enrolled") ||
                normalized.lowercased().contains("managed")
            {
                return enrolledStatusLabel
            }

            return normalized
        }
    }

    /// Normalizes a serial number by trimming whitespace and converting to uppercase.
    ///
    /// Returns `nil` for blank or nil inputs, ensuring consistent comparison across sources.
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

    // MARK: - Generic JSON Extraction Utilities

    /// Attempts to extract an array of dictionaries from a loosely-typed JSON value.
    ///
    /// Handles direct arrays, arrays of `Any` with dictionary elements, and nested wrapper
    /// objects with known collection keys (`results`, `items`, `assignments`, etc.).
    private func dictionaryArray(from value: Any?) -> [[String: Any]]? {
        if let dictionaries = value as? [[String: Any]] {
            return dictionaries
        }

        if let array = value as? [Any] {
            let dictionaries = array.compactMap { $0 as? [String: Any] }
            return dictionaries.isEmpty ? nil : dictionaries
        }

        // Unwrap a single wrapper object
        if let dictionary = value as? [String: Any] {
            return
                dictionaryArray(from: dictionary["results"]) ??
                dictionaryArray(from: dictionary["items"]) ??
                dictionaryArray(from: dictionary["assignments"]) ??
                dictionaryArray(from: dictionary["devices"]) ??
                dictionaryArray(from: dictionary["computers"]) ??
                dictionaryArray(from: dictionary["data"])
        }

        return nil
    }

    /// Extracts a non-empty string from a loosely-typed JSON value.
    ///
    /// Handles strings, booleans, integers, doubles, NSNumber, nested dictionaries
    /// (trying `displayName`, `name`, `value`, `id`), and arrays (joining elements).
    private func extractString(from value: Any?) -> String? {
        switch value {
        case let stringValue as String:
            let trimmed = stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        case let boolValue as Bool:
            return boolValue ? "true" : "false"
        case let intValue as Int:
            return String(intValue)
        case let doubleValue as Double:
            return String(doubleValue)
        case let numberValue as NSNumber:
            return numberValue.stringValue
        case let dictionary as [String: Any]:
            return
                extractString(from: dictionary["displayName"]) ??
                extractString(from: dictionary["name"]) ??
                extractString(from: dictionary["value"]) ??
                extractString(from: dictionary["id"])
        case let array as [Any]:
            let flattened = array.compactMap { extractString(from: $0) }
                .filter { $0.isEmpty == false }
            return flattened.isEmpty ? nil : flattened.joined(separator: ", ")
        default:
            return nil
        }
    }

    /// Extracts an array of non-empty strings from a loosely-typed JSON value.
    ///
    /// Handles direct `[String]` arrays, `[Any]` arrays, and nested wrapper objects
    /// with known array keys (`serialNumbers`, `serials`, `items`, `values`).
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

    /// Recursively searches a dictionary for any key containing the given fragment and
    /// returns the first non-empty string value found.
    ///
    /// Used as a last-resort extraction strategy when the exact key name is unknown.
    private func extractValue(matching keyFragment: String, in dictionary: [String: Any]) -> String? {
        for (key, value) in dictionary {
            if key.localizedCaseInsensitiveContains(keyFragment),
               let extracted = extractString(from: value)
            {
                return extracted
            }

            // Recurse into nested dictionaries
            if let nestedDictionary = value as? [String: Any],
               let nestedValue = extractValue(matching: keyFragment, in: nestedDictionary)
            {
                return nestedValue
            }
        }

        return nil
    }

    /// Extracts a profile display name from raw prestage detail JSON data.
    ///
    /// Deserializes the data, then recursively searches for `displayName`, `name`, or `profileName`.
    private func extractProfileName(fromPrestageDetails data: Data) -> String? {
        let json: Any
        do {
            json = try JSONSerialization.jsonObject(with: data)
        } catch {
            reportError(category: "prestage", message: "Failed to parse prestage details JSON.", errorDescription: describe(error))
            return nil
        }

        return extractProfileName(from: json)
    }

    /// Recursively searches a JSON value tree for a profile name, trying `displayName`,
    /// `name`, and `profileName` at each dictionary level.
    private func extractProfileName(from value: Any) -> String? {
        if let dictionary = value as? [String: Any] {
            if let directName =
                extractString(from: dictionary["displayName"]) ??
                extractString(from: dictionary["name"]) ??
                extractString(from: dictionary["profileName"])
            {
                return directName
            }

            for nestedValue in dictionary.values {
                if let nestedName = extractProfileName(from: nestedValue) {
                    return nestedName
                }
            }
        }

        if let array = value as? [Any] {
            for element in array {
                if let nestedName = extractProfileName(from: element) {
                    return nestedName
                }
            }
        }

        return nil
    }

    // MARK: - Error Handling

    /// Extracts the localized description from an error, preferring `LocalizedError.errorDescription`.
    private func describe(_ error: any Error) -> String {
        (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
    }

    /// Returns a user-friendly error message for search failures.
    ///
    /// Provides a specific message for 403/INVALID_PRIVILEGE errors that guides the user
    /// to check their API role privileges.
    private func userFacingSearchErrorMessage(for error: any Error) -> String {
        if isInvalidPrivilegeError(error) {
            return "Computer search was denied by Jamf for at least one requested inventory section. Verify API Role privileges for Computer Inventory sections and Read Computers access."
        }

        return describe(error)
    }

    /// Checks whether an error is a 403 with an INVALID_PRIVILEGE body,
    /// indicating that the requested sections exceed the API client's
    /// privilege level (distinct from a generic 403).
    ///
    /// Combines the shared `isJamfInvalidPrivilege` status check with a
    /// body-content match. Kept inline because the "INVALID_PRIVILEGE"
    /// body match is specific to Jamf's privilege-denial response and
    /// isn't generalizable to other 403s that belong elsewhere in the
    /// fallback chain.
    private func isInvalidPrivilegeError(_ error: any Error) -> Bool {
        guard error.isJamfInvalidPrivilege else { return false }
        switch error {
        case let JamfFrameworkError.forbidden(message):
            return message.localizedCaseInsensitiveContains("INVALID_PRIVILEGE")
        case let JamfFrameworkError.networkFailure(_, message):
            return message.localizedCaseInsensitiveContains("INVALID_PRIVILEGE")
        default:
            return false
        }
    }

    /// Determines whether the next API endpoint version should be tried
    /// after a failure — 400/403/404. Thin wrapper around the shared
    /// `Error.matchesJamf(status:)` helper.
    private func shouldTryNextEndpointVersion(for error: any Error) -> Bool {
        error.matchesJamf(status: 400, 403, 404)
    }

    // MARK: - Diagnostics

    /// Sends a diagnostics event to the shared reporter asynchronously.
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

    /// Sends a diagnostics error to the shared reporter asynchronously.
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
