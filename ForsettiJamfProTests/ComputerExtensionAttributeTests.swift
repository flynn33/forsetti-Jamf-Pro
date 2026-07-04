import XCTest
@testable import ForsettiJamfProApp

/// Exercises `ComputerExtensionAttribute`: decoding the tenant EA config across
/// the id/popup-choice shape variations Jamf ships, the `dataType` → runtime
/// type mapping, the synthetic `ComputerField` produced by `makeField()`, and
/// the `cea_<id>` key convention that ties EA config to the inventory values
/// extracted by `ComputerSearchViewModel` and resolved via
/// `ComputerRecord.value(for:)`.
final class ComputerExtensionAttributeTests: XCTestCase {

    private func decode(_ json: String) throws -> ComputerExtensionAttribute {
        try JSONDecoder().decode(ComputerExtensionAttribute.self, from: Data(json.utf8))
    }

    // MARK: - Decoding

    func test_decode_acceptsIntegerID() throws {
        let ea = try decode(#"{"id": 7, "name": "Department Code", "dataType": "STRING", "inputType": "TEXT"}"#)

        XCTAssertEqual(ea.id, "7")
        XCTAssertEqual(ea.name, "Department Code")
    }

    func test_decode_acceptsStringID() throws {
        let ea = try decode(#"{"id": "42", "name": "Asset Owner"}"#)

        XCTAssertEqual(ea.id, "42")
    }

    func test_decode_unknownDataAndInputTypesFallToStringTreatment() throws {
        let ea = try decode(#"{"id": 1, "name": "X", "dataType": "WEIRD", "inputType": "MYSTERY"}"#)

        XCTAssertEqual(ea.dataType, .unknown)
        XCTAssertEqual(ea.inputType, .unknown)
        XCTAssertEqual(ea.swiftDataType, .string)
    }

    func test_decode_missingTypesUseDecoderDefaults() throws {
        let ea = try decode(#"{"id": 1, "name": "X"}"#)

        XCTAssertEqual(ea.dataType, .string)
        XCTAssertEqual(ea.inputType, .text)
    }

    func test_decode_readsPopupChoicesFromModernKey() throws {
        let ea = try decode(#"{"id": 1, "name": "Site", "dataType": "STRING", "inputType": "POPUP", "popupMenuChoices": ["A","B"]}"#)

        XCTAssertEqual(ea.popupChoices, ["A", "B"])
    }

    func test_decode_readsPopupChoicesFromAlternateKey() throws {
        let ea = try decode(#"{"id": 1, "name": "Site", "dataType": "STRING", "inputType": "POPUP", "popupChoices": ["X","Y"]}"#)

        XCTAssertEqual(ea.popupChoices, ["X", "Y"])
    }

    func test_decode_bareArrayOfAttributes() throws {
        let json = #"[{"id":1,"name":"One"},{"id":"2","name":"Two"}]"#

        let attrs = try JSONDecoder().decode([ComputerExtensionAttribute].self, from: Data(json.utf8))

        XCTAssertEqual(attrs.map(\.id), ["1", "2"])
    }

    // MARK: - swiftDataType mapping

    func test_swiftDataType_stringTextIsString() {
        let ea = ComputerExtensionAttribute(id: "1", name: "n", dataType: .string, inputType: .text)

        XCTAssertEqual(ea.swiftDataType, .string)
    }

    func test_swiftDataType_stringPopupIsEnumeration() {
        let ea = ComputerExtensionAttribute(id: "1", name: "n", dataType: .string, inputType: .popup, popupChoices: ["a"])

        XCTAssertEqual(ea.swiftDataType, .enumeration)
    }

    func test_swiftDataType_integerIsInteger() {
        let ea = ComputerExtensionAttribute(id: "1", name: "n", dataType: .integer)

        XCTAssertEqual(ea.swiftDataType, .integer)
    }

    func test_swiftDataType_dateTimeIsDate() {
        let ea = ComputerExtensionAttribute(id: "1", name: "n", dataType: .dateTime)

        XCTAssertEqual(ea.swiftDataType, .date)
    }

    // MARK: - makeField (synthetic catalog field)

    func test_keyPrefixIsComputerSpecific() {
        // Distinct from the mobile `ea_` prefix so both modules can run without
        // synthetic-key collisions.
        XCTAssertEqual(ComputerExtensionAttribute.keyPrefix, "cea_")
    }

    func test_makeField_keyMatchesFieldKey() {
        let ea = ComputerExtensionAttribute(id: "5", name: "Department Code")

        XCTAssertEqual(ea.fieldKey, "cea_5")
        XCTAssertEqual(ea.makeField().key, "cea_5")
    }

    func test_makeField_isClientFilterableOnly() {
        let field = ComputerExtensionAttribute(id: "5", name: "Dept").makeField()

        XCTAssertEqual(field.section, .extensionAttributes)
        XCTAssertTrue(field.isFilterable)
        XCTAssertFalse(field.isSortable)
        XCTAssertFalse(field.isServerFilterable)
        XCTAssertFalse(field.supportsRSQLSearch)
        XCTAssertEqual(field.responsePaths, ["cea_5"])
    }

    func test_makeField_popupExposesAllowedValues() {
        let field = ComputerExtensionAttribute(
            id: "5", name: "Site", dataType: .string, inputType: .popup, popupChoices: ["NY", "LA"]
        ).makeField()

        XCTAssertEqual(field.dataType, .enumeration)
        XCTAssertEqual(field.allowedValues, ["NY", "LA"])
    }

    func test_makeField_nonPopupHasNoAllowedValues() {
        let field = ComputerExtensionAttribute(
            id: "5", name: "Note", dataType: .string, inputType: .text, popupChoices: ["ignored"]
        ).makeField()

        XCTAssertNil(field.allowedValues)
    }

    func test_makeField_descriptionFallsBackWhenEmpty() {
        let field = ComputerExtensionAttribute(id: "5", name: "n", description: "").makeField()

        XCTAssertTrue(field.description.contains("Custom extension attribute"))
    }

    // MARK: - Inventory value resolution (extraction key convention)

    func test_recordResolvesEAValueByFieldKey() {
        // The view model extracts inventory EA values into `cea_<id>` keys; this
        // proves the synthetic field key matches that convention so a selected
        // EA column and client-side filter both resolve the value.
        let ea = ComputerExtensionAttribute(id: "9", name: "Asset Owner")
        let record = ComputerRecord(
            id: "1",
            computerName: "Mac",
            serialNumber: "S1",
            fieldValues: [ea.fieldKey: "Jane Tech"]
        )

        XCTAssertEqual(record.value(for: ea.makeField().key), "Jane Tech")
    }
}

//endofline
