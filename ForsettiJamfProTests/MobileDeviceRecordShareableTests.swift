import XCTest
@testable import ForsettiJamfProApp

/// Verifies `MobileDeviceRecord`'s `ShareableRecord` conformance maps populated catalog
/// fields and omits empty ones.
final class MobileDeviceRecordShareableTests: XCTestCase {

    private func makeRecord(fieldValues: [String: String] = [:]) -> MobileDeviceRecord {
        MobileDeviceRecord(
            id: "1", deviceName: "Jane's iPad", serialNumber: "DMP1",
            udid: nil, model: nil, osVersion: nil,
            prestageEnrollmentStatus: nil, prestageEnrollmentProfileName: nil,
            prestageEnrollmentProfileID: nil, fieldValues: fieldValues
        )
    }

    func test_shareTitleIsDeviceName() {
        XCTAssertEqual(makeRecord().shareTitle, "Jane's iPad")
    }

    func test_shareFieldsIncludePopulatedFieldsAndOmitEmpties() {
        let record = makeRecord(fieldValues: ["username": "jdoe", "emailAddress": "j@x.com"])
        let dict = Dictionary(uniqueKeysWithValues: record.shareFields.map { ($0.label, $0.value) })
        XCTAssertEqual(dict["Serial Number"], "DMP1")        // first-class fallback resolves
        XCTAssertEqual(dict["Assigned Username"], "jdoe")
        XCTAssertEqual(dict["Email Address"], "j@x.com")
        XCTAssertNil(dict["IP Address"])                     // unpopulated → omitted
    }
}

//endofline
