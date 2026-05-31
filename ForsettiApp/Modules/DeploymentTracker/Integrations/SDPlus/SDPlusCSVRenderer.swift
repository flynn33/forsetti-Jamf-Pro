import Foundation

// MARK: - SD+ CSV renderer
//
// The SD+ renderer creates template-driven CSV output and validation results
// from Tracker devices. It uses Workbench display-value rules so what users
// inspect in the grid matches what appears in exported CSV.
nonisolated struct SDPlusCSVRenderer: Sendable {
    private let fieldDefinitionsByKey: [String: DeploymentFieldDefinition]
    private let referenceValuesById: [String: String]
    private let projectionService = DeploymentWorkbenchProjectionService()

    init(
        fieldDefinitions: [DeploymentFieldDefinition],
        referenceValues: [DeploymentReferenceValue]
    ) {
        self.fieldDefinitionsByKey = Dictionary(uniqueKeysWithValues: fieldDefinitions.map { ($0.fieldKey, $0) })
        self.referenceValuesById = Dictionary(uniqueKeysWithValues: referenceValues.map { ($0.id, $0.displayName) })
    }

    func render(
        devices: [DeploymentDevice],
        template: SDPlusExportTemplate
    ) -> SDPlusRenderedExport {
        // Template column order is authoritative. Unknown fields are reported as
        // blocking issues so exports do not silently drop required SD+ columns.
        let columns = template.columns.sorted { $0.columnOrder < $1.columnOrder }
        var issues: [SDPlusExportValidationIssue] = []
        let unknownColumns = columns.filter { fieldDefinitionsByKey[$0.sourceField] == nil }

        issues.append(contentsOf: unknownColumns.map {
            issue(
                .blocking,
                fieldKey: $0.sourceField,
                columnHeader: $0.header,
                "SD+ template source field must be a Deployment Tracker Field Catalog key."
            )
        })

        var lines: [String] = []
        if template.includeHeader {
            lines.append(columns.map { csvEscape($0.header, delimiter: template.delimiter) }.joined(separator: template.delimiter))
        }

        for device in devices {
            let row = columns.map { column in
                let renderedValue = renderValue(
                    for: column,
                    device: device,
                    issues: &issues
                )
                return csvEscape(renderedValue, delimiter: template.delimiter)
            }
            lines.append(row.joined(separator: template.delimiter))
        }

        let hasGlobalBlockingIssue = issues.contains { $0.severity == .blocking && $0.deviceId == nil }
        let failedDeviceIds: [String]
        if hasGlobalBlockingIssue {
            failedDeviceIds = devices.map(\.id)
        } else {
            failedDeviceIds = Array(Set(issues.compactMap { $0.severity == .blocking ? $0.deviceId : nil })).sorted()
        }
        let failedDeviceIdSet = Set(failedDeviceIds)

        return SDPlusRenderedExport(
            templateId: template.id,
            csv: lines.joined(separator: "\n"),
            validation: SDPlusExportValidationResult(issues: issues),
            includedDeviceIds: devices.map(\.id).filter { !failedDeviceIdSet.contains($0) },
            failedDeviceIds: failedDeviceIds
        )
    }

    private func renderValue(
        for column: SDPlusExportColumn,
        device: DeploymentDevice,
        issues: inout [SDPlusExportValidationIssue]
    ) -> String {
        let sourceFieldExists = fieldDefinitionsByKey[column.sourceField] != nil
        var value = sourceFieldExists
            ? projectionService.displayValue(
                for: column.sourceField,
                device: device,
                referenceValuesById: referenceValuesById
            )
            : ""

        value = applyTransform(column.transformRule, to: value)

        if value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
           let defaultValue = column.defaultValue {
            value = applyTransform(column.transformRule, to: defaultValue)
        }

        let trimmedValue = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if column.required && trimmedValue.isEmpty {
            issues.append(issue(
                .blocking,
                deviceId: device.id,
                fieldKey: column.sourceField,
                columnHeader: column.header,
                "Required SD+ value is missing."
            ))
        }

        if column.emptyValueBehavior?.caseInsensitiveCompare("fail") == .orderedSame,
           trimmedValue.isEmpty {
            issues.append(issue(
                .blocking,
                deviceId: device.id,
                fieldKey: column.sourceField,
                columnHeader: column.header,
                "SD+ template disallows empty values for this column."
            ))
        }

        if !column.allowedValues.isEmpty && !trimmedValue.isEmpty {
            let allowedValues = column.allowedValues.map { $0.lowercased() }
            if !allowedValues.contains(trimmedValue.lowercased()) {
                issues.append(issue(
                    .blocking,
                    deviceId: device.id,
                    fieldKey: column.sourceField,
                    columnHeader: column.header,
                    "Value is not allowed by the SD+ template."
                ))
            }
        }

        if let maxLength = column.maxLength,
           value.count > maxLength {
            issues.append(issue(
                .blocking,
                deviceId: device.id,
                fieldKey: column.sourceField,
                columnHeader: column.header,
                "Value exceeds the SD+ template maximum length."
            ))
        }

        return value
    }

    private func applyTransform(_ transformRule: String?, to value: String) -> String {
        switch transformRule?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "uppercase":
            return value.uppercased()
        case "lowercase":
            return value.lowercased()
        case "trim":
            return value.trimmingCharacters(in: .whitespacesAndNewlines)
        default:
            return value
        }
    }

    private func issue(
        _ severity: SDPlusExportValidationSeverity,
        deviceId: String? = nil,
        fieldKey: String? = nil,
        columnHeader: String? = nil,
        _ message: String
    ) -> SDPlusExportValidationIssue {
        SDPlusExportValidationIssue(
            severity: severity,
            deviceId: deviceId,
            fieldKey: fieldKey,
            columnHeader: columnHeader,
            message: message
        )
    }

    private func csvEscape(_ value: String, delimiter: String) -> String {
        if value.contains(delimiter) || value.contains("\"") || value.contains("\n") || value.contains("\r") {
            return "\"\(value.replacingOccurrences(of: "\"", with: "\"\""))\""
        }
        return value
    }
}
