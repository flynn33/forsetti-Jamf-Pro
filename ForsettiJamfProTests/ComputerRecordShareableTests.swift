import XCTest
@testable import ForsettiJamfProApp

/// Verifies `ComputerRecord`'s `ShareableRecord` conformance maps populated catalog
/// fields and omits empty ones.
final class ComputerRecordShareableTests: XCTestCase {

    private func makeRecord() -> ComputerRecord {
        ComputerRecord(
            id: "1",
            computerName: "Jim's MacBook Pro",
            serialNumber: "C02ABC123",
            username: "jdoe",
            email: "jdoe@example.com"
        )
    }

    func test_shareTitleIsComputerName() {
        XCTAssertEqual(makeRecord().shareTitle, "Jim's MacBook Pro")
    }

    func test_shareFieldsIncludePopulatedIdentifiersAndOmitEmpties() {
        let dict = Dictionary(uniqueKeysWithValues: makeRecord().shareFields.map { ($0.label, $0.value) })
        XCTAssertEqual(dict["Hardware serial number"], "C02ABC123")
        XCTAssertEqual(dict["Username"], "jdoe")
        XCTAssertEqual(dict["Email address"], "jdoe@example.com")
        XCTAssertNil(dict["Last reported IP address"])   // lastIpAddress unset → omitted
    }
}

//endofline
