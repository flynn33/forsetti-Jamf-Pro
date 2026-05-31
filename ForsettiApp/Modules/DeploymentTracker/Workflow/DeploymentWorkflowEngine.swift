import Foundation

// MARK: - Deployment workflow engine
//
// Workflow code decides whether a device can move from one tracker status to
// another. It evaluates project policy, device readiness, local exceptions, and
// integration states before saving a transition or recording a blocked attempt.
nonisolated enum DeploymentWorkflowEngineError: LocalizedError, Equatable {
    case missingDevice(id: String)
    case missingStatus(id: String)

    var errorDescription: String? {
        switch self {
        case let .missingDevice(id):
            return "Deployment device \(id) was not found."
        case let .missingStatus(id):
            return "Workflow status \(id) was not found."
        }
    }
}

// Gate validation is pure business logic. It does not fetch or save records; it
// receives the device, optional project policy, and current exceptions, then
// returns the actionable issues that block or warn on the transition.
nonisolated struct DeploymentGateValidationService: Sendable {
    func validate(
        _ gateType: DeploymentGateType,
        device: DeploymentDevice,
        project: DeploymentProject?,
        exceptions: [DeploymentException] = []
    ) -> DeploymentGateValidationResult {
        // Each gate is intentionally a separate function so workflow policy can
        // evolve without turning this switch into a dense block of mixed rules.
        switch gateType {
        case .catalogGate:
            return catalogGate(device: device)
        case .abmVerificationReadinessGate:
            return abmVerificationReadinessGate(gateType: gateType, project: project)
        case .abmVerificationGate:
            return abmVerificationGate(device: device, project: project)
        case .projectAssignmentGate:
            return projectAssignmentGate(device: device, project: project)
        case .configurationGate:
            return configurationGate(device: device)
        case .qaGate:
            return qaGate(device: device, project: project)
        case .jamfPreloadReadinessGate:
            return jamfPreloadReadinessGate(device: device, project: project)
        case .jamfPreloadSubmissionGate:
            return jamfPreloadSubmissionGate(device: device, project: project)
        case .jamfPreloadReconciliationGate:
            return jamfPreloadReconciliationGate(device: device, project: project)
        case .sdPlusExportGate:
            return sdPlusExportGate(device: device, project: project)
        case .shippingGate:
            return shippingGate(device: device, project: project)
        case .deliveryGate:
            return deliveryGate(device: device, project: project)
        case .completionGate:
            return completionGate(device: device, project: project, exceptions: exceptions)
        case .recordsManagementGate:
            return result(gateType, status: .pass)
        }
    }

    nonisolated private func catalogGate(device: DeploymentDevice) -> DeploymentGateValidationResult {
        result(
            .catalogGate,
            issues: [
                required(device.normalizedSerialNumber, message: "Serial number is required.", fieldKey: "device.serialNumber"),
                required(device.deviceTypeId, message: "Device type is required.", fieldKey: "device.deviceTypeId"),
                required(device.model, message: "Model is required.", fieldKey: "device.model")
            ].compactMap { $0 }
        )
    }

    nonisolated private func abmVerificationReadinessGate(
        gateType: DeploymentGateType,
        project: DeploymentProject?
    ) -> DeploymentGateValidationResult {
        guard project?.requiresABMVerification == true else {
            return result(gateType, status: .notApplicable)
        }
        return result(gateType, status: .pass)
    }

    nonisolated private func abmVerificationGate(
        device: DeploymentDevice,
        project: DeploymentProject?
    ) -> DeploymentGateValidationResult {
        guard project?.requiresABMVerification == true else {
            return result(.abmVerificationGate, status: .notApplicable)
        }

        if project?.requiresExpectedABMMDMService == true {
            guard device.abmVerificationState == .assignedToExpectedMDM else {
                return result(
                    .abmVerificationGate,
                    issues: [issue(.blocking, "Device is not assigned to the expected ABM MDM service.", fieldKey: "abm.assignedMDMServiceName")]
                )
            }
            return result(.abmVerificationGate, status: .pass)
        }

        switch device.abmVerificationState {
        case .found, .assignedToExpectedMDM:
            return result(.abmVerificationGate, status: .pass)
        case .lookupFailed, .staleSnapshot:
            return result(
                .abmVerificationGate,
                status: .warning,
                issues: [issue(.warning, "ABM verification is not current.", fieldKey: "abm.lastCheckedAt")]
            )
        default:
            return result(
                .abmVerificationGate,
                issues: [issue(.blocking, "ABM verification has not passed.", fieldKey: "abm.assignedMDMServiceName")]
            )
        }
    }

    nonisolated private func projectAssignmentGate(
        device: DeploymentDevice,
        project: DeploymentProject?
    ) -> DeploymentGateValidationResult {
        if device.projectId == nil {
            return result(
                .projectAssignmentGate,
                issues: [issue(.blocking, "Project assignment is required.", fieldKey: "device.projectId")]
            )
        }

        if project == nil {
            return result(
                .projectAssignmentGate,
                status: .warning,
                issues: [issue(.warning, "Project policy was not available for validation.", fieldKey: "device.projectId")]
            )
        }

        return result(.projectAssignmentGate, status: .pass)
    }

    nonisolated private func configurationGate(device: DeploymentDevice) -> DeploymentGateValidationResult {
        if device.profileId == nil {
            return result(
                .configurationGate,
                status: .warning,
                issues: [issue(.warning, "Profile is not set.", fieldKey: "device.profileId")]
            )
        }
        return result(.configurationGate, status: .pass)
    }

    nonisolated private func qaGate(
        device: DeploymentDevice,
        project: DeploymentProject?
    ) -> DeploymentGateValidationResult {
        guard project?.requiresQA == true else {
            return result(.qaGate, status: .notApplicable)
        }

        if let blockingReason = device.blockingReason, !blockingReason.isEmpty {
            return result(
                .qaGate,
                issues: [issue(.blocking, "QA is blocked: \(blockingReason).")]
            )
        }

        return result(.qaGate, status: .pass)
    }

    nonisolated private func jamfPreloadReadinessGate(
        device: DeploymentDevice,
        project: DeploymentProject?
    ) -> DeploymentGateValidationResult {
        guard project?.requiresJamfInventoryPreload != false else {
            return result(.jamfPreloadReadinessGate, status: .notApplicable)
        }

        return result(
            .jamfPreloadReadinessGate,
            issues: [
                required(device.normalizedSerialNumber, message: "Serial number is required for Jamf Inventory Preload.", fieldKey: "device.serialNumber"),
                required(device.deviceTypeId, message: "Device type must map to a Jamf preload type.", fieldKey: "device.deviceTypeId")
            ].compactMap { $0 }
        )
    }

    nonisolated private func jamfPreloadSubmissionGate(
        device: DeploymentDevice,
        project: DeploymentProject?
    ) -> DeploymentGateValidationResult {
        guard project?.requiresJamfInventoryPreload != false else {
            return result(.jamfPreloadSubmissionGate, status: .notApplicable)
        }

        if [.ready, .submitted, .reconciled].contains(device.jamfPreloadState) {
            return result(.jamfPreloadSubmissionGate, status: .pass)
        }

        return result(
            .jamfPreloadSubmissionGate,
            issues: [issue(.blocking, "Device is not ready for Jamf Inventory Preload submission.", fieldKey: "device.jamfPreloadState")]
        )
    }

    nonisolated private func jamfPreloadReconciliationGate(
        device: DeploymentDevice,
        project: DeploymentProject?
    ) -> DeploymentGateValidationResult {
        guard project?.requiresJamfPreloadReconciliation == true else {
            return result(.jamfPreloadReconciliationGate, status: .notApplicable)
        }

        if device.jamfReconciliationState == .reconciled || device.jamfPreloadState == .reconciled {
            return result(.jamfPreloadReconciliationGate, status: .pass)
        }

        return result(
            .jamfPreloadReconciliationGate,
            issues: [issue(.blocking, "Jamf Inventory Preload reconciliation is required.", fieldKey: "device.jamfPreloadState")]
        )
    }

    nonisolated private func sdPlusExportGate(
        device: DeploymentDevice,
        project: DeploymentProject?
    ) -> DeploymentGateValidationResult {
        guard project?.requiresSDPlusExport == true else {
            return result(.sdPlusExportGate, status: .notApplicable)
        }

        if [.ready, .exported, .complete].contains(device.sdPlusExportState) {
            return result(.sdPlusExportGate, status: .pass)
        }

        return result(
            .sdPlusExportGate,
            issues: [issue(.blocking, "SD+ export is required before this transition.", fieldKey: "device.sdPlusExportState")]
        )
    }

    nonisolated private func shippingGate(
        device: DeploymentDevice,
        project: DeploymentProject?
    ) -> DeploymentGateValidationResult {
        guard project?.requiresShipping == true else {
            return result(.shippingGate, status: .notApplicable)
        }

        if device.fedExTrackingNumber?.isEmpty == false {
            return result(.shippingGate, status: .pass)
        }

        return result(
            .shippingGate,
            issues: [issue(.blocking, "FedEx tracking is required before shipping.", fieldKey: "device.fedExTrackingNumber")]
        )
    }

    nonisolated private func deliveryGate(
        device: DeploymentDevice,
        project: DeploymentProject?
    ) -> DeploymentGateValidationResult {
        guard project?.requiresDeliveryConfirmation == true else {
            return result(.deliveryGate, status: .notApplicable)
        }

        if device.deliveryConfirmation?.isEmpty == false {
            return result(.deliveryGate, status: .pass)
        }

        return result(
            .deliveryGate,
            issues: [issue(.blocking, "Delivery confirmation is required.", fieldKey: "device.deliveryConfirmation")]
        )
    }

    nonisolated private func completionGate(
        device: DeploymentDevice,
        project: DeploymentProject?,
        exceptions: [DeploymentException]
    ) -> DeploymentGateValidationResult {
        // Completion is stricter than intermediate gates because it closes the
        // operational loop. Blocking exceptions must be resolved or waived, and
        // project policy decides whether warnings can still move forward.
        var issues: [DeploymentGateValidationIssue] = []
        let activeBlockingExceptions = exceptions.filter { exception in
            [.open, .acknowledged].contains(exception.status) &&
            [.blocking, .critical].contains(exception.severity)
        }

        if !activeBlockingExceptions.isEmpty {
            issues.append(issue(.blocking, "Open blocking exceptions must be resolved or waived before completion."))
        }

        if project?.requiresCompletionReview == true {
            issues.append(issue(.warning, "Completion review is required by project policy."))
        }

        if !issues.isEmpty {
            let hasBlockingIssue = issues.contains { [.blocking, .critical].contains($0.severity) }
            if hasBlockingIssue {
                return result(.completionGate, issues: issues)
            }
            if project?.allowsCompletionWithWarnings != true {
                issues.append(issue(.blocking, "Project policy does not allow completion with warnings."))
                return result(.completionGate, issues: issues)
            }
            return result(.completionGate, status: .warning, issues: issues)
        }

        return result(.completionGate, status: .pass)
    }

    nonisolated private func required(
        _ value: String?,
        message: String,
        fieldKey: String? = nil
    ) -> DeploymentGateValidationIssue? {
        guard let value, !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return issue(.blocking, message, fieldKey: fieldKey)
        }
        return nil
    }

    nonisolated private func issue(
        _ severity: DeploymentExceptionSeverity,
        _ message: String,
        fieldKey: String? = nil
    ) -> DeploymentGateValidationIssue {
        DeploymentGateValidationIssue(severity: severity, message: message, fieldKey: fieldKey)
    }

    nonisolated private func result(
        _ gateType: DeploymentGateType,
        status: DeploymentGateValidationStatus? = nil,
        issues: [DeploymentGateValidationIssue] = []
    ) -> DeploymentGateValidationResult {
        let resolvedStatus: DeploymentGateValidationStatus
        if let status {
            resolvedStatus = status
        } else if issues.contains(where: { [.blocking, .critical].contains($0.severity) }) {
            resolvedStatus = .blocked
        } else if issues.contains(where: { $0.severity == .warning }) {
            resolvedStatus = .warning
        } else {
            resolvedStatus = .pass
        }

        return DeploymentGateValidationResult(gateType: gateType, status: resolvedStatus, issues: issues)
    }
}

// The workflow engine bridges pure validation and persistence. It loads the
// current record context, evaluates the requested transition, applies safe
// tracker-side effects when allowed, and writes workflow/audit events for both
// allowed and blocked attempts.
nonisolated struct DeploymentWorkflowEngine: Sendable {
    let store: any DeploymentTrackerStore
    let validator: DeploymentGateValidationService
    let transitions: [DeploymentWorkflowTransitionDefinition]

    init(
        store: any DeploymentTrackerStore,
        validator: DeploymentGateValidationService = DeploymentGateValidationService(),
        transitions: [DeploymentWorkflowTransitionDefinition] = DeploymentTrackerSeedData.workflowTransitions
    ) {
        self.store = store
        self.validator = validator
        self.transitions = transitions
    }

    func transitionDevice(
        deviceId: String,
        to targetStatusId: String,
        actor: String? = nil,
        reason: String? = nil
    ) async throws -> DeploymentWorkflowTransitionResult {
        // Always fetch current records immediately before evaluating a transition
        // so decisions use the latest project policy, exception state, and
        // workflow status definitions.
        let devices = try await store.fetchDevices(includeArchived: true)
        guard let device = devices.first(where: { $0.id == deviceId }) else {
            throw DeploymentWorkflowEngineError.missingDevice(id: deviceId)
        }

        let statuses = try await store.fetchWorkflowStatuses(includeArchived: false)
        guard let targetStatus = statuses.first(where: { $0.id == targetStatusId }) else {
            throw DeploymentWorkflowEngineError.missingStatus(id: targetStatusId)
        }

        let fromStatusId = device.workflowStatusId ?? statuses.first(where: \.isDefault)?.id
        let project = try await project(for: device)
        let exceptions = try await store.fetchExceptions(deviceId: device.id, projectId: device.projectId, includeResolved: false)
        let result = evaluateTransition(
            device: device,
            project: project,
            exceptions: exceptions,
            fromStatusId: fromStatusId,
            targetStatus: targetStatus,
            reason: reason
        )

        if result.allowed {
            // Allowed transitions update the device, record a workflow event, and
            // append an audit event. The audit event stores gate metadata so a
            // technician can later explain why the transition was permitted.
            var updatedDevice = device.withWorkflowStatus(targetStatus.id, modifiedBy: actor)
            updatedDevice = applyWorkflowSideEffects(to: updatedDevice, targetStatus: targetStatus)
            try await store.saveDevice(updatedDevice)
            try await store.appendWorkflowEvent(
                DeploymentWorkflowEvent(
                    deviceId: device.id,
                    fromStatusId: fromStatusId,
                    toStatusId: targetStatus.id,
                    transitionedBy: actor,
                    gateResult: result.gateResult?.status.rawValue,
                    reason: reason
                )
            )
            try await store.appendAuditEvent(
                DeploymentAuditEvent(
                    eventType: "workflow.transition",
                    entityType: "DeploymentDevice",
                    entityId: device.id,
                    fieldKey: "device.workflowStatusId",
                    oldValue: fromStatusId,
                    newValue: targetStatus.id,
                    actor: actor,
                    metadata: auditMetadata(result)
                )
            )
        } else {
            // Blocked transitions still create an audit trail. This is important
            // for diagnosing repeated gate failures or policy confusion without
            // changing the device's workflow status.
            try await store.appendAuditEvent(
                DeploymentAuditEvent(
                    eventType: "workflow.transition.blocked",
                    entityType: "DeploymentDevice",
                    entityId: device.id,
                    fieldKey: "device.workflowStatusId",
                    oldValue: fromStatusId,
                    newValue: targetStatus.id,
                    actor: actor,
                    metadata: auditMetadata(result)
                )
            )
        }

        return result
    }

    func evaluateTransition(
        device: DeploymentDevice,
        project: DeploymentProject?,
        exceptions: [DeploymentException] = [],
        fromStatusId: String?,
        targetStatus: DeploymentWorkflowStatusDefinition,
        reason: String? = nil
    ) -> DeploymentWorkflowTransitionResult {
        // A transition must be explicitly defined from the current status to the
        // target status. Missing definitions are treated as blocked movement, not
        // as an implicit free transition.
        guard let fromStatusId,
              let transition = transitions.first(where: { $0.fromStatusId == fromStatusId && $0.toStatusId == targetStatus.id }) else {
            let issue = DeploymentGateValidationIssue(
                severity: .blocking,
                message: "Transition is not allowed from the current workflow status.",
                fieldKey: "device.workflowStatusId"
            )
            return DeploymentWorkflowTransitionResult(
                allowed: false,
                fromStatusId: fromStatusId,
                toStatusId: targetStatus.id,
                gateResult: nil,
                issues: [issue]
            )
        }

        var issues: [DeploymentGateValidationIssue] = []
        if transition.requiresReason || targetStatus.requiresReason {
            // Some workflow states require an operator reason for audit clarity,
            // such as exceptions, returns, rollback, or final completion review.
            if reason?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty != false {
                issues.append(
                    DeploymentGateValidationIssue(
                        severity: .blocking,
                        message: "A reason is required for this workflow transition.",
                        fieldKey: "device.workflowStatusId"
                    )
                )
            }
        }

        let gateResult = transition.gateType.map {
            validator.validate($0, device: device, project: project, exceptions: exceptions)
        }
        if let gateResult {
            issues.append(contentsOf: gateResult.issues)
        }

        let allowed = issues.allSatisfy { ![.blocking, .critical].contains($0.severity) } &&
            (gateResult?.allowsForwardMovement ?? true)

        return DeploymentWorkflowTransitionResult(
            allowed: allowed,
            fromStatusId: fromStatusId,
            toStatusId: targetStatus.id,
            gateResult: gateResult,
            issues: issues
        )
    }

    nonisolated private func applyWorkflowSideEffects(
        to device: DeploymentDevice,
        targetStatus: DeploymentWorkflowStatusDefinition
    ) -> DeploymentDevice {
        // Status definitions may carry behavior tags that synchronize related
        // local integration states. These side effects remain local Tracker
        // state; Jamf, SD+, ABM, and shipping systems are not mutated here.
        var copy = device

        switch targetStatus.systemBehaviorTag {
        case "jamfPreload.ready":
            copy.jamfPreloadState = .ready
        case "jamfPreload.submitted":
            copy.jamfPreloadState = .submitted
        case "jamfPreload.failed":
            copy.jamfPreloadState = .failed
        case "jamfPreload.reconciled":
            copy.jamfPreloadState = .reconciled
            copy.jamfReconciliationState = .reconciled
        case "sdplus.ready":
            copy.sdPlusExportState = .ready
        case "sdplus.exported":
            copy.sdPlusExportState = .exported
        case "shipping.ready":
            copy.shippingState = .ready
        case "shipping.shipped":
            copy.shippingState = .submitted
        case "shipping.delivered":
            copy.shippingState = .complete
        case "records.archived":
            copy = copy.withLifecycleState(.archived)
        default:
            break
        }

        return copy
    }

    private func project(for device: DeploymentDevice) async throws -> DeploymentProject? {
        // Project policy is optional. Devices without a project can still be
        // validated, but project-dependent gates may warn or block accordingly.
        guard let projectId = device.projectId else {
            return nil
        }
        let projects = try await store.fetchProjects(includeArchived: false)
        return projects.first { $0.id == projectId }
    }

    nonisolated private func auditMetadata(_ result: DeploymentWorkflowTransitionResult) -> [String: String] {
        // Audit metadata is compact by design. The event gets enough information
        // to reconstruct the decision without embedding full device or project
        // snapshots into every workflow event.
        var metadata: [String: String] = [
            "allowed": result.allowed ? "true" : "false",
            "issueCount": "\(result.issues.count)"
        ]
        if let gateResult = result.gateResult {
            metadata["gate"] = gateResult.gateType.rawValue
            metadata["gateResult"] = gateResult.status.rawValue
        }
        if !result.issues.isEmpty {
            metadata["issues"] = result.issues.map(\.message).joined(separator: " | ")
        }
        return metadata
    }
}
