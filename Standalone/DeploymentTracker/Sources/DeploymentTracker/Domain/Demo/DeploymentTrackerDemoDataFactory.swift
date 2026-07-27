import Foundation

nonisolated struct DeploymentTrackerDemoSeedBundle: Sendable {
    let seedVersion: String
    let devices: [DeploymentDevice]
    let projects: [DeploymentProject]
    let referenceValues: [DeploymentReferenceValue]
    let fieldDefinitions: [DeploymentFieldDefinition]
    let workbenchLayouts: [WorkbenchLayout]
    let workflowStatuses: [DeploymentWorkflowStatusDefinition]
    let appleCatalogEntries: [DeploymentAppleHardwareCatalogEntry]
    let auditEvents: [DeploymentAuditEvent]
    let workflowEvents: [DeploymentWorkflowEvent]
    let exceptions: [DeploymentException]
    let appleBusinessSnapshots: [AppleBusinessDeviceSnapshot]
    let jamfPreloadSnapshots: [JamfInventoryPreloadSnapshot]
    let jamfInventorySnapshots: [JamfInventoryDeviceSnapshot]
    let jamfPreloadRecords: [JamfInventoryPreloadRecord]
    let jamfPreloadSubmissions: [JamfInventoryPreloadSubmission]
    let sdPlusExportJobs: [SDPlusExportJob]
    let recordsExportJobs: [RecordsExportJob]
}

nonisolated enum DeploymentTrackerDemoDataFactory {
    static let seedVersion = DeploymentTrackerDemoMode.installedDefault.seedVersion
    static let baseDate = Date(timeIntervalSince1970: 1_778_544_000)

    private static let projectSpecs: [(code: String, name: String)] = [
        ("DEMO-RETAIL-REFRESH", "Demo Retail Refresh"),
        ("DEMO-FIELD-IPAD", "Demo Field iPad Rollout"),
        ("DEMO-EXEC-MAC", "Demo Executive Mac Refresh"),
        ("DEMO-WAREHOUSE-SHARED", "Demo Warehouse Shared Devices"),
        ("DEMO-REPLACEMENT-WAVE", "Demo Replacement Wave"),
        ("DEMO-PILOT-RING", "Demo Pilot Ring")
    ]

    private static let modelExamples = [
        "MacBook Air 13-inch M3",
        "MacBook Pro 14-inch M3 Pro",
        "Mac mini M2",
        "iPad 10th generation",
        "iPad Air 11-inch",
        "iPad Pro 11-inch",
        "iPhone 15",
        "iPhone 15 Pro",
        "iPhone SE",
        "Studio Display"
    ]

    private static let statusSequence = [
        "status-received",
        "status-cataloged",
        "status-abm-verification-required",
        "status-abm-verified",
        "status-abm-exception",
        "status-ready-for-jamf-preload",
        "status-jamf-preload-submitted",
        "status-jamf-preload-reconciled",
        "status-ready-for-sdplus-export",
        "status-sdplus-exported",
        "status-ready-to-ship",
        "status-shipped",
        "status-delivered",
        "status-complete",
        "status-exception"
    ]

    static func makeSeed() -> DeploymentTrackerDemoSeedBundle {
        let projects = makeProjects()
        let references = makeReferenceValues(projects: projects)
        let layouts = makeWorkbenchLayouts()
        let catalogEntries = makeAppleCatalogEntries()
        let devices = makeDevices(projects: projects)
        let exceptions = makeExceptions(devices: devices)
        let auditEvents = makeAuditEvents(devices: devices, projects: projects)
        let workflowEvents = makeWorkflowEvents(devices: devices)
        let abmSnapshots = makeAppleBusinessSnapshots(devices: devices)
        let preloadSnapshots = makeJamfPreloadSnapshots(devices: devices)
        let inventorySnapshots = makeJamfInventorySnapshots(devices: devices)
        let preloadRecords = makePreloadRecords(devices: devices)
        let submissions = makePreloadSubmissions(devices: devices)
        let sdPlusJobs = makeSDPlusJobs(devices: devices)
        let recordsJobs = makeRecordsJobs(devices: devices)

        return DeploymentTrackerDemoSeedBundle(
            seedVersion: seedVersion,
            devices: devices,
            projects: projects,
            referenceValues: references,
            fieldDefinitions: DeploymentTrackerSeedData.fieldDefinitions,
            workbenchLayouts: layouts,
            workflowStatuses: DeploymentTrackerSeedData.workflowStatuses,
            appleCatalogEntries: catalogEntries,
            auditEvents: auditEvents,
            workflowEvents: workflowEvents,
            exceptions: exceptions,
            appleBusinessSnapshots: abmSnapshots,
            jamfPreloadSnapshots: preloadSnapshots,
            jamfInventorySnapshots: inventorySnapshots,
            jamfPreloadRecords: preloadRecords,
            jamfPreloadSubmissions: submissions,
            sdPlusExportJobs: sdPlusJobs,
            recordsExportJobs: recordsJobs
        )
    }

    static func makeStore() -> InMemoryDeploymentTrackerStore {
        let seed = makeSeed()
        return makeStore(seed: seed)
    }

    static func makeStore(seed: DeploymentTrackerDemoSeedBundle) -> InMemoryDeploymentTrackerStore {
        return InMemoryDeploymentTrackerStore(
            devices: seed.devices,
            projects: seed.projects,
            referenceValues: seed.referenceValues,
            fieldDefinitions: seed.fieldDefinitions,
            workbenchLayouts: seed.workbenchLayouts,
            workflowStatuses: seed.workflowStatuses,
            appleCatalogEntries: seed.appleCatalogEntries,
            auditEvents: seed.auditEvents,
            workflowEvents: seed.workflowEvents,
            exceptions: seed.exceptions,
            appleBusinessSnapshots: seed.appleBusinessSnapshots,
            jamfPreloadSnapshots: seed.jamfPreloadSnapshots,
            jamfInventorySnapshots: seed.jamfInventorySnapshots,
            jamfPreloadSubmissions: seed.jamfPreloadSubmissions,
            sdPlusExportJobs: seed.sdPlusExportJobs,
            recordsExportJobs: seed.recordsExportJobs
        )
    }

    static func makePreloadRecords() -> [JamfInventoryPreloadRecord] {
        let devices = makeDevices(projects: makeProjects())
        return makePreloadRecords(devices: devices)
    }

    static func makeSerial(prefix: String, index: Int) -> String {
        "DEMO-\(prefix)-\(String(format: "%04d", index))"
    }

    static func makeDemoEmail(index: Int) -> String {
        "demo.user\(String(format: "%03d", index))@example.invalid"
    }

    private static func makeProjects() -> [DeploymentProject] {
        projectSpecs.enumerated().map { index, spec in
            var project = DeploymentProject(
                id: "demo-project-\(index + 1)",
                projectName: spec.name,
                projectCode: spec.code,
                ticketNumber: "DEMO-REQ-\(String(format: "%06d", index + 1))",
                createdAt: baseDate.addingTimeInterval(Double(index) * 86_400)
            )
            project.projectStatus = "Demo Active"
            project.businessUnit = "Demo Operations"
            project.customerOrDepartment = "Demo Stakeholders"
            project.projectOwner = "Demo Coordinator"
            project.defaultGeoId = "demo-region-\((index % 6) + 1)"
            project.defaultLocationId = "demo-location-\((index % 6) + 1)"
            project.defaultProfileId = "demo-profile-\((index % 5) + 1)"
            project.requiresABMVerification = true
            project.requiresExpectedABMMDMService = true
            project.allowsABMVerificationWaiver = true
            project.requiresQA = true
            project.requiresJamfInventoryPreload = true
            project.requiresJamfPreloadReconciliation = true
            project.allowsJamfPreloadOverwrite = true
            project.requiresSDPlusExport = true
            project.requiresShipping = true
            project.requiresDeliveryConfirmation = true
            project.allowsCompletionWithWarnings = true
            project.requiresCompletionReview = true
            project.notes = "Demo project only. Coming Soon preview data."
            return project
        }
    }

    private static func makeReferenceValues(projects: [DeploymentProject]) -> [DeploymentReferenceValue] {
        var values = DeploymentTrackerSeedData.referenceValues

        values += projects.enumerated().map { index, project in
            DeploymentReferenceValue(
                id: project.id,
                categoryId: "projects",
                displayName: project.projectCode ?? project.projectName,
                sortOrder: (index + 1) * 10,
                metadata: ["demo": "true", "projectName": project.projectName]
            )
        }

        values += (1...6).map {
            DeploymentReferenceValue(
                id: "demo-region-\($0)",
                categoryId: "geos",
                displayName: ["Demo North Region", "Demo South Region", "Demo Staging Lab", "Demo Remote User", "Demo Warehouse", "Demo Pilot Site"][$0 - 1],
                sortOrder: $0 * 10,
                metadata: ["demo": "true"]
            )
        }

        values += (1...6).map {
            DeploymentReferenceValue(
                id: "demo-location-\($0)",
                categoryId: "locations",
                displayName: ["Demo North Region", "Demo South Region", "Demo Staging Lab", "Demo Remote User", "Demo Warehouse", "Demo Pilot Site"][$0 - 1],
                sortOrder: $0 * 10,
                metadata: [
                    "demo": "true",
                    "building": "Demo Building \($0)",
                    "room": "Demo Room \(100 + $0)"
                ]
            )
        }

        values += (1...5).map {
            DeploymentReferenceValue(
                id: "demo-profile-\($0)",
                categoryId: "profiles",
                displayName: ["Demo Standard Mac", "Demo Shared iPad", "Demo Executive Mac", "Demo Field iPhone", "Demo Kiosk iPad"][$0 - 1],
                sortOrder: $0 * 10,
                metadata: ["demo": "true"]
            )
        }

        values += (1...8).map {
            DeploymentReferenceValue(
                id: "demo-department-\($0)",
                categoryId: "departments",
                displayName: "Demo Department \($0)",
                sortOrder: $0 * 10,
                metadata: ["demo": "true"]
            )
        }

        values += (1...10).map {
            DeploymentReferenceValue(
                id: "demo-status-reason-\($0)",
                categoryId: "status-reasons",
                displayName: "Demo Status Reason \($0)",
                sortOrder: $0 * 10,
                metadata: ["demo": "true"]
            )
        }

        values += (1...8).map {
            DeploymentReferenceValue(
                id: "demo-vendor-\($0)",
                categoryId: "vendors",
                displayName: "Demo Vendor \($0)",
                sortOrder: $0 * 10,
                metadata: ["demo": "true"]
            )
        }

        return values
    }

    private static func makeWorkbenchLayouts() -> [WorkbenchLayout] {
        [
            DeploymentTrackerSeedData.workbookDefaultLayout,
            demoLayout(id: "demo-layout-executive", name: "Demo Executive Summary", ownerScope: "Demo", visiblePrefixCount: 10),
            demoLayout(id: "demo-layout-preload", name: "Demo Jamf Preload Review", ownerScope: "Demo", visiblePrefixCount: 14),
            demoLayout(id: "demo-layout-shipping", name: "Demo Shipping Review", ownerScope: "Demo", visiblePrefixCount: 18)
        ]
    }

    private static func demoLayout(id: String, name: String, ownerScope: String, visiblePrefixCount: Int) -> WorkbenchLayout {
        let columns = DeploymentTrackerSeedData.workbookDefaultLayout.columns.map { column in
            WorkbenchLayoutColumn(
                fieldKey: column.fieldKey,
                visible: column.order <= visiblePrefixCount,
                order: column.order,
                width: column.width,
                pinned: column.pinned
            )
        }
        return WorkbenchLayout(
            id: id,
            displayName: name,
            ownerScope: ownerScope,
            isDefault: false,
            isSystem: true,
            columns: columns,
            notes: "Demo layout for the Deployment Tracker Demo interactive preview."
        )
    }

    private static func makeDevices(projects: [DeploymentProject]) -> [DeploymentDevice] {
        (1...120).map { index in
            var device = DeploymentDevice(
                id: "demo-device-\(String(format: "%03d", index))",
                serialNumber: serial(for: index),
                assetTag: "DEMO-AT-\(String(format: "%05d", index))",
                deviceTypeId: deviceTypeId(for: index),
                model: model(for: index),
                projectId: projects[(index - 1) % projects.count].id,
                workflowStatusId: workflowStatusId(for: index),
                createdAt: baseDate.addingTimeInterval(Double(index) * 900),
                createdBy: "Deployment Tracker Demo"
            )
            device.assignedUser = "Demo User \(String(format: "%03d", index))"
            device.assignedUserEmail = makeDemoEmail(index: index)
            device.department = "Demo Department \((index % 8) + 1)"
            device.businessUnit = "Demo Operations"
            device.geoId = "demo-region-\((index % 6) + 1)"
            device.locationId = "demo-location-\((index % 6) + 1)"
            device.profileId = "demo-profile-\((index % 5) + 1)"
            device.poNumber = "DEMO-PO-\(String(format: "%06d", index))"
            device.orderNumber = "DEMO-ORD-\(String(format: "%06d", index))"
            device.ticketNumber = "DEMO-SD-\(String(format: "%06d", index))"
            device.vendorName = "Demo Vendor \((index % 8) + 1)"
            device.vendorSku = "DEMO-SKU-\(String(format: "%04d", index))"
            device.applePartNumber = "DEMO-PART-\(String(format: "%04d", index))"
            device.modelIdentifier = modelIdentifier(for: index)
            device.replacementForSerialNumber = index % 9 == 0 ? makeSerial(prefix: "OLD", index: index) : nil
            device.receivedDate = baseDate.addingTimeInterval(Double(index) * 1_800)
            device.abmVerificationState = abmState(for: index)
            device.jamfPreloadState = preloadState(for: index)
            device.jamfEnrollmentState = jamfState(for: index)
            device.jamfReconciliationState = reconciliationState(for: index)
            device.sdPlusExportState = sdPlusState(for: index)
            device.shippingState = shippingState(for: index)
            device.fedExTrackingNumber = index % 5 == 0 ? "DEMO-FDX-\(String(format: "%012d", index))" : nil
            device.returnTrackingNumber = index % 17 == 0 ? "DEMO-RET-\(String(format: "%012d", index))" : nil
            device.deliveryConfirmation = index % 6 == 0 ? "DEMO-DELIVERED-\(String(format: "%04d", index))" : nil
            device.gmEmailed = index % 4 == 0
            device.comments = "Demo record \(index). Simulation data only."
            device.notes = "No live Jamf actions. Coming Soon workflow preview."
            device.blockingReason = index % 11 == 0 ? "Demo exception requires review." : nil
            return device
        }
    }

    private static func serial(for index: Int) -> String {
        if index == 7 {
            return "DEMO-MAC-0007"
        }
        if index == 21 {
            return "DEMO-IPAD-0021"
        }
        if index == 33 {
            return "DEMO-MAC-0033"
        }
        if index <= 54 {
            return makeSerial(prefix: "MAC", index: index)
        }
        if index <= 96 {
            let ipadIndex = index - 54
            return makeSerial(prefix: "IPAD", index: ipadIndex >= 21 ? ipadIndex + 1 : ipadIndex)
        }
        return makeSerial(prefix: "IPHONE", index: index - 96)
    }

    private static func deviceTypeId(for index: Int) -> String {
        if index == 21 {
            return "device-type-ipad"
        }
        if index <= 54 {
            return index % 4 == 0 ? "device-type-mac-mini" : "device-type-macbook-air"
        }
        if index <= 96 {
            return "device-type-ipad"
        }
        return "device-type-iphone"
    }

    private static func modelIdentifier(for index: Int) -> String {
        if index == 21 {
            return "iPad14,1"
        }
        if index <= 54 {
            return ["Mac15,1", "Mac15,3", "Macmini9,1"][index % 3]
        }
        if index <= 96 {
            return ["iPad13,18", "iPad14,1", "iPad15,7"][index % 3]
        }
        return ["iPhone15,4", "iPhone16,1", "iPhone14,6"][index % 3]
    }

    private static func model(for index: Int) -> String {
        if index == 21 {
            return "iPad Air 11-inch"
        }
        return modelExamples[(index - 1) % modelExamples.count]
    }

    private static func workflowStatusId(for index: Int) -> String {
        if index == 7 {
            return "status-ready-for-jamf-preload"
        }
        if index == 21 {
            return "status-jamf-preload-submitted"
        }
        if index == 33 {
            return "status-abm-exception"
        }
        return statusSequence[(index - 1) % statusSequence.count]
    }

    private static func abmState(for index: Int) -> DeploymentABMVerificationState {
        if index == 33 || index % 13 == 0 {
            return .assignedToDifferentMDM
        }
        if index % 17 == 0 {
            return .unassigned
        }
        if index % 19 == 0 {
            return .notFound
        }
        if index % 5 == 0 {
            return .found
        }
        return .assignedToExpectedMDM
    }

    private static func preloadState(for index: Int) -> DeploymentIntegrationState {
        if index == 7 {
            return .ready
        }
        if index == 21 {
            return .submitted
        }
        if index % 14 == 0 {
            return .failed
        }
        if index % 6 == 0 {
            return .reconciled
        }
        if index % 4 == 0 {
            return .submitted
        }
        return .ready
    }

    private static func jamfState(for index: Int) -> DeploymentIntegrationState {
        index % 9 == 0 ? .unknown : .complete
    }

    private static func reconciliationState(for index: Int) -> DeploymentIntegrationState {
        index % 8 == 0 ? .reconciled : .pending
    }

    private static func sdPlusState(for index: Int) -> DeploymentIntegrationState {
        index % 7 == 0 ? .exported : (index % 3 == 0 ? .ready : .pending)
    }

    private static func shippingState(for index: Int) -> DeploymentIntegrationState {
        if index % 15 == 0 {
            return .complete
        }
        if index % 6 == 0 {
            return .submitted
        }
        if index % 4 == 0 {
            return .ready
        }
        return .pending
    }

    private static func makeExceptions(devices: [DeploymentDevice]) -> [DeploymentException] {
        let exceptionDevices = [
            10, 11, 13, 17, 21, 22, 33, 44, 55, 66, 77, 88
        ].compactMap { index in devices.first { $0.id == "demo-device-\(String(format: "%03d", index))" } }

        return exceptionDevices.enumerated().map { index, device in
            DeploymentException(
                id: "demo-exception-\(String(format: "%03d", index + 1))",
                deviceId: device.id,
                projectId: device.projectId,
                reasonCode: [
                    "demo.missing-ticket",
                    "demo.abm-mismatch",
                    "demo.preload-conflict",
                    "demo.shipping-hold",
                    "demo.duplicate-serial",
                    "demo.missing-assigned-user"
                ][index % 6],
                summary: "Demo exception for \(device.serialNumber). Simulation data only.",
                severity: index % 4 == 0 ? .blocking : .warning,
                status: index % 5 == 0 ? .acknowledged : .open,
                createdAt: baseDate.addingTimeInterval(Double(index) * 3_600)
            )
        }
    }

    private static func makeAuditEvents(devices: [DeploymentDevice], projects: [DeploymentProject]) -> [DeploymentAuditEvent] {
        var events: [DeploymentAuditEvent] = projects.enumerated().map { index, project in
            DeploymentAuditEvent(
                id: "demo-audit-project-\(index + 1)",
                occurredAt: baseDate.addingTimeInterval(Double(index) * 600),
                eventType: "demo.project.seeded",
                entityType: "DeploymentProject",
                entityId: project.id,
                fieldKey: "project.projectCode",
                oldValue: nil,
                newValue: project.projectCode,
                actor: "Deployment Tracker Demo",
                metadata: demoMetadata(action: "seed-project")
            )
        }

        events += devices.prefix(48).enumerated().map { index, device in
            DeploymentAuditEvent(
                id: "demo-audit-device-\(String(format: "%03d", index + 1))",
                occurredAt: baseDate.addingTimeInterval(Double(index + 10) * 600),
                eventType: "demo.workflow.event",
                entityType: "DeploymentDevice",
                entityId: device.id,
                fieldKey: "device.workflowStatusId",
                oldValue: "status-received",
                newValue: device.workflowStatusId,
                actor: "Deployment Tracker Demo",
                metadata: demoMetadata(action: "seed-device")
            )
        }
        return events
    }

    private static func makeWorkflowEvents(devices: [DeploymentDevice]) -> [DeploymentWorkflowEvent] {
        devices.prefix(40).enumerated().map { index, device in
            DeploymentWorkflowEvent(
                id: "demo-workflow-event-\(String(format: "%03d", index + 1))",
                deviceId: device.id,
                fromStatusId: "status-received",
                toStatusId: device.workflowStatusId ?? "status-cataloged",
                transitionedAt: baseDate.addingTimeInterval(Double(index) * 1_200),
                transitionedBy: "Deployment Tracker Demo",
                gateResult: "demo",
                reason: "Demo scenario seed transition."
            )
        }
    }

    private static func makeAppleBusinessSnapshots(devices: [DeploymentDevice]) -> [AppleBusinessDeviceSnapshot] {
        devices.prefix(30).map { device in
            AppleBusinessDeviceSnapshot(
                id: "demo-abm-snapshot-\(device.id)",
                deploymentDeviceId: device.id,
                serialNumber: device.serialNumber,
                capturedAt: baseDate.addingTimeInterval(3_600),
                capturedBy: "Deployment Tracker Demo",
                lookupStatus: device.abmVerificationState,
                abmModel: device.model,
                abmSerialNumber: device.serialNumber,
                abmPartNumber: device.applePartNumber,
                abmOrderNumber: device.orderNumber,
                abmOrderSource: "Demo Apple Business",
                abmStorageSize: "Demo 512 GB",
                abmDeviceSource: "Demo Automated Device Enrollment",
                abmDateAdded: baseDate,
                abmAssignedManagementServiceId: device.abmVerificationState == .assignedToDifferentMDM ? "demo-mdm-wrong" : "demo-mdm-expected",
                abmAssignedManagementServiceName: device.abmVerificationState == .assignedToDifferentMDM ? "Demo Wrong MDM" : "Demo Expected Jamf MDM",
                rawRecordHash: "demo-abm-\(device.normalizedSerialNumber)",
                diagnosticsCorrelationId: "demo-abm-\(device.id)"
            )
        }
    }

    private static func makeJamfPreloadSnapshots(devices: [DeploymentDevice]) -> [JamfInventoryPreloadSnapshot] {
        devices.prefix(30).map { device in
            let missing = device.serialNumber == "DEMO-MAC-0007" || device.id.hasSuffix("009")
            let conflict = device.serialNumber == "DEMO-IPAD-0021" || device.id.hasSuffix("014")
            return JamfInventoryPreloadSnapshot(
                id: "demo-preload-snapshot-\(device.id)",
                deploymentDeviceId: device.id,
                serialNumber: device.serialNumber,
                capturedAt: baseDate.addingTimeInterval(7_200),
                rawRecordHash: missing ? nil : "demo-preload-\(device.normalizedSerialNumber)",
                payloadSummary: [
                    "lookupStatus": missing ? "notFound" : "found",
                    "recordId": "demo-preload-record-\(device.id)",
                    "deviceType": device.deviceTypeId == "device-type-iphone" || device.deviceTypeId == "device-type-ipad" ? "Mobile Device" : "Computer",
                    "username": device.assignedUser ?? "",
                    "emailAddress": device.assignedUserEmail ?? "",
                    "building": conflict ? "Demo Current Building" : "Demo Proposed Building",
                    "room": "Demo Room",
                    "assetTag": device.assetTag ?? "",
                    "department": conflict ? "Demo Legacy Department" : (device.department ?? ""),
                    "poNumber": device.poNumber ?? ""
                ]
            )
        }
    }

    private static func makeJamfInventorySnapshots(devices: [DeploymentDevice]) -> [JamfInventoryDeviceSnapshot] {
        devices.prefix(30).map { device in
            JamfInventoryDeviceSnapshot(
                id: "demo-jamf-inventory-\(device.id)",
                deploymentDeviceId: device.id,
                serialNumber: device.serialNumber,
                capturedAt: baseDate.addingTimeInterval(10_800),
                jamfComputerId: device.deviceTypeId?.contains("mac") == true ? "DEMO-JAMF-C-\(device.id)" : nil,
                jamfMobileDeviceId: device.deviceTypeId?.contains("ipad") == true || device.deviceTypeId?.contains("iphone") == true ? "DEMO-JAMF-M-\(device.id)" : nil,
                inventoryState: device.jamfEnrollmentState,
                rawRecordHash: "demo-jamf-inventory-\(device.normalizedSerialNumber)",
                payloadSummary: ["demo": "true", "serialNumber": device.serialNumber, "model": device.model ?? ""]
            )
        }
    }

    private static func makePreloadRecords(devices: [DeploymentDevice]) -> [JamfInventoryPreloadRecord] {
        devices.prefix(30).compactMap { device in
            let missing = device.serialNumber == "DEMO-MAC-0007" || device.id.hasSuffix("009")
            guard missing == false else {
                return nil
            }
            let conflict = device.serialNumber == "DEMO-IPAD-0021" || device.id.hasSuffix("014")
            return JamfInventoryPreloadRecord(
                id: "demo-preload-record-\(device.id)",
                serialNumber: device.serialNumber,
                deviceType: device.deviceTypeId == "device-type-iphone" || device.deviceTypeId == "device-type-ipad" ? "Mobile Device" : "Computer",
                username: device.assignedUser,
                emailAddress: device.assignedUserEmail,
                building: conflict ? "Demo Current Building" : "Demo Proposed Building",
                room: "Demo Room",
                assetTag: device.assetTag,
                department: conflict ? "Demo Legacy Department" : device.department,
                poNumber: device.poNumber
            )
        }
    }

    private static func makePreloadSubmissions(devices: [DeploymentDevice]) -> [JamfInventoryPreloadSubmission] {
        (1...8).map { index in
            let includedIds = devices.dropFirst((index - 1) * 8).prefix(8).map(\.id)
            return JamfInventoryPreloadSubmission(
                id: "demo-preload-submission-\(index)",
                submittedAt: baseDate.addingTimeInterval(Double(index) * 4_200),
                submittedBy: "Deployment Tracker Demo",
                deviceIds: includedIds,
                payloadHash: "demo-payload-hash-\(index)",
                state: index == 3 ? .failed : (index == 5 ? .reconciled : .submitted),
                diagnosticsCorrelationId: "demo-preload-correlation-\(index)",
                failedDeviceIds: index == 3 ? Array(includedIds.prefix(2)) : [],
                responseSummary: index == 3 ? "Demo permission failure. No Jamf upload occurred." : "Demo Inventory Preload submission simulated."
            )
        }
    }

    private static func makeSDPlusJobs(devices: [DeploymentDevice]) -> [SDPlusExportJob] {
        (1...6).map { index in
            let includedIds = devices.dropFirst((index - 1) * 10).prefix(10).map(\.id)
            return SDPlusExportJob(
                id: "demo-sdplus-export-\(index)",
                projectId: "demo-project-\(((index - 1) % 6) + 1)",
                templateId: DeploymentTrackerSeedData.sdPlusAssetImportTemplate.id,
                exportedAt: baseDate.addingTimeInterval(Double(index) * 5_400),
                exportedBy: "Deployment Tracker Demo",
                deviceCount: includedIds.count,
                fileName: "Demo-SDPlus-Export-\(index).csv",
                fileHash: "demo-sdplus-hash-\(index)",
                exportVersion: index,
                exportState: index == 2 ? .failed : .exported,
                validationSummary: index == 2 ? "1 demo missing ticket warning" : "Demo export preview valid",
                includedDeviceIds: includedIds,
                failedDeviceIds: index == 2 ? Array(includedIds.prefix(1)) : [],
                notes: "Demo SD+ export history. No SD+ data changed."
            )
        }
    }

    private static func makeRecordsJobs(devices: [DeploymentDevice]) -> [RecordsExportJob] {
        (1...3).map { index in
            RecordsExportJob(
                id: "demo-records-export-\(index)",
                createdAt: baseDate.addingTimeInterval(Double(index) * 7_200),
                createdBy: "Deployment Tracker Demo",
                exportFormat: "Demo ZIP package",
                packageName: "DemoRecordsExport-\(index)",
                fileName: "DemoRecordsExport-\(index).zip",
                fileHash: "demo-records-hash-\(index)",
                includedRecordCount: devices.count
            )
        }
    }

    private static func makeAppleCatalogEntries() -> [DeploymentAppleHardwareCatalogEntry] {
        var entries: [DeploymentAppleHardwareCatalogEntry] = []
        entries.reserveCapacity(20)

        for index in 1...20 {
            let paddedID = String(format: "%03d", index)
            let paddedNumber = String(format: "%04d", index)
            let family: String = index <= 8 ? "Mac" : (index <= 15 ? "iPad" : "iPhone")
            let type: String = index <= 8 ? "Computer" : "Mobile Device"

            entries.append(
                DeploymentAppleHardwareCatalogEntry(
                    id: "demo-apple-catalog-\(paddedID)",
                    sourceName: "Deployment Tracker Demo Catalog",
                    sourceType: "demo",
                    sourceFileName: "demo-apple-catalog.csv",
                    sourceFileHash: "demo-catalog-hash",
                    importedAt: baseDate,
                    importedBy: "Deployment Tracker Demo",
                    applePartNumber: "DEMO-PART-\(paddedNumber)",
                    appleModelNumber: "DEMO-MODEL-\(paddedNumber)",
                    orderPartNumber: "DEMO-ORDER-PART-\(paddedNumber)",
                    vendorSku: "DEMO-SKU-\(paddedNumber)",
                    modelIdentifier: modelIdentifier(for: index),
                    marketingName: modelExamples[(index - 1) % modelExamples.count],
                    deviceFamily: family,
                    deviceType: type,
                    chipFamily: "Demo Apple Silicon",
                    chipName: "Demo M\(index % 4 + 1)",
                    cpuCoreCount: 8 + (index % 4),
                    gpuCoreCount: 8 + (index % 6),
                    storage: "Demo 512 GB",
                    memory: "Demo 16 GB",
                    color: "Demo Silver",
                    cellularCapability: index > 8,
                    wifiCapability: true,
                    releaseYear: 2026,
                    supportedOSRange: "Demo supported OS range",
                    confidenceScore: 0.92,
                    notes: "Demo catalog entry. Not production data."
                )
            )
        }

        return entries
    }

    private static func demoMetadata(action: String) -> [String: String] {
        [
            "demo_mode": "true",
            "simulation": "true",
            "external_data_changed": "false",
            "production_data_changed": "false",
            "action": action
        ]
    }
}
