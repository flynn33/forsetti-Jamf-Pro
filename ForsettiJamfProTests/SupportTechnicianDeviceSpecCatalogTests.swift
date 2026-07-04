import XCTest
@testable import ForsettiJamfProApp

final class SupportTechnicianDeviceSpecCatalogTests: XCTestCase {

    func test_mobileCatalogDerivesM4IPadRamFromCapacity() {
        let info = SupportTechnicianDeviceSpecCatalog.info(for: "iPad16,6")

        XCTAssertEqual(info?.marketingName, "iPad Pro 13-inch (M4)")
        XCTAssertEqual(info?.chipName, "Apple M4")
        XCTAssertEqual(info?.cpuCoreCount, 9)
        XCTAssertEqual(info?.gpuCoreCount, 10)
        XCTAssertEqual(info?.ramGB(1_024_569), 16)
    }

    func test_macCatalogFillsMissingM1MaxSpecs() {
        let info = SupportTechnicianDeviceSpecCatalog.info(for: "MacBookPro18,2")

        XCTAssertEqual(info?.marketingName, "MacBook Pro 16-inch (2021)")
        XCTAssertEqual(info?.chipName, "Apple M1 Max")
        XCTAssertEqual(info?.cpuCoreCount, 10)
        XCTAssertEqual(info?.gpuCoreDescription, "24 or 32 GPU cores")
        XCTAssertEqual(info?.neuralCoreCount, 16)
        XCTAssertEqual(info?.cpuFrequencyDescription, "Performance cores up to 3.2 GHz")
        XCTAssertEqual(info?.memoryDescription, "Unified memory · up to 400 GB/s bandwidth")
    }

    func test_unknownIdentifierReturnsNil() {
        XCTAssertNil(SupportTechnicianDeviceSpecCatalog.info(for: "Mac99,99"))
    }
}

//endofline
