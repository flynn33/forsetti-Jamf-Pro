import Foundation

/// Represents the inventory sections available in the Jamf Pro Computer Inventory API.
///
/// Each case maps directly to a Jamf Pro API section identifier (e.g. `"GENERAL"`, `"HARDWARE"`).
/// These sections determine which data categories are requested when querying the inventory
/// endpoint, and are used to scope both the API request and the field catalog UI.
enum ComputerInventorySection: String, CaseIterable, Sendable {
    case general = "GENERAL"
    case diskEncryption = "DISK_ENCRYPTION"
    case purchasing = "PURCHASING"
    case userAndLocation = "USER_AND_LOCATION"
    case configurationProfiles = "CONFIGURATION_PROFILES"
    case printers = "PRINTERS"
    case services = "SERVICES"
    case hardware = "HARDWARE"
    case localUserAccounts = "LOCAL_USER_ACCOUNTS"
    case certificates = "CERTIFICATES"
    case attachments = "ATTACHMENTS"
    case plugins = "PLUGINS"
    case packageReceipts = "PACKAGE_RECEIPTS"
    case fonts = "FONTS"
    case security = "SECURITY"
    case operatingSystem = "OPERATING_SYSTEM"
    case licensedSoftware = "LICENSED_SOFTWARE"
    case ibeacons = "IBEACONS"
    case softwareUpdates = "SOFTWARE_UPDATES"
    case extensionAttributes = "EXTENSION_ATTRIBUTES"
    case contentCaching = "CONTENT_CACHING"
    case groupMemberships = "GROUP_MEMBERSHIPS"
}

/// Describes a single queryable field within the Jamf Pro computer inventory.
///
/// Each `ComputerField` maps a dot-notation API key (e.g. `"hardware.serialNumber"`) to
/// its human-readable display name, description, parent section, and whether it supports
/// RSQL-based server-side filtering. The static `catalog` array enumerates every known
/// field across all inventory sections.
struct ComputerField: Identifiable, Hashable, Sendable {
    /// The dot-notation API key path used in Jamf Pro API requests (e.g. `"hardware.serialNumber"`).
    let key: String

    /// The user-facing label shown in the field catalog and search results UI.
    let displayName: String

    /// A brief explanation of what this field represents.
    let description: String

    /// The inventory section this field belongs to, used for grouping and API section scoping.
    let section: ComputerInventorySection

    /// Whether this field can be used in RSQL filter expressions for server-side search.
    /// Fields inside array containers (e.g. `configurationProfiles[]`) typically do not support RSQL.
    let supportsRSQLSearch: Bool

    /// The unique identity of this field, derived from its API key.
    var id: String { key }
}

/// Static catalog and lookup helpers for the complete set of known computer inventory fields.
extension ComputerField {
    /// The master catalog of every known Jamf Pro computer inventory field.
    ///
    /// This array drives the field catalog UI, RSQL filter construction, and section resolution.
    /// Each entry defines the API key, display metadata, parent section, and RSQL support flag.
    static let catalog: [ComputerField] = [
        .init(key: "id", displayName: "Unique identifier for the computer", description: "Unique identifier for the computer", section: .general, supportsRSQLSearch: true),
        .init(key: "general.name", displayName: "Computer name", description: "Computer name", section: .general, supportsRSQLSearch: true),
        .init(key: "hardware.macAddress", displayName: "Primary MAC address", description: "Primary MAC address", section: .hardware, supportsRSQLSearch: true),
        .init(key: "hardware.altMacAddress", displayName: "Secondary MAC address", description: "Secondary MAC address", section: .hardware, supportsRSQLSearch: true),
        .init(key: "general.lastIpAddress", displayName: "Last reported IP address", description: "Last reported IP address", section: .general, supportsRSQLSearch: true),
        .init(key: "hardware.serialNumber", displayName: "Hardware serial number", description: "Hardware serial number", section: .hardware, supportsRSQLSearch: true),
        .init(key: "udid", displayName: "Unique device identifier", description: "Unique device identifier", section: .general, supportsRSQLSearch: true),
        .init(key: "general.jamfBinaryVersion", displayName: "Jamf binary version", description: "Jamf binary version", section: .general, supportsRSQLSearch: true),
        .init(key: "general.platform", displayName: "Device platform", description: "Device platform", section: .general, supportsRSQLSearch: true),
        .init(key: "general.barcode1", displayName: "Primary barcode", description: "Primary barcode", section: .general, supportsRSQLSearch: true),
        .init(key: "general.barcode2", displayName: "Secondary barcode", description: "Secondary barcode", section: .general, supportsRSQLSearch: true),
        .init(key: "general.assetTag", displayName: "Asset tag", description: "Asset tag", section: .general, supportsRSQLSearch: true),
        .init(key: "general.remoteManagement.managed", displayName: "Remote management status", description: "Remote management status", section: .general, supportsRSQLSearch: true),
        .init(key: "general.supervised", displayName: "Supervision status", description: "Supervision status", section: .general, supportsRSQLSearch: true),
        .init(key: "general.mdmCapable.capable", displayName: "MDM capability status", description: "MDM capability status", section: .general, supportsRSQLSearch: true),
        .init(key: "diskEncryption.fileVault2Enabled", displayName: "FileVault 2 status", description: "FileVault 2 status", section: .diskEncryption, supportsRSQLSearch: true),
        .init(key: "diskEncryption.individualRecoveryKeyValidityStatus", displayName: "Recovery key validity", description: "Recovery key validity", section: .diskEncryption, supportsRSQLSearch: true),
        .init(key: "diskEncryption.institutionalRecoveryKeyPresent", displayName: "Institutional recovery key presence", description: "Institutional recovery key presence", section: .diskEncryption, supportsRSQLSearch: true),
        .init(key: "diskEncryption.diskEncryptionConfigurationName", displayName: "Disk encryption configuration", description: "Disk encryption configuration", section: .diskEncryption, supportsRSQLSearch: true),
        .init(key: "diskEncryption.fileVault2EnabledUserNames", displayName: "FileVault 2 enabled users", description: "FileVault 2 enabled users", section: .diskEncryption, supportsRSQLSearch: true),
        .init(key: "purchasing.purchased", displayName: "Purchase status", description: "Purchase status", section: .purchasing, supportsRSQLSearch: true),
        .init(key: "purchasing.leased", displayName: "Lease status", description: "Lease status", section: .purchasing, supportsRSQLSearch: true),
        .init(key: "purchasing.poNumber", displayName: "Purchase order number", description: "Purchase order number", section: .purchasing, supportsRSQLSearch: true),
        .init(key: "purchasing.vendor", displayName: "Vendor name", description: "Vendor name", section: .purchasing, supportsRSQLSearch: true),
        .init(key: "purchasing.appleCareId", displayName: "AppleCare ID", description: "AppleCare ID", section: .purchasing, supportsRSQLSearch: true),
        .init(key: "purchasing.purchasePrice", displayName: "Purchase price", description: "Purchase price", section: .purchasing, supportsRSQLSearch: true),
        .init(key: "purchasing.lifeExpectancy", displayName: "Expected life in months", description: "Expected life in months", section: .purchasing, supportsRSQLSearch: true),
        .init(key: "purchasing.purchasingAccount", displayName: "Purchasing account", description: "Purchasing account", section: .purchasing, supportsRSQLSearch: true),
        .init(key: "purchasing.purchasingContact", displayName: "Purchasing contact", description: "Purchasing contact", section: .purchasing, supportsRSQLSearch: true),
        .init(key: "purchasing.poDate", displayName: "Purchase order date", description: "Purchase order date", section: .purchasing, supportsRSQLSearch: true),
        .init(key: "purchasing.warrantyDate", displayName: "Warranty expiration date", description: "Warranty expiration date", section: .purchasing, supportsRSQLSearch: true),
        .init(key: "purchasing.leaseDate", displayName: "Lease date", description: "Lease date", section: .purchasing, supportsRSQLSearch: true),
        .init(key: "hardware.make", displayName: "Device manufacturer", description: "Device manufacturer", section: .hardware, supportsRSQLSearch: true),
        .init(key: "hardware.model", displayName: "Device model", description: "Device model", section: .hardware, supportsRSQLSearch: true),
        .init(key: "hardware.modelIdentifier", displayName: "Model identifier", description: "Model identifier", section: .hardware, supportsRSQLSearch: true),
        .init(key: "operatingSystem.version", displayName: "OS version", description: "OS version", section: .operatingSystem, supportsRSQLSearch: true),
        .init(key: "operatingSystem.build", displayName: "OS build number", description: "OS build number", section: .operatingSystem, supportsRSQLSearch: true),
        .init(key: "hardware.processorType", displayName: "Processor type", description: "Processor type", section: .hardware, supportsRSQLSearch: true),
        .init(key: "hardware.processorSpeedMhz", displayName: "Processor speed", description: "Processor speed", section: .hardware, supportsRSQLSearch: true),
        .init(key: "hardware.processorCount", displayName: "Number of processors", description: "Number of processors", section: .hardware, supportsRSQLSearch: true),
        .init(key: "hardware.coreCount", displayName: "Number of cores", description: "Number of cores", section: .hardware, supportsRSQLSearch: true),
        .init(key: "hardware.totalRamMegabytes", displayName: "Total RAM in MB", description: "Total RAM in MB", section: .hardware, supportsRSQLSearch: true),
        .init(key: "hardware.bootRom", displayName: "Boot ROM version", description: "Boot ROM version", section: .hardware, supportsRSQLSearch: true),
        .init(key: "hardware.busSpeedMhz", displayName: "Bus speed in MHz", description: "Bus speed in MHz", section: .hardware, supportsRSQLSearch: true),
        .init(key: "hardware.cacheSizeKilobytes", displayName: "Cache size in KB", description: "Cache size in KB", section: .hardware, supportsRSQLSearch: true),
        .init(key: "hardware.nicSpeed", displayName: "Network interface speed", description: "Network interface speed", section: .hardware, supportsRSQLSearch: true),
        .init(key: "hardware.opticalDrive", displayName: "Optical drive type", description: "Optical drive type", section: .hardware, supportsRSQLSearch: true),
        .init(key: "hardware.smcVersion", displayName: "SMC version", description: "SMC version", section: .hardware, supportsRSQLSearch: true),
        .init(key: "hardware.batteryCapacityPercent", displayName: "Battery capacity percentage", description: "Battery capacity percentage", section: .hardware, supportsRSQLSearch: true),
        .init(key: "hardware.supportsIosAppInstalls", displayName: "iOS app installation support", description: "iOS app installation support", section: .hardware, supportsRSQLSearch: true),
        .init(key: "hardware.appleSilicon", displayName: "Apple Silicon status", description: "Apple Silicon status", section: .hardware, supportsRSQLSearch: true),
        .init(key: "operatingSystem.name", displayName: "OS name", description: "OS name", section: .operatingSystem, supportsRSQLSearch: true),
        .init(key: "operatingSystem.activeDirectoryStatus", displayName: "Active Directory status", description: "Active Directory status", section: .operatingSystem, supportsRSQLSearch: true),
        .init(key: "operatingSystem.fileVault2Status", displayName: "FileVault 2 status", description: "FileVault 2 status", section: .operatingSystem, supportsRSQLSearch: true),
        .init(key: "operatingSystem.supplementalBuildVersion", displayName: "Supplemental build version", description: "Supplemental build version", section: .operatingSystem, supportsRSQLSearch: true),
        .init(key: "operatingSystem.rapidSecurityResponse", displayName: "Rapid Security Response version", description: "Rapid Security Response version", section: .operatingSystem, supportsRSQLSearch: true),
        .init(key: "security.activationLockEnabled", displayName: "Activation Lock status", description: "Activation Lock status", section: .security, supportsRSQLSearch: true),
        .init(key: "security.secureBootLevel", displayName: "Secure Boot level", description: "Secure Boot level", section: .security, supportsRSQLSearch: true),
        .init(key: "security.externalBootLevel", displayName: "External boot level", description: "External boot level", section: .security, supportsRSQLSearch: true),
        .init(key: "security.firewallEnabled", displayName: "Firewall status", description: "Firewall status", section: .security, supportsRSQLSearch: true),
        .init(key: "security.sipStatus", displayName: "System Integrity Protection status", description: "System Integrity Protection status", section: .security, supportsRSQLSearch: true),
        .init(key: "security.gatekeeperStatus", displayName: "Gatekeeper status", description: "Gatekeeper status", section: .security, supportsRSQLSearch: true),
        .init(key: "security.xprotectVersion", displayName: "XProtect version", description: "XProtect version", section: .security, supportsRSQLSearch: true),
        .init(key: "security.autoLoginDisabled", displayName: "Auto-login disabled status", description: "Auto-login disabled status", section: .security, supportsRSQLSearch: true),
        .init(key: "security.remoteDesktopEnabled", displayName: "Remote Desktop status", description: "Remote Desktop status", section: .security, supportsRSQLSearch: true),
        .init(key: "security.bootstrapTokenAllowed", displayName: "Bootstrap token status", description: "Bootstrap token status", section: .security, supportsRSQLSearch: true),
        .init(key: "userAndLocation.username", displayName: "Username", description: "Username", section: .userAndLocation, supportsRSQLSearch: true),
        .init(key: "userAndLocation.realname", displayName: "User's real name", description: "User's real name", section: .userAndLocation, supportsRSQLSearch: true),
        .init(key: "userAndLocation.email", displayName: "Email address", description: "Email address", section: .userAndLocation, supportsRSQLSearch: true),
        .init(key: "userAndLocation.position", displayName: "Position/title", description: "Position/title", section: .userAndLocation, supportsRSQLSearch: true),
        .init(key: "userAndLocation.phone", displayName: "Phone number", description: "Phone number", section: .userAndLocation, supportsRSQLSearch: true),
        .init(key: "userAndLocation.departmentId", displayName: "Department identifier", description: "Department identifier", section: .userAndLocation, supportsRSQLSearch: true),
        .init(key: "userAndLocation.buildingId", displayName: "Building identifier", description: "Building identifier", section: .userAndLocation, supportsRSQLSearch: true),
        .init(key: "userAndLocation.room", displayName: "Room identifier/name", description: "Room identifier/name", section: .userAndLocation, supportsRSQLSearch: true),
        .init(key: "configurationProfiles[].id", displayName: "Profile identifier", description: "Profile identifier", section: .configurationProfiles, supportsRSQLSearch: false),
        .init(key: "configurationProfiles[].displayName", displayName: "Profile name", description: "Profile name", section: .configurationProfiles, supportsRSQLSearch: false),
        .init(key: "configurationProfiles[].profileIdentifier", displayName: "Profile UUID", description: "Profile UUID", section: .configurationProfiles, supportsRSQLSearch: false),
        .init(key: "configurationProfiles[].username", displayName: "Associated username", description: "Associated username", section: .configurationProfiles, supportsRSQLSearch: false),
        .init(key: "configurationProfiles[].removable", displayName: "Profile removable status", description: "Profile removable status", section: .configurationProfiles, supportsRSQLSearch: false),
        .init(key: "printers[].name", displayName: "Printer name", description: "Printer name", section: .printers, supportsRSQLSearch: false),
        .init(key: "printers[].uri", displayName: "Printer URI", description: "Printer URI", section: .printers, supportsRSQLSearch: false),
        .init(key: "printers[].type", displayName: "Printer type", description: "Printer type", section: .printers, supportsRSQLSearch: false),
        .init(key: "printers[].location", displayName: "Printer location", description: "Printer location", section: .printers, supportsRSQLSearch: false),
        .init(key: "services[].name", displayName: "Service name", description: "Service name", section: .services, supportsRSQLSearch: false),
        .init(key: "localUserAccounts[].username", displayName: "Account username", description: "Account username", section: .localUserAccounts, supportsRSQLSearch: false),
        .init(key: "localUserAccounts[].fullName", displayName: "User's full name", description: "User's full name", section: .localUserAccounts, supportsRSQLSearch: false),
        .init(key: "localUserAccounts[].uid", displayName: "User ID", description: "User ID", section: .localUserAccounts, supportsRSQLSearch: false),
        .init(key: "localUserAccounts[].homeDirectory", displayName: "Home directory path", description: "Home directory path", section: .localUserAccounts, supportsRSQLSearch: false),
        .init(key: "localUserAccounts[].admin", displayName: "Administrator status", description: "Administrator status", section: .localUserAccounts, supportsRSQLSearch: false),
        .init(key: "localUserAccounts[].fileVault2Enabled", displayName: "FileVault 2 status", description: "FileVault 2 status", section: .localUserAccounts, supportsRSQLSearch: false),
        .init(key: "localUserAccounts[].passwordMinLength", displayName: "Minimum password length", description: "Minimum password length", section: .localUserAccounts, supportsRSQLSearch: false),
        .init(key: "localUserAccounts[].passwordMaxAge", displayName: "Maximum password age", description: "Maximum password age", section: .localUserAccounts, supportsRSQLSearch: false),
        .init(key: "localUserAccounts[].passwordMinComplexCharacters", displayName: "Minimum complex characters", description: "Minimum complex characters", section: .localUserAccounts, supportsRSQLSearch: false),
        .init(key: "localUserAccounts[].passwordHistoryDepth", displayName: "Password history depth", description: "Password history depth", section: .localUserAccounts, supportsRSQLSearch: false),
        .init(key: "localUserAccounts[].passwordRequireAlphanumeric", displayName: "Alphanumeric requirement", description: "Alphanumeric requirement", section: .localUserAccounts, supportsRSQLSearch: false),
        .init(key: "localUserAccounts[].computerAzureActiveDirectoryId", displayName: "Azure AD computer ID", description: "Azure AD computer ID", section: .localUserAccounts, supportsRSQLSearch: false),
        .init(key: "localUserAccounts[].userAzureActiveDirectoryId", displayName: "Azure AD user ID", description: "Azure AD user ID", section: .localUserAccounts, supportsRSQLSearch: false),
        .init(key: "localUserAccounts[].azureActiveDirectoryId", displayName: "Azure AD status", description: "Azure AD status", section: .localUserAccounts, supportsRSQLSearch: false),
        .init(key: "certificates[].commonName", displayName: "Certificate common name", description: "Certificate common name", section: .certificates, supportsRSQLSearch: false),
        .init(key: "certificates[].identity", displayName: "Identity certificate status", description: "Identity certificate status", section: .certificates, supportsRSQLSearch: false),
        .init(key: "certificates[].expirationDate", displayName: "Expiration date", description: "Expiration date", section: .certificates, supportsRSQLSearch: false),
        .init(key: "certificates[].username", displayName: "Associated username", description: "Associated username", section: .certificates, supportsRSQLSearch: false),
        .init(key: "certificates[].serialNumber", displayName: "Certificate serial number", description: "Certificate serial number", section: .certificates, supportsRSQLSearch: false),
        .init(key: "certificates[].sha1Fingerprint", displayName: "SHA1 fingerprint", description: "SHA1 fingerprint", section: .certificates, supportsRSQLSearch: false),
        .init(key: "certificates[].issuedDate", displayName: "Issue date", description: "Issue date", section: .certificates, supportsRSQLSearch: false),
        .init(key: "certificates[].certificateStatus", displayName: "Certificate status", description: "Certificate status", section: .certificates, supportsRSQLSearch: false),
        .init(key: "certificates[].lifecycleStatus", displayName: "Lifecycle status", description: "Lifecycle status", section: .certificates, supportsRSQLSearch: false),
        .init(key: "attachments[].id", displayName: "Attachment ID", description: "Attachment ID", section: .attachments, supportsRSQLSearch: false),
        .init(key: "attachments[].name", displayName: "Attachment name", description: "Attachment name", section: .attachments, supportsRSQLSearch: false),
        .init(key: "attachments[].fileType", displayName: "File type", description: "File type", section: .attachments, supportsRSQLSearch: false),
        .init(key: "attachments[].sizeBytes", displayName: "Size in bytes", description: "Size in bytes", section: .attachments, supportsRSQLSearch: false),
        .init(key: "plugins[].name", displayName: "Plugin name", description: "Plugin name", section: .plugins, supportsRSQLSearch: false),
        .init(key: "plugins[].version", displayName: "Plugin version", description: "Plugin version", section: .plugins, supportsRSQLSearch: false),
        .init(key: "plugins[].path", displayName: "Plugin path", description: "Plugin path", section: .plugins, supportsRSQLSearch: false),
        .init(key: "packageReceipts.installedByInstallerSwu", displayName: "Software Update installed packages", description: "Software Update installed packages", section: .packageReceipts, supportsRSQLSearch: true),
        .init(key: "packageReceipts.cached", displayName: "Cached packages", description: "Cached packages", section: .packageReceipts, supportsRSQLSearch: true),
        .init(key: "packageReceipts.installedByJamfPro", displayName: "Jamf Pro installed packages", description: "Jamf Pro installed packages", section: .packageReceipts, supportsRSQLSearch: true),
        .init(key: "fonts[].name", displayName: "Font name", description: "Font name", section: .fonts, supportsRSQLSearch: false),
        .init(key: "fonts[].version", displayName: "Font version", description: "Font version", section: .fonts, supportsRSQLSearch: false),
        .init(key: "fonts[].path", displayName: "Font path", description: "Font path", section: .fonts, supportsRSQLSearch: false),
        .init(key: "licensedSoftware[].id", displayName: "Software ID", description: "Software ID", section: .licensedSoftware, supportsRSQLSearch: false),
        .init(key: "licensedSoftware[].name", displayName: "Software name", description: "Software name", section: .licensedSoftware, supportsRSQLSearch: false),
        .init(key: "ibeacons[].name", displayName: "iBeacon name", description: "iBeacon name", section: .ibeacons, supportsRSQLSearch: false),
        .init(key: "softwareUpdates[].name", displayName: "Update name", description: "Update name", section: .softwareUpdates, supportsRSQLSearch: false),
        .init(key: "softwareUpdates[].version", displayName: "Update version", description: "Update version", section: .softwareUpdates, supportsRSQLSearch: false),
        .init(key: "softwareUpdates[].packageName", displayName: "Package name", description: "Package name", section: .softwareUpdates, supportsRSQLSearch: false),
        .init(key: "extensionAttributes[].definitionId", displayName: "Attribute ID", description: "Attribute ID", section: .extensionAttributes, supportsRSQLSearch: false),
        .init(key: "extensionAttributes[].name", displayName: "Attribute name", description: "Attribute name", section: .extensionAttributes, supportsRSQLSearch: false),
        .init(key: "extensionAttributes[].dataType", displayName: "Data type", description: "Data type", section: .extensionAttributes, supportsRSQLSearch: false),
        .init(key: "extensionAttributes[].values[]", displayName: "Attribute values", description: "Attribute values", section: .extensionAttributes, supportsRSQLSearch: false),
        .init(key: "extensionAttributes[].multiValue", displayName: "Multi-value status", description: "Multi-value status", section: .extensionAttributes, supportsRSQLSearch: false),
        .init(key: "extensionAttributes[].enabled", displayName: "Enabled status", description: "Enabled status", section: .extensionAttributes, supportsRSQLSearch: false),
        .init(key: "extensionAttributes[].description", displayName: "Description", description: "Description", section: .extensionAttributes, supportsRSQLSearch: false),
        .init(key: "extensionAttributes[].inputType", displayName: "Input type", description: "Input type", section: .extensionAttributes, supportsRSQLSearch: false),
        .init(key: "contentCaching.active", displayName: "Service active status", description: "Service active status", section: .contentCaching, supportsRSQLSearch: true),
        .init(key: "contentCaching.activated", displayName: "Service activated status", description: "Service activated status", section: .contentCaching, supportsRSQLSearch: true),
        .init(key: "contentCaching.cacheStatus", displayName: "Cache status", description: "Cache status", section: .contentCaching, supportsRSQLSearch: true),
        .init(key: "contentCaching.cacheBytesFree", displayName: "Available cache space", description: "Available cache space", section: .contentCaching, supportsRSQLSearch: true),
        .init(key: "contentCaching.cacheBytesUsed", displayName: "Used cache space", description: "Used cache space", section: .contentCaching, supportsRSQLSearch: true),
        .init(key: "contentCaching.cacheBytesLimit", displayName: "Cache size limit", description: "Cache size limit", section: .contentCaching, supportsRSQLSearch: true),
        .init(key: "contentCaching.port", displayName: "Service port", description: "Service port", section: .contentCaching, supportsRSQLSearch: true),
        .init(key: "contentCaching.publicAddress", displayName: "Public address", description: "Public address", section: .contentCaching, supportsRSQLSearch: true),
        .init(key: "contentCaching.serverGuid", displayName: "Server GUID", description: "Server GUID", section: .contentCaching, supportsRSQLSearch: true),
        .init(key: "contentCaching.startupStatus", displayName: "Startup status", description: "Startup status", section: .contentCaching, supportsRSQLSearch: true),
        .init(key: "contentCaching.registrationStatus", displayName: "Registration status", description: "Registration status", section: .contentCaching, supportsRSQLSearch: true),
        .init(key: "contentCaching.registrationError", displayName: "Registration error", description: "Registration error", section: .contentCaching, supportsRSQLSearch: true),
        .init(key: "contentCaching.registrationResponseCode", displayName: "Registration response code", description: "Registration response code", section: .contentCaching, supportsRSQLSearch: true),
        .init(key: "contentCaching.restrictedMedia", displayName: "Restricted media status", description: "Restricted media status", section: .contentCaching, supportsRSQLSearch: true),
        .init(key: "groupMemberships[].groupName", displayName: "Group name", description: "Group name", section: .groupMemberships, supportsRSQLSearch: false),
        .init(key: "groupMemberships[].groupId", displayName: "Group ID", description: "Group ID", section: .groupMemberships, supportsRSQLSearch: false),
        .init(key: "groupMemberships[].smartGroup", displayName: "Smart group status", description: "Smart group status", section: .groupMemberships, supportsRSQLSearch: false),
    ]

    /// The default set of field keys used for RSQL queries when no profile is selected.
    ///
    /// These represent the most commonly searched identifiers: name, serial, MAC, asset tag,
    /// barcodes, IP address, and UDID.
    static let defaultRSQLQueryFieldKeys: [String] = [
        "general.name",
        "hardware.serialNumber",
        "hardware.macAddress",
        "general.assetTag",
        "general.barcode1",
        "general.barcode2",
        "general.lastIpAddress",
        "udid",
        "userAndLocation.username",
        "userAndLocation.email",
        "userAndLocation.realname"
    ]

    /// A dictionary that maps each field's API key to its `ComputerField` instance for O(1) lookups.
    ///
    /// Built once from the catalog and used throughout the search pipeline to quickly resolve
    /// field metadata from raw key strings.
    static let keyLookup: [String: ComputerField] = Dictionary(
        uniqueKeysWithValues: catalog.map { ($0.key, $0) }
    )
}

//endofline
