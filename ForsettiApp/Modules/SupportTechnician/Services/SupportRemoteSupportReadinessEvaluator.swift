import Foundation

/// Pure, deterministic interpretation of Jamf MDM command history into a Remote Support command
/// readiness verdict. Has one responsibility and is independently testable — it performs no
/// networking and parses no raw payloads (the API service already produced `SupportMDMCommandRecord`s).
///
/// It reuses `SupportMDMCommandRecord.bucket`, so the tenant-status normalization (`Acknowledged`,
/// `Pending`, `Error - …`, `NotNow`, classic `Completed`/`Failed`, retry-count suffixes) is shared
/// with the Command History frame rather than re-implemented here.
nonisolated struct SupportRemoteSupportReadinessEvaluator {

    /// The MDM command type whose status indicates Remote Management has been enabled.
    static let enableCommandType = "ENABLE_REMOTE_DESKTOP"

    /// Evaluates the readiness of the Enable Remote Management command.
    ///
    /// - Parameters:
    ///   - records: command history records (from `GET api/v2/mdm/commands` via the gateway).
    ///   - enableCommandID: the queued command's UUID, when known. Matched first so a specific
    ///     command's status is honored even if newer commands of other types exist.
    /// - Returns: a `SupportRemoteSupportCommandReadiness` verdict, defaulting to `.unknown` when
    ///   no relevant record is found (an empty/denied history is uncertainty, not failure).
    func evaluateCommand(
        records: [SupportMDMCommandRecord],
        enableCommandID: String?
    ) -> SupportRemoteSupportCommandReadiness {
        let record = locate(records: records, enableCommandID: enableCommandID)
        guard let record else { return .unknown }

        switch record.bucket {
        case .completed:
            return .confirmed
        case .pending, .notNow:
            return .pending
        case .failed:
            let reason = record.errorReasons.first
                ?? (record.status.isEmpty ? "device reported an error" : record.status)
            return .failed(reason: reason)
        case .other:
            return .unknown
        }
    }

    /// Finds the most relevant enable-command record: an exact UUID match wins; otherwise the
    /// first `ENABLE_REMOTE_DESKTOP` record (callers fetch sorted `dateSent:desc`, so "first" is
    /// the newest — but the verdict does not rely on ordering for correctness).
    private func locate(
        records: [SupportMDMCommandRecord],
        enableCommandID: String?
    ) -> SupportMDMCommandRecord? {
        if let id = enableCommandID?.trimmingCharacters(in: .whitespacesAndNewlines),
           id.isEmpty == false,
           let match = records.first(where: { $0.uuid == id }) {
            return match
        }
        let wanted = Self.enableCommandType.uppercased()
        return records.first { $0.commandType.uppercased() == wanted }
    }
}

//endofline
