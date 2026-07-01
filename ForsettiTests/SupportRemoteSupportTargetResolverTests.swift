import XCTest
@testable import Forsetti

/// Verifies `SupportRemoteSupportTargetResolver` follows the deterministic priority order,
/// never uses the serial number as a host, rejects invalid/blank targets, and builds a safe
/// percent-encoded `vnc://` URL.
final class SupportRemoteSupportTargetResolverTests: XCTestCase {

    private let resolver = SupportRemoteSupportTargetResolver()

    // MARK: - Fixtures

    private func makeNetwork(
        ipAddress: String? = nil,
        lastReportedIp: String? = nil,
        lastReportedIpV4: String? = nil,
        hostname: String? = nil
    ) -> SupportNetworkInfo {
        SupportNetworkInfo(
            ipAddress: ipAddress,
            lastReportedIp: lastReportedIp,
            lastReportedIpV4: lastReportedIpV4,
            lastReportedIpV6: nil,
            connectionActive: nil,
            wifiMacAddress: nil,
            wifiEnabled: nil,
            ssid: nil,
            bluetoothMacAddress: nil,
            bluetoothEnabled: nil,
            hostname: hostname,
            networkAdapterType: nil,
            alternateMacAddress: nil,
            alternateNetworkAdapterType: nil,
            nicSpeed: nil,
            bleCapable: nil,
            cellularCarrier: nil,
            cellularTechnology: nil,
            imei: nil,
            imei2: nil,
            meid: nil,
            iccid: nil,
            eid: nil,
            phoneNumber: nil,
            dataRoamingEnabled: nil,
            voiceRoamingEnabled: nil,
            roaming: nil,
            personalHotspotEnabled: nil
        )
    }

    private func makeDetail(
        displayName: String = "Test Mac",
        serial: String = "C02ABC123XYZ",
        network: SupportNetworkInfo? = nil
    ) -> SupportDeviceDetail {
        let summary = SupportSearchResult(
            assetType: .computer,
            inventoryID: "1",
            managementID: "mgmt-1",
            clientManagementID: nil,
            displayName: displayName,
            serialNumber: serial,
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
            rawJSON: "{}",
            networkInfo: network
        )
    }

    // MARK: - Priority

    func test_manualOverride_winsOverInventory() {
        let detail = makeDetail(network: makeNetwork(hostname: "mac.corp.example.com"))
        let resolution = resolver.resolve(detail: detail, manualOverride: "10.0.0.5")
        XCTAssertEqual(resolution.target?.host, "10.0.0.5")
        XCTAssertEqual(resolution.target?.source, .manualOverride)
        XCTAssertEqual(resolution.target?.confidence, .high)
    }

    func test_inventoryHostname_winsOverDisplayName() {
        let detail = makeDetail(displayName: "Some Display Name",
                                network: makeNetwork(lastReportedIpV4: "192.168.1.50", hostname: "mac.corp.example.com"))
        let resolution = resolver.resolve(detail: detail)
        XCTAssertEqual(resolution.target?.host, "mac.corp.example.com")
        XCTAssertEqual(resolution.target?.source, .inventoryHostname)
    }

    func test_lastReportedIPv4_fallback() {
        let detail = makeDetail(network: makeNetwork(ipAddress: "10.1.1.9", lastReportedIpV4: "192.168.1.50"))
        let resolution = resolver.resolve(detail: detail)
        XCTAssertEqual(resolution.target?.host, "192.168.1.50")
        XCTAssertEqual(resolution.target?.source, .lastReportedIPv4)
    }

    func test_currentIP_fallback() {
        let detail = makeDetail(network: makeNetwork(ipAddress: "10.1.1.9"))
        let resolution = resolver.resolve(detail: detail)
        XCTAssertEqual(resolution.target?.host, "10.1.1.9")
        XCTAssertEqual(resolution.target?.source, .currentIPAddress)
        XCTAssertEqual(resolution.target?.confidence, .medium)
    }

    func test_displayNameFQDN_used() {
        let detail = makeDetail(displayName: "lab-mac.corp.example.com")
        let resolution = resolver.resolve(detail: detail)
        XCTAssertEqual(resolution.target?.host, "lab-mac.corp.example.com")
        XCTAssertEqual(resolution.target?.source, .displayNameHost)
    }

    func test_bonjourFallback_isLowConfidence() {
        let detail = makeDetail(displayName: "MacBook-Pro")
        let resolution = resolver.resolve(detail: detail)
        XCTAssertEqual(resolution.target?.host, "MacBook-Pro.local")
        XCTAssertEqual(resolution.target?.source, .bonjourLocal)
        XCTAssertEqual(resolution.target?.confidence, .low)
    }

    // MARK: - Rejection

    func test_serialNumber_neverUsed() {
        // Display name equals the serial; no network info → must NOT resolve to the serial.
        let detail = makeDetail(displayName: "C02ABC123XYZ", serial: "C02ABC123XYZ")
        let resolution = resolver.resolve(detail: detail)
        XCTAssertFalse(resolution.isResolved)
        XCTAssertNotNil(resolution.unresolvedReason)
    }

    func test_manualOverrideSerial_rejected() {
        let detail = makeDetail()
        let resolution = resolver.resolve(detail: detail, manualOverride: "C02ABC123XYZ")
        XCTAssertFalse(resolution.isResolved)
        XCTAssertEqual(resolution.unresolvedReason?.contains("serial"), true)
    }

    func test_manualOverrideWithSpaces_rejected() {
        let detail = makeDetail()
        let resolution = resolver.resolve(detail: detail, manualOverride: "not a host")
        XCTAssertFalse(resolution.isResolved)
    }

    func test_displayNameWithSpaces_notBonjourSafe_unresolved() {
        let detail = makeDetail(displayName: "Jane's MacBook Pro")
        let resolution = resolver.resolve(detail: detail)
        XCTAssertFalse(resolution.isResolved)
    }

    func test_blankEverything_unresolved() {
        let detail = makeDetail(displayName: "", serial: "")
        let resolution = resolver.resolve(detail: detail)
        XCTAssertFalse(resolution.isResolved)
        XCTAssertNotNil(resolution.unresolvedReason)
    }

    // MARK: - Safe URL construction

    func test_screenSharingURL_isPercentEncodedVNC() {
        let detail = makeDetail(network: makeNetwork(hostname: "mac.corp.example.com"))
        let target = resolver.resolve(detail: detail).target
        XCTAssertEqual(target?.screenSharingURL, URL(string: "vnc://mac.corp.example.com"))
    }
}

//endofline
