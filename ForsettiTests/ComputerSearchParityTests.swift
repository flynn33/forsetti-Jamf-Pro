import XCTest
@testable import Forsetti

final class ComputerSearchParityTests: XCTestCase {

    func testComputerFieldCatalogCarriesTypedSearchMetadata() {
        XCTAssertEqual(ComputerField.keyLookup["hardware.totalRamMegabytes"]?.dataType, .integer)
        XCTAssertEqual(ComputerField.keyLookup["hardware.batteryCapacityPercent"]?.dataType, .integer)
        XCTAssertEqual(ComputerField.keyLookup["hardware.appleSilicon"]?.dataType, .bool)
        XCTAssertEqual(ComputerField.keyLookup["udid"]?.dataType, .string)
        XCTAssertEqual(ComputerField.keyLookup["hardware.modelIdentifier"]?.dataType, .string)
        XCTAssertEqual(ComputerField.keyLookup["hardware.macAddress"]?.dataType, .string)
        XCTAssertEqual(ComputerField.keyLookup["localUserAccounts[].computerAzureActiveDirectoryId"]?.dataType, .string)
        XCTAssertEqual(ComputerField.keyLookup["diskEncryption.fileVault2EnabledUserNames"]?.dataType, .string)
        XCTAssertEqual(ComputerField.keyLookup["operatingSystem.activeDirectoryStatus"]?.dataType, .string)
        XCTAssertEqual(ComputerField.keyLookup["userAndLocation.departmentId"]?.dataType, .integer)
        XCTAssertEqual(ComputerField.keyLookup["configurationProfiles[].id"]?.dataType, .integer)
        XCTAssertEqual(ComputerField.keyLookup["contentCaching.active"]?.dataType, .bool)
        XCTAssertEqual(ComputerField.keyLookup["extensionAttributes[].values[]"]?.isServerFilterable, false)
    }

    @MainActor
    func testComputerRecordExposesDynamicValuesAndExtensionAttributes() throws {
        let json = """
        {
          "id": 42,
          "general": {
            "name": "Mac Studio 7",
            "assetTag": "ASSET-7",
            "lastIpAddress": "10.40.1.7"
          },
          "hardware": {
            "serialNumber": "C02TEST7",
            "model": "Mac Studio",
            "modelIdentifier": "Mac13,1",
            "processorType": "M1 Max",
            "totalRamMegabytes": 32768,
            "batteryCapacityPercent": 97,
            "appleSilicon": true
          },
          "operatingSystem": {
            "version": "15.5",
            "build": "24F74"
          },
          "diskEncryption": {
            "fileVault2Enabled": true
          },
          "localUserAccounts": [
            {
              "username": "admin"
            },
            {
              "username": "standard"
            }
          ],
          "userAndLocation": {
            "username": "jane.appleseed",
            "email": "jane@example.test",
            "departmentId": 501,
            "buildingId": 77
          },
          "extensionAttributes": [
            {
              "definitionId": 123,
              "name": "Lease End",
              "values": ["2027-05-31"]
            }
          ]
        }
        """.data(using: .utf8)!

        let record = try JSONDecoder().decode(ComputerRecord.self, from: json)

        XCTAssertEqual(record.value(for: "general.name"), "Mac Studio 7")
        XCTAssertEqual(record.value(for: "hardware.serialNumber"), "C02TEST7")
        XCTAssertEqual(record.value(for: "hardware.totalRamMegabytes"), "32768")
        XCTAssertEqual(record.value(for: "hardware.appleSilicon"), "true")
        XCTAssertEqual(record.value(for: "userAndLocation.email"), "jane@example.test")
        XCTAssertEqual(record.value(for: "diskEncryption.fileVault2Enabled"), "true")
        XCTAssertEqual(record.value(for: "localUserAccounts[].username"), "admin, standard")
        XCTAssertEqual(record.value(for: "ea_123"), "2027-05-31")
        XCTAssertEqual(record.value(for: "extensionAttributes.Lease End"), "2027-05-31")
        XCTAssertEqual(record.value(for: "extensionAttributes[].values[]"), "2027-05-31")
    }

    func testComputerExtensionAttributeMetadataBuildsClientFilterField() {
        let attribute = ComputerExtensionAttribute(
            id: "321",
            name: "Lease End",
            description: "Lease expiration",
            dataType: .dateTime,
            inputType: .popup,
            popupChoices: ["2027-05-31"]
        )

        let field = attribute.makeField()

        XCTAssertEqual(field.key, "ea_321")
        XCTAssertEqual(field.displayName, "Lease End")
        XCTAssertEqual(field.section, .extensionAttributes)
        XCTAssertEqual(field.dataType, .date)
        XCTAssertTrue(field.isFilterable)
        XCTAssertFalse(field.isServerFilterable)
        XCTAssertEqual(field.allowedValues, ["2027-05-31"])
    }

    func testComputerRSQLComposerUsesComputerFieldSections() {
        let query = AdvancedQuery(groups: [
            AdvancedQueryGroup(criteria: [
                AdvancedQueryCriterion(
                    fieldKey: "hardware.totalRamMegabytes",
                    op: .greaterThan,
                    value: .int(8192)
                )
            ])
        ])

        let result = JamfRSQLComposer.composeComputer(query, fieldLookup: ComputerField.keyLookup)

        XCTAssertEqual(result.serverFilter, "(hardware.totalRamMegabytes=gt='8192')")
        XCTAssertTrue(result.referencedSections.contains(.hardware))
        XCTAssertTrue(result.clientCriteria.isEmpty)
    }

    func testComputerRSQLComposerRoutesExtensionAttributesToClientCriteria() {
        let query = AdvancedQuery(groups: [
            AdvancedQueryGroup(criteria: [
                AdvancedQueryCriterion(
                    fieldKey: "extensionAttributes[].values[]",
                    op: .contains,
                    value: .string("2027")
                )
            ])
        ])

        let result = JamfRSQLComposer.composeComputer(query, fieldLookup: ComputerField.keyLookup)

        XCTAssertNil(result.serverFilter)
        XCTAssertEqual(result.clientCriteria.map(\.fieldKey), ["extensionAttributes[].values[]"])
        XCTAssertTrue(result.referencedSections.contains(.extensionAttributes))
    }

    @MainActor
    func testComputerAdvancedSearchViewModelComposesComputerFields() {
        let attributeField = ComputerExtensionAttribute(
            id: "321",
            name: "Lease End",
            dataType: .dateTime
        ).makeField()
        let fields = [
            ComputerField.keyLookup["hardware.totalRamMegabytes"]!,
            attributeField
        ]
        let lookup = Dictionary(uniqueKeysWithValues: fields.map { ($0.key, $0) })
        let query = AdvancedQuery(groups: [
            AdvancedQueryGroup(criteria: [
                AdvancedQueryCriterion(
                    fieldKey: "hardware.totalRamMegabytes",
                    op: .greaterThan,
                    value: .int(8192)
                ),
                AdvancedQueryCriterion(
                    fieldKey: "ea_321",
                    op: .after,
                    value: .date(Date(timeIntervalSince1970: 1_799_884_800))
                )
            ])
        ])

        let viewModel = ComputerAdvancedSearchViewModel(
            initialQuery: query,
            initialFieldKeys: ["hardware.totalRamMegabytes"],
            availableFields: fields,
            fieldLookup: lookup
        )
        let result = viewModel.compose()

        XCTAssertEqual(result.serverFilter, "(hardware.totalRamMegabytes=gt='8192')")
        XCTAssertEqual(result.clientCriteria.map(\.fieldKey), ["ea_321"])
        XCTAssertNil(viewModel.validationMessage)
    }
}
