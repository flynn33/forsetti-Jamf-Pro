import XCTest
@testable import Jamf_Dashboard

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

    func test_computerOnlyAction_unsupportedForMobileDevice() {
        let detail = makeDetail(assetType: .mobileDevice)

        let availability = SupportManagementAction.redeployManagementFramework.availability(for: detail)

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

    /// Locks in the redundancy removal: the Support Technician management-action grid must never
    /// offer a remote-management / Screen Sharing action again — that workflow is exclusively the
    /// dedicated Remote Support frame. Guards against the grid being silently re-extended (or the
    /// Remote Support workflow re-surfacing as a grid button) without anyone noticing.
    func test_managementGrid_offersNoRemoteManagementOrScreenSharingAction() {
        for assetType in [SupportAssetType.computer, .mobileDevice] {
            let detail = makeDetail(assetType: assetType)
            let actions = SupportTechnicianViewModel.resolvedActions(for: detail)
            for action in actions {
                let text = "\(action.rawValue) \(action.title) \(action.subtitle)".lowercased()
                XCTAssertFalse(
                    text.contains("remote management")
                        || text.contains("remote desktop")
                        || text.contains("screen sharing"),
                    "Management-action grid must not offer a remote-management/screen-sharing action "
                        + "(found '\(action.rawValue)' for \(assetType)); that surface is exclusively the Remote Support frame."
                )
            }
        }
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
