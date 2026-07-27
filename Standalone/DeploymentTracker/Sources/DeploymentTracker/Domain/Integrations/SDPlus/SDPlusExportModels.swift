import Foundation

// MARK: - SD+ export models
//
// These models describe ServiceDesk Plus export templates, validation issues,
// rendered CSV output, and recorded export jobs. SD+ output is generated locally
// and does not mutate an external SD+ system from this module.
nonisolated enum SDPlusExportValidationSeverity: String, Codable, Sendable {
    case warning
    case blocking
}

nonisolated struct SDPlusExportValidationIssue: Identifiable, Codable, Equatable, Sendable {
    let id: String
    let severity: SDPlusExportValidationSeverity
    let deviceId: String?
    let fieldKey: String?
    let columnHeader: String?
    let message: String

    init(
        id: String = UUID().uuidString,
        severity: SDPlusExportValidationSeverity,
        deviceId: String? = nil,
        fieldKey: String? = nil,
        columnHeader: String? = nil,
        message: String
    ) {
        self.id = id
        self.severity = severity
        self.deviceId = deviceId
        self.fieldKey = fieldKey
        self.columnHeader = columnHeader
        self.message = message
    }
}

nonisolated struct SDPlusExportValidationResult: Codable, Equatable, Sendable {
    let issues: [SDPlusExportValidationIssue]

    var blockingIssues: [SDPlusExportValidationIssue] {
        issues.filter { $0.severity == .blocking }
    }

    var warningIssues: [SDPlusExportValidationIssue] {
        issues.filter { $0.severity == .warning }
    }

    var isValid: Bool {
        blockingIssues.isEmpty
    }
}

nonisolated struct SDPlusRenderedExport: Codable, Equatable, Sendable {
    let templateId: String
    let csv: String
    let validation: SDPlusExportValidationResult
    let includedDeviceIds: [String]
    let failedDeviceIds: [String]
}

nonisolated struct SDPlusExportResult: Codable, Equatable, Sendable {
    let renderedExport: SDPlusRenderedExport
    let job: SDPlusExportJob
}
