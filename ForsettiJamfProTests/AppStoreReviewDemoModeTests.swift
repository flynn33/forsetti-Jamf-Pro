import Foundation
import XCTest
@testable import ForsettiJamfProApp

final class AppStoreReviewDemoModeTests: XCTestCase {

    private var previousDemoEnabled: Bool = false

    override func setUp() {
        super.setUp()
        previousDemoEnabled = AppStoreReviewDemoMode.isEnabled
        AppStoreReviewDemoMode.setEnabled(false)
    }

    override func tearDown() {
        AppStoreReviewDemoMode.setEnabled(previousDemoEnabled)
        super.tearDown()
    }

    // MARK: - Mode flag

    func test_demoModeDefaultsOffAndTogglesWithoutCredentials() {
        XCTAssertFalse(AppStoreReviewDemoMode.isEnabled)
        AppStoreReviewDemoMode.setEnabled(true)
        XCTAssertTrue(AppStoreReviewDemoMode.isEnabled)
        AppStoreReviewDemoMode.setEnabled(false)
        XCTAssertFalse(AppStoreReviewDemoMode.isEnabled)
    }

    func test_demoCopyIsAppReviewOriented() {
        XCTAssertTrue(AppStoreReviewDemoMode.ribbonMessage.contains("APP STORE DEMO"))
        XCTAssertTrue(AppStoreReviewDemoMode.ribbonMessage.contains("SAMPLE DATA"))
        XCTAssertTrue(AppStoreReviewDemoMode.safetyMessage.contains("No live Jamf Pro"))
        XCTAssertTrue(AppStoreReviewDemoMode.appReviewNotes.contains("Explore App Store Demo"))
        XCTAssertTrue(AppStoreReviewDemoMode.appReviewNotes.contains("C02DEMO0001"))
    }

    // MARK: - Response router safety

    func test_routerServesComputerInventoryThatDecodesAsSearchResponse() throws {
        let data = try AppStoreDemoResponseRouter.response(
            path: "api/v3/computers-inventory",
            method: .get,
            queryItems: []
        )
        let payload = try JSONDecoder().decode(ComputerSearchResponse.self, from: data)
        XCTAssertEqual(payload.results.count, 3)
        XCTAssertTrue(payload.results.contains(where: { $0.serialNumber == "C02DEMO0001" }))
        XCTAssertTrue(payload.results.contains(where: { $0.computerName.contains("Reviewer") }))
    }

    func test_routerFiltersComputersByQuerySubstring() throws {
        let data = try AppStoreDemoResponseRouter.response(
            path: "api/v1/computers-inventory",
            method: .get,
            queryItems: [URLQueryItem(name: "filter", value: "macbook")]
        )
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let results = try XCTUnwrap(json["results"] as? [[String: Any]])
        XCTAssertEqual(results.count, 1)
        let general = try XCTUnwrap(results[0]["general"] as? [String: Any])
        XCTAssertEqual(general["name"] as? String, "Reviewer MacBook Pro")
    }

    func test_routerFiltersComputersUsingSupportTechnicianRSQL() throws {
        // Mirrors SupportTechnicianAPIService.buildComputerFilter (double-quoted wildcards).
        let filter = #"(general.name=="*C02DEMO0001*",hardware.serialNumber=="*C02DEMO0001*",userAndLocation.username=="*C02DEMO0001*",userAndLocation.email=="*C02DEMO0001*")"#
        let data = try AppStoreDemoResponseRouter.response(
            path: "api/v3/computers-inventory",
            method: .get,
            queryItems: [
                URLQueryItem(name: "page", value: "0"),
                URLQueryItem(name: "page-size", value: "200"),
                URLQueryItem(name: "filter", value: filter)
            ]
        )
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let results = try XCTUnwrap(json["results"] as? [[String: Any]])
        XCTAssertEqual(results.count, 1)
        let hardware = try XCTUnwrap(results[0]["hardware"] as? [String: Any])
        XCTAssertEqual(hardware["serialNumber"] as? String, "C02DEMO0001")
        let general = try XCTUnwrap(results[0]["general"] as? [String: Any])
        XCTAssertEqual(general["managementId"] as? String, "11111111-1111-4111-8111-111111111101")
    }

    func test_routerFiltersMobileUsingSupportTechnicianRSQL() throws {
        let filter = "(serialNumber=='*F9FDEMO0001*',username=='*F9FDEMO0001*')"
        let data = try AppStoreDemoResponseRouter.response(
            path: "api/v2/mobile-devices/detail",
            method: .get,
            queryItems: [URLQueryItem(name: "filter", value: filter)]
        )
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let results = try XCTUnwrap(json["results"] as? [[String: Any]])
        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(results[0]["serialNumber"] as? String, "F9FDEMO0001")
    }

    func test_routerComputerDetailIncludesApplicationsAndManagementID() throws {
        let data = try AppStoreDemoResponseRouter.response(
            path: "api/v1/computers-inventory/1001",
            method: .get,
            queryItems: [URLQueryItem(name: "section", value: "APPLICATIONS")]
        )
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let general = try XCTUnwrap(json["general"] as? [String: Any])
        XCTAssertEqual(general["managementId"] as? String, "11111111-1111-4111-8111-111111111101")
        let apps = try XCTUnwrap(json["applications"] as? [[String: Any]])
        XCTAssertGreaterThanOrEqual(apps.count, 3)
        XCTAssertTrue(apps.contains { ($0["name"] as? String) == "Safari" })
    }

    func test_routerInventoryDetailPathResolvesComputer() throws {
        let data = try AppStoreDemoResponseRouter.response(
            path: "api/v2/computers-inventory-detail/1002",
            method: .get
        )
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(String(describing: json["id"] ?? ""), "1002")
        let hardware = try XCTUnwrap(json["hardware"] as? [String: Any])
        XCTAssertEqual(hardware["serialNumber"] as? String, "C02DEMO0002")
    }

    func test_routerMDMCommandHistoryParsesForSupportFrame() throws {
        let data = try AppStoreDemoResponseRouter.response(
            path: "api/v2/mdm/commands",
            method: .get,
            queryItems: [
                URLQueryItem(name: "filter", value: "clientManagementId=='11111111-1111-4111-8111-111111111101'")
            ]
        )
        let history = SupportTechnicianAPIService.parseModernMDMCommandHistory(from: data)
        XCTAssertEqual(history.count, 4)
        XCTAssertTrue(history.contains { $0.commandType == "DEVICE_INFORMATION" })
        XCTAssertTrue(history.contains { $0.status == "Pending" })
        XCTAssertTrue(history.contains { $0.status == "Failed" })
    }

    func test_routerClassicPoliciesListForPolicyFrame() throws {
        let data = try AppStoreDemoResponseRouter.response(
            path: "JSSResource/policies",
            method: .get
        )
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let policies = try XCTUnwrap(json["policies"] as? [[String: Any]])
        XCTAssertGreaterThanOrEqual(policies.count, 3)
        XCTAssertTrue(policies.contains { ($0["name"] as? String)?.contains("Demo") == true })
    }

    func test_routerServesMobileDevicesDetailEnvelope() throws {
        let data = try AppStoreDemoResponseRouter.response(
            path: "api/v2/mobile-devices/detail",
            method: .get,
            queryItems: [URLQueryItem(name: "page", value: "0")]
        )
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let results = try XCTUnwrap(json["results"] as? [[String: Any]])
        XCTAssertEqual(results.count, 3)
        XCTAssertEqual(json["totalCount"] as? Int, 3)
    }

    func test_routerAuthEndpointReturnsPrivilegesForRuntimeChecks() throws {
        let data = try AppStoreDemoResponseRouter.response(
            path: "api/v1/auth",
            method: .get
        )
        let privileges = JamfAPIGateway.parseAuthorizations(from: data)
        XCTAssertFalse(privileges.isEmpty)
        XCTAssertTrue(privileges.contains("View MDM command information in Jamf Pro API"))
        XCTAssertTrue(privileges.contains("Read Computers"))
    }

    func test_routerMutationsAreSimulatedAndNeverClaimExternalChange() throws {
        let methods: [HTTPMethod] = [.post, .put, .delete]
        for method in methods {
            let data = try AppStoreDemoResponseRouter.response(
                path: "api/v2/mdm/commands",
                method: method,
                body: Data("{}".utf8)
            )
            let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
            XCTAssertEqual(json["externalDataChanged"] as? Bool, false)
            XCTAssertEqual(json["demoMode"] as? Bool, true)
            let message = try XCTUnwrap(json["message"] as? String)
            XCTAssertTrue(message.contains("No live Jamf Pro action ran"))
        }
    }

    func test_routerNeverRequiresNetworkForUnknownPaths() throws {
        let data = try AppStoreDemoResponseRouter.response(
            path: "api/v9/totally-unknown-endpoint",
            method: .get
        )
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(json["totalCount"] as? Int, 0)
    }

    // MARK: - Gateway hard gate

    @MainActor
    func test_gatewayDemoModeNeverUsesURLSession() async throws {
        AppStoreReviewDemoMode.setEnabled(true)

        let store = JamfCredentialsStore(secureStore: DemoTestSecureStore())
        // Intentionally no credentials — demo must still succeed.
        XCTAssertFalse(store.hasStoredCredentials)

        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [DemoFailIfUsedURLProtocol.self]
        let session = URLSession(configuration: config)

        let gateway = JamfAPIGateway(
            credentialsStore: store,
            authenticationService: JamfAuthenticationService(
                diagnosticsReporter: DemoNoopDiagnosticsReporter()
            ),
            diagnosticsReporter: DemoNoopDiagnosticsReporter(),
            session: session
        )

        DemoFailIfUsedURLProtocol.reset()
        let data = try await gateway.request(
            path: "api/v3/computers-inventory",
            method: .get
        )
        XCTAssertEqual(DemoFailIfUsedURLProtocol.requestCount, 0)

        let payload = try JSONDecoder().decode(ComputerSearchResponse.self, from: data)
        XCTAssertEqual(payload.results.count, 3)

        let baseURL = await gateway.currentServerBaseURL()
        XCTAssertEqual(baseURL?.absoluteString, AppStoreReviewDemoMode.demoServerURLString)

        let privileges = try await gateway.fetchTokenAuthorizations()
        XCTAssertFalse(privileges.isEmpty)
        XCTAssertEqual(DemoFailIfUsedURLProtocol.requestCount, 0)
    }

    @MainActor
    func test_sessionAvailabilityTrueInDemoWithoutKeychainCredentials() {
        let store = JamfCredentialsStore(secureStore: DemoTestSecureStore())
        XCTAssertFalse(JamfSessionAvailability.isAvailable(credentialsStore: store))

        AppStoreReviewDemoController.shared.enable()
        XCTAssertTrue(JamfSessionAvailability.isAvailable(credentialsStore: store))

        AppStoreReviewDemoController.shared.disable()
        XCTAssertFalse(JamfSessionAvailability.isAvailable(credentialsStore: store))
    }
}

// MARK: - Test doubles

private final class DemoTestSecureStore: SecureDataStore, @unchecked Sendable {
    private var storage: [String: Data] = [:]

    func save(data: Data, for key: String) throws {
        storage[key] = data
    }

    func loadData(for key: String) throws -> Data? {
        storage[key]
    }

    func deleteData(for key: String) throws {
        storage.removeValue(forKey: key)
    }
}

private actor DemoNoopDiagnosticsReporter: DiagnosticsReporting {
    func report(
        source: String,
        category: String,
        severity: DiagnosticSeverity,
        message: String,
        metadata: [String: String]
    ) async {}

    func currentEvents() async -> [DiagnosticEvent] { [] }
    func renderJSONReportData() async throws -> Data { Data("[]".utf8) }
    func renderMarkdownReportData() async throws -> Data { Data() }
    func suggestedExportFileName(extension ext: String) async -> String {
        "demo-diagnostics.\(ext)"
    }
    func clear() async {}
    func persistentLogFileURL() async -> URL? { nil }
}

private final class DemoFailIfUsedURLProtocol: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) private static var _requestCount = 0
    private static let lock = NSLock()

    static var requestCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return _requestCount
    }

    static func reset() {
        lock.lock()
        defer { lock.unlock() }
        _requestCount = 0
    }

    override class func canInit(with request: URLRequest) -> Bool {
        true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        Self.lock.lock()
        Self._requestCount += 1
        Self.lock.unlock()
        client?.urlProtocol(self, didFailWithError: URLError(.notConnectedToInternet))
    }

    override func stopLoading() {}
}
