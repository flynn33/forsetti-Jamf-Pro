import Foundation
import simd

// Presentation-only scene model for the Permissions Helper visual hierarchy.
//
// A `PermissionGraphSceneSnapshot` is derived from the existing matrix selection
// by `PermissionGraphSceneBuilder` and laid out by `PermissionGraphLayeredLayoutEngine`.
// It is pure data — no Metal, no SwiftUI, no Jamf access — so it can be built off
// the main actor and unit-tested directly. The renderer consumes the snapshot; it
// never decodes the matrix or talks to Jamf.
//
// Enum raw values are deliberately space-free (e.g. `implemented_by`) so production
// source stays neutral.

/// The kind of entity a node represents.
enum PermissionGraphNodeKind: String, Sendable, CaseIterable {
    case selected_item
    case privilege_group
    case privilege
    case endpoint_family
    case endpoint
    case command_overlay
    case runtime_status
    case risk_flag
}

/// The kind of relationship an edge represents.
enum PermissionGraphEdgeKind: String, Sendable, CaseIterable {
    case requires
    case contains
    case implemented_by
    case fallback_to
    case overlay_applies
    case runtime_reports
    case warning
}

/// Depth-ranked hierarchy layers. `rawValue` is the rank (0 = nearest / selected).
enum PermissionGraphLayer: Int, Sendable, CaseIterable {
    case selectedItem = 0
    case privilegeGroups = 1
    case privileges = 2
    case endpointFamilies = 3
    case endpoints = 4
    case runtimeOverlays = 5

    /// World-space z used by the 3D layout (selected nearest, endpoints far,
    /// runtime overlays floated forward).
    var zDepth: Float {
        switch self {
        case .selectedItem: return 0
        case .privilegeGroups: return -1.5
        case .privileges: return -3.0
        case .endpointFamilies: return -4.5
        case .endpoints: return -6.0
        case .runtimeOverlays: return 0.8
        }
    }
}

/// The Jamf API surface a node belongs to. Also a stable ordering key.
enum PermissionGraphSurface: String, Sendable, CaseIterable {
    case modern
    case classic
    case mdm_overlay
    case ddm
    case runtime
    case mixed
    case none

    var orderRank: Int {
        switch self {
        case .modern: return 0
        case .ddm: return 1
        case .mdm_overlay: return 2
        case .classic: return 3
        case .runtime: return 4
        case .mixed: return 5
        case .none: return 6
        }
    }
}

/// Runtime / verification status mapped from the live comparison result.
enum PermissionGraphRuntimeStatus: String, Sendable, CaseIterable {
    case available
    case missing
    case unknown
    case notChecked
    case tenantVerify
    case deprecated
    case legacyFallback
}

/// Risk markers attached to a node (shape/symbol cues, never color-only).
enum PermissionGraphRiskFlag: String, Sendable, CaseIterable {
    case destructive
    case security_sensitive
    case deprecated
    case tenant_verify
    case legacy_fallback
    case classic_api
    case read_only
}

struct PermissionGraphNode: Identifiable, Equatable, Sendable {
    var id: String
    var kind: PermissionGraphNodeKind
    var layer: PermissionGraphLayer
    var title: String
    var subtitle: String?
    /// Exact full string (privilege name / full endpoint path) shown in the inspector.
    var detail: String?
    var surface: PermissionGraphSurface
    var runtimeStatus: PermissionGraphRuntimeStatus
    var riskFlags: [PermissionGraphRiskFlag]
    /// Hierarchy spine parent (used for clustering and selected-path tracing).
    var parentID: String?
    var sourceRecordID: String?
    /// 3D world position (set by the layout engine).
    var position: SIMD3<Float> = .zero
    /// 2D blueprint position (set by the layout engine).
    var blueprintPosition: SIMD2<Float> = .zero
    var radius: Float = 0.5
    var accessibilityLabel: String = ""
}

struct PermissionGraphEdge: Identifiable, Equatable, Sendable {
    var id: String
    var fromNodeID: String
    var toNodeID: String
    var kind: PermissionGraphEdgeKind
    var runtimeStatus: PermissionGraphRuntimeStatus = .notChecked
    var weight: Float = 1
    /// Edges sharing a bundleID are drawn as one bundled spline into a dense family.
    var bundleID: String?
    var isSelectedPath: Bool = false
    var accessibilityLabel: String = ""
}

struct PermissionGraphGroup: Identifiable, Equatable, Sendable {
    var id: String
    var title: String
    var layer: PermissionGraphLayer
    var memberNodeIDs: [String]
    var collapsed: Bool = false
}

struct PermissionGraphLegendEntry: Identifiable, Equatable, Sendable {
    var id: String
    var label: String
    var symbolName: String
    var runtimeStatus: PermissionGraphRuntimeStatus?
    var kind: PermissionGraphNodeKind?
}

struct PermissionGraphRuntimeSummary: Equatable, Sendable {
    var available: Int = 0
    var missing: Int = 0
    var unknown: Int = 0
    var tenantVerify: Int = 0
    var notChecked: Int = 0
    var hasLiveData: Bool = false
}

struct PermissionGraphWarning: Identifiable, Equatable, Sendable {
    var id: String
    var title: String
    var detail: String
    var relatedNodeIDs: [String]
}

struct PermissionGraphSceneSnapshot: Equatable, Sendable {
    var selectedItemID: String
    var title: String
    var subtitle: String?
    var nodes: [PermissionGraphNode]
    var edges: [PermissionGraphEdge]
    var groups: [PermissionGraphGroup]
    var legend: [PermissionGraphLegendEntry]
    var runtimeSummary: PermissionGraphRuntimeSummary
    var warnings: [PermissionGraphWarning]

    init(
        selectedItemID: String,
        title: String,
        subtitle: String? = nil,
        nodes: [PermissionGraphNode],
        edges: [PermissionGraphEdge],
        groups: [PermissionGraphGroup] = [],
        legend: [PermissionGraphLegendEntry] = [],
        runtimeSummary: PermissionGraphRuntimeSummary = PermissionGraphRuntimeSummary(),
        warnings: [PermissionGraphWarning] = []
    ) {
        self.selectedItemID = selectedItemID
        self.title = title
        self.subtitle = subtitle
        self.nodes = nodes
        self.edges = edges
        self.groups = groups
        self.legend = legend
        self.runtimeSummary = runtimeSummary
        self.warnings = warnings
    }

    func node(id: String) -> PermissionGraphNode? {
        nodes.first { $0.id == id }
    }

    /// Node IDs on the highlighted selected path (endpoints of selected-path edges
    /// plus the selected item). These are always rendered and never LOD-culled.
    var selectedPathNodeIDs: Set<String> {
        var ids: Set<String> = [selectedItemID]
        for edge in edges where edge.isSelectedPath {
            ids.insert(edge.fromNodeID)
            ids.insert(edge.toNodeID)
        }
        return ids
    }

    /// Structural identity used by the renderer to decide whether to rebuild GPU
    /// geometry. Excludes transient camera/selection — those are uniforms.
    var identityHash: Int {
        var hasher = Hasher()
        hasher.combine(selectedItemID)
        for node in nodes {
            hasher.combine(node.id)
            hasher.combine(node.kind)
            hasher.combine(node.layer)
            hasher.combine(node.runtimeStatus)
            hasher.combine(Int((node.position.x * 100).rounded()))
            hasher.combine(Int((node.position.y * 100).rounded()))
            hasher.combine(Int((node.position.z * 100).rounded()))
        }
        for edge in edges {
            hasher.combine(edge.id)
            hasher.combine(edge.kind)
            hasher.combine(edge.runtimeStatus)
        }
        return hasher.finalize()
    }
}
