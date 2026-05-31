import Foundation

// MARK: - Vendor import parser
//
// The parser creates a preview from text content and an import mapping. It checks
// mapping targets against the Field Catalog before parsing rows so bad mappings
// are visible before any device records are created or updated.
nonisolated struct DeploymentVendorImportParser: Sendable {
    private let fieldKeys: Set<String>

    init(fieldDefinitions: [DeploymentFieldDefinition]) {
        self.fieldKeys = Set(fieldDefinitions.map(\.fieldKey))
    }

    func preview(
        content: String,
        mapping: DeploymentImportMapping
    ) -> DeploymentVendorImportPreview {
        // Validate mapping field keys first. Unknown keys indicate the import
        // template is out of sync with the current Field Catalog.
        var issues: [DeploymentVendorImportIssue] = []

        for column in mapping.columns where !fieldKeys.contains(column.fieldKey) {
            issues.append(DeploymentVendorImportIssue(
                fieldKey: column.fieldKey,
                message: "Import mapping target must be a Deployment Tracker Field Catalog key."
            ))
        }

        let parsedRows: [[String]]
        let headers: [String]
        switch mapping.format {
        case .serialList:
            headers = ["Serial Number"]
            parsedRows = content
                .components(separatedBy: .newlines)
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
                .map { [$0] }
        case .csv, .excelExportedCSV, .numbersExportedCSV:
            let rows = parseCSV(content)
            headers = rows.first ?? []
            parsedRows = Array(rows.dropFirst())
        }

        let headerIndexes = Dictionary(uniqueKeysWithValues: headers.enumerated().map { ($0.element, $0.offset) })
        var rows: [DeploymentVendorImportRow] = []

        for (offset, parsedRow) in parsedRows.enumerated() {
            let rowNumber = offset + (mapping.format == .serialList ? 1 : 2)
            var values: [String: String] = [:]

            for column in mapping.columns {
                let rawValue = headerIndexes[column.sourceHeader].flatMap { index in
                    parsedRow.indices.contains(index) ? parsedRow[index] : nil
                }
                let value = rawValue?.trimmingCharacters(in: .whitespacesAndNewlines)
                let resolvedValue = value?.isEmpty == false ? value! : column.defaultValue ?? ""
                values[column.fieldKey] = resolvedValue

                if column.required && resolvedValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    issues.append(DeploymentVendorImportIssue(
                        rowNumber: rowNumber,
                        fieldKey: column.fieldKey,
                        message: "Required import value is missing."
                    ))
                }
            }

            rows.append(DeploymentVendorImportRow(rowNumber: rowNumber, valuesByFieldKey: values))
        }

        issues.append(contentsOf: duplicateSerialIssues(rows: rows))

        return DeploymentVendorImportPreview(mappingId: mapping.id, rows: rows, issues: issues)
    }

    private func duplicateSerialIssues(rows: [DeploymentVendorImportRow]) -> [DeploymentVendorImportIssue] {
        let rowsBySerial = Dictionary(grouping: rows) {
            DeploymentDevice.normalizeSerial($0.valuesByFieldKey["device.serialNumber"] ?? "")
        }

        return rowsBySerial
            .filter { !$0.key.isEmpty && $0.value.count > 1 }
            .flatMap { serial, rows in
                rows.map {
                    DeploymentVendorImportIssue(
                        rowNumber: $0.rowNumber,
                        fieldKey: "device.serialNumber",
                        message: "Duplicate serial number \(serial) appears in import preview."
                    )
                }
            }
            .sorted { ($0.rowNumber ?? 0) < ($1.rowNumber ?? 0) }
    }

    private func parseCSV(_ content: String) -> [[String]] {
        var rows: [[String]] = []
        var row: [String] = []
        var field = ""
        var inQuotes = false
        var index = content.startIndex

        while index < content.endIndex {
            let character = content[index]

            if character == "\"" {
                let nextIndex = content.index(after: index)
                if inQuotes, nextIndex < content.endIndex, content[nextIndex] == "\"" {
                    field.append("\"")
                    index = nextIndex
                } else {
                    inQuotes.toggle()
                }
            } else if character == "," && !inQuotes {
                row.append(field)
                field = ""
            } else if character == "\n" && !inQuotes {
                row.append(field)
                rows.append(row)
                row = []
                field = ""
            } else if character != "\r" || inQuotes {
                field.append(character)
            }

            index = content.index(after: index)
        }

        row.append(field)
        if row.contains(where: { !$0.isEmpty }) {
            rows.append(row)
        }
        return rows
    }
}
