import XCTest
@testable import Jamf_Dashboard

@MainActor
final class DeploymentTrackerGuideTests: XCTestCase {
    func test_guideIncludesEveryRequiredTopic() {
        let topicIDs = Set(DeploymentTrackerGuideContent.topics.map(\.id))

        for requiredTopicID in DeploymentTrackerGuideContent.requiredTopicIDs {
            XCTAssertTrue(topicIDs.contains(requiredTopicID), "Missing guide topic \(requiredTopicID)")
        }
    }

    func test_requiredGuideTopicsHaveStepsAndExpectedResults() {
        for topic in DeploymentTrackerGuideContent.topics {
            XCTAssertFalse(topic.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            XCTAssertFalse(topic.summary.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            XCTAssertFalse(topic.steps.isEmpty, "Topic \(topic.id) needs step-by-step content.")
            XCTAssertFalse(topic.expectedResult.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
    }

    func test_guideSearchFindsJamfPermissionsTopic() {
        let results = DeploymentTrackerGuideContent.topics(matching: "403 API role privilege")

        XCTAssertTrue(results.contains { $0.id == "jamf-permissions" })
    }

    func test_workspacesMapToContextualGuideTopics() {
        XCTAssertEqual(DeploymentTrackerWorkspace.dashboard.guideTopicID, "dashboard")
        XCTAssertEqual(DeploymentTrackerWorkspace.inProgress.guideTopicID, "workbench")
        XCTAssertEqual(DeploymentTrackerWorkspace.intakeImports.guideTopicID, "imports")
        XCTAssertEqual(DeploymentTrackerWorkspace.jamfPreload.guideTopicID, "jamf-preload")
        XCTAssertEqual(DeploymentTrackerWorkspace.sdPlusExport.guideTopicID, "sdplus-export")
        XCTAssertEqual(DeploymentTrackerWorkspace.guide.guideTopicID, "start-here")
    }

    func test_structuredErrorCarriesRelatedGuideTopicInDiagnosticsMetadata() {
        let error = DeploymentUserFacingIntegrationError(
            title: "Permission failure",
            summary: "Jamf rejected the request.",
            technicalCause: "HTTP 403",
            requiredJamfPrivileges: ["Read Inventory Preload Records"],
            localDataChanged: false,
            externalDataChanged: false,
            safeToRetry: true,
            recommendedAction: "Update the Jamf API role.",
            diagnosticsCategory: "deployment-tracker.jamf-preload.permission",
            diagnosticsCorrelationId: "abc-123",
            relatedGuideTopicId: "jamf-permissions"
        )

        XCTAssertEqual(error.diagnosticsMetadata["related_guide_topic_id"], "jamf-permissions")
        XCTAssertEqual(error.relatedGuideTopicId, "jamf-permissions")
    }
}
