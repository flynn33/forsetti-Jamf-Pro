import Foundation

enum ReportInventoryDomain: String, Codable, CaseIterable, Identifiable, Sendable {
    case computer
    case mobile

    nonisolated var id: String { rawValue }

    nonisolated var displayName: String {
        switch self {
        case .computer: return "Computers"
        case .mobile: return "Mobile Devices"
        }
    }
}

enum ReportDeviceDomain: String, Codable, CaseIterable, Identifiable, Sendable {
    case all
    case computers
    case mobileDevices

    nonisolated var id: String { rawValue }

    nonisolated var displayName: String {
        switch self {
        case .all: return "All Devices"
        case .computers: return "Computers"
        case .mobileDevices: return "Mobile Devices"
        }
    }

    nonisolated var inventoryDomains: Set<ReportInventoryDomain> {
        switch self {
        case .all: return [.computer, .mobile]
        case .computers: return [.computer]
        case .mobileDevices: return [.mobile]
        }
    }
}

enum ReportDeviceType: String, Codable, CaseIterable, Identifiable, Sendable {
    case mac
    case ipad
    case iphone
    case other
    case unknown

    nonisolated var id: String { rawValue }

    nonisolated static let displayOrder: [ReportDeviceType] = [.mac, .ipad, .iphone, .other, .unknown]

    nonisolated var displayName: String {
        switch self {
        case .mac: return "Mac"
        case .ipad: return "iPad"
        case .iphone: return "iPhone"
        case .other: return "Other"
        case .unknown: return "Unknown"
        }
    }

    nonisolated var symbolName: String {
        switch self {
        case .mac: return "desktopcomputer"
        case .ipad: return "ipad"
        case .iphone: return "iphone"
        case .other: return "display"
        case .unknown: return "questionmark.circle"
        }
    }

    nonisolated var rgba: ReportRGBA {
        switch self {
        case .mac: return ReportRGBA(red: 0.12, green: 0.38, blue: 0.88, alpha: 1.0)
        case .ipad: return ReportRGBA(red: 0.18, green: 0.66, blue: 0.38, alpha: 1.0)
        case .iphone: return ReportRGBA(red: 0.94, green: 0.55, blue: 0.16, alpha: 1.0)
        case .other: return ReportRGBA(red: 0.48, green: 0.34, blue: 0.84, alpha: 1.0)
        case .unknown: return ReportRGBA(red: 0.48, green: 0.50, blue: 0.55, alpha: 1.0)
        }
    }
}

enum ReportEnrichmentConfidence: String, Codable, CaseIterable, Identifiable, Sendable {
    case jamfAuthoritative
    case catalogResolved
    case inferredHigh
    case inferredMedium
    case unknown

    nonisolated var id: String { rawValue }

    nonisolated var displayName: String {
        switch self {
        case .jamfAuthoritative: return "Jamf authoritative"
        case .catalogResolved: return "Catalog resolved"
        case .inferredHigh: return "Inferred high confidence"
        case .inferredMedium: return "Inferred medium confidence"
        case .unknown: return "Unknown"
        }
    }

    nonisolated var isInferred: Bool {
        switch self {
        case .inferredHigh, .inferredMedium:
            return true
        case .jamfAuthoritative, .catalogResolved, .unknown:
            return false
        }
    }
}

struct ReportRGBA: Codable, Hashable, Sendable {
    let red: Double
    let green: Double
    let blue: Double
    let alpha: Double

    nonisolated var floatComponents: [Float] {
        [Float(red), Float(green), Float(blue), Float(alpha)]
    }
}

struct ReportDeviceLocation: Codable, Hashable, Sendable {
    var building: String?
    var department: String?
    var room: String?
    var assignedName: String?
    var email: String?

    nonisolated var summary: String {
        [building, department, room]
            .compactMap { value in
                let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines)
                return trimmed?.isEmpty == false ? trimmed : nil
            }
            .joined(separator: " / ")
    }
}

struct ReportDeviceManagement: Codable, Hashable, Sendable {
    var managed: Bool?
    var supervised: Bool?
    var ownership: String?
}

struct ReportHardwareMetrics: Codable, Hashable, Sendable {
    var capacityMb: Int?
    var availableSpaceMb: Int?
    var usedSpacePercentage: Int?
    var batteryLevel: Int?
    var batteryHealth: String?
}

struct ReportDeviceIdentity: Codable, Hashable, Sendable {
    var deviceType: ReportDeviceType
    var marketingName: String?
    var generation: String?
    var chipName: String?
    var ramGB: Int?
    var confidence: ReportEnrichmentConfidence
    var sourceDescription: String
}

struct ReportDeviceRecord: Identifiable, Codable, Hashable, Sendable {
    /// `fieldValues` key under which `ReportsInventoryService` carries the
    /// resolved value of the "Billing GL & Store NO" Extension Attribute.
    /// `ReportsAggregator` reads from this key to populate the Locations
    /// panel. Single source of truth so the two sides cannot drift.
    nonisolated static let locationExtensionAttributeFieldKey = "billingGLStoreNo"

    let id: String
    let domain: ReportInventoryDomain
    let deviceType: ReportDeviceType
    let displayName: String?
    let serialNumber: String?
    let model: String?
    let modelIdentifier: String?
    let modelNumber: String?
    let osVersion: String?
    let osBuild: String?
    let location: ReportDeviceLocation
    let management: ReportDeviceManagement
    let hardwareMetrics: ReportHardwareMetrics
    let identity: ReportDeviceIdentity
    let fieldValues: [String: String]

    nonisolated func value(for fieldKey: String) -> String? {
        if let mapped = fieldValues[fieldKey], mapped.isEmpty == false {
            return mapped
        }

        switch fieldKey {
        case "domain": return domain.displayName
        case "deviceType": return deviceType.displayName
        case "name": return displayName
        case "serialNumber": return serialNumber
        case "model": return model
        case "modelIdentifier": return modelIdentifier
        case "modelNumber": return modelNumber
        case "osVersion": return osVersion
        case "osBuild": return osBuild
        case "building": return location.building
        case "department": return location.department
        case "room": return location.room
        case "assignedName": return location.assignedName
        case "email": return location.email
        case "managed": return management.managed.map(String.init)
        case "supervised": return management.supervised.map(String.init)
        case "ownership": return management.ownership
        case "capacityMb": return hardwareMetrics.capacityMb.map(String.init)
        case "availableSpaceMb": return hardwareMetrics.availableSpaceMb.map(String.init)
        case "usedSpacePercentage": return hardwareMetrics.usedSpacePercentage.map(String.init)
        case "batteryLevel": return hardwareMetrics.batteryLevel.map(String.init)
        case "batteryHealth": return hardwareMetrics.batteryHealth
        case "marketingName": return identity.marketingName
        case "chipName": return identity.chipName
        case "sourceConfidence": return identity.confidence.displayName
        default: return nil
        }
    }
}

struct ReportDataSet: Codable, Hashable, Sendable {
    let records: [ReportDeviceRecord]
    let aggregate: ReportAggregate
    let generatedAt: Date
    let serverLabel: String?
}
