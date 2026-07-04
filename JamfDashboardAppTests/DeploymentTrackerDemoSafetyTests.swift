import XCTest
@testable import Jamf_Dashboard

final class DeploymentTrackerDemoSafetyTests: XCTestCase {
    func test_installedDemoConfigurationDisablesAllLiveAndExternalActions() {
        let configuration = DeploymentTrackerDemoConfiguration.installedDemo

        XCTAssertEqual(configuration.runtimeMode, .demo)
        XCTAssertFalse(configuration.allowLiveJamfActions)
        XCTAssertFalse(configuration.allowLiveABMActions)
        XCTAssertFalse(configuration.allowLiveSDPlusActions)
        XCTAssertFalse(configuration.allowExternalNetworkActions)
    }

    func test_installedDemoConfigurationSeedsAndResetsDummyDataOnLaunch() {
        let configuration = DeploymentTrackerDemoConfiguration.installedDemo

        XCTAssertTrue(configuration.showDemoRibbon)
        XCTAssertTrue(configuration.seedDummyDataOnLaunch)
        XCTAssertTrue(configuration.resetDummyDataOnLaunch)
    }

    func test_runtimeModeCodableRoundTripsDemoAndProductionDisabled() throws {
        let modes: [DeploymentTrackerRuntimeMode] = [.demo, .productionDisabled]
        let data = try JSONEncoder().encode(modes)
        let decoded = try JSONDecoder().decode([DeploymentTrackerRuntimeMode].self, from: data)

        XCTAssertEqual(decoded, modes)
    }

    func test_runtimeModeDemoPropertiesResolveInstalledDemoMode() {
        XCTAssertTrue(DeploymentTrackerRuntimeMode.demo.isDemoMode)
        XCTAssertEqual(DeploymentTrackerRuntimeMode.demo.demoMode, .installedDefault)
        XCTAssertFalse(DeploymentTrackerRuntimeMode.productionDisabled.isDemoMode)
        XCTAssertNil(DeploymentTrackerRuntimeMode.productionDisabled.demoMode)
    }

    func test_demoModeWarningCopyUsesDummyDataAndNoLiveJamfActions() {
        let mode = DeploymentTrackerDemoMode.installedDefault

        XCTAssertTrue(mode.safetyMessage.contains("Dummy data only"))
        XCTAssertTrue(mode.safetyMessage.contains("No live Jamf actions"))
        XCTAssertTrue(mode.ribbonMessage.contains("DUMMY DATA ONLY"))
        XCTAssertTrue(mode.ribbonMessage.contains("NO LIVE JAMF ACTIONS"))
    }

    func test_demoIntegrationSimulatorReturnsNoExternalDataChangedForEverySupportedSystem() {
        let simulator = DeploymentTrackerDemoIntegrationSimulator()
        let results = [
            simulator.simulateJamfPreload(recordCount: 2),
            simulator.simulateABMVerification(recordCount: 3),
            simulator.simulateSDPlusExport(recordCount: 4),
            simulator.simulateShippingReturns(recordCount: 5),
            simulator.simulateRecordsArchive(recordCount: 6),
            simulator.simulateImportPreview(recordCount: 7),
            simulator.simulateValidationRecovery(recordCount: 8),
            simulator.simulateAdministrationReview(recordCount: 9)
        ]

        XCTAssertTrue(results.allSatisfy { $0.externalDataChanged == false })
        XCTAssertTrue(results.allSatisfy { $0.summary.contains("No external data changed") })
        XCTAssertTrue(results.allSatisfy { $0.affectedDemoRecordCount > 0 })
    }

    func test_demoIntegrationSimulatorRejectsLiveActionsWhenSafetyFlagsAreDisabled() {
        let simulator = DeploymentTrackerDemoIntegrationSimulator(configuration: .installedDemo)

        XCTAssertEqual(
            simulator.liveActionBlocked("Jamf upload"),
            .liveActionBlocked(action: "Jamf upload")
        )
    }
}
