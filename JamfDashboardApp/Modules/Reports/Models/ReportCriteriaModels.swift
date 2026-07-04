import Foundation

enum ReportFieldDataType: String, Codable, CaseIterable, Identifiable, Sendable {
    case string
    case integer
    case decimal
    case bool
    case deviceType

    var id: String { rawValue }
}

enum ReportComparison: String, Codable, CaseIterable, Identifiable, Sendable {
    case equals
    case notEquals
    case contains
    case notContains
    case startsWith
    case endsWith
    case greaterThan
    case lessThan
    case isSet
    case isEmpty

    nonisolated var id: String { rawValue }

    nonisolated var displayName: String {
        switch self {
        case .equals: return "Equals"
        case .notEquals: return "Does Not Equal"
        case .contains: return "Contains"
        case .notContains: return "Does Not Contain"
        case .startsWith: return "Starts With"
        case .endsWith: return "Ends With"
        case .greaterThan: return "Greater Than"
        case .lessThan: return "Less Than"
        case .isSet: return "Is Set"
        case .isEmpty: return "Is Empty"
        }
    }

    nonisolated var requiresValue: Bool {
        switch self {
        case .isSet, .isEmpty:
            return false
        default:
            return true
        }
    }

    nonisolated func supports(_ dataType: ReportFieldDataType) -> Bool {
        switch (self, dataType) {
        case (.greaterThan, .integer), (.greaterThan, .decimal), (.lessThan, .integer), (.lessThan, .decimal):
            return true
        case (.contains, .string), (.notContains, .string), (.startsWith, .string), (.endsWith, .string):
            return true
        case (.equals, _), (.notEquals, _), (.isSet, _), (.isEmpty, _):
            return true
        default:
            return false
        }
    }
}

enum ReportGrouping: String, Codable, CaseIterable, Identifiable, Sendable {
    case deviceType
    case model
    case building
    case department
    case osVersion

    nonisolated var id: String { rawValue }

    nonisolated var displayName: String {
        switch self {
        case .deviceType: return "Device Type"
        case .model: return "Model"
        case .building: return "Building"
        case .department: return "Department"
        case .osVersion: return "OS Version"
        }
    }

    nonisolated var fieldKey: String {
        switch self {
        case .deviceType: return "deviceType"
        case .model: return "model"
        case .building: return "building"
        case .department: return "department"
        case .osVersion: return "osVersion"
        }
    }
}

enum ReportChartPreference: String, Codable, CaseIterable, Identifiable, Sendable {
    case compositionRing
    case rankedBars
    case locationDistribution
    case osDistribution

    nonisolated var id: String { rawValue }

    nonisolated var displayName: String {
        switch self {
        case .compositionRing: return "Composition Ring"
        case .rankedBars: return "Ranked Bars"
        case .locationDistribution: return "Location Distribution"
        case .osDistribution: return "OS Distribution"
        }
    }
}

struct ReportField: Identifiable, Hashable, Sendable {
    let key: String
    let displayName: String
    let description: String
    let dataType: ReportFieldDataType
    let domains: Set<ReportInventoryDomain>
    let computerFieldKey: String?
    let mobileFieldKey: String?
    let computerSection: ComputerInventorySection?
    let mobileSection: MobileDeviceInventorySection?
    let isServerFilterableForComputers: Bool
    let isServerFilterableForMobile: Bool

    var id: String { key }
}

struct ReportCriterion: Identifiable, Codable, Hashable, Sendable {
    var id = UUID()
    var fieldKey: String
    var comparison: ReportComparison
    var value: String

    nonisolated var trimmedValue: String {
        value.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

/// Optional visual panels the generated report can display. The metric grid
/// (Total / Mac / iPad / iPhone / Unknown) and the inferred/unknown
/// disclosure line are always shown — they describe the result set itself
/// and are not user-selectable. Everything else is opt-in via this enum.
///
/// `defaults` mirrors what shipped before user-selectable frames existed,
/// minus Storage and Battery, which were rarely useful on mixed-fleet
/// reports and have been moved off the default set per operator feedback.
enum ReportFrame: String, Codable, CaseIterable, Identifiable, Sendable {
    case compositionGauge
    case topModels
    case locations
    case osVersions
    case storage
    case battery
    case detailsTable

    nonisolated var id: String { rawValue }

    nonisolated var displayName: String {
        switch self {
        case .compositionGauge: return "Composition Gauge"
        case .topModels: return "Top Models"
        case .locations: return "Locations"
        case .osVersions: return "OS Versions"
        case .storage: return "Storage"
        case .battery: return "Battery"
        case .detailsTable: return "Details Table"
        }
    }

    nonisolated var summary: String {
        switch self {
        case .compositionGauge: return "Segmented device-type ring with totals."
        case .topModels: return "Ranked bar chart of marketing model names."
        case .locations: return "Ranked bar chart grouped by the \u{201C}Billing GL & Store NO\u{201D} EA."
        case .osVersions: return "Ranked bar chart of installed OS versions."
        case .storage: return "Distribution of mobile devices across storage-usage buckets."
        case .battery: return "Distribution of mobile devices across battery-level buckets."
        case .detailsTable: return "Per-device detail rows. Sortable. All records visible."
        }
    }

    /// Default frames for a new report. Excludes Storage and Battery.
    nonisolated static let defaults: Set<ReportFrame> = [
        .compositionGauge,
        .topModels,
        .locations,
        .osVersions,
        .detailsTable
    ]

    /// Stable order used by the report builder and the generated report
    /// page so frame ordering is the same across the UI surfaces.
    nonisolated static let displayOrder: [ReportFrame] = [
        .compositionGauge,
        .topModels,
        .locations,
        .osVersions,
        .storage,
        .battery,
        .detailsTable
    ]
}

struct ReportRequest: Identifiable, Codable, Hashable, Sendable {
    var id = UUID()
    var name: String
    var domain: ReportDeviceDomain
    var criteria: [ReportCriterion]
    var grouping: ReportGrouping
    var chartPreference: ReportChartPreference
    /// Which visual panels the generated report should render. Always-shown
    /// elements (metric grid, inferred/unknown disclosure) are not included
    /// here. Defaults to `ReportFrame.defaults` for newly built reports;
    /// kept Codable so persisted requests round-trip cleanly.
    var frames: Set<ReportFrame> = ReportFrame.defaults

    nonisolated static let defaultCounts = ReportRequest(
        name: "Device Counts",
        domain: .all,
        criteria: [],
        grouping: .deviceType,
        chartPreference: .compositionRing,
        frames: ReportFrame.defaults
    )

    nonisolated static let blankBuilder = ReportRequest(
        name: "Device Counts",
        domain: .all,
        criteria: [],
        grouping: .deviceType,
        chartPreference: .compositionRing,
        frames: ReportFrame.defaults
    )

    nonisolated var resolvedName: String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "Jamf Inventory Report" : trimmed
    }
}

struct ReportQueryPlan: Hashable, Sendable {
    let domains: Set<ReportInventoryDomain>
    let computerSections: Set<ComputerInventorySection>
    let mobileSections: Set<MobileDeviceInventorySection>
    let computerServerFilter: String?
    let mobileServerFilter: String?
    let clientCriteria: [ReportCriterion]
    let requestedFields: [ReportField]
}

struct GeneratedReport: Identifiable, Hashable, Sendable {
    let id = UUID()
    let request: ReportRequest
    let dataSet: ReportDataSet

    nonisolated var aggregate: ReportAggregate {
        dataSet.aggregate
    }
}
