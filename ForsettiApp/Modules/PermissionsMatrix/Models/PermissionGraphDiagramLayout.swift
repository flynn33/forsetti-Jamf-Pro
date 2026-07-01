import Foundation
import CoreGraphics

// Deterministic layout for the premium tiered Permissions Helper diagram.
//
// The Permissions Helper hierarchy is, for every selection type, two tracks rooted
// at a single selected item:
//
//   Selected ─▶ Privilege groups ─▶ Privileges
//   Selected ─▶ Endpoint families ─▶ Endpoints (+ command overlays)
//
// This engine lays those two tracks out as two stacked bands of cards in a content
// coordinate space (origin top-left, y grows downward). Children are placed under
// their parent and the parent is centered against its children, so connectors only
// ever span one column — no crossings.
//
// Card heights are content-aware: each card is sized to fit its (possibly two-line)
// title, optional subtitle, and — when runtime data is shown — a status pill, so
// long privilege names never clip. Connectors are anchored to the resulting card
// edges, so they always land correctly regardless of card height.
//
// Excluded from the columns: runtime-status and risk-flag overlay nodes (surfaced
// by the panel as per-card status pills, risk badges, the runtime summary, and the
// warnings banner). Command-overlay nodes ARE placed as col-2 cards beneath their
// MDM endpoint family.
//
// Pure value logic — no SwiftUI, no Metal — so it is unit-testable and produces an
// identical result every time.
struct PermissionGraphDiagramLayout: Equatable {

    /// A placed node card.
    struct Card: Identifiable, Equatable {
        let id: String
        let frame: CGRect
        let column: Int          // 0 = selected, 1 = groups/families, 2 = privileges/endpoints
    }

    /// A connector between two cards.
    struct Connector: Identifiable, Equatable {
        enum Orientation: Equatable { case horizontal, vertical }
        let id: String
        let from: CGPoint
        let to: CGPoint
        let kind: PermissionGraphEdgeKind
        let runtimeStatus: PermissionGraphRuntimeStatus
        let isSelectedPath: Bool
        let orientation: Orientation
    }

    /// A labeled band region (privilege track / endpoint track) for the header + backdrop.
    struct Band: Identifiable, Equatable {
        let id: String
        let title: String
        let symbolName: String
        let frame: CGRect        // encloses the band header + its cards
        let headerOrigin: CGPoint
    }

    /// Sizing knobs. Defaults are tuned for a premium, readable density.
    struct Metrics: Equatable {
        var selectedWidth: CGFloat = 212
        var minSelectedHeight: CGFloat = 92
        var col1Width: CGFloat = 210
        var col2Width: CGFloat = 268
        var minRowHeight: CGFloat = 64
        var rowGap: CGFloat = 14
        var groupGap: CGFloat = 24      // between sibling groups/families within a band
        var columnGap: CGFloat = 66     // horizontal gap between columns
        var bandGap: CGFloat = 44       // vertical gap between the two bands
        var bandHeaderHeight: CGFloat = 30
        var padding: CGFloat = 30
        static let `default` = Metrics()
    }

    var cards: [Card]
    var connectors: [Connector]
    var bands: [Band]
    var contentSize: CGSize

    private let frameByID: [String: CGRect]

    func frame(for id: String) -> CGRect? { frameByID[id] }

    static let empty = PermissionGraphDiagramLayout(
        cards: [], connectors: [], bands: [], contentSize: .zero, frameByID: [:]
    )

    // MARK: - Build

    /// - Parameter showRuntime: when true a status pill is budgeted into the height of
    ///   cards whose status is informative (so the pill never clips).
    static func make(_ snapshot: PermissionGraphSceneSnapshot, metrics m: Metrics = .default, showRuntime: Bool = true) -> PermissionGraphDiagramLayout {
        let columnNodes = snapshot.nodes.filter { $0.kind != .runtime_status && $0.kind != .risk_flag }
        guard let selected = columnNodes.first(where: { $0.kind == .selected_item }) else {
            return .empty
        }

        let col1 = columnNodes.filter { $0.parentID == selected.id }
        let privParents = col1.filter { $0.kind != .endpoint_family }
        let famParents  = col1.filter { $0.kind == .endpoint_family }

        func children(of parentID: String) -> [PermissionGraphNode] {
            columnNodes.filter { $0.parentID == parentID && $0.id != selected.id }
        }

        let x0 = m.padding
        let x1 = x0 + m.selectedWidth + m.columnGap
        let x2 = x1 + m.col1Width + m.columnGap

        var frames: [String: CGRect] = [:]
        var cards: [Card] = []
        var bands: [Band] = []
        var cursorY = m.padding

        func layoutBand(id: String, title: String, symbol: String, parents: [PermissionGraphNode]) {
            guard parents.isEmpty == false else { return }
            let headerY = cursorY
            cursorY += m.bandHeaderHeight + 6

            for parent in parents {
                let kids = children(of: parent.id)
                let kidHeights = kids.map { cardHeight(for: $0, width: m.col2Width, metrics: m, showRuntime: showRuntime) }
                let blockHeight = kids.isEmpty
                    ? cardHeight(for: parent, width: m.col1Width, metrics: m, showRuntime: showRuntime)
                    : kidHeights.reduce(0, +) + CGFloat(max(kids.count - 1, 0)) * m.rowGap

                var ky = cursorY
                for (i, kid) in kids.enumerated() {
                    let f = CGRect(x: x2, y: ky, width: m.col2Width, height: kidHeights[i])
                    frames[kid.id] = f
                    cards.append(Card(id: kid.id, frame: f, column: 2))
                    ky += kidHeights[i] + m.rowGap
                }

                let parentHeight = cardHeight(for: parent, width: m.col1Width, metrics: m, showRuntime: showRuntime)
                let parentY = cursorY + (blockHeight - parentHeight) / 2
                let pf = CGRect(x: x1, y: parentY, width: m.col1Width, height: parentHeight)
                frames[parent.id] = pf
                cards.append(Card(id: parent.id, frame: pf, column: 1))

                // Advance by the taller of the child block or the (centered) parent so a
                // tall col-1 parent over a single short child can't overrun the next group.
                cursorY += max(blockHeight, parentHeight) + m.groupGap
            }
            cursorY -= m.groupGap
            let bandBottom = cursorY

            let bandFrame = CGRect(
                x: x1 - 10, y: headerY - 4,
                width: (x2 + m.col2Width) - x1 + 20,
                height: bandBottom - headerY + 10
            )
            bands.append(Band(id: id, title: title, symbolName: symbol,
                              frame: bandFrame, headerOrigin: CGPoint(x: x1, y: headerY)))
            cursorY = bandBottom + m.bandGap
        }

        let privTitle = privParents.contains { $0.title == "Dependent actions" } ? "Where it is used" : "Required privileges"
        layoutBand(id: "band:privileges", title: privTitle, symbol: "key.fill", parents: privParents)
        layoutBand(id: "band:endpoints", title: "API endpoints", symbol: "network", parents: famParents)

        // Selected hero card: vertically centered against all band cards.
        let bandCardFrames = cards.map(\.frame)
        let minY = bandCardFrames.map(\.minY).min() ?? m.padding
        let maxY = bandCardFrames.map(\.maxY).max() ?? (m.padding + m.minSelectedHeight)
        let selHeight = cardHeight(for: selected, width: m.selectedWidth, metrics: m, showRuntime: showRuntime, isHero: true)
        let selY = (minY + maxY) / 2 - selHeight / 2
        let selFrame = CGRect(x: x0, y: selY, width: m.selectedWidth, height: selHeight)
        frames[selected.id] = selFrame
        cards.append(Card(id: selected.id, frame: selFrame, column: 0))

        // Connectors from the visible edges (both endpoints must be placed).
        var connectors: [Connector] = []
        for edge in snapshot.edges {
            guard let a = frames[edge.fromNodeID], let b = frames[edge.toNodeID] else { continue }
            let connector: Connector
            if abs(a.minX - b.minX) < 0.5 {
                let top = a.minY <= b.minY ? a : b
                let bottom = a.minY <= b.minY ? b : a
                connector = Connector(
                    id: edge.id,
                    from: CGPoint(x: top.midX, y: top.maxY),
                    to: CGPoint(x: bottom.midX, y: bottom.minY),
                    kind: edge.kind, runtimeStatus: edge.runtimeStatus,
                    isSelectedPath: edge.isSelectedPath, orientation: .vertical
                )
            } else {
                let left = a.minX < b.minX ? a : b
                let right = a.minX < b.minX ? b : a
                connector = Connector(
                    id: edge.id,
                    from: CGPoint(x: left.maxX, y: left.midY),
                    to: CGPoint(x: right.minX, y: right.midY),
                    kind: edge.kind, runtimeStatus: edge.runtimeStatus,
                    isSelectedPath: edge.isSelectedPath, orientation: .horizontal
                )
            }
            connectors.append(connector)
        }

        // Normalize so the union of everything starts at (padding, padding).
        let allFrames = cards.map(\.frame)
        let unionMinX = allFrames.map(\.minX).min() ?? 0
        let unionMinY = allFrames.map(\.minY).min() ?? 0
        let dx = m.padding - unionMinX
        let dy = m.padding - unionMinY

        if dx != 0 || dy != 0 {
            let shift = CGAffineTransform(translationX: dx, y: dy)
            for key in frames.keys { frames[key] = frames[key]!.applying(shift) }
            cards = cards.map { Card(id: $0.id, frame: $0.frame.applying(shift), column: $0.column) }
            connectors = connectors.map {
                Connector(id: $0.id, from: $0.from.applying(shift), to: $0.to.applying(shift),
                          kind: $0.kind, runtimeStatus: $0.runtimeStatus,
                          isSelectedPath: $0.isSelectedPath, orientation: $0.orientation)
            }
            bands = bands.map {
                Band(id: $0.id, title: $0.title, symbolName: $0.symbolName,
                     frame: $0.frame.applying(shift),
                     headerOrigin: $0.headerOrigin.applying(shift))
            }
        }

        let maxX = cards.map(\.frame.maxX).max() ?? m.padding
        let bottomY = cards.map(\.frame.maxY).max() ?? m.padding
        let contentSize = CGSize(width: maxX + m.padding, height: bottomY + m.padding)

        return PermissionGraphDiagramLayout(
            cards: cards, connectors: connectors, bands: bands,
            contentSize: contentSize, frameByID: frames
        )
    }

    // MARK: - Content-aware card height

    /// Estimate the height a card needs for its title (up to two lines), optional
    /// subtitle, and optional status pill. Deliberately conservative (biases toward
    /// two title lines near the wrap threshold) so text never clips. The matching
    /// SwiftUI card caps the title at two lines, so two lines is the worst case.
    private static func cardHeight(for node: PermissionGraphNode, width: CGFloat, metrics m: Metrics, showRuntime: Bool, isHero: Bool = false) -> CGFloat {
        let titlePointSize: CGFloat = isHero ? 15 : 11
        let lineHeight = titlePointSize + 5
        let iconWidth: CGFloat = isHero ? 40 : 32
        let textWidth = max(width - (iconWidth + 10 + 24 + 14), 40)
        let charsPerLine = max(Int(textWidth / (titlePointSize * 0.56)), 8)
        let titleLines = Double(node.title.count) <= Double(charsPerLine) * 0.9 ? 1 : 2
        let titleH = CGFloat(titleLines) * lineHeight

        let hasSubtitle = (node.subtitle?.isEmpty == false)
        let subtitleH: CGFloat = hasSubtitle ? 14 : 0
        let pillH: CGFloat = (showRuntime && node.runtimeStatus != .notChecked) ? 20 : 0
        let interRowSpacing: CGFloat = 3 * (CGFloat([true, hasSubtitle, pillH > 0].filter { $0 }.count) - 1)
        let verticalPadding: CGFloat = isHero ? 24 : 18

        let content = titleH + subtitleH + pillH + max(interRowSpacing, 0) + verticalPadding
        let floor = isHero ? m.minSelectedHeight : m.minRowHeight
        return max(floor, content)
    }
}
