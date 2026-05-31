import XCTest
@testable import Forsetti

final class SupportTechnicianCommandHistoryTests: XCTestCase {

    func test_commandHistoryFilterQuotesAndEscapesClientManagementID() {
        let filter = SupportTechnicianAPIService.commandHistoryFilter(for: "  abc'123  ")

        XCTAssertEqual(filter, "clientManagementId=='abc\\'123'")
    }

    func test_modernCommandHistoryParsesNestedCommandAndErrors() throws {
        let json = """
        {
          "results": [
            {
              "uuid": "command-1",
              "command": { "commandType": "DEVICE_INFORMATION" },
              "status": "Completed",
              "dateSent": "2026-05-24T10:00:00Z",
              "dateCompleted": "2026-05-24T10:01:00Z"
            },
            {
              "id": "command-2",
              "commandType": "RESTART_DEVICE",
              "commandStatus": "Failed",
              "issued": "2026-05-24T10:05:00Z",
              "failureReason": "Device was offline"
            }
          ]
        }
        """

        let records = SupportTechnicianAPIService.parseModernMDMCommandHistory(from: Data(json.utf8))

        XCTAssertEqual(records.count, 2)
        XCTAssertEqual(records[0].uuid, "command-1")
        XCTAssertEqual(records[0].commandType, "DEVICE_INFORMATION")
        XCTAssertEqual(records[0].bucket, .completed)
        XCTAssertEqual(records[1].uuid, "command-2")
        XCTAssertEqual(records[1].commandType, "RESTART_DEVICE")
        XCTAssertEqual(records[1].bucket, .failed)
        XCTAssertEqual(records[1].errorReasons, ["Device was offline"])
    }

    func test_bucketMatchesJamfStatusVariants() {
        func bucket(for status: String) -> SupportMDMCommandRecord.Bucket {
            SupportMDMCommandRecord(
                uuid: "x",
                commandType: "y",
                status: status,
                dateSent: nil,
                dateCompleted: nil,
                errorReasons: [],
                source: .modern
            ).bucket
        }

        // v2 standard values
        XCTAssertEqual(bucket(for: "Pending"), .pending)
        XCTAssertEqual(bucket(for: "Acknowledged"), .completed)
        XCTAssertEqual(bucket(for: "Error"), .failed)
        XCTAssertEqual(bucket(for: "NotNow"), .notNow)

        // Casing / spacing variants seen across Jamf versions
        XCTAssertEqual(bucket(for: "PENDING"), .pending)
        XCTAssertEqual(bucket(for: "NOT_NOW"), .notNow)
        XCTAssertEqual(bucket(for: "Not Now"), .notNow)

        // States that previously fell through to .other and made
        // the colored bucket boxes read zero even when commands existed
        XCTAssertEqual(bucket(for: "Sent"), .pending)
        XCTAssertEqual(bucket(for: "Sending"), .pending)
        XCTAssertEqual(bucket(for: "Issued"), .pending)
        XCTAssertEqual(bucket(for: "Idle"), .pending)
        XCTAssertEqual(bucket(for: "Expired"), .failed)
        XCTAssertEqual(bucket(for: "Cancelled"), .failed)

        // Verbose Jamf suffixes
        XCTAssertEqual(bucket(for: "Acknowledged (1 retries)"), .completed)
        XCTAssertEqual(bucket(for: "Error - device offline"), .failed)
        XCTAssertEqual(bucket(for: "Pending: queued at 10:00"), .pending)

        // Genuinely unknown still falls through
        XCTAssertEqual(bucket(for: "(unknown)"), .other)
        XCTAssertEqual(bucket(for: ""), .other)
    }

    func test_modernCommandHistoryParsesDocumentedV2NestedShape() {
        // Mirrors the real GET /api/v2/mdm/commands response: every field
        // the frame needs (commandType, the status under `commandState`,
        // dates) is nested inside `command`, with `client` alongside it.
        // The previous parser read only the flat `status`/`commandType`
        // keys, so every record resolved to "(unknown)" -> .other and the
        // colored bucket boxes read zero against a non-empty response.
        let json = """
        {
          "totalCount": 3,
          "results": [
            {
              "client": { "managementId": "mgmt-1", "type": "COMPUTER" },
              "command": {
                "uuid": "cmd-1",
                "clientManagementId": "mgmt-1",
                "commandState": "PENDING",
                "commandType": "DEVICE_INFORMATION",
                "dateSent": "2026-05-29T12:48:00Z"
              }
            },
            {
              "client": { "managementId": "mgmt-1", "type": "COMPUTER" },
              "command": {
                "uuid": "cmd-2",
                "commandState": "ACKNOWLEDGED",
                "commandType": "SETTINGS",
                "dateSent": "2026-05-29T12:40:00Z",
                "dateCompleted": "2026-05-29T12:41:00Z"
              }
            },
            {
              "client": { "managementId": "mgmt-1", "type": "COMPUTER" },
              "command": {
                "uuid": "cmd-3",
                "commandState": "ERROR",
                "commandType": "RESTART_DEVICE",
                "errorReasons": ["Device was offline"]
              }
            }
          ]
        }
        """

        let records = SupportTechnicianAPIService.parseModernMDMCommandHistory(from: Data(json.utf8))

        XCTAssertEqual(records.count, 3)
        XCTAssertEqual(records[0].uuid, "cmd-1")
        XCTAssertEqual(records[0].commandType, "DEVICE_INFORMATION")
        XCTAssertEqual(records[0].status, "PENDING")
        XCTAssertEqual(records[0].bucket, .pending)
        XCTAssertEqual(records[1].commandType, "SETTINGS")
        XCTAssertEqual(records[1].bucket, .completed)
        XCTAssertEqual(records[2].commandType, "RESTART_DEVICE")
        XCTAssertEqual(records[2].bucket, .failed)
        XCTAssertEqual(records[2].errorReasons, ["Device was offline"])
        XCTAssertEqual(records.map(\.bucket), [.pending, .completed, .failed])
    }

    func test_modernCommandHistoryParsesTopLevelArrayShape() {
        // Some tenants/versions return a bare top-level array rather than
        // a `{ "results": [...] }` object. The previous parser cast the
        // top level to a dictionary and returned [] for an array, silently
        // dropping every record.
        let json = """
        [
          { "uuid": "a1", "commandType": "RESTART_DEVICE", "status": "Pending" },
          { "uuid": "a2", "commandType": "DEVICE_LOCK", "status": "Acknowledged" },
          { "uuid": "a3", "commandType": "ERASE_DEVICE", "status": "NotNow" }
        ]
        """

        let records = SupportTechnicianAPIService.parseModernMDMCommandHistory(from: Data(json.utf8))

        XCTAssertEqual(records.count, 3)
        XCTAssertEqual(records.map(\.bucket), [.pending, .completed, .notNow])
    }

    func test_commandHistoryShapeSummaryReportsBucketsAndNesting() {
        let json = """
        {
          "results": [
            { "command": { "uuid": "s1", "commandState": "PENDING", "commandType": "SETTINGS" } },
            { "command": { "uuid": "s2", "commandState": "ACKNOWLEDGED", "commandType": "SETTINGS" } }
          ]
        }
        """
        let data = Data(json.utf8)
        let records = SupportTechnicianAPIService.parseModernMDMCommandHistory(from: data)
        let summary = SupportTechnicianAPIService.commandHistoryShapeSummary(data: data, records: records)

        XCTAssertEqual(summary["top_level"], "object")
        XCTAssertEqual(summary["results_count"], "2")
        XCTAssertEqual(summary["parsed_count"], "2")
        // Status lives under `command`, so the summary must surface that the
        // nested object is where the parser found the fields.
        XCTAssertEqual(summary["first_command_keys"], "commandState,commandType,uuid")
        XCTAssertEqual(summary["first_bucket"], "pending")
        XCTAssertEqual(summary["buckets"], "pending=1 completed=1 failed=0 notNow=0 other=0")
    }

    func test_classicCommandHistoryParsesBuckets() {
        let json = """
        {
          "computer_history": {
            "commands": {
              "completed": [
                {
                  "id": "classic-1",
                  "name": "UpdateInventory",
                  "date_time_issued": "2026-05-24T10:00:00Z",
                  "date_time_completed": "2026-05-24T10:01:00Z"
                }
              ],
              "pending": [
                {
                  "id": "classic-2",
                  "command": "DeviceInformation",
                  "issued": "2026-05-24T10:02:00Z"
                }
              ],
              "failed": [
                {
                  "id": "classic-3",
                  "name": "RestartDevice",
                  "failed_reason": "NotNow"
                }
              ]
            }
          }
        }
        """

        let records = SupportTechnicianAPIService.parseClassicMDMCommandHistory(from: Data(json.utf8))

        XCTAssertEqual(records.count, 3)
        XCTAssertEqual(records.map(\.bucket), [.completed, .pending, .failed])
        XCTAssertEqual(records[2].errorReasons, ["NotNow"])
    }
}
