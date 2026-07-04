import Foundation

// MARK: - Core tracker domain models
//
// These enums and structs describe the local Deployment Tracker domain. External
// systems such as Jamf Pro and Apple Business Manager are represented as
// snapshots so local workflow state remains separate from upstream source data.
nonisolated enum DeploymentRecordLifecycleState: String, Codable, CaseIterable, Sendable {
    case active
    case deprecated
    case archived
    case pendingDeletion
    case deleted
}

nonisolated enum DeploymentIntegrationState: String, Codable, CaseIterable, Sendable {
    case unknown
    case pending
    case ready
    case submitted
    case failed
    case reconciled
    case exported
    case complete
}

nonisolated enum DeploymentABMVerificationState: String, Codable, CaseIterable, Sendable {
    case unknown
    case lookupPending
    case found
    case notFound
    case assignedToExpectedMDM
    case assignedToDifferentMDM
    case unassigned
    case releasedOrUnavailable
    case snapshotConflict
    case lookupFailed
    case staleSnapshot
}

nonisolated enum DeploymentExceptionSeverity: String, Codable, CaseIterable, Sendable {
    case info
    case warning
    case blocking
    case critical
}

nonisolated enum DeploymentExceptionStatus: String, Codable, CaseIterable, Sendable {
    case open
    case acknowledged
    case resolved
    case waived
    case superseded
}

nonisolated enum DeploymentExternalSystem: String, Codable, CaseIterable, Sendable {
    case deploymentTracker
    case appleBusiness
    case jamfPro
    case sdPlus
    case vendorImport
    case appleCatalog
}

nonisolated struct DeploymentDevice: Identifiable, Codable, Equatable, Sendable {
    let id: String
    private(set) var serialNumber: String
    private(set) var normalizedSerialNumber: String
    var assetTag: String?
    var deviceTypeId: String?
    var model: String?
    var modelIdentifier: String?
    var applePartNumber: String?
    var vendorSku: String?
    var vendorName: String?
    var poNumber: String?
    var orderNumber: String?
    var receivedDate: Date?
    var replacementForSerialNumber: String?
    var projectId: String?
    var ticketNumber: String?
    var assignedUser: String?
    var assignedUserEmail: String?
    var department: String?
    var businessUnit: String?
    var geoId: String?
    var locationId: String?
    var profileId: String?
    var workflowStatusId: String?
    var workflowStatusReason: String?
    var blockingReason: String?
    var abmVerificationState: DeploymentABMVerificationState
    var latestABMSnapshotId: String?
    var jamfPreloadState: DeploymentIntegrationState
    var latestPreloadSubmissionId: String?
    var jamfEnrollmentState: DeploymentIntegrationState
    var jamfReconciliationState: DeploymentIntegrationState
    var jamfComputerId: String?
    var jamfMobileDeviceId: String?
    var sdPlusExportState: DeploymentIntegrationState
    var sdPlusExportTemplateId: String?
    var sdPlusLastExportedAt: Date?
    var sdPlusExportVersion: Int
    var shippingState: DeploymentIntegrationState
    var fedExTrackingNumber: String?
    var returnTrackingNumber: String?
    var deliveryConfirmation: String?
    var gmEmailed: Bool
    var comments: String?
    var notes: String?
    var internalNotes: String?
    let createdAt: Date
    var createdBy: String?
    private(set) var modifiedAt: Date
    var modifiedBy: String?
    private(set) var recordLifecycleState: DeploymentRecordLifecycleState
    private(set) var recordVersion: Int

    init(
        id: String = UUID().uuidString,
        serialNumber: String,
        assetTag: String? = nil,
        deviceTypeId: String? = nil,
        model: String? = nil,
        projectId: String? = nil,
        workflowStatusId: String? = nil,
        recordLifecycleState: DeploymentRecordLifecycleState = .active,
        createdAt: Date = Date(),
        createdBy: String? = nil
    ) {
        self.id = id
        self.serialNumber = serialNumber.trimmingCharacters(in: .whitespacesAndNewlines)
        self.normalizedSerialNumber = Self.normalizeSerial(serialNumber)
        self.assetTag = assetTag
        self.deviceTypeId = deviceTypeId
        self.model = model
        self.modelIdentifier = nil
        self.applePartNumber = nil
        self.vendorSku = nil
        self.vendorName = nil
        self.poNumber = nil
        self.orderNumber = nil
        self.receivedDate = nil
        self.replacementForSerialNumber = nil
        self.projectId = projectId
        self.ticketNumber = nil
        self.assignedUser = nil
        self.assignedUserEmail = nil
        self.department = nil
        self.businessUnit = nil
        self.geoId = nil
        self.locationId = nil
        self.profileId = nil
        self.workflowStatusId = workflowStatusId
        self.workflowStatusReason = nil
        self.blockingReason = nil
        self.abmVerificationState = .unknown
        self.latestABMSnapshotId = nil
        self.jamfPreloadState = .unknown
        self.latestPreloadSubmissionId = nil
        self.jamfEnrollmentState = .unknown
        self.jamfReconciliationState = .unknown
        self.jamfComputerId = nil
        self.jamfMobileDeviceId = nil
        self.sdPlusExportState = .unknown
        self.sdPlusExportTemplateId = nil
        self.sdPlusLastExportedAt = nil
        self.sdPlusExportVersion = 0
        self.shippingState = .unknown
        self.fedExTrackingNumber = nil
        self.returnTrackingNumber = nil
        self.deliveryConfirmation = nil
        self.gmEmailed = false
        self.comments = nil
        self.notes = nil
        self.internalNotes = nil
        self.createdAt = createdAt
        self.createdBy = createdBy
        self.modifiedAt = createdAt
        self.modifiedBy = createdBy
        self.recordLifecycleState = recordLifecycleState
        self.recordVersion = 1
    }

    nonisolated static func normalizeSerial(_ serialNumber: String) -> String {
        serialNumber.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
    }

    mutating func updateSerialNumber(_ serialNumber: String, modifiedAt: Date = Date(), modifiedBy: String? = nil) {
        self.serialNumber = serialNumber.trimmingCharacters(in: .whitespacesAndNewlines)
        self.normalizedSerialNumber = Self.normalizeSerial(serialNumber)
        touch(modifiedAt: modifiedAt, modifiedBy: modifiedBy)
    }

    func withLifecycleState(
        _ state: DeploymentRecordLifecycleState,
        modifiedAt: Date = Date(),
        modifiedBy: String? = nil
    ) -> DeploymentDevice {
        var copy = self
        copy.recordLifecycleState = state
        copy.touch(modifiedAt: modifiedAt, modifiedBy: modifiedBy)
        return copy
    }

    func withWorkflowStatus(
        _ statusId: String,
        modifiedAt: Date = Date(),
        modifiedBy: String? = nil
    ) -> DeploymentDevice {
        var copy = self
        copy.workflowStatusId = statusId
        copy.touch(modifiedAt: modifiedAt, modifiedBy: modifiedBy)
        return copy
    }

    private mutating func touch(modifiedAt: Date, modifiedBy: String?) {
        self.modifiedAt = modifiedAt
        self.modifiedBy = modifiedBy
        recordVersion += 1
    }
}

nonisolated struct DeploymentProject: Identifiable, Codable, Equatable, Sendable {
    let id: String
    var projectName: String
    var projectCode: String?
    var ticketNumber: String?
    var businessUnit: String?
    var customerOrDepartment: String?
    var projectOwner: String?
    var projectStatus: String?
    var defaultGeoId: String?
    var defaultLocationId: String?
    var defaultProfileId: String?
    var requiresABMVerification: Bool
    var requiresExpectedABMMDMService: Bool
    var allowsABMVerificationWaiver: Bool
    var requiresQA: Bool
    var allowsQAWaiver: Bool
    var requiresJamfInventoryPreload: Bool
    var requiresJamfPreloadReconciliation: Bool
    var allowsJamfPreloadOverwrite: Bool
    var requiresSDPlusExport: Bool
    var requiresShipping: Bool
    var requiresDeliveryConfirmation: Bool
    var allowsCompletionWithWarnings: Bool
    var requiresCompletionReview: Bool
    var notes: String?
    let createdAt: Date
    private(set) var modifiedAt: Date
    private(set) var recordLifecycleState: DeploymentRecordLifecycleState

    init(
        id: String = UUID().uuidString,
        projectName: String,
        projectCode: String? = nil,
        ticketNumber: String? = nil,
        createdAt: Date = Date(),
        recordLifecycleState: DeploymentRecordLifecycleState = .active
    ) {
        self.id = id
        self.projectName = projectName
        self.projectCode = projectCode
        self.ticketNumber = ticketNumber
        self.businessUnit = nil
        self.customerOrDepartment = nil
        self.projectOwner = nil
        self.projectStatus = nil
        self.defaultGeoId = nil
        self.defaultLocationId = nil
        self.defaultProfileId = nil
        self.requiresABMVerification = false
        self.requiresExpectedABMMDMService = false
        self.allowsABMVerificationWaiver = false
        self.requiresQA = false
        self.allowsQAWaiver = false
        self.requiresJamfInventoryPreload = true
        self.requiresJamfPreloadReconciliation = false
        self.allowsJamfPreloadOverwrite = false
        self.requiresSDPlusExport = false
        self.requiresShipping = false
        self.requiresDeliveryConfirmation = false
        self.allowsCompletionWithWarnings = false
        self.requiresCompletionReview = false
        self.notes = nil
        self.createdAt = createdAt
        self.modifiedAt = createdAt
        self.recordLifecycleState = recordLifecycleState
    }

    func withLifecycleState(
        _ state: DeploymentRecordLifecycleState,
        modifiedAt: Date = Date()
    ) -> DeploymentProject {
        var copy = self
        copy.recordLifecycleState = state
        copy.modifiedAt = modifiedAt
        return copy
    }
}

nonisolated struct DeploymentBatch: Identifiable, Codable, Equatable, Sendable {
    let id: String
    var displayName: String
    var sourceDescription: String?
    var createdAt: Date
    var deviceIds: [String]

    init(id: String = UUID().uuidString, displayName: String, sourceDescription: String? = nil, createdAt: Date = Date(), deviceIds: [String] = []) {
        self.id = id
        self.displayName = displayName
        self.sourceDescription = sourceDescription
        self.createdAt = createdAt
        self.deviceIds = deviceIds
    }
}

nonisolated struct DeploymentReferenceValue: Identifiable, Codable, Equatable, Sendable {
    let id: String
    let categoryId: String
    var displayName: String
    var sortOrder: Int
    var metadata: [String: String]
    var lifecycleState: DeploymentRecordLifecycleState

    init(
        id: String,
        categoryId: String,
        displayName: String,
        sortOrder: Int = 0,
        metadata: [String: String] = [:],
        lifecycleState: DeploymentRecordLifecycleState = .active
    ) {
        self.id = id
        self.categoryId = categoryId
        self.displayName = displayName
        self.sortOrder = sortOrder
        self.metadata = metadata
        self.lifecycleState = lifecycleState
    }
}

nonisolated struct DeploymentWorkflowStatusDefinition: Identifiable, Codable, Equatable, Sendable {
    let id: String
    var displayName: String
    var description: String?
    let systemBehaviorTag: String
    var statusCategory: String
    var lifecycleState: DeploymentRecordLifecycleState
    var isDefault: Bool
    var isTerminal: Bool
    var isExceptionState: Bool
    var isBlockingState: Bool
    var requiresReason: Bool
    var colorToken: String?
    var iconToken: String?
    var sortOrder: Int
    let createdAt: Date
    var createdBy: String?
    var modifiedAt: Date
    var modifiedBy: String?

    init(
        id: String,
        displayName: String,
        description: String? = nil,
        systemBehaviorTag: String,
        statusCategory: String,
        lifecycleState: DeploymentRecordLifecycleState = .active,
        isDefault: Bool = false,
        isTerminal: Bool = false,
        isExceptionState: Bool = false,
        isBlockingState: Bool = false,
        requiresReason: Bool = false,
        colorToken: String? = nil,
        iconToken: String? = nil,
        sortOrder: Int = 0,
        createdAt: Date = Date(),
        createdBy: String? = nil,
        modifiedAt: Date? = nil,
        modifiedBy: String? = nil
    ) {
        self.id = id
        self.displayName = displayName
        self.description = description
        self.systemBehaviorTag = systemBehaviorTag
        self.statusCategory = statusCategory
        self.lifecycleState = lifecycleState
        self.isDefault = isDefault
        self.isTerminal = isTerminal
        self.isExceptionState = isExceptionState
        self.isBlockingState = isBlockingState
        self.requiresReason = requiresReason
        self.colorToken = colorToken
        self.iconToken = iconToken
        self.sortOrder = sortOrder
        self.createdAt = createdAt
        self.createdBy = createdBy
        self.modifiedAt = modifiedAt ?? createdAt
        self.modifiedBy = modifiedBy
    }
}

nonisolated struct DeploymentWorkflowTransitionDefinition: Identifiable, Codable, Equatable, Sendable {
    var id: String { "\(fromStatusId)->\(toStatusId)" }
    let fromStatusId: String
    let toStatusId: String
    let gateType: DeploymentGateType?
    let requiresReason: Bool

    init(
        fromStatusId: String,
        toStatusId: String,
        gateType: DeploymentGateType? = nil,
        requiresReason: Bool = false
    ) {
        self.fromStatusId = fromStatusId
        self.toStatusId = toStatusId
        self.gateType = gateType
        self.requiresReason = requiresReason
    }
}

nonisolated enum DeploymentGateType: String, Codable, CaseIterable, Sendable {
    case catalogGate
    case abmVerificationReadinessGate
    case abmVerificationGate
    case projectAssignmentGate
    case configurationGate
    case qaGate
    case jamfPreloadReadinessGate
    case jamfPreloadSubmissionGate
    case jamfPreloadReconciliationGate
    case sdPlusExportGate
    case shippingGate
    case deliveryGate
    case completionGate
    case recordsManagementGate
}

nonisolated enum DeploymentGateValidationStatus: String, Codable, CaseIterable, Sendable {
    case pass
    case warning
    case blocked
    case failed
    case notApplicable

    var allowsForwardMovement: Bool {
        switch self {
        case .pass, .warning, .notApplicable:
            return true
        case .blocked, .failed:
            return false
        }
    }
}

nonisolated struct DeploymentGateValidationIssue: Identifiable, Codable, Equatable, Sendable {
    let id: String
    let severity: DeploymentExceptionSeverity
    let message: String
    let fieldKey: String?

    init(
        id: String = UUID().uuidString,
        severity: DeploymentExceptionSeverity,
        message: String,
        fieldKey: String? = nil
    ) {
        self.id = id
        self.severity = severity
        self.message = message
        self.fieldKey = fieldKey
    }
}

nonisolated struct DeploymentGateValidationResult: Codable, Equatable, Sendable {
    let gateType: DeploymentGateType
    let status: DeploymentGateValidationStatus
    let issues: [DeploymentGateValidationIssue]

    var allowsForwardMovement: Bool {
        status.allowsForwardMovement
    }
}

nonisolated struct DeploymentWorkflowTransitionResult: Codable, Equatable, Sendable {
    let allowed: Bool
    let fromStatusId: String?
    let toStatusId: String
    let gateResult: DeploymentGateValidationResult?
    let issues: [DeploymentGateValidationIssue]
}

nonisolated struct DeploymentWaiver: Identifiable, Codable, Equatable, Sendable {
    let id: String
    let reason: String
    let approvedBy: String
    let approvedAt: Date
    let scope: String
    let auditEventId: String

    init(
        id: String = UUID().uuidString,
        reason: String,
        approvedBy: String,
        approvedAt: Date = Date(),
        scope: String,
        auditEventId: String
    ) {
        self.id = id
        self.reason = reason
        self.approvedBy = approvedBy
        self.approvedAt = approvedAt
        self.scope = scope
        self.auditEventId = auditEventId
    }
}

nonisolated struct DeploymentAuditEvent: Identifiable, Codable, Equatable, Sendable {
    let id: String
    let occurredAt: Date
    let eventType: String
    let entityType: String
    let entityId: String
    let fieldKey: String?
    let oldValue: String?
    let newValue: String?
    let actor: String?
    let metadata: [String: String]

    init(
        id: String = UUID().uuidString,
        occurredAt: Date = Date(),
        eventType: String,
        entityType: String,
        entityId: String,
        fieldKey: String? = nil,
        oldValue: String? = nil,
        newValue: String? = nil,
        actor: String? = nil,
        metadata: [String: String] = [:]
    ) {
        self.id = id
        self.occurredAt = occurredAt
        self.eventType = eventType
        self.entityType = entityType
        self.entityId = entityId
        self.fieldKey = fieldKey
        self.oldValue = oldValue
        self.newValue = newValue
        self.actor = actor
        self.metadata = metadata
    }
}

nonisolated struct DeploymentWorkflowEvent: Identifiable, Codable, Equatable, Sendable {
    let id: String
    let deviceId: String
    let fromStatusId: String?
    let toStatusId: String
    let transitionedAt: Date
    let transitionedBy: String?
    let gateResult: String?
    let reason: String?

    init(
        id: String = UUID().uuidString,
        deviceId: String,
        fromStatusId: String?,
        toStatusId: String,
        transitionedAt: Date = Date(),
        transitionedBy: String? = nil,
        gateResult: String? = nil,
        reason: String? = nil
    ) {
        self.id = id
        self.deviceId = deviceId
        self.fromStatusId = fromStatusId
        self.toStatusId = toStatusId
        self.transitionedAt = transitionedAt
        self.transitionedBy = transitionedBy
        self.gateResult = gateResult
        self.reason = reason
    }
}

nonisolated struct DeploymentException: Identifiable, Codable, Equatable, Sendable {
    let id: String
    let deviceId: String?
    let projectId: String?
    var reasonCode: String
    var summary: String
    var severity: DeploymentExceptionSeverity
    var status: DeploymentExceptionStatus
    let createdAt: Date
    var resolvedAt: Date?

    init(
        id: String = UUID().uuidString,
        deviceId: String? = nil,
        projectId: String? = nil,
        reasonCode: String,
        summary: String,
        severity: DeploymentExceptionSeverity,
        status: DeploymentExceptionStatus = .open,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.deviceId = deviceId
        self.projectId = projectId
        self.reasonCode = reasonCode
        self.summary = summary
        self.severity = severity
        self.status = status
        self.createdAt = createdAt
        self.resolvedAt = nil
    }
}

nonisolated struct AppleBusinessDeviceSnapshot: Identifiable, Codable, Equatable, Sendable {
    let id: String
    let deploymentDeviceId: String
    let serialNumber: String
    let capturedAt: Date
    let capturedBy: String?
    let lookupStatus: DeploymentABMVerificationState
    let abmModel: String?
    let abmSerialNumber: String?
    let abmPartNumber: String?
    let abmOrderNumber: String?
    let abmOrderSource: String?
    let abmStorageSize: String?
    let abmDeviceSource: String?
    let abmDateAdded: Date?
    let abmReleasedState: String?
    let abmReleasedDate: Date?
    let abmAssignedManagementServiceId: String?
    let abmAssignedManagementServiceName: String?
    let rawRecordHash: String?
    let diagnosticsCorrelationId: String?

    init(
        id: String = UUID().uuidString,
        deploymentDeviceId: String,
        serialNumber: String,
        capturedAt: Date = Date(),
        capturedBy: String? = nil,
        lookupStatus: DeploymentABMVerificationState,
        abmModel: String? = nil,
        abmSerialNumber: String? = nil,
        abmPartNumber: String? = nil,
        abmOrderNumber: String? = nil,
        abmOrderSource: String? = nil,
        abmStorageSize: String? = nil,
        abmDeviceSource: String? = nil,
        abmDateAdded: Date? = nil,
        abmReleasedState: String? = nil,
        abmReleasedDate: Date? = nil,
        abmAssignedManagementServiceId: String? = nil,
        abmAssignedManagementServiceName: String? = nil,
        rawRecordHash: String? = nil,
        diagnosticsCorrelationId: String? = nil
    ) {
        self.id = id
        self.deploymentDeviceId = deploymentDeviceId
        self.serialNumber = serialNumber
        self.capturedAt = capturedAt
        self.capturedBy = capturedBy
        self.lookupStatus = lookupStatus
        self.abmModel = abmModel
        self.abmSerialNumber = abmSerialNumber
        self.abmPartNumber = abmPartNumber
        self.abmOrderNumber = abmOrderNumber
        self.abmOrderSource = abmOrderSource
        self.abmStorageSize = abmStorageSize
        self.abmDeviceSource = abmDeviceSource
        self.abmDateAdded = abmDateAdded
        self.abmReleasedState = abmReleasedState
        self.abmReleasedDate = abmReleasedDate
        self.abmAssignedManagementServiceId = abmAssignedManagementServiceId
        self.abmAssignedManagementServiceName = abmAssignedManagementServiceName
        self.rawRecordHash = rawRecordHash
        self.diagnosticsCorrelationId = diagnosticsCorrelationId
    }
}

nonisolated struct JamfInventoryPreloadSnapshot: Identifiable, Codable, Equatable, Sendable {
    let id: String
    let deploymentDeviceId: String
    let serialNumber: String
    let capturedAt: Date
    let rawRecordHash: String?
    let payloadSummary: [String: String]
}

nonisolated struct JamfInventoryDeviceSnapshot: Identifiable, Codable, Equatable, Sendable {
    let id: String
    let deploymentDeviceId: String
    let serialNumber: String
    let capturedAt: Date
    let jamfComputerId: String?
    let jamfMobileDeviceId: String?
    let inventoryState: DeploymentIntegrationState
    let rawRecordHash: String?
    let payloadSummary: [String: String]

    init(
        id: String = UUID().uuidString,
        deploymentDeviceId: String,
        serialNumber: String,
        capturedAt: Date = Date(),
        jamfComputerId: String? = nil,
        jamfMobileDeviceId: String? = nil,
        inventoryState: DeploymentIntegrationState,
        rawRecordHash: String? = nil,
        payloadSummary: [String: String] = [:]
    ) {
        self.id = id
        self.deploymentDeviceId = deploymentDeviceId
        self.serialNumber = serialNumber
        self.capturedAt = capturedAt
        self.jamfComputerId = jamfComputerId
        self.jamfMobileDeviceId = jamfMobileDeviceId
        self.inventoryState = inventoryState
        self.rawRecordHash = rawRecordHash
        self.payloadSummary = payloadSummary
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case deploymentDeviceId
        case serialNumber
        case capturedAt
        case jamfComputerId
        case jamfMobileDeviceId
        case inventoryState
        case rawRecordHash
        case payloadSummary
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        deploymentDeviceId = try container.decode(String.self, forKey: .deploymentDeviceId)
        serialNumber = try container.decode(String.self, forKey: .serialNumber)
        capturedAt = try container.decode(Date.self, forKey: .capturedAt)
        jamfComputerId = try container.decodeIfPresent(String.self, forKey: .jamfComputerId)
        jamfMobileDeviceId = try container.decodeIfPresent(String.self, forKey: .jamfMobileDeviceId)
        inventoryState = try container.decode(DeploymentIntegrationState.self, forKey: .inventoryState)
        rawRecordHash = try container.decodeIfPresent(String.self, forKey: .rawRecordHash)
        payloadSummary = try container.decodeIfPresent([String: String].self, forKey: .payloadSummary) ?? [:]
    }
}

nonisolated struct JamfInventoryPreloadSubmission: Identifiable, Codable, Equatable, Sendable {
    let id: String
    let submittedAt: Date
    let submittedBy: String?
    let deviceIds: [String]
    let payloadHash: String
    var state: DeploymentIntegrationState
    var diagnosticsCorrelationId: String?
    var failedDeviceIds: [String]
    var responseSummary: String?

    init(
        id: String = UUID().uuidString,
        submittedAt: Date = Date(),
        submittedBy: String? = nil,
        deviceIds: [String],
        payloadHash: String,
        state: DeploymentIntegrationState,
        diagnosticsCorrelationId: String? = nil,
        failedDeviceIds: [String] = [],
        responseSummary: String? = nil
    ) {
        self.id = id
        self.submittedAt = submittedAt
        self.submittedBy = submittedBy
        self.deviceIds = deviceIds
        self.payloadHash = payloadHash
        self.state = state
        self.diagnosticsCorrelationId = diagnosticsCorrelationId
        self.failedDeviceIds = failedDeviceIds
        self.responseSummary = responseSummary
    }
}

nonisolated struct SDPlusExportTemplate: Identifiable, Codable, Equatable, Sendable {
    let id: String
    var displayName: String
    var version: String
    var targetSystem: String
    var delimiter: String
    var includeHeader: Bool
    var columns: [SDPlusExportColumn]
    var validationRules: [String]
    var lifecycleState: DeploymentRecordLifecycleState
    let createdAt: Date
    var modifiedAt: Date

    init(
        id: String = UUID().uuidString,
        displayName: String,
        version: String,
        targetSystem: String = "SD+",
        delimiter: String = ",",
        includeHeader: Bool = true,
        columns: [SDPlusExportColumn],
        validationRules: [String] = [],
        lifecycleState: DeploymentRecordLifecycleState = .active,
        createdAt: Date = Date(),
        modifiedAt: Date? = nil
    ) {
        self.id = id
        self.displayName = displayName
        self.version = version
        self.targetSystem = targetSystem
        self.delimiter = delimiter
        self.includeHeader = includeHeader
        self.columns = columns
        self.validationRules = validationRules
        self.lifecycleState = lifecycleState
        self.createdAt = createdAt
        self.modifiedAt = modifiedAt ?? createdAt
    }
}

nonisolated struct SDPlusExportColumn: Codable, Equatable, Sendable {
    var columnOrder: Int
    var header: String
    var sourceField: String
    var required: Bool
    var defaultValue: String?
    var transformRule: String?
    var allowedValues: [String]
    var maxLength: Int?
    var emptyValueBehavior: String?

    init(
        columnOrder: Int,
        header: String,
        sourceField: String,
        required: Bool,
        defaultValue: String? = nil,
        transformRule: String? = nil,
        allowedValues: [String] = [],
        maxLength: Int? = nil,
        emptyValueBehavior: String? = nil
    ) {
        self.columnOrder = columnOrder
        self.header = header
        self.sourceField = sourceField
        self.required = required
        self.defaultValue = defaultValue
        self.transformRule = transformRule
        self.allowedValues = allowedValues
        self.maxLength = maxLength
        self.emptyValueBehavior = emptyValueBehavior
    }
}

nonisolated struct SDPlusExportJob: Identifiable, Codable, Equatable, Sendable {
    let id: String
    let projectId: String?
    let templateId: String
    let exportedAt: Date
    let exportedBy: String?
    let deviceCount: Int
    let fileName: String
    let fileHash: String
    let exportVersion: Int
    var exportState: DeploymentIntegrationState
    var validationSummary: String
    let includedDeviceIds: [String]
    let failedDeviceIds: [String]
    var notes: String?

    init(
        id: String = UUID().uuidString,
        projectId: String?,
        templateId: String,
        exportedAt: Date = Date(),
        exportedBy: String? = nil,
        deviceCount: Int,
        fileName: String,
        fileHash: String,
        exportVersion: Int,
        exportState: DeploymentIntegrationState = .exported,
        validationSummary: String,
        includedDeviceIds: [String],
        failedDeviceIds: [String] = [],
        notes: String? = nil
    ) {
        self.id = id
        self.projectId = projectId
        self.templateId = templateId
        self.exportedAt = exportedAt
        self.exportedBy = exportedBy
        self.deviceCount = deviceCount
        self.fileName = fileName
        self.fileHash = fileHash
        self.exportVersion = exportVersion
        self.exportState = exportState
        self.validationSummary = validationSummary
        self.includedDeviceIds = includedDeviceIds
        self.failedDeviceIds = failedDeviceIds
        self.notes = notes
    }
}

nonisolated struct RecordsExportJob: Identifiable, Codable, Equatable, Sendable {
    let id: String
    let createdAt: Date
    let createdBy: String?
    let exportFormat: String
    let packageName: String
    let fileName: String
    let fileHash: String?
    let includedRecordCount: Int

    init(
        id: String = UUID().uuidString,
        createdAt: Date = Date(),
        createdBy: String? = nil,
        exportFormat: String,
        packageName: String,
        fileName: String,
        fileHash: String? = nil,
        includedRecordCount: Int
    ) {
        self.id = id
        self.createdAt = createdAt
        self.createdBy = createdBy
        self.exportFormat = exportFormat
        self.packageName = packageName
        self.fileName = fileName
        self.fileHash = fileHash
        self.includedRecordCount = includedRecordCount
    }
}

nonisolated struct RecordsDeletionReview: Identifiable, Codable, Equatable, Sendable {
    let id: String
    let recordId: String
    let recordType: String
    var impactSummary: String
    var exportPolicySatisfied: Bool
    var finalConfirmationSatisfied: Bool
}

nonisolated struct DeploymentKPIProjection: Identifiable, Codable, Equatable, Sendable {
    let id: String
    let displayName: String
    let value: Int
    let category: String
    let total: Int
    let fraction: Double
    let color: DeploymentKPIColor
    let accessibilitySummary: String

    init(
        id: String,
        displayName: String,
        value: Int,
        category: String,
        total: Int = 0,
        color: DeploymentKPIColor = .blue,
        accessibilitySummary: String? = nil
    ) {
        self.id = id
        self.displayName = displayName
        self.value = value
        self.category = category
        self.total = total
        self.fraction = total > 0 ? min(max(Double(value) / Double(total), 0), 1) : 0
        self.color = color
        self.accessibilitySummary = accessibilitySummary ?? "\(displayName): \(value)"
    }
}

nonisolated struct DeploymentKPIColor: Codable, Equatable, Sendable {
    let red: Double
    let green: Double
    let blue: Double
    let alpha: Double

    var floatComponents: [Float] {
        [Float(red), Float(green), Float(blue), Float(alpha)]
    }

    static let blue = DeploymentKPIColor(red: 0.12, green: 0.38, blue: 0.88, alpha: 1)
    static let green = DeploymentKPIColor(red: 0.18, green: 0.66, blue: 0.38, alpha: 1)
    static let orange = DeploymentKPIColor(red: 0.94, green: 0.55, blue: 0.16, alpha: 1)
    static let red = DeploymentKPIColor(red: 0.86, green: 0.22, blue: 0.22, alpha: 1)
    static let purple = DeploymentKPIColor(red: 0.48, green: 0.34, blue: 0.84, alpha: 1)
    static let gray = DeploymentKPIColor(red: 0.48, green: 0.50, blue: 0.55, alpha: 1)
}

nonisolated struct DeploymentDashboardProjection: Codable, Equatable, Sendable {
    let generatedAt: Date
    let operationalTotals: [DeploymentKPIProjection]
    let statusIndicators: [DeploymentKPIProjection]
    let deviceTypeDistribution: [DeploymentKPIProjection]
    let integrationHealth: [DeploymentKPIProjection]

    var allKPIs: [DeploymentKPIProjection] {
        operationalTotals + statusIndicators + deviceTypeDistribution + integrationHealth
    }

    static let empty = DeploymentDashboardProjection(
        generatedAt: Date(timeIntervalSince1970: 0),
        operationalTotals: [],
        statusIndicators: [],
        deviceTypeDistribution: [],
        integrationHealth: []
    )
}
