import Foundation

// Typed models for the bundled Forsetti Permissions Matrix v4 resource.
//
// These decode the verified matrix JSON
// (`jamf_dashboard_permissions_matrix.v4.module_resource.json`) into strongly
// typed values. The matrix is advisory/diagnostic only — it documents which Jamf
// Pro privileges a Forsetti action or API endpoint requires. Jamf Pro
// remains the source of truth for authorization.
//
// The shapes here mirror the *actual* JSON, which is richer than the reference
// sketches shipped with the handoff package: `privileges` is a flat `[String]`,
// requirements carry a `mode` plus one of several privilege containers, and
// catalog entries describe both the modern `/api` and Classic `/JSSResource`
// surfaces.

// MARK: - Document Root

/// The decoded root of the Permissions Matrix resource.
struct PermissionsMatrixDocument: Decodable {
    let schemaVersion: String
    let artifact: String?
    let generatedAtUTC: String?
    let project: String?
    let jamfDocsReference: JamfDocsReference?
    let coverageStatement: CoverageStatement?
    let authorizationModel: AuthorizationModel?
    /// The full catalog of Jamf Pro privilege names (flat list of strings).
    let privileges: [String]
    /// Forsetti actions/commands and their required privileges.
    let actions: [PermissionsMatrixAction]
    /// The modern and Classic API endpoint privilege catalogs plus MDM overlays.
    let endpointCatalog: APIEndpointPrivilegeCatalog
    let sourceObservedEndpoints: [String]?
    let sourceCoverage: SourceCoverage?
    let verificationSummary: VerificationSummary?

    enum CodingKeys: String, CodingKey {
        case schemaVersion = "schema_version"
        case artifact
        case generatedAtUTC = "generated_at_utc"
        case project
        case jamfDocsReference = "jamf_docs_reference"
        case coverageStatement = "coverage_statement"
        case authorizationModel = "authorization_model"
        case privileges
        case actions = "jamf_dashboard_actions"
        case endpointCatalog = "api_endpoint_privilege_catalog"
        case sourceObservedEndpoints = "source_observed_endpoints"
        case sourceCoverage = "source_coverage_v4"
        case verificationSummary = "verification_summary_v4"
    }
}

// MARK: - Metadata Blocks

/// Reference to the Jamf developer-portal docs the matrix was verified against.
struct JamfDocsReference: Decodable {
    let developerPortalVersionObserved: String?
    let docsCheckedUTC: String?
    let officialURLs: [String]?

    enum CodingKeys: String, CodingKey {
        case developerPortalVersionObserved = "developer_portal_version_observed"
        case docsCheckedUTC = "docs_checked_utc"
        case officialURLs = "official_urls"
    }
}

/// Plain-language statement of what the matrix covers.
struct CoverageStatement: Decodable {
    let scope: String?
    let sourceTruthLayers: [String]?
    let v4Corrections: [String]?

    enum CodingKeys: String, CodingKey {
        case scope
        case sourceTruthLayers = "source_truth_layers"
        case v4Corrections = "v4_corrections"
    }
}

/// Describes who controls Jamf authorization. Reinforces that the dashboard is
/// advisory and never grants/overrides privileges locally.
struct AuthorizationModel: Decodable {
    let controlledBy: [String]?
    let dashboardBehavior: String?
    let mdmCommandNote: String?

    enum CodingKeys: String, CodingKey {
        case controlledBy = "controlled_by"
        case dashboardBehavior = "dashboard_behavior"
        case mdmCommandNote = "mdm_command_note"
    }
}

/// Source-audit coverage summary (v4).
struct SourceCoverage: Decodable {
    let sourceEndpointCount: Int?
    let catalogAndActionPathCount: Int?
    let uncoveredSourceEndpointCount: Int?
    let coverageMethod: String?

    enum CodingKeys: String, CodingKey {
        case sourceEndpointCount = "source_endpoint_count"
        case catalogAndActionPathCount = "catalog_and_action_path_count"
        case uncoveredSourceEndpointCount = "uncovered_source_endpoint_count"
        case coverageMethod = "coverage_method"
    }
}

/// The validator-facing count summary baked into the resource.
struct VerificationSummary: Decodable {
    let actions: Int?
    let privileges: Int?
    let modernEndpointCatalogEntries: Int?
    let classicEndpointCatalogEntries: Int?
    let mdmCommandTypeOverlays: Int?
    let currentSourceObservedEndpoints: Int?
    let uncoveredSourceEndpoints: Int?

    enum CodingKeys: String, CodingKey {
        case actions = "jamf_dashboard_actions"
        case privileges
        case modernEndpointCatalogEntries = "modern_endpoint_catalog_entries"
        case classicEndpointCatalogEntries = "classic_endpoint_catalog_entries"
        case mdmCommandTypeOverlays = "mdm_command_type_overlays"
        case currentSourceObservedEndpoints = "current_source_observed_endpoints"
        case uncoveredSourceEndpoints = "uncovered_source_endpoints"
    }
}

// MARK: - Actions

/// A single Forsetti action/command and the privileges it requires.
struct PermissionsMatrixAction: Decodable, Identifiable, Hashable {
    var id: String { commandID }

    let commandID: String
    let displayName: String?
    let module: String?
    let category: String?
    /// e.g. `read`, `command`, `create`, `update`, `delete`, `local`.
    let actionType: String?
    /// e.g. `computer`, `mobile_device`, `mixed`, `tenant`.
    let assetScope: String?
    let implementationIDs: [String]
    let endpoints: [ActionEndpoint]
    let requiredPrivilegeRequirements: [PrivilegeRequirement]
    let localOnly: Bool
    let destructive: Bool
    let deprecatedOrLegacy: Bool
    let securitySensitive: Bool?
    let sourceFiles: [String]
    let uiTags: [String]
    let notes: [String]

    enum CodingKeys: String, CodingKey {
        case commandID = "command_id"
        case displayName = "display_name"
        case module
        case category
        case actionType = "action_type"
        case assetScope = "asset_scope"
        case implementationIDs = "implementation_ids"
        case endpoints
        case requiredPrivilegeRequirements = "required_privilege_requirements"
        case localOnly = "local_only"
        case destructive
        case deprecatedOrLegacy = "deprecated_or_legacy"
        case securitySensitive = "security_sensitive"
        case sourceFiles = "source_files"
        case uiTags = "ui_tags"
        case notes
    }

    // Resilient decode: tolerate missing optional arrays/flags rather than fail
    // the whole document if a future entry omits one.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        commandID = try c.decode(String.self, forKey: .commandID)
        displayName = try c.decodeIfPresent(String.self, forKey: .displayName)
        module = try c.decodeIfPresent(String.self, forKey: .module)
        category = try c.decodeIfPresent(String.self, forKey: .category)
        actionType = try c.decodeIfPresent(String.self, forKey: .actionType)
        assetScope = try c.decodeIfPresent(String.self, forKey: .assetScope)
        implementationIDs = try c.decodeIfPresent([String].self, forKey: .implementationIDs) ?? []
        endpoints = try c.decodeIfPresent([ActionEndpoint].self, forKey: .endpoints) ?? []
        requiredPrivilegeRequirements = try c.decodeIfPresent([PrivilegeRequirement].self, forKey: .requiredPrivilegeRequirements) ?? []
        localOnly = try c.decodeIfPresent(Bool.self, forKey: .localOnly) ?? false
        destructive = try c.decodeIfPresent(Bool.self, forKey: .destructive) ?? false
        deprecatedOrLegacy = try c.decodeIfPresent(Bool.self, forKey: .deprecatedOrLegacy) ?? false
        securitySensitive = try c.decodeIfPresent(Bool.self, forKey: .securitySensitive)
        sourceFiles = try c.decodeIfPresent([String].self, forKey: .sourceFiles) ?? []
        uiTags = try c.decodeIfPresent([String].self, forKey: .uiTags) ?? []
        notes = try c.decodeIfPresent([String].self, forKey: .notes) ?? []
    }

    /// The title shown in lists, falling back to the command ID.
    var resolvedDisplayName: String {
        if let displayName, displayName.isEmpty == false { return displayName }
        return commandID
    }

    /// Every distinct privilege name referenced by this action, across all
    /// requirement containers, in first-seen order.
    var allPrivilegeNames: [String] {
        var seen = Set<String>()
        var ordered: [String] = []
        for requirement in requiredPrivilegeRequirements {
            for name in requirement.allPrivilegeNames where seen.insert(name).inserted {
                ordered.append(name)
            }
        }
        return ordered
    }

    /// The hard-required privilege names: every `all_of` name, plus the
    /// device-family branch of any `conditional_all_of_by_asset_type`
    /// requirement (selected by this action's `assetScope`).
    ///
    /// This is the single source of truth used by both the runtime verifier and
    /// the unit tests, so the "what does this action require" rule lives with the
    /// data it describes.
    var hardRequiredPrivilegeNames: [String] {
        var ordered: [String] = []
        var seen = Set<String>()
        func add(_ names: [String]) {
            for name in names where seen.insert(name).inserted { ordered.append(name) }
        }
        for requirement in requiredPrivilegeRequirements {
            switch requirement.mode {
            case "all_of":
                add(requirement.privileges ?? [])
            case "conditional_all_of_by_asset_type":
                switch assetScope {
                case "computer": add(requirement.computerPrivileges ?? [])
                case "mobile_device": add(requirement.mobileDevicePrivileges ?? [])
                case "mixed": add(requirement.mixedOrGroupPrivileges ?? [])
                default: add(requirement.allPrivilegeNames) // unknown scope — hide nothing
                }
            default:
                break // any_of / optional_runtime_overlay are alternatives
            }
        }
        return ordered
    }

    /// Optional/alternative privilege names (`any_of` and `optional_runtime_overlay`).
    var alternativePrivilegeNames: [String] {
        var ordered: [String] = []
        var seen = Set<String>()
        for requirement in requiredPrivilegeRequirements where requirement.isAdvisoryOrAlternative {
            for name in requirement.allPrivilegeNames where seen.insert(name).inserted {
                ordered.append(name)
            }
        }
        return ordered
    }

    /// True when any requirement carries tenant-verification confidence — i.e.
    /// the operator should confirm against their tenant `/api/doc`.
    var needsTenantVerification: Bool {
        requiredPrivilegeRequirements.contains { $0.needsTenantVerification }
    }

    /// A friendly device-family label derived from `assetScope`.
    var deviceFamilyLabel: String {
        PermissionsMatrixAction.deviceFamilyLabel(for: assetScope)
    }

    static func deviceFamilyLabel(for assetScope: String?) -> String {
        switch assetScope {
        case "computer": return "Computer"
        case "mobile_device": return "Mobile Device"
        case "mixed": return "Computer & Mobile"
        case "tenant": return "Tenant"
        default: return assetScope?.capitalized ?? "Unspecified"
        }
    }
}

/// An endpoint invoked by an action.
struct ActionEndpoint: Decodable, Identifiable, Hashable {
    var id: String { "\(method) \(path)" }
    let method: String
    let path: String
    /// Action endpoints use `modern` / `classic` here.
    let apiSurface: String?

    enum CodingKeys: String, CodingKey {
        case method, path
        case apiSurface = "api_surface"
    }

    var isClassic: Bool {
        let surface = (apiSurface ?? "").lowercased()
        return surface.contains("classic") || path.contains("JSSResource")
    }
}

/// A single privilege requirement attached to an action.
///
/// The matrix expresses requirements in several `mode`s:
/// - `all_of` — every name in `privileges` is required.
/// - `any_of` — any one of the inner `privilegeSets` (each an AND group) suffices.
/// - `optional_runtime_overlay` — advisory overlay privileges (`privilegeSets`)
///   that may apply only when the tenant token/API role exposes them.
/// - `conditional_all_of_by_asset_type` — the required set depends on the
///   device family (`computerPrivileges` / `mobileDevicePrivileges` /
///   `mixedOrGroupPrivileges`).
struct PrivilegeRequirement: Decodable, Hashable {
    let mode: String
    let privileges: [String]?
    let privilegeSets: [[String]]?
    let computerPrivileges: [String]?
    let mobileDevicePrivileges: [String]?
    let mixedOrGroupPrivileges: [String]?
    let confidence: String?
    let source: String?
    let note: String?

    enum CodingKeys: String, CodingKey {
        case mode, privileges, confidence, source, note
        case privilegeSets = "privilege_sets"
        case computerPrivileges = "computer_privileges"
        case mobileDevicePrivileges = "mobile_device_privileges"
        case mixedOrGroupPrivileges = "mixed_or_group_privileges"
    }

    /// `true` for advisory overlays / alternative sets that should not be
    /// reported as definitively missing during runtime comparison.
    var isAdvisoryOrAlternative: Bool {
        mode == "optional_runtime_overlay" || mode == "any_of"
    }

    var needsTenantVerification: Bool {
        guard let confidence = confidence?.lowercased() else { return false }
        return confidence.contains("tenant") || confidence.contains("runtime_verify") || confidence.contains("explorer")
    }

    /// Every privilege name referenced by this requirement, regardless of mode.
    var allPrivilegeNames: [String] {
        var ordered: [String] = []
        if let privileges { ordered.append(contentsOf: privileges) }
        if let privilegeSets { ordered.append(contentsOf: privilegeSets.flatMap { $0 }) }
        if let computerPrivileges { ordered.append(contentsOf: computerPrivileges) }
        if let mobileDevicePrivileges { ordered.append(contentsOf: mobileDevicePrivileges) }
        if let mixedOrGroupPrivileges { ordered.append(contentsOf: mixedOrGroupPrivileges) }
        return ordered
    }

    /// A human-readable label for the requirement's mode.
    var modeDescription: String {
        switch mode {
        case "all_of": return "All of the following"
        case "any_of": return "Any one of the following sets"
        case "optional_runtime_overlay": return "Optional runtime overlay (tenant-dependent)"
        case "conditional_all_of_by_asset_type": return "Required by device family"
        default: return mode.replacingOccurrences(of: "_", with: " ").capitalized
        }
    }
}

// MARK: - Endpoint Privilege Catalog

/// The modern and Classic API endpoint privilege catalogs plus MDM overlays.
struct APIEndpointPrivilegeCatalog: Decodable {
    let modernJamfProAPI: [EndpointPrivilegeEntry]
    let classicAPI: [EndpointPrivilegeEntry]
    let mdmCommandTypeOverlays: [MDMCommandOverlay]

    enum CodingKeys: String, CodingKey {
        case modernJamfProAPI = "modern_jamf_pro_api"
        case classicAPI = "classic_api"
        case mdmCommandTypeOverlays = "mdm_command_type_overlays"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        modernJamfProAPI = try c.decodeIfPresent([EndpointPrivilegeEntry].self, forKey: .modernJamfProAPI) ?? []
        classicAPI = try c.decodeIfPresent([EndpointPrivilegeEntry].self, forKey: .classicAPI) ?? []
        mdmCommandTypeOverlays = try c.decodeIfPresent([MDMCommandOverlay].self, forKey: .mdmCommandTypeOverlays) ?? []
    }
}

/// One catalogued endpoint and the privileges Jamf Pro requires for it.
struct EndpointPrivilegeEntry: Decodable, Identifiable, Hashable {
    var id: String { endpointID ?? "\(method) \(path)" }
    let endpointID: String?
    /// Catalog entries use `jamf_pro_api` / `classic_api` here.
    let apiSurface: String?
    let method: String
    let path: String
    let family: String?
    let purpose: String?
    let requiredPrivileges: [String]
    let deprecationDate: String?
    let confidence: String?
    let source: String?
    let notes: [String]

    enum CodingKeys: String, CodingKey {
        case endpointID = "endpoint_id"
        case apiSurface = "api_surface"
        case method, path, family, purpose
        case requiredPrivileges = "required_privileges"
        case deprecationDate = "deprecation_date"
        case confidence, source, notes
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        endpointID = try c.decodeIfPresent(String.self, forKey: .endpointID)
        apiSurface = try c.decodeIfPresent(String.self, forKey: .apiSurface)
        method = try c.decode(String.self, forKey: .method)
        path = try c.decode(String.self, forKey: .path)
        family = try c.decodeIfPresent(String.self, forKey: .family)
        purpose = try c.decodeIfPresent(String.self, forKey: .purpose)
        requiredPrivileges = try c.decodeIfPresent([String].self, forKey: .requiredPrivileges) ?? []
        deprecationDate = try c.decodeIfPresent(String.self, forKey: .deprecationDate)
        confidence = try c.decodeIfPresent(String.self, forKey: .confidence)
        source = try c.decodeIfPresent(String.self, forKey: .source)
        notes = try c.decodeIfPresent([String].self, forKey: .notes) ?? []
    }

    var isClassic: Bool {
        let surface = (apiSurface ?? "").lowercased()
        return surface.contains("classic") || path.contains("JSSResource")
    }

    /// A deprecation note when the entry carries a real date (not "N/A").
    var deprecationNote: String? {
        guard let date = deprecationDate?.trimmingCharacters(in: .whitespaces),
              date.isEmpty == false,
              date.caseInsensitiveCompare("N/A") != .orderedSame else {
            return nil
        }
        return date
    }

    var needsTenantVerification: Bool {
        guard let confidence = confidence?.lowercased() else { return false }
        return confidence.contains("tenant") || confidence.contains("runtime_verify") || confidence.contains("explorer")
    }
}

/// A per-MDM-command-type privilege overlay that layers on top of the
/// endpoint-level requirement for `/api/v2/mdm/commands`.
struct MDMCommandOverlay: Decodable, Identifiable, Hashable {
    var id: String { commandType }
    let commandType: String
    let platforms: [String]
    let additionalRequiredPrivileges: [String]
    let confidence: String?
    let notes: String?

    enum CodingKeys: String, CodingKey {
        case commandType = "command_type"
        case platforms
        case additionalRequiredPrivileges = "additional_required_privileges"
        case confidence, notes
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        commandType = try c.decode(String.self, forKey: .commandType)
        platforms = try c.decodeIfPresent([String].self, forKey: .platforms) ?? []
        additionalRequiredPrivileges = try c.decodeIfPresent([String].self, forKey: .additionalRequiredPrivileges) ?? []
        confidence = try c.decodeIfPresent(String.self, forKey: .confidence)
        notes = try c.decodeIfPresent(String.self, forKey: .notes)
    }
}

// MARK: - Filtering

/// Pure action-matching used by the command explorer. Lives here (not in the
/// view model) so the rule has a single source of truth and is unit-testable
/// without constructing the full view model / API gateway.
enum PermissionsMatrixActionFilter {
    static func matches(
        _ action: PermissionsMatrixAction,
        query: String,
        module: String?,
        deviceFamily: String?,
        destructiveOnly: Bool,
        tenantVerificationOnly: Bool
    ) -> Bool {
        if let module, action.module != module { return false }
        if let deviceFamily, action.assetScope != deviceFamily { return false }
        if destructiveOnly, action.destructive == false { return false }
        if tenantVerificationOnly, action.needsTenantVerification == false { return false }

        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard trimmed.isEmpty == false else { return true }

        if action.resolvedDisplayName.lowercased().contains(trimmed) { return true }
        if action.commandID.lowercased().contains(trimmed) { return true }
        if let value = action.module?.lowercased(), value.contains(trimmed) { return true }
        if let value = action.category?.lowercased(), value.contains(trimmed) { return true }
        if action.allPrivilegeNames.contains(where: { $0.lowercased().contains(trimmed) }) { return true }
        if action.endpoints.contains(where: { $0.path.lowercased().contains(trimmed) }) { return true }
        return false
    }
}

//endofline
