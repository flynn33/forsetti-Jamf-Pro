import Foundation

// MARK: - Jamf Inventory Preload models
//
// These models describe the Jamf Inventory Preload workflow from Tracker's
// perspective: endpoint paths, required privileges, templates, rendered payloads,
// submission history, lookup records, snapshots, and validation results.
nonisolated enum JamfInventoryPreloadEndpoint {
    nonisolated static let records = "api/v2/inventory-preload/records"
    nonisolated static let csvUpload = "api/v2/inventory-preload/csv"
    nonisolated static let csvTemplate = "api/v2/inventory-preload/csv-template"
    nonisolated static let csvValidate = "api/v2/inventory-preload/csv-validate"
}

// Privilege names are surfaced directly in structured errors so a Jamf Pro
// administrator can update the API Client role without guessing which access is
// missing.
nonisolated enum JamfInventoryPreloadPrivilege {
    nonisolated static let lookup = ["Read Inventory Preload Records"]
    nonisolated static let upload = [
        "Create Inventory Preload Records",
        "Update Inventory Preload Records",
        "Create User",
        "Update User"
    ]
}

nonisolated struct JamfInventoryPreloadTemplate: Identifiable, Codable, Equatable, Sendable {
    let id: String
    var displayName: String
    var targetSystem: String
    var transport: String
    var endpoint: String
    var requiredPrivileges: [String]
    var columns: [JamfInventoryPreloadColumn]

    init(
        id: String,
        displayName: String,
        targetSystem: String = "Jamf Pro",
        transport: String = "internal-csv-upload",
        endpoint: String = JamfInventoryPreloadEndpoint.csvUpload,
        requiredPrivileges: [String] = JamfInventoryPreloadPrivilege.upload,
        columns: [JamfInventoryPreloadColumn]
    ) {
        self.id = id
        self.displayName = displayName
        self.targetSystem = targetSystem
        self.transport = transport
        self.endpoint = endpoint
        self.requiredPrivileges = requiredPrivileges
        self.columns = columns
    }
}

nonisolated struct JamfInventoryPreloadColumn: Identifiable, Codable, Equatable, Sendable {
    var id: String { jamfColumn }
    let jamfColumn: String
    let sourceField: String
    let required: Bool
}

nonisolated struct JamfInventoryPreloadValidationIssue: Identifiable, Codable, Equatable, Sendable {
    let id: String
    let deviceId: String?
    let serialNumber: String?
    let fieldKey: String?
    let severity: DeploymentExceptionSeverity
    let message: String

    init(
        id: String = UUID().uuidString,
        deviceId: String? = nil,
        serialNumber: String? = nil,
        fieldKey: String? = nil,
        severity: DeploymentExceptionSeverity,
        message: String
    ) {
        self.id = id
        self.deviceId = deviceId
        self.serialNumber = serialNumber
        self.fieldKey = fieldKey
        self.severity = severity
        self.message = message
    }
}

nonisolated struct JamfInventoryPreloadValidationResult: Codable, Equatable, Sendable {
    let deviceCount: Int
    let readyDeviceIds: [String]
    let issues: [JamfInventoryPreloadValidationIssue]
    let requiredPrivileges: [String]

    var blockedIssues: [JamfInventoryPreloadValidationIssue] {
        issues.filter { [.blocking, .critical].contains($0.severity) }
    }

    var warningIssues: [JamfInventoryPreloadValidationIssue] {
        issues.filter { $0.severity == .warning }
    }

    var isReadyForUpload: Bool {
        blockedIssues.isEmpty
    }
}

nonisolated struct JamfInventoryPreloadRecord: Identifiable, Codable, Equatable, Sendable {
    let id: String
    var serialNumber: String
    var deviceType: String?
    var username: String?
    var emailAddress: String?
    var building: String?
    var room: String?
    var assetTag: String?
    var department: String?
    var poNumber: String?

    init(
        id: String = UUID().uuidString,
        serialNumber: String,
        deviceType: String? = nil,
        username: String? = nil,
        emailAddress: String? = nil,
        building: String? = nil,
        room: String? = nil,
        assetTag: String? = nil,
        department: String? = nil,
        poNumber: String? = nil
    ) {
        self.id = id
        self.serialNumber = serialNumber
        self.deviceType = deviceType
        self.username = username
        self.emailAddress = emailAddress
        self.building = building
        self.room = room
        self.assetTag = assetTag
        self.department = department
        self.poNumber = poNumber
    }

    enum CodingKeys: String, CodingKey {
        case id
        case serialNumber
        case serial_number
        case deviceType
        case device_type
        case username
        case emailAddress
        case email_address
        case building
        case room
        case assetTag
        case asset_tag
        case department
        case poNumber
        case po_number
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let decodedID = try Self.decodeFlexibleString(for: .id, from: container) ?? UUID().uuidString
        self.id = decodedID
        self.serialNumber = try Self.decodeFlexibleString(for: .serialNumber, from: container)
            ?? Self.decodeFlexibleString(for: .serial_number, from: container)
            ?? ""
        self.deviceType = try Self.decodeFlexibleString(for: .deviceType, from: container)
            ?? Self.decodeFlexibleString(for: .device_type, from: container)
        self.username = try Self.decodeFlexibleString(for: .username, from: container)
        self.emailAddress = try Self.decodeFlexibleString(for: .emailAddress, from: container)
            ?? Self.decodeFlexibleString(for: .email_address, from: container)
        self.building = try Self.decodeFlexibleString(for: .building, from: container)
        self.room = try Self.decodeFlexibleString(for: .room, from: container)
        self.assetTag = try Self.decodeFlexibleString(for: .assetTag, from: container)
            ?? Self.decodeFlexibleString(for: .asset_tag, from: container)
        self.department = try Self.decodeFlexibleString(for: .department, from: container)
        self.poNumber = try Self.decodeFlexibleString(for: .poNumber, from: container)
            ?? Self.decodeFlexibleString(for: .po_number, from: container)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(serialNumber, forKey: .serialNumber)
        try container.encodeIfPresent(deviceType, forKey: .deviceType)
        try container.encodeIfPresent(username, forKey: .username)
        try container.encodeIfPresent(emailAddress, forKey: .emailAddress)
        try container.encodeIfPresent(building, forKey: .building)
        try container.encodeIfPresent(room, forKey: .room)
        try container.encodeIfPresent(assetTag, forKey: .assetTag)
        try container.encodeIfPresent(department, forKey: .department)
        try container.encodeIfPresent(poNumber, forKey: .poNumber)
    }

    nonisolated private static func decodeFlexibleString(
        for key: CodingKeys,
        from container: KeyedDecodingContainer<CodingKeys>
    ) throws -> String? {
        if let value = try container.decodeIfPresent(String.self, forKey: key) {
            return value
        }
        if let value = try container.decodeIfPresent(Int.self, forKey: key) {
            return String(value)
        }
        return nil
    }
}

nonisolated struct JamfInventoryPreloadSupersedenceDiff: Identifiable, Codable, Equatable, Sendable {
    var id: String { "\(serialNumber)-\(jamfColumn)" }
    let serialNumber: String
    let jamfColumn: String
    let oldValue: String
    let newValue: String
}

nonisolated struct JamfInventoryPreloadSupersedencePreview: Codable, Equatable, Sendable {
    let selectedDeviceCount: Int
    let changedRecordCount: Int
    let unchangedRecordCount: Int
    let blockedRecordCount: Int
    let warnings: [String]
    let diffs: [JamfInventoryPreloadSupersedenceDiff]
}

nonisolated struct DeploymentUserFacingIntegrationError: Identifiable, Codable, Equatable, Sendable {
    let id: String
    let title: String
    let summary: String
    let technicalCause: String
    let affectedSystem: String
    let requiredJamfPrivileges: [String]
    let localDataChanged: Bool
    let externalDataChanged: Bool
    let safeToRetry: Bool
    let recommendedAction: String
    let diagnosticsCategory: String
    let diagnosticsCorrelationId: String?
    let relatedGuideTopicId: String?

    init(
        id: String = UUID().uuidString,
        title: String,
        summary: String,
        technicalCause: String,
        affectedSystem: String = "Jamf Pro",
        requiredJamfPrivileges: [String],
        localDataChanged: Bool,
        externalDataChanged: Bool,
        safeToRetry: Bool,
        recommendedAction: String,
        diagnosticsCategory: String,
        diagnosticsCorrelationId: String? = nil,
        relatedGuideTopicId: String? = nil
    ) {
        self.id = id
        self.title = title
        self.summary = summary
        self.technicalCause = technicalCause
        self.affectedSystem = affectedSystem
        self.requiredJamfPrivileges = requiredJamfPrivileges
        self.localDataChanged = localDataChanged
        self.externalDataChanged = externalDataChanged
        self.safeToRetry = safeToRetry
        self.recommendedAction = recommendedAction
        self.diagnosticsCategory = diagnosticsCategory
        self.diagnosticsCorrelationId = diagnosticsCorrelationId
        self.relatedGuideTopicId = relatedGuideTopicId
    }

    nonisolated var diagnosticsMetadata: [String: String] {
        var metadata = [
            "summary": summary,
            "technical_cause": technicalCause,
            "affected_system": affectedSystem,
            "local_data_changed": String(localDataChanged),
            "external_data_changed": String(externalDataChanged),
            "safe_to_retry": String(safeToRetry),
            "recommended_action": recommendedAction
        ]
        if !requiredJamfPrivileges.isEmpty {
            metadata["required_jamf_privileges"] = requiredJamfPrivileges.joined(separator: ", ")
        }
        if let diagnosticsCorrelationId {
            metadata["diagnostics_correlation_id"] = diagnosticsCorrelationId
        }
        if let relatedGuideTopicId {
            metadata["related_guide_topic_id"] = relatedGuideTopicId
        }
        return metadata
    }
}
