import XCTest
@testable import Forsetti

// "End of Line"

/// Exercises `JamfCredentials.normalizedServerURL` — the canonical
/// URL derivation that prevents the `/api/api/...` double-path bug
/// the audit flagged.
///
/// Prior behavior: any stored URL was accepted as-is. An operator
/// typing `https://tenant.jamfcloud.com/api` (a common mistake —
/// that's what they see in the browser URL bar) caused every
/// gateway request to build `.../api/api/v1/...` and 404. The fix
/// is to strip path/query/fragment, enforce http(s), and require
/// a non-empty host.
final class JamfCredentialsURLTests: XCTestCase {

    // MARK: - Happy path

    func test_normalizedServerURL_keepsSchemeHostAndPort() {
        let credentials = makeCredentials(serverURL: "https://tenant.jamfcloud.com")
        XCTAssertEqual(credentials.normalizedServerURL?.absoluteString, "https://tenant.jamfcloud.com")
    }

    func test_normalizedServerURL_preservesExplicitPort() {
        let credentials = makeCredentials(serverURL: "https://tenant.jamfcloud.com:8443")
        XCTAssertEqual(credentials.normalizedServerURL?.absoluteString, "https://tenant.jamfcloud.com:8443")
    }

    func test_normalizedServerURL_addsHTTPSWhenSchemeMissing() {
        let credentials = makeCredentials(serverURL: "tenant.jamfcloud.com")
        XCTAssertEqual(credentials.normalizedServerURL?.absoluteString, "https://tenant.jamfcloud.com")
    }

    // MARK: - Stripping path / query / fragment

    func test_normalizedServerURL_stripsPathSegment() {
        let credentials = makeCredentials(serverURL: "https://tenant.jamfcloud.com/api")
        XCTAssertEqual(credentials.normalizedServerURL?.absoluteString, "https://tenant.jamfcloud.com")
    }

    func test_normalizedServerURL_stripsDeepPathSegment() {
        let credentials = makeCredentials(serverURL: "https://tenant.jamfcloud.com/api/v1/computers")
        XCTAssertEqual(credentials.normalizedServerURL?.absoluteString, "https://tenant.jamfcloud.com")
    }

    func test_normalizedServerURL_stripsQueryString() {
        let credentials = makeCredentials(serverURL: "https://tenant.jamfcloud.com?foo=bar")
        XCTAssertEqual(credentials.normalizedServerURL?.absoluteString, "https://tenant.jamfcloud.com")
    }

    func test_normalizedServerURL_stripsFragment() {
        let credentials = makeCredentials(serverURL: "https://tenant.jamfcloud.com#section")
        XCTAssertEqual(credentials.normalizedServerURL?.absoluteString, "https://tenant.jamfcloud.com")
    }

    func test_normalizedServerURL_stripsTrailingSlash() {
        let credentials = makeCredentials(serverURL: "https://tenant.jamfcloud.com/")
        XCTAssertEqual(credentials.normalizedServerURL?.absoluteString, "https://tenant.jamfcloud.com")
    }

    // MARK: - Whitespace handling

    func test_normalizedServerURL_trimsLeadingAndTrailingWhitespace() {
        let credentials = makeCredentials(serverURL: "   https://tenant.jamfcloud.com   ")
        XCTAssertEqual(credentials.normalizedServerURL?.absoluteString, "https://tenant.jamfcloud.com")
    }

    // MARK: - Rejection

    func test_normalizedServerURL_emptyString_returnsNil() {
        let credentials = makeCredentials(serverURL: "")
        XCTAssertNil(credentials.normalizedServerURL)
    }

    func test_normalizedServerURL_whitespaceOnly_returnsNil() {
        let credentials = makeCredentials(serverURL: "   ")
        XCTAssertNil(credentials.normalizedServerURL)
    }

    func test_normalizedServerURL_fileScheme_returnsNil() {
        let credentials = makeCredentials(serverURL: "file:///etc/passwd")
        XCTAssertNil(credentials.normalizedServerURL)
    }

    func test_normalizedServerURL_ftpScheme_returnsNil() {
        let credentials = makeCredentials(serverURL: "ftp://tenant.jamfcloud.com")
        XCTAssertNil(credentials.normalizedServerURL)
    }

    func test_normalizedServerURL_schemeOnlyNoHost_returnsNil() {
        let credentials = makeCredentials(serverURL: "https://")
        XCTAssertNil(credentials.normalizedServerURL)
    }

    // MARK: - Helpers

    private func makeCredentials(serverURL: String) -> JamfCredentials {
        JamfCredentials(
            serverURL: serverURL,
            authenticationMethod: .apiClient,
            clientID: "id",
            clientSecret: "secret",
            accountUsername: "",
            accountPassword: "",
            oauthScope: ""
        )
    }
}

//endofline
