import Foundation

nonisolated struct ReportsAggregator: Sendable {
    nonisolated func aggregate(records: [ReportDeviceRecord]) -> ReportAggregate {
        let countsByType = Dictionary(
            uniqueKeysWithValues: ReportDeviceType.allCases.map { type in
                (type, records.filter { $0.deviceType == type }.count)
            }
        )

        let countsByModel = count(records.compactMap {
            $0.identity.marketingName ?? $0.model
        })
        // The Locations panel buckets records by the value of the
        // "Billing GL & Store NO" Extension Attribute. `ReportsInventoryService`
        // resolves the EA value per record on both the computer and mobile
        // sides and writes it under `locationExtensionAttributeFieldKey` in
        // `fieldValues`. Records without the EA bucket as "Unassigned".
        let countsByLocation = count(records.map { record in
            let value = record.fieldValues[ReportDeviceRecord.locationExtensionAttributeFieldKey]?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return value.isEmpty ? "Unassigned" : value
        })
        let countsByOSVersion = count(records.map { $0.osVersion ?? "Unknown" })
        let storageBuckets = count(records.compactMap { storageBucket(for: $0.hardwareMetrics.usedSpacePercentage) })
        let batteryBuckets = count(records.compactMap { batteryBucket(for: $0.hardwareMetrics.batteryLevel) })
        let inferredCount = records.filter { $0.identity.confidence.isInferred }.count
        let unknownCount = records.filter { $0.deviceType == .unknown || $0.identity.confidence == .unknown }.count

        let aggregateWithoutSegments = ReportAggregate(
            totalCount: records.count,
            countsByType: countsByType,
            countsByModel: countsByModel,
            countsByLocation: countsByLocation,
            countsByOSVersion: countsByOSVersion,
            storageBuckets: storageBuckets,
            batteryBuckets: batteryBuckets,
            unknownCount: unknownCount,
            inferredCount: inferredCount,
            gaugeSegments: []
        )

        return ReportAggregate(
            totalCount: aggregateWithoutSegments.totalCount,
            countsByType: aggregateWithoutSegments.countsByType,
            countsByModel: aggregateWithoutSegments.countsByModel,
            countsByLocation: aggregateWithoutSegments.countsByLocation,
            countsByOSVersion: aggregateWithoutSegments.countsByOSVersion,
            storageBuckets: aggregateWithoutSegments.storageBuckets,
            batteryBuckets: aggregateWithoutSegments.batteryBuckets,
            unknownCount: aggregateWithoutSegments.unknownCount,
            inferredCount: aggregateWithoutSegments.inferredCount,
            gaugeSegments: gaugeSegments(for: aggregateWithoutSegments)
        )
    }

    nonisolated private func count(_ values: [String]) -> [String: Int] {
        var result: [String: Int] = [:]
        for value in values {
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            result[trimmed.isEmpty ? "Unknown" : trimmed, default: 0] += 1
        }
        return result
    }

    nonisolated private func storageBucket(for usedPercent: Int?) -> String? {
        guard let usedPercent else { return nil }
        switch usedPercent {
        case ..<50: return "Under 50% Used"
        case 50 ..< 80: return "50-79% Used"
        case 80...: return "80%+ Used"
        default: return nil
        }
    }

    nonisolated private func batteryBucket(for batteryLevel: Int?) -> String? {
        guard let batteryLevel else { return nil }
        switch batteryLevel {
        case ..<20: return "Under 20%"
        case 20 ..< 50: return "20-49%"
        case 50 ..< 80: return "50-79%"
        case 80...: return "80%+"
        default: return nil
        }
    }

    nonisolated private func gaugeSegments(for aggregate: ReportAggregate) -> [ReportGaugeSegment] {
        guard aggregate.totalCount > 0 else { return [] }

        var cursor = -Double.pi / 2.0
        return aggregate.nonZeroTypeCounts.map { type, count in
            let fraction = Double(count) / Double(aggregate.totalCount)
            let start = cursor
            let end = cursor + (Double.pi * 2.0 * fraction)
            cursor = end
            let percent = Int((fraction * 100).rounded())
            return ReportGaugeSegment(
                id: type.rawValue,
                label: type.displayName,
                count: count,
                fraction: fraction,
                startAngle: start,
                endAngle: end,
                colorRGBA: type.rgba,
                accessibilityText: "\(type.displayName): \(count), \(percent) percent"
            )
        }
    }
}
