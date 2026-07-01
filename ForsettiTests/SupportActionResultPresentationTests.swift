import XCTest
@testable import Forsetti

/// Verifies the pure mapping that splits a server action result into its two
/// UI surfaces: the one-time credential popup and the non-secret sidebar
/// summary frame. The security-critical invariant is that the secret value
/// reaches the popup but is never present in the summary.
final class SupportActionResultPresentationTests: XCTestCase {

    func test_resultWithSensitiveValue_producesCredentialPopup() {
        let result = SupportActionResult(
            title: "View Local Admin Password",
            detail: "Retrieved LAPS password for admin.",
            sensitiveValue: "S3cr3t-P@ss"
        )

        let presentation = SupportActionResultPresentation.make(from: result)

        XCTAssertEqual(presentation.credential?.title, "View Local Admin Password")
        XCTAssertEqual(presentation.credential?.value, "S3cr3t-P@ss")
    }

    func test_summaryNeverContainsSecret() {
        let result = SupportActionResult(
            title: "View jssmanage Password",
            detail: "Retrieved LAPS password for jssmanage.",
            sensitiveValue: "TopSecretValue123"
        )

        let presentation = SupportActionResultPresentation.make(from: result)

        XCTAssertEqual(presentation.summary.title, "View jssmanage Password")
        XCTAssertEqual(presentation.summary.detail, "Retrieved LAPS password for jssmanage.")
        XCTAssertFalse(presentation.summary.title.contains("TopSecretValue123"))
        XCTAssertFalse(presentation.summary.detail.contains("TopSecretValue123"))
    }

    func test_resultWithoutSensitiveValue_producesNoCredentialPopup() {
        let result = SupportActionResult(
            title: "Refresh Inventory",
            detail: "Requested inventory refresh.",
            sensitiveValue: nil
        )

        let presentation = SupportActionResultPresentation.make(from: result)

        XCTAssertNil(presentation.credential)
        XCTAssertEqual(presentation.summary.detail, "Requested inventory refresh.")
    }

    func test_resultWithBlankSensitiveValue_producesNoCredentialPopup() {
        let result = SupportActionResult(
            title: "View Recovery Lock Password",
            detail: "No recovery lock password is set.",
            sensitiveValue: "   "
        )

        let presentation = SupportActionResultPresentation.make(from: result)

        XCTAssertNil(presentation.credential)
    }
}
