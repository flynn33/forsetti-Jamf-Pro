import Foundation

enum ReportsFieldCatalog {
    nonisolated static let fields: [ReportField] = [
        .init(
            key: "deviceType",
            displayName: "Type",
            description: "Normalized device type.",
            dataType: .deviceType,
            domains: [.computer, .mobile],
            computerFieldKey: nil,
            mobileFieldKey: nil,
            computerSection: .general,
            mobileSection: .general,
            isServerFilterableForComputers: false,
            isServerFilterableForMobile: false
        ),
        .init(
            key: "model",
            displayName: "Model",
            description: "Jamf model string or catalog-resolved marketing model.",
            dataType: .string,
            domains: [.computer, .mobile],
            computerFieldKey: "hardware.model",
            mobileFieldKey: "model",
            computerSection: .hardware,
            mobileSection: .hardware,
            isServerFilterableForComputers: true,
            isServerFilterableForMobile: true
        ),
        .init(
            key: "modelIdentifier",
            displayName: "Model Identifier",
            description: "Apple model identifier.",
            dataType: .string,
            domains: [.computer, .mobile],
            computerFieldKey: "hardware.modelIdentifier",
            mobileFieldKey: "modelIdentifier",
            computerSection: .hardware,
            mobileSection: .hardware,
            isServerFilterableForComputers: true,
            isServerFilterableForMobile: true
        ),
        .init(
            key: "modelNumber",
            displayName: "Model Number",
            description: "Apple model number where Jamf reports it.",
            dataType: .string,
            domains: [.mobile],
            computerFieldKey: nil,
            mobileFieldKey: "modelNumber",
            computerSection: nil,
            mobileSection: .hardware,
            isServerFilterableForComputers: false,
            isServerFilterableForMobile: false
        ),
        .init(
            key: "osVersion",
            displayName: "OS Version",
            description: "Installed OS version.",
            dataType: .string,
            domains: [.computer, .mobile],
            computerFieldKey: "operatingSystem.version",
            mobileFieldKey: "osVersion",
            computerSection: .operatingSystem,
            mobileSection: .general,
            isServerFilterableForComputers: true,
            isServerFilterableForMobile: true
        ),
        .init(
            key: "osBuild",
            displayName: "OS Build",
            description: "Installed OS build.",
            dataType: .string,
            domains: [.computer, .mobile],
            computerFieldKey: "operatingSystem.build",
            mobileFieldKey: "osBuild",
            computerSection: .operatingSystem,
            mobileSection: .general,
            isServerFilterableForComputers: true,
            isServerFilterableForMobile: true
        ),
        .init(
            key: "building",
            displayName: "Building",
            description: "Jamf inventory building name.",
            dataType: .string,
            domains: [.computer, .mobile],
            // Computer inventory only exposes `buildingId` (numeric) in the
            // filter grammar. Names are resolved client-side via the
            // buildings directory, so the criterion runs client-side too.
            computerFieldKey: nil,
            mobileFieldKey: "building",
            computerSection: .userAndLocation,
            mobileSection: .location,
            isServerFilterableForComputers: false,
            isServerFilterableForMobile: true
        ),
        .init(
            key: "department",
            displayName: "Department",
            description: "Jamf inventory department name.",
            dataType: .string,
            domains: [.computer, .mobile],
            computerFieldKey: nil,
            mobileFieldKey: "department",
            computerSection: .userAndLocation,
            mobileSection: .location,
            isServerFilterableForComputers: false,
            isServerFilterableForMobile: true
        ),
        .init(
            key: "room",
            displayName: "Room",
            description: "Jamf inventory room field.",
            dataType: .string,
            domains: [.computer, .mobile],
            computerFieldKey: "userAndLocation.room",
            mobileFieldKey: "room",
            computerSection: .userAndLocation,
            mobileSection: .location,
            isServerFilterableForComputers: true,
            isServerFilterableForMobile: true
        ),
        .init(
            key: "assignedName",
            displayName: "Assigned Name",
            description: "Assigned user or real name.",
            dataType: .string,
            domains: [.computer, .mobile],
            computerFieldKey: "userAndLocation.realname",
            mobileFieldKey: "username",
            computerSection: .userAndLocation,
            mobileSection: .location,
            isServerFilterableForComputers: true,
            isServerFilterableForMobile: true
        ),
        .init(
            key: "email",
            displayName: "Assigned Email",
            description: "Assigned user email address.",
            dataType: .string,
            domains: [.computer, .mobile],
            computerFieldKey: "userAndLocation.email",
            mobileFieldKey: "emailAddress",
            computerSection: .userAndLocation,
            mobileSection: .location,
            isServerFilterableForComputers: true,
            isServerFilterableForMobile: true
        ),
        .init(
            key: "managed",
            displayName: "Managed",
            description: "Inventory management status.",
            dataType: .bool,
            domains: [.computer, .mobile],
            computerFieldKey: "general.remoteManagement.managed",
            mobileFieldKey: "managed",
            computerSection: .general,
            mobileSection: .general,
            isServerFilterableForComputers: true,
            isServerFilterableForMobile: true
        ),
        .init(
            key: "supervised",
            displayName: "Supervised",
            description: "Supervision status where supported.",
            dataType: .bool,
            domains: [.computer, .mobile],
            computerFieldKey: "general.supervised",
            mobileFieldKey: "supervised",
            computerSection: .general,
            mobileSection: .security,
            isServerFilterableForComputers: true,
            isServerFilterableForMobile: true
        ),
        .init(
            key: "ownership",
            displayName: "Ownership Type",
            description: "Device ownership type where Jamf reports it.",
            dataType: .string,
            domains: [.mobile],
            computerFieldKey: nil,
            mobileFieldKey: "deviceOwnershipType",
            computerSection: nil,
            mobileSection: .general,
            isServerFilterableForComputers: false,
            isServerFilterableForMobile: true
        ),
        .init(
            key: "batteryLevel",
            displayName: "Battery Level",
            description: "Battery level percentage where available.",
            dataType: .integer,
            domains: [.mobile],
            computerFieldKey: nil,
            mobileFieldKey: "batteryLevel",
            computerSection: nil,
            mobileSection: .hardware,
            isServerFilterableForComputers: false,
            isServerFilterableForMobile: false
        ),
        .init(
            key: "batteryHealth",
            displayName: "Battery Health",
            description: "Battery health state where available.",
            dataType: .string,
            domains: [.mobile],
            computerFieldKey: nil,
            mobileFieldKey: "batteryHealth",
            computerSection: nil,
            mobileSection: .hardware,
            isServerFilterableForComputers: false,
            isServerFilterableForMobile: false
        ),
        .init(
            key: "capacityMb",
            displayName: "Storage Capacity",
            description: "Reported device storage capacity in MB.",
            dataType: .integer,
            domains: [.mobile],
            computerFieldKey: nil,
            mobileFieldKey: "capacityMb",
            computerSection: nil,
            mobileSection: .hardware,
            isServerFilterableForComputers: false,
            isServerFilterableForMobile: false
        ),
        .init(
            key: "availableSpaceMb",
            displayName: "Available Storage",
            description: "Reported available storage in MB.",
            dataType: .integer,
            domains: [.mobile],
            computerFieldKey: nil,
            mobileFieldKey: "availableSpaceMb",
            computerSection: nil,
            mobileSection: .hardware,
            isServerFilterableForComputers: false,
            isServerFilterableForMobile: false
        ),
        .init(
            key: "usedSpacePercentage",
            displayName: "Used Storage %",
            description: "Reported used storage percentage.",
            dataType: .integer,
            domains: [.mobile],
            computerFieldKey: nil,
            mobileFieldKey: "usedSpacePercentage",
            computerSection: nil,
            mobileSection: .hardware,
            isServerFilterableForComputers: false,
            isServerFilterableForMobile: false
        ),
        .init(
            key: "extensionAttributes",
            displayName: "Extension Attributes",
            description: "Tenant extension attribute values present in returned inventory.",
            dataType: .string,
            domains: [.computer, .mobile],
            computerFieldKey: "extensionAttributes[].values[]",
            mobileFieldKey: "extensionAttributes",
            computerSection: .extensionAttributes,
            mobileSection: .extensionAttributes,
            isServerFilterableForComputers: false,
            isServerFilterableForMobile: false
        )
    ]

    nonisolated static let keyLookup: [String: ReportField] = Dictionary(uniqueKeysWithValues: fields.map { ($0.key, $0) })

    nonisolated static func field(for key: String) -> ReportField? {
        keyLookup[key]
    }

    nonisolated static func fields(for domain: ReportDeviceDomain) -> [ReportField] {
        let domains = domain.inventoryDomains
        return fields.filter { $0.domains.isDisjoint(with: domains) == false }
    }
}
