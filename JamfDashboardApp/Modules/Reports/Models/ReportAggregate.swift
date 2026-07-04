import Foundation

struct ReportAggregate: Codable, Hashable, Sendable {
    let totalCount: Int
    let countsByType: [ReportDeviceType: Int]
    let countsByModel: [String: Int]
    let countsByLocation: [String: Int]
    let countsByOSVersion: [String: Int]
    let storageBuckets: [String: Int]
    let batteryBuckets: [String: Int]
    let unknownCount: Int
    let inferredCount: Int
    let gaugeSegments: [ReportGaugeSegment]

    nonisolated static let empty = ReportAggregate(
        totalCount: 0,
        countsByType: Dictionary(uniqueKeysWithValues: ReportDeviceType.allCases.map { ($0, 0) }),
        countsByModel: [:],
        countsByLocation: [:],
        countsByOSVersion: [:],
        storageBuckets: [:],
        batteryBuckets: [:],
        unknownCount: 0,
        inferredCount: 0,
        gaugeSegments: []
    )

    nonisolated func count(for type: ReportDeviceType) -> Int {
        countsByType[type] ?? 0
    }

    nonisolated var orderedTypeCounts: [(type: ReportDeviceType, count: Int)] {
        ReportDeviceType.displayOrder.map { ($0, count(for: $0)) }
    }

    nonisolated var nonZeroTypeCounts: [(type: ReportDeviceType, count: Int)] {
        orderedTypeCounts.filter { $0.count > 0 }
    }
}

struct ReportGaugeSegment: Identifiable, Codable, Hashable, Sendable {
    let id: String
    let label: String
    let count: Int
    let fraction: Double
    let startAngle: Double
    let endAngle: Double
    let colorRGBA: ReportRGBA
    let accessibilityText: String
}
