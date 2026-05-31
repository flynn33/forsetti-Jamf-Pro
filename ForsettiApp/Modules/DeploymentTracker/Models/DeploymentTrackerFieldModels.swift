import Foundation

// MARK: - Field Catalog models
//
// Field models define where each value comes from, how it should be displayed,
// whether it can be edited locally, and how it participates in Workbench layouts,
// imports, exports, validation, grouping, and auditing.
nonisolated enum DeploymentFieldSourceOfTruth: String, Codable, CaseIterable, Sendable {
    case deploymentTracker = "DeploymentTracker"
    case abm = "ABM"
    case jamfPro = "JamfPro"
    case sdPlusExport = "SDPlusExport"
    case appleCatalog = "AppleCatalog"
    case vendorImport = "VendorImport"
    case derived = "Derived"
    case audit = "Audit"
    case system = "System"
}

nonisolated enum DeploymentFieldValueType: String, Codable, CaseIterable, Sendable {
    case text
    case multilineText
    case serialNumber
    case reference
    case boolean
    case integer
    case date
    case dateTime
    case externalState
    case externalSnapshot
    case trackingNumber
}

nonisolated struct DeploymentFieldDefinition: Identifiable, Codable, Equatable, Sendable {
    var id: String { fieldKey }
    let fieldKey: String
    var displayName: String
    var description: String?
    var category: String
    var entityType: String
    var sourceOfTruth: DeploymentFieldSourceOfTruth
    var fieldType: DeploymentFieldValueType
    var editable: Bool
    var required: Bool
    var sortable: Bool
    var filterable: Bool
    var groupable: Bool
    var exportable: Bool
    var reportable: Bool
    var visibleByDefault: Bool
    var defaultWidth: Double
    var rendererType: String
    var editorType: String
    var validationRules: [String]
    var referenceCategoryId: String?
    var systemBehaviorTag: String?
    var lifecycleState: DeploymentRecordLifecycleState
}

nonisolated struct WorkbenchLayout: Identifiable, Codable, Equatable, Sendable {
    let id: String
    var displayName: String
    var ownerScope: String
    var isDefault: Bool
    var isSystem: Bool
    var columns: [WorkbenchLayoutColumn]
    var notes: String?
}

nonisolated struct WorkbenchLayoutColumn: Identifiable, Codable, Equatable, Sendable {
    var id: String { fieldKey }
    let fieldKey: String
    var visible: Bool
    var order: Int
    var width: Double
    var pinned: Bool
}

nonisolated struct DeploymentAppleHardwareCatalogEntry: Identifiable, Codable, Equatable, Sendable {
    let id: String
    var sourceName: String
    var sourceType: String
    var sourceFileName: String?
    var sourceFileHash: String?
    var importedAt: Date?
    var importedBy: String?
    var applePartNumber: String?
    var appleModelNumber: String?
    var orderPartNumber: String?
    var vendorSku: String?
    var modelIdentifier: String?
    var marketingName: String?
    var deviceFamily: String?
    var deviceType: String?
    var chipFamily: String?
    var chipName: String?
    var cpuCoreCount: Int?
    var gpuCoreCount: Int?
    var neuralCoreCount: Int?
    var storage: String?
    var memory: String?
    var color: String?
    var cellularCapability: Bool?
    var wifiCapability: Bool?
    var releaseYear: Int?
    var supportedOSRange: String?
    var lifecycleState: DeploymentRecordLifecycleState
    var confidenceScore: Double
    var notes: String?

    init(
        id: String = UUID().uuidString,
        sourceName: String,
        sourceType: String,
        sourceFileName: String? = nil,
        sourceFileHash: String? = nil,
        importedAt: Date? = nil,
        importedBy: String? = nil,
        applePartNumber: String? = nil,
        appleModelNumber: String? = nil,
        orderPartNumber: String? = nil,
        vendorSku: String? = nil,
        modelIdentifier: String? = nil,
        marketingName: String? = nil,
        deviceFamily: String? = nil,
        deviceType: String? = nil,
        chipFamily: String? = nil,
        chipName: String? = nil,
        cpuCoreCount: Int? = nil,
        gpuCoreCount: Int? = nil,
        neuralCoreCount: Int? = nil,
        storage: String? = nil,
        memory: String? = nil,
        color: String? = nil,
        cellularCapability: Bool? = nil,
        wifiCapability: Bool? = nil,
        releaseYear: Int? = nil,
        supportedOSRange: String? = nil,
        lifecycleState: DeploymentRecordLifecycleState = .active,
        confidenceScore: Double = 1,
        notes: String? = nil
    ) {
        self.id = id
        self.sourceName = sourceName
        self.sourceType = sourceType
        self.sourceFileName = sourceFileName
        self.sourceFileHash = sourceFileHash
        self.importedAt = importedAt
        self.importedBy = importedBy
        self.applePartNumber = applePartNumber
        self.appleModelNumber = appleModelNumber
        self.orderPartNumber = orderPartNumber
        self.vendorSku = vendorSku
        self.modelIdentifier = modelIdentifier
        self.marketingName = marketingName
        self.deviceFamily = deviceFamily
        self.deviceType = deviceType
        self.chipFamily = chipFamily
        self.chipName = chipName
        self.cpuCoreCount = cpuCoreCount
        self.gpuCoreCount = gpuCoreCount
        self.neuralCoreCount = neuralCoreCount
        self.storage = storage
        self.memory = memory
        self.color = color
        self.cellularCapability = cellularCapability
        self.wifiCapability = wifiCapability
        self.releaseYear = releaseYear
        self.supportedOSRange = supportedOSRange
        self.lifecycleState = lifecycleState
        self.confidenceScore = confidenceScore
        self.notes = notes
    }
}

nonisolated enum DeploymentAppleCatalogMatchState: String, Codable, CaseIterable, Sendable {
    case exact
    case highConfidence
    case partial
    case ambiguous
    case conflict
    case noMatch
}

nonisolated struct DeploymentAppleCatalogResolution: Identifiable, Codable, Equatable, Sendable {
    let id: String
    let deviceId: String
    let matchState: DeploymentAppleCatalogMatchState
    let matchedEntry: DeploymentAppleHardwareCatalogEntry?
    let confidenceScore: Double
    let matchedFields: [String]
    let conflictMessages: [String]

    init(
        id: String = UUID().uuidString,
        deviceId: String,
        matchState: DeploymentAppleCatalogMatchState,
        matchedEntry: DeploymentAppleHardwareCatalogEntry? = nil,
        confidenceScore: Double,
        matchedFields: [String] = [],
        conflictMessages: [String] = []
    ) {
        self.id = id
        self.deviceId = deviceId
        self.matchState = matchState
        self.matchedEntry = matchedEntry
        self.confidenceScore = confidenceScore
        self.matchedFields = matchedFields
        self.conflictMessages = conflictMessages
    }
}
