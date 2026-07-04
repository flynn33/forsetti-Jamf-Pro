import XCTest
@testable import ForsettiJamfProApp

// "End of Line"

/// Exercises the typed RSQL composer used by Advanced Search.
///
/// The shape contract these tests lock in:
/// - Every group is parenthesized — no exceptions, even single-criterion groups.
/// - Single-quote literals always pass through `JamfRSQLFilter.escapeSingleQuoted`.
/// - Wildcard wrapping happens AFTER escaping (so a literal `*` typed by the user
///   doesn't accidentally turn into a wildcard).
/// - Unknown field keys are silently dropped — composer never throws.
/// - All-empty queries produce a nil server filter (so the caller can omit
///   the `filter=` query param entirely).
final class JamfRSQLComposerTests: XCTestCase {

    private var lookup: [String: MobileDeviceField] {
        MobileDeviceField.keyLookup
    }

    // MARK: - Single criterion shapes

    func test_singleEqualsString_emitsParenthesizedFragment() {
        let query = AdvancedQuery(groups: [
            AdvancedQueryGroup(criteria: [
                AdvancedQueryCriterion(fieldKey: "building", op: .equals, value: .string("HHC"))
            ])
        ])
        let result = JamfRSQLComposer.compose(query, fieldLookup: lookup)
        XCTAssertEqual(result.serverFilter, "(building=='HHC')")
    }

    func test_containsWrapsWildcardsBothSides() {
        let query = AdvancedQuery(groups: [
            AdvancedQueryGroup(criteria: [
                AdvancedQueryCriterion(fieldKey: "model", op: .contains, value: .string("iPad"))
            ])
        ])
        let result = JamfRSQLComposer.compose(query, fieldLookup: lookup)
        XCTAssertEqual(result.serverFilter, "(model=='*iPad*')")
    }

    func test_startsWithUsesTrailingWildcardOnly() {
        let query = AdvancedQuery(groups: [
            AdvancedQueryGroup(criteria: [
                AdvancedQueryCriterion(fieldKey: "model", op: .startsWith, value: .string("iPhone"))
            ])
        ])
        let result = JamfRSQLComposer.compose(query, fieldLookup: lookup)
        XCTAssertEqual(result.serverFilter, "(model=='iPhone*')")
    }

    func test_endsWithUsesLeadingWildcardOnly() {
        let query = AdvancedQuery(groups: [
            AdvancedQueryGroup(criteria: [
                AdvancedQueryCriterion(fieldKey: "model", op: .endsWith, value: .string("Pro"))
            ])
        ])
        let result = JamfRSQLComposer.compose(query, fieldLookup: lookup)
        XCTAssertEqual(result.serverFilter, "(model=='*Pro')")
    }

    func test_notEqualsEmitsBangEquals() {
        let query = AdvancedQuery(groups: [
            AdvancedQueryGroup(criteria: [
                AdvancedQueryCriterion(fieldKey: "department", op: .notEquals, value: .string("Sales"))
            ])
        ])
        let result = JamfRSQLComposer.compose(query, fieldLookup: lookup)
        XCTAssertEqual(result.serverFilter, "(department!='Sales')")
    }

    func test_isTrueEmitsLiteralBool() {
        let query = AdvancedQuery(groups: [
            AdvancedQueryGroup(criteria: [
                AdvancedQueryCriterion(fieldKey: "supervised", op: .isTrue, value: .bool(true))
            ])
        ])
        let result = JamfRSQLComposer.compose(query, fieldLookup: lookup)
        XCTAssertEqual(result.serverFilter, "(supervised==true)")
    }

    func test_lessThanEmitsRelationalOperator() {
        let query = AdvancedQuery(groups: [
            AdvancedQueryGroup(criteria: [
                AdvancedQueryCriterion(fieldKey: "availableSpaceMb", op: .lessThan, value: .int(1024))
            ])
        ])
        let result = JamfRSQLComposer.compose(query, fieldLookup: lookup)
        XCTAssertEqual(result.serverFilter, "(availableSpaceMb=lt='1024')")
    }

    // MARK: - Combinator semantics

    func test_andOfTwoCriteriaJoinsWithSemicolon() {
        let query = AdvancedQuery(groups: [
            AdvancedQueryGroup(combinator: .and, criteria: [
                AdvancedQueryCriterion(fieldKey: "building", op: .equals, value: .string("HHC")),
                AdvancedQueryCriterion(fieldKey: "model", op: .contains, value: .string("iPad"))
            ])
        ])
        let result = JamfRSQLComposer.compose(query, fieldLookup: lookup)
        XCTAssertEqual(result.serverFilter, "(building=='HHC';model=='*iPad*')")
    }

    func test_orOfTwoCriteriaJoinsWithComma() {
        let query = AdvancedQuery(groups: [
            AdvancedQueryGroup(combinator: .or, criteria: [
                AdvancedQueryCriterion(fieldKey: "department", op: .equals, value: .string("Sales")),
                AdvancedQueryCriterion(fieldKey: "department", op: .equals, value: .string("Engineering"))
            ])
        ])
        let result = JamfRSQLComposer.compose(query, fieldLookup: lookup)
        XCTAssertEqual(result.serverFilter, "(department=='Sales',department=='Engineering')")
    }

    func test_mixedAndOfOrGroupsParenthesizesOuterPrecedence() {
        let query = AdvancedQuery(groups: [
            AdvancedQueryGroup(combinator: .or, criteria: [
                AdvancedQueryCriterion(fieldKey: "model", op: .contains, value: .string("iPad")),
                AdvancedQueryCriterion(fieldKey: "model", op: .contains, value: .string("iPhone"))
            ]),
            AdvancedQueryGroup(combinator: .and, criteria: [
                AdvancedQueryCriterion(fieldKey: "supervised", op: .isTrue, value: .bool(true))
            ])
        ], outerCombinator: .and)
        let result = JamfRSQLComposer.compose(query, fieldLookup: lookup)
        XCTAssertEqual(result.serverFilter, "(model=='*iPad*',model=='*iPhone*');(supervised==true)")
    }

    // MARK: - Escaping

    func test_singleQuoteInValueGetsEscaped() {
        let query = AdvancedQuery(groups: [
            AdvancedQueryGroup(criteria: [
                AdvancedQueryCriterion(fieldKey: "fullName", op: .equals, value: .string("O'Brien"))
            ])
        ])
        let result = JamfRSQLComposer.compose(query, fieldLookup: lookup)
        XCTAssertEqual(result.serverFilter, "(fullName=='O\\'Brien')")
    }

    func test_backslashInValueGetsDoubled() {
        let query = AdvancedQuery(groups: [
            AdvancedQueryGroup(criteria: [
                AdvancedQueryCriterion(fieldKey: "username", op: .equals, value: .string("domain\\jdoe"))
            ])
        ])
        let result = JamfRSQLComposer.compose(query, fieldLookup: lookup)
        XCTAssertEqual(result.serverFilter, "(username=='domain\\\\jdoe')")
    }

    // MARK: - Empty / invalid input

    func test_emptyQueryReturnsNilFilter() {
        let query = AdvancedQuery(groups: [])
        let result = JamfRSQLComposer.compose(query, fieldLookup: lookup)
        XCTAssertNil(result.serverFilter)
    }

    func test_emptyStringValueIsSkipped() {
        let query = AdvancedQuery(groups: [
            AdvancedQueryGroup(criteria: [
                AdvancedQueryCriterion(fieldKey: "building", op: .equals, value: .string("   "))
            ])
        ])
        let result = JamfRSQLComposer.compose(query, fieldLookup: lookup)
        XCTAssertNil(result.serverFilter)
    }

    func test_unknownFieldKeyIsSilentlyDropped() {
        let query = AdvancedQuery(groups: [
            AdvancedQueryGroup(criteria: [
                AdvancedQueryCriterion(fieldKey: "thisDoesNotExist", op: .equals, value: .string("foo")),
                AdvancedQueryCriterion(fieldKey: "building", op: .equals, value: .string("HHC"))
            ])
        ])
        let result = JamfRSQLComposer.compose(query, fieldLookup: lookup)
        XCTAssertEqual(result.serverFilter, "(building=='HHC')")
    }

    // MARK: - Client-side routing

    func test_prestageProfileCriterionGoesToClientCriteria() {
        let prestageCriterion = AdvancedQueryCriterion(
            fieldKey: "prestageEnrollmentProfile",
            op: .contains,
            value: .string("Shared")
        )
        let query = AdvancedQuery(groups: [
            AdvancedQueryGroup(criteria: [prestageCriterion])
        ])
        let result = JamfRSQLComposer.compose(query, fieldLookup: lookup)
        XCTAssertNil(result.serverFilter)
        XCTAssertEqual(result.clientCriteria.count, 1)
        XCTAssertEqual(result.clientCriteria.first?.fieldKey, "prestageEnrollmentProfile")
    }

    func test_mixedFilterableAndClientCriteriaSplitCorrectly() {
        let query = AdvancedQuery(groups: [
            AdvancedQueryGroup(criteria: [
                AdvancedQueryCriterion(fieldKey: "building", op: .equals, value: .string("HHC")),
                AdvancedQueryCriterion(fieldKey: "model", op: .contains, value: .string("iPad")),
                AdvancedQueryCriterion(
                    fieldKey: "prestageEnrollmentProfile",
                    op: .contains,
                    value: .string("Shared")
                )
            ])
        ])
        let result = JamfRSQLComposer.compose(query, fieldLookup: lookup)
        XCTAssertEqual(result.serverFilter, "(building=='HHC';model=='*iPad*')")
        XCTAssertEqual(result.clientCriteria.count, 1)
        XCTAssertEqual(result.clientCriteria.first?.fieldKey, "prestageEnrollmentProfile")
    }

    // MARK: - Section coverage

    func test_referencedSectionsIncludeGeneralAndAnyTouched() {
        let query = AdvancedQuery(groups: [
            AdvancedQueryGroup(criteria: [
                AdvancedQueryCriterion(fieldKey: "building", op: .equals, value: .string("HHC")),
                AdvancedQueryCriterion(fieldKey: "capacityMb", op: .greaterThan, value: .int(0))
            ])
        ])
        let result = JamfRSQLComposer.compose(query, fieldLookup: lookup)
        XCTAssertTrue(result.referencedSections.contains(.general))
        XCTAssertTrue(result.referencedSections.contains(.location))
        XCTAssertTrue(result.referencedSections.contains(.hardware))
    }
}

//endofline
