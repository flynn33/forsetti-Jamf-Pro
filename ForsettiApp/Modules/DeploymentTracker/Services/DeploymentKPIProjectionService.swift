import Foundation

// MARK: - Dashboard KPI projection service
//
// The Dashboard renders projections, not raw model arrays. This service converts
// active devices, active projects, workflow statuses, and reference values into
// operational totals, integration health rings, status indicators, and device
// type distribution data.
nonisolated struct DeploymentKPIProjectionService: Sendable {
    func makeDashboardProjection(
        devices: [DeploymentDevice],
        projects: [DeploymentProject],
        statuses: [DeploymentWorkflowStatusDefinition],
        referenceValues: [DeploymentReferenceValue],
        generatedAt: Date = Date()
    ) -> DeploymentDashboardProjection {
        // Archived and pending-deletion records remain available to records
        // management, but they are excluded from active operational KPIs.
        let activeDevices = devices.filter { $0.recordLifecycleState == .active }
        let activeProjects = projects.filter { $0.recordLifecycleState == .active }
        let total = activeDevices.count
        let statusById = Dictionary(uniqueKeysWithValues: statuses.map { ($0.id, $0) })

        return DeploymentDashboardProjection(
            generatedAt: generatedAt,
            operationalTotals: operationalTotals(
                devices: activeDevices,
                projects: activeProjects,
                statusById: statusById
            ),
            statusIndicators: statusIndicators(
                devices: activeDevices,
                statuses: statuses
            ),
            deviceTypeDistribution: deviceTypeDistribution(
                devices: activeDevices,
                referenceValues: referenceValues
            ),
            integrationHealth: integrationHealth(
                devices: activeDevices,
                total: total
            )
        )
    }

    private func operationalTotals(
        devices: [DeploymentDevice],
        projects: [DeploymentProject],
        statusById: [String: DeploymentWorkflowStatusDefinition]
    ) -> [DeploymentKPIProjection] {
        let total = devices.count
        let inProgress = devices.filter { device in
            guard let status = device.workflowStatusId.flatMap({ statusById[$0] }) else {
                return device.recordLifecycleState == .active
            }
            return !status.isTerminal
        }.count
        let readyForJamfPreload = count(devices, behaviorTag: "jamfPreload.ready", statusById: statusById)
        let readyForSDPlusExport = count(devices, behaviorTag: "sdplus.ready", statusById: statusById)
        let shipped = count(devices, behaviorTag: "shipping.shipped", statusById: statusById)
        let delivered = count(devices, behaviorTag: "shipping.delivered", statusById: statusById)
        let complete = count(devices, behaviorTag: "completion.complete", statusById: statusById)
        let blocked = devices.filter { device in
            device.blockingReason != nil || device.workflowStatusId.flatMap { statusById[$0]?.isBlockingState } == true
        }.count

        return [
            kpi("inventory-total", "Total Inventory", total, category: "Inventory", total: total, color: .blue),
            kpi("active-projects", "Active Projects", projects.count, category: "Projects", total: max(projects.count, 1), color: .purple),
            kpi("in-progress", "In Progress", inProgress, category: "Workflow", total: total, color: .blue),
            kpi("ready-jamf-preload", "Ready for Jamf Preload", readyForJamfPreload, category: "Jamf Preload", total: total, color: .orange),
            kpi("ready-sdplus-export", "Ready for SD+ Export", readyForSDPlusExport, category: "SD+ Export", total: total, color: .green),
            kpi("shipped", "Shipped", shipped, category: "Shipping", total: total, color: .purple),
            kpi("delivered", "Delivered", delivered, category: "Shipping", total: total, color: .green),
            kpi("blocked", "Blocked", blocked, category: "Exceptions", total: total, color: .red),
            kpi("complete", "Complete", complete, category: "Completion", total: total, color: .green)
        ]
    }

    private func statusIndicators(
        devices: [DeploymentDevice],
        statuses: [DeploymentWorkflowStatusDefinition]
    ) -> [DeploymentKPIProjection] {
        let total = devices.count
        let countsByStatusId = Dictionary(grouping: devices.compactMap(\.workflowStatusId), by: { $0 })
            .mapValues(\.count)

        return statuses
            .filter { countsByStatusId[$0.id, default: 0] > 0 }
            .sorted { $0.sortOrder < $1.sortOrder }
            .map { status in
                let value = countsByStatusId[status.id, default: 0]
                let color: DeploymentKPIColor = status.isBlockingState ? .red : (status.isTerminal ? .green : .blue)
                return kpi(
                    "status-\(status.id)",
                    status.displayName,
                    value,
                    category: status.statusCategory,
                    total: total,
                    color: color
                )
            }
    }

    private func deviceTypeDistribution(
        devices: [DeploymentDevice],
        referenceValues: [DeploymentReferenceValue]
    ) -> [DeploymentKPIProjection] {
        let total = devices.count
        let namesById = Dictionary(uniqueKeysWithValues: referenceValues.map { ($0.id, $0.displayName) })
        let countsByType = Dictionary(grouping: devices.map { $0.deviceTypeId ?? "unknown" }, by: { $0 }).mapValues(\.count)

        return countsByType.keys.sorted {
            displayName(for: $0, namesById: namesById).localizedCaseInsensitiveCompare(displayName(for: $1, namesById: namesById)) == .orderedAscending
        }
        .map { typeId in
            let display = displayName(for: typeId, namesById: namesById)
            return kpi(
                "device-type-\(typeId)",
                display,
                countsByType[typeId, default: 0],
                category: "Device Type",
                total: total,
                color: color(forDeviceTypeId: typeId)
            )
        }
    }

    private func integrationHealth(
        devices: [DeploymentDevice],
        total: Int
    ) -> [DeploymentKPIProjection] {
        [
            kpi(
                "jamf-preload-gauge",
                "Jamf Preload",
                devices.filter { [.submitted, .reconciled, .complete].contains($0.jamfPreloadState) }.count,
                category: "Integration",
                total: total,
                color: .orange
            ),
            kpi(
                "abm-verification-ring",
                "ABM Verification",
                devices.filter { [.found, .assignedToExpectedMDM].contains($0.abmVerificationState) }.count,
                category: "Integration",
                total: total,
                color: .blue
            ),
            kpi(
                "sdplus-export-gauge",
                "SD+ Export",
                devices.filter { [.exported, .complete].contains($0.sdPlusExportState) }.count,
                category: "Integration",
                total: total,
                color: .green
            ),
            kpi(
                "shipment-progress",
                "Shipment Progress",
                devices.filter { [.submitted, .complete].contains($0.shippingState) || $0.fedExTrackingNumber != nil }.count,
                category: "Integration",
                total: total,
                color: .purple
            ),
            kpi(
                "exception-heat-map",
                "Exceptions",
                devices.filter { $0.blockingReason != nil }.count,
                category: "Integration",
                total: total,
                color: .red
            )
        ]
    }

    private func count(
        _ devices: [DeploymentDevice],
        behaviorTag: String,
        statusById: [String: DeploymentWorkflowStatusDefinition]
    ) -> Int {
        devices.filter { device in
            device.workflowStatusId.flatMap { statusById[$0]?.systemBehaviorTag } == behaviorTag
        }.count
    }

    private func kpi(
        _ id: String,
        _ displayName: String,
        _ value: Int,
        category: String,
        total: Int,
        color: DeploymentKPIColor
    ) -> DeploymentKPIProjection {
        DeploymentKPIProjection(
            id: id,
            displayName: displayName,
            value: value,
            category: category,
            total: total,
            color: color,
            accessibilitySummary: total > 0 ? "\(displayName): \(value) of \(total)" : "\(displayName): \(value)"
        )
    }

    private func displayName(for typeId: String, namesById: [String: String]) -> String {
        if typeId == "unknown" {
            return "Unknown"
        }
        return namesById[typeId] ?? typeId
    }

    private func color(forDeviceTypeId typeId: String) -> DeploymentKPIColor {
        if typeId.contains("macbook") || typeId.contains("mac") {
            return .blue
        }
        if typeId.contains("ipad") {
            return .green
        }
        if typeId.contains("iphone") {
            return .orange
        }
        return .gray
    }
}
