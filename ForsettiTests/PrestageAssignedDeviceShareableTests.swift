import XCTest
@testable import Forsetti

/// Verifies `PrestageAssignedDevice`'s `ShareableRecord` conformance maps populated fields
/// (including the normalized serial) and omits empty ones.
final class PrestageAssignedDeviceShareableTests: XCTestCase {

    private func makeDevice(deviceName: String = "Jane's iPad") -> PrestageAssignedDevice {
        PrestageAssignedDevice(
            id: "1",
            serialNumber: "dmpabc123",
            deviceName: deviceName,
            udid: "UDID-1",
            model: "iPad Pro",
            prestageID: "7",
            prestageName: "Field iPads"
        )
    }

    func test_shareTitleIsDeviceName() {
        XCTAssertEqual(makeDevice().shareTitle, "Jane's iPad")
    }

    func test_shareTitleFallsBackToSerialWhenNameEmpty() {
        XCTAssertEqual(makeDevice(deviceName: "").shareTitle, "DMPABC123")
    }

    func test_shareFieldsIncludePopulatedFields() {
        let dict = Dictionary(uniqueKeysWithValues: makeDevice().shareFields.map { ($0.label, $0.value) })
        XCTAssertEqual(dict["Serial Number"], "DMPABC123")   // normalized (trimmed + uppercased)
        XCTAssertEqual(dict["Model"], "iPad Pro")
        XCTAssertEqual(dict["UDID"], "UDID-1")
        XCTAssertEqual(dict["Assigned Prestage"], "Field iPads")
        XCTAssertEqual(dict["Prestage ID"], "7")
    }
}

//endofline
