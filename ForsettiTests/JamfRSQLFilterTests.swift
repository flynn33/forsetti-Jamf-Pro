import XCTest
@testable import Forsetti

// "End of Line"

/// Exercises the shared RSQL filter builder.
///
/// These tests lock in the audit-fixed grammar: logical OR is `,`, not
/// the literal word `or`. Regression here means strict Jamf tenants
/// would silently lose search results, so the bar is zero tolerance
/// for a wrong operator making it into the output.
final class JamfRSQLFilterTests: XCTestCase {

    // MARK: - OR operator grammar

    func test_serialOrUsername_usesCommaForLogicalOR() {
        let result = JamfRSQLFilter.serialOrUsername(query: "ABC123", useWildcard: false)
        XCTAssertEqual(result, "(serialNumber=='ABC123',username=='ABC123')")
    }

    func test_serialOrUsername_neverEmitsLiteralOrKeyword() {
        // The audit caught the mobile search paths emitting `or` between
        // conditions. This test is a belt-and-suspenders guard: if
        // anyone ever re-introduces the word, the test catches it.
        let result = JamfRSQLFilter.serialOrUsername(query: "foo", useWildcard: true) ?? ""
        XCTAssertFalse(result.lowercased().contains(" or "))
        XCTAssertFalse(result.lowercased().contains("|"))
    }

    // MARK: - Wildcard handling

    func test_serialOrUsername_withWildcard_wrapsValueInAsterisks() {
        let result = JamfRSQLFilter.serialOrUsername(query: "foo", useWildcard: true)
        XCTAssertEqual(result, "(serialNumber=='*foo*',username=='*foo*')")
    }

    func test_serialOrUsername_withoutWildcard_producesExactMatch() {
        let result = JamfRSQLFilter.serialOrUsername(query: "foo", useWildcard: false)
        XCTAssertEqual(result, "(serialNumber=='foo',username=='foo')")
    }

    // MARK: - Empty and whitespace queries

    func test_serialOrUsername_emptyQuery_returnsNil() {
        XCTAssertNil(JamfRSQLFilter.serialOrUsername(query: "", useWildcard: true))
    }

    func test_serialOrUsername_whitespaceOnly_returnsNil() {
        XCTAssertNil(JamfRSQLFilter.serialOrUsername(query: "   ", useWildcard: true))
        XCTAssertNil(JamfRSQLFilter.serialOrUsername(query: "\t\n ", useWildcard: false))
    }

    func test_serialOrUsername_trimsLeadingAndTrailingWhitespace() {
        let result = JamfRSQLFilter.serialOrUsername(query: "  ABC  ", useWildcard: false)
        XCTAssertEqual(result, "(serialNumber=='ABC',username=='ABC')")
    }

    // MARK: - Field name customization

    func test_serialOrUsername_respectsCustomFieldNames() {
        let result = JamfRSQLFilter.serialOrUsername(
            query: "XYZ",
            useWildcard: false,
            serialField: "hardware.serialNumber",
            usernameField: "location.username"
        )
        XCTAssertEqual(result, "(hardware.serialNumber=='XYZ',location.username=='XYZ')")
    }

    // MARK: - Escaping

    func test_escapeSingleQuoted_escapesBackslashesFirstThenQuotes() {
        // Order matters: backslash-then-quote ensures a literal
        // backslash doesn't get mistaken for the escape prefix of a
        // subsequently-inserted quote escape.
        XCTAssertEqual(JamfRSQLFilter.escapeSingleQuoted("a\\b"), "a\\\\b")
        XCTAssertEqual(JamfRSQLFilter.escapeSingleQuoted("a'b"), "a\\'b")
        XCTAssertEqual(JamfRSQLFilter.escapeSingleQuoted("a\\'b"), "a\\\\\\'b")
    }

    func test_serialOrUsername_escapesQuotesInsideValue() {
        // An operator searching for an exotic username like `O'Brien`
        // must produce valid RSQL — the single quote needs to be
        // escaped, not left to break out of the literal.
        let result = JamfRSQLFilter.serialOrUsername(query: "O'Brien", useWildcard: false)
        XCTAssertEqual(result, "(serialNumber=='O\\'Brien',username=='O\\'Brien')")
    }

    func test_serialOrUsername_escapesBackslashesInsideValue() {
        let result = JamfRSQLFilter.serialOrUsername(query: "domain\\user", useWildcard: false)
        XCTAssertEqual(result, "(serialNumber=='domain\\\\user',username=='domain\\\\user')")
    }
}

//endofline
