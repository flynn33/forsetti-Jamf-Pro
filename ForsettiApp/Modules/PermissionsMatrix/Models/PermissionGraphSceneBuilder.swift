import Foundation

// Builds a `PermissionGraphSceneSnapshot` from the existing Permissions Helper
// selection (action / privilege / endpoint). Presentation-only: reads matrix
// records + the runtime comparison result, mutates nothing, never calls Jamf.
// Produces the full hierarchy spine selected → privilege groups → privileges →
// endpoint families → endpoints, plus runtime/risk overlays, then lays it out.
struct PermissionGraphSceneBuilder {

    private typealias Synth = PermissionGraphHierarchySynthesis
    private let layout = PermissionGraphLayeredLayoutEngine()

    // MARK: - Selected action

    func snapshot(
        for action: PermissionsMatrixAction,
        overlays: [MDMCommandOverlay] = [],
        comparison: PermissionsMatrixComparisonResult? = nil
    ) -> PermissionGraphSceneSnapshot {
        var nodes: [PermissionGraphNode] = []
        var edges: [PermissionGraphEdge] = []
        var groups: [PermissionGraphGroup] = []
        var warnings: [PermissionGraphWarning] = []
        var seen = Set<String>()

        let slugBase = Synth.slug(action.commandID)
        let selID = "selected:\(slugBase)"
        nodes.append(PermissionGraphNode(
            id: selID, kind: .selected_item, layer: .selectedItem,
            title: action.resolvedDisplayName, subtitle: action.module, detail: action.commandID,
            surface: .mixed, runtimeStatus: .notChecked, riskFlags: actionRiskFlags(action),
            parentID: nil, sourceRecordID: action.commandID, radius: 0.72,
            accessibilityLabel: "Selected command, \(action.resolvedDisplayName)"
        ))
        seen.insert(selID)

        // --- Privilege groups & privileges ---
        var bucketOrder: [String] = []
        var bucketTitle: [String: String] = [:]
        var bucketRisk: [String: [PermissionGraphRiskFlag]] = [:]
        var bucketNames: [String: [String]] = [:]
        var bucketAlt: [String: Bool] = [:]
        var bucketMode: [String: String?] = [:]

        for requirement in action.requiredPrivilegeRequirements {
            let isOverlay = requirement.mode == "optional_runtime_overlay"
            for name in names(for: requirement, action: action) {
                let b = Synth.bucket(privilege: name, action: action, isOverlay: isOverlay)
                if bucketNames[b.key] == nil {
                    bucketOrder.append(b.key)
                    bucketTitle[b.key] = b.title
                    bucketRisk[b.key] = b.risk
                    bucketNames[b.key] = []
                    bucketAlt[b.key] = isOverlay
                    bucketMode[b.key] = requirement.modeDescription
                }
                if bucketNames[b.key]?.contains(name) == false { bucketNames[b.key]?.append(name) }
            }
        }
        bucketOrder.sort { Synth.groupOrderRank($0) < Synth.groupOrderRank($1) }

        for (gIndex, key) in bucketOrder.enumerated() {
            let groupID = "group:\(slugBase):\(key)"
            guard seen.insert(groupID).inserted else { continue }
            let names = (bucketNames[key] ?? []).sorted()
            let childStatuses = names.map { runtimeStatus(forPrivilege: $0, comparison: comparison) }
            let groupStatus = rollup(childStatuses)
            let isPrimary = gIndex == 0
            nodes.append(PermissionGraphNode(
                id: groupID, kind: .privilege_group, layer: .privilegeGroups,
                title: bucketTitle[key] ?? "Required Privileges", subtitle: bucketMode[key] ?? nil, detail: nil,
                surface: .mixed, runtimeStatus: groupStatus, riskFlags: bucketRisk[key] ?? [],
                parentID: selID, sourceRecordID: nil, radius: 0.55,
                accessibilityLabel: "Privilege group, \(bucketTitle[key] ?? ""), \(statusWord(groupStatus))"
            ))
            edges.append(edge(selID, groupID, .requires, status: groupStatus, selectedPath: isPrimary,
                              a11y: "\(action.resolvedDisplayName) requires \(bucketTitle[key] ?? "")"))

            var memberIDs: [String] = []
            for name in names {
                let pid = "priv:\(slugBase):\(key):\(Synth.slug(name))"
                guard seen.insert(pid).inserted else { continue }
                let st = runtimeStatus(forPrivilege: name, comparison: comparison)
                var risk = bucketRisk[key] ?? []
                if (bucketAlt[key] ?? false) { risk.append(.tenant_verify) }
                nodes.append(PermissionGraphNode(
                    id: pid, kind: .privilege, layer: .privileges,
                    title: name, subtitle: "Required privilege", detail: name,
                    surface: .mixed, runtimeStatus: st, riskFlags: risk,
                    parentID: groupID, sourceRecordID: name, radius: 0.4,
                    accessibilityLabel: "Privilege, \(name), \(statusWord(st))"
                ))
                edges.append(edge(groupID, pid, .contains, status: st, selectedPath: isPrimary,
                                  a11y: "\(bucketTitle[key] ?? "") contains \(name)"))
                memberIDs.append(pid)
            }
            groups.append(PermissionGraphGroup(id: groupID, title: bucketTitle[key] ?? "Required Privileges",
                                               layer: .privilegeGroups, memberNodeIDs: memberIDs))
        }

        // --- Endpoint families & endpoints ---
        var famOrder: [String] = []
        var famTitle: [String: String] = [:]
        var famSurface: [String: PermissionGraphSurface] = [:]
        var famRisk: [String: [PermissionGraphRiskFlag]] = [:]
        var famEndpoints: [String: [ActionEndpoint]] = [:]
        for endpoint in action.endpoints {
            let f = Synth.family(path: endpoint.path, isClassic: endpoint.isClassic, catalogFamily: nil)
            if famEndpoints[f.key] == nil {
                famOrder.append(f.key); famTitle[f.key] = f.title; famSurface[f.key] = f.surface; famRisk[f.key] = f.risk; famEndpoints[f.key] = []
            }
            famEndpoints[f.key]?.append(endpoint)
        }
        famOrder.sort { (famSurface[$0]?.orderRank ?? 9, $0) < (famSurface[$1]?.orderRank ?? 9, $1) }

        var familyNodeID: [String: String] = [:]
        for (fIndex, key) in famOrder.enumerated() {
            let famID = "family:\(slugBase):\(key)"
            guard seen.insert(famID).inserted else { continue }
            familyNodeID[key] = famID
            let surface = famSurface[key] ?? .modern
            let isPrimary = fIndex == 0
            let famStatus: PermissionGraphRuntimeStatus = surface == .classic ? .legacyFallback : .notChecked
            nodes.append(PermissionGraphNode(
                id: famID, kind: .endpoint_family, layer: .endpointFamilies,
                title: famTitle[key] ?? "API", subtitle: surfaceLabel(surface), detail: nil,
                surface: surface, runtimeStatus: famStatus, riskFlags: famRisk[key] ?? [],
                parentID: selID, sourceRecordID: nil, radius: 0.5,
                accessibilityLabel: "Endpoint family, \(famTitle[key] ?? ""), \(surfaceLabel(surface))"
            ))
            edges.append(edge(selID, famID, .implemented_by, status: famStatus, selectedPath: isPrimary,
                              a11y: "\(action.resolvedDisplayName) served by \(famTitle[key] ?? "")"))

            let bundleID = (famEndpoints[key]?.count ?? 0) > 5 ? "bundle:\(famID)" : nil
            for endpoint in (famEndpoints[key] ?? []) {
                let full = "\(endpoint.method) \(endpoint.path)"
                let epID = "endpoint:\(Synth.slug(full))"
                guard seen.insert(epID).inserted else { continue }
                let st: PermissionGraphRuntimeStatus = endpoint.isClassic ? .legacyFallback : .notChecked
                nodes.append(PermissionGraphNode(
                    id: epID, kind: .endpoint, layer: .endpoints,
                    title: Synth.shortPath(method: endpoint.method, path: endpoint.path),
                    subtitle: surfaceLabel(surface), detail: full,
                    surface: surface, runtimeStatus: st, riskFlags: famRisk[key] ?? [],
                    parentID: famID, sourceRecordID: endpoint.path, radius: 0.32,
                    accessibilityLabel: "Endpoint, \(full)"
                ))
                edges.append(edge(famID, epID, .contains, status: st, selectedPath: isPrimary, bundleID: bundleID,
                                  a11y: "\(famTitle[key] ?? "") contains \(full)"))
            }
        }
        // Modern → Classic fallback edge when both surfaces are present.
        if let classicID = famOrder.first(where: { famSurface[$0] == .classic }).flatMap({ familyNodeID[$0] }),
           let modernKey = famOrder.first(where: { famSurface[$0] == .modern || famSurface[$0] == .ddm }),
           let modernID = familyNodeID[modernKey] {
            edges.append(edge(modernID, classicID, .fallback_to, status: .legacyFallback, selectedPath: false,
                              a11y: "Classic API fallback path"))
        }

        // --- MDM command-type overlays (only when an /mdm/commands endpoint is present) ---
        if action.endpoints.contains(where: { $0.path.lowercased().contains("/mdm/commands") }), overlays.isEmpty == false,
           let mdmFamID = familyNodeID["mdm"] {
            for overlay in overlays.prefix(8) {
                let ovID = "overlay:\(Synth.slug(overlay.commandType))"
                guard seen.insert(ovID).inserted else { continue }
                nodes.append(PermissionGraphNode(
                    id: ovID, kind: .command_overlay, layer: .endpoints,
                    title: overlay.commandType, subtitle: "Command overlay", detail: overlay.additionalRequiredPrivileges.joined(separator: ", "),
                    surface: .mdm_overlay, runtimeStatus: .tenantVerify, riskFlags: [.tenant_verify],
                    parentID: mdmFamID, sourceRecordID: overlay.commandType, radius: 0.3,
                    accessibilityLabel: "MDM command overlay, \(overlay.commandType)"
                ))
                edges.append(edge(ovID, mdmFamID, .overlay_applies, status: .tenantVerify, selectedPath: false,
                                  a11y: "\(overlay.commandType) overlay applies to MDM commands"))
            }
        }

        // --- Runtime summary node ---
        let summary = runtimeSummary(nodes: nodes, comparison: comparison)
        if let comparison, comparison.state == .comparisonComplete || comparison.state == .missingReadApiRoles {
            let runtimeID = "runtime:summary"
            let ok = comparison.notConfirmed.isEmpty
            if seen.insert(runtimeID).inserted {
                nodes.append(PermissionGraphNode(
                    id: runtimeID, kind: .runtime_status, layer: .runtimeOverlays,
                    title: ok ? "All required confirmed" : "\(comparison.notConfirmed.count) not confirmed",
                    subtitle: "Live token check", detail: nil,
                    surface: .runtime, runtimeStatus: ok ? .available : .missing, riskFlags: [],
                    parentID: selID, sourceRecordID: nil, radius: 0.42,
                    accessibilityLabel: ok ? "Runtime check: all required confirmed" : "Runtime check: \(comparison.notConfirmed.count) not confirmed"
                ))
                edges.append(edge(runtimeID, selID, .runtime_reports, status: ok ? .available : .missing, selectedPath: false,
                                  a11y: "Runtime verification result"))
            }
        }

        // --- Risk flag nodes + warnings ---
        appendRiskNodes(action: action, selID: selID, nodes: &nodes, edges: &edges, warnings: &warnings, seen: &seen)

        let snapshot = PermissionGraphSceneSnapshot(
            selectedItemID: selID, title: action.resolvedDisplayName, subtitle: action.module,
            nodes: nodes, edges: edges, groups: groups,
            legend: legend(for: nodes), runtimeSummary: summary, warnings: warnings
        )
        return layout.layout(snapshot)
    }

    // MARK: - Selected privilege

    func snapshot(
        forPrivilege privilege: String,
        actions: [PermissionsMatrixAction],
        endpoints: [EndpointPrivilegeEntry],
        comparison: PermissionsMatrixComparisonResult? = nil
    ) -> PermissionGraphSceneSnapshot {
        var nodes: [PermissionGraphNode] = []
        var edges: [PermissionGraphEdge] = []
        var seen = Set<String>()

        let selID = "selected:\(Synth.slug(privilege))"
        let st = runtimeStatus(forPrivilege: privilege, comparison: comparison)
        nodes.append(PermissionGraphNode(
            id: selID, kind: .selected_item, layer: .selectedItem, title: privilege,
            subtitle: "Jamf Pro privilege", detail: privilege, surface: .mixed, runtimeStatus: st,
            riskFlags: [], parentID: nil, sourceRecordID: privilege, radius: 0.72,
            accessibilityLabel: "Selected privilege, \(privilege), \(statusWord(st))"
        ))
        seen.insert(selID)

        // Related actions as a "Dependent actions" group of action nodes.
        if actions.isEmpty == false {
            let groupID = "group:actions"
            nodes.append(PermissionGraphNode(
                id: groupID, kind: .privilege_group, layer: .privilegeGroups, title: "Dependent actions",
                subtitle: "\(actions.count) action(s)", detail: nil, surface: .mixed, runtimeStatus: .notChecked,
                riskFlags: [], parentID: selID, sourceRecordID: nil, radius: 0.55,
                accessibilityLabel: "Dependent actions group"
            ))
            edges.append(edge(selID, groupID, .requires, status: .notChecked, selectedPath: true, a11y: "Actions requiring \(privilege)"))
            for action in actions.prefix(24) {
                let aid = "action:\(Synth.slug(action.commandID))"
                guard seen.insert(aid).inserted else { continue }
                nodes.append(PermissionGraphNode(
                    id: aid, kind: .privilege, layer: .privileges, title: action.resolvedDisplayName,
                    subtitle: action.module, detail: action.commandID, surface: .mixed, runtimeStatus: .notChecked,
                    riskFlags: actionRiskFlags(action), parentID: groupID, sourceRecordID: action.commandID, radius: 0.38,
                    accessibilityLabel: "Action, \(action.resolvedDisplayName)"
                ))
                edges.append(edge(groupID, aid, .contains, status: .notChecked, selectedPath: false, a11y: "\(action.resolvedDisplayName) requires \(privilege)"))
            }
        }

        // Related endpoints grouped into families.
        var famSeen = Set<String>()
        for endpoint in endpoints.prefix(18) {
            let f = Synth.family(path: endpoint.path, isClassic: endpoint.isClassic, catalogFamily: endpoint.family)
            let famID = "family:\(f.key)"
            if famSeen.insert(famID).inserted, seen.insert(famID).inserted {
                nodes.append(PermissionGraphNode(
                    id: famID, kind: .endpoint_family, layer: .endpointFamilies, title: f.title,
                    subtitle: surfaceLabel(f.surface), detail: nil, surface: f.surface,
                    runtimeStatus: f.surface == .classic ? .legacyFallback : .notChecked, riskFlags: f.risk,
                    parentID: selID, sourceRecordID: nil, radius: 0.5,
                    accessibilityLabel: "Endpoint family, \(f.title)"
                ))
                edges.append(edge(selID, famID, .implemented_by, status: .notChecked, selectedPath: false, a11y: "\(privilege) served by \(f.title)"))
            }
            let full = "\(endpoint.method) \(endpoint.path)"
            let epID = "endpoint:\(Synth.slug(full))"
            guard seen.insert(epID).inserted else { continue }
            let est: PermissionGraphRuntimeStatus = endpoint.deprecationNote != nil ? .deprecated : (endpoint.isClassic ? .legacyFallback : .notChecked)
            nodes.append(PermissionGraphNode(
                id: epID, kind: .endpoint, layer: .endpoints,
                title: Synth.shortPath(method: endpoint.method, path: endpoint.path),
                subtitle: surfaceLabel(f.surface), detail: full, surface: f.surface, runtimeStatus: est,
                riskFlags: f.risk, parentID: famID, sourceRecordID: endpoint.path, radius: 0.32,
                accessibilityLabel: "Endpoint, \(full)"
            ))
            edges.append(edge(famID, epID, .contains, status: est, selectedPath: false, a11y: "\(f.title) contains \(full)"))
        }

        let snapshot = PermissionGraphSceneSnapshot(
            selectedItemID: selID, title: privilege, subtitle: "Privilege",
            nodes: nodes, edges: edges, groups: [], legend: legend(for: nodes),
            runtimeSummary: runtimeSummary(nodes: nodes, comparison: comparison), warnings: []
        )
        return layout.layout(snapshot)
    }

    // MARK: - Selected endpoint

    func snapshot(
        forEndpoint endpoint: EndpointPrivilegeEntry,
        comparison: PermissionsMatrixComparisonResult? = nil
    ) -> PermissionGraphSceneSnapshot {
        var nodes: [PermissionGraphNode] = []
        var edges: [PermissionGraphEdge] = []
        var warnings: [PermissionGraphWarning] = []
        var seen = Set<String>()

        let full = "\(endpoint.method) \(endpoint.path)"
        let selID = "selected:\(Synth.slug(full))"
        let surface: PermissionGraphSurface = endpoint.isClassic ? .classic : .modern
        nodes.append(PermissionGraphNode(
            id: selID, kind: .selected_item, layer: .selectedItem,
            title: Synth.shortPath(method: endpoint.method, path: endpoint.path), subtitle: surfaceLabel(surface),
            detail: full, surface: surface, runtimeStatus: endpoint.deprecationNote != nil ? .deprecated : .notChecked,
            riskFlags: endpoint.isClassic ? [.classic_api, .legacy_fallback] : [], parentID: nil,
            sourceRecordID: endpoint.path, radius: 0.7, accessibilityLabel: "Selected endpoint, \(full)"
        ))
        seen.insert(selID)

        let groupID = "group:required"
        if endpoint.requiredPrivileges.isEmpty == false {
            nodes.append(PermissionGraphNode(
                id: groupID, kind: .privilege_group, layer: .privilegeGroups, title: "Required Privileges",
                subtitle: nil, detail: nil, surface: surface, runtimeStatus: .notChecked, riskFlags: [],
                parentID: selID, sourceRecordID: nil, radius: 0.55, accessibilityLabel: "Required privileges group"
            ))
            edges.append(edge(selID, groupID, .requires, status: .notChecked, selectedPath: true, a11y: "\(full) requires privileges"))
            for name in endpoint.requiredPrivileges.sorted() {
                let pid = "priv:\(Synth.slug(name))"
                guard seen.insert(pid).inserted else { continue }
                let st = runtimeStatus(forPrivilege: name, comparison: comparison)
                nodes.append(PermissionGraphNode(
                    id: pid, kind: .privilege, layer: .privileges, title: name, subtitle: "Required privilege",
                    detail: name, surface: surface, runtimeStatus: st, riskFlags: [], parentID: groupID,
                    sourceRecordID: name, radius: 0.4, accessibilityLabel: "Privilege, \(name), \(statusWord(st))"
                ))
                edges.append(edge(groupID, pid, .contains, status: st, selectedPath: true, a11y: "requires \(name)"))
            }
        }
        if let note = endpoint.deprecationNote {
            warnings.append(PermissionGraphWarning(id: "warn:deprecated", title: "Deprecated endpoint",
                                                   detail: "Deprecation date: \(note).", relatedNodeIDs: [selID]))
        }

        let snapshot = PermissionGraphSceneSnapshot(
            selectedItemID: selID, title: full, subtitle: surfaceLabel(surface),
            nodes: nodes, edges: edges, groups: [], legend: legend(for: nodes),
            runtimeSummary: runtimeSummary(nodes: nodes, comparison: comparison), warnings: warnings
        )
        return layout.layout(snapshot)
    }

    // MARK: - Helpers

    private func names(for requirement: PrivilegeRequirement, action: PermissionsMatrixAction) -> [String] {
        switch requirement.mode {
        case "all_of": return requirement.privileges ?? []
        case "any_of": return (requirement.privilegeSets ?? []).flatMap { $0 }
        case "optional_runtime_overlay": return requirement.allPrivilegeNames
        case "conditional_all_of_by_asset_type":
            switch action.assetScope {
            case "computer": return requirement.computerPrivileges ?? []
            case "mobile_device": return requirement.mobileDevicePrivileges ?? []
            case "mixed": return requirement.mixedOrGroupPrivileges ?? []
            default: return requirement.allPrivilegeNames
            }
        default: return requirement.allPrivilegeNames
        }
    }

    private func actionRiskFlags(_ action: PermissionsMatrixAction) -> [PermissionGraphRiskFlag] {
        var flags: [PermissionGraphRiskFlag] = []
        if action.destructive { flags.append(.destructive) }
        if action.deprecatedOrLegacy { flags.append(contentsOf: [.deprecated, .legacy_fallback]) }
        if action.needsTenantVerification { flags.append(.tenant_verify) }
        if action.securitySensitive == true { flags.append(.security_sensitive) }
        return flags
    }

    private func appendRiskNodes(
        action: PermissionsMatrixAction, selID: String,
        nodes: inout [PermissionGraphNode], edges: inout [PermissionGraphEdge],
        warnings: inout [PermissionGraphWarning], seen: inout Set<String>
    ) {
        func add(_ flag: PermissionGraphRiskFlag, _ title: String, _ detail: String) {
            let rid = "risk:\(flag.rawValue)"
            guard seen.insert(rid).inserted else { return }
            nodes.append(PermissionGraphNode(
                id: rid, kind: .risk_flag, layer: .runtimeOverlays, title: title, subtitle: "Warning", detail: detail,
                surface: .runtime, runtimeStatus: flag == .tenant_verify ? .tenantVerify : .deprecated, riskFlags: [flag],
                parentID: selID, sourceRecordID: nil, radius: 0.3, accessibilityLabel: "Warning, \(title)"
            ))
            edges.append(edge(rid, selID, .warning, status: .notChecked, selectedPath: false, a11y: title))
            warnings.append(PermissionGraphWarning(id: rid, title: title, detail: detail, relatedNodeIDs: [selID]))
        }
        if action.destructive { add(.destructive, "Destructive", "This action performs a destructive operation.") }
        if action.deprecatedOrLegacy { add(.legacy_fallback, "Legacy / deprecated", "This action uses a legacy or deprecated path.") }
        if action.needsTenantVerification { add(.tenant_verify, "Tenant verify", "Confirm against your tenant /api/doc — some requirements are tenant-verified.") }
    }

    private func runtimeStatus(forPrivilege name: String, comparison: PermissionsMatrixComparisonResult?) -> PermissionGraphRuntimeStatus {
        guard let comparison else { return .notChecked }
        if comparison.confirmedPresent.contains(name) { return .available }
        if comparison.notConfirmed.contains(name) { return .missing }
        if comparison.alternativesNotPresent.contains(name) { return .unknown }
        return .notChecked
    }

    private func rollup(_ statuses: [PermissionGraphRuntimeStatus]) -> PermissionGraphRuntimeStatus {
        guard statuses.isEmpty == false else { return .notChecked }
        if statuses.contains(.missing) { return .missing }
        if statuses.contains(.unknown) { return .unknown }
        if statuses.contains(.tenantVerify) { return .tenantVerify }
        if statuses.allSatisfy({ $0 == .available }) { return .available }
        return .notChecked
    }

    private func runtimeSummary(nodes: [PermissionGraphNode], comparison: PermissionsMatrixComparisonResult?) -> PermissionGraphRuntimeSummary {
        var s = PermissionGraphRuntimeSummary(hasLiveData: comparison != nil)
        for node in nodes where node.kind == .privilege {
            switch node.runtimeStatus {
            case .available: s.available += 1
            case .missing: s.missing += 1
            case .unknown: s.unknown += 1
            case .tenantVerify: s.tenantVerify += 1
            default: s.notChecked += 1
            }
        }
        return s
    }

    private func legend(for nodes: [PermissionGraphNode]) -> [PermissionGraphLegendEntry] {
        var entries: [PermissionGraphLegendEntry] = []
        let statuses = Set(nodes.map(\.runtimeStatus))
        func add(_ status: PermissionGraphRuntimeStatus, _ label: String, _ symbol: String) {
            if statuses.contains(status) {
                entries.append(PermissionGraphLegendEntry(id: "legend-\(status.rawValue)", label: label, symbolName: symbol, runtimeStatus: status, kind: nil))
            }
        }
        add(.available, "Available", "checkmark.circle.fill")
        add(.missing, "Missing", "xmark.octagon.fill")
        add(.unknown, "Unknown", "questionmark.circle")
        add(.tenantVerify, "Tenant verify", "exclamationmark.triangle")
        add(.deprecated, "Deprecated", "clock.badge.exclamationmark")
        add(.legacyFallback, "Classic fallback", "arrow.triangle.branch")
        return entries
    }

    private func surfaceLabel(_ surface: PermissionGraphSurface) -> String {
        switch surface {
        case .modern: return "Jamf Pro API"
        case .classic: return "Classic API"
        case .mdm_overlay: return "MDM Overlay"
        case .ddm: return "Declarative DM"
        case .runtime: return "Runtime"
        case .mixed: return "Mixed"
        case .none: return ""
        }
    }

    private func statusWord(_ status: PermissionGraphRuntimeStatus) -> String {
        switch status {
        case .available: return "confirmed available"
        case .missing: return "not confirmed"
        case .unknown: return "status unknown"
        case .notChecked: return "not checked"
        case .tenantVerify: return "tenant verification recommended"
        case .deprecated: return "deprecated"
        case .legacyFallback: return "classic fallback"
        }
    }

    private func edge(
        _ from: String, _ to: String, _ kind: PermissionGraphEdgeKind,
        status: PermissionGraphRuntimeStatus, selectedPath: Bool, bundleID: String? = nil, a11y: String
    ) -> PermissionGraphEdge {
        PermissionGraphEdge(
            id: "\(kind.rawValue):\(from)->\(to)", fromNodeID: from, toNodeID: to, kind: kind,
            runtimeStatus: status, weight: kind == .contains ? 0.7 : 1.0, bundleID: bundleID,
            isSelectedPath: selectedPath, accessibilityLabel: a11y
        )
    }
}
