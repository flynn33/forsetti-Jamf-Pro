import Foundation

// Pure, deterministic bucketing rules that turn flat matrix privileges/endpoints
// into the hierarchy's privilege GROUPS and endpoint FAMILIES. Kept separate from
// the scene builder so the rules are unit-testable in isolation. No Metal, no Jamf.
enum PermissionGraphHierarchySynthesis {

    // MARK: - Privilege groups

    struct PrivilegeBucket: Equatable {
        let key: String
        let title: String
        let risk: [PermissionGraphRiskFlag]
    }

    /// Classify a single privilege into a semantic group. `isOverlay` marks
    /// optional runtime/tenant overlay privileges.
    static func bucket(privilege: String, action: PermissionsMatrixAction, isOverlay: Bool) -> PrivilegeBucket {
        if isOverlay {
            return PrivilegeBucket(key: "runtime_tenant", title: "Runtime / Tenant Verification", risk: [.tenant_verify])
        }
        let lower = privilege.lowercased()
        if lower.contains("mdm command") {
            return PrivilegeBucket(key: "mdm_visibility", title: "MDM Command Visibility", risk: [])
        }
        let isCommandLike = lower.hasPrefix("send ") || lower.contains(" command") || lower.contains("blank push") || lower.hasPrefix("flush")
        if action.destructive && (isCommandLike || lower.contains("wipe") || lower.contains("erase") || lower.hasPrefix("delete")) {
            return PrivilegeBucket(key: "destructive", title: "Destructive Operations", risk: [.destructive])
        }
        if isCommandLike {
            return PrivilegeBucket(key: "command", title: "Command Execution", risk: [])
        }
        if lower.hasPrefix("create") || lower.hasPrefix("update") {
            return PrivilegeBucket(key: "create_update", title: "Create / Update", risk: [])
        }
        if lower.hasPrefix("delete") {
            return PrivilegeBucket(key: "delete", title: "Delete", risk: [])
        }
        if lower.hasPrefix("view") || lower.hasPrefix("read") {
            return PrivilegeBucket(key: "read", title: "Read Access", risk: [.read_only])
        }
        return PrivilegeBucket(key: "required", title: "Required Privileges", risk: [])
    }

    /// Stable display order for group buckets.
    static func groupOrderRank(_ key: String) -> Int {
        switch key {
        case "read": return 0
        case "create_update": return 1
        case "command": return 2
        case "mdm_visibility": return 3
        case "destructive": return 4
        case "delete": return 5
        case "runtime_tenant": return 6
        default: return 7
        }
    }

    // MARK: - Endpoint families

    struct FamilyBucket: Equatable {
        let key: String
        let title: String
        let surface: PermissionGraphSurface
        let risk: [PermissionGraphRiskFlag]
    }

    /// Classify an endpoint path into an endpoint family.
    static func family(path: String, isClassic: Bool, catalogFamily: String?) -> FamilyBucket {
        let lower = path.lowercased()
        if lower.contains("/ddm/") {
            return FamilyBucket(key: "ddm", title: "Declarative Device Management", surface: .ddm, risk: [])
        }
        if lower.contains("/mdm/") {
            return FamilyBucket(key: "mdm", title: "MDM Commands", surface: .modern, risk: [])
        }
        if isClassic {
            return FamilyBucket(key: "classic", title: "Classic API", surface: .classic, risk: [.classic_api, .legacy_fallback])
        }
        if let catalogFamily, catalogFamily.isEmpty == false {
            return FamilyBucket(key: "family-\(slug(catalogFamily))", title: "\(titleCase(catalogFamily)) API", surface: .modern, risk: [])
        }
        // Derive from the first meaningful path segment after /api/vN/.
        let derived = derivedFamilySegment(path)
        return FamilyBucket(key: "family-\(slug(derived))", title: "\(titleCase(derived)) API", surface: .modern, risk: [])
    }

    private static func derivedFamilySegment(_ path: String) -> String {
        let parts = path.split(separator: "/").map(String.init)
        // Skip leading "api" and a version token like "v1"/"v2".
        var idx = 0
        if idx < parts.count, parts[idx].lowercased() == "api" { idx += 1 }
        if idx < parts.count, parts[idx].lowercased().hasPrefix("v"), Int(parts[idx].dropFirst()) != nil { idx += 1 }
        if idx < parts.count { return parts[idx] }
        return parts.first ?? "endpoint"
    }

    // MARK: - Label abbreviation

    /// Abbreviate an endpoint path for the in-scene node title; the inspector keeps
    /// the full string. e.g. "POST /api/v2/mdm/blank-push" → "POST mdm/blank-push".
    static func shortPath(method: String, path: String) -> String {
        var trimmed = path
        if let range = trimmed.range(of: #"^/api/v\d+/"#, options: .regularExpression) {
            trimmed.removeSubrange(range)
        } else if trimmed.hasPrefix("/JSSResource/") {
            // "/JSSResource/computercommands/command/UpdateInventory/id/{id}" → "computercommands/UpdateInventory"
            let parts = trimmed.dropFirst("/JSSResource/".count).split(separator: "/").map(String.init)
            if let first = parts.first {
                if let cmdIdx = parts.firstIndex(of: "command"), cmdIdx + 1 < parts.count {
                    return "\(method.uppercased()) \(first)/\(parts[cmdIdx + 1])"
                }
                return "\(method.uppercased()) \(first)"
            }
        } else if trimmed.hasPrefix("/") {
            trimmed.removeFirst()
        }
        // Drop trailing id placeholders for brevity.
        trimmed = trimmed.replacingOccurrences(of: "/{id}", with: "").replacingOccurrences(of: "/id/{id}", with: "")
        return "\(method.uppercased()) \(trimmed)"
    }

    // MARK: - Helpers

    static func slug(_ value: String) -> String {
        let lowered = value.lowercased().replacingOccurrences(of: "[^a-z0-9]+", with: "-", options: .regularExpression)
        return lowered.trimmingCharacters(in: CharacterSet(charactersIn: "-"))
    }

    private static func titleCase(_ value: String) -> String {
        value.split(whereSeparator: { $0 == "-" || $0 == "_" || $0 == " " })
            .map { $0.prefix(1).uppercased() + $0.dropFirst() }
            .joined(separator: " ")
    }
}
