import Foundation

// MARK: - Workbench projection service
//
// This service transforms raw devices plus field definitions into the exact rows
// and cells that the Workbench renders. It centralizes filtering, sorting,
// reference value display names, derived values, validation messages, and CSV
// preview behavior so UI views do not duplicate formatting logic.
nonisolated struct DeploymentWorkbenchProjectionService: Sendable {
    func makeProjection(
        devices: [DeploymentDevice],
        fieldDefinitions: [DeploymentFieldDefinition],
        layout: WorkbenchLayout,
        referenceValues: [DeploymentReferenceValue] = [],
        filters: [DeploymentWorkbenchFilter] = [],
        sort: DeploymentWorkbenchSort? = nil
    ) -> DeploymentWorkbenchProjection {
        // The active layout decides which columns are visible. The projection
        // service then renders all matching devices into those columns.
        let catalogService = DeploymentFieldCatalogService(definitions: fieldDefinitions)
        let columns = catalogService.visibleColumns(for: layout)
        let referenceValuesById = Dictionary(uniqueKeysWithValues: referenceValues.map { ($0.id, $0.displayName) })

        let filteredDevices = devices.filter { device in
            filters.allSatisfy { filter in
                let query = filter.query.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !query.isEmpty else {
                    return true
                }
                if filter.fieldKey == "*" {
                    return fieldDefinitions.contains { definition in
                        displayValue(
                            for: definition.fieldKey,
                            device: device,
                            referenceValuesById: referenceValuesById
                        )
                        .localizedCaseInsensitiveContains(query)
                    }
                }
                let value = displayValue(
                    for: filter.fieldKey,
                    device: device,
                    referenceValuesById: referenceValuesById
                )
                return value.localizedCaseInsensitiveContains(query)
            }
        }

        let sortedDevices = sorted(filteredDevices, by: sort, referenceValuesById: referenceValuesById)
        let rows = sortedDevices.map { device in
            DeploymentWorkbenchRowProjection(
                id: device.id,
                device: device,
                cells: columns.map { column in
                    let displayValue = displayValue(
                        for: column.field.fieldKey,
                        device: device,
                        referenceValuesById: referenceValuesById
                    )
                    return DeploymentWorkbenchCellProjection(
                        fieldKey: column.field.fieldKey,
                        displayValue: displayValue,
                        rawValue: rawValue(for: column.field.fieldKey, device: device),
                        isEditable: column.field.editable
                    )
                }
            )
        }

        return DeploymentWorkbenchProjection(
            layout: layout,
            columns: columns,
            rows: rows,
            hiddenFieldCount: hiddenFieldCount(in: layout, fieldDefinitions: fieldDefinitions),
            validationMessages: validationMessages(fieldDefinitions: fieldDefinitions, layout: layout)
        )
    }

    func displayValue(
        for fieldKey: String,
        device: DeploymentDevice,
        referenceValuesById: [String: String] = [:]
    ) -> String {
        switch fieldKey {
        case "device.serialNumber":
            return device.serialNumber
        case "device.assetTag":
            return device.assetTag ?? ""
        case "device.projectId":
            return referenceDisplay(for: device.projectId, referenceValuesById: referenceValuesById)
        case "device.deviceTypeId":
            return referenceDisplay(for: device.deviceTypeId, referenceValuesById: referenceValuesById)
        case "device.model":
            return device.model ?? ""
        case "device.workflowStatusId":
            return referenceDisplay(for: device.workflowStatusId, referenceValuesById: referenceValuesById)
        case "device.geoLocation":
            return [device.geoId, device.locationId]
                .compactMap { id in
                    guard let id else {
                        return nil
                    }
                    let value = referenceDisplay(for: id, referenceValuesById: referenceValuesById)
                    return value.isEmpty ? nil : value
                }
                .joined(separator: " / ")
        case "device.profileId":
            return referenceDisplay(for: device.profileId, referenceValuesById: referenceValuesById)
        case "device.assignedUser":
            return device.assignedUser ?? ""
        case "device.jamfPreloadState":
            return displayName(for: device.jamfPreloadState)
        case "device.sdPlusExportState":
            return displayName(for: device.sdPlusExportState)
        case "device.jamfEnrollmentState":
            return displayName(for: device.jamfEnrollmentState)
        case "device.poNumber":
            return device.poNumber ?? ""
        case "device.orderNumber":
            return device.orderNumber ?? ""
        case "device.ticketNumber":
            return device.ticketNumber ?? ""
        case "device.replacingSerialNumber":
            return device.replacementForSerialNumber ?? ""
        case "device.fedExTrackingNumber":
            return device.fedExTrackingNumber ?? ""
        case "device.returnTrackingNumber":
            return device.returnTrackingNumber ?? ""
        case "device.deliveryConfirmation":
            return device.deliveryConfirmation ?? ""
        case "device.gmEmailed":
            return device.gmEmailed ? "Yes" : "No"
        case "device.comments":
            return device.comments ?? ""
        case "device.notes":
            return device.notes ?? ""
        case "abm.assignedMDMServiceName":
            return device.abmVerificationState == .unknown ? "Not checked" : displayName(for: device.abmVerificationState)
        case "abm.lastCheckedAt":
            return device.latestABMSnapshotId == nil ? "Never" : "Snapshot recorded"
        case "catalog.marketingName":
            return device.model ?? ""
        case "derived.blockingExceptionCount":
            return device.blockingReason == nil ? "0" : "1"
        default:
            return ""
        }
    }

    nonisolated private func rawValue(for fieldKey: String, device: DeploymentDevice) -> String {
        switch fieldKey {
        case "device.serialNumber":
            return device.normalizedSerialNumber
        case "device.assetTag":
            return device.assetTag ?? ""
        case "device.projectId":
            return device.projectId ?? ""
        case "device.deviceTypeId":
            return device.deviceTypeId ?? ""
        case "device.model":
            return device.model ?? ""
        case "device.workflowStatusId":
            return device.workflowStatusId ?? ""
        case "device.geoLocation":
            return [device.geoId, device.locationId].compactMap { $0 }.joined(separator: "/")
        case "device.profileId":
            return device.profileId ?? ""
        case "device.assignedUser":
            return device.assignedUser ?? ""
        case "device.jamfPreloadState":
            return device.jamfPreloadState.rawValue
        case "device.sdPlusExportState":
            return device.sdPlusExportState.rawValue
        case "device.jamfEnrollmentState":
            return device.jamfEnrollmentState.rawValue
        case "device.poNumber":
            return device.poNumber ?? ""
        case "device.orderNumber":
            return device.orderNumber ?? ""
        case "device.ticketNumber":
            return device.ticketNumber ?? ""
        case "device.replacingSerialNumber":
            return device.replacementForSerialNumber ?? ""
        case "device.fedExTrackingNumber":
            return device.fedExTrackingNumber ?? ""
        case "device.returnTrackingNumber":
            return device.returnTrackingNumber ?? ""
        case "device.deliveryConfirmation":
            return device.deliveryConfirmation ?? ""
        case "device.gmEmailed":
            return device.gmEmailed ? "true" : "false"
        case "device.comments":
            return device.comments ?? ""
        case "device.notes":
            return device.notes ?? ""
        case "abm.assignedMDMServiceName":
            return device.abmVerificationState.rawValue
        case "abm.lastCheckedAt":
            return device.latestABMSnapshotId ?? ""
        case "catalog.marketingName":
            return device.model ?? ""
        case "derived.blockingExceptionCount":
            return device.blockingReason == nil ? "0" : "1"
        default:
            return ""
        }
    }

    nonisolated private func sorted(
        _ devices: [DeploymentDevice],
        by sort: DeploymentWorkbenchSort?,
        referenceValuesById: [String: String]
    ) -> [DeploymentDevice] {
        guard let sort else {
            return devices.sorted {
                $0.normalizedSerialNumber.localizedCaseInsensitiveCompare($1.normalizedSerialNumber) == .orderedAscending
            }
        }

        return devices.sorted { lhs, rhs in
            let lhsValue = displayValue(for: sort.fieldKey, device: lhs, referenceValuesById: referenceValuesById)
            let rhsValue = displayValue(for: sort.fieldKey, device: rhs, referenceValuesById: referenceValuesById)
            let comparison = lhsValue.localizedCaseInsensitiveCompare(rhsValue)
            switch sort.direction {
            case .ascending:
                return comparison == .orderedAscending
            case .descending:
                return comparison == .orderedDescending
            }
        }
    }

    nonisolated private func hiddenFieldCount(
        in layout: WorkbenchLayout,
        fieldDefinitions: [DeploymentFieldDefinition]
    ) -> Int {
        let visibleFieldKeys = Set(layout.columns.filter(\.visible).map(\.fieldKey))
        return fieldDefinitions.filter { !visibleFieldKeys.contains($0.fieldKey) }.count
    }

    nonisolated private func validationMessages(
        fieldDefinitions: [DeploymentFieldDefinition],
        layout: WorkbenchLayout
    ) -> [String] {
        var messages: [String] = []
        let fieldKeys = Set(fieldDefinitions.map(\.fieldKey))
        let unknownLayoutFields = layout.columns
            .filter { !fieldKeys.contains($0.fieldKey) }
            .map(\.fieldKey)

        if !unknownLayoutFields.isEmpty {
            messages.append("Layout contains unknown fields: \(unknownLayoutFields.joined(separator: ", ")).")
        }

        let firstVisibleField = layout.columns
            .filter(\.visible)
            .sorted { $0.order < $1.order }
            .first?.fieldKey
        if firstVisibleField != "device.serialNumber" {
            messages.append("Workbook Default expects Serial to remain the first visible column.")
        }

        if let statusField = fieldDefinitions.first(where: { $0.fieldKey == "device.workflowStatusId" }),
           statusField.editorType != "referenceDropdown" || statusField.systemBehaviorTag != "workflowStatus" {
            messages.append("Status must remain tied to workflow transition behavior.")
        }

        return messages
    }

    nonisolated private func referenceDisplay(
        for id: String?,
        referenceValuesById: [String: String],
        emptyValue: String = ""
    ) -> String {
        guard let id, !id.isEmpty else {
            return emptyValue
        }
        return referenceValuesById[id] ?? id
    }

    nonisolated private func displayName(for state: DeploymentIntegrationState) -> String {
        switch state {
        case .unknown:
            return "Unknown"
        case .pending:
            return "Pending"
        case .ready:
            return "Ready"
        case .submitted:
            return "Submitted"
        case .failed:
            return "Failed"
        case .reconciled:
            return "Reconciled"
        case .exported:
            return "Exported"
        case .complete:
            return "Complete"
        }
    }

    nonisolated private func displayName(for state: DeploymentABMVerificationState) -> String {
        switch state {
        case .unknown:
            return "Unknown"
        case .lookupPending:
            return "Lookup Pending"
        case .found:
            return "Found"
        case .notFound:
            return "Not Found"
        case .assignedToExpectedMDM:
            return "Expected MDM"
        case .assignedToDifferentMDM:
            return "Different MDM"
        case .unassigned:
            return "Unassigned"
        case .releasedOrUnavailable:
            return "Released or Unavailable"
        case .snapshotConflict:
            return "Snapshot Conflict"
        case .lookupFailed:
            return "Lookup Failed"
        case .staleSnapshot:
            return "Stale Snapshot"
        }
    }
}
