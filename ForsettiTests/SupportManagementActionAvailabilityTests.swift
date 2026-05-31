import XCTest
@testable import Forsetti

final class SupportManagementActionAvailabilityTests: XCTestCase {

    func test_updateInventory_availableForComputerWithoutManagementID() {
        let detail = makeDetail(assetType: .computer, managementID: nil, clientManagementID: nil)

        let availability = SupportManagementAction.refreshInventory.availability(for: detail)

        XCTAssertTrue(availability.isAvailable)
        XCTAssertEqual(availability.state, .available)
    }

    func test_updateInventory_availableForMobileDeviceWithoutManagementID() {
        let detail = makeDetail(assetType: .mobileDevice, managementID: nil, clientManagementID: nil)

        let availability = SupportManagementAction.refreshInventory.availability(for: detail)

        XCTAssertTrue(availability.isAvailable)
        XCTAssertEqual(availability.state, .available)
    }

    func test_blankPush_blockedWithoutManagementID() {
        let detail = makeDetail(assetType: .computer, managementID: nil, clientManagementID: nil)

        let availability = SupportManagementAction.blankPush.availability(for: detail)

        XCTAssertFalse(availability.isAvailable)
        XCTAssertEqual(availability.state, .blocked)
        XCTAssertTrue(availability.helpText.localizedCaseInsensitiveContains("management ID"))
    }

    func test_remoteDesktop_unsupportedForMobileDevice() {
        let detail = makeDetail(assetType: .mobileDevice)

        let availability = SupportManagementAction.remoteManagement.availability(for: detail)

        XCTAssertFalse(availability.isAvailable)
        XCTAssertEqual(availability.state, .unsupported)
    }

    func test_lostMode_unsupportedForComputer() {
        let detail = makeDetail(assetType: .computer)

        let availability = SupportManagementAction.enableLostMode.availability(for: detail)

        XCTAssertFalse(availability.isAvailable)
        XCTAssertEqual(availability.state, .unsupported)
    }

    func test_lapsPassword_blockedWithoutClientOrManagementID() {
        let detail = makeDetail(assetType: .computer, managementID: nil, clientManagementID: nil)

        let availability = SupportManagementAction.viewLAPSAccountPassword.availability(for: detail)

        XCTAssertFalse(availability.isAvailable)
        XCTAssertEqual(availability.state, .blocked)
        XCTAssertTrue(availability.helpText.localizedCaseInsensitiveContains("client management ID"))
    }

    private func makeDetail(
        assetType: SupportAssetType,
        inventoryID: String = "123",
        managementID: String? = "management-id",
        clientManagementID: String? = "client-management-id"
    ) -> SupportDeviceDetail {
        let summary = SupportSearchResult(
            assetType: assetType,
            inventoryID: inventoryID,
            managementID: managementID,
            clientManagementID: clientManagementID,
            displayName: "Test Device",
            serialNumber: "SERIAL123",
            username: nil,
            email: nil,
            model: nil,
            osVersion: nil,
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
}

//endofline
