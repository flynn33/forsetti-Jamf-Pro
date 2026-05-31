import Foundation

struct ReportCSVRenderer: ReportExportRendering {
    private let columns: [String] = [
        "Device Type",
        "Name",
        "Serial Number",
        "Model",
        "Model Identifier",
        "OS Version",
        "Building",
        "Department",
        "Room",
        "Managed",
        "Supervised",
        "Source Confidence"
    ]

    func render(payload: ReportExportPayload) throws -> Data {
        var rows: [[String]] = [columns]
        for record in payload.records {
            let managed = record.management.managed.map { String($0) } ?? ""
            let supervised = record.management.supervised.map { String($0) } ?? ""
            let row: [String] = [
                record.deviceType.displayName,
                record.displayName ?? "",
                record.serialNumber ?? "",
                record.identity.marketingName ?? record.model ?? "",
                record.modelIdentifier ?? "",
                record.osVersion ?? "",
                record.location.building ?? "",
                record.location.department ?? "",
                record.location.room ?? "",
                managed,
                supervised,
                record.identity.confidence.displayName
            ]
            rows.append(row)
        }

        let csv = rows.map { $0.map(Self.escape).joined(separator: ",") }.joined(separator: "\n") + "\n"
        return Data(csv.utf8)
    }

    nonisolated static func escape(_ value: String) -> String {
        let escaped = value.replacingOccurrences(of: "\"", with: "\"\"")
        if escaped.contains(",") || escaped.contains("\"") || escaped.contains("\n") || escaped.contains("\r") {
            return "\"\(escaped)\""
        }
        return escaped
    }
}
