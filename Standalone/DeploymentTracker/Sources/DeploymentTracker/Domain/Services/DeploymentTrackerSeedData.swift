import Foundation

// MARK: - Deployment Tracker seed data
//
// Seed data defines the module's default Field Catalog, Workbench layout,
// workflow statuses, reference values, preload templates, and SD+ templates.
// Persistence can store user-edited versions, but these defaults give a clean
// first-run experience and a recovery baseline for resetting layouts.
nonisolated enum DeploymentTrackerSeedData {
    // Field definitions are the module's schema contract for the Workbench,
    // imports, exports, validations, and inspectors. The fieldKey values must
    // stay stable because layouts, audit events, and export mappings refer to
    // them by string.
    nonisolated static let fieldDefinitions: [DeploymentFieldDefinition] = [
        field(
            "device.serialNumber",
            displayName: "Serial",
            category: "Identity",
            fieldType: .serialNumber,
            defaultWidth: 160
        ),
        field(
            "device.assetTag",
            displayName: "Asset Tag",
            category: "Identity",
            defaultWidth: 140
        ),
        field(
            "device.projectId",
            displayName: "Project",
            category: "Project",
            fieldType: .reference,
            groupable: true,
            defaultWidth: 220,
            editorType: "referenceDropdown",
            referenceCategoryId: "projects"
        ),
        field(
            "device.deviceTypeId",
            displayName: "Device Type",
            category: "Device Classification",
            fieldType: .reference,
            groupable: true,
            defaultWidth: 160,
            editorType: "referenceDropdown",
            referenceCategoryId: "device-types"
        ),
        field(
            "device.model",
            displayName: "Model",
            category: "Device Classification",
            defaultWidth: 180
        ),
        field(
            "device.workflowStatusId",
            displayName: "Status",
            category: "Workflow",
            fieldType: .reference,
            groupable: true,
            defaultWidth: 180,
            editorType: "referenceDropdown",
            referenceCategoryId: "workflow-statuses",
            systemBehaviorTag: "workflowStatus"
        ),
        field(
            "device.geoLocation",
            displayName: "GEO/Location",
            category: "Location",
            fieldType: .reference,
            groupable: true,
            defaultWidth: 180,
            editorType: "referenceDropdown",
            referenceCategoryId: "locations"
        ),
        field(
            "device.profileId",
            displayName: "Profile",
            category: "Profile",
            fieldType: .reference,
            groupable: true,
            defaultWidth: 180,
            editorType: "referenceDropdown",
            referenceCategoryId: "profiles"
        ),
        field(
            "device.assignedUser",
            displayName: "Assigned User",
            category: "User Assignment",
            defaultWidth: 180
        ),
        field(
            "device.jamfPreloadState",
            displayName: "Inventory Preload",
            category: "Jamf Inventory Preload",
            fieldType: .externalState,
            editable: false,
            groupable: true,
            defaultWidth: 170,
            rendererType: "externalStateBadge",
            editorType: "none",
            systemBehaviorTag: "jamfInventoryPreloadState"
        ),
        field(
            "device.sdPlusExportState",
            displayName: "SD+",
            category: "SD+",
            fieldType: .externalState,
            editable: false,
            groupable: true,
            defaultWidth: 120,
            rendererType: "externalStateBadge",
            editorType: "none",
            systemBehaviorTag: "sdPlusExportState"
        ),
        field(
            "device.jamfEnrollmentState",
            displayName: "JAMF",
            category: "Jamf Inventory",
            sourceOfTruth: .jamfPro,
            fieldType: .externalSnapshot,
            editable: false,
            groupable: true,
            defaultWidth: 140,
            rendererType: "externalStateBadge",
            editorType: "none"
        ),
        field(
            "device.poNumber",
            displayName: "PO Number",
            category: "Procurement",
            defaultWidth: 150
        ),
        field(
            "device.orderNumber",
            displayName: "Order Number",
            category: "Procurement",
            defaultWidth: 150
        ),
        field(
            "device.ticketNumber",
            displayName: "Ticket Number",
            category: "Project",
            defaultWidth: 160
        ),
        field(
            "device.replacingSerialNumber",
            displayName: "Replacing Serial",
            category: "Identity",
            fieldType: .serialNumber,
            defaultWidth: 170
        ),
        field(
            "device.fedExTrackingNumber",
            displayName: "FedEx Tracking",
            category: "Shipping",
            fieldType: .trackingNumber,
            defaultWidth: 180
        ),
        field(
            "device.returnTrackingNumber",
            displayName: "Return Tracking",
            category: "Returns",
            fieldType: .trackingNumber,
            defaultWidth: 180
        ),
        field(
            "device.deliveryConfirmation",
            displayName: "Delivery Confirmation",
            category: "Shipping",
            defaultWidth: 190
        ),
        field(
            "device.gmEmailed",
            displayName: "GM Emailed",
            category: "Workflow",
            fieldType: .boolean,
            groupable: true,
            defaultWidth: 120,
            rendererType: "booleanCheckmark",
            editorType: "toggle"
        ),
        field(
            "device.comments",
            displayName: "Comments",
            category: "Notes",
            fieldType: .multilineText,
            defaultWidth: 240
        ),
        field(
            "device.notes",
            displayName: "Notes",
            category: "Notes",
            fieldType: .multilineText,
            defaultWidth: 240
        ),
        field(
            "abm.assignedMDMServiceName",
            displayName: "ABM Assigned MDM Service",
            category: "Apple Business / ABM",
            sourceOfTruth: .abm,
            fieldType: .externalSnapshot,
            editable: false,
            groupable: true,
            visibleByDefault: false,
            defaultWidth: 240,
            rendererType: "externalStateBadge",
            editorType: "none"
        ),
        field(
            "abm.lastCheckedAt",
            displayName: "ABM Last Checked",
            category: "Apple Business / ABM",
            sourceOfTruth: .abm,
            fieldType: .dateTime,
            editable: false,
            visibleByDefault: false,
            defaultWidth: 180,
            editorType: "none"
        ),
        field(
            "catalog.marketingName",
            displayName: "Catalog Marketing Name",
            category: "Apple Catalog",
            sourceOfTruth: .appleCatalog,
            editable: false,
            visibleByDefault: false,
            defaultWidth: 220,
            editorType: "none"
        ),
        field(
            "derived.blockingExceptionCount",
            displayName: "Blocking Exceptions",
            category: "Exceptions",
            sourceOfTruth: .derived,
            fieldType: .integer,
            editable: false,
            groupable: true,
            visibleByDefault: false,
            defaultWidth: 140,
            editorType: "none"
        )
    ]

    nonisolated static let workbookDefaultLayout = WorkbenchLayout(
        id: "workbench-layout-workbook-default",
        displayName: "Workbook Default",
        ownerScope: "SystemDefault",
        isDefault: true,
        isSystem: true,
        columns: [
            column("device.serialNumber", order: 1, width: 160, pinned: true),
            column("device.projectId", order: 2, width: 220),
            column("device.deviceTypeId", order: 3, width: 160),
            column("device.model", order: 4, width: 180),
            column("device.workflowStatusId", order: 5, width: 180),
            column("device.geoLocation", order: 6, width: 180),
            column("device.profileId", order: 7, width: 180),
            column("device.assignedUser", order: 8, width: 180),
            column("device.jamfPreloadState", order: 9, width: 170),
            column("device.sdPlusExportState", order: 10, width: 120),
            column("device.jamfEnrollmentState", order: 11, width: 140),
            column("device.poNumber", order: 12, width: 150),
            column("device.orderNumber", order: 13, width: 150),
            column("device.ticketNumber", order: 14, width: 160),
            column("device.replacingSerialNumber", order: 15, width: 170),
            column("device.fedExTrackingNumber", order: 16, width: 180),
            column("device.returnTrackingNumber", order: 17, width: 180),
            column("device.deliveryConfirmation", order: 18, width: 190),
            column("device.gmEmailed", order: 19, width: 120),
            column("device.comments", order: 20, width: 240),
            column("device.notes", order: 21, width: 240)
        ],
        notes: "Visual default based on the workbook In-Progress column order. This is layout only, not formula/data behavior."
    )

    nonisolated static let workflowStatuses: [DeploymentWorkflowStatusDefinition] = [
        status("status-received", "Received", tag: "intake.received", category: "Intake", isDefault: true, order: 10),
        status("status-cataloged", "Cataloged", tag: "catalog.cataloged", category: "Catalog", order: 20),
        status("status-abm-verification-required", "ABM Verification Required", tag: "abm.verificationRequired", category: "Verification", order: 30),
        status("status-abm-verified", "ABM Verified", tag: "abm.verified", category: "Verification", order: 40),
        status("status-abm-exception", "ABM Exception", tag: "abm.exception", category: "Exception", isExceptionState: true, isBlockingState: true, requiresReason: true, order: 50),
        status("status-assigned-to-project", "Assigned to Project", tag: "project.assigned", category: "Project Assignment", order: 60),
        status("status-pending-configuration", "Pending Configuration", tag: "configuration.pending", category: "Configuration", order: 70),
        status("status-configured", "Configured", tag: "configuration.configured", category: "Configuration", order: 80),
        status("status-qa-ready", "QA Ready", tag: "qa.ready", category: "QA", order: 90),
        status("status-qa-failed", "QA Failed", tag: "qa.failed", category: "QA", isExceptionState: true, isBlockingState: true, requiresReason: true, order: 100),
        status("status-ready-for-jamf-preload", "Ready for Jamf Inventory Preload", tag: "jamfPreload.ready", category: "Jamf Preload", order: 110),
        status("status-jamf-preload-submitted", "Jamf Inventory Preload Submitted", tag: "jamfPreload.submitted", category: "Jamf Preload", order: 120),
        status("status-jamf-preload-failed", "Jamf Inventory Preload Failed", tag: "jamfPreload.failed", category: "Jamf Preload", isExceptionState: true, isBlockingState: true, requiresReason: true, order: 130),
        status("status-jamf-preload-reconciled", "Jamf Inventory Preload Reconciled", tag: "jamfPreload.reconciled", category: "Jamf Preload", order: 140),
        status("status-ready-for-sdplus-export", "Ready for SD+ Export", tag: "sdplus.ready", category: "SD+ Export", order: 150),
        status("status-sdplus-exported", "SD+ Exported", tag: "sdplus.exported", category: "SD+ Export", order: 160),
        status("status-ready-to-ship", "Ready to Ship", tag: "shipping.ready", category: "Shipping", order: 170),
        status("status-shipped", "Shipped", tag: "shipping.shipped", category: "Shipping", order: 180),
        status("status-delivered", "Delivered", tag: "shipping.delivered", category: "Shipping", order: 190),
        status("status-complete", "Complete", tag: "completion.complete", category: "Completion", isTerminal: true, order: 200),
        status("status-exception", "Exception", tag: "exception.general", category: "Exception", isExceptionState: true, isBlockingState: true, requiresReason: true, order: 210),
        status("status-returned", "Returned", tag: "return.returned", category: "Return", order: 220),
        status("status-retired", "Retired", tag: "retirement.retired", category: "Retirement", isTerminal: true, order: 230),
        status("status-archived", "Archived", tag: "records.archived", category: "Archive", isTerminal: true, order: 240)
    ]

    nonisolated static let workflowTransitions: [DeploymentWorkflowTransitionDefinition] = [
        transition("status-received", "status-cataloged", gate: .catalogGate),
        transition("status-cataloged", "status-abm-verification-required", gate: .abmVerificationReadinessGate),
        transition("status-abm-verification-required", "status-abm-verified", gate: .abmVerificationGate),
        transition("status-abm-verification-required", "status-abm-exception", requiresReason: true),
        transition("status-abm-verified", "status-assigned-to-project", gate: .projectAssignmentGate),
        transition("status-assigned-to-project", "status-pending-configuration", gate: .configurationGate),
        transition("status-pending-configuration", "status-configured", gate: .configurationGate),
        transition("status-configured", "status-qa-ready", gate: .qaGate),
        transition("status-qa-ready", "status-ready-for-jamf-preload", gate: .qaGate),
        transition("status-qa-ready", "status-qa-failed", requiresReason: true),
        transition("status-qa-failed", "status-pending-configuration", gate: .configurationGate),
        transition("status-configured", "status-ready-for-jamf-preload", gate: .jamfPreloadReadinessGate),
        transition("status-ready-for-jamf-preload", "status-jamf-preload-submitted", gate: .jamfPreloadSubmissionGate),
        transition("status-ready-for-jamf-preload", "status-jamf-preload-failed", requiresReason: true),
        transition("status-jamf-preload-submitted", "status-jamf-preload-reconciled", gate: .jamfPreloadReconciliationGate),
        transition("status-jamf-preload-submitted", "status-jamf-preload-failed", requiresReason: true),
        transition("status-jamf-preload-failed", "status-ready-for-jamf-preload", gate: .jamfPreloadReadinessGate),
        transition("status-jamf-preload-reconciled", "status-ready-for-sdplus-export", gate: .sdPlusExportGate),
        transition("status-ready-for-sdplus-export", "status-sdplus-exported", gate: .sdPlusExportGate),
        transition("status-sdplus-exported", "status-ready-to-ship", gate: .shippingGate),
        transition("status-ready-to-ship", "status-shipped", gate: .shippingGate),
        transition("status-shipped", "status-delivered", gate: .deliveryGate),
        transition("status-delivered", "status-complete", gate: .completionGate),
        transition("status-complete", "status-archived", gate: .recordsManagementGate)
    ]

    nonisolated static let jamfInventoryPreloadStandardTemplate = JamfInventoryPreloadTemplate(
        id: "jamf-inventory-preload-standard-v1",
        displayName: "Jamf Inventory Preload Standard",
        columns: [
            JamfInventoryPreloadColumn(jamfColumn: "Serial Number", sourceField: "device.serialNumber", required: true),
            JamfInventoryPreloadColumn(jamfColumn: "Device Type", sourceField: "device.deviceType.jamfPreloadDeviceType", required: true),
            JamfInventoryPreloadColumn(jamfColumn: "Username", sourceField: "device.assignedUser", required: false),
            JamfInventoryPreloadColumn(jamfColumn: "Email Address", sourceField: "device.assignedUserEmail", required: false),
            JamfInventoryPreloadColumn(jamfColumn: "Building", sourceField: "device.location.building", required: false),
            JamfInventoryPreloadColumn(jamfColumn: "Room", sourceField: "device.location.room", required: false),
            JamfInventoryPreloadColumn(jamfColumn: "Asset Tag", sourceField: "device.assetTag", required: false),
            JamfInventoryPreloadColumn(jamfColumn: "Department", sourceField: "device.department", required: false),
            JamfInventoryPreloadColumn(jamfColumn: "PO Number", sourceField: "device.poNumber", required: false)
        ]
    )

    nonisolated static let sdPlusAssetImportTemplate = SDPlusExportTemplate(
        id: "sdplus-asset-import-v1",
        displayName: "SD+ Asset Import",
        version: "1",
        targetSystem: "SD+",
        delimiter: ",",
        includeHeader: true,
        columns: [
            SDPlusExportColumn(columnOrder: 0, header: "Serial Number", sourceField: "device.serialNumber", required: true),
            SDPlusExportColumn(columnOrder: 1, header: "Asset Type", sourceField: "device.deviceTypeId", required: true),
            SDPlusExportColumn(columnOrder: 2, header: "Model", sourceField: "device.model", required: false),
            SDPlusExportColumn(columnOrder: 3, header: "Project", sourceField: "device.projectId", required: false),
            SDPlusExportColumn(columnOrder: 4, header: "Assigned User", sourceField: "device.assignedUser", required: false),
            SDPlusExportColumn(columnOrder: 5, header: "Location", sourceField: "device.geoLocation", required: false),
            SDPlusExportColumn(columnOrder: 6, header: "Ticket Number", sourceField: "device.ticketNumber", required: false),
            SDPlusExportColumn(columnOrder: 7, header: "Asset Tag", sourceField: "device.assetTag", required: false)
        ],
        validationRules: ["requiredFields", "fieldCatalogSourceKeys"]
    )

    nonisolated static let referenceValues: [DeploymentReferenceValue] = [
        DeploymentReferenceValue(
            id: "device-type-macbook-pro",
            categoryId: "device-types",
            displayName: "MacBook Pro",
            sortOrder: 10,
            metadata: ["jamfPreloadDeviceType": "Computer"]
        ),
        DeploymentReferenceValue(
            id: "device-type-macbook-air",
            categoryId: "device-types",
            displayName: "MacBook Air",
            sortOrder: 20,
            metadata: ["jamfPreloadDeviceType": "Computer"]
        ),
        DeploymentReferenceValue(
            id: "device-type-imac",
            categoryId: "device-types",
            displayName: "iMac",
            sortOrder: 30,
            metadata: ["jamfPreloadDeviceType": "Computer"]
        ),
        DeploymentReferenceValue(
            id: "device-type-mac-mini",
            categoryId: "device-types",
            displayName: "Mac mini",
            sortOrder: 40,
            metadata: ["jamfPreloadDeviceType": "Computer"]
        ),
        DeploymentReferenceValue(
            id: "device-type-ipad",
            categoryId: "device-types",
            displayName: "iPad",
            sortOrder: 50,
            metadata: ["jamfPreloadDeviceType": "Mobile Device"]
        ),
        DeploymentReferenceValue(
            id: "device-type-iphone",
            categoryId: "device-types",
            displayName: "iPhone",
            sortOrder: 60,
            metadata: ["jamfPreloadDeviceType": "Mobile Device"]
        )
    ]

    nonisolated private static func field(
        _ fieldKey: String,
        displayName: String,
        category: String,
        entityType: String = "DeploymentDevice",
        sourceOfTruth: DeploymentFieldSourceOfTruth = .deploymentTracker,
        fieldType: DeploymentFieldValueType = .text,
        editable: Bool = true,
        required: Bool = false,
        sortable: Bool = true,
        filterable: Bool = true,
        groupable: Bool = false,
        exportable: Bool = true,
        reportable: Bool = true,
        visibleByDefault: Bool = true,
        defaultWidth: Double,
        rendererType: String = "text",
        editorType: String = "text",
        validationRules: [String] = [],
        referenceCategoryId: String? = nil,
        systemBehaviorTag: String? = nil,
        lifecycleState: DeploymentRecordLifecycleState = .active
    ) -> DeploymentFieldDefinition {
        DeploymentFieldDefinition(
            fieldKey: fieldKey,
            displayName: displayName,
            description: nil,
            category: category,
            entityType: entityType,
            sourceOfTruth: sourceOfTruth,
            fieldType: fieldType,
            editable: editable,
            required: required,
            sortable: sortable,
            filterable: filterable,
            groupable: groupable,
            exportable: exportable,
            reportable: reportable,
            visibleByDefault: visibleByDefault,
            defaultWidth: defaultWidth,
            rendererType: rendererType,
            editorType: editorType,
            validationRules: validationRules,
            referenceCategoryId: referenceCategoryId,
            systemBehaviorTag: systemBehaviorTag,
            lifecycleState: lifecycleState
        )
    }

    nonisolated private static func column(
        _ fieldKey: String,
        order: Int,
        width: Double,
        visible: Bool = true,
        pinned: Bool = false
    ) -> WorkbenchLayoutColumn {
        WorkbenchLayoutColumn(
            fieldKey: fieldKey,
            visible: visible,
            order: order,
            width: width,
            pinned: pinned
        )
    }

    nonisolated private static func status(
        _ id: String,
        _ displayName: String,
        tag: String,
        category: String,
        isDefault: Bool = false,
        isTerminal: Bool = false,
        isExceptionState: Bool = false,
        isBlockingState: Bool = false,
        requiresReason: Bool = false,
        order: Int
    ) -> DeploymentWorkflowStatusDefinition {
        DeploymentWorkflowStatusDefinition(
            id: id,
            displayName: displayName,
            systemBehaviorTag: tag,
            statusCategory: category,
            isDefault: isDefault,
            isTerminal: isTerminal,
            isExceptionState: isExceptionState,
            isBlockingState: isBlockingState,
            requiresReason: requiresReason,
            colorToken: category,
            iconToken: nil,
            sortOrder: order
        )
    }

    nonisolated private static func transition(
        _ fromStatusId: String,
        _ toStatusId: String,
        gate: DeploymentGateType? = nil,
        requiresReason: Bool = false
    ) -> DeploymentWorkflowTransitionDefinition {
        DeploymentWorkflowTransitionDefinition(
            fromStatusId: fromStatusId,
            toStatusId: toStatusId,
            gateType: gate,
            requiresReason: requiresReason
        )
    }
}
