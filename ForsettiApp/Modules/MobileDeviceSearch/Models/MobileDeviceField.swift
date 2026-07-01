import Foundation

// "Would you like to play a game?"

/// Enumerates the inventory sections available in the Jamf Pro mobile device API.
///
/// Each case maps to a specific `section` query parameter value recognized by the
/// Jamf Pro v2 mobile device detail endpoint. The raw values match the modern
/// parameter names used by current Jamf Pro versions; legacy name translation
/// is handled separately in the view model.
enum MobileDeviceInventorySection: String, CaseIterable, Sendable {
    /// General device information such as name, UDID, OS version, and enrollment details.
    case general = "GENERAL"
    /// User and location fields including username, email, department, and building.
    case location = "USER_AND_LOCATION"
    /// Hardware attributes like model, serial number, and model identifier.
    case hardware = "HARDWARE"
    /// Purchasing information including warranty and lease details.
    case purchasing = "PURCHASING"
    /// Security posture data such as passcode compliance and encryption status.
    case security = "SECURITY"
    /// Installed applications on the device.
    case applications = "APPLICATIONS"
    /// E-books deployed to the device.
    case ebooks = "EBOOKS"
    /// Network interface details (Wi-Fi, cellular, etc.).
    case network = "NETWORK"
    /// Carrier service subscription information.
    case serviceSubscriptions = "SERVICE_SUBSCRIPTIONS"
    /// Installed certificates on the device.
    case certificates = "CERTIFICATES"
    /// Configuration profiles installed on the device.
    case configurationProfiles = "PROFILES"
    /// User-level profiles on the device.
    case userProfiles = "USER_PROFILES"
    /// Provisioning profiles for app distribution.
    case provisioningProfiles = "PROVISIONING_PROFILES"
    /// Shared iPad user accounts on the device.
    case sharedUsers = "SHARED_USERS"
    /// Custom extension attribute values defined in Jamf Pro.
    case extensionAttributes = "EXTENSION_ATTRIBUTES"
    /// Smart and static mobile device group memberships.
    case mobileDeviceGroups = "GROUPS"
}

/// Represents a single selectable inventory field that can be included in search results.
///
/// Each `MobileDeviceField` defines how to display a field in the UI (`displayName`),
/// how to look it up programmatically (`key`), which inventory section it belongs to,
/// and an ordered list of JSON key paths (`responsePaths`) to try when extracting the
/// field's value from varying Jamf Pro API response shapes.
struct MobileDeviceField: Identifiable, Hashable, Sendable {
    /// The programmatic key used to store and retrieve this field's value in dictionaries.
    let key: String

    /// The human-readable label shown in the field catalog and result rows.
    let displayName: String

    /// A brief explanation of what this field contains, shown as helper text in the UI.
    let description: String

    /// The inventory section this field belongs to, used to request the correct data from the API.
    let section: MobileDeviceInventorySection

    /// An ordered list of dot-separated JSON key paths to try when extracting this field's value.
    /// The first path that yields a non-empty value wins. Multiple paths accommodate the
    /// different response shapes returned by various Jamf Pro versions and endpoints.
    let responsePaths: [String]

    /// The runtime value type. Drives the Advanced Search input control and the
    /// RSQL operator allowlist. Defaults to `.string` so existing catalog entries
    /// stay valid without explicit type annotation.
    let dataType: MobileDeviceFieldDataType

    /// Whether the field appears in the Advanced Search field picker as a queryable
    /// criterion. `false` means the field is hidden from the picker entirely
    /// (e.g. display-only sortable fields like `batteryHealth`). When `true`,
    /// `isServerFilterable` decides whether the criterion is emitted as RSQL
    /// or routed to the in-memory matcher.
    let isFilterable: Bool

    /// Whether the field is documented by Jamf as sortable on the inventory detail
    /// endpoint. Reserved for future sort UI; not currently consumed by any view.
    let isSortable: Bool

    /// Whether `JamfRSQLComposer` may emit a server-side RSQL fragment for
    /// criteria against this field. Defaults to `true`. Set to `false` for
    /// fields that are filterable from the user's perspective but whose RSQL
    /// support is unreliable or undocumented — currently the Pre-Stage
    /// Enrollment profile (resolved client-side via the prestage scope
    /// endpoint) and tenant Extension Attributes (RSQL syntax varies per
    /// Jamf Pro version, so we filter in memory after fetching).
    let isServerFilterable: Bool

    /// Closed allowed-values list for `dataType == .enumeration`. `nil` for all
    /// other types. The Advanced Search picker offers a multi-select control when
    /// this is non-nil.
    let allowedValues: [String]?

    /// Stable identity derived from the field's unique key.
    var id: String { key }

    /// Memberwise initializer with sensible defaults so existing catalog entries
    /// don't need to specify the new metadata. New entries should set
    /// `dataType` explicitly to get correct operator allowlists; otherwise the
    /// field will only support string-style operators.
    init(
        key: String,
        displayName: String,
        description: String,
        section: MobileDeviceInventorySection,
        responsePaths: [String],
        dataType: MobileDeviceFieldDataType = .string,
        isFilterable: Bool = true,
        isSortable: Bool = true,
        isServerFilterable: Bool = true,
        allowedValues: [String]? = nil
    ) {
        self.key = key
        self.displayName = displayName
        self.description = description
        self.section = section
        self.responsePaths = responsePaths
        self.dataType = dataType
        self.isFilterable = isFilterable
        self.isSortable = isSortable
        self.isServerFilterable = isServerFilterable
        self.allowedValues = allowedValues
    }
}

// "End of Line"

extension MobileDeviceField {
    /// The hand-curated catalog of fields the original module shipped with.
    ///
    /// `catalog` (the public API) merges these entries with `generatedCatalog`
    /// from `MobileDeviceFieldCatalog+Generated.swift`, preferring curated entries
    /// when keys collide. Curated entries can therefore override generated metadata
    /// without removing the generated row.
    static let curatedCatalog: [MobileDeviceField] = [
        .init(
            key: "id",
            displayName: "Record ID",
            description: "Internal Jamf mobile device record id.",
            section: .general,
            responsePaths: ["id", "mobileDeviceId", "deviceId", "hardware.deviceId"]
        ),
        .init(
            key: "deviceName",
            displayName: "Device Name",
            description: "User friendly device name.",
            section: .general,
            responsePaths: [
                "general.displayName",
                "general.deviceName",
                "general.name",
                "deviceName",
                "displayName",
                "name"
            ]
        ),
        .init(
            key: "serialNumber",
            displayName: "Serial Number",
            description: "Hardware serial number.",
            section: .hardware,
            responsePaths: ["hardware.serialNumber", "general.serialNumber", "serialNumber"]
        ),
        .init(
            key: "udid",
            displayName: "UDID",
            description: "Unique device identifier.",
            section: .general,
            responsePaths: ["general.udid", "udid"]
        ),
        .init(
            key: "assetTag",
            displayName: "Asset Tag",
            description: "Assigned inventory asset tag.",
            section: .general,
            responsePaths: ["general.assetTag", "assetTag"]
        ),
        .init(
            key: "model",
            displayName: "Model",
            description: "Device model string.",
            section: .hardware,
            responsePaths: ["hardware.model", "general.model", "model"]
        ),
        .init(
            key: "modelIdentifier",
            displayName: "Model Identifier",
            description: "Apple model identifier.",
            section: .hardware,
            responsePaths: ["hardware.modelIdentifier", "general.modelIdentifier", "modelIdentifier"]
        ),
        .init(
            key: "osVersion",
            displayName: "OS Version",
            description: "Installed iOS/iPadOS version.",
            section: .general,
            responsePaths: ["general.osVersion", "osVersion"]
        ),
        .init(
            key: "osBuild",
            displayName: "OS Build",
            description: "OS build number.",
            section: .general,
            responsePaths: ["general.osBuild", "osBuild"]
        ),
        .init(
            key: "managedAppleId",
            displayName: "Managed Apple ID",
            description: "Managed Apple ID assigned to the user.",
            section: .general,
            responsePaths: ["general.managedAppleId", "managedAppleId"]
        ),
        .init(
            key: "username",
            displayName: "Assigned Username",
            description: "Account username associated with the device.",
            section: .location,
            responsePaths: ["userAndLocation.username", "location.username", "username"]
        ),
        .init(
            key: "emailAddress",
            displayName: "Email Address",
            description: "Primary user email for the device.",
            section: .location,
            responsePaths: [
                "userAndLocation.emailAddress",
                "location.emailAddress",
                "location.email",
                "emailAddress",
                "email"
            ]
        ),
        .init(
            key: "phoneNumber",
            displayName: "Phone Number",
            description: "Associated phone number.",
            section: .location,
            responsePaths: ["userAndLocation.phoneNumber", "location.phoneNumber", "phoneNumber"]
        ),
        .init(
            key: "department",
            displayName: "Department",
            description: "Assigned department field.",
            section: .location,
            responsePaths: ["userAndLocation.department", "location.department", "department"]
        ),
        .init(
            key: "building",
            displayName: "Building",
            description: "Assigned building field.",
            section: .location,
            responsePaths: ["userAndLocation.building", "location.building", "building"]
        ),
        .init(
            key: "site",
            displayName: "Site",
            description: "Jamf site assignment.",
            section: .location,
            responsePaths: [
                "general.site.name",
                "general.siteId",
                "siteId",
                "location.site.name",
                "location.site",
                "site.name",
                "site"
            ]
        ),
        .init(
            key: "lastInventoryUpdate",
            displayName: "Last Inventory Update",
            description: "Most recent inventory sync timestamp.",
            section: .general,
            responsePaths: [
                "general.lastInventoryUpdateDate",
                "general.lastInventoryUpdate",
                "lastInventoryUpdateDate",
                "lastInventoryUpdate"
            ],
            dataType: .date
        ),
        .init(
            key: "enrollmentMethod",
            displayName: "Enrollment Method",
            description: "Method used to enroll the device.",
            section: .general,
            responsePaths: [
                "general.deviceOwnershipType",
                "general.enrollmentMethod",
                "enrollmentMethod",
                "deviceOwnershipType"
            ]
        ),
        .init(
            key: "prestageEnrollmentProfile",
            displayName: "Pre-Stage Enrollment",
            description: "Assigned Pre-Stage Enrollment profile for the device.",
            section: .general,
            responsePaths: [
                "general.enrollmentMethodPrestage.profileName",
                "general.enrollmentMethodPrestage.mobileDevicePrestageId",
                "general.prestageEnrollmentProfile.displayName",
                "general.prestageEnrollmentProfile.name",
                "general.prestageEnrollmentProfileName",
                "prestageEnrollmentProfileName",
                "general.prestageEnrollmentProfileId",
                "prestageEnrollmentProfileId",
                "prestageId",
                "prestageEnrollmentProfile"
            ],
            // Resolved client-side from /api/v2/mobile-device-prestages/{id}/scope.
            // Jamf does not expose prestage profile name to RSQL, so we keep
            // `isFilterable: true` (so users can pick it in the Advanced Search
            // picker) but flip `isServerFilterable: false` so the composer
            // routes the criterion to the in-memory matcher after the existing
            // `resolvePrestageEnrollmentProfiles(...)` enrichment runs.
            isServerFilterable: false
        ),
        .init(
            key: "managementId",
            displayName: "Management ID",
            description: "Management identifier from Jamf Pro.",
            section: .general,
            responsePaths: ["general.managementId", "managementId"]
        ),
        .init(
            key: "supervised",
            displayName: "Supervised",
            description: "Whether device is in supervised mode.",
            section: .general,
            responsePaths: ["general.supervised", "supervised"],
            dataType: .bool
        )
    ]

    /// The default set of field keys shown in results when no profile is selected.
    ///
    /// Provides a sensible out-of-the-box experience by including the most commonly
    /// needed identifiers: device name, serial number, username, model, and OS version.
    static let defaultResultFieldKeys: [String] = [
        "deviceName",
        "serialNumber",
        "username",
        "model",
        "osVersion"
    ]

    /// The full public catalog. Built lazily as a curated-first merge with the
    /// API-derived generated catalog so curated metadata wins on key collisions.
    /// Entries are ordered with curated rows first, then generated rows in the
    /// order they appear in the generated source.
    static let catalog: [MobileDeviceField] = mergedCatalog()

    /// A dictionary mapping each field's `key` to its `MobileDeviceField` instance
    /// for O(1) lookups when resolving selected field keys into full field definitions.
    static let keyLookup: [String: MobileDeviceField] = Dictionary(
        uniqueKeysWithValues: catalog.map { ($0.key, $0) }
    )

    /// Combines `curatedCatalog` and `generatedCatalog`, deduping by key and
    /// preferring curated metadata when both define the same field.
    private static func mergedCatalog() -> [MobileDeviceField] {
        var seenKeys: Set<String> = []
        var merged: [MobileDeviceField] = []

        for field in curatedCatalog {
            guard seenKeys.contains(field.key) == false else { continue }
            seenKeys.insert(field.key)
            merged.append(field)
        }

        for field in generatedCatalog {
            guard seenKeys.contains(field.key) == false else { continue }
            seenKeys.insert(field.key)
            merged.append(field)
        }

        return merged
    }
}

//endofline
