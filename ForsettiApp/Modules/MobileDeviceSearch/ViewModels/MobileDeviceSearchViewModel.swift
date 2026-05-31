import Foundation
import Combine

@MainActor
/// The view model driving the Mobile Device Search module.
///
/// `MobileDeviceSearchViewModel` coordinates between the UI layer and the Jamf Pro API
/// to perform inventory searches, manage saved search profiles, and resolve Pre-Stage
/// Enrollment data for each device record. It owns all published state consumed by
/// `MobileDeviceSearchView` and `FieldCatalogView`.
///
/// Key responsibilities:
/// - Executing mobile device inventory searches with automatic fallback strategies
///   (wildcard -> exact match, modern section names -> legacy -> no sections)
/// - Loading, saving, and deleting user-created search profiles via the profile store
/// - Resolving Pre-Stage Enrollment profile names and IDs by cross-referencing
///   the prestage scope API and individual prestage detail endpoints
/// - Parsing loosely-typed JSON responses that vary across Jamf Pro versions
final class MobileDeviceSearchViewModel: ObservableObject {

    /// A lightweight summary of a Pre-Stage Enrollment profile (ID + display name),
    /// used when enumerating all prestages to build scope associations.
    private struct MobilePrestageSummary: Sendable {
        let id: String
        let name: String
    }

    /// Associates a device serial number with the Pre-Stage Enrollment profile
    /// it is scoped to, as discovered by walking the prestage scope endpoints.
    private struct MobilePrestageScopeAssociation: Sendable {
        let serialNumber: String
        let profileID: String
        let profileName: String
    }

    // MARK: - Published UI State

    /// The user's current search query (serial number or username).
    @Published var query = ""

    /// All saved search profiles, sorted alphabetically by name.
    @Published private(set) var profiles: [MobileDeviceSearchProfile] = []

    /// The ID of the currently selected profile, or `nil` if no profile is active.
    @Published var selectedProfileID: UUID?

    /// The set of field keys currently toggled on, either from a profile or manual selection.
    @Published var selectedFieldKeys: Set<String> = []

    /// The device records returned by the most recent search.
    @Published private(set) var searchResults: [MobileDeviceRecord] = []

    /// Whether a search is currently in progress (drives the loading indicator).
    @Published private(set) var isSearching = false

    /// Controls presentation of the field catalog sheet.
    @Published var isFieldCatalogPresented = false

    /// Controls presentation of the Advanced Search sheet.
    @Published var isAdvancedSearchPresented = false

    /// Controls presentation of the "Save Profile" alert.
    @Published var isSaveProfilePromptPresented = false

    /// The text field value in the save-profile alert.
    @Published var pendingProfileName = ""

    /// All saved smart filters, sorted alphabetically.
    @Published private(set) var smartFilters: [SmartFilter] = []

    /// Mobile-device extension attributes published by the connected tenant.
    /// Empty until `loadExtensionAttributes()` succeeds; refreshed on the
    /// search view's `.task` block so users see EA criteria immediately when
    /// they open Advanced Search.
    @Published private(set) var extensionAttributes: [MobileDeviceExtensionAttribute] = []

    /// Last error from the most recent `loadExtensionAttributes()` attempt,
    /// or `nil` after a successful load. Surfaced in the Advanced Search
    /// field picker so the user can diagnose missing EAs without having to
    /// open the Diagnostics tab.
    @Published private(set) var extensionAttributeLoadError: String?

    /// Resolves to `true` once any EA load attempt has finished, regardless
    /// of outcome. Used by the picker to differentiate "haven't tried yet"
    /// from "tried and got zero EAs".
    @Published private(set) var hasAttemptedExtensionAttributeLoad: Bool = false

    /// A user-facing error message displayed in the UI, or `nil` when there is no error.
    @Published var errorMessage: String?

    // MARK: - Dependencies

    /// The API gateway used for all Jamf Pro network requests.
    private let apiGateway: JamfAPIGateway

    /// The diagnostics reporter for logging events and errors.
    private let diagnosticsReporter: any DiagnosticsReporting

    /// The persistence layer for loading and saving search profiles.
    private let profileStore: MobileDeviceSearchProfileStore

    /// The persistence layer for saved smart filters (Advanced Search queries).
    private let smartFilterStore: SmartFilterStore

    // MARK: - Constants

    /// The diagnostics source identifier for all events emitted by this module.
    private let moduleSource = "module.mobile-device-search"

    /// The field key used to identify Pre-Stage Enrollment profile data.
    private let prestageFieldKey = "prestageEnrollmentProfile"

    /// The RSQL filter key for serial number searches.
    private let serialSearchFilterKey = "serialNumber"

    /// The RSQL filter key for username searches.
    private let usernameSearchFilterKey = "username"

    /// The API sort field used to order results alphabetically by display name.
    private let sortFieldKey = "displayName"

    /// The query parameter name for inventory sections in the v2 API.
    private let sectionParameterName = "section"

    /// The error code returned by Jamf Pro when it rejects a section parameter type.
    private let sectionParameterTypeErrorCode = "INVALID_REQUEST_PARAMETER_TYPE"

    /// Display label for enrolled devices.
    private let enrolledStatusLabel = "Enrolled"

    /// Display label for non-enrolled devices.
    private let notEnrolledStatusLabel = "Not Enrolled"

    /// In-memory cache mapping prestage profile IDs to their display names,
    /// populated lazily to avoid redundant API calls for the same profile.
    private var prestageNameCache: [String: String] = [:]

    /// One-shot flag so we only emit the response-shape diagnostic for the
    /// first record decoded after each app launch. Lets us see what field
    /// names the user's Jamf Pro version actually returns without flooding
    /// the diagnostics log on every search result.
    private var hasLoggedResponseShape: Bool = false

    /// One-shot flag for the computed-deviceName diagnostic. Pairs with
    /// `hasLoggedResponseShape` so we get exactly one of each per session.
    private var hasLoggedNameFallback: Bool = false

    /// One-shot flag for the single-detail-endpoint response-shape diagnostic.
    /// The single endpoint can return a different shape than the list
    /// endpoint, so we capture both shapes once per session.
    private var hasLoggedSingleDetailShape: Bool = false

    /// Determines how inventory section parameters are encoded in API requests.
    /// The view model tries modern encoding first, then falls back to legacy names,
    /// then omits sections entirely if the server rejects both.
    private enum SectionEncodingMode {
        /// Uses the current Jamf Pro v2 section raw values (e.g. "USER_AND_LOCATION").
        case modern
        /// Uses legacy section names (e.g. "LOCATION") for older Jamf Pro versions.
        case legacy
        /// Omits section parameters entirely as a last-resort fallback.
        case none
    }

    /// Creates the view model with its required dependencies.
    ///
    /// - Parameters:
    ///   - apiGateway: The gateway for Jamf Pro API requests.
    ///   - diagnosticsReporter: The reporter for logging events and errors.
    ///   - profileStore: The store for persisting search profiles. Defaults to a new instance.
    init(
        apiGateway: JamfAPIGateway,
        diagnosticsReporter: any DiagnosticsReporting,
        profileStore: MobileDeviceSearchProfileStore = MobileDeviceSearchProfileStore(),
        smartFilterStore: SmartFilterStore = SmartFilterStore()
    ) {
        self.apiGateway = apiGateway
        self.diagnosticsReporter = diagnosticsReporter
        self.profileStore = profileStore
        self.smartFilterStore = smartFilterStore
    }

    // MARK: - Computed Properties

    /// The currently selected profile, if one exists and matches `selectedProfileID`.
    var selectedProfile: MobileDeviceSearchProfile? {
        guard let selectedProfileID else {
            return nil
        }

        return profiles.first(where: { $0.id == selectedProfileID })
    }

    /// The resolved list of `MobileDeviceField` objects for the active field selection,
    /// used by result rows to know which columns to display.
    var resultFields: [MobileDeviceField] {
        let selectedKeys = activeFieldKeys()
        return resolvedCatalogFields(from: selectedKeys)
    }

    // MARK: - Profile Management

    /// Loads saved profiles from the persistent store and sets the initial selection.
    ///
    /// Profiles are sorted alphabetically by name. If no profile was previously selected,
    /// the first profile in the sorted list is auto-selected. After loading, the selected
    /// profile's field keys are applied to `selectedFieldKeys`.
    func loadProfiles() async {
        do {
            let loaded = try await profileStore.loadProfiles()
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

    /// Copies the selected profile's field keys into `selectedFieldKeys`.
    ///
    /// Called whenever the selected profile changes to ensure the field catalog
    /// and result columns stay in sync with the active profile.
    func applySelectedProfileFields() {
        guard let selectedProfile else {
            return
        }

        selectedFieldKeys = Set(selectedProfile.fieldKeys)
    }

    /// Validates that fields are selected, then presents the save-profile naming prompt.
    ///
    /// If no fields are currently selected, an error message is shown instead and
    /// a warning diagnostic is reported.
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

    /// Saves a new profile (or updates an existing one with the same name) using
    /// the current field selection and the name entered in the prompt.
    ///
    /// If a profile with the same name already exists (case-insensitive match),
    /// its field keys are updated in place. Otherwise a new profile is created and
    /// appended to the list. The updated list is then persisted to disk.
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

        // Check for an existing profile with the same name (case-insensitive)
        if let index = profiles.firstIndex(where: { $0.name.localizedCaseInsensitiveCompare(profileName) == .orderedSame }) {
            profiles[index].fieldKeys = sortedFieldKeys
            selectedProfileID = profiles[index].id
        } else {
            let profile = MobileDeviceSearchProfile(name: profileName, fieldKeys: sortedFieldKeys)
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

    /// Deletes profiles at the given index set offsets and persists the change.
    ///
    /// If the currently selected profile is among those deleted, the selection
    /// falls back to the first remaining profile and its fields are applied.
    /// Deletion is persisted asynchronously in a background task.
    ///
    /// - Parameter offsets: The index set of profiles to remove, as provided by SwiftUI's `onDelete`.
    func deleteProfiles(at offsets: IndexSet) {
        // Remove in reverse order to keep indices stable during removal
        for index in offsets.sorted(by: >) {
            guard profiles.indices.contains(index) else {
                continue
            }
            profiles.remove(at: index)
        }

        // If the active profile was deleted, fall back to the first remaining profile
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
    /// the same (case-insensitive) name already exists. Persists synchronously
    /// before returning so the UI sees a consistent post-save state.
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

    /// Builds a fresh `AdvancedSearchViewModel` seeded from the current field
    /// selection. Sheet presentations call this so each open starts from the
    /// user's current column choices without retaining stale state.
    func makeAdvancedSearchViewModel(initialQuery: AdvancedQuery? = nil) -> AdvancedSearchViewModel {
        AdvancedSearchViewModel(
            initialQuery: initialQuery ?? AdvancedQuery(groups: [AdvancedQueryGroup()]),
            initialFieldKeys: selectedFieldKeys,
            availableFields: allCatalogFields,
            fieldLookup: mergedFieldLookup
        )
    }

    /// Loads a saved smart filter as the live state of the Advanced sheet
    /// AND applies its captured field columns to the result list. Returns
    /// the prepared sheet view model so the caller can present it.
    func loadSmartFilterIntoAdvancedSearch(_ filter: SmartFilter) -> AdvancedSearchViewModel {
        if filter.fieldKeys.isEmpty == false {
            selectedFieldKeys = Set(filter.fieldKeys)
        }
        return AdvancedSearchViewModel(
            initialQuery: filter.query,
            initialFieldKeys: selectedFieldKeys,
            availableFields: allCatalogFields,
            fieldLookup: mergedFieldLookup
        )
    }

    // MARK: - Extension Attributes

    /// The merged catalog: built-in `MobileDeviceField.catalog` + any
    /// EA-derived fields the tenant published. Recomputed each access so it
    /// always reflects the current `extensionAttributes` array.
    var allCatalogFields: [MobileDeviceField] {
        let extensionFields = extensionAttributes.map { $0.makeField() }
        return MobileDeviceField.catalog + extensionFields
    }

    /// Lookup dictionary over `allCatalogFields`. Used by the composer (so
    /// EA criteria resolve) and by the client-side matcher (so it can find
    /// the field's `key` to look up the value in the record's `fieldValues`).
    var mergedFieldLookup: [String: MobileDeviceField] {
        Dictionary(uniqueKeysWithValues: allCatalogFields.map { ($0.key, $0) })
    }

    /// Fetches the tenant's mobile-device extension attribute list.
    ///
    /// The endpoint is paginated. We follow pages until a partial page comes
    /// back, with the same 50-page safety cap the inventory pagination uses.
    /// Failure is reported to diagnostics but doesn't surface a user-facing
    /// error — Advanced Search still works against built-in fields, and a
    /// retry happens whenever the user reopens the module.
    func loadExtensionAttributes() async {
        defer { hasAttemptedExtensionAttributeLoad = true }

        // Try the documented Modern API path first; if that's unsupported on
        // the user's Jamf Pro version, fall back to v1, then to the Classic
        // API. We keep the LAST error in `extensionAttributeLoadError` only
        // if every variant failed — otherwise the user sees stale errors
        // even when EAs successfully loaded via a fallback.
        let attempts: [(label: String, fetch: () async throws -> [MobileDeviceExtensionAttribute])] = [
            ("api/v2/mobile-device-extension-attributes", { try await self.fetchModernExtensionAttributes(version: "v2") }),
            ("api/v1/mobile-device-extension-attributes", { try await self.fetchModernExtensionAttributes(version: "v1") }),
            ("JSSResource/mobiledeviceextensionattributes", { try await self.fetchClassicExtensionAttributes() })
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
                    message: "Loaded mobile-device extension attributes.",
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

        // All variants failed. Surface the last error to the picker.
        extensionAttributeLoadError = lastError ?? "Unknown error"
        reportError(
            category: "extensionAttributes",
            message: "Failed to load mobile-device extension attributes from any endpoint.",
            errorDescription: lastError ?? "Unknown"
        )
    }

    /// Fetches EAs from a Modern API endpoint with pagination.
    /// `version` selects between `v1` and `v2`.
    private func fetchModernExtensionAttributes(version: String) async throws -> [MobileDeviceExtensionAttribute] {
        var all: [MobileDeviceExtensionAttribute] = []
        var page = 0
        let pageSize = 200

        while true {
            let queryItems = [
                URLQueryItem(name: "page", value: String(page)),
                URLQueryItem(name: "page-size", value: String(pageSize))
            ]
            let data = try await apiGateway.request(
                path: "api/\(version)/mobile-device-extension-attributes",
                method: .get,
                queryItems: queryItems
            )

            let pageResults = try decodeExtensionAttributePage(data: data)
            all.append(contentsOf: pageResults)

            if pageResults.count < pageSize || pageResults.isEmpty {
                break
            }
            page += 1
            if page >= 50 {
                reportEvent(
                    severity: .warning,
                    category: "extensionAttributes",
                    message: "Modern extension attribute pagination hit safety cap.",
                    metadata: ["accumulated": String(all.count), "version": version]
                )
                break
            }
        }
        return all
    }

    /// Fetches EAs from the Classic API. The Classic list endpoint returns
    /// just `{id, name}` per entry — to get full metadata (data type, input
    /// type, popup choices) we'd need an N+1 detail fetch per EA. For
    /// usability we accept the lightweight list and treat every EA as a
    /// `string` data type with text input. Users can still query against
    /// them; integer/date EAs will work because the client matcher is
    /// permissive about value shape.
    private func fetchClassicExtensionAttributes() async throws -> [MobileDeviceExtensionAttribute] {
        let data = try await apiGateway.request(
            path: "JSSResource/mobiledeviceextensionattributes",
            method: .get,
            queryItems: []
        )

        struct ClassicEntry: Decodable {
            let id: Int
            let name: String
        }
        struct ClassicWrapper: Decodable {
            let mobile_device_extension_attributes: [ClassicEntry]
        }

        let decoder = JSONDecoder()
        let wrapper = try decoder.decode(ClassicWrapper.self, from: data)
        return wrapper.mobile_device_extension_attributes.map { entry in
            MobileDeviceExtensionAttribute(
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
    /// `loadExtensionAttributes` relies on a thrown error to advance to the
    /// next endpoint. Swallowing the failure with `?? []` would make a
    /// 200-with-malformed-payload look like a successful empty result and
    /// short-circuit the v2 → v1 → Classic fallback.
    private func decodeExtensionAttributePage(data: Data) throws -> [MobileDeviceExtensionAttribute] {
        let decoder = JSONDecoder()
        if let wrapper = try? decoder.decode(ExtensionAttributePageWrapper.self, from: data) {
            return wrapper.results
        }
        if let bareArray = try? decoder.decode([MobileDeviceExtensionAttribute].self, from: data) {
            return bareArray
        }
        throw JamfFrameworkError.decodingFailure
    }

    private struct ExtensionAttributePageWrapper: Decodable {
        let results: [MobileDeviceExtensionAttribute]
    }

    // MARK: - Search Execution

    /// Executes a mobile device inventory search against the Jamf Pro API.
    ///
    /// The search flow:
    /// 1. Determines which inventory sections and fields to request based on the active profile
    /// 2. Sends the initial API request with wildcard filtering
    /// 3. If the initial request fails with a 400 status, retries with exact-match filtering
    /// 4. Decodes the JSON response into `MobileDeviceRecord` instances
    /// 5. Optionally resolves Pre-Stage Enrollment data by querying prestage scope endpoints
    /// 6. Updates `searchResults` with the final resolved records
    ///
    /// All errors are caught, reported to diagnostics, and surfaced as user-facing messages.
    func executeSearch() async {
        isSearching = true
        defer { isSearching = false }

        let selectedKeys = activeFieldKeys()
        let activeFields = resolvedCatalogFields(from: selectedKeys)
        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let sections = resolvedSections(from: activeFields, includesQuery: trimmedQuery.isEmpty == false)

        // Prestage resolution is needed if the field is selected or a query is active
        let shouldResolvePrestage =
            activeFields.contains(where: { $0.key == prestageFieldKey }) ||
            trimmedQuery.isEmpty == false

        do {
            let decodedResults = try await requestAllInventoryPages(
                sections: sections,
                query: trimmedQuery,
                useWildcardFilter: true,
                requestedFields: activeFields
            )

            let resolvedResults: [MobileDeviceRecord]
            if shouldResolvePrestage {
                resolvedResults = await resolvePrestageEnrollmentProfiles(
                    for: decodedResults,
                    query: trimmedQuery
                )
            } else {
                resolvedResults = decodedResults
            }

            searchResults = resolvedResults
            errorMessage = nil
            reportEvent(
                severity: .info,
                category: "search",
                message: "Mobile device search completed.",
                metadata: [
                    "result_count": String(searchResults.count),
                    "has_query": trimmedQuery.isEmpty ? "false" : "true",
                    "field_count": String(activeFields.count),
                    "section_count": String(sections.count),
                    "prestage_requested": shouldResolvePrestage ? "true" : "false"
                ]
            )
        } catch {
            // If the wildcard search fails with 400 and a query was provided,
            // retry with an exact-match filter as a fallback. Uses the shared
            // status-matching helper so a typed `.networkFailure(400, _)`
            // reaches this path identically.
            if error.matchesJamf(status: 400),
               trimmedQuery.isEmpty == false
            {
                do {
                    let fallbackResults = try await requestAllInventoryPages(
                        sections: sections,
                        query: trimmedQuery,
                        useWildcardFilter: false,
                        requestedFields: activeFields
                    )

                    let resolvedResults: [MobileDeviceRecord]
                    if shouldResolvePrestage {
                        resolvedResults = await resolvePrestageEnrollmentProfiles(
                            for: fallbackResults,
                            query: trimmedQuery
                        )
                    } else {
                        resolvedResults = fallbackResults
                    }

                    searchResults = resolvedResults
                    errorMessage = nil
                    reportEvent(
                        severity: .warning,
                        category: "search",
                        message: "Mobile device search completed using exact-match fallback.",
                        metadata: [
                            "result_count": String(searchResults.count),
                            "has_query": "true",
                            "field_count": String(activeFields.count),
                            "section_count": String(sections.count),
                            "prestage_requested": shouldResolvePrestage ? "true" : "false"
                        ]
                    )
                    return
                } catch {
                    let description = describe(error)
                    errorMessage = userFacingSearchErrorMessage(for: error)
                    reportError(
                        category: "search",
                        message: "Mobile device search failed after exact-match fallback.",
                        errorDescription: description,
                        metadata: [
                            "has_query": "true",
                            "field_count": String(activeFields.count),
                            "section_count": String(sections.count),
                            "prestage_requested": shouldResolvePrestage ? "true" : "false"
                        ]
                    )
                    return
                }
            }

            let description = describe(error)
            errorMessage = userFacingSearchErrorMessage(for: error)
            reportError(
                category: "search",
                message: "Mobile device search failed.",
                errorDescription: description,
                metadata: [
                    "has_query": trimmedQuery.isEmpty ? "false" : "true",
                    "field_count": String(activeFields.count),
                    "section_count": String(sections.count),
                    "prestage_requested": shouldResolvePrestage ? "true" : "false"
                ]
            )
        }
    }

    // MARK: - Advanced Search Execution

    /// Runs a search composed by the Advanced Search sheet.
    ///
    /// The composer's `serverFilter` is sent verbatim to Jamf via the existing
    /// pagination pipeline. `clientCriteria` (entries the server cannot
    /// filter, e.g. Pre-Stage profile name) are applied in-memory after the
    /// usual prestage enrichment. The `referencedSections` are unioned with
    /// the active profile's sections so the response carries every value the
    /// post-filter pass needs to evaluate.
    ///
    /// Unlike `executeSearch`, this path does NOT auto-rewrite to exact-match
    /// on a 400 response. Wildcarding semantics in advanced search are
    /// authored by the user; silently swapping operators would change the
    /// meaning of their criteria. Failures surface the RSQL preview via the
    /// error banner so the user can correct the query.
    func executeAdvancedSearch(_ composeResult: JamfRSQLComposer.ComposeResult, fieldKeys: Set<String>) async {
        isSearching = true
        defer { isSearching = false }

        if fieldKeys.isEmpty == false {
            selectedFieldKeys = fieldKeys
        }

        let activeFields = resolvedCatalogFields(from: activeFieldKeys())
        let referencedSet = composeResult.referencedSections
        let baseSections = resolvedSections(from: activeFields, includesQuery: false)
        let unionedSections = Array(Set(baseSections).union(referencedSet))
            .sorted { $0.rawValue < $1.rawValue }

        // Force prestage resolution if any client criterion mentions the
        // prestage field. Without this the in-memory filter would always
        // see nil and drop every device.
        let mentionsPrestage = composeResult.clientCriteria
            .contains(where: { $0.fieldKey == prestageFieldKey })
        let shouldResolvePrestage = mentionsPrestage
            || activeFields.contains(where: { $0.key == prestageFieldKey })

        do {
            let rawResults = try await requestAllInventoryPagesWithRawFilter(
                sections: unionedSections,
                rawFilter: composeResult.serverFilter,
                requestedFields: activeFields
            )

            let enriched: [MobileDeviceRecord]
            if shouldResolvePrestage {
                enriched = await resolvePrestageEnrollmentProfiles(for: rawResults, query: "")
            } else {
                enriched = rawResults
            }

            let postFiltered = applyClientCriteria(composeResult.clientCriteria, to: enriched)
            searchResults = postFiltered
            errorMessage = nil

            reportEvent(
                severity: .info,
                category: "advancedSearch",
                message: "Advanced search completed.",
                metadata: [
                    "result_count": String(postFiltered.count),
                    "server_filter_present": composeResult.serverFilter == nil ? "false" : "true",
                    "client_criteria_count": String(composeResult.clientCriteria.count),
                    "field_count": String(activeFields.count),
                    "section_count": String(unionedSections.count)
                ]
            )
        } catch {
            let description = describe(error)
            // User-facing message stays clean (no RSQL grammar). The query
            // is still captured for support diagnosis in the
            // `reportError` metadata below.
            errorMessage = userFacingSearchErrorMessage(for: error)
            reportError(
                category: "advancedSearch",
                message: "Advanced search failed.",
                errorDescription: description,
                metadata: [
                    "server_filter": composeResult.serverFilter ?? "",
                    "field_count": String(activeFields.count),
                    "section_count": String(unionedSections.count)
                ]
            )
        }
    }

    /// Pagination wrapper that mirrors `requestAllInventoryPages` but takes a
    /// pre-composed RSQL filter string (instead of building one from a
    /// query+wildcard pair). Reuses the same section-encoding fallback chain.
    private func requestAllInventoryPagesWithRawFilter(
        sections: [MobileDeviceInventorySection],
        rawFilter: String?,
        requestedFields: [MobileDeviceField]
    ) async throws -> [MobileDeviceRecord] {
        var allRecords: [MobileDeviceRecord] = []
        var page = 0

        while true {
            let data = try await requestInventoryWithRawFilter(
                sections: sections,
                rawFilter: rawFilter,
                page: page
            )
            let pageRecords = try decodeSearchResults(from: data, requestedFields: requestedFields)
            allRecords.append(contentsOf: pageRecords)

            if pageRecords.count < Self.mobileInventoryPageSize || pageRecords.isEmpty {
                break
            }

            page += 1
            if page >= 50 {
                reportEvent(
                    severity: .warning,
                    category: "advancedSearch",
                    message: "Advanced search paginated to safety cap of 50 pages; stopping.",
                    metadata: ["accumulated_count": String(allRecords.count)]
                )
                break
            }
        }
        return allRecords
    }

    /// Single-page fetch using the section-encoding fallback chain. Mirrors
    /// the existing `requestInventory(sections:query:useWildcardFilter:page:)`
    /// shape but accepts an opaque RSQL string.
    private func requestInventoryWithRawFilter(
        sections: [MobileDeviceInventorySection],
        rawFilter: String?,
        page: Int
    ) async throws -> Data {
        do {
            return try await requestInventoryWithRawFilter(
                sections: sections,
                rawFilter: rawFilter,
                sectionEncodingMode: .modern,
                page: page
            )
        } catch {
            guard isSectionParameterError(error) else { throw error }
            do {
                return try await requestInventoryWithRawFilter(
                    sections: sections,
                    rawFilter: rawFilter,
                    sectionEncodingMode: .legacy,
                    page: page
                )
            } catch {
                guard isSectionParameterError(error) else { throw error }
                return try await requestInventoryWithRawFilter(
                    sections: sections,
                    rawFilter: rawFilter,
                    sectionEncodingMode: .none,
                    page: page
                )
            }
        }
    }

    private func requestInventoryWithRawFilter(
        sections: [MobileDeviceInventorySection],
        rawFilter: String?,
        sectionEncodingMode: SectionEncodingMode,
        page: Int
    ) async throws -> Data {
        var queryItems: [URLQueryItem] = [
            URLQueryItem(name: "page", value: String(page)),
            URLQueryItem(name: "page-size", value: String(Self.mobileInventoryPageSize)),
            URLQueryItem(name: "sort", value: "\(sortFieldKey):asc")
        ]

        if sectionEncodingMode != .none {
            queryItems.append(
                contentsOf: sectionQueryItems(
                    for: sections,
                    useLegacyNames: sectionEncodingMode == .legacy
                )
            )
        }

        if let rawFilter, rawFilter.isEmpty == false {
            queryItems.append(URLQueryItem(name: "filter", value: rawFilter))
        }

        return try await apiGateway.request(
            path: "api/v2/mobile-devices/detail",
            method: .get,
            queryItems: queryItems
        )
    }

    /// Applies in-memory criteria over enriched results. Each criterion is
    /// matched against the record's `value(for:)` lookup using the same
    /// case-insensitive semantics the server uses for RSQL strings.
    private func applyClientCriteria(
        _ criteria: [AdvancedQueryCriterion],
        to records: [MobileDeviceRecord]
    ) -> [MobileDeviceRecord] {
        guard criteria.isEmpty == false else { return records }
        return records.filter { record in
            criteria.allSatisfy { matches(criterion: $0, record: record) }
        }
    }

    /// Lowercased substring/prefix/suffix/equality semantics for client-side
    /// criterion matching. Boolean and date operators are best-effort:
    /// the typical client-only field is `prestageEnrollmentProfile`, and that
    /// is a string.
    private func matches(criterion: AdvancedQueryCriterion, record: MobileDeviceRecord) -> Bool {
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
            // Numeric / date / boolean criteria currently never reach the
            // client filter (the only `isFilterable: false` field is the
            // string-typed prestage profile). If a future field gets added
            // that needs them, extend this switch.
            return true
        }
        return true
    }

    // MARK: - Detail Refresh

    /// Targeted single-device fetch used by `MobileDeviceDetailView` to
    /// guarantee the hardware section is loaded regardless of the active
    /// search profile. Updates the matching record in `searchResults` so the
    /// detail view's binding picks up the freshly-decoded values.
    func refreshDeviceHardware(id: String) async throws {
        let allFieldsFromHardwareAndGeneral = MobileDeviceField.catalog.filter {
            $0.section == .hardware || $0.section == .general
        }

        let queryItems: [URLQueryItem] = [
            URLQueryItem(name: "section", value: MobileDeviceInventorySection.general.rawValue),
            URLQueryItem(name: "section", value: MobileDeviceInventorySection.hardware.rawValue)
        ]

        let data = try await apiGateway.request(
            path: "api/v2/mobile-devices/\(id)/detail",
            method: .get,
            queryItems: queryItems
        )

        // One-shot diagnostic for the single-detail endpoint shape.
        // The list endpoint and the single-detail endpoint return JSON
        // that may differ in shape (top-level wrapping, nested keys, etc.)
        // and a previously-rendered hardware gauge can disappear after
        // this fetch if extraction fails. Logs once per session.
        logSingleDetailShapeOnce(data: data, deviceID: id)

        let refreshed = try decodeSingleRecord(
            from: data,
            requestedFields: allFieldsFromHardwareAndGeneral
        )

        if let index = searchResults.firstIndex(where: { $0.id == id }) {
            // Merge instead of replace. The refresh fetch sometimes returns
            // a smaller payload (or the single-detail endpoint uses a
            // different shape than the list endpoint), and a wholesale
            // replacement would erase fields the search response had
            // already populated. The merge keeps every populated field from
            // either source — refresh values win on collision, search-row
            // values win where refresh is empty.
            let existing = searchResults[index]
            let merged = existing.merging(refreshed)
            searchResults[index] = merged

            // Capture the actual values that drive the hardware card so we
            // can definitively answer "is the data reaching the UI?" without
            // another guessing round. Plus the Metal renderer's shared-pipeline
            // status — if it's nil the user sees only the SwiftUI fallback bar.
            reportEvent(
                severity: .info,
                category: "detailRefresh",
                message: "Merged single-device detail into search-result row.",
                metadata: [
                    "deviceId": id,
                    "existingFieldCount": String(existing.fieldValues.filter { $0.value.isEmpty == false }.count),
                    "refreshedFieldCount": String(refreshed.fieldValues.filter { $0.value.isEmpty == false }.count),
                    "mergedFieldCount": String(merged.fieldValues.filter { $0.value.isEmpty == false }.count),
                    "merged.capacityMb": merged.capacityMb.map(String.init) ?? "nil",
                    "merged.availableSpaceMb": merged.availableSpaceMb.map(String.init) ?? "nil",
                    "merged.batteryLevel": merged.batteryLevel.map(String.init) ?? "nil",
                    "merged.modelIdentifier": merged.modelIdentifier ?? "nil",
                    "merged.modelNumber": merged.modelNumber ?? "nil",
                    "metal.deviceAvailable": HardwareStorageRenderer.sharedDevice != nil ? "true" : "false",
                    "metal.pipelineAvailable": HardwareStorageRenderer.sharedPipelineState != nil ? "true" : "false",
                    "metal.lastInitError": HardwareStorageRenderer.lastInitError ?? "none"
                ]
            )
        } else {
            searchResults.insert(refreshed, at: 0)
        }
    }

    /// Decodes a single-record response from the per-device detail endpoint.
    /// The response is a JSON object (not a wrapped array), so we extract the
    /// device dict directly and feed it to `parseRecord`. Avoids the
    /// round-trip through `decodeSearchResults` that re-serialized the JSON.
    private func decodeSingleRecord(
        from data: Data,
        requestedFields: [MobileDeviceField]
    ) throws -> MobileDeviceRecord {
        let parsed: Any
        do {
            parsed = try JSONSerialization.jsonObject(with: data, options: [])
        } catch {
            reportError(
                category: "decoding",
                message: "Failed to parse single mobile-device JSON.",
                errorDescription: describe(error)
            )
            throw JamfFrameworkError.decodingFailure
        }

        let dict: [String: Any]
        if let direct = parsed as? [String: Any] {
            dict = direct
        } else if let raw = parsed as? [[String: Any]], let first = raw.first {
            dict = first
        } else {
            throw JamfFrameworkError.decodingFailure
        }

        return parseRecord(from: dict, requestedFields: requestedFields)
    }

    // MARK: - API Request Construction

    /// Requests inventory data with automatic section encoding fallback.
    ///
    /// Tries modern section parameter names first. If the server rejects the section
    /// parameter type, retries with legacy names, and finally with no section parameters
    /// at all. This three-tier fallback ensures compatibility across Jamf Pro versions.
    ///
    /// - Parameters:
    ///   - sections: The inventory sections to request.
    ///   - query: The search query string.
    ///   - useWildcardFilter: Whether to wrap the query in wildcards for substring matching.
    /// - Returns: The raw response `Data` from the API.
    private func requestInventory(
        sections: [MobileDeviceInventorySection],
        query: String,
        useWildcardFilter: Bool,
        page: Int = 0
    ) async throws -> Data {
        do {
            return try await requestInventory(
                sections: sections,
                query: query,
                useWildcardFilter: useWildcardFilter,
                sectionEncodingMode: .modern,
                page: page
            )
        } catch {
            guard isSectionParameterError(error) else {
                throw error
            }

            // Modern section names rejected -- try legacy names
            do {
                reportEvent(
                    severity: .warning,
                    category: "search",
                    message: "Retrying mobile device search with legacy inventory section names.",
                    metadata: [
                        "section_count": String(sections.count)
                    ]
                )

                return try await requestInventory(
                    sections: sections,
                    query: query,
                    useWildcardFilter: useWildcardFilter,
                    sectionEncodingMode: .legacy,
                    page: page
                )
            } catch {
                guard isSectionParameterError(error) else {
                    throw error
                }

                // Legacy names also rejected -- omit sections entirely
                reportEvent(
                    severity: .warning,
                    category: "search",
                    message: "Retrying mobile device search without inventory section parameters.",
                    metadata: [
                        "section_count": String(sections.count)
                    ]
                )

                return try await requestInventory(
                    sections: sections,
                    query: query,
                    useWildcardFilter: useWildcardFilter,
                    sectionEncodingMode: .none,
                    page: page
                )
            }
        }
    }

    /// Paginated wrapper around `requestInventory` that loops pages until a
    /// page returns fewer items than the page size (Jamf's last-page signal).
    /// Replaces the previous page-0-only search that silently truncated
    /// result sets above ~100 devices.
    private func requestAllInventoryPages(
        sections: [MobileDeviceInventorySection],
        query: String,
        useWildcardFilter: Bool,
        requestedFields: [MobileDeviceField]
    ) async throws -> [MobileDeviceRecord] {
        var allRecords: [MobileDeviceRecord] = []
        var page = 0

        while true {
            let data = try await requestInventory(
                sections: sections,
                query: query,
                useWildcardFilter: useWildcardFilter,
                page: page
            )
            let pageRecords = try decodeSearchResults(from: data, requestedFields: requestedFields)
            allRecords.append(contentsOf: pageRecords)

            if pageRecords.count < Self.mobileInventoryPageSize || pageRecords.isEmpty {
                break
            }

            page += 1

            // Safety cap to avoid runaway loops. 50 pages × 200/page = 10k
            // devices, well above normal Jamf tenant mobile fleet sizes for
            // a single technician search.
            if page >= 50 {
                reportEvent(
                    severity: .warning,
                    category: "search",
                    message: "Mobile device search paginated to safety cap of 50 pages; stopping.",
                    metadata: [
                        "accumulated_count": String(allRecords.count)
                    ]
                )
                break
            }
        }

        return allRecords
    }

    /// Builds query parameters and sends the inventory detail API request.
    ///
    /// Constructs pagination, sorting, section, and filter query items, then delegates
    /// to the API gateway for the actual network call.
    ///
    /// - Parameters:
    ///   - sections: The inventory sections to include.
    ///   - query: The search query string.
    ///   - useWildcardFilter: Whether to use wildcard wrapping on the filter value.
    ///   - sectionEncodingMode: How to encode section parameters (modern, legacy, or none).
    /// - Returns: The raw response `Data`.
    /// Page size used when fetching mobile device search results.
    private static let mobileInventoryPageSize = 200

    private func requestInventory(
        sections: [MobileDeviceInventorySection],
        query: String,
        useWildcardFilter: Bool,
        sectionEncodingMode: SectionEncodingMode,
        page: Int = 0
    ) async throws -> Data {
        var queryItems: [URLQueryItem] = [
            URLQueryItem(name: "page", value: String(page)),
            URLQueryItem(name: "page-size", value: String(Self.mobileInventoryPageSize)),
            URLQueryItem(name: "sort", value: "\(sortFieldKey):asc")
        ]

        // Append section parameters unless the mode is .none
        if sectionEncodingMode != .none {
            queryItems.append(
                contentsOf: sectionQueryItems(
                    for: sections,
                    useLegacyNames: sectionEncodingMode == .legacy
                )
            )
        }

        // Build and append the RSQL filter expression if a query is present
        if let filter = buildFilterExpression(for: query, useWildcard: useWildcardFilter) {
            queryItems.append(URLQueryItem(name: "filter", value: filter))
        }

        return try await apiGateway.request(
            path: "api/v2/mobile-devices/detail",
            method: .get,
            queryItems: queryItems
        )
    }

    /// Converts inventory sections into URL query items using either modern or legacy names.
    ///
    /// - Parameters:
    ///   - sections: The sections to encode.
    ///   - useLegacyNames: If `true`, maps sections to their legacy parameter values.
    /// - Returns: An array of `URLQueryItem` instances, one per section.
    private func sectionQueryItems(
        for sections: [MobileDeviceInventorySection],
        useLegacyNames: Bool
    ) -> [URLQueryItem] {
        sections.map { section in
            let value = useLegacyNames ? legacySectionParameterValue(for: section) : section.rawValue
            return URLQueryItem(name: sectionParameterName, value: value)
        }
    }

    /// Maps a section to its legacy parameter value for older Jamf Pro versions.
    ///
    /// Some section names differ between modern and legacy API versions (e.g.
    /// "USER_AND_LOCATION" vs "LOCATION", "PROFILES" vs "CONFIGURATION_PROFILES").
    ///
    /// - Parameter section: The section to map.
    /// - Returns: The legacy string value for the section parameter.
    private func legacySectionParameterValue(for section: MobileDeviceInventorySection) -> String {
        switch section {
        case .general:
            return "GENERAL"
        case .location:
            return "LOCATION"
        case .hardware:
            return "HARDWARE"
        case .purchasing:
            return "PURCHASING"
        case .security:
            return "SECURITY"
        case .applications:
            return "APPLICATIONS"
        case .ebooks:
            return "EBOOKS"
        case .network:
            return "NETWORK"
        case .serviceSubscriptions:
            return "SERVICE_SUBSCRIPTIONS"
        case .certificates:
            return "CERTIFICATES"
        case .configurationProfiles:
            return "CONFIGURATION_PROFILES"
        case .userProfiles:
            return "USER_PROFILES"
        case .provisioningProfiles:
            return "PROVISIONING_PROFILES"
        case .sharedUsers:
            return "SHARED_USERS"
        case .extensionAttributes:
            return "EXTENSION_ATTRIBUTES"
        case .mobileDeviceGroups:
            return "MOBILE_DEVICE_GROUPS"
        }
    }

    // MARK: - Field Resolution

    /// Resolves a list of field keys into their corresponding `MobileDeviceField` catalog entries.
    ///
    /// If the provided keys are empty or none of them match catalog entries, the default
    /// result field set is returned as a fallback so the UI always has something to display.
    ///
    /// - Parameter selectedKeys: The field keys to resolve.
    /// - Returns: An ordered array of catalog fields matching the keys.
    private func resolvedCatalogFields(from selectedKeys: [String]) -> [MobileDeviceField] {
        // Use the merged lookup so EA-derived field keys (`ea_<id>`) resolve
        // even though they aren't in `MobileDeviceField.catalog` at compile time.
        let lookup = mergedFieldLookup
        let defaultFields = MobileDeviceField.defaultResultFieldKeys.compactMap { lookup[$0] }

        guard selectedKeys.isEmpty == false else {
            return defaultFields
        }

        let resolved = selectedKeys.compactMap { lookup[$0] }
        if resolved.isEmpty {
            return defaultFields
        }

        return resolved
    }

    /// Returns the currently active field keys, preferring the live UI selection
    /// over the selected profile's stored keys.
    ///
    /// - Returns: A sorted array of field key strings.
    private func activeFieldKeys() -> [String] {
        let liveSelection = Array(selectedFieldKeys).sorted()
        if liveSelection.isEmpty == false {
            return liveSelection
        }

        return selectedProfile?.fieldKeys ?? []
    }

    /// Determines which inventory sections need to be requested based on the active fields.
    ///
    /// Always includes `.general` AND `.hardware` (the entire value-prop of
    /// the Mobile Device Search module now hinges on hardware fields —
    /// `modelIdentifier` for the chip lookup that produces the friendly device
    /// name, `capacityMb` / `availableSpaceMb` / `batteryLevel` for the
    /// hardware card and gauges). When a query is present, `.location` is
    /// also included so username-based searches can match.
    ///
    /// Without `.hardware` always-on, an Advanced Search whose criteria
    /// reference only General/Location/EA fields (the common case) emits an
    /// API request without the HARDWARE section, the response carries no
    /// hardware values, `displayEssentialKeys` has nothing to extract, and
    /// every device renders as "Unknown Device" with no gauge — no matter
    /// how correct the downstream parsing or rendering pipeline is.
    ///
    /// - Parameters:
    ///   - fields: The active field list whose sections should be included.
    ///   - includesQuery: Whether the user has entered a search query.
    /// - Returns: A sorted array of unique inventory sections.
    private func resolvedSections(
        from fields: [MobileDeviceField],
        includesQuery: Bool
    ) -> [MobileDeviceInventorySection] {
        var sections = Set(fields.map(\.section))
        sections.insert(.general)
        sections.insert(.hardware)

        if includesQuery {
            sections.insert(.location)
        }

        return sections.sorted { $0.rawValue < $1.rawValue }
    }

    // MARK: - RSQL Filter Construction

    /// Builds an RSQL filter expression that searches by serial number OR username.
    ///
    /// When `useWildcard` is true, the query is wrapped in `*...*` for substring matching.
    /// Special RSQL characters (backslash and single quote) are escaped to prevent injection.
    ///
    /// - Parameters:
    ///   - query: The raw user query string.
    ///   - useWildcard: Whether to wrap the query in wildcard characters.
    /// - Returns: The RSQL filter string, or `nil` if the query is empty.
    private func buildFilterExpression(for query: String, useWildcard: Bool) -> String? {
        // Delegates to the shared `JamfRSQLFilter.serialOrUsername` helper
        // so both this view model and `SupportTechnicianAPIService`'s mobile
        // search path emit identical RSQL. Prior to the extraction, the
        // two sites duplicated the grammar and the literal-`or` bug the
        // audit caught only existed at one of them — a second copy had
        // drifted the other way.
        JamfRSQLFilter.serialOrUsername(
            query: query,
            useWildcard: useWildcard,
            serialField: serialSearchFilterKey,
            usernameField: usernameSearchFilterKey
        )
    }

    // MARK: - Response Decoding

    /// Decodes raw API response data into an array of `MobileDeviceRecord` instances.
    ///
    /// The response JSON may be a top-level array, or an object containing a results
    /// array under a known key. Each dictionary element is manually parsed into a record
    /// using the active field definitions for value extraction.
    ///
    /// - Parameters:
    ///   - data: The raw JSON data from the API.
    ///   - requestedFields: The fields to extract values for.
    /// - Returns: An array of parsed device records.
    /// - Throws: `JamfFrameworkError.decodingFailure` if the JSON cannot be parsed.
    private func decodeSearchResults(
        from data: Data,
        requestedFields: [MobileDeviceField]
    ) throws -> [MobileDeviceRecord] {
        let jsonObject: Any
        do {
            jsonObject = try JSONSerialization.jsonObject(with: data)
        } catch {
            reportError(
                category: "decoding",
                message: "Failed to parse mobile device search results JSON.",
                errorDescription: describe(error)
            )
            throw JamfFrameworkError.decodingFailure
        }

        guard let objects = dictionaryArray(from: jsonObject) else {
            reportError(
                category: "decoding",
                message: "Mobile device search results JSON did not contain a recognized array structure.",
                errorDescription: "Expected array of dictionaries at top level or under a known key."
            )
            throw JamfFrameworkError.decodingFailure
        }

        return objects.map { dictionary in
            parseRecord(from: dictionary, requestedFields: requestedFields)
        }
    }

    /// Parses a single JSON dictionary into a `MobileDeviceRecord`, extracting values
    /// for each requested field using the field's configured response paths.
    ///
    /// Core identity fields (id, name, serial, UDID, model, OS version) are extracted
    /// first using their known path lists, then each requested field is extracted using
    /// its catalog-defined `responsePaths`. Pre-Stage data is resolved inline from the
    /// dictionary as well. All extracted values are collected into the record's `fieldValues`.
    private func parseRecord(
        from dictionary: [String: Any],
        requestedFields: [MobileDeviceField]
    ) -> MobileDeviceRecord {
        // First-record-per-session shape diagnostic. Logs the top-level keys
        // plus the keys inside common section containers AND the resolved
        // values for a handful of critical paths. Lets us spot Jamf Pro
        // schema variations (different field names, missing nesting, etc.)
        // without dumping potentially-sensitive full payloads to the log.
        logResponseShapeOnce(dictionary)

        // Extract core identity fields with multiple path fallbacks
        let id =
            extractValue(using: ["id", "mobileDeviceId", "deviceId", "hardware.deviceId"], from: dictionary) ??
            UUID().uuidString

        // Resolve the display name with a graceful fallback chain. The Jamf
        // v2 detail endpoint returns `general.displayName: null` (not a
        // missing key) when the device hasn't been given a custom name, so
        // the path resolver's iteration also has to skip nulls before
        // falling back. Final fallback is "<model> (last 4 of serial)" so
        // a row like "iPhone (XYZ4)" is far more useful than "Unknown
        // Device".
        let serialNumber =
            extractValue(using: ["hardware.serialNumber", "general.serialNumber", "serialNumber"], from: dictionary) ??
            "Unknown"

        let resolvedDisplayName = extractValue(
            using: [
                "general.displayName",
                "general.deviceName",
                "general.name",
                "deviceName",
                "displayName",
                "name"
            ],
            from: dictionary
        )

        let modelHint = extractValue(
            using: ["hardware.model", "general.model", "model"],
            from: dictionary
        )

        let deviceName: String
        let nameFallbackBranch: String
        if let resolvedDisplayName {
            deviceName = resolvedDisplayName
            nameFallbackBranch = "displayName"
        } else if let modelHint, modelHint.isEmpty == false {
            let suffix: String
            if serialNumber.count >= 4 && serialNumber != "Unknown" {
                suffix = " (\(serialNumber.suffix(4)))"
            } else {
                suffix = ""
            }
            deviceName = modelHint + suffix
            nameFallbackBranch = "modelHint"
        } else {
            deviceName = "Unknown Device"
            nameFallbackBranch = "unknownFallback"
        }

        // One-shot diagnostic so we can confirm which fallback branch fired
        // for the first record of the session. Helps catch cases where the
        // user reports "still seeing Unknown Device" — the diagnostic tells
        // us exactly which extraction path actually ran.
        if hasLoggedResponseShape == true && hasLoggedNameFallback == false {
            hasLoggedNameFallback = true
            reportEvent(
                severity: .info,
                category: "deviceNameFallback",
                message: "Computed device name for first parsed record.",
                metadata: [
                    "branch": nameFallbackBranch,
                    "resultLength": String(deviceName.count),
                    "modelHintWasNil": modelHint == nil ? "true" : "false",
                    "displayNameWasNil": resolvedDisplayName == nil ? "true" : "false",
                    "serialKnown": (serialNumber == "Unknown") ? "false" : "true"
                ]
            )
        }

        let udid = extractValue(using: ["general.udid", "udid"], from: dictionary)
        let model = extractValue(
            using: [
                "hardware.model",
                "general.model",
                "model",
                "hardware.modelIdentifier",
                "general.modelIdentifier",
                "modelIdentifier"
            ],
            from: dictionary
        )
        let osVersion = extractValue(using: ["general.osVersion", "osVersion"], from: dictionary)

        // Extract Pre-Stage Enrollment components from the dictionary.
        // Status is intentionally optional here. Defaulting to "Enrolled"
        // would silently flip a previously-resolved "Not Enrolled" record
        // back to "Enrolled" any time `parseRecord` re-runs on a payload
        // that omits the management-status keys (e.g. the single-device
        // detail-refresh response). The downstream prestage-resolution
        // helpers and `MobileDeviceRecord.prestageDisplayValue` already
        // tolerate a nil status.
        let prestage = extractPrestageNameAndID(from: dictionary)
        let prestageStatus =
            normalizePrestageStatus(extractPrestageEnrollmentStatus(from: dictionary))
        let prestageDisplayValue = MobileDeviceRecord.prestageDisplayValue(
            status: prestageStatus,
            profileName: prestage.name,
            profileID: prestage.id
        )

        // Build the flexible field values dictionary from all requested fields
        var fieldValues: [String: String] = [:]

        for field in requestedFields {
            let resolvedValue: String?
            if field.key == prestageFieldKey {
                // Prestage field uses its own composed display value
                resolvedValue = prestageDisplayValue
            } else {
                resolvedValue = extractValue(using: field.responsePaths, from: dictionary)
            }

            if let resolvedValue, resolvedValue.isEmpty == false {
                fieldValues[field.key] = resolvedValue
            }
        }

        // Display-essential hardware fields — always extracted regardless of
        // the active column profile so the inline storage gauge in result
        // rows AND the HardwareInfoCard in the detail view both populate.
        // Without this, devices whose profile doesn't explicitly request
        // these (most users keep the 5-column default) would never show
        // storage/battery/chip data even though it's right there in the
        // response payload. Only writes when the JSON value isn't null AND
        // the field wasn't already populated above (so an explicit profile
        // pick still wins on collisions).
        let displayEssentialKeys = [
            "capacityMb",
            "availableSpaceMb",
            "usedSpacePercentage",
            "batteryLevel",
            "batteryHealth",
            "modelIdentifier",
            "modelNumber"
        ]
        for key in displayEssentialKeys {
            if fieldValues[key] != nil { continue }
            guard let field = MobileDeviceField.keyLookup[key] else { continue }
            if let resolved = extractValue(using: field.responsePaths, from: dictionary),
               resolved.isEmpty == false
            {
                fieldValues[key] = resolved
            }
        }

        // Ensure core fields are always present in fieldValues
        fieldValues["id"] = fieldValues["id"] ?? id
        fieldValues["deviceName"] = fieldValues["deviceName"] ?? deviceName
        fieldValues["serialNumber"] = fieldValues["serialNumber"] ?? serialNumber

        if let udid, udid.isEmpty == false {
            fieldValues["udid"] = fieldValues["udid"] ?? udid
        }

        if let model, model.isEmpty == false {
            fieldValues["model"] = fieldValues["model"] ?? model
        }

        if let osVersion, osVersion.isEmpty == false {
            fieldValues["osVersion"] = fieldValues["osVersion"] ?? osVersion
        }

        if let prestageDisplayValue, prestageDisplayValue.isEmpty == false {
            fieldValues[prestageFieldKey] = fieldValues[prestageFieldKey] ?? prestageDisplayValue
        }

        // Flatten extension-attribute values into `fieldValues` so the
        // client-side criterion matcher and the result-row column lookup
        // resolve them via the synthetic `ea_<id>` key. Jamf's response
        // mirrors EAs in two places depending on the EA's "Display Section"
        // setting: an inline array under each section (e.g.
        // `general.extensionAttributes`) AND a top-level
        // `extensionAttributes` array. Scanning both covers every variant
        // shipped across recent Jamf Pro versions.
        let eaScanLocations: [Any?] = [
            dictionary["extensionAttributes"],
            (dictionary["general"] as? [String: Any])?["extensionAttributes"],
            (dictionary["hardware"] as? [String: Any])?["extensionAttributes"],
            (dictionary["userAndLocation"] as? [String: Any])?["extensionAttributes"],
            (dictionary["location"] as? [String: Any])?["extensionAttributes"],
            (dictionary["purchasing"] as? [String: Any])?["extensionAttributes"],
            (dictionary["security"] as? [String: Any])?["extensionAttributes"],
            (dictionary["network"] as? [String: Any])?["extensionAttributes"]
        ]
        for location in eaScanLocations {
            guard let array = location as? [[String: Any]] else { continue }
            for eaDict in array {
                let rawID: String?
                if let intValue = eaDict["id"] as? Int {
                    rawID = String(intValue)
                } else if let stringValue = eaDict["id"] as? String,
                          stringValue.isEmpty == false
                {
                    rawID = stringValue
                } else if let definitionID = eaDict["definitionId"] as? Int {
                    rawID = String(definitionID)
                } else if let definitionID = eaDict["definitionId"] as? String,
                          definitionID.isEmpty == false
                {
                    rawID = definitionID
                } else {
                    rawID = nil
                }

                guard let eaID = rawID else { continue }
                let key = MobileDeviceExtensionAttribute.keyPrefix + eaID
                guard fieldValues[key] == nil else { continue } // first wins

                // EA value is an array of strings in modern responses, a
                // single string in older shapes, or buried in a nested
                // `values`/`value` structure. Try the common shapes in order.
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

        return MobileDeviceRecord(
            id: id,
            deviceName: deviceName,
            serialNumber: serialNumber,
            udid: udid,
            model: model,
            osVersion: osVersion,
            prestageEnrollmentStatus: prestageStatus,
            prestageEnrollmentProfileName: prestage.name,
            prestageEnrollmentProfileID: prestage.id,
            fieldValues: fieldValues
        )
    }

    /// Emits a one-shot diagnostic capturing the shape of the first device
    /// dictionary parsed in this app session. Used to pinpoint Jamf schema
    /// variations on customer tenants when expected fields don't extract.
    private func logResponseShapeOnce(_ dictionary: [String: Any]) {
        guard hasLoggedResponseShape == false else { return }
        hasLoggedResponseShape = true

        var info: [String: String] = [:]

        info["topLevelKeys"] = dictionary.keys.sorted().joined(separator: ",")

        if let general = dictionary["general"] as? [String: Any] {
            info["generalKeys"] = general.keys.sorted().joined(separator: ",")
        }
        if let hardware = dictionary["hardware"] as? [String: Any] {
            info["hardwareKeys"] = hardware.keys.sorted().joined(separator: ",")
        }
        if let userAndLocation = dictionary["userAndLocation"] as? [String: Any] {
            info["userAndLocationKeys"] = userAndLocation.keys.sorted().joined(separator: ",")
        }
        if let security = dictionary["security"] as? [String: Any] {
            info["securityKeys"] = security.keys.sorted().joined(separator: ",")
        }

        // Resolve the specific paths the hardware card depends on so we can
        // see whether the field names match my catalog assumptions.
        let probePaths = [
            "general.displayName",
            "general.deviceName",
            "general.name",
            "general.model",
            "general.modelIdentifier",
            "hardware.model",
            "hardware.modelIdentifier",
            "hardware.modelNumber",
            "hardware.serialNumber",
            "hardware.capacityMb",
            "hardware.availableSpaceMb",
            "hardware.usedSpacePercentage",
            "hardware.batteryLevel",
            "hardware.batteryHealth"
        ]
        for path in probePaths {
            let resolved = resolveValue(atPath: path, in: dictionary)
            // Only include the type + truthiness — never the value itself.
            // Avoids leaking PII (serials, names) while still telling us
            // which fields exist and which don't.
            if let resolved {
                info["path_\(path)"] = "\(type(of: resolved))"
            } else {
                info["path_\(path)"] = "nil"
            }
        }

        reportEvent(
            severity: .info,
            category: "responseShape",
            message: "Mobile device response shape captured.",
            metadata: info
        )
    }

    /// One-shot diagnostic for the per-device detail endpoint's JSON shape.
    /// Mirrors `logResponseShapeOnce` but for the single-device endpoint so
    /// we can compare shapes across the two paths without touching the
    /// shared parseRecord flag.
    private func logSingleDetailShapeOnce(data: Data, deviceID: String) {
        guard hasLoggedSingleDetailShape == false else { return }
        hasLoggedSingleDetailShape = true

        let parsed: Any?
        parsed = try? JSONSerialization.jsonObject(with: data, options: [])

        var info: [String: String] = [
            "deviceId": deviceID,
            "byteCount": String(data.count)
        ]

        guard let dict = parsed as? [String: Any] else {
            info["topLevelType"] = String(describing: type(of: parsed))
            reportEvent(
                severity: .warning,
                category: "responseShape",
                message: "Single-detail response is not a top-level dictionary.",
                metadata: info
            )
            return
        }

        info["topLevelKeys"] = dict.keys.sorted().joined(separator: ",")
        if let general = dict["general"] as? [String: Any] {
            info["generalKeys"] = general.keys.sorted().joined(separator: ",")
        }
        if let hardware = dict["hardware"] as? [String: Any] {
            info["hardwareKeys"] = hardware.keys.sorted().joined(separator: ",")
        }

        for path in [
            "general.displayName",
            "hardware.capacityMb",
            "hardware.availableSpaceMb",
            "hardware.modelIdentifier",
            "hardware.batteryLevel"
        ] {
            let resolved = resolveValue(atPath: path, in: dict)
            if let resolved {
                info["path_\(path)"] = "\(type(of: resolved))"
            } else {
                info["path_\(path)"] = "nil"
            }
        }

        reportEvent(
            severity: .info,
            category: "responseShape",
            message: "Single-device-detail response shape captured.",
            metadata: info
        )
    }

    /// Joins an EA value array into a single comma-separated string for
    /// in-memory matching. Multi-value EAs are rare on iOS but exist in some
    /// LDAP-fed configurations. Empty entries are dropped.
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

    // MARK: - JSON Traversal Helpers

    /// Recursively searches a JSON value for an array of dictionaries.
    ///
    /// Handles three common API response shapes:
    /// 1. A top-level array of dictionaries
    /// 2. An object with a known results key (e.g. "results", "mobileDevices", "devices")
    /// 3. Nested structures where the array is buried deeper in the hierarchy
    ///
    /// - Parameter value: The raw JSON value to search.
    /// - Returns: An array of dictionaries, or `nil` if no recognizable structure is found.
    private func dictionaryArray(from value: Any?) -> [[String: Any]]? {
        if let dictionaries = value as? [[String: Any]] {
            return dictionaries
        }

        if let array = value as? [Any] {
            let dictionaries = array.compactMap { $0 as? [String: Any] }
            if dictionaries.isEmpty == false {
                return dictionaries
            }

            // Try unwrapping nested arrays
            for element in array {
                if let nested = dictionaryArray(from: element), nested.isEmpty == false {
                    return nested
                }
            }

            return []
        }

        if let dictionary = value as? [String: Any] {
            // Check well-known result container keys first
            let candidateKeys = ["results", "mobileDevices", "devices", "items", "data"]

            for key in candidateKeys {
                guard dictionary.keys.contains(key) else {
                    continue
                }

                if let nested = dictionaryArray(from: dictionary[key]) {
                    return nested
                }
            }

            // Fall back to checking all values
            for nestedValue in dictionary.values {
                if let nested = dictionaryArray(from: nestedValue), nested.isEmpty == false {
                    return nested
                }
            }
        }

        return nil
    }

    /// Tries each dot-separated path in order, returning the first non-empty string value found.
    ///
    /// - Parameters:
    ///   - paths: An ordered list of dot-separated key paths to try.
    ///   - dictionary: The JSON dictionary to extract from.
    /// - Returns: The first successfully extracted string value, or `nil`.
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
    /// objects and arrays along the way.
    ///
    /// For example, `"general.serialNumber"` first looks up the `"general"` key to get
    /// a nested dictionary, then looks up `"serialNumber"` within it. If an array is
    /// encountered mid-path, the next component is mapped across all array elements.
    ///
    /// - Parameters:
    ///   - path: A dot-separated key path (e.g. `"hardware.model"`).
    ///   - dictionary: The root dictionary to traverse.
    /// - Returns: The resolved value, or `nil` if the path cannot be followed.
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

            // When traversing through an array, map the key across all elements
            if let currentArray = current as? [Any] {
                let mappedValues = currentArray.compactMap { element -> Any? in
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

    // MARK: - Pre-Stage Enrollment Resolution

    /// Enriches device records with Pre-Stage Enrollment data by cross-referencing
    /// the prestage scope API.
    ///
    /// For each record, the method checks if a scope association exists for its serial
    /// number. If additional detail is needed, individual device detail and prestage
    /// detail endpoints are queried. Records that appear only in the prestage scope
    /// (not in the inventory results) are appended as "scope-only" placeholder records
    /// when the query matches their serial number.
    ///
    /// - Parameters:
    ///   - records: The decoded device records from the search.
    ///   - query: The original search query, used for scope-only record matching.
    /// - Returns: The records with Pre-Stage Enrollment data resolved where possible.
    private func resolvePrestageEnrollmentProfiles(
        for records: [MobileDeviceRecord],
        query: String
    ) async -> [MobileDeviceRecord] {
        let normalizedQuerySerial = normalizeSerial(query)
        let inventorySerials = Set(records.compactMap { normalizeSerial($0.serialNumber) })
        let scopeAssociations = await fetchMobilePrestageScopeAssociations(
            targetSerials: inventorySerials,
            querySerial: normalizedQuerySerial
        )

        var resolvedRecords: [MobileDeviceRecord] = []
        resolvedRecords.reserveCapacity(records.count + scopeAssociations.count)
        var existingSerials = Set<String>()

        for record in records {
            let normalizedSerial = normalizeSerial(record.serialNumber)
            if let normalizedSerial {
                existingSerials.insert(normalizedSerial)
            }

            // Look up the scope association for this device's serial number
            let scopeAssociation = normalizedSerial.flatMap { scopeAssociations[$0] }
            let resolved = await resolvePrestageEnrollmentProfile(
                for: record,
                scopeAssociation: scopeAssociation
            )
            resolvedRecords.append(resolved)
        }

        // Append scope-only records for devices that appear in prestage scope
        // but not in the inventory search results
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

    /// Resolves Pre-Stage Enrollment details for a single device record.
    ///
    /// Merges data from the record itself, the scope association (if available),
    /// and optionally the individual device detail endpoint. If a profile ID is
    /// known but the name is not, the prestage detail endpoint is queried to
    /// resolve the name (with caching to avoid repeated calls).
    private func resolvePrestageEnrollmentProfile(
        for record: MobileDeviceRecord,
        scopeAssociation: MobilePrestageScopeAssociation?
    ) async -> MobileDeviceRecord {
        var resolvedStatus = normalizePrestageStatus(record.prestageEnrollmentStatus) ?? enrolledStatusLabel
        var resolvedName = normalizePrestageComponent(record.prestageEnrollmentProfileName)
        var resolvedID = normalizePrestageComponent(record.prestageEnrollmentProfileID)

        // Merge scope association data if available
        if let scopeAssociation {
            resolvedName = resolvedName ?? scopeAssociation.profileName
            resolvedID = resolvedID ?? scopeAssociation.profileID
        }

        // If we have an ID but no name, look up the name via the prestage detail endpoint
        if resolvedName == nil, let resolvedID, resolvedID.isEmpty == false {
            resolvedName = await resolvePrestageName(forProfileID: resolvedID)
        }

        if resolvedName != nil || resolvedID != nil {
            return record.withPrestageEnrollment(
                profileName: resolvedName,
                profileID: resolvedID,
                status: resolvedStatus
            )
        }

        // Last resort: fetch the individual device detail endpoint for prestage info
        let deviceID = record.id.trimmingCharacters(in: .whitespacesAndNewlines)
        guard deviceID.isEmpty == false else {
            return record.withPrestageEnrollment(profileName: nil, profileID: nil, status: resolvedStatus)
        }

        do {
            let detailData = try await apiGateway.request(
                path: "api/v2/mobile-devices/\(deviceID)/detail",
                method: .get
            )

            let extracted = extractPrestageNameAndID(from: detailData)
            let detailStatus = normalizePrestageStatus(extractPrestageEnrollmentStatus(from: detailData))

            resolvedStatus = detailStatus ?? resolvedStatus
            resolvedName = resolvedName ?? extracted.name
            resolvedID = resolvedID ?? extracted.id

            if resolvedName == nil, let resolvedID, resolvedID.isEmpty == false {
                resolvedName = await resolvePrestageName(forProfileID: resolvedID)
            }

            return record.withPrestageEnrollment(
                profileName: resolvedName,
                profileID: resolvedID,
                status: resolvedStatus
            )
        } catch {
            let description = describe(error)
            await diagnosticsReporter.reportError(
                source: moduleSource,
                category: "prestage",
                message: "Failed to resolve Pre-Stage Enrollment profile for a device.",
                errorDescription: description,
                metadata: [
                    "device_id": deviceID
                ]
            )
            return record.withPrestageEnrollment(profileName: nil, profileID: nil, status: resolvedStatus)
        }
    }

    /// Creates a placeholder record for a device that exists only in the Pre-Stage
    /// scope (not yet in inventory), using the serial number as the display name.
    private func makeScopeOnlyRecord(from association: MobilePrestageScopeAssociation) -> MobileDeviceRecord {
        let recordID = "prestage-scope-\(association.serialNumber)-\(association.profileID)"
        var fieldValues: [String: String] = [
            "id": recordID,
            "deviceName": association.serialNumber,
            "serialNumber": association.serialNumber
        ]

        if let displayValue = MobileDeviceRecord.prestageDisplayValue(
            status: notEnrolledStatusLabel,
            profileName: association.profileName,
            profileID: association.profileID
        ) {
            fieldValues[prestageFieldKey] = displayValue
        }

        return MobileDeviceRecord(
            id: recordID,
            deviceName: association.serialNumber,
            serialNumber: association.serialNumber,
            udid: nil,
            model: nil,
            osVersion: nil,
            prestageEnrollmentStatus: notEnrolledStatusLabel,
            prestageEnrollmentProfileName: association.profileName,
            prestageEnrollmentProfileID: association.profileID,
            fieldValues: fieldValues
        )
    }

    // MARK: - Prestage Scope Fetching

    /// Fetches all Pre-Stage scope associations relevant to the given serial numbers.
    ///
    /// Enumerates all mobile device prestages, fetches each one's scope (serial list),
    /// and builds a lookup dictionary mapping serial numbers to their prestage profile
    /// associations. Only serials that match the target set or the query serial are included.
    ///
    /// - Parameters:
    ///   - targetSerials: Serial numbers from the inventory search results.
    ///   - querySerial: The normalized search query serial, for scope-only record discovery.
    /// - Returns: A dictionary mapping uppercase serial numbers to their scope associations.
    private func fetchMobilePrestageScopeAssociations(
        targetSerials: Set<String>,
        querySerial: String?
    ) async -> [String: MobilePrestageScopeAssociation] {
        guard targetSerials.isEmpty == false || querySerial != nil else {
            return [:]
        }

        do {
            let prestages = try await fetchAllMobilePrestages()
            var associations: [String: MobilePrestageScopeAssociation] = [:]

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
                                    associations[serial] = MobilePrestageScopeAssociation(
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
                        let serials = try await self.fetchMobilePrestageScopeSerials(forPrestageID: prestage.id)
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
                            associations[serial] = MobilePrestageScopeAssociation(
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
                message: "Failed reading mobile pre-stage inventory.",
                errorDescription: description
            )
            return [:]
        }
    }

    /// Fetches all mobile device prestage profiles using paginated API calls.
    ///
    /// Pages through the prestage list endpoint in batches of 100, deduplicating
    /// by profile ID. Pagination stops when a page returns fewer results than the
    /// page size, an empty page, or no new unique IDs (guarding against infinite loops).
    ///
    /// - Returns: An array of prestage summaries (ID + display name).
    private func fetchAllMobilePrestages() async throws -> [MobilePrestageSummary] {
        let pageSize = 100
        var page = 0
        var prestages: [MobilePrestageSummary] = []
        var seenIDs = Set<String>()
        var totalFetched = 0

        while true {
            let data = try await apiGateway.request(
                path: "api/v2/mobile-device-prestages",
                method: .get,
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

            let pagePrestages = parseMobilePrestageSummaries(from: data)
            let uniquePrestages = pagePrestages.filter { seenIDs.insert($0.id).inserted }
            prestages.append(contentsOf: uniquePrestages)
            totalFetched += pagePrestages.count

            // Stop when the page is undersized, empty, yielded no new unique entries, or we've fetched all items
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

    /// Fetches all serial numbers scoped to a specific prestage profile using paginated calls.
    ///
    /// Serials are normalized to uppercase and deduplicated. Pagination terminates using
    /// the same guard conditions as `fetchAllMobilePrestages`.
    ///
    /// - Parameter prestageID: The prestage profile ID to fetch scope for.
    /// - Returns: A set of uppercase serial numbers scoped to this prestage.
    private func fetchMobilePrestageScopeSerials(forPrestageID prestageID: String) async throws -> Set<String> {
        let pageSize = 100
        var page = 0
        var serials = Set<String>()

        while true {
            let data = try await apiGateway.request(
                path: "api/v2/mobile-device-prestages/\(prestageID)/scope",
                method: .get,
                queryItems: [
                    URLQueryItem(name: "page", value: String(page)),
                    URLQueryItem(name: "page-size", value: String(pageSize))
                ]
            )

            let pageSerials = parseMobileScopeSerials(from: data)
            let previousCount = serials.count
            serials.formUnion(pageSerials.compactMap(normalizeSerial))
            let appendedCount = serials.count - previousCount

            if pageSerials.isEmpty || pageSerials.count < pageSize || appendedCount == 0 {
                break
            }

            page += 1
        }

        return serials
    }

    // MARK: - Prestage JSON Parsing

    /// Parses an array of prestage summaries from raw API response data.
    ///
    /// Searches the JSON for an array of objects under well-known keys (results,
    /// prestages, mobileDevicePrestages, items, data), then extracts ID and name
    /// from each element.
    private func parseMobilePrestageSummaries(from data: Data) -> [MobilePrestageSummary] {
        let jsonObject: Any
        do {
            jsonObject = try JSONSerialization.jsonObject(with: data)
        } catch {
            reportError(category: "prestage", message: "Failed to parse mobile prestage summaries JSON.", errorDescription: describe(error))
            return []
        }

        if let dictionary = jsonObject as? [String: Any] {
            let candidateArrays: [Any?] = [
                dictionary["results"],
                dictionary["prestages"],
                dictionary["mobileDevicePrestages"],
                dictionary["items"],
                dictionary["data"]
            ]

            for candidate in candidateArrays {
                guard let objects = dictionaryArray(from: candidate), objects.isEmpty == false else {
                    continue
                }

                let parsed = objects.compactMap(parseMobilePrestageSummary(from:))
                if parsed.isEmpty == false {
                    return parsed
                }
            }

            for nestedValue in dictionary.values {
                guard let objects = dictionaryArray(from: nestedValue), objects.isEmpty == false else {
                    continue
                }

                let parsed = objects.compactMap(parseMobilePrestageSummary(from:))
                if parsed.isEmpty == false {
                    return parsed
                }
            }
        }

        guard let objects = dictionaryArray(from: jsonObject) else {
            return []
        }

        return objects.compactMap(parseMobilePrestageSummary(from:))
    }

    /// Extracts a single prestage summary (ID + name) from a JSON dictionary.
    /// Returns `nil` if no ID can be found.
    private func parseMobilePrestageSummary(from item: [String: Any]) -> MobilePrestageSummary? {
        guard let id = extractString(from: item["id"]) ?? extractString(from: item["prestageId"]) else {
            return nil
        }

        let name =
            extractString(from: item["displayName"]) ??
            extractString(from: item["name"]) ??
            extractString(from: item["profileName"]) ??
            "Pre-Stage \(id)"

        return MobilePrestageSummary(id: id, name: name)
    }

    /// Parses serial numbers from a prestage scope API response.
    ///
    /// Handles multiple response shapes: arrays of assignment objects with serial keys,
    /// nested serial number arrays, or flat string arrays.
    private func parseMobileScopeSerials(from data: Data) -> [String] {
        let jsonObject: Any
        do {
            jsonObject = try JSONSerialization.jsonObject(with: data)
        } catch {
            reportError(category: "prestage", message: "Failed to parse mobile scope serials JSON.", errorDescription: describe(error))
            return []
        }

        if let dictionary = jsonObject as? [String: Any] {
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

                let serials = objects.compactMap(parseMobileScopeSerial(from:))
                if serials.isEmpty == false {
                    return serials
                }
            }

            for nestedValue in dictionary.values {
                guard let objects = dictionaryArray(from: nestedValue), objects.isEmpty == false else {
                    continue
                }

                let serials = objects.compactMap(parseMobileScopeSerial(from:))
                if serials.isEmpty == false {
                    return serials
                }
            }

            // Try extracting a flat serial number array
            if let serialNumbers =
                extractStringArray(from: dictionary["serialNumbers"]) ??
                extractStringArray(from: (dictionary["assignments"] as? [String: Any])?["serialNumbers"])
            {
                return serialNumbers.compactMap(normalizeSerial)
            }
        }

        if let objects = dictionaryArray(from: jsonObject), objects.isEmpty == false {
            return objects.compactMap(parseMobileScopeSerial(from:))
        }

        if let serialNumbers = extractStringArray(from: jsonObject) {
            return serialNumbers.compactMap(normalizeSerial)
        }

        return []
    }

    /// Extracts a serial number from a single scope assignment dictionary.
    ///
    /// Checks direct keys first, then looks inside nested device objects,
    /// and finally does a fuzzy key-name match as a last resort.
    private func parseMobileScopeSerial(from item: [String: Any]) -> String? {
        var serial =
            extractString(from: item["serialNumber"]) ??
            extractString(from: item["serial"]) ??
            extractString(from: item["hardwareSerialNumber"])

        // Check nested device objects for the serial number
        let nestedKeys = ["mobileDevice", "device", "inventoryRecord", "inventory", "item"]
        for key in nestedKeys {
            guard let nested = item[key] as? [String: Any] else {
                continue
            }

            serial = serial ??
                extractString(from: nested["serialNumber"]) ??
                extractString(from: nested["serial"])
        }

        // Last resort: fuzzy key matching for any key containing "serial"
        if serial == nil {
            serial = extractValue(matching: "serial", in: item)
        }

        return normalizeSerial(serial)
    }

    /// Resolves the display name of a prestage profile by its ID, using the cache
    /// or fetching from the API if not yet cached.
    ///
    /// - Parameter profileID: The prestage profile ID to look up.
    /// - Returns: The profile's display name, or `nil` if it cannot be resolved.
    private func resolvePrestageName(forProfileID profileID: String) async -> String? {
        if let cached = prestageNameCache[profileID] {
            return cached
        }

        do {
            let profileData = try await apiGateway.request(
                path: "api/v2/mobile-device-prestages/\(profileID)",
                method: .get
            )

            if let profileName = extractProfileName(fromPrestageDetails: profileData) {
                prestageNameCache[profileID] = profileName
                return profileName
            }
        } catch {
            let description = describe(error)
            await diagnosticsReporter.reportError(
                source: moduleSource,
                category: "prestage",
                message: "Failed reading Pre-Stage Enrollment profile details.",
                errorDescription: description,
                metadata: [
                    "prestage_profile_id": profileID
                ]
            )
        }

        return nil
    }

    // MARK: - Normalization Helpers

    /// Trims whitespace and returns `nil` for empty strings.
    private func normalizePrestageComponent(_ value: String?) -> String? {
        guard let value else {
            return nil
        }

        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    /// Normalizes a raw prestage status string into "Enrolled" or "Not Enrolled".
    ///
    /// Handles various representations from different Jamf Pro versions:
    /// boolean strings ("true"/"false"), management labels ("managed"/"unmanaged"),
    /// and enrollment labels ("enrolled"/"not enrolled"). Unrecognized values are
    /// returned as-is.
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
    /// Returns `nil` for empty or whitespace-only inputs.
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

    // MARK: - Value Extraction Utilities

    /// Extracts an array of non-empty strings from a JSON value.
    ///
    /// Handles direct string arrays, heterogeneous arrays (extracting string
    /// representations), and dictionaries with known array-valued keys.
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

    /// Searches a dictionary for the first key whose name contains the given fragment
    /// (case-insensitive) and returns its string value. Recurses into nested dictionaries.
    ///
    /// This is a last-resort extraction strategy used when the exact key name is unknown.
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

    /// Extracts the prestage enrollment status from raw API response data.
    private func extractPrestageEnrollmentStatus(from data: Data) -> String? {
        let jsonObject: Any
        do {
            jsonObject = try JSONSerialization.jsonObject(with: data)
        } catch {
            reportError(category: "prestage", message: "Failed to parse prestage enrollment status JSON.", errorDescription: describe(error))
            return nil
        }

        return extractPrestageEnrollmentStatus(from: jsonObject)
    }

    /// Recursively searches a JSON value for a prestage enrollment status field.
    ///
    /// Checks preferred keys first (`prestageEnrollmentStatus`, `managementStatus`, etc.),
    /// then searches keys whose names contain "enroll" or "managed", and finally recurses
    /// into nested objects.
    private func extractPrestageEnrollmentStatus(from value: Any) -> String? {
        if let dictionary = value as? [String: Any] {
            let preferredKeys = [
                "prestageEnrollmentStatus",
                "managementStatus",
                "enrollmentStatus",
                "managed",
                "isManaged",
                "enrolled",
                "isEnrolled"
            ]

            for key in preferredKeys {
                if let normalized = normalizePrestageStatus(extractString(from: dictionary[key])) {
                    return normalized
                }
            }

            for (key, nestedValue) in dictionary {
                let normalizedKey = key.lowercased()
                if normalizedKey.contains("enroll") || normalizedKey.contains("managed") {
                    if let normalized = normalizePrestageStatus(extractString(from: nestedValue)) {
                        return normalized
                    }
                }

                if let nested = extractPrestageEnrollmentStatus(from: nestedValue) {
                    return nested
                }
            }
        }

        if let array = value as? [Any] {
            for element in array {
                if let nested = extractPrestageEnrollmentStatus(from: element) {
                    return nested
                }
            }
        }

        return nil
    }

    /// Extracts a prestage profile name and ID tuple from raw API response data.
    private func extractPrestageNameAndID(from data: Data) -> (name: String?, id: String?) {
        let json: Any
        do {
            json = try JSONSerialization.jsonObject(with: data)
        } catch {
            reportError(category: "prestage", message: "Failed to parse prestage name and ID JSON.", errorDescription: describe(error))
            return (nil, nil)
        }

        return extractPrestageNameAndID(from: json)
    }

    /// Recursively searches a JSON value for prestage profile name and ID.
    ///
    /// Checks direct keys, nested `prestageEnrollmentProfile` objects, and keys
    /// whose names contain "prestage" with "name" or "id" suffixes. Returns as
    /// soon as at least one component is found.
    private func extractPrestageNameAndID(from value: Any) -> (name: String?, id: String?) {
        if let dictionary = value as? [String: Any] {
            var foundName = extractString(from: dictionary["prestageEnrollmentProfileName"])
            var foundID =
                extractString(from: dictionary["prestageEnrollmentProfileId"]) ??
                extractString(from: dictionary["prestageId"])

            if let prestageObject = dictionary["prestageEnrollmentProfile"] {
                let nested = extractPrestageNameAndID(from: prestageObject)
                foundName = foundName ?? nested.name
                foundID = foundID ?? nested.id
            }

            // Search keys containing "prestage" for name/id fragments
            for (key, nestedValue) in dictionary where key.lowercased().contains("prestage") {
                let lowerKey = key.lowercased()

                if foundName == nil && lowerKey.contains("name") {
                    foundName = extractString(from: nestedValue)
                }

                if foundID == nil && lowerKey.contains("id") {
                    foundID = extractString(from: nestedValue)
                }

                if foundName == nil || foundID == nil {
                    let nested = extractPrestageNameAndID(from: nestedValue)
                    foundName = foundName ?? nested.name
                    foundID = foundID ?? nested.id
                }
            }

            if foundName != nil || foundID != nil {
                return (foundName, foundID)
            }

            for nestedValue in dictionary.values {
                let nested = extractPrestageNameAndID(from: nestedValue)
                if nested.name != nil || nested.id != nil {
                    return nested
                }
            }
        }

        if let array = value as? [Any] {
            for element in array {
                let nested = extractPrestageNameAndID(from: element)
                if nested.name != nil || nested.id != nil {
                    return nested
                }
            }
        }

        return (nil, nil)
    }

    /// Extracts a profile display name from prestage detail API response data.
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

    /// Recursively searches a JSON value for a profile display name,
    /// checking `displayName`, `name`, and `profileName` keys.
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

    /// Extracts a trimmed, non-empty string from a loosely-typed JSON value.
    ///
    /// Handles strings, booleans, integers, doubles, NSNumbers, dictionaries
    /// (looking for displayName/name/value/id), and arrays (joining elements
    /// with commas). Returns `nil` for empty or unrecognized values.
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
            // Try well-known display keys within a nested object
            return
                extractString(from: dictionary["displayName"]) ??
                extractString(from: dictionary["name"]) ??
                extractString(from: dictionary["value"]) ??
                extractString(from: dictionary["id"])
        case let array as [Any]:
            // Flatten array elements into a comma-separated string
            let flattened = array.compactMap { extractString(from: $0) }
                .filter { $0.isEmpty == false }

            guard flattened.isEmpty == false else {
                return nil
            }

            return flattened.joined(separator: ", ")
        default:
            return nil
        }
    }

    // MARK: - Error Handling

    /// Returns the localized description for an error, preferring `LocalizedError.errorDescription`.
    private func describe(_ error: any Error) -> String {
        (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
    }

    /// Produces a user-friendly error message for search failures.
    ///
    /// Special-cases permission errors (403 with `INVALID_PRIVILEGE` body)
    /// with actionable guidance, and section parameter errors with a
    /// clear explanation. Falls back to the raw error description for
    /// other failures.
    ///
    /// The 403 check matches BOTH typed `.forbidden(message)` and untyped
    /// `.networkFailure(403, message)` — matching only the untyped form
    /// (the prior implementation) silently dropped typed 403s back to the
    /// raw description, so technicians saw a cryptic message instead of
    /// the actionable privilege guidance.
    private func userFacingSearchErrorMessage(for error: any Error) -> String {
        if error.isJamfInvalidPrivilege, privilegeBodyMentionsInvalidPrivilege(error) {
            return "Mobile device search was denied by Jamf. Verify API Role privileges for Mobile Device Inventory sections and Read Mobile Devices access."
        }

        if isSectionParameterError(error) {
            return "Mobile device search failed because the server rejected inventory section parameters."
        }

        return describe(error)
    }

    /// `true` when the 403 error body contains Jamf's `INVALID_PRIVILEGE`
    /// marker, for either a typed `.forbidden(message)` or an untyped
    /// `.networkFailure(403, message)`.
    private func privilegeBodyMentionsInvalidPrivilege(_ error: any Error) -> Bool {
        switch error {
        case let JamfFrameworkError.forbidden(message):
            return message.localizedCaseInsensitiveContains("INVALID_PRIVILEGE")
        case let JamfFrameworkError.networkFailure(_, message):
            return message.localizedCaseInsensitiveContains("INVALID_PRIVILEGE")
        default:
            return false
        }
    }

    /// Determines whether an error is caused by the Jamf Pro server rejecting
    /// the inventory section query parameter type or value.
    ///
    /// This check drives the automatic section encoding fallback logic.
    private func isSectionParameterError(_ error: any Error) -> Bool {
        guard case let JamfFrameworkError.networkFailure(statusCode, message) = error else {
            return false
        }

        guard statusCode == 400 else {
            return false
        }

        let normalizedMessage = message.lowercased()
        guard normalizedMessage.contains(sectionParameterName) else {
            return false
        }

        if normalizedMessage.contains(sectionParameterTypeErrorCode.lowercased()) {
            return true
        }

        return normalizedMessage.contains("invalid value of request parameter") ||
            normalizedMessage.contains("required type: java.util.set")
    }

    // MARK: - Diagnostics

    /// Reports a diagnostic event asynchronously via the diagnostics reporter.
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

    /// Reports a diagnostic error asynchronously via the diagnostics reporter.
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
