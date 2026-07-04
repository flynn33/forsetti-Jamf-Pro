import XCTest
@testable import Jamf_Dashboard

/// Covers `ComputerRecord.merging(_:)`, the contract the detail view relies on
/// when a hardware/detail refresh returns a record that may carry *less* data
/// than the original search row. The refresh result must never discard
/// already-known fields, must not swap a real Jamf id for a synthetic UUID, and
/// must ignore "Unknown" placeholder identity values.
final class ComputerDetailMergeTests: XCTestCase {

    // MARK: - fieldValues merge

    func test_refreshedNonEmptyFieldValuesWin() {
        let base = ComputerRecord(
            id: "123",
            computerName: "Mac",
            serialNumber: "C02BASE",
            fieldValues: ["hardware.processorType": "Apple M1"]
        )
        let refreshed = ComputerRecord(
            id: "123",
            computerName: "Mac",
            serialNumber: "C02BASE",
            fieldValues: [
                "hardware.processorType": "Apple M2 Pro",
                "storage.totalSizeMegabytes": "994662"
            ]
        )

        let merged = base.merging(refreshed)

        XCTAssertEqual(merged.value(for: "hardware.processorType"), "Apple M2 Pro")
        XCTAssertEqual(merged.value(for: "storage.totalSizeMegabytes"), "994662")
    }

    func test_emptyRefreshValueDoesNotOverwriteExisting() {
        let base = ComputerRecord(
            id: "123",
            computerName: "Mac",
            serialNumber: "C02BASE",
            fieldValues: ["hardware.totalRamMegabytes": "16384"]
        )
        // Refresh reports the key but with an empty string (e.g. section present
        // but value absent) and omits a key the base already had.
        let refreshed = ComputerRecord(
            id: "123",
            computerName: "Mac",
            serialNumber: "C02BASE",
            fieldValues: ["hardware.totalRamMegabytes": ""]
        )

        let merged = base.merging(refreshed)

        XCTAssertEqual(merged.value(for: "hardware.totalRamMegabytes"), "16384")
    }

    func test_missingRefreshKeyPreservesExisting() {
        let base = ComputerRecord(
            id: "123",
            computerName: "Mac",
            serialNumber: "C02BASE",
            fieldValues: ["storage.bootDriveAvailableSpaceMegabytes": "250000"]
        )
        let refreshed = ComputerRecord(id: "123", computerName: "Mac", serialNumber: "C02BASE")

        let merged = base.merging(refreshed)

        XCTAssertEqual(merged.value(for: "storage.bootDriveAvailableSpaceMegabytes"), "250000")
    }

    func test_extensionAttributeValuesMerge() {
        let base = ComputerRecord(
            id: "123",
            computerName: "Mac",
            serialNumber: "C02BASE",
            fieldValues: ["cea_12": "Finance"]
        )
        let refreshed = ComputerRecord(
            id: "123",
            computerName: "Mac",
            serialNumber: "C02BASE",
            fieldValues: ["cea_12": "Engineering", "cea_44": "Jane Tech"]
        )

        let merged = base.merging(refreshed)

        XCTAssertEqual(merged.value(for: "cea_12"), "Engineering")
        XCTAssertEqual(merged.value(for: "cea_44"), "Jane Tech")
    }

    // MARK: - Identity (id) guarding

    func test_realIDKeptWhenRefreshCarriesSyntheticUUID() {
        let base = ComputerRecord(id: "123", computerName: "Mac", serialNumber: "C02BASE")
        let refreshed = ComputerRecord(
            id: UUID().uuidString,
            computerName: "Mac",
            serialNumber: "C02BASE"
        )

        let merged = base.merging(refreshed)

        XCTAssertEqual(merged.id, "123")
    }

    func test_emptyRefreshIDKeepsBaseID() {
        let base = ComputerRecord(id: "123", computerName: "Mac", serialNumber: "C02BASE")
        let refreshed = ComputerRecord(id: "", computerName: "Mac", serialNumber: "C02BASE")

        let merged = base.merging(refreshed)

        XCTAssertEqual(merged.id, "123")
    }

    func test_realRefreshIDWins() {
        let base = ComputerRecord(id: "123", computerName: "Mac", serialNumber: "C02BASE")
        let refreshed = ComputerRecord(id: "456", computerName: "Mac", serialNumber: "C02BASE")

        let merged = base.merging(refreshed)

        XCTAssertEqual(merged.id, "456")
    }

    // MARK: - Placeholder identity values

    func test_unknownComputerNamePlaceholderDoesNotOverwrite() {
        let base = ComputerRecord(id: "123", computerName: "Jane's MacBook Pro", serialNumber: "C02BASE")
        let refreshed = ComputerRecord(id: "123", computerName: "Unknown Computer", serialNumber: "C02BASE")

        let merged = base.merging(refreshed)

        XCTAssertEqual(merged.computerName, "Jane's MacBook Pro")
    }

    func test_unknownSerialPlaceholderDoesNotOverwrite() {
        let base = ComputerRecord(id: "123", computerName: "Mac", serialNumber: "C02REAL123")
        let refreshed = ComputerRecord(id: "123", computerName: "Mac", serialNumber: "Unknown")

        let merged = base.merging(refreshed)

        XCTAssertEqual(merged.serialNumber, "C02REAL123")
    }

    func test_realNameAndSerialFromRefreshWin() {
        let base = ComputerRecord(id: "123", computerName: "Unknown Computer", serialNumber: "Unknown")
        let refreshed = ComputerRecord(id: "123", computerName: "Lab Mac 04", serialNumber: "C02NEW999")

        let merged = base.merging(refreshed)

        XCTAssertEqual(merged.computerName, "Lab Mac 04")
        XCTAssertEqual(merged.serialNumber, "C02NEW999")
    }

    // MARK: - Optional first-class fields

    func test_optionalFieldRefreshWinsWhenPresentBasePreservedWhenNil() {
        let base = ComputerRecord(
            id: "123",
            computerName: "Mac",
            serialNumber: "C02BASE",
            model: "MacBook Pro (legacy label)",
            modelIdentifier: "MacBookPro18,1",
            osVersion: "14.0"
        )
        // Refresh updates the OS, omits model (nil → keep base), updates identifier.
        let refreshed = ComputerRecord(
            id: "123",
            computerName: "Mac",
            serialNumber: "C02BASE",
            modelIdentifier: "Mac14,7",
            osVersion: "14.5"
        )

        let merged = base.merging(refreshed)

        XCTAssertEqual(merged.model, "MacBook Pro (legacy label)")
        XCTAssertEqual(merged.modelIdentifier, "Mac14,7")
        XCTAssertEqual(merged.osVersion, "14.5")
    }
}
