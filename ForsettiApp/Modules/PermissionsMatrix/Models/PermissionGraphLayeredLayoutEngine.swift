import Foundation
import simd

// Deterministic layered hierarchy layout. Fills BOTH `position` (3D, per-layer
// rings at fixed z-depths with children clustered under their parent's angle) and
// `blueprintPosition` (2D, ranked left-to-right columns) so the display-mode
// toggle never rebuilds the snapshot. No force-directed placement.
struct PermissionGraphLayeredLayoutEngine {

    func layout(_ snapshot: PermissionGraphSceneSnapshot) -> PermissionGraphSceneSnapshot {
        var result = snapshot
        var nodes = result.nodes
        var angleByID: [String: Float] = [:]

        for layer in PermissionGraphLayer.allCases.sorted(by: { $0.rawValue < $1.rawValue }) {
            let indices = nodes.indices.filter { nodes[$0].layer == layer }
            place3D(layer: layer, indices: indices, nodes: &nodes, angleByID: &angleByID)
            placeBlueprint(layer: layer, indices: indices, nodes: &nodes)
        }

        result.nodes = nodes
        return result
    }

    // MARK: - 3D placement

    private func radius(for layer: PermissionGraphLayer) -> Float {
        switch layer {
        case .selectedItem: return 0
        case .privilegeGroups: return 2.4
        case .privileges: return 4.4
        case .endpointFamilies: return 6.6
        case .endpoints: return 8.8
        case .runtimeOverlays: return 1.3
        }
    }

    private func place3D(layer: PermissionGraphLayer, indices: [Int], nodes: inout [PermissionGraphNode], angleByID: inout [String: Float]) {
        guard indices.isEmpty == false else { return }
        let z = layer.zDepth * 1.6
        if layer == .selectedItem {
            for idx in indices { nodes[idx].position = SIMD3<Float>(0, 0, z); angleByID[nodes[idx].id] = 0 }
            return
        }
        let r = radius(for: layer)
        let sorted = indices.sorted { orderKey(nodes[$0]) < orderKey(nodes[$1]) }
        let distributesFull = layer == .privilegeGroups || layer == .endpointFamilies || layer == .runtimeOverlays

        if distributesFull {
            let count = sorted.count
            for (i, idx) in sorted.enumerated() {
                let angle: Float
                if layer == .runtimeOverlays {
                    let t = count <= 1 ? 0.5 : Float(i) / Float(count - 1)
                    angle = -.pi / 2 + (t - 0.5) * 0.9        // small arc near top
                } else {
                    angle = (Float(i) / Float(max(count, 1))) * 2 * .pi - .pi / 2
                }
                nodes[idx].position = SIMD3<Float>(cos(angle) * r, sin(angle) * r * 0.62, z)
                angleByID[nodes[idx].id] = angle
            }
        } else {
            // Cluster children around their parent's angle (privileges under groups,
            // endpoints under families) so the hierarchy reads as a cone.
            var byParent: [String: [Int]] = [:]
            var parentOrder: [String] = []
            for idx in sorted {
                let p = nodes[idx].parentID ?? "?"
                if byParent[p] == nil { parentOrder.append(p) }
                byParent[p, default: []].append(idx)
            }
            for parent in parentOrder {
                let sibs = byParent[parent] ?? []
                let base = angleByID[parent] ?? 0
                let span = min(1.0, 0.20 * Float(sibs.count))
                for (j, idx) in sibs.enumerated() {
                    let t = sibs.count <= 1 ? 0.5 : Float(j) / Float(sibs.count - 1)
                    let angle = base + (t - 0.5) * span
                    nodes[idx].position = SIMD3<Float>(cos(angle) * r, sin(angle) * r * 0.62, z)
                    angleByID[nodes[idx].id] = angle
                }
            }
        }
    }

    // MARK: - Blueprint (2D) placement

    private func placeBlueprint(layer: PermissionGraphLayer, indices: [Int], nodes: inout [PermissionGraphNode]) {
        guard indices.isEmpty == false else { return }
        let column = Float(layer.rawValue) * 3.2
        let sorted = indices.sorted { orderKey(nodes[$0]) < orderKey(nodes[$1]) }
        let count = sorted.count
        for (i, idx) in sorted.enumerated() {
            let centered = Float(i) - Float(max(count - 1, 0)) / 2
            nodes[idx].blueprintPosition = SIMD2<Float>(column, -centered * 1.0)
        }
    }

    // MARK: - Ordering

    private func orderKey(_ node: PermissionGraphNode) -> String {
        // surface rank, then kind, then title — stable & deterministic.
        String(format: "%d|%@|%@", node.surface.orderRank, node.kind.rawValue, node.title)
    }
}

// MARK: - Bounds helpers (used by camera fit)

extension PermissionGraphSceneSnapshot {
    /// 3D world AABB over node positions expanded by radius.
    var worldBounds3D: (min: SIMD3<Float>, max: SIMD3<Float>) {
        guard nodes.isEmpty == false else { return (SIMD3(-6, -6, -6), SIMD3(6, 6, 6)) }
        var lo = SIMD3<Float>(repeating: .greatestFiniteMagnitude)
        var hi = SIMD3<Float>(repeating: -.greatestFiniteMagnitude)
        for n in nodes {
            let r = SIMD3<Float>(repeating: n.radius)
            lo = simd_min(lo, n.position - r)
            hi = simd_max(hi, n.position + r)
        }
        return (lo, hi)
    }

    /// 2D blueprint AABB.
    var blueprintBounds: (min: SIMD2<Float>, max: SIMD2<Float>) {
        guard nodes.isEmpty == false else { return (SIMD2(-6, -6), SIMD2(6, 6)) }
        var lo = SIMD2<Float>(repeating: .greatestFiniteMagnitude)
        var hi = SIMD2<Float>(repeating: -.greatestFiniteMagnitude)
        for n in nodes {
            let r = SIMD2<Float>(repeating: n.radius)
            lo = simd_min(lo, n.blueprintPosition - r)
            hi = simd_max(hi, n.blueprintPosition + r)
        }
        return (lo, hi)
    }
}
