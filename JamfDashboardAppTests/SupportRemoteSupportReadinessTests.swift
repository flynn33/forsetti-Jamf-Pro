import XCTest
@testable import Jamf_Dashboard

/// Verifies the pure readiness evaluator (Jamf command-status → readiness verdict) and the honest
/// combined report summary. The evaluator shares `SupportMDMCommandRecord.bucket` normalization,
/// so tenant status variants (`Acknowledged (1 retries)`, `Error - …`, classic `Completed`) map
/// correctly. Reachability is always reported as a separate signal from command status.
final class SupportRemoteSupportReadinessTests: XCTestCase {

    private let evaluator = SupportRemoteSupportReadinessEvaluator()

    private func record(
        uuid: String = "enable-1",
        commandType: String = "ENABLE_REMOTE_DESKTOP",
        status: String,
        errorReasons: [String] = []
    ) -> SupportMDMCommandRecord {
        SupportMDMCommandRecord(
            uuid: uuid,
            commandType: commandType,
            status: status,
            dateSent: nil,
            dateCompleted: nil,
            errorReasons: errorReasons,
            source: .modern
        )
    }

    // MARK: - Command verdicts

    func test_acknowledged_isConfirmed() {
        let v = evaluator.evaluateCommand(records: [record(status: "Acknowledged")], enableCommandID: nil)
        XCTAssertEqual(v, .confirmed)
    }

    func test_completedClassic_isConfirmed() {
        let v = evaluator.evaluateCommand(records: [record(status: "Completed")], enableCommandID: nil)
        XCTAssertEqual(v, .confirmed)
    }

    func test_acknowledgedWithRetrySuffix_isConfirmed() {
        let v = evaluator.evaluateCommand(records: [record(status: "Acknowledged (1 retries)")], enableCommandID: nil)
        XCTAssertEqual(v, .confirmed)
    }

    func test_pending_isPending() {
        let v = evaluator.evaluateCommand(records: [record(status: "Pending")], enableCommandID: nil)
        XCTAssertEqual(v, .pending)
    }

    func test_notNow_isPending() {
        let v = evaluator.evaluateCommand(records: [record(status: "NotNow")], enableCommandID: nil)
        XCTAssertEqual(v, .pending)
    }

    func test_error_isFailedWithReason() {
        let v = evaluator.evaluateCommand(
            records: [record(status: "Error - device offline", errorReasons: ["device offline"])],
            enableCommandID: nil
        )
        XCTAssertEqual(v, .failed(reason: "device offline"))
    }

    func test_failedWithoutReason_usesStatus() {
        let v = evaluator.evaluateCommand(records: [record(status: "Failed")], enableCommandID: nil)
        XCTAssertEqual(v, .failed(reason: "Failed"))
    }

    // MARK: - Record selection

    func test_noEnableRecord_isUnknown() {
        let other = record(uuid: "x", commandType: "DeviceInformation", status: "Acknowledged")
        let v = evaluator.evaluateCommand(records: [other], enableCommandID: nil)
        XCTAssertEqual(v, .unknown)
    }

    func test_emptyHistory_isUnknown() {
        let v = evaluator.evaluateCommand(records: [], enableCommandID: nil)
        XCTAssertEqual(v, .unknown)
    }

    func test_picksEnableCommand_ignoringOtherTypes() {
        let records = [
            record(uuid: "a", commandType: "DeviceInformation", status: "Acknowledged"),
            record(uuid: "b", commandType: "ENABLE_REMOTE_DESKTOP", status: "Pending")
        ]
        XCTAssertEqual(evaluator.evaluateCommand(records: records, enableCommandID: nil), .pending)
    }

    func test_uuidMatchWins_overNewerEnableRecord() {
        let records = [
            record(uuid: "new", status: "Pending"),
            record(uuid: "mine", status: "Acknowledged")
        ]
        // The specific queued command (mine) is acknowledged even though another enable record is pending.
        XCTAssertEqual(evaluator.evaluateCommand(records: records, enableCommandID: "mine"), .confirmed)
    }

    // MARK: - Report summary (honest, signals never collapsed)

    func test_summary_failed_reportsCommandFailure() {
        let r = SupportRemoteSupportReadinessReport(
            commandReadiness: .failed(reason: "device offline"),
            reachability: .unknown,
            checkedAt: Date(timeIntervalSince1970: 0)
        )
        XCTAssertTrue(r.summary.lowercased().contains("failed"))
        XCTAssertTrue(r.summary.contains("device offline"))
    }

    func test_summary_confirmedButUnreachable_invitesAttempt_notFailure() {
        let r = SupportRemoteSupportReadinessReport(
            commandReadiness: .confirmed,
            reachability: .unreachable,
            checkedAt: Date(timeIntervalSince1970: 0)
        )
        XCTAssertFalse(r.summary.lowercased().contains("command failed"))
        XCTAssertTrue(r.summary.lowercased().contains("attempt"))
    }

    func test_summary_pending_saysNotAppliedYet() {
        let r = SupportRemoteSupportReadinessReport(
            commandReadiness: .pending,
            reachability: .unknown,
            checkedAt: Date(timeIntervalSince1970: 0)
        )
        XCTAssertTrue(r.summary.lowercased().contains("hasn’t applied")
            || r.summary.lowercased().contains("hasn't applied")
            || r.summary.lowercased().contains("queued"))
    }

    func test_reachabilityLabels_areDistinct() {
        XCTAssertNotEqual(SupportRemoteSupportReachability.reachable.label,
                          SupportRemoteSupportReachability.unreachable.label)
        XCTAssertNotEqual(SupportRemoteSupportReachability.unreachable.label,
                          SupportRemoteSupportReachability.unknown.label)
    }
}

//endofline
