import Foundation

// MARK: - Tracker persistence contract
//
// Store errors are intentionally user-readable because they are often surfaced
// through structured error cards. Keep these descriptions specific enough for a
// technician to correct data without reading logs.
nonisolated enum DeploymentTrackerStoreError: LocalizedError, Equatable {
    case duplicateActiveSerial(String)
    case missingRecord(id: String)
    case protectedWorkflowBehaviorTag(statusId: String)

    var errorDescription: String? {
        switch self {
        case let .duplicateActiveSerial(serial):
            return "An active Deployment Tracker device already uses serial number \(serial)."
        case let .missingRecord(id):
            return "Deployment Tracker record \(id) was not found."
        case let .protectedWorkflowBehaviorTag(statusId):
            return "Workflow status \(statusId) cannot change its protected behavior tag."
        }
    }
}

// DeploymentTrackerStore is the module's persistence boundary. UI and services
// depend on this protocol instead of Core Data directly, which keeps tests and
// temporary fallback storage independent from the production database.
nonisolated protocol DeploymentTrackerStore: Sendable {
    func fetchDevices(includeArchived: Bool) async throws -> [DeploymentDevice]
    @discardableResult func saveDevice(_ device: DeploymentDevice) async throws -> DeploymentDevice
    @discardableResult func archiveDevice(id: String, actor: String?) async throws -> DeploymentDevice
    @discardableResult func restoreDevice(id: String, actor: String?) async throws -> DeploymentDevice

    func fetchProjects(includeArchived: Bool) async throws -> [DeploymentProject]
    @discardableResult func saveProject(_ project: DeploymentProject) async throws -> DeploymentProject
    @discardableResult func archiveProject(id: String, actor: String?) async throws -> DeploymentProject
    @discardableResult func restoreProject(id: String, actor: String?) async throws -> DeploymentProject

    func fetchReferenceValues(categoryId: String?) async throws -> [DeploymentReferenceValue]
    @discardableResult func saveReferenceValue(_ value: DeploymentReferenceValue) async throws -> DeploymentReferenceValue

    func fetchFieldDefinitions() async throws -> [DeploymentFieldDefinition]
    @discardableResult func saveFieldDefinition(_ field: DeploymentFieldDefinition) async throws -> DeploymentFieldDefinition

    func fetchWorkbenchLayouts() async throws -> [WorkbenchLayout]
    @discardableResult func saveWorkbenchLayout(_ layout: WorkbenchLayout) async throws -> WorkbenchLayout

    func fetchWorkflowStatuses(includeArchived: Bool) async throws -> [DeploymentWorkflowStatusDefinition]
    @discardableResult func saveWorkflowStatus(_ status: DeploymentWorkflowStatusDefinition) async throws -> DeploymentWorkflowStatusDefinition
    func fetchAppleCatalogEntries(includeArchived: Bool) async throws -> [DeploymentAppleHardwareCatalogEntry]
    @discardableResult func saveAppleCatalogEntry(_ entry: DeploymentAppleHardwareCatalogEntry) async throws -> DeploymentAppleHardwareCatalogEntry

    func fetchAuditEvents(entityId: String?) async throws -> [DeploymentAuditEvent]
    func fetchWorkflowEvents(deviceId: String?) async throws -> [DeploymentWorkflowEvent]
    func fetchExceptions(deviceId: String?, projectId: String?, includeResolved: Bool) async throws -> [DeploymentException]
    func fetchAppleBusinessSnapshots() async throws -> [AppleBusinessDeviceSnapshot]
    func fetchJamfPreloadSnapshots() async throws -> [JamfInventoryPreloadSnapshot]
    func fetchJamfInventorySnapshots() async throws -> [JamfInventoryDeviceSnapshot]
    func fetchJamfPreloadSubmissions() async throws -> [JamfInventoryPreloadSubmission]
    func fetchSDPlusExportJobs() async throws -> [SDPlusExportJob]
    func fetchRecordsExportJobs() async throws -> [RecordsExportJob]

    func appendAuditEvent(_ event: DeploymentAuditEvent) async throws
    func appendWorkflowEvent(_ event: DeploymentWorkflowEvent) async throws
    func appendException(_ exception: DeploymentException) async throws
    func appendAppleBusinessSnapshot(_ snapshot: AppleBusinessDeviceSnapshot) async throws
    func appendJamfPreloadSnapshot(_ snapshot: JamfInventoryPreloadSnapshot) async throws
    func appendJamfInventorySnapshot(_ snapshot: JamfInventoryDeviceSnapshot) async throws
    func createJamfPreloadSubmission(_ submission: JamfInventoryPreloadSubmission) async throws
    func createSDPlusExportJob(_ job: SDPlusExportJob) async throws
    func createRecordsExportJob(_ job: RecordsExportJob) async throws
}

actor InMemoryDeploymentTrackerStore: DeploymentTrackerStore {
    private var devices: [String: DeploymentDevice]
    private var projects: [String: DeploymentProject]
    private var referenceValues: [String: DeploymentReferenceValue]
    private var fieldDefinitions: [String: DeploymentFieldDefinition]
    private var workbenchLayouts: [String: WorkbenchLayout]
    private var workflowStatuses: [String: DeploymentWorkflowStatusDefinition]
    private var appleCatalogEntries: [String: DeploymentAppleHardwareCatalogEntry]
    private var auditEvents: [DeploymentAuditEvent]
    private var workflowEvents: [DeploymentWorkflowEvent]
    private var exceptions: [DeploymentException]
    private var appleBusinessSnapshots: [AppleBusinessDeviceSnapshot]
    private var jamfPreloadSnapshots: [JamfInventoryPreloadSnapshot]
    private var jamfInventorySnapshots: [JamfInventoryDeviceSnapshot]
    private var jamfPreloadSubmissions: [JamfInventoryPreloadSubmission]
    private var sdPlusExportJobs: [SDPlusExportJob]
    private var recordsExportJobs: [RecordsExportJob]

    init(
        devices: [DeploymentDevice] = [],
        projects: [DeploymentProject] = [],
        referenceValues: [DeploymentReferenceValue] = DeploymentTrackerSeedData.referenceValues,
        fieldDefinitions: [DeploymentFieldDefinition] = DeploymentTrackerSeedData.fieldDefinitions,
        workbenchLayouts: [WorkbenchLayout] = [DeploymentTrackerSeedData.workbookDefaultLayout],
        workflowStatuses: [DeploymentWorkflowStatusDefinition] = DeploymentTrackerSeedData.workflowStatuses,
        appleCatalogEntries: [DeploymentAppleHardwareCatalogEntry] = [],
        auditEvents: [DeploymentAuditEvent] = [],
        workflowEvents: [DeploymentWorkflowEvent] = [],
        exceptions: [DeploymentException] = [],
        appleBusinessSnapshots: [AppleBusinessDeviceSnapshot] = [],
        jamfPreloadSnapshots: [JamfInventoryPreloadSnapshot] = [],
        jamfInventorySnapshots: [JamfInventoryDeviceSnapshot] = [],
        jamfPreloadSubmissions: [JamfInventoryPreloadSubmission] = [],
        sdPlusExportJobs: [SDPlusExportJob] = [],
        recordsExportJobs: [RecordsExportJob] = []
    ) {
        self.devices = Dictionary(uniqueKeysWithValues: devices.map { ($0.id, $0) })
        self.projects = Dictionary(uniqueKeysWithValues: projects.map { ($0.id, $0) })
        self.referenceValues = Dictionary(uniqueKeysWithValues: referenceValues.map { ($0.id, $0) })
        self.fieldDefinitions = Dictionary(uniqueKeysWithValues: fieldDefinitions.map { ($0.fieldKey, $0) })
        self.workbenchLayouts = Dictionary(uniqueKeysWithValues: workbenchLayouts.map { ($0.id, $0) })
        self.workflowStatuses = Dictionary(uniqueKeysWithValues: workflowStatuses.map { ($0.id, $0) })
        self.appleCatalogEntries = Dictionary(uniqueKeysWithValues: appleCatalogEntries.map { ($0.id, $0) })
        self.auditEvents = auditEvents
        self.workflowEvents = workflowEvents
        self.exceptions = exceptions
        self.appleBusinessSnapshots = appleBusinessSnapshots
        self.jamfPreloadSnapshots = jamfPreloadSnapshots
        self.jamfInventorySnapshots = jamfInventorySnapshots
        self.jamfPreloadSubmissions = jamfPreloadSubmissions
        self.sdPlusExportJobs = sdPlusExportJobs
        self.recordsExportJobs = recordsExportJobs
    }

    func fetchDevices(includeArchived: Bool = false) async throws -> [DeploymentDevice] {
        sorted(devices.values.filter { includeArchived || $0.recordLifecycleState == .active })
    }

    @discardableResult
    func saveDevice(_ device: DeploymentDevice) async throws -> DeploymentDevice {
        try validateUniqueActiveSerial(for: device)
        devices[device.id] = device
        return device
    }

    @discardableResult
    func archiveDevice(id: String, actor: String? = nil) async throws -> DeploymentDevice {
        guard let device = devices[id] else {
            throw DeploymentTrackerStoreError.missingRecord(id: id)
        }
        let archived = device.withLifecycleState(.archived, modifiedBy: actor)
        devices[id] = archived
        return archived
    }

    @discardableResult
    func restoreDevice(id: String, actor: String? = nil) async throws -> DeploymentDevice {
        guard let device = devices[id] else {
            throw DeploymentTrackerStoreError.missingRecord(id: id)
        }
        let restored = device.withLifecycleState(.active, modifiedBy: actor)
        try validateUniqueActiveSerial(for: restored)
        devices[id] = restored
        return restored
    }

    func fetchProjects(includeArchived: Bool = false) async throws -> [DeploymentProject] {
        projects.values
            .filter { includeArchived || $0.recordLifecycleState == .active }
            .sorted { $0.projectName.localizedCaseInsensitiveCompare($1.projectName) == .orderedAscending }
    }

    @discardableResult
    func saveProject(_ project: DeploymentProject) async throws -> DeploymentProject {
        projects[project.id] = project
        return project
    }

    @discardableResult
    func archiveProject(id: String, actor: String? = nil) async throws -> DeploymentProject {
        guard let project = projects[id] else {
            throw DeploymentTrackerStoreError.missingRecord(id: id)
        }
        let archived = project.withLifecycleState(.archived)
        projects[id] = archived
        return archived
    }

    @discardableResult
    func restoreProject(id: String, actor: String? = nil) async throws -> DeploymentProject {
        guard let project = projects[id] else {
            throw DeploymentTrackerStoreError.missingRecord(id: id)
        }
        let restored = project.withLifecycleState(.active)
        projects[id] = restored
        return restored
    }

    func fetchReferenceValues(categoryId: String? = nil) async throws -> [DeploymentReferenceValue] {
        referenceValues.values
            .filter { categoryId == nil || $0.categoryId == categoryId }
            .sorted {
                if $0.sortOrder == $1.sortOrder {
                    return $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending
                }
                return $0.sortOrder < $1.sortOrder
            }
    }

    @discardableResult
    func saveReferenceValue(_ value: DeploymentReferenceValue) async throws -> DeploymentReferenceValue {
        referenceValues[value.id] = value
        return value
    }

    func fetchFieldDefinitions() async throws -> [DeploymentFieldDefinition] {
        fieldDefinitions.values.sorted { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending }
    }

    @discardableResult
    func saveFieldDefinition(_ field: DeploymentFieldDefinition) async throws -> DeploymentFieldDefinition {
        fieldDefinitions[field.fieldKey] = field
        return field
    }

    func fetchWorkbenchLayouts() async throws -> [WorkbenchLayout] {
        workbenchLayouts.values.sorted { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending }
    }

    @discardableResult
    func saveWorkbenchLayout(_ layout: WorkbenchLayout) async throws -> WorkbenchLayout {
        workbenchLayouts[layout.id] = layout
        return layout
    }

    func fetchWorkflowStatuses(includeArchived: Bool = false) async throws -> [DeploymentWorkflowStatusDefinition] {
        workflowStatuses.values
            .filter { includeArchived || $0.lifecycleState == .active }
            .sorted { $0.sortOrder < $1.sortOrder }
    }

    @discardableResult
    func saveWorkflowStatus(_ status: DeploymentWorkflowStatusDefinition) async throws -> DeploymentWorkflowStatusDefinition {
        if let existing = workflowStatuses[status.id],
           existing.systemBehaviorTag != status.systemBehaviorTag {
            throw DeploymentTrackerStoreError.protectedWorkflowBehaviorTag(statusId: status.id)
        }

        workflowStatuses[status.id] = status
        return status
    }

    func fetchAppleCatalogEntries(includeArchived: Bool = false) async throws -> [DeploymentAppleHardwareCatalogEntry] {
        appleCatalogEntries.values
            .filter { includeArchived || $0.lifecycleState == .active }
            .sorted {
                ($0.marketingName ?? $0.id).localizedCaseInsensitiveCompare($1.marketingName ?? $1.id) == .orderedAscending
            }
    }

    @discardableResult
    func saveAppleCatalogEntry(_ entry: DeploymentAppleHardwareCatalogEntry) async throws -> DeploymentAppleHardwareCatalogEntry {
        appleCatalogEntries[entry.id] = entry
        return entry
    }

    func fetchAuditEvents(entityId: String? = nil) async throws -> [DeploymentAuditEvent] {
        auditEvents
            .filter { entityId == nil || $0.entityId == entityId }
            .sorted { $0.occurredAt < $1.occurredAt }
    }

    func fetchWorkflowEvents(deviceId: String? = nil) async throws -> [DeploymentWorkflowEvent] {
        workflowEvents
            .filter { deviceId == nil || $0.deviceId == deviceId }
            .sorted { $0.transitionedAt < $1.transitionedAt }
    }

    func fetchExceptions(
        deviceId: String? = nil,
        projectId: String? = nil,
        includeResolved: Bool = true
    ) async throws -> [DeploymentException] {
        exceptions
            .filter { exception in
                let deviceMatches = deviceId == nil || exception.deviceId == deviceId
                let projectMatches = projectId == nil || exception.projectId == projectId
                let resolutionMatches = includeResolved || ![.resolved, .waived, .superseded].contains(exception.status)
                return deviceMatches && projectMatches && resolutionMatches
            }
            .sorted { $0.createdAt < $1.createdAt }
    }

    func fetchJamfPreloadSubmissions() async throws -> [JamfInventoryPreloadSubmission] {
        jamfPreloadSubmissions.sorted { $0.submittedAt < $1.submittedAt }
    }

    func fetchAppleBusinessSnapshots() async throws -> [AppleBusinessDeviceSnapshot] {
        appleBusinessSnapshots.sorted { $0.capturedAt < $1.capturedAt }
    }

    func fetchJamfPreloadSnapshots() async throws -> [JamfInventoryPreloadSnapshot] {
        jamfPreloadSnapshots.sorted { $0.capturedAt < $1.capturedAt }
    }

    func fetchJamfInventorySnapshots() async throws -> [JamfInventoryDeviceSnapshot] {
        jamfInventorySnapshots.sorted { $0.capturedAt < $1.capturedAt }
    }

    func fetchSDPlusExportJobs() async throws -> [SDPlusExportJob] {
        sdPlusExportJobs.sorted { $0.exportedAt < $1.exportedAt }
    }

    func fetchRecordsExportJobs() async throws -> [RecordsExportJob] {
        recordsExportJobs.sorted { $0.createdAt < $1.createdAt }
    }

    func appendAuditEvent(_ event: DeploymentAuditEvent) async throws {
        auditEvents.append(event)
    }

    func appendWorkflowEvent(_ event: DeploymentWorkflowEvent) async throws {
        workflowEvents.append(event)
    }

    func appendException(_ exception: DeploymentException) async throws {
        exceptions.append(exception)
    }

    func appendAppleBusinessSnapshot(_ snapshot: AppleBusinessDeviceSnapshot) async throws {
        appleBusinessSnapshots.append(snapshot)
    }

    func appendJamfPreloadSnapshot(_ snapshot: JamfInventoryPreloadSnapshot) async throws {
        jamfPreloadSnapshots.append(snapshot)
    }

    func appendJamfInventorySnapshot(_ snapshot: JamfInventoryDeviceSnapshot) async throws {
        jamfInventorySnapshots.append(snapshot)
    }

    func createJamfPreloadSubmission(_ submission: JamfInventoryPreloadSubmission) async throws {
        jamfPreloadSubmissions.append(submission)
    }

    func createSDPlusExportJob(_ job: SDPlusExportJob) async throws {
        sdPlusExportJobs.append(job)
    }

    func createRecordsExportJob(_ job: RecordsExportJob) async throws {
        recordsExportJobs.append(job)
    }

    private func validateUniqueActiveSerial(for device: DeploymentDevice) throws {
        guard device.recordLifecycleState == .active else {
            return
        }

        if devices.values.contains(where: {
            $0.id != device.id &&
            $0.recordLifecycleState == .active &&
            $0.normalizedSerialNumber == device.normalizedSerialNumber
        }) {
            throw DeploymentTrackerStoreError.duplicateActiveSerial(device.serialNumber)
        }
    }

    private func sorted(_ devices: some Sequence<DeploymentDevice>) -> [DeploymentDevice] {
        devices.sorted { lhs, rhs in
            lhs.normalizedSerialNumber.localizedCaseInsensitiveCompare(rhs.normalizedSerialNumber) == .orderedAscending
        }
    }
}
