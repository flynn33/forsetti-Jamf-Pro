import XCTest
@testable import Forsetti

/// Tests for the visual hierarchy scene builder: it maps the real bundled matrix
/// into a layered snapshot, runtime states map correctly, and layout positions are
/// finite/deterministic. (The premium diagram layout is covered separately by
/// `PermissionGraphDiagramLayoutTests`.)
final class PermissionGraphSceneBuilderTests: XCTestCase {

    private var moduleBundle: Bundle { Bundle(for: PermissionsMatrixModule.self) }
    private let builder = PermissionGraphSceneBuilder()

    private func loadDocument() async throws -> PermissionsMatrixDocument {
        let loader = PermissionsMatrixResourceLoader(bundle: moduleBundle, diagnosticsReporter: GraphTestDiag())
        return try await loader.loadMatrix()
    }

    private func action(_ id: String, in doc: PermissionsMatrixDocument) throws -> PermissionsMatrixAction {
        try XCTUnwrap(doc.actions.first { $0.commandID == id }, "missing action \(id)")
    }

    // MARK: - Blank Push hierarchy

    func test_blankPush_buildsLayeredHierarchy() async throws {
        let doc = try await loadDocument()
        let snapshot = builder.snapshot(for: try action("support.action.blank_push", in: doc), overlays: doc.endpointCatalog.mdmCommandTypeOverlays)

        XCTAssertEqual(snapshot.nodes.filter { $0.kind == .selected_item }.count, 1)
        XCTAssertTrue(snapshot.nodes.contains { $0.kind == .privilege_group && $0.title == "MDM Command Visibility" })
        XCTAssertTrue(snapshot.nodes.contains { $0.kind == .privilege && $0.title == "View MDM command information in Jamf Pro API" })
        XCTAssertTrue(snapshot.nodes.contains { $0.kind == .endpoint_family && $0.surface == .modern })
        XCTAssertTrue(snapshot.nodes.contains { $0.kind == .endpoint && $0.title.contains("mdm/blank-push") })

        // Overlay (tenant) privileges land in a runtime/tenant group and carry the flag.
        XCTAssertTrue(snapshot.nodes.contains { $0.title == "Send Computer Blank Push" && $0.riskFlags.contains(.tenant_verify) })

        let kinds = Set(snapshot.edges.map(\.kind))
        XCTAssertTrue(kinds.contains(.requires))
        XCTAssertTrue(kinds.contains(.contains))
        XCTAssertTrue(kinds.contains(.implemented_by))

        for node in snapshot.nodes {
            XCTAssertTrue(node.position.x.isFinite && node.position.y.isFinite && node.position.z.isFinite, "non-finite 3D position")
            XCTAssertTrue(node.blueprintPosition.x.isFinite && node.blueprintPosition.y.isFinite, "non-finite blueprint position")
        }
    }

    func test_blankPush_isDeterministic() async throws {
        let doc = try await loadDocument()
        let a = builder.snapshot(for: try action("support.action.blank_push", in: doc))
        let b = builder.snapshot(for: try action("support.action.blank_push", in: doc))
        XCTAssertEqual(a.nodes.map(\.id), b.nodes.map(\.id))
        XCTAssertEqual(a.edges.map(\.id), b.edges.map(\.id))
    }

    // MARK: - Runtime-state mapping

    func test_runtimeMapping() async throws {
        let doc = try await loadDocument()
        let blankPush = try action("support.action.blank_push", in: doc)
        let privilege = "View MDM command information in Jamf Pro API"

        let confirmed = PermissionsMatrixComparisonResult(
            state: .comparisonComplete, confirmedPresent: [privilege], notConfirmed: [],
            alternativesNotPresent: [], tokenPrivilegeCount: 1, apiRoleCatalogAvailable: true, userFacingError: nil)
        let s1 = builder.snapshot(for: blankPush, comparison: confirmed)
        XCTAssertEqual(s1.nodes.first { $0.title == privilege }?.runtimeStatus, .available)
        XCTAssertTrue(s1.nodes.contains { $0.kind == .runtime_status })

        let missing = PermissionsMatrixComparisonResult(
            state: .comparisonComplete, confirmedPresent: [], notConfirmed: [privilege],
            alternativesNotPresent: [], tokenPrivilegeCount: 0, apiRoleCatalogAvailable: true, userFacingError: nil)
        let s2 = builder.snapshot(for: blankPush, comparison: missing)
        XCTAssertEqual(s2.nodes.first { $0.title == privilege }?.runtimeStatus, .missing)

        let s3 = builder.snapshot(for: blankPush, comparison: nil)
        XCTAssertEqual(s3.nodes.first { $0.title == privilege }?.runtimeStatus, .notChecked)
    }

    // MARK: - Classic surface / risk

    func test_classicSurfaceCarriesRiskFlag() async throws {
        let doc = try await loadDocument()
        let wifi = try action("support.action.enable_wifi", in: doc)
        let snapshot = builder.snapshot(for: wifi)
        let classicFamily = snapshot.nodes.first { $0.kind == .endpoint_family && $0.surface == .classic }
        XCTAssertNotNil(classicFamily, "Wi-Fi enable uses a Classic API endpoint family")
        XCTAssertTrue(classicFamily?.riskFlags.contains(.classic_api) ?? false)
    }

    // MARK: - Privilege scene

    func test_privilegeScene() async throws {
        let doc = try await loadDocument()
        let counts = Dictionary(grouping: doc.actions.flatMap { a in a.allPrivilegeNames.map { ($0, a) } }, by: { $0.0 })
        let privilege = try XCTUnwrap(counts.max(by: { $0.value.count < $1.value.count })?.key)
        let actions = doc.actions.filter { $0.allPrivilegeNames.contains(privilege) }
        let endpoints = (doc.endpointCatalog.modernJamfProAPI + doc.endpointCatalog.classicAPI).filter { $0.requiredPrivileges.contains(privilege) }
        let snapshot = builder.snapshot(forPrivilege: privilege, actions: actions, endpoints: endpoints)
        XCTAssertEqual(snapshot.nodes.first { $0.kind == .selected_item }?.title, privilege)
        XCTAssertTrue(snapshot.nodes.contains { $0.kind == .privilege })  // related action nodes live in the privileges layer
        for node in snapshot.nodes { XCTAssertTrue(node.position.x.isFinite && node.blueprintPosition.y.isFinite) }
    }

    // MARK: - Layout finiteness across many actions

    func test_allActionsProduceFiniteLayout() async throws {
        let doc = try await loadDocument()
        for action in doc.actions where action.localOnly == false {
            let snapshot = builder.snapshot(for: action)
            for node in snapshot.nodes {
                XCTAssertTrue(node.position.x.isFinite && node.position.y.isFinite && node.position.z.isFinite,
                              "non-finite position for \(action.commandID)")
            }
        }
    }

}

private actor GraphTestDiag: DiagnosticsReporting {
    func report(source: String, category: String, severity: DiagnosticSeverity, message: String, metadata: [String: String]) async {}
    func currentEvents() async -> [DiagnosticEvent] { [] }
    func renderJSONReportData() async throws -> Data { Data() }
    func renderMarkdownReportData() async throws -> Data { Data() }
    func suggestedExportFileName(extension ext: String) async -> String { "d.\(ext)" }
    func clear() async {}
    func persistentLogFileURL() async -> URL? { nil }
}
