import XCTest
@testable import ForsettiJamfProApp

/// Tests for the Permissions Helper (Permissions Matrix) module: that the bundled
/// v4 resource decodes, that counts and required commands are intact, that the
/// heterogeneous requirement modes flatten correctly, and that command filtering
/// narrows results. These run offline — no Jamf connectivity required.
final class PermissionsMatrixTests: XCTestCase {

    // The bundled resource lives in the host app bundle; `Bundle(for:)` resolves
    // to it because this view model is compiled into the app under @testable.
    private var moduleBundle: Bundle { Bundle(for: PermissionsMatrixViewModel.self) }

    private func loadDocument() async throws -> PermissionsMatrixDocument {
        let loader = PermissionsMatrixResourceLoader(
            bundle: moduleBundle,
            diagnosticsReporter: NoopDiagnosticsReporter()
        )
        return try await loader.loadMatrix()
    }

    // MARK: - Decode & counts

    func test_resourceIsBundledAndDecodes() async throws {
        let document = try await loadDocument()
        XCTAssertEqual(document.schemaVersion.isEmpty, false, "Schema version should decode.")
        XCTAssertFalse(document.actions.isEmpty, "Actions should decode. If this is empty the JSON likely did not bundle into the app target.")
    }

    func test_coverageCountsMatchVerifiedBaseline() async throws {
        let document = try await loadDocument()
        XCTAssertEqual(document.actions.count, 87, "Action count")
        XCTAssertEqual(document.privileges.count, 263, "Privilege count")
        XCTAssertEqual(document.endpointCatalog.modernJamfProAPI.count, 458, "Modern endpoint count")
        XCTAssertEqual(document.endpointCatalog.classicAPI.count, 106, "Classic endpoint count")
        XCTAssertEqual(document.endpointCatalog.mdmCommandTypeOverlays.count, 19, "MDM overlay count")
    }

    func test_requiredCommandsArePresent() async throws {
        let document = try await loadDocument()
        let ids = Set(document.actions.map(\.commandID))
        let missing = PermissionsMatrixResourceLoader.requiredCommandIDs.subtracting(ids)
        XCTAssertTrue(missing.isEmpty, "Missing required commands: \(missing.sorted())")
    }

    // MARK: - Requirement-mode handling

    func test_allOfAndOverlayModes_blankPush() async throws {
        let document = try await loadDocument()
        let blankPush = try XCTUnwrap(document.actions.first { $0.commandID == "support.action.blank_push" })

        // all_of contributes to the hard-required set.
        XCTAssertTrue(
            blankPush.hardRequiredPrivilegeNames.contains("View MDM command information in Jamf Pro API"),
            "Blank Push should hard-require the MDM command information privilege."
        )

        // optional_runtime_overlay contributes to alternatives, NOT hard-required.
        XCTAssertTrue(blankPush.alternativePrivilegeNames.contains("Send Computer Blank Push"))
        XCTAssertTrue(blankPush.alternativePrivilegeNames.contains("Send Mobile Device Blank Push"))
        XCTAssertFalse(blankPush.hardRequiredPrivilegeNames.contains("Send Computer Blank Push"))

        // The overlay requirement decodes its nested privilege_sets.
        let overlay = try XCTUnwrap(blankPush.requiredPrivilegeRequirements.first { $0.mode == "optional_runtime_overlay" })
        XCTAssertEqual(overlay.privilegeSets?.count, 2)
    }

    func test_anyOfMode_isAlternativeNotHardRequired() async throws {
        let document = try await loadDocument()
        let action = try XCTUnwrap(document.actions.first { $0.commandID == "mobile_search.read_extension_attribute_catalog" })
        XCTAssertTrue(action.hardRequiredPrivilegeNames.isEmpty, "any_of sets are alternatives, not hard-required.")
        XCTAssertTrue(action.alternativePrivilegeNames.contains("Read Mobile Device Extension Attributes"))
    }

    func test_conditionalByAssetType_selectsMixedBranch() async throws {
        let document = try await loadDocument()
        let action = try XCTUnwrap(document.actions.first { $0.commandID == "support.action.schedule_os_update" })
        // Scope is "mixed", so the mixed_or_group branch is the hard-required set.
        let required = action.hardRequiredPrivilegeNames
        XCTAssertTrue(required.contains("Create Managed Software Updates"))
        XCTAssertTrue(required.contains("Read Computers"))
        XCTAssertTrue(required.contains("Read Mobile Devices"))
    }

    // MARK: - Endpoint surface classification

    func test_classicEndpointsAreClassifiedAsClassic() async throws {
        let document = try await loadDocument()
        let wifi = document.endpointCatalog.classicAPI + document.endpointCatalog.modernJamfProAPI
        let jssEntry = try XCTUnwrap(wifi.first { $0.path.contains("JSSResource") })
        XCTAssertTrue(jssEntry.isClassic)

        let modernEntry = try XCTUnwrap(document.endpointCatalog.modernJamfProAPI.first { $0.path.hasPrefix("/api/") })
        XCTAssertFalse(modernEntry.isClassic)
    }

    // MARK: - Filtering

    func test_commandFilter_matchesByDisplayName() async throws {
        let document = try await loadDocument()
        let results = document.actions.filter {
            PermissionsMatrixActionFilter.matches($0, query: "blank push", module: nil, deviceFamily: nil, destructiveOnly: false, tenantVerificationOnly: false)
        }
        XCTAssertTrue(results.contains { $0.commandID == "support.action.blank_push" })
    }

    func test_commandFilter_moduleFilterExcludesOtherModules() async throws {
        let document = try await loadDocument()
        let results = document.actions.filter {
            PermissionsMatrixActionFilter.matches($0, query: "", module: "SupportTechnician", deviceFamily: nil, destructiveOnly: false, tenantVerificationOnly: false)
        }
        XCTAssertFalse(results.isEmpty)
        XCTAssertTrue(results.allSatisfy { $0.module == "SupportTechnician" })
    }

    func test_commandFilter_privilegeNameMatch() async throws {
        let document = try await loadDocument()
        let results = document.actions.filter {
            PermissionsMatrixActionFilter.matches($0, query: "Send Mobile Device Blank Push", module: nil, deviceFamily: nil, destructiveOnly: false, tenantVerificationOnly: false)
        }
        XCTAssertTrue(results.contains { $0.commandID == "support.action.blank_push" }, "Searching a privilege name should surface actions that require it.")
    }
}

/// Minimal no-op diagnostics reporter for tests.
private actor NoopDiagnosticsReporter: DiagnosticsReporting {
    func report(source: String, category: String, severity: DiagnosticSeverity, message: String, metadata: [String: String]) async {}
    func currentEvents() async -> [DiagnosticEvent] { [] }
    func renderJSONReportData() async throws -> Data { Data() }
    func renderMarkdownReportData() async throws -> Data { Data() }
    func suggestedExportFileName(extension ext: String) async -> String { "diagnostics.\(ext)" }
    func clear() async {}
    func persistentLogFileURL() async -> URL? { nil }
}
