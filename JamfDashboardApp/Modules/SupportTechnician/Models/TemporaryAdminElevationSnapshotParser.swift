import Foundation

/// Pure parser that maps the five Computer Extension Attributes the Mac-side
/// scripts populate into a `TemporaryAdminElevationSnapshot`.
///
/// Kept free of networking and view state so it is synchronously unit-testable.
/// It never mutates anything and tolerates missing, malformed, or unknown
/// values — an offline or never-reported Mac yields a `.ready` snapshot rather
/// than an error.
nonisolated enum TemporaryAdminElevationSnapshotParser {

    /// Values the EA scripts emit when there is nothing to report. Treated as
    /// "absent" for user / run-id / date fields.
    private static let placeholderValues: Set<String> = ["not reported", "not_reported", ""]

    /// Parses a snapshot from a device detail's extension attributes.
    ///
    /// - Parameters:
    ///   - extensionAttributes: The reported EAs from the computer's inventory.
    ///   - names: The configured EA display names to match against.
    ///   - now: The reference time, injected for deterministic tests.
    static func parse(
        extensionAttributes: [SupportExtensionAttribute],
        names: TemporaryAdminExtensionAttributeNames,
        now: Date = Date()
    ) -> TemporaryAdminElevationSnapshot {
        let lookup = buildLookup(from: extensionAttributes)

        let rawStatus = value(for: names.status, in: lookup)
        let user = nonPlaceholderValue(for: names.user, in: lookup)
        let runId = nonPlaceholderValue(for: names.runId, in: lookup)
        let expiresAt = date(for: names.expiresAt, in: lookup)
        let lastChange = date(for: names.lastChange, in: lookup)

        let normalizedStatus = rawStatus?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased() ?? ""

        let state = mapState(
            normalizedStatus: normalizedStatus,
            rawStatus: rawStatus,
            user: user,
            expiresAt: expiresAt,
            runId: runId
        )

        // Preserve the raw value (e.g. "expired_pending_demotion") for audit and
        // diagnostics even when the mapped state collapses it onto `.elevated`.
        let preservedRaw: String?
        if let rawStatus,
           placeholderValues.contains(rawStatus.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()) == false {
            preservedRaw = rawStatus.trimmingCharacters(in: .whitespacesAndNewlines)
        } else {
            preservedRaw = nil
        }

        return TemporaryAdminElevationSnapshot(
            state: state,
            statusRawValue: preservedRaw,
            user: user,
            expiresAt: expiresAt,
            lastChange: lastChange,
            runId: runId
        )
    }

    // MARK: - Mapping

    private static func mapState(
        normalizedStatus: String,
        rawStatus: String?,
        user: String?,
        expiresAt: Date?,
        runId: String?
    ) -> TemporaryAdminElevationState {
        let reportedUser = user ?? "the signed-in user"

        switch normalizedStatus {
        case "", TemporaryAdminStatusValue.notReported, TemporaryAdminStatusValue.notRequested:
            return .ready
        case TemporaryAdminStatusValue.elevated, TemporaryAdminStatusValue.expiredPendingDemotion:
            // `expired_pending_demotion` means the timer lapsed but the demotion
            // daemon has not yet run, so the user is still a local admin. We
            // surface it as elevated (raw value preserved on the snapshot) until
            // the Mac confirms `demoted`.
            return .elevated(user: reportedUser, expiresAt: expiresAt, runId: runId)
        case TemporaryAdminStatusValue.alreadyAdmin:
            return .alreadyAdmin(user: reportedUser, runId: runId)
        case TemporaryAdminStatusValue.demoted:
            return .demoted(user: user, runId: runId)
        case TemporaryAdminStatusValue.failed:
            return .failed(message: "The Mac reported a failed temporary-admin state.")
        default:
            let raw = rawStatus?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "unknown"
            return .failed(message: "Unrecognized temporary-admin status reported by the Mac: \(raw)")
        }
    }

    // MARK: - Lookup helpers

    private static func buildLookup(from attributes: [SupportExtensionAttribute]) -> [String: String] {
        var lookup: [String: String] = [:]
        for attribute in attributes {
            let key = normalizeName(attribute.name)
            guard key.isEmpty == false else { continue }
            // First non-empty wins; keep an existing non-empty value over a later
            // empty duplicate.
            if let existing = lookup[key], existing.isEmpty == false { continue }
            lookup[key] = attribute.value
        }
        return lookup
    }

    private static func normalizeName(_ name: String) -> String {
        name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    private static func value(for name: String, in lookup: [String: String]) -> String? {
        let raw = lookup[normalizeName(name)]
        guard let raw else { return nil }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private static func nonPlaceholderValue(for name: String, in lookup: [String: String]) -> String? {
        guard let raw = value(for: name, in: lookup) else { return nil }
        return placeholderValues.contains(raw.lowercased()) ? nil : raw
    }

    private static func date(for name: String, in lookup: [String: String]) -> Date? {
        guard let raw = nonPlaceholderValue(for: name, in: lookup) else { return nil }
        return parseISO8601(raw)
    }

    /// Parses an ISO-8601 timestamp, tolerating both the fractional and
    /// non-fractional forms the Mac may emit. Returns nil for anything
    /// unparseable rather than throwing.
    private static func parseISO8601(_ string: String) -> Date? {
        let withFractional = ISO8601DateFormatter()
        withFractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = withFractional.date(from: string) { return date }

        let plain = ISO8601DateFormatter()
        plain.formatOptions = [.withInternetDateTime]
        return plain.date(from: string)
    }
}
