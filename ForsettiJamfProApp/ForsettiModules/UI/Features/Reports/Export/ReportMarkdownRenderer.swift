import Foundation

struct ReportMarkdownRenderer: ReportExportRendering {
    func render(payload: ReportExportPayload) throws -> Data {
        var lines: [String] = []
        lines.append("# \(payload.request.resolvedName)")
        lines.append("")
        lines.append("| Metadata | Value |")
        lines.append("|---|---|")
        lines.append("| Generated | \(escape(dateFormatter.string(from: payload.generatedAt))) |")
        lines.append("| Jamf Server | \(escape(payload.serverLabel ?? "Not available")) |")
        lines.append("| Domain | \(escape(payload.request.domain.displayName)) |")
        lines.append("| Total Devices | \(payload.aggregate.totalCount) |")
        lines.append("")
        lines.append("## Device Types")
        lines.append("")
        lines.append("| Type | Count |")
        lines.append("|---|---:|")
        for item in payload.aggregate.orderedTypeCounts {
            lines.append("| \(escape(item.type.displayName)) | \(item.count) |")
        }
        lines.append("")
        lines.append("## Details")
        lines.append("")
        lines.append("| Type | Name | Serial | Model | OS | Enrolled | Confidence |")
        lines.append("|---|---|---|---|---|---|---|")
        for record in payload.records.prefix(500) {
            lines.append("| \(escape(record.deviceType.displayName)) | \(escape(record.displayName ?? "")) | \(escape(record.serialNumber ?? "")) | \(escape(record.identity.marketingName ?? record.model ?? "")) | \(escape(record.osVersion ?? "")) | \(escape(record.value(for: "enrollmentDate") ?? "")) | \(escape(record.identity.confidence.displayName)) |")
        }
        if payload.records.count > 500 {
            lines.append("")
            lines.append("_Details truncated to first 500 records._")
        }
        if payload.aggregate.inferredCount > 0 || payload.aggregate.unknownCount > 0 {
            lines.append("")
            lines.append("> \(payload.aggregate.inferredCount) records include inferred identity values. \(payload.aggregate.unknownCount) records contain unknown type or identity values.")
        }
        return Data(lines.joined(separator: "\n").utf8)
    }

    private func escape(_ value: String) -> String {
        value
            .replacingOccurrences(of: "|", with: "\\|")
            .replacingOccurrences(of: "\n", with: " ")
    }

    private let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter
    }()
}
