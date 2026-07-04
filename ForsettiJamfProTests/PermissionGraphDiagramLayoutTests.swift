import XCTest
@testable import ForsettiJamfProApp

/// Tests for the premium tiered diagram layout: the two-track hierarchy is placed
/// into deterministic, finite card frames in three columns; overlay nodes are
/// excluded; connectors only reference placed cards; and the real bundled matrix
/// lays out cleanly for every action.
final class PermissionGraphDiagramLayoutTests: XCTestCase {

    private var moduleBundle: Bundle { Bundle(for: PermissionsMatrixViewModel.self) }
    private let builder = PermissionGraphSceneBuilder()

    private func loadDocument() async throws -> PermissionsMatrixDocument {
        let loader = PermissionsMatrixResourceLoader(bundle: moduleBundle, diagnosticsReporter: DiagramTestDiag())
        return try await loader.loadMatrix()
    }

    // MARK: - Synthetic structural checks

    private func node(_ id: String, _ kind: PermissionGraphNodeKind, _ layer: PermissionGraphLayer, parent: String?) -> PermissionGraphNode {
        PermissionGraphNode(
            id: id, kind: kind, layer: layer, title: id, subtitle: nil, detail: nil,
            surface: .mixed, runtimeStatus: .notChecked, riskFlags: [], parentID: parent, sourceRecordID: nil
        )
    }

    private func syntheticSnapshot() -> PermissionGraphSceneSnapshot {
        let nodes = [
            node("sel", .selected_item, .selectedItem, parent: nil),
            node("g", .privilege_group, .privilegeGroups, parent: "sel"),
            node("p", .privilege, .privileges, parent: "g"),
            node("fam", .endpoint_family, .endpointFamilies, parent: "sel"),
            node("ep", .endpoint, .endpoints, parent: "fam"),
            node("runtime", .runtime_status, .runtimeOverlays, parent: "sel"),
            node("risk", .risk_flag, .runtimeOverlays, parent: "sel")
        ]
        let edges = [
            PermissionGraphEdge(id: "e1", fromNodeID: "sel", toNodeID: "g", kind: .requires, isSelectedPath: true),
            PermissionGraphEdge(id: "e2", fromNodeID: "g", toNodeID: "p", kind: .contains, isSelectedPath: true),
            PermissionGraphEdge(id: "e3", fromNodeID: "sel", toNodeID: "fam", kind: .implemented_by),
            PermissionGraphEdge(id: "e4", fromNodeID: "fam", toNodeID: "ep", kind: .contains),
            PermissionGraphEdge(id: "e5", fromNodeID: "runtime", toNodeID: "sel", kind: .runtime_reports),
            PermissionGraphEdge(id: "e6", fromNodeID: "risk", toNodeID: "sel", kind: .warning)
        ]
        return PermissionGraphSceneSnapshot(selectedItemID: "sel", title: "Sel", nodes: nodes, edges: edges)
    }

    func test_columnsAndExclusions() {
        let layout = PermissionGraphDiagramLayout.make(syntheticSnapshot())

        // Overlay kinds are excluded from the columns.
        XCTAssertNil(layout.frame(for: "runtime"))
        XCTAssertNil(layout.frame(for: "risk"))
        XCTAssertEqual(layout.cards.count, 5)

        func column(_ id: String) -> Int? { layout.cards.first { $0.id == id }?.column }
        XCTAssertEqual(column("sel"), 0)
        XCTAssertEqual(column("g"), 1)
        XCTAssertEqual(column("fam"), 1)
        XCTAssertEqual(column("p"), 2)
        XCTAssertEqual(column("ep"), 2)

        // Columns advance left-to-right.
        let selX = layout.frame(for: "sel")!.minX
        let gX = layout.frame(for: "g")!.minX
        let pX = layout.frame(for: "p")!.minX
        XCTAssertLessThan(selX, gX)
        XCTAssertLessThan(gX, pX)
    }

    func test_connectorsOnlyReferencePlacedCards() {
        let layout = PermissionGraphDiagramLayout.make(syntheticSnapshot())
        // Edges touching the excluded runtime/risk nodes are dropped → 4 connectors.
        XCTAssertEqual(layout.connectors.count, 4)
        for c in layout.connectors {
            XCTAssertTrue(c.from.x.isFinite && c.from.y.isFinite && c.to.x.isFinite && c.to.y.isFinite)
        }
        XCTAssertTrue(layout.connectors.contains { $0.id == "e1" && $0.isSelectedPath })
        XCTAssertFalse(layout.connectors.contains { $0.id == "e5" || $0.id == "e6" })
    }

    func test_selectedCardCenteredBetweenBands() {
        let layout = PermissionGraphDiagramLayout.make(syntheticSnapshot())
        let sel = layout.frame(for: "sel")!
        let bandCards = layout.cards.filter { $0.column != 0 }.map(\.frame)
        let minY = bandCards.map(\.minY).min()!
        let maxY = bandCards.map(\.maxY).max()!
        XCTAssertGreaterThanOrEqual(sel.midY, minY - 1)
        XCTAssertLessThanOrEqual(sel.midY, maxY + 1)
    }

    func test_deterministic() {
        let s = syntheticSnapshot()
        XCTAssertEqual(PermissionGraphDiagramLayout.make(s), PermissionGraphDiagramLayout.make(s))
    }

    func test_emptyWhenNoSelectedItem() {
        let snapshot = PermissionGraphSceneSnapshot(selectedItemID: "x", title: "x", nodes: [], edges: [])
        XCTAssertEqual(PermissionGraphDiagramLayout.make(snapshot), .empty)
    }

    func test_longTitleProducesTallerCardThanShort() {
        func privilege(_ title: String) -> PermissionGraphNode {
            PermissionGraphNode(id: "p", kind: .privilege, layer: .privileges, title: title,
                                subtitle: "Required privilege", detail: nil, surface: .mixed,
                                runtimeStatus: .missing, riskFlags: [], parentID: "g", sourceRecordID: nil)
        }
        func cardHeight(_ p: PermissionGraphNode) -> CGFloat {
            let nodes = [
                node("sel", .selected_item, .selectedItem, parent: nil),
                node("g", .privilege_group, .privilegeGroups, parent: "sel"),
                p
            ]
            let edges = [
                PermissionGraphEdge(id: "e1", fromNodeID: "sel", toNodeID: "g", kind: .requires),
                PermissionGraphEdge(id: "e2", fromNodeID: "g", toNodeID: "p", kind: .contains)
            ]
            let snap = PermissionGraphSceneSnapshot(selectedItemID: "sel", title: "Sel", nodes: nodes, edges: edges)
            return PermissionGraphDiagramLayout.make(snap).frame(for: "p")!.height
        }
        let short = cardHeight(privilege("Read"))
        let long = cardHeight(privilege("Send Mobile Device Remote Command to Download and Install iOS Update"))
        XCTAssertGreaterThan(long, short, "a long, wrapping title must grow the card so nothing clips")
    }

    // MARK: - Real matrix

    func test_blankPush_diagramHasBothBands() async throws {
        let doc = try await loadDocument()
        let action = try XCTUnwrap(doc.actions.first { $0.commandID == "support.action.blank_push" })
        let snapshot = builder.snapshot(for: action, overlays: doc.endpointCatalog.mdmCommandTypeOverlays)
        let layout = PermissionGraphDiagramLayout.make(snapshot)

        XCTAssertEqual(layout.bands.count, 2, "Blank Push has both a privilege band and an endpoint band")
        XCTAssertGreaterThan(layout.contentSize.width, 0)
        XCTAssertGreaterThan(layout.contentSize.height, 0)
        // Every column node is placed; only runtime-status / risk-flag overlays are
        // excluded. Command-overlay nodes ARE placed (as col-2 cards under the MDM family).
        let placed = Set(layout.cards.map(\.id))
        for n in snapshot.nodes where n.kind != .runtime_status && n.kind != .risk_flag {
            XCTAssertTrue(placed.contains(n.id), "missing card for \(n.id)")
        }
        // No runtime / risk overlay node is placed as a column card.
        for n in snapshot.nodes where n.kind == .runtime_status || n.kind == .risk_flag {
            XCTAssertNil(layout.frame(for: n.id), "overlay node \(n.id) should not be a column card")
        }
        // Any command overlays present land in column 2.
        for card in layout.cards where snapshot.node(id: card.id)?.kind == .command_overlay {
            XCTAssertEqual(card.column, 2, "command overlay should be a col-2 card")
        }
    }

    func test_allActionsLayoutFiniteAndNonNegative() async throws {
        let doc = try await loadDocument()
        for action in doc.actions where action.localOnly == false {
            let layout = PermissionGraphDiagramLayout.make(builder.snapshot(for: action))
            XCTAssertTrue(layout.contentSize.width.isFinite && layout.contentSize.height.isFinite,
                          "non-finite content size for \(action.commandID)")
            for card in layout.cards {
                XCTAssertGreaterThanOrEqual(card.frame.minX, 0, "negative x for \(action.commandID)")
                XCTAssertGreaterThanOrEqual(card.frame.minY, 0, "negative y for \(action.commandID)")
                XCTAssertTrue(card.frame.width > 0 && card.frame.height > 0)
            }
        }
    }
}

private actor DiagramTestDiag: DiagnosticsReporting {
    func report(source: String, category: String, severity: DiagnosticSeverity, message: String, metadata: [String: String]) async {}
    func currentEvents() async -> [DiagnosticEvent] { [] }
    func renderJSONReportData() async throws -> Data { Data() }
    func renderMarkdownReportData() async throws -> Data { Data() }
    func suggestedExportFileName(extension ext: String) async -> String { "d.\(ext)" }
    func clear() async {}
    func persistentLogFileURL() async -> URL? { nil }
}
