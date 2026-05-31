import Foundation

// MARK: - Vendor import models
//
// Import models describe preview-first data ingestion from vendor CSV exports,
// serial lists, workbook migration files, or Numbers/Excel CSV output. The
// preview layer captures issues before anything is committed to Tracker storage.
nonisolated enum DeploymentVendorImportFormat: String, Codable, CaseIterable, Sendable {
    case csv
    case excelExportedCSV
    case numbersExportedCSV
    case serialList
}

nonisolated struct DeploymentImportMapping: Identifiable, Codable, Equatable, Sendable {
    let id: String
    var displayName: String
    var format: DeploymentVendorImportFormat
    var columns: [DeploymentImportMappingColumn]
    var createdAt: Date
    var modifiedAt: Date

    init(
        id: String = UUID().uuidString,
        displayName: String,
        format: DeploymentVendorImportFormat,
        columns: [DeploymentImportMappingColumn],
        createdAt: Date = Date(),
        modifiedAt: Date? = nil
    ) {
        self.id = id
        self.displayName = displayName
        self.format = format
        self.columns = columns
        self.createdAt = createdAt
        self.modifiedAt = modifiedAt ?? createdAt
    }
}

nonisolated struct DeploymentImportMappingColumn: Codable, Equatable, Sendable {
    var sourceHeader: String
    var fieldKey: String
    var required: Bool
    var defaultValue: String?

    init(sourceHeader: String, fieldKey: String, required: Bool, defaultValue: String? = nil) {
        self.sourceHeader = sourceHeader
        self.fieldKey = fieldKey
        self.required = required
        self.defaultValue = defaultValue
    }
}

nonisolated struct DeploymentVendorImportRow: Identifiable, Codable, Equatable, Sendable {
    let id: String
    let rowNumber: Int
    let valuesByFieldKey: [String: String]

    init(id: String = UUID().uuidString, rowNumber: Int, valuesByFieldKey: [String: String]) {
        self.id = id
        self.rowNumber = rowNumber
        self.valuesByFieldKey = valuesByFieldKey
    }
}

nonisolated struct DeploymentVendorImportIssue: Identifiable, Codable, Equatable, Sendable {
    let id: String
    let rowNumber: Int?
    let fieldKey: String?
    let message: String

    init(id: String = UUID().uuidString, rowNumber: Int? = nil, fieldKey: String? = nil, message: String) {
        self.id = id
        self.rowNumber = rowNumber
        self.fieldKey = fieldKey
        self.message = message
    }
}

nonisolated struct DeploymentVendorImportPreview: Codable, Equatable, Sendable {
    let mappingId: String
    let rows: [DeploymentVendorImportRow]
    let issues: [DeploymentVendorImportIssue]
}
