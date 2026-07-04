import XCTest
@testable import ForsettiJamfProApp

final class DeploymentDemoScenarioCatalogTests: XCTestCase {
    func test_demoScenarioCatalogContainsAtLeastTwelveScenarios() {
        XCTAssertGreaterThanOrEqual(DeploymentDemoScenarioCatalog.scenarios.count, 12)
    }

    func test_demoScenarioCatalogContainsAllPass2RequiredScenarioIDs() {
        let scenarioIDs = Set(DeploymentDemoScenarioCatalog.scenarios.map(\.id))

        for requiredID in DeploymentDemoScenarioCatalog.requiredScenarioIDs {
            XCTAssertTrue(scenarioIDs.contains(requiredID), "Missing scenario \(requiredID)")
        }
    }

    func test_demoScenarioIDsAreUnique() {
        let scenarioIDs = DeploymentDemoScenarioCatalog.scenarios.map(\.id)

        XCTAssertEqual(Set(scenarioIDs).count, scenarioIDs.count)
    }

    func test_demoScenariosHaveStepsHighlightTargetsActionsExpectedResultsAndGuideTopics() {
        for scenario in DeploymentDemoScenarioCatalog.scenarios {
            XCTAssertGreaterThanOrEqual(scenario.steps.count, 4, "Scenario \(scenario.id) has too few steps")
            XCTAssertFalse(scenario.expectedResult.isEmpty, "Scenario \(scenario.id) missing expected result")
            XCTAssertFalse(scenario.relatedGuideTopicID.isEmpty, "Scenario \(scenario.id) missing guide topic")
            XCTAssertFalse(scenario.productionEquivalent.isEmpty, "Scenario \(scenario.id) missing production equivalent")

            for step in scenario.steps {
                XCTAssertFalse(step.title.isEmpty, "Scenario \(scenario.id) has step without title")
                XCTAssertFalse(step.body.isEmpty, "Scenario \(scenario.id) has step without body")
                XCTAssertFalse(step.expectedResult.isEmpty, "Scenario \(scenario.id) has step without expected result")
                XCTAssertTrue(DeploymentDemoHighlightTarget.allCases.contains(step.highlightTarget))
                XCTAssertTrue(DeploymentDemoActionKind.allCases.contains(step.actionKind))
            }
        }
    }

    func test_demoScenarioCatalogCoversRequiredWorkspaces() {
        let workspaces = Set(DeploymentDemoScenarioCatalog.scenarios.map(\.workspace))

        XCTAssertTrue(workspaces.contains(.dashboard))
        XCTAssertTrue(workspaces.contains(.inProgress))
        XCTAssertTrue(workspaces.contains(.intakeImports))
        XCTAssertTrue(workspaces.contains(.jamfPreload))
        XCTAssertTrue(workspaces.contains(.abmVerification))
        XCTAssertTrue(workspaces.contains(.sdPlusExport))
        XCTAssertTrue(workspaces.contains(.shipments))
        XCTAssertTrue(workspaces.contains(.recordsManagement))
        XCTAssertTrue(workspaces.contains(.administration))
    }

    func test_scenarioLookupReturnsRequiredScenariosByID() {
        for requiredID in DeploymentDemoScenarioCatalog.requiredScenarioIDs {
            XCTAssertEqual(DeploymentDemoScenarioCatalog.scenario(id: requiredID)?.id, requiredID)
        }
    }

    func test_legacyScenarioLookupAliasesRemainGuideCompatible() {
        XCTAssertEqual(DeploymentDemoScenarioCatalog.scenario(id: "full_deployment_flow")?.id, "quick-start-tour")
        XCTAssertEqual(DeploymentDemoScenarioCatalog.scenario(id: "jamf_preload_supersedence")?.id, "jamf-preload-update")
        XCTAssertEqual(DeploymentDemoScenarioCatalog.scenario(id: "abm_mismatch_handling")?.id, "abm-verification-simulation")
        XCTAssertEqual(DeploymentDemoScenarioCatalog.scenario(id: "sdplus_export_and_shipping")?.id, "sdplus-export-simulation")
    }
}
