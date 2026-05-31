import CoreData
import Foundation

// MARK: - Core Data tracker store
//
// Production persistence for Deployment Tracker. The actor boundary serializes
// Core Data access, and the store implements the DeploymentTrackerStore protocol
// so the rest of the module does not depend on Core Data details.
actor CoreDataDeploymentTrackerStore: DeploymentTrackerStore {
    // Record types are used by seeded-data upsert and migration helpers to keep
    // default definitions, layouts, and reference data synchronized.
    private enum RecordType: String, CaseIterable {
        case device
        case project
        case referenceValue
        case fieldDefinition
        case workbenchLayout
        case workflowStatus
        case appleCatalogEntry
        case auditEvent
        case workflowEvent
        case exception
        case appleBusinessSnapshot
        case jamfPreloadSnapshot
        case jamfInventorySnapshot
        case jamfPreloadSubmission
        case sdPlusExportJob
        case recordsExportJob
    }

    private let container: NSPersistentContainer
    private let context: NSManagedObjectContext
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    init(storeURL: URL? = nil) throws {
        let model = Self.makeModel()
        container = NSPersistentContainer(name: "DeploymentTracker", managedObjectModel: model)

        let resolvedURL = storeURL ?? Self.defaultStoreURL()
        do {
            try FileManager.default.createDirectory(
                at: resolvedURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
        } catch {
            throw JamfFrameworkError.persistenceFailure(
                message: "Deployment Tracker could not create its local database folder at \(resolvedURL.deletingLastPathComponent().path): \(error.localizedDescription)"
            )
        }

        let description = NSPersistentStoreDescription(url: resolvedURL)
        description.type = NSSQLiteStoreType
        description.shouldMigrateStoreAutomatically = true
        description.shouldInferMappingModelAutomatically = true
        container.persistentStoreDescriptions = [description]

        var loadError: Error?
        let semaphore = DispatchSemaphore(value: 0)
        container.loadPersistentStores { _, error in
            loadError = error
            semaphore.signal()
        }
        semaphore.wait()

        if let loadError {
            throw JamfFrameworkError.persistenceFailure(
                message: "Deployment Tracker could not open its local database at \(resolvedURL.path): \(loadError.localizedDescription)"
            )
        }

        context = container.newBackgroundContext()
        context.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy
        context.undoManager = nil

        encoder = JSONEncoder()
        decoder = JSONDecoder()

        do {
            try Self.seedDefaultsIfNeeded(context: context, encoder: encoder)
        } catch {
            throw JamfFrameworkError.persistenceFailure(
                message: "Deployment Tracker opened its local database but could not seed required reference data: \(error.localizedDescription)"
            )
        }
    }

    func close() async throws {
        do {
            try context.performAndWait {
                if context.hasChanges {
                    try context.save()
                }
                context.reset()
            }

            let coordinator = container.persistentStoreCoordinator
            for store in coordinator.persistentStores {
                try coordinator.remove(store)
            }
        } catch {
            throw JamfFrameworkError.persistenceFailure(
                message: "Deployment Tracker could not close its local database cleanly: \(error.localizedDescription)"
            )
        }
    }

    func fetchDevices(includeArchived: Bool = false) async throws -> [DeploymentDevice] {
        try fetchRecords(.device, as: DeploymentDevice.self)
            .filter { includeArchived || $0.recordLifecycleState == .active }
            .sorted { $0.normalizedSerialNumber.localizedCaseInsensitiveCompare($1.normalizedSerialNumber) == .orderedAscending }
    }

    @discardableResult
    func saveDevice(_ device: DeploymentDevice) async throws -> DeploymentDevice {
        try validateUniqueActiveSerial(for: device)
        try upsert(device, type: .device, id: device.id)
        return device
    }

    @discardableResult
    func archiveDevice(id: String, actor: String? = nil) async throws -> DeploymentDevice {
        guard let device = try fetchRecord(.device, id: id, as: DeploymentDevice.self) else {
            throw DeploymentTrackerStoreError.missingRecord(id: id)
        }
        let archived = device.withLifecycleState(.archived, modifiedBy: actor)
        try upsert(archived, type: .device, id: id)
        try appendAuditEventSync(
            DeploymentAuditEvent(
                eventType: "records.archive",
                entityType: "DeploymentDevice",
                entityId: id,
                fieldKey: "recordLifecycleState",
                oldValue: device.recordLifecycleState.rawValue,
                newValue: DeploymentRecordLifecycleState.archived.rawValue,
                actor: actor
            )
        )
        return archived
    }

    @discardableResult
    func restoreDevice(id: String, actor: String? = nil) async throws -> DeploymentDevice {
        guard let device = try fetchRecord(.device, id: id, as: DeploymentDevice.self) else {
            throw DeploymentTrackerStoreError.missingRecord(id: id)
        }
        let restored = device.withLifecycleState(.active, modifiedBy: actor)
        try validateUniqueActiveSerial(for: restored)
        try upsert(restored, type: .device, id: id)
        try appendAuditEventSync(
            DeploymentAuditEvent(
                eventType: "records.restore",
                entityType: "DeploymentDevice",
                entityId: id,
                fieldKey: "recordLifecycleState",
                oldValue: device.recordLifecycleState.rawValue,
                newValue: DeploymentRecordLifecycleState.active.rawValue,
                actor: actor
            )
        )
        return restored
    }

    func fetchProjects(includeArchived: Bool = false) async throws -> [DeploymentProject] {
        try fetchRecords(.project, as: DeploymentProject.self)
            .filter { includeArchived || $0.recordLifecycleState == .active }
            .sorted { $0.projectName.localizedCaseInsensitiveCompare($1.projectName) == .orderedAscending }
    }

    @discardableResult
    func saveProject(_ project: DeploymentProject) async throws -> DeploymentProject {
        try upsert(project, type: .project, id: project.id)
        return project
    }

    @discardableResult
    func archiveProject(id: String, actor: String? = nil) async throws -> DeploymentProject {
        guard let project = try fetchRecord(.project, id: id, as: DeploymentProject.self) else {
            throw DeploymentTrackerStoreError.missingRecord(id: id)
        }
        let archived = project.withLifecycleState(.archived)
        try upsert(archived, type: .project, id: id)
        try appendAuditEventSync(
            DeploymentAuditEvent(
                eventType: "records.archive",
                entityType: "DeploymentProject",
                entityId: id,
                fieldKey: "recordLifecycleState",
                oldValue: project.recordLifecycleState.rawValue,
                newValue: DeploymentRecordLifecycleState.archived.rawValue,
                actor: actor
            )
        )
        return archived
    }

    @discardableResult
    func restoreProject(id: String, actor: String? = nil) async throws -> DeploymentProject {
        guard let project = try fetchRecord(.project, id: id, as: DeploymentProject.self) else {
            throw DeploymentTrackerStoreError.missingRecord(id: id)
        }
        let restored = project.withLifecycleState(.active)
        try upsert(restored, type: .project, id: id)
        try appendAuditEventSync(
            DeploymentAuditEvent(
                eventType: "records.restore",
                entityType: "DeploymentProject",
                entityId: id,
                fieldKey: "recordLifecycleState",
                oldValue: project.recordLifecycleState.rawValue,
                newValue: DeploymentRecordLifecycleState.active.rawValue,
                actor: actor
            )
        )
        return restored
    }

    func fetchReferenceValues(categoryId: String? = nil) async throws -> [DeploymentReferenceValue] {
        try fetchRecords(.referenceValue, as: DeploymentReferenceValue.self)
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
        try upsert(value, type: .referenceValue, id: value.id)
        return value
    }

    func fetchFieldDefinitions() async throws -> [DeploymentFieldDefinition] {
        try fetchRecords(.fieldDefinition, as: DeploymentFieldDefinition.self)
            .sorted { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending }
    }

    @discardableResult
    func saveFieldDefinition(_ field: DeploymentFieldDefinition) async throws -> DeploymentFieldDefinition {
        try upsert(field, type: .fieldDefinition, id: field.fieldKey)
        return field
    }

    func fetchWorkbenchLayouts() async throws -> [WorkbenchLayout] {
        try fetchRecords(.workbenchLayout, as: WorkbenchLayout.self)
            .sorted {
                if $0.isDefault != $1.isDefault {
                    return $0.isDefault
                }
                return $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending
            }
    }

    @discardableResult
    func saveWorkbenchLayout(_ layout: WorkbenchLayout) async throws -> WorkbenchLayout {
        try upsert(layout, type: .workbenchLayout, id: layout.id)
        return layout
    }

    func fetchWorkflowStatuses(includeArchived: Bool = false) async throws -> [DeploymentWorkflowStatusDefinition] {
        try fetchRecords(.workflowStatus, as: DeploymentWorkflowStatusDefinition.self)
            .filter { includeArchived || $0.lifecycleState == .active }
            .sorted { $0.sortOrder < $1.sortOrder }
    }

    @discardableResult
    func saveWorkflowStatus(_ status: DeploymentWorkflowStatusDefinition) async throws -> DeploymentWorkflowStatusDefinition {
        if let existing = try fetchRecord(.workflowStatus, id: status.id, as: DeploymentWorkflowStatusDefinition.self),
           existing.systemBehaviorTag != status.systemBehaviorTag {
            throw DeploymentTrackerStoreError.protectedWorkflowBehaviorTag(statusId: status.id)
        }
        try upsert(status, type: .workflowStatus, id: status.id)
        return status
    }

    func fetchAppleCatalogEntries(includeArchived: Bool = false) async throws -> [DeploymentAppleHardwareCatalogEntry] {
        try fetchRecords(.appleCatalogEntry, as: DeploymentAppleHardwareCatalogEntry.self)
            .filter { includeArchived || $0.lifecycleState == .active }
            .sorted { ($0.marketingName ?? $0.id).localizedCaseInsensitiveCompare($1.marketingName ?? $1.id) == .orderedAscending }
    }

    @discardableResult
    func saveAppleCatalogEntry(_ entry: DeploymentAppleHardwareCatalogEntry) async throws -> DeploymentAppleHardwareCatalogEntry {
        try upsert(entry, type: .appleCatalogEntry, id: entry.id)
        return entry
    }

    func fetchAuditEvents(entityId: String? = nil) async throws -> [DeploymentAuditEvent] {
        try fetchRecords(.auditEvent, as: DeploymentAuditEvent.self)
            .filter { entityId == nil || $0.entityId == entityId }
            .sorted { $0.occurredAt < $1.occurredAt }
    }

    func fetchWorkflowEvents(deviceId: String? = nil) async throws -> [DeploymentWorkflowEvent] {
        try fetchRecords(.workflowEvent, as: DeploymentWorkflowEvent.self)
            .filter { deviceId == nil || $0.deviceId == deviceId }
            .sorted { $0.transitionedAt < $1.transitionedAt }
    }

    func fetchExceptions(
        deviceId: String? = nil,
        projectId: String? = nil,
        includeResolved: Bool = true
    ) async throws -> [DeploymentException] {
        try fetchRecords(.exception, as: DeploymentException.self)
            .filter { exception in
                let deviceMatches = deviceId == nil || exception.deviceId == deviceId
                let projectMatches = projectId == nil || exception.projectId == projectId
                let resolutionMatches = includeResolved || ![.resolved, .waived, .superseded].contains(exception.status)
                return deviceMatches && projectMatches && resolutionMatches
            }
            .sorted { $0.createdAt < $1.createdAt }
    }

    func fetchAppleBusinessSnapshots() async throws -> [AppleBusinessDeviceSnapshot] {
        try fetchRecords(.appleBusinessSnapshot, as: AppleBusinessDeviceSnapshot.self)
            .sorted { $0.capturedAt < $1.capturedAt }
    }

    func fetchJamfPreloadSnapshots() async throws -> [JamfInventoryPreloadSnapshot] {
        try fetchRecords(.jamfPreloadSnapshot, as: JamfInventoryPreloadSnapshot.self)
            .sorted { $0.capturedAt < $1.capturedAt }
    }

    func fetchJamfInventorySnapshots() async throws -> [JamfInventoryDeviceSnapshot] {
        try fetchRecords(.jamfInventorySnapshot, as: JamfInventoryDeviceSnapshot.self)
            .sorted { $0.capturedAt < $1.capturedAt }
    }

    func fetchJamfPreloadSubmissions() async throws -> [JamfInventoryPreloadSubmission] {
        try fetchRecords(.jamfPreloadSubmission, as: JamfInventoryPreloadSubmission.self)
            .sorted { $0.submittedAt < $1.submittedAt }
    }

    func fetchSDPlusExportJobs() async throws -> [SDPlusExportJob] {
        try fetchRecords(.sdPlusExportJob, as: SDPlusExportJob.self)
            .sorted { $0.exportedAt < $1.exportedAt }
    }

    func fetchRecordsExportJobs() async throws -> [RecordsExportJob] {
        try fetchRecords(.recordsExportJob, as: RecordsExportJob.self)
            .sorted { $0.createdAt < $1.createdAt }
    }

    func appendAuditEvent(_ event: DeploymentAuditEvent) async throws {
        try appendAuditEventSync(event)
    }

    func appendWorkflowEvent(_ event: DeploymentWorkflowEvent) async throws {
        try insert(event, type: .workflowEvent, id: event.id)
    }

    func appendException(_ exception: DeploymentException) async throws {
        try insert(exception, type: .exception, id: exception.id)
    }

    func appendAppleBusinessSnapshot(_ snapshot: AppleBusinessDeviceSnapshot) async throws {
        try insert(snapshot, type: .appleBusinessSnapshot, id: snapshot.id)
    }

    func appendJamfPreloadSnapshot(_ snapshot: JamfInventoryPreloadSnapshot) async throws {
        try insert(snapshot, type: .jamfPreloadSnapshot, id: snapshot.id)
    }

    func appendJamfInventorySnapshot(_ snapshot: JamfInventoryDeviceSnapshot) async throws {
        try insert(snapshot, type: .jamfInventorySnapshot, id: snapshot.id)
    }

    func createJamfPreloadSubmission(_ submission: JamfInventoryPreloadSubmission) async throws {
        try insert(submission, type: .jamfPreloadSubmission, id: submission.id)
    }

    func createSDPlusExportJob(_ job: SDPlusExportJob) async throws {
        try insert(job, type: .sdPlusExportJob, id: job.id)
    }

    func createRecordsExportJob(_ job: RecordsExportJob) async throws {
        try insert(job, type: .recordsExportJob, id: job.id)
    }

    private func validateUniqueActiveSerial(for device: DeploymentDevice) throws {
        guard device.recordLifecycleState == .active else {
            return
        }
        let activeDevices = try fetchRecords(.device, as: DeploymentDevice.self)
        if activeDevices.contains(where: {
            $0.id != device.id &&
            $0.recordLifecycleState == .active &&
            $0.normalizedSerialNumber == device.normalizedSerialNumber
        }) {
            throw DeploymentTrackerStoreError.duplicateActiveSerial(device.serialNumber)
        }
    }

    private func appendAuditEventSync(_ event: DeploymentAuditEvent) throws {
        try insert(event, type: .auditEvent, id: event.id)
    }

    private func fetchRecords<T: Decodable>(_ type: RecordType, as decodedType: T.Type) throws -> [T] {
        let request = NSFetchRequest<NSManagedObject>(entityName: "DeploymentTrackerRecord")
        request.predicate = NSPredicate(format: "recordType == %@", type.rawValue)
        request.sortDescriptors = [NSSortDescriptor(key: "createdAt", ascending: true)]
        return try context.fetch(request).compactMap { object in
            guard let payload = object.value(forKey: "payload") as? Data else {
                return nil
            }
            return try decoder.decode(decodedType, from: payload)
        }
    }

    private func fetchRecord<T: Decodable>(_ type: RecordType, id: String, as decodedType: T.Type) throws -> T? {
        guard let object = try fetchObject(type: type, id: id),
              let payload = object.value(forKey: "payload") as? Data else {
            return nil
        }
        return try decoder.decode(decodedType, from: payload)
    }

    private func upsert<T: Encodable>(_ value: T, type: RecordType, id: String) throws {
        let object = try fetchObject(type: type, id: id) ?? makeObject(type: type, id: id)
        object.setValue(try encoder.encode(value), forKey: "payload")
        object.setValue(Date(), forKey: "modifiedAt")
        try saveIfNeeded()
    }

    private func insert<T: Encodable>(_ value: T, type: RecordType, id: String) throws {
        let object = makeObject(type: type, id: id)
        object.setValue(try encoder.encode(value), forKey: "payload")
        try saveIfNeeded()
    }

    private func fetchObject(type: RecordType, id: String) throws -> NSManagedObject? {
        let request = NSFetchRequest<NSManagedObject>(entityName: "DeploymentTrackerRecord")
        request.fetchLimit = 1
        request.predicate = NSPredicate(format: "recordType == %@ AND recordId == %@", type.rawValue, id)
        return try context.fetch(request).first
    }

    private func makeObject(type: RecordType, id: String) -> NSManagedObject {
        let object = NSEntityDescription.insertNewObject(forEntityName: "DeploymentTrackerRecord", into: context)
        let now = Date()
        object.setValue(type.rawValue, forKey: "recordType")
        object.setValue(id, forKey: "recordId")
        object.setValue(now, forKey: "createdAt")
        object.setValue(now, forKey: "modifiedAt")
        return object
    }

    private func count(_ type: RecordType) throws -> Int {
        let request = NSFetchRequest<NSFetchRequestResult>(entityName: "DeploymentTrackerRecord")
        request.predicate = NSPredicate(format: "recordType == %@", type.rawValue)
        return try context.count(for: request)
    }

    private static func seedDefaultsIfNeeded(context: NSManagedObjectContext, encoder: JSONEncoder) throws {
        if try count(.fieldDefinition, context: context) == 0 {
            for field in DeploymentTrackerSeedData.fieldDefinitions {
                try upsert(field, type: .fieldDefinition, id: field.fieldKey, context: context, encoder: encoder)
            }
        }
        if try count(.workbenchLayout, context: context) == 0 {
            try upsert(DeploymentTrackerSeedData.workbookDefaultLayout, type: .workbenchLayout, id: DeploymentTrackerSeedData.workbookDefaultLayout.id, context: context, encoder: encoder)
        }
        if try count(.workflowStatus, context: context) == 0 {
            for status in DeploymentTrackerSeedData.workflowStatuses {
                try upsert(status, type: .workflowStatus, id: status.id, context: context, encoder: encoder)
            }
        }
        if try count(.referenceValue, context: context) == 0 {
            for value in DeploymentTrackerSeedData.referenceValues {
                try upsert(value, type: .referenceValue, id: value.id, context: context, encoder: encoder)
            }
        }
    }

    private static func upsert<T: Encodable>(
        _ value: T,
        type: RecordType,
        id: String,
        context: NSManagedObjectContext,
        encoder: JSONEncoder
    ) throws {
        let object = try fetchObject(type: type, id: id, context: context) ?? makeObject(type: type, id: id, context: context)
        object.setValue(try encoder.encode(value), forKey: "payload")
        object.setValue(Date(), forKey: "modifiedAt")
        try saveIfNeeded(context: context)
    }

    private static func fetchObject(type: RecordType, id: String, context: NSManagedObjectContext) throws -> NSManagedObject? {
        let request = NSFetchRequest<NSManagedObject>(entityName: "DeploymentTrackerRecord")
        request.fetchLimit = 1
        request.predicate = NSPredicate(format: "recordType == %@ AND recordId == %@", type.rawValue, id)
        return try context.fetch(request).first
    }

    private static func makeObject(type: RecordType, id: String, context: NSManagedObjectContext) -> NSManagedObject {
        let object = NSEntityDescription.insertNewObject(forEntityName: "DeploymentTrackerRecord", into: context)
        let now = Date()
        object.setValue(type.rawValue, forKey: "recordType")
        object.setValue(id, forKey: "recordId")
        object.setValue(now, forKey: "createdAt")
        object.setValue(now, forKey: "modifiedAt")
        return object
    }

    private static func count(_ type: RecordType, context: NSManagedObjectContext) throws -> Int {
        let request = NSFetchRequest<NSFetchRequestResult>(entityName: "DeploymentTrackerRecord")
        request.predicate = NSPredicate(format: "recordType == %@", type.rawValue)
        return try context.count(for: request)
    }

    private static func saveIfNeeded(context: NSManagedObjectContext) throws {
        if context.hasChanges {
            try context.save()
        }
    }

    private func saveIfNeeded() throws {
        if context.hasChanges {
            try context.save()
        }
    }

    private static func defaultStoreURL() -> URL {
        let baseURL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        return baseURL
            .appendingPathComponent("Forsetti", isDirectory: true)
            .appendingPathComponent("DeploymentTracker", isDirectory: true)
            .appendingPathComponent("DeploymentTracker.sqlite")
    }

    private static func makeModel() -> NSManagedObjectModel {
        let model = NSManagedObjectModel()
        let entity = NSEntityDescription()
        entity.name = "DeploymentTrackerRecord"
        entity.managedObjectClassName = NSStringFromClass(NSManagedObject.self)

        let recordType = NSAttributeDescription()
        recordType.name = "recordType"
        recordType.attributeType = .stringAttributeType
        recordType.isOptional = false

        let recordId = NSAttributeDescription()
        recordId.name = "recordId"
        recordId.attributeType = .stringAttributeType
        recordId.isOptional = false

        let payload = NSAttributeDescription()
        payload.name = "payload"
        payload.attributeType = .binaryDataAttributeType
        payload.isOptional = false
        payload.allowsExternalBinaryDataStorage = true

        let createdAt = NSAttributeDescription()
        createdAt.name = "createdAt"
        createdAt.attributeType = .dateAttributeType
        createdAt.isOptional = false

        let modifiedAt = NSAttributeDescription()
        modifiedAt.name = "modifiedAt"
        modifiedAt.attributeType = .dateAttributeType
        modifiedAt.isOptional = false

        entity.properties = [recordType, recordId, payload, createdAt, modifiedAt]
        entity.uniquenessConstraints = [["recordType", "recordId"]]
        model.entities = [entity]
        return model
    }
}
