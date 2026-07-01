import Foundation

struct ReportTextRenderer: ReportExportRendering {
    func render(payload: ReportExportPayload) throws -> Data {
        var lines: [String] = []
        lines.append(payload.request.resolvedName)
        lines.append(String(repeating: "=", count: payload.request.resolvedName.count))
        lines.append("Generated: \(Self.dateFormatter.string(from: payload.generatedAt))")
        if let serverLabel = payload.serverLabel {
            lines.append("Jamf Server: \(serverLabel)")
        }
        lines.append("Criteria: \(criteriaSummary(payload.request))")
        lines.append("")
        lines.append("Total Devices: \(payload.aggregate.totalCount)")
        lines.append("")
        lines.append("Device Types")
        for item in payload.aggregate.orderedTypeCounts where item.count > 0 {
            lines.append("- \(item.type.displayName): \(item.count)")
        }
        lines.append("")
        lines.append("Top Models")
        for (label, count) in ranked(payload.aggregate.countsByModel).prefix(10) {
            lines.append("- \(label): \(count)")
        }
        lines.append("")
        lines.append("Details")
        for record in payload.records.prefix(500) {
            lines.append("- \(record.deviceType.displayName) | \(record.displayName ?? "Unnamed") | \(record.serialNumber ?? "No serial") | \(record.identity.marketingName ?? record.model ?? "Unknown model") | enrolled \(record.value(for: "enrollmentDate") ?? "n/a") | \(record.identity.confidence.displayName)")
        }
        if payload.records.count > 500 {
            lines.append("- Details truncated to first 500 records.")
        }
        if payload.aggregate.inferredCount > 0 || payload.aggregate.unknownCount > 0 {
            lines.append("")
            lines.append("Disclosure: \(payload.aggregate.inferredCount) records include inferred identity values. \(payload.aggregate.unknownCount) records contain unknown type or identity values.")
        }
        return Data(lines.joined(separator: "\n").utf8)
    }

    private func criteriaSummary(_ request: ReportRequest) -> String {
        guard request.criteria.isEmpty == false else {
            return "No criteria. Domain: \(request.domain.displayName)."
        }
        return request.criteria.compactMap { criterion in
            guard let field = ReportsFieldCatalog.field(for: criterion.fieldKey) else { return nil }
            return "\(field.displayName) \(criterion.comparison.displayName.lowercased()) \(criterion.value)"
        }.joined(separator: "; ")
    }

    private func ranked(_ values: [String: Int]) -> [(String, Int)] {
        values.sorted {
            if $0.value == $1.value {
                return $0.key.localizedCaseInsensitiveCompare($1.key) == .orderedAscending
            }
            return $0.value > $1.value
        }
    }

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter
    }()
}
