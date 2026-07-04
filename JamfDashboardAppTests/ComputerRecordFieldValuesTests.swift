import XCTest
@testable import Jamf_Dashboard

/// Exercises the dynamic field-value layer added to `ComputerRecord`: the
/// `value(for:)` / `intValue(for:)` lookups, the `withFieldValues` and `merging`
/// copy builders that back the detail-view hardware refresh, and the typed
/// hardware accessors that drive the storage gauge and hardware card.
final class ComputerRecordFieldValuesTests: XCTestCase {

    private func makeRecord(
        id: String = "42",
        computerName: String = "LAB-LAPTOP-01",
        serialNumber: String = "C02ABC123DEF",
        fieldValues: [String: String] = [:]
    ) -> ComputerRecord {
        ComputerRecord(
            id: id,
            computerName: computerName,
            serialNumber: serialNumber,
            fieldValues: fieldValues
        )
    }

    // MARK: - value(for:)

    func test_valueForFieldKey_prefersDynamicFieldValuesOverFirstClass() {
        let record = makeRecord(
            computerName: "First-Class-Name",
            fieldValues: ["general.name": "Dynamic-Name"]
        )

        XCTAssertEqual(record.value(for: "general.name"), "Dynamic-Name")
    }

    func test_valueForFieldKey_fallsBackToFirstClassPropertiesForCoreKeys() {
        let record = makeRecord(computerName: "LAB-MAC", serialNumber: "SERIAL123")

        XCTAssertEqual(record.value(for: "general.name"), "LAB-MAC")
        XCTAssertEqual(record.value(for: "computerName"), "LAB-MAC")
        XCTAssertEqual(record.value(for: "hardware.serialNumber"), "SERIAL123")
        XCTAssertEqual(record.value(for: "serialNumber"), "SERIAL123")
        XCTAssertEqual(record.value(for: "id"), "42")
    }

    func test_valueForFieldKey_returnsNilForUnpopulatedArbitraryKey() {
        let record = makeRecord()

        XCTAssertNil(record.value(for: "hardware.macAddress"))
    }

    func test_valueForFieldKey_resolvesArbitraryCatalogKeyFromFieldValues() {
        let record = makeRecord(fieldValues: ["userAndLocation.realname": "Jane Tech"])

        XCTAssertEqual(record.value(for: "userAndLocation.realname"), "Jane Tech")
    }

    func test_valueForFieldKey_composesPrestageDisplayValue() {
        let record = ComputerRecord(
            id: "7",
            computerName: "Mac",
            serialNumber: "S7",
            prestageEnrollmentStatus: "Enrolled",
            prestageEnrollmentProfileName: "Standard Mac",
            prestageEnrollmentProfileID: "12"
        )

        XCTAssertEqual(
            record.value(for: "prestageEnrollmentProfile"),
            "Enrolled - Standard Mac (ID: 12)"
        )
    }

    // MARK: - intValue(for:)

    func test_intValue_stripsTrailingDecimal() {
        let record = makeRecord(fieldValues: ["hardware.totalRamMegabytes": "16384.0"])

        XCTAssertEqual(record.intValue(for: "hardware.totalRamMegabytes"), 16384)
    }

    func test_intValue_takesFirstElementOfCommaJoinedArrayValue() {
        // storage.disks.sizeMegabytes can resolve to a joined multi-disk string.
        let record = makeRecord(fieldValues: ["storage.totalSizeMegabytes": "994662, 500000"])

        XCTAssertEqual(record.intValue(for: "storage.totalSizeMegabytes"), 994662)
    }

    func test_intValue_returnsNilForNonNumericValue() {
        let record = makeRecord(fieldValues: ["hardware.coreCount": "not-a-number"])

        XCTAssertNil(record.intValue(for: "hardware.coreCount"))
    }

    // MARK: - withFieldValues

    func test_withFieldValues_mergesAndIncomingNonEmptyWins() {
        let record = makeRecord(fieldValues: ["a": "original", "keep": "me"])

        let merged = record.withFieldValues(["a": "updated", "b": "new"])

        XCTAssertEqual(merged.value(for: "a"), "updated")
        XCTAssertEqual(merged.value(for: "b"), "new")
        XCTAssertEqual(merged.value(for: "keep"), "me")
    }

    func test_withFieldValues_ignoresEmptyIncomingValues() {
        let record = makeRecord(fieldValues: ["a": "original"])

        let merged = record.withFieldValues(["a": ""])

        XCTAssertEqual(merged.value(for: "a"), "original")
    }

    // MARK: - merging (detail-view hardware refresh)

    func test_merging_refreshedNonEmptyValuesWinWithoutErasingExisting() {
        let searchRow = makeRecord(fieldValues: [
            "userAndLocation.username": "jtech",
            "storage.totalSizeMegabytes": "994662"
        ])
        // Refresh response carries hardware but omits the user/storage the row had.
        let refreshed = makeRecord(fieldValues: [
            "hardware.processorType": "Apple M2 Pro"
        ])

        let merged = searchRow.merging(refreshed)

        XCTAssertEqual(merged.value(for: "hardware.processorType"), "Apple M2 Pro")
        XCTAssertEqual(merged.value(for: "userAndLocation.username"), "jtech")
        XCTAssertEqual(merged.value(for: "storage.totalSizeMegabytes"), "994662")
    }

    func test_merging_keepsRealIDWhenRefreshReturnsSyntheticUUID() {
        let searchRow = makeRecord(id: "55")
        let refreshed = makeRecord(id: UUID().uuidString)

        let merged = searchRow.merging(refreshed)

        XCTAssertEqual(merged.id, "55")
    }

    func test_merging_doesNotOverwriteWithUnknownPlaceholders() {
        let searchRow = makeRecord(computerName: "LAB-REAL", serialNumber: "REALSERIAL")
        let refreshed = makeRecord(computerName: "Unknown Computer", serialNumber: "Unknown")

        let merged = searchRow.merging(refreshed)

        XCTAssertEqual(merged.computerName, "LAB-REAL")
        XCTAssertEqual(merged.serialNumber, "REALSERIAL")
    }

    // MARK: - Typed hardware accessors

    func test_storageAccessors_parseMegabyteValues() {
        let record = makeRecord(fieldValues: [
            "storage.totalSizeMegabytes": "994662",
            "storage.bootDriveAvailableSpaceMegabytes": "248665"
        ])

        XCTAssertEqual(record.totalStorageMb, 994662)
        XCTAssertEqual(record.bootDriveAvailableMb, 248665)
    }

    func test_storageUsedPercentage_prefersReportedPercentWhenInRange() {
        let record = makeRecord(fieldValues: [
            "storage.percentUsed": "73",
            "storage.totalSizeMegabytes": "1000",
            "storage.bootDriveAvailableSpaceMegabytes": "900"
        ])

        // Reported 73 wins over the (total-free)/total = 10% computation.
        XCTAssertEqual(record.storageUsedPercentage, 73)
    }

    func test_storageUsedPercentage_computesFromTotalAndFreeWhenPercentMissing() {
        let record = makeRecord(fieldValues: [
            "storage.totalSizeMegabytes": "1000",
            "storage.bootDriveAvailableSpaceMegabytes": "250"
        ])

        // (1000 - 250) / 1000 = 75%
        XCTAssertEqual(record.storageUsedPercentage, 75)
    }

    func test_storageUsedPercentage_ignoresOutOfRangeReportedPercent() {
        let record = makeRecord(fieldValues: [
            "storage.percentUsed": "150",
            "storage.totalSizeMegabytes": "1000",
            "storage.bootDriveAvailableSpaceMegabytes": "400"
        ])

        // 150 is out of 0...100, so it falls through to the computed 60%.
        XCTAssertEqual(record.storageUsedPercentage, 60)
    }

    func test_hardwareAccessors_parseTypedValues() {
        let record = makeRecord(fieldValues: [
            "hardware.totalRamMegabytes": "32768",
            "hardware.coreCount": "12",
            "hardware.batteryCapacityPercent": "94",
            "hardware.processorType": "Apple M2 Max"
        ])

        XCTAssertEqual(record.totalRamMb, 32768)
        XCTAssertEqual(record.coreCount, 12)
        XCTAssertEqual(record.batteryCapacityPercent, 94)
        XCTAssertEqual(record.processorType, "Apple M2 Max")
    }

    func test_hardwareAccessors_returnNilWhenAbsent() {
        let record = makeRecord()

        XCTAssertNil(record.totalRamMb)
        XCTAssertNil(record.coreCount)
        XCTAssertNil(record.batteryCapacityPercent)
        XCTAssertNil(record.processorType)
        XCTAssertNil(record.totalStorageMb)
        XCTAssertNil(record.storageUsedPercentage)
    }
}

//endofline
