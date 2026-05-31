import Foundation

// MARK: - Jamf Inventory Preload validator
//
// Validation runs before upload and before preview messaging. It checks that a
// template exists, required fields are present, and blocking local exceptions
// are handled before the module attempts to mutate Jamf Pro.
nonisolated struct JamfInventoryPreloadValidator: Sendable {
    let renderer: JamfInventoryPreloadCSVRenderer

    init(renderer: JamfInventoryPreloadCSVRenderer = JamfInventoryPreloadCSVRenderer()) {
        self.renderer = renderer
    }

    func validate(
        devices: [DeploymentDevice],
        template: JamfInventoryPreloadTemplate?,
        referenceValues: [DeploymentReferenceValue],
        exceptions: [DeploymentException] = []
    ) -> JamfInventoryPreloadValidationResult {
        // Missing template is a hard block because the renderer cannot know
        // which Jamf columns to produce.
        guard let template else {
            return JamfInventoryPreloadValidationResult(
                deviceCount: devices.count,
                readyDeviceIds: [],
                issues: [
                    JamfInventoryPreloadValidationIssue(
                        severity: .blocking,
                        message: "A Jamf Inventory Preload template must be selected."
                    )
                ],
                requiredPrivileges: JamfInventoryPreloadPrivilege.upload
            )
        }

        var issues: [JamfInventoryPreloadValidationIssue] = []
        if template.columns.isEmpty {
            issues.append(
                JamfInventoryPreloadValidationIssue(
                    severity: .blocking,
                    message: "The selected Jamf Inventory Preload template has no columns."
                )
            )
        }

        var seenSerials: [String: String] = [:]
        for device in devices {
            if device.recordLifecycleState != .active {
                issues.append(issue(device, fieldKey: nil, severity: .blocking, "Only active records can be submitted to Jamf Inventory Preload."))
            }

            if device.normalizedSerialNumber.isEmpty {
                issues.append(issue(device, fieldKey: "device.serialNumber", severity: .blocking, "Serial number is required."))
            } else if let existingDeviceId = seenSerials[device.normalizedSerialNumber], existingDeviceId != device.id {
                issues.append(issue(device, fieldKey: "device.serialNumber", severity: .blocking, "Duplicate serial number in selected batch."))
            } else {
                seenSerials[device.normalizedSerialNumber] = device.id
            }

            let jamfDeviceType = renderer.jamfPreloadDeviceType(for: device, referenceValues: referenceValues)
            if jamfDeviceType != "Computer" && jamfDeviceType != "Mobile Device" {
                issues.append(issue(device, fieldKey: "device.deviceTypeId", severity: .blocking, "Device type must map to Computer or Mobile Device for Jamf Inventory Preload."))
            }

            for column in template.columns where column.required {
                let value = renderer.value(for: column.sourceField, device: device, referenceValues: referenceValues)
                if value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    issues.append(issue(device, fieldKey: column.sourceField, severity: .blocking, "\(column.jamfColumn) is required."))
                }
            }
        }

        for exception in exceptions where [.open, .acknowledged].contains(exception.status) && [.blocking, .critical].contains(exception.severity) {
            issues.append(
                JamfInventoryPreloadValidationIssue(
                    deviceId: exception.deviceId,
                    serialNumber: devices.first { $0.id == exception.deviceId }?.serialNumber,
                    severity: .blocking,
                    message: "Unresolved blocking exception prevents Jamf Inventory Preload submission: \(exception.summary)"
                )
            )
        }

        if template.columns.contains(where: { ["device.assignedUser", "device.assignedUserEmail"].contains($0.sourceField) }) {
            issues.append(
                JamfInventoryPreloadValidationIssue(
                    severity: .warning,
                    message: "Username or email fields may create or update Jamf Pro user records during CSV upload."
                )
            )
        }

        let blockedDeviceIds = Set(issues.compactMap { issue -> String? in
            guard [.blocking, .critical].contains(issue.severity) else {
                return nil
            }
            return issue.deviceId
        })
        let readyDeviceIds = devices
            .filter { !blockedDeviceIds.contains($0.id) }
            .map(\.id)

        return JamfInventoryPreloadValidationResult(
            deviceCount: devices.count,
            readyDeviceIds: readyDeviceIds,
            issues: issues,
            requiredPrivileges: template.requiredPrivileges
        )
    }

    nonisolated private func issue(
        _ device: DeploymentDevice,
        fieldKey: String?,
        severity: DeploymentExceptionSeverity,
        _ message: String
    ) -> JamfInventoryPreloadValidationIssue {
        JamfInventoryPreloadValidationIssue(
            deviceId: device.id,
            serialNumber: device.serialNumber,
            fieldKey: fieldKey,
            severity: severity,
            message: message
        )
    }
}
