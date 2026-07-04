import XCTest
@testable import ForsettiJamfProApp

/// Verifies `SupportDeviceDetail`'s `ShareableRecord` conformance maps the manually
/// enumerated identity fields and omits empty / absent ones.
final class SupportDeviceDetailShareableTests: XCTestCase {

    private func makeDetail() -> SupportDeviceDetail {
        let summary = SupportSearchResult(
            assetType: .computer,
            inventoryID: "42",
            managementID: "mgmt-1",
            clientManagementID: nil,
            displayName: "Jim's MacBook Pro",
            serialNumber: "C02ABC123",
            username: "jdoe",
            email: "jdoe@example.com",
            model: "MacBook Pro",
            osVersion: "14.5",
            lastInventoryUpdate: nil,
            prestageEnrollment: nil,
            automatedDeviceEnrollment: nil
        )
        return SupportDeviceDetail(
            summary: summary,
            diagnostics: [],
            sections: [],
            applications: [],
            rawJSON: "{}"
        )
    }

    func test_shareTitleIsDeviceName() {
        XCTAssertEqual(makeDetail().shareTitle, "Jim's MacBook Pro")
    }

    func test_shareFieldsIncludeIdentityAndOmitEmpties() {
        let dict = Dictionary(uniqueKeysWithValues: makeDetail().shareFields.map { ($0.label, $0.value) })
        XCTAssertEqual(dict["Serial Number"], "C02ABC123")
        XCTAssertEqual(dict["Assigned User"], "jdoe")
        XCTAssertEqual(dict["User Email"], "jdoe@example.com")
        XCTAssertEqual(dict["Inventory ID"], "42")
        XCTAssertEqual(dict["Management ID"], "mgmt-1")
        XCTAssertNil(dict["IP Address"])            // networkInfo nil → omitted
        XCTAssertNil(dict["PreStage Enrollment"])   // nil → omitted
    }
}

//endofline
