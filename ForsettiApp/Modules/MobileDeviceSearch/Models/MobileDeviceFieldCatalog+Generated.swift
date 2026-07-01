import Foundation

// "Klatu-barada-Nikto"

/// Generated mobile device field catalog seeded from the Jamf Pro v2
/// `/api/v2/mobile-devices/detail` documented schema.
///
/// Two pools are concatenated into `generatedCatalog`:
///
/// 1. **Filterable fields** — all fields documented as accepting an RSQL filter
///    against the inventory detail endpoint. These power Advanced Search.
/// 2. **Sortable-only fields** — fields documented as sortable but not
///    filterable. They are included so result rows and the detail view can
///    display them, but the Advanced Search picker hides them via the
///    `isFilterable: false` flag.
///
/// The merge in `MobileDeviceField.mergedCatalog` lets curated entries
/// (in `MobileDeviceField.curatedCatalog`) override any generated entry with
/// the same `key`, so curated rows like `prestageEnrollmentProfile` keep their
/// hand-tuned response paths and filterability flags.
extension MobileDeviceField {

    /// All Jamf-documented fields not already covered by the curated catalog.
    /// See class-level doc for the split between filterable and display-only.
    static let generatedCatalog: [MobileDeviceField] = filterableGenerated + sortableOnlyGenerated

    // MARK: - Filterable

    /// Fields the v2 detail endpoint accepts as RSQL filter operands.
    /// Each entry's `responsePaths` covers both the modern dotted-section path
    /// (e.g. `hardware.capacityMb`) and a flat fallback the older list shape uses.
    private static let filterableGenerated: [MobileDeviceField] = [

        // MARK: General
        .init(
            key: "deviceId",
            displayName: "Device ID",
            description: "Numeric device identifier from Jamf Pro.",
            section: .general,
            responsePaths: ["general.deviceId", "deviceId"],
            dataType: .integer
        ),
        .init(
            key: "displayName",
            displayName: "Display Name",
            description: "Display name as reported by the device.",
            section: .general,
            responsePaths: ["general.displayName", "displayName"]
        ),
        .init(
            key: "languages",
            displayName: "Languages",
            description: "Languages configured on the device.",
            section: .general,
            responsePaths: ["general.languages", "languages"]
        ),
        .init(
            key: "locales",
            displayName: "Locales",
            description: "Locales configured on the device.",
            section: .general,
            responsePaths: ["general.locales", "locales"]
        ),
        .init(
            key: "timeZone",
            displayName: "Time Zone",
            description: "IANA time zone identifier.",
            section: .general,
            responsePaths: ["general.timeZone", "timeZone"]
        ),
        .init(
            key: "managed",
            displayName: "Managed",
            description: "Whether Jamf considers the device managed.",
            section: .general,
            responsePaths: ["general.managed", "managed"],
            dataType: .bool
        ),
        .init(
            key: "ipAddress",
            displayName: "IP Address",
            description: "Most recently reported IP address.",
            section: .general,
            responsePaths: ["general.ipAddress", "ipAddress"]
        ),
        .init(
            key: "exchangeDeviceId",
            displayName: "Exchange Device ID",
            description: "Exchange ActiveSync device identifier.",
            section: .general,
            responsePaths: ["general.exchangeDeviceId", "exchangeDeviceId"]
        ),
        .init(
            key: "declarativeDeviceManagementEnabled",
            displayName: "DDM Enabled",
            description: "Whether Declarative Device Management is enabled.",
            section: .general,
            responsePaths: [
                "general.declarativeDeviceManagementEnabled",
                "declarativeDeviceManagementEnabled"
            ],
            dataType: .bool
        ),
        .init(
            key: "sharedIpad",
            displayName: "Shared iPad",
            description: "Whether the device is configured as a Shared iPad.",
            section: .general,
            responsePaths: ["general.sharedIpad", "sharedIpad"],
            dataType: .bool
        ),
        .init(
            key: "tethered",
            displayName: "Tethered",
            description: "Whether the device is tethered to another device.",
            section: .general,
            responsePaths: ["general.tethered", "tethered"],
            dataType: .bool
        ),
        .init(
            key: "lastLoggedInUsernameSelfService",
            displayName: "Self Service Last User",
            description: "Last user that signed into Self Service Mobile.",
            section: .general,
            responsePaths: [
                "general.lastLoggedInUsernameSelfService",
                "lastLoggedInUsernameSelfService"
            ]
        ),
        .init(
            key: "lastLoggedInUsernameSelfServiceTimestamp",
            displayName: "Self Service Last Login",
            description: "Timestamp of the last Self Service Mobile login.",
            section: .general,
            responsePaths: [
                "general.lastLoggedInUsernameSelfServiceTimestamp",
                "lastLoggedInUsernameSelfServiceTimestamp"
            ],
            dataType: .date
        ),
        .init(
            key: "deviceLocatorServiceEnabled",
            displayName: "Find My Enabled",
            description: "Whether the Find My / Device Locator service is enabled.",
            section: .general,
            responsePaths: [
                "general.deviceLocatorServiceEnabled",
                "deviceLocatorServiceEnabled"
            ],
            dataType: .bool
        ),
        .init(
            key: "lifeExpectancyYears",
            displayName: "Life Expectancy (years)",
            description: "Configured life-expectancy value in whole years.",
            section: .general,
            responsePaths: ["general.lifeExpectancyYears", "lifeExpectancyYears"],
            dataType: .integer
        ),
        .init(
            key: "doNotDisturbEnabled",
            displayName: "Do Not Disturb",
            description: "Whether Do Not Disturb is currently enabled.",
            section: .general,
            responsePaths: ["general.doNotDisturbEnabled", "doNotDisturbEnabled"],
            dataType: .bool
        ),
        .init(
            key: "locationServicesForSelfServiceMobileEnabled",
            displayName: "Self Service Location Services",
            description: "Whether Location Services for Self Service Mobile is enabled.",
            section: .general,
            responsePaths: [
                "general.locationServicesForSelfServiceMobileEnabled",
                "locationServicesForSelfServiceMobileEnabled"
            ],
            dataType: .bool
        ),
        .init(
            key: "osRapidSecurityResponse",
            displayName: "Rapid Security Response",
            description: "Installed Rapid Security Response build identifier.",
            section: .general,
            responsePaths: ["general.osRapidSecurityResponse", "osRapidSecurityResponse"]
        ),
        .init(
            key: "osSupplementalBuildVersion",
            displayName: "Supplemental Build",
            description: "Supplemental OS build identifier when present.",
            section: .general,
            responsePaths: [
                "general.osSupplementalBuildVersion",
                "osSupplementalBuildVersion"
            ]
        ),
        .init(
            key: "position",
            displayName: "Position",
            description: "Reported position string (where supported).",
            section: .general,
            responsePaths: ["general.position", "position"]
        ),

        // MARK: Hardware
        .init(
            key: "capacityMb",
            displayName: "Storage Capacity (MB)",
            description: "Total device storage capacity in megabytes.",
            section: .hardware,
            responsePaths: ["hardware.capacityMb", "capacityMb"],
            dataType: .integer
        ),
        .init(
            key: "availableSpaceMb",
            displayName: "Available Space (MB)",
            description: "Free device storage in megabytes.",
            section: .hardware,
            responsePaths: ["hardware.availableSpaceMb", "availableSpaceMb"],
            dataType: .integer
        ),
        .init(
            key: "usedSpacePercentage",
            displayName: "Used Space (%)",
            description: "Percentage of device storage in use.",
            section: .hardware,
            responsePaths: ["hardware.usedSpacePercentage", "usedSpacePercentage"],
            dataType: .integer
        ),
        .init(
            key: "batteryLevel",
            displayName: "Battery Level (%)",
            description: "Reported battery level as a percentage 0-100.",
            section: .hardware,
            responsePaths: ["hardware.batteryLevel", "batteryLevel"],
            dataType: .integer
        ),
        .init(
            key: "modelNumber",
            displayName: "Model Number",
            description: "Apple model number (e.g. A2757).",
            section: .hardware,
            responsePaths: ["hardware.modelNumber", "general.modelNumber", "modelNumber"]
        ),
        .init(
            key: "bluetoothMacAddress",
            displayName: "Bluetooth MAC",
            description: "Bluetooth MAC address.",
            section: .hardware,
            responsePaths: ["hardware.bluetoothMacAddress", "bluetoothMacAddress"]
        ),
        .init(
            key: "wifiMacAddress",
            displayName: "Wi-Fi MAC",
            description: "Wi-Fi MAC address.",
            section: .hardware,
            responsePaths: ["hardware.wifiMacAddress", "wifiMacAddress"]
        ),
        .init(
            key: "modemFirmwareVersion",
            displayName: "Modem Firmware",
            description: "Cellular modem firmware version string.",
            section: .hardware,
            responsePaths: ["hardware.modemFirmwareVersion", "modemFirmwareVersion"]
        ),
        .init(
            key: "dataProtection",
            displayName: "Data Protection",
            description: "Reported data-protection capability.",
            section: .hardware,
            responsePaths: ["hardware.dataProtection", "dataProtection"]
        ),
        .init(
            key: "blockEncryptionCapable",
            displayName: "Block Encryption Capable",
            description: "Whether the device supports block encryption.",
            section: .hardware,
            responsePaths: ["hardware.blockEncryptionCapable", "blockEncryptionCapable"],
            dataType: .bool
        ),
        .init(
            key: "fileEncryptionCapable",
            displayName: "File Encryption Capable",
            description: "Whether the device supports file-level encryption.",
            section: .hardware,
            responsePaths: ["hardware.fileEncryptionCapable", "fileEncryptionCapable"],
            dataType: .bool
        ),
        .init(
            key: "bluetoothLowEnergyCapable",
            displayName: "BLE Capable",
            description: "Whether the device supports Bluetooth Low Energy.",
            section: .hardware,
            responsePaths: [
                "hardware.bluetoothLowEnergyCapable",
                "bluetoothLowEnergyCapable"
            ],
            dataType: .bool
        ),
        .init(
            key: "eid",
            displayName: "EID",
            description: "Embedded SIM eUICC identifier.",
            section: .hardware,
            responsePaths: ["hardware.eid", "eid"]
        ),
        .init(
            key: "imei",
            displayName: "IMEI",
            description: "Primary cellular IMEI.",
            section: .hardware,
            responsePaths: ["hardware.imei", "imei"]
        ),
        .init(
            key: "imei2",
            displayName: "IMEI (2)",
            description: "Secondary cellular IMEI for dual-SIM devices.",
            section: .hardware,
            responsePaths: ["hardware.imei2", "imei2"]
        ),
        .init(
            key: "meid",
            displayName: "MEID",
            description: "Mobile Equipment Identifier (CDMA).",
            section: .hardware,
            responsePaths: ["hardware.meid", "meid"]
        ),
        .init(
            key: "iccid",
            displayName: "ICCID",
            description: "Integrated Circuit Card Identifier.",
            section: .hardware,
            responsePaths: ["hardware.iccid", "iccid"]
        ),
        .init(
            key: "currentCarrierNetwork",
            displayName: "Current Carrier",
            description: "Current cellular carrier name.",
            section: .hardware,
            responsePaths: ["hardware.currentCarrierNetwork", "currentCarrierNetwork"]
        ),
        .init(
            key: "currentMobileCountryCode",
            displayName: "Current MCC",
            description: "Current Mobile Country Code.",
            section: .hardware,
            responsePaths: [
                "hardware.currentMobileCountryCode",
                "currentMobileCountryCode"
            ]
        ),
        .init(
            key: "currentMobileNetworkCode",
            displayName: "Current MNC",
            description: "Current Mobile Network Code.",
            section: .hardware,
            responsePaths: [
                "hardware.currentMobileNetworkCode",
                "currentMobileNetworkCode"
            ]
        ),
        .init(
            key: "homeMobileCountryCode",
            displayName: "Home MCC",
            description: "Home Mobile Country Code.",
            section: .hardware,
            responsePaths: ["hardware.homeMobileCountryCode", "homeMobileCountryCode"]
        ),
        .init(
            key: "homeMobileNetworkCode",
            displayName: "Home MNC",
            description: "Home Mobile Network Code.",
            section: .hardware,
            responsePaths: ["hardware.homeMobileNetworkCode", "homeMobileNetworkCode"]
        ),
        .init(
            key: "carrierSettingsVersion",
            displayName: "Carrier Settings",
            description: "Installed carrier settings version.",
            section: .hardware,
            responsePaths: ["hardware.carrierSettingsVersion", "carrierSettingsVersion"]
        ),
        .init(
            key: "devicePhoneNumber",
            displayName: "Device Phone",
            description: "Cellular phone number assigned to the device.",
            section: .hardware,
            responsePaths: ["hardware.devicePhoneNumber", "devicePhoneNumber"]
        ),
        .init(
            key: "preferredVoiceNumber",
            displayName: "Preferred Voice Number",
            description: "Preferred voice number for dual-SIM devices.",
            section: .hardware,
            responsePaths: ["hardware.preferredVoiceNumber", "preferredVoiceNumber"]
        ),
        .init(
            key: "network",
            displayName: "Network",
            description: "Currently connected network identifier.",
            section: .hardware,
            responsePaths: ["hardware.network", "network"]
        ),
        .init(
            key: "dataRoamingEnabled",
            displayName: "Data Roaming",
            description: "Whether cellular data roaming is enabled.",
            section: .hardware,
            responsePaths: ["hardware.dataRoamingEnabled", "dataRoamingEnabled"],
            dataType: .bool
        ),
        .init(
            key: "voiceRoamingEnabled",
            displayName: "Voice Roaming",
            description: "Whether cellular voice roaming is enabled.",
            section: .hardware,
            responsePaths: ["hardware.voiceRoamingEnabled", "voiceRoamingEnabled"],
            dataType: .bool
        ),
        .init(
            key: "roaming",
            displayName: "Roaming",
            description: "Whether the device is currently roaming.",
            section: .hardware,
            responsePaths: ["hardware.roaming", "roaming"],
            dataType: .bool
        ),
        .init(
            key: "personalHotspotEnabled",
            displayName: "Personal Hotspot",
            description: "Whether Personal Hotspot is enabled.",
            section: .hardware,
            responsePaths: ["hardware.personalHotspotEnabled", "personalHotspotEnabled"],
            dataType: .bool
        ),

        // MARK: User and Location
        .init(
            key: "fullName",
            displayName: "Full Name",
            description: "Assigned user's full name.",
            section: .location,
            responsePaths: [
                "userAndLocation.fullName",
                "location.realName",
                "location.fullName",
                "fullName"
            ]
        ),
        .init(
            key: "userPhoneNumber",
            displayName: "User Phone",
            description: "User's phone number from inventory.",
            section: .location,
            responsePaths: [
                "userAndLocation.phoneNumber",
                "location.phone",
                "location.phoneNumber",
                "userPhoneNumber"
            ]
        ),
        .init(
            key: "room",
            displayName: "Room",
            description: "Room assignment.",
            section: .location,
            responsePaths: ["userAndLocation.room", "location.room", "room"]
        ),

        // MARK: Purchasing
        .init(
            key: "appleCareId",
            displayName: "AppleCare ID",
            description: "AppleCare reference identifier.",
            section: .purchasing,
            responsePaths: ["purchasing.appleCareId", "appleCareId"]
        ),
        .init(
            key: "poNumber",
            displayName: "PO Number",
            description: "Purchase order number.",
            section: .purchasing,
            responsePaths: ["purchasing.poNumber", "poNumber"]
        ),
        .init(
            key: "purchasePrice",
            displayName: "Purchase Price",
            description: "Recorded purchase price.",
            section: .purchasing,
            responsePaths: ["purchasing.purchasePrice", "purchasePrice"]
        ),
        .init(
            key: "purchasingAccount",
            displayName: "Purchasing Account",
            description: "Account that owns the purchase record.",
            section: .purchasing,
            responsePaths: ["purchasing.purchasingAccount", "purchasingAccount"]
        ),
        .init(
            key: "purchasingContact",
            displayName: "Purchasing Contact",
            description: "Purchasing contact for the device.",
            section: .purchasing,
            responsePaths: ["purchasing.purchasingContact", "purchasingContact"]
        ),
        .init(
            key: "purchasedOrLeased",
            displayName: "Purchased or Leased",
            description: "Whether the device is purchased or leased.",
            section: .purchasing,
            responsePaths: ["purchasing.purchasedOrLeased", "purchasedOrLeased"]
        ),
        .init(
            key: "vendor",
            displayName: "Vendor",
            description: "Vendor that supplied the device.",
            section: .purchasing,
            responsePaths: ["purchasing.vendor", "vendor"]
        ),

        // MARK: Security
        .init(
            key: "activationLockEnabled",
            displayName: "Activation Lock",
            description: "Whether Activation Lock is enabled.",
            section: .security,
            responsePaths: ["security.activationLockEnabled", "activationLockEnabled"],
            dataType: .bool
        ),
        .init(
            key: "lostModeEnabled",
            displayName: "Lost Mode",
            description: "Whether Lost Mode is currently enabled.",
            section: .security,
            responsePaths: ["security.lostModeEnabled", "lostModeEnabled"],
            dataType: .bool
        ),
        .init(
            key: "passcodePresent",
            displayName: "Passcode Present",
            description: "Whether a passcode is set on the device.",
            section: .security,
            responsePaths: ["security.passcodePresent", "passcodePresent"],
            dataType: .bool
        ),
        .init(
            key: "passcodeCompliant",
            displayName: "Passcode Compliant",
            description: "Whether the passcode meets policy.",
            section: .security,
            responsePaths: ["security.passcodeCompliant", "passcodeCompliant"],
            dataType: .bool
        ),
        .init(
            key: "passcodeCompliantWithProfile",
            displayName: "Passcode Compliant w/ Profile",
            description: "Whether the passcode meets the assigned profile.",
            section: .security,
            responsePaths: [
                "security.passcodeCompliantWithProfile",
                "passcodeCompliantWithProfile"
            ],
            dataType: .bool
        ),
        .init(
            key: "passcodeLockGracePeriodEnforcedSeconds",
            displayName: "Passcode Grace Period (s)",
            description: "Enforced passcode lock grace period in seconds.",
            section: .security,
            responsePaths: [
                "security.passcodeLockGracePeriodEnforcedSeconds",
                "passcodeLockGracePeriodEnforcedSeconds"
            ],
            dataType: .integer
        ),
        .init(
            key: "cloudBackupEnabled",
            displayName: "iCloud Backup",
            description: "Whether iCloud Backup is enabled.",
            section: .security,
            responsePaths: ["security.cloudBackupEnabled", "cloudBackupEnabled"],
            dataType: .bool
        ),
        .init(
            key: "itunesStoreAccountActive",
            displayName: "iTunes Store Account Active",
            description: "Whether an iTunes Store account is signed in.",
            section: .security,
            responsePaths: [
                "security.itunesStoreAccountActive",
                "itunesStoreAccountActive"
            ],
            dataType: .bool
        ),
        .init(
            key: "appAnalyticsEnabled",
            displayName: "App Analytics",
            description: "Whether app analytics sharing is enabled.",
            section: .security,
            responsePaths: ["security.appAnalyticsEnabled", "appAnalyticsEnabled"],
            dataType: .bool
        ),
        .init(
            key: "diagnosticAndUsageReportingEnabled",
            displayName: "Diagnostics & Usage Reporting",
            description: "Whether diagnostic and usage reporting is enabled.",
            section: .security,
            responsePaths: [
                "security.diagnosticAndUsageReportingEnabled",
                "diagnosticAndUsageReportingEnabled"
            ],
            dataType: .bool
        ),
        .init(
            key: "airPlayPassword",
            displayName: "AirPlay Password Set",
            description: "Whether an AirPlay password is configured.",
            section: .security,
            responsePaths: ["security.airPlayPassword", "airPlayPassword"]
        ),
        .init(
            key: "quotaSize",
            displayName: "Quota Size",
            description: "Shared iPad quota size in megabytes.",
            section: .security,
            responsePaths: ["security.quotaSize", "quotaSize"],
            dataType: .integer
        ),
        .init(
            key: "residentUsers",
            displayName: "Resident Users",
            description: "Number of cached resident users on Shared iPad.",
            section: .security,
            responsePaths: ["security.residentUsers", "residentUsers"],
            dataType: .integer
        )
    ]

    // MARK: - Sortable-only display fields
    //
    // Documented as sortable on the inventory detail endpoint but absent from
    // the filterable allowlist. These can be selected as result columns or shown
    // on the detail screen, but the Advanced Search picker hides them via
    // `isFilterable: false`.

    private static let sortableOnlyGenerated: [MobileDeviceField] = [
        .init(
            key: "batteryHealth",
            displayName: "Battery Health",
            description: "Reported battery health classification.",
            section: .hardware,
            responsePaths: ["hardware.batteryHealth", "batteryHealth"],
            isFilterable: false
        ),
        .init(
            key: "lastBackupDate",
            displayName: "Last Backup",
            description: "Most recent device backup timestamp.",
            section: .general,
            responsePaths: ["general.lastBackupDate", "lastBackupDate"],
            dataType: .date,
            isFilterable: false
        ),
        .init(
            key: "lastEnrolledDate",
            displayName: "Last Enrolled",
            description: "Timestamp of the most recent enrollment.",
            section: .general,
            responsePaths: ["general.lastEnrolledDate", "lastEnrolledDate"],
            dataType: .date,
            isFilterable: false
        ),
        .init(
            key: "lastCloudBackupDate",
            displayName: "Last iCloud Backup",
            description: "Timestamp of the most recent iCloud backup.",
            section: .general,
            responsePaths: ["general.lastCloudBackupDate", "lastCloudBackupDate"],
            dataType: .date,
            isFilterable: false
        ),
        .init(
            key: "mdmProfileExpirationDate",
            displayName: "MDM Profile Expires",
            description: "Expiration date of the active MDM profile.",
            section: .general,
            responsePaths: [
                "general.mdmProfileExpirationDate",
                "mdmProfileExpirationDate"
            ],
            dataType: .date,
            isFilterable: false
        ),
        .init(
            key: "deviceOwnershipType",
            displayName: "Ownership Type",
            description: "Configured ownership classification.",
            section: .general,
            responsePaths: ["general.deviceOwnershipType", "deviceOwnershipType"],
            isFilterable: false
        ),
        .init(
            key: "leaseExpirationDate",
            displayName: "Lease Expires",
            description: "Recorded lease expiration date.",
            section: .purchasing,
            responsePaths: ["purchasing.leaseExpirationDate", "leaseExpirationDate"],
            dataType: .date,
            isFilterable: false
        ),
        .init(
            key: "poDate",
            displayName: "PO Date",
            description: "Purchase order date.",
            section: .purchasing,
            responsePaths: ["purchasing.poDate", "poDate"],
            dataType: .date,
            isFilterable: false
        ),
        .init(
            key: "warrantyExpirationDate",
            displayName: "Warranty Expires",
            description: "Recorded warranty expiration date.",
            section: .purchasing,
            responsePaths: [
                "purchasing.warrantyExpirationDate",
                "warrantyExpirationDate"
            ],
            dataType: .date,
            isFilterable: false
        ),
        .init(
            key: "hardwareEncryptionSupported",
            displayName: "Hardware Encryption",
            description: "Whether the hardware supports encryption.",
            section: .hardware,
            responsePaths: [
                "hardware.hardwareEncryptionSupported",
                "hardwareEncryptionSupported"
            ],
            dataType: .bool,
            isFilterable: false
        ),
        .init(
            key: "jailbreakStatus",
            displayName: "Jailbreak Status",
            description: "Reported jailbreak status.",
            section: .security,
            responsePaths: ["security.jailbreakStatus", "jailbreakStatus"],
            isFilterable: false
        ),
        .init(
            key: "cellularTechnology",
            displayName: "Cellular Technology",
            description: "Reported cellular technology generation.",
            section: .hardware,
            responsePaths: ["hardware.cellularTechnology", "cellularTechnology"],
            isFilterable: false
        )
    ]
}

//endofline
