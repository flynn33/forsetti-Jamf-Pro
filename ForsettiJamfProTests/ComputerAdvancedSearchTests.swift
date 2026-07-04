import XCTest
@testable import ForsettiJamfProApp

// "End of Line"

/// Exercises the computer-side RSQL composer (`composeForComputers`) used by
/// the computer Advanced Search builder.
///
/// The shape contract these tests lock in mirrors the mobile composer:
/// - Every group is parenthesized — no exceptions, even single-criterion groups.
/// - Single-quote literals always pass through `JamfRSQLFilter.escapeSingleQuoted`.
/// - Wildcard wrapping happens AFTER escaping.
/// - Unknown field keys are silently dropped — composer never throws.
/// - All-empty queries produce a nil server filter.
/// - Fields whose `isServerFilterable == false` (e.g. the storage display
///   fields, which are not RSQL-searchable) route to `clientCriteria` instead
///   of the server filter.
final class ComputerAdvancedSearchTests: XCTestCase {

    private var lookup: [String: ComputerField] {
        ComputerField.keyLookup
    }

    // MARK: - Single criterion shapes

    func test_singleEqualsString_emitsParenthesizedFragment() {
        let query = AdvancedQuery(groups: [
            AdvancedQueryGroup(criteria: [
                AdvancedQueryCriterion(fieldKey: "general.name", op: .equals, value: .string("MacBook"))
            ])
        ])
        let result = JamfRSQLComposer.composeForComputers(query, fieldLookup: lookup)
        XCTAssertEqual(result.serverFilter, "(general.name=='MacBook')")
    }

    func test_containsWrapsWildcardsBothSides() {
        let query = AdvancedQuery(groups: [
            AdvancedQueryGroup(criteria: [
                AdvancedQueryCriterion(fieldKey: "hardware.model", op: .contains, value: .string("Pro"))
            ])
        ])
        let result = JamfRSQLComposer.composeForComputers(query, fieldLookup: lookup)
        XCTAssertEqual(result.serverFilter, "(hardware.model=='*Pro*')")
    }

    func test_startsWithUsesTrailingWildcardOnly() {
        let query = AdvancedQuery(groups: [
            AdvancedQueryGroup(criteria: [
                AdvancedQueryCriterion(fieldKey: "general.name", op: .startsWith, value: .string("LAB-"))
            ])
        ])
        let result = JamfRSQLComposer.composeForComputers(query, fieldLookup: lookup)
        XCTAssertEqual(result.serverFilter, "(general.name=='LAB-*')")
    }

    func test_endsWithUsesLeadingWildcardOnly() {
        let query = AdvancedQuery(groups: [
            AdvancedQueryGroup(criteria: [
                AdvancedQueryCriterion(fieldKey: "hardware.model", op: .endsWith, value: .string("Air"))
            ])
        ])
        let result = JamfRSQLComposer.composeForComputers(query, fieldLookup: lookup)
        XCTAssertEqual(result.serverFilter, "(hardware.model=='*Air')")
    }

    func test_notEqualsEmitsBangEquals() {
        let query = AdvancedQuery(groups: [
            AdvancedQueryGroup(criteria: [
                AdvancedQueryCriterion(fieldKey: "userAndLocation.username", op: .notEquals, value: .string("admin"))
            ])
        ])
        let result = JamfRSQLComposer.composeForComputers(query, fieldLookup: lookup)
        XCTAssertEqual(result.serverFilter, "(userAndLocation.username!='admin')")
    }

    func test_isTrueEmitsLiteralBool() {
        let query = AdvancedQuery(groups: [
            AdvancedQueryGroup(criteria: [
                AdvancedQueryCriterion(fieldKey: "hardware.appleSilicon", op: .isTrue, value: .bool(true))
            ])
        ])
        let result = JamfRSQLComposer.composeForComputers(query, fieldLookup: lookup)
        XCTAssertEqual(result.serverFilter, "(hardware.appleSilicon==true)")
    }

    // MARK: - Combinator semantics

    func test_andOfTwoCriteriaJoinsWithSemicolon() {
        let query = AdvancedQuery(groups: [
            AdvancedQueryGroup(combinator: .and, criteria: [
                AdvancedQueryCriterion(fieldKey: "general.name", op: .equals, value: .string("LAB-01")),
                AdvancedQueryCriterion(fieldKey: "hardware.model", op: .contains, value: .string("Pro"))
            ])
        ])
        let result = JamfRSQLComposer.composeForComputers(query, fieldLookup: lookup)
        XCTAssertEqual(result.serverFilter, "(general.name=='LAB-01';hardware.model=='*Pro*')")
    }

    func test_orOfTwoCriteriaJoinsWithComma() {
        let query = AdvancedQuery(groups: [
            AdvancedQueryGroup(combinator: .or, criteria: [
                AdvancedQueryCriterion(fieldKey: "hardware.model", op: .equals, value: .string("MacBookPro18,1")),
                AdvancedQueryCriterion(fieldKey: "hardware.model", op: .equals, value: .string("Mac14,9"))
            ])
        ])
        let result = JamfRSQLComposer.composeForComputers(query, fieldLookup: lookup)
        XCTAssertEqual(result.serverFilter, "(hardware.model=='MacBookPro18,1',hardware.model=='Mac14,9')")
    }

    func test_mixedAndOfOrGroupsParenthesizesOuterPrecedence() {
        let query = AdvancedQuery(groups: [
            AdvancedQueryGroup(combinator: .or, criteria: [
                AdvancedQueryCriterion(fieldKey: "hardware.model", op: .contains, value: .string("Pro")),
                AdvancedQueryCriterion(fieldKey: "hardware.model", op: .contains, value: .string("Air"))
            ]),
            AdvancedQueryGroup(combinator: .and, criteria: [
                AdvancedQueryCriterion(fieldKey: "hardware.appleSilicon", op: .isTrue, value: .bool(true))
            ])
        ], outerCombinator: .and)
        let result = JamfRSQLComposer.composeForComputers(query, fieldLookup: lookup)
        XCTAssertEqual(result.serverFilter, "(hardware.model=='*Pro*',hardware.model=='*Air*');(hardware.appleSilicon==true)")
    }

    // MARK: - Escaping

    func test_singleQuoteInValueGetsEscaped() {
        let query = AdvancedQuery(groups: [
            AdvancedQueryGroup(criteria: [
                AdvancedQueryCriterion(fieldKey: "general.name", op: .equals, value: .string("O'Brien-Mac"))
            ])
        ])
        let result = JamfRSQLComposer.composeForComputers(query, fieldLookup: lookup)
        XCTAssertEqual(result.serverFilter, "(general.name=='O\\'Brien-Mac')")
    }

    func test_backslashInValueGetsDoubled() {
        let query = AdvancedQuery(groups: [
            AdvancedQueryGroup(criteria: [
                AdvancedQueryCriterion(fieldKey: "userAndLocation.username", op: .equals, value: .string("domain\\jdoe"))
            ])
        ])
        let result = JamfRSQLComposer.composeForComputers(query, fieldLookup: lookup)
        XCTAssertEqual(result.serverFilter, "(userAndLocation.username=='domain\\\\jdoe')")
    }

    // MARK: - Empty / invalid input

    func test_emptyQueryReturnsNilFilter() {
        let query = AdvancedQuery(groups: [])
        let result = JamfRSQLComposer.composeForComputers(query, fieldLookup: lookup)
        XCTAssertNil(result.serverFilter)
        XCTAssertTrue(result.clientCriteria.isEmpty)
    }

    func test_emptyStringValueIsSkipped() {
        let query = AdvancedQuery(groups: [
            AdvancedQueryGroup(criteria: [
                AdvancedQueryCriterion(fieldKey: "general.name", op: .equals, value: .string("   "))
            ])
        ])
        let result = JamfRSQLComposer.composeForComputers(query, fieldLookup: lookup)
        XCTAssertNil(result.serverFilter)
    }

    func test_unknownFieldKeyIsSilentlyDropped() {
        let query = AdvancedQuery(groups: [
            AdvancedQueryGroup(criteria: [
                AdvancedQueryCriterion(fieldKey: "thisDoesNotExist", op: .equals, value: .string("foo")),
                AdvancedQueryCriterion(fieldKey: "general.name", op: .equals, value: .string("LAB-01"))
            ])
        ])
        let result = JamfRSQLComposer.composeForComputers(query, fieldLookup: lookup)
        XCTAssertEqual(result.serverFilter, "(general.name=='LAB-01')")
    }

    // MARK: - Client-side routing

    /// Storage display fields are not RSQL-searchable (`supportsRSQLSearch:
    /// false`, hence `isServerFilterable == false`), so they must route to the
    /// in-memory client filter rather than the server RSQL string.
    func test_nonServerFilterableFieldGoesToClientCriteria() {
        let query = AdvancedQuery(groups: [
            AdvancedQueryGroup(criteria: [
                AdvancedQueryCriterion(fieldKey: "storage.totalSizeMegabytes", op: .greaterThan, value: .int(500_000))
            ])
        ])
        let result = JamfRSQLComposer.composeForComputers(query, fieldLookup: lookup)
        XCTAssertNil(result.serverFilter)
        XCTAssertEqual(result.clientCriteria.count, 1)
        XCTAssertEqual(result.clientCriteria.first?.fieldKey, "storage.totalSizeMegabytes")
    }

    func test_mixedServerAndClientCriteriaSplitCorrectly() {
        let query = AdvancedQuery(groups: [
            AdvancedQueryGroup(criteria: [
                AdvancedQueryCriterion(fieldKey: "general.name", op: .equals, value: .string("LAB-01")),
                AdvancedQueryCriterion(fieldKey: "hardware.model", op: .contains, value: .string("Pro")),
                AdvancedQueryCriterion(fieldKey: "storage.percentUsed", op: .greaterThan, value: .int(80))
            ])
        ])
        let result = JamfRSQLComposer.composeForComputers(query, fieldLookup: lookup)
        XCTAssertEqual(result.serverFilter, "(general.name=='LAB-01';hardware.model=='*Pro*')")
        XCTAssertEqual(result.clientCriteria.count, 1)
        XCTAssertEqual(result.clientCriteria.first?.fieldKey, "storage.percentUsed")
    }

    // MARK: - Section coverage

    func test_referencedSectionsIncludeGeneralAndAnyTouched() {
        let query = AdvancedQuery(groups: [
            AdvancedQueryGroup(criteria: [
                AdvancedQueryCriterion(fieldKey: "userAndLocation.username", op: .equals, value: .string("jdoe")),
                AdvancedQueryCriterion(fieldKey: "hardware.model", op: .contains, value: .string("Pro")),
                AdvancedQueryCriterion(fieldKey: "storage.totalSizeMegabytes", op: .greaterThan, value: .int(0))
            ])
        ])
        let result = JamfRSQLComposer.composeForComputers(query, fieldLookup: lookup)
        XCTAssertTrue(result.referencedSections.contains(.general))
        XCTAssertTrue(result.referencedSections.contains(.userAndLocation))
        XCTAssertTrue(result.referencedSections.contains(.hardware))
        XCTAssertTrue(result.referencedSections.contains(.storage))
    }
}

//endofline
