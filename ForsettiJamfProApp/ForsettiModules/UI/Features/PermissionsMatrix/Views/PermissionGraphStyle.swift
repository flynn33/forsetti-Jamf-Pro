import SwiftUI

// SwiftUI color/symbol/label vocabulary for labels, legend, inspector, and the
// accessible fallback. Parallels the Metal palette. Status is conveyed by symbol
// and text (not color alone) so the legend/inspector/fallback remain accessible.
enum PermissionGraphStyle {
    /// Single amber used for risk badges and the warnings banner so the hue never drifts.
    static let riskAmber = Color(red: 1.0, green: 0.78, blue: 0.40)

    static func color(status: PermissionGraphRuntimeStatus, kind: PermissionGraphNodeKind) -> Color {
        switch status {
        case .available: return Color(red: 0.40, green: 0.86, blue: 0.58)
        case .missing: return Color(red: 1.00, green: 0.42, blue: 0.42)
        case .tenantVerify: return Color(red: 1.00, green: 0.80, blue: 0.36)
        case .deprecated: return Color(red: 1.00, green: 0.62, blue: 0.30)
        case .legacyFallback: return Color(red: 0.78, green: 0.62, blue: 0.44)
        case .unknown: return Color(red: 0.62, green: 0.64, blue: 0.72)
        case .notChecked: break
        }
        switch kind {
        case .selected_item: return Color(red: 0.34, green: 0.72, blue: 1.00)
        case .privilege_group: return Color(red: 0.46, green: 0.64, blue: 1.00)
        case .privilege: return Color(red: 0.40, green: 0.82, blue: 0.88)
        case .endpoint_family: return Color(red: 0.58, green: 0.62, blue: 0.76)
        case .endpoint: return Color(red: 0.50, green: 0.66, blue: 1.00)
        case .command_overlay: return Color(red: 0.74, green: 0.56, blue: 1.00)
        case .runtime_status: return Color(red: 0.42, green: 0.86, blue: 0.60)
        case .risk_flag: return Color(red: 1.00, green: 0.72, blue: 0.34)
        }
    }

    static func symbol(kind: PermissionGraphNodeKind) -> String {
        switch kind {
        case .selected_item: return "scope"
        case .privilege_group: return "folder.fill"
        case .privilege: return "key.fill"
        case .endpoint_family: return "rectangle.stack.fill"
        case .endpoint: return "network"
        case .command_overlay: return "plus.rectangle.on.rectangle"
        case .runtime_status: return "checkmark.shield"
        case .risk_flag: return "exclamationmark.triangle.fill"
        }
    }

    static func statusSymbol(_ status: PermissionGraphRuntimeStatus) -> String {
        switch status {
        case .available: return "checkmark.circle.fill"
        case .missing: return "xmark.octagon.fill"
        case .unknown: return "questionmark.circle"
        case .notChecked: return "circle.dashed"
        case .tenantVerify: return "exclamationmark.triangle"
        case .deprecated: return "clock.badge.exclamationmark"
        case .legacyFallback: return "arrow.triangle.branch"
        }
    }

    static func kindLabel(_ kind: PermissionGraphNodeKind) -> String {
        switch kind {
        case .selected_item: return "Selected"
        case .privilege_group: return "Privilege group"
        case .privilege: return "Privilege"
        case .endpoint_family: return "Endpoint family"
        case .endpoint: return "Endpoint"
        case .command_overlay: return "Command overlay"
        case .runtime_status: return "Runtime"
        case .risk_flag: return "Warning"
        }
    }

    static func statusLabel(_ status: PermissionGraphRuntimeStatus) -> String {
        switch status {
        case .available: return "Available"
        case .missing: return "Missing"
        case .unknown: return "Unknown"
        case .notChecked: return "Not checked"
        case .tenantVerify: return "Tenant verify"
        case .deprecated: return "Deprecated"
        case .legacyFallback: return "Classic fallback"
        }
    }
}
