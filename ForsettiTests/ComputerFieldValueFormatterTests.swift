import XCTest
@testable import Forsetti

/// Pins the human-readability contract for `ComputerFieldValueFormatter`, the pure
/// seam that turns raw Jamf inventory strings into display text for the Computer
/// detail view.
///
/// The formatter deliberately leaves booleans alone — `CategoryFieldRow` renders
/// those as a colored indicator — and never groups digits, so identifiers, ports,
/// versions, and serials survive verbatim. These tests guard both promises.
final class ComputerFieldValueFormatterTests: XCTestCase {

    // MARK: - UPPER_SNAKE → Title Case

    func test_upperSnakeBecomesTitleCase() {
        XCTAssertEqual(ComputerFieldValueFormatter.displayString("FULL_SECURITY"), "Full Security")
    }

    func test_longUpperSnakeBecomesTitleCase() {
        XCTAssertEqual(
            ComputerFieldValueFormatter.displayString("APP_STORE_AND_IDENTIFIED_DEVELOPERS"),
            "App Store And Identified Developers"
        )
    }

    // MARK: - SHOUTING CASE → Title Case

    func test_singleShoutingWordBecomesTitleCase() {
        XCTAssertEqual(ComputerFieldValueFormatter.displayString("ENABLED"), "Enabled")
    }

    func test_shoutingWithSpacesBecomesTitleCase() {
        XCTAssertEqual(ComputerFieldValueFormatter.displayString("NOT ENABLED"), "Not Enabled")
    }

    func test_shoutingIsTrimmedFirst() {
        XCTAssertEqual(ComputerFieldValueFormatter.displayString("  ENABLED  "), "Enabled")
    }

    // MARK: - Passthrough (no mangling)

    func test_mixedCaseValuePassesThrough() {
        XCTAssertEqual(ComputerFieldValueFormatter.displayString("MacBook Pro"), "MacBook Pro")
    }

    func test_serialWithDigitsPassesThrough() {
        XCTAssertEqual(ComputerFieldValueFormatter.displayString("C02XL0E3JGH5"), "C02XL0E3JGH5")
    }

    func test_versionNumberPassesThrough() {
        XCTAssertEqual(ComputerFieldValueFormatter.displayString("5273"), "5273")
    }

    func test_ipAddressPassesThrough() {
        XCTAssertEqual(ComputerFieldValueFormatter.displayString("10.0.1.42"), "10.0.1.42")
    }

    func test_emailPassesThrough() {
        XCTAssertEqual(ComputerFieldValueFormatter.displayString("user@example.com"), "user@example.com")
    }

    // MARK: - Booleans are left for the indicator layer

    func test_lowercaseBooleanPassesThrough() {
        XCTAssertEqual(ComputerFieldValueFormatter.displayString("true"), "true")
        XCTAssertEqual(ComputerFieldValueFormatter.displayString("false"), "false")
    }

    // MARK: - Empty / whitespace

    func test_emptyAndWhitespaceCollapseToEmpty() {
        XCTAssertEqual(ComputerFieldValueFormatter.displayString(""), "")
        XCTAssertEqual(ComputerFieldValueFormatter.displayString("   "), "")
    }

    // MARK: - ISO-8601 timestamps → localized date

    func test_isoTimestampIsLocalizedAndNotRaw() {
        let raw = "2026-05-29T12:00:00Z"
        let result = ComputerFieldValueFormatter.displayString(raw)
        XCTAssertNotEqual(result, raw, "Timestamp should be reformatted, not passed through")
        XCTAssertFalse(result.isEmpty)
        XCTAssertFalse(result.contains("T"), "Localized date should not retain the ISO 'T' delimiter")
    }

    func test_isoTimestampWithFractionalSecondsIsLocalized() {
        let raw = "2026-05-29T12:00:00.500Z"
        let result = ComputerFieldValueFormatter.displayString(raw)
        XCTAssertNotEqual(result, raw)
        XCTAssertFalse(result.isEmpty)
    }
}
