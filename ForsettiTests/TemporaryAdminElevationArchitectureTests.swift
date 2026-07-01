import XCTest
@testable import Forsetti

/// Static guardrail tests that prove the Temporary Admin Elevation feature
/// preserves the project's architecture contracts. They scan the feature's
/// source files (located relative to this test file) for prohibited patterns.
final class TemporaryAdminElevationArchitectureTests: XCTestCase {

    /// Feature source files, relative to the repository root.
    private let featureFiles = [
        "ForsettiApp/Modules/SupportTechnician/Models/TemporaryAdminElevationModels.swift",
        "ForsettiApp/Modules/SupportTechnician/Models/TemporaryAdminElevationSnapshotParser.swift",
        "ForsettiApp/Modules/SupportTechnician/Models/TemporaryAdminUserFacingError+Mapping.swift",
        "ForsettiApp/Modules/SupportTechnician/Services/TemporaryAdminElevationService.swift",
        "ForsettiApp/Modules/SupportTechnician/ViewModels/TemporaryAdminElevationController.swift",
        "ForsettiApp/Modules/SupportTechnician/Views/Frames/TemporaryAdminElevationFrame.swift",
        "ForsettiApp/Framework/Networking/JamfComputerRequestScopeService.swift"
    ]

    private var repoRoot: URL {
        // <repo>/ForsettiAppTests/<thisFile>.swift → two parents up = <repo>.
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }

    private func contents(of relativePath: String) throws -> String {
        let url = repoRoot.appendingPathComponent(relativePath)
        guard FileManager.default.fileExists(atPath: url.path) else {
            XCTFail("Feature file missing (rename it here too if you moved it): \(relativePath)")
            return ""
        }
        return try String(contentsOf: url, encoding: .utf8)
    }

    private func forEachFeatureFile(_ assert: (String, String) throws -> Void) throws {
        for path in featureFiles {
            let text = try contents(of: path)
            XCTAssertFalse(text.isEmpty, "Feature file unexpectedly empty: \(path)")
            try assert(path, text)
        }
    }

    func test_featureDoesNotUseDirectURLSession() throws {
        // All Jamf networking must go through the framework gateway abstraction.
        try forEachFeatureFile { path, text in
            XCTAssertFalse(text.contains("URLSession"), "Feature file uses URLSession directly: \(path)")
        }
    }

    func test_featureDoesNotCreateDynamicPoliciesOrScripts() throws {
        // The feature only updates dedicated static-group membership; it must not
        // reference policy/script creation endpoints.
        let forbidden = ["/policies", "JSSResource/policies", "/scripts", "JSSResource/scripts", "computercommands"]
        try forEachFeatureFile { path, text in
            for token in forbidden {
                XCTAssertFalse(text.contains(token), "Feature file references a policy/script endpoint (\(token)): \(path)")
            }
        }
    }

    func test_featureDoesNotIntroduceNewAuthCredentialOrDiagnosticsStack() throws {
        // No new auth manager, credential store, diagnostics system, or app
        // container — the feature reuses the existing framework services.
        let forbidden = [
            "JamfCredentialsStore(",
            "JamfAuthenticationService(",
            "DiagnosticsCenter(",
            "class JamfCredentials",
            "class JamfAuthentication",
            "protocol DiagnosticsReporting"
        ]
        try forEachFeatureFile { path, text in
            for token in forbidden {
                XCTAssertFalse(text.contains(token), "Feature file introduces a forbidden stack (\(token)): \(path)")
            }
        }
    }

    func test_noImplementationToolAttributionMarkers() throws {
        // Same policy as the package validator: no implementation-tool or
        // external-authorship markers. Terms are assembled from fragments so this
        // test file does not itself contain the literal markers.
        let restricted = [
            "chat" + "gpt", "open" + "ai", "cl" + "aude", "co" + "dex",
            "gr" + "ok", "anth" + "ropic", "x" + ".ai",
            "generated " + "by", "created " + "by", "implemented " + "by", "assisted " + "by"
        ]
        try forEachFeatureFile { path, text in
            let lower = text.lowercased()
            for term in restricted {
                XCTAssertFalse(lower.contains(term), "Feature file contains a prohibited attribution marker: \(path)")
            }
        }
    }

    func test_mobileDevicesCannotTriggerElevation() {
        // The validator is the single gate every request flows through.
        let result = TemporaryAdminElevationValidator.validate(
            assetType: .mobileDevice,
            isManaged: true,
            inventoryID: "1",
            duration: .fifteen,
            hasConfiguredScope: true,
            reason: "needs admin",
            ticketReference: "TICKET-1",
            requiresTicket: true
        )
        XCTAssertFalse(result.isValid, "A mobile device must never pass validation.")
    }
}
