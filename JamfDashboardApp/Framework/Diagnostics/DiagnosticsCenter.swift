import Foundation
import os


/// The central hub for recording and exporting diagnostic events.
///
/// Three-tier persistence strategy:
///
/// 1. **In-memory ring buffer** (2 000 events) — the UI reads this for
///    instant list rendering; JSON and Markdown exports serialize from
///    here. Bounded so memory stays flat on long-running sessions.
/// 2. **On-disk NDJSON log** (`jamf-dashboard-diagnostics.ndjson` under
///    the app's Documents/JamfDashboardDiagnostics directory) —
///    every reported event is appended as a single JSON object on its
///    own line. Survives app quits and crashes. On first access the
///    log is loaded into the in-memory buffer so history from prior
///    sessions is visible. Size-rotated at 10 MB with three generations
///    kept so a very busy session doesn't grow the log unbounded.
/// 3. **Unified log mirror** (`os.Logger`) — same event written to
///    Apple's unified log with `privacy: .public`, so Console.app and
///    `log show --subsystem …` can see entries without the app running.
///    Not the authoritative source — just visibility.
///
/// The in-memory-only design that shipped briefly between v3.10.1 and
/// v3.12.x was a regression: quitting the app threw away every
/// recorded error, and Jamf Pro API 403s that the technician would
/// otherwise forward to Jamf support were lost. The NDJSON file is
/// the fix — errors persist across relaunches.
actor DiagnosticsCenter: DiagnosticsReporting {
    /// Subsystem identifier for every `Logger` instance.
    nonisolated private static let subsystem = "com.forsetti.jamfdashboard.diagnostics"

    /// Persistent log filename. Single file, all severities — the
    /// severity field in each line identifies info / warning / error.
    nonisolated private static let logFileName = "jamf-dashboard-diagnostics.ndjson"

    /// In-memory ring buffer. Caps to `maxInMemoryEvents` via
    /// oldest-first eviction.
    private var events: [DiagnosticEvent] = []

    /// Per-category `Logger` cache.
    private var loggersByCategory: [String: Logger] = [:]

    /// Set after `loadFromDisk()` runs once during the actor's lifetime.
    /// Prevents re-reading the file on every `currentEvents()` call.
    private var didLoadFromDisk = false

    /// Running count of persist-to-disk write failures. Exposed via
    /// `mergedEventsForRead` as a synthetic warning so silent log
    /// loss becomes visible.
    private var persistFailureCount: Int = 0

    /// Most recent persist-failure description, surfaced alongside
    /// `persistFailureCount`.
    private var lastPersistFailureDescription: String?

    /// In-memory bound.
    nonisolated private let maxInMemoryEvents = 2000

    /// Hard size cap for the persistent log. When the file exceeds this,
    /// the oldest whole NDJSON lines are pruned away (see `pruneIfNeeded`)
    /// so the on-disk log is a single self-pruning file ≤ 5 MB.
    nonisolated private let maxLogFileBytes: UInt64 = 5 * 1024 * 1024

    /// Size the log is pruned back down to once it exceeds the cap — 70%
    /// of the cap, so roughly the oldest 30% is dropped each prune. The
    /// headroom means pruning runs about once per ~1.5 MB of new events
    /// instead of rewriting the whole file on every append at the cap.
    nonisolated private let pruneTargetBytes: UInt64 = (5 * 1024 * 1024) * 7 / 10

    /// Generations written by the pre-5 MB rotation scheme. Retained only
    /// so an existing install's `.1`/`.2`/`.3` files are migrated on first
    /// load and removed by `clear()`.
    nonisolated private let legacyRotatedGenerations = 3

    /// JSON encoder/decoder configured for NDJSON round-trip.
    nonisolated private let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.outputFormatting = [.sortedKeys]
        e.dateEncodingStrategy = .iso8601
        return e
    }()
    nonisolated private let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()

    private let fileManager = FileManager.default

    // MARK: - Public API

    func report(
        source: String,
        category: String,
        severity: DiagnosticSeverity,
        message: String,
        metadata: [String: String]
    ) async {
        loadFromDiskIfNeeded()

        let event = DiagnosticEvent(
            source: source,
            category: category,
            severity: severity,
            message: message,
            metadata: metadata
        )

        // 1. In-memory ring buffer.
        events.append(event)
        if events.count > maxInMemoryEvents {
            events.removeFirst(events.count - maxInMemoryEvents)
        }

        // 2. Append to on-disk NDJSON. Best-effort — never crash the
        // app for a log write. Failures are counted and surfaced.
        persistEvent(event)

        // 3. Mirror to os.Logger for Console.app / `log show`.
        let logger = loggerFor(category: category)
        let metadataTail = metadata.isEmpty
            ? ""
            : " [" + metadata.keys.sorted().map { "\($0)=\(metadata[$0] ?? "")" }.joined(separator: " ") + "]"
        let line = "\(source) — \(message)\(metadataTail)"
        switch severity {
        case .info:    logger.info("\(line, privacy: .public)")
        case .warning: logger.notice("\(line, privacy: .public)")
        case .error:   logger.error("\(line, privacy: .public)")
        }
    }

    func currentEvents() async -> [DiagnosticEvent] {
        loadFromDiskIfNeeded()
        return mergedEventsForRead().sorted { $0.timestamp > $1.timestamp }
    }

    func renderJSONReportData() async throws -> Data {
        loadFromDiskIfNeeded()
        let sorted = mergedEventsForRead().sorted { $0.timestamp < $1.timestamp }
        let payload = DiagnosticExportPayload(
            appName: "Jamf Dashboard",
            exportedAt: Date(),
            eventCount: sorted.count,
            events: sorted
        )
        let exportEncoder = JSONEncoder()
        exportEncoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        exportEncoder.dateEncodingStrategy = .iso8601
        return try exportEncoder.encode(payload)
    }

    func renderMarkdownReportData() async throws -> Data {
        loadFromDiskIfNeeded()
        let sorted = mergedEventsForRead().sorted { $0.timestamp < $1.timestamp }
        let markdown = renderMarkdownReport(events: sorted, exportedAt: Date())
        guard let data = markdown.data(using: .utf8) else {
            throw CocoaError(.fileWriteInapplicableStringEncoding)
        }
        return data
    }

    func suggestedExportFileName(extension ext: String) async -> String {
        exportFileName(extension: ext)
    }

    /// Clears the in-memory buffer AND deletes the on-disk log +
    /// rotated copies. Unified-log entries aren't touched — they remain
    /// accessible via `log show --subsystem …` for forensic analysis.
    func clear() async {
        events.removeAll()

        // Delete the current log + every rotated generation. Silent on
        // failure — clearing is best-effort.
        if let dir = try? diagnosticsDirectoryURL(createIfMissing: false) {
            for generation in 0...legacyRotatedGenerations {
                let url = dir.appending(path: rotatedFileName(forGeneration: generation))
                try? fileManager.removeItem(at: url)
            }
        }

        // Reset counters too — a cleared view shouldn't carry stale
        // failure counts.
        persistFailureCount = 0
        lastPersistFailureDescription = nil
        didLoadFromDisk = true
    }

    /// Absolute URL of the persistent log file. Exposed so the View
    /// can show the path (and let the tech reveal it in Finder).
    func persistentLogFileURL() async -> URL? {
        try? diagnosticsDirectoryURL(createIfMissing: true)
            .appending(path: Self.logFileName)
    }

    // MARK: - In-Memory + On-Disk Coordination

    /// Returns the current in-memory buffer plus, if applicable, a
    /// synthetic warning event documenting persist-failure count. The
    /// synthetic event is appended only to the returned copy — it is
    /// NOT written to disk, so the counter can keep growing accurately
    /// and the warning is always fresh at read time.
    private func mergedEventsForRead() -> [DiagnosticEvent] {
        var result = events

        if persistFailureCount > 0 {
            let warning = DiagnosticEvent(
                source: "framework.diagnostics-center",
                category: "persist-failure",
                severity: .warning,
                message: "\(persistFailureCount) diagnostic event\(persistFailureCount == 1 ? "" : "s") could not be persisted to disk since launch. In-memory diagnostics are unaffected.",
                metadata: [
                    "persist_failure_count": String(persistFailureCount),
                    "last_failure": lastPersistFailureDescription ?? "unknown"
                ]
            )
            result.append(warning)
        }

        return result
    }

    /// Reads the current log file + each rotated generation (oldest
    /// first so replay order matches event timestamp order) into the
    /// in-memory buffer. Idempotent — `didLoadFromDisk` gates the work.
    private func loadFromDiskIfNeeded() {
        guard didLoadFromDisk == false else { return }
        didLoadFromDisk = true

        guard let dir = try? diagnosticsDirectoryURL(createIfMissing: false) else {
            return
        }

        let currentURL = dir.appending(path: Self.logFileName)
        var loaded: [DiagnosticEvent] = []

        // One-time migration from the old rotation scheme: fold any
        // `.1`/`.2`/`.3` generations (oldest → newest) into the in-memory
        // buffer, then delete them so on-disk history is a single file
        // bounded by the 5 MB cap.
        for generation in (1...legacyRotatedGenerations).reversed() {
            let url = dir.appending(path: rotatedFileName(forGeneration: generation))
            loaded.append(contentsOf: readNDJSON(at: url))
            try? fileManager.removeItem(at: url)
        }
        loaded.append(contentsOf: readNDJSON(at: currentURL))

        // Cap to the in-memory bound, keeping the LATEST entries.
        if loaded.count > maxInMemoryEvents {
            loaded.removeFirst(loaded.count - maxInMemoryEvents)
        }

        events = loaded

        // A legacy current file may exceed the new 5 MB cap; bring it
        // under immediately rather than waiting for the next event.
        pruneIfNeeded(logFileURL: currentURL)
    }

    /// Reads an NDJSON file into `[DiagnosticEvent]`. Malformed lines
    /// are skipped silently (they are rare and the file is primarily
    /// for human review; a broken line shouldn't lose the others).
    private func readNDJSON(at url: URL) -> [DiagnosticEvent] {
        guard fileManager.fileExists(atPath: url.path),
              let data = try? Data(contentsOf: url),
              let text = String(data: data, encoding: .utf8)
        else {
            return []
        }

        var decoded: [DiagnosticEvent] = []
        for line in text.split(separator: "\n", omittingEmptySubsequences: true) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard trimmed.isEmpty == false,
                  let lineData = trimmed.data(using: .utf8),
                  let event = try? decoder.decode(DiagnosticEvent.self, from: lineData)
            else {
                continue
            }
            decoded.append(event)
        }
        return decoded
    }

    /// Appends a single event to the on-disk log as one NDJSON line.
    /// Best-effort: a failure increments `persistFailureCount` and
    /// stores the last error description but does not throw.
    private func persistEvent(_ event: DiagnosticEvent) {
        do {
            let dir = try diagnosticsDirectoryURL(createIfMissing: true)
            let url = dir.appending(path: Self.logFileName)

            var data = try encoder.encode(event)
            data.append(0x0A) // newline → valid NDJSON

            if fileManager.fileExists(atPath: url.path) {
                let handle = try FileHandle(forWritingTo: url)
                defer { try? handle.close() }
                try handle.seekToEnd()
                try handle.write(contentsOf: data)
            } else {
                try data.write(to: url, options: [.atomic])
            }

            pruneIfNeeded(logFileURL: url)
        } catch {
            persistFailureCount += 1
            lastPersistFailureDescription = error.localizedDescription
        }
    }

    /// Size-based self-pruning. When the log exceeds `maxLogFileBytes`,
    /// the oldest whole NDJSON lines are dropped until the surviving tail
    /// is back within `pruneTargetBytes` (≈70% of the cap), then that tail
    /// is rewritten atomically. Keeps the log a single self-pruning file.
    ///
    /// Best-effort; failures are silent so a full disk doesn't crash the app.
    private func pruneIfNeeded(logFileURL: URL) {
        guard let attributes = try? fileManager.attributesOfItem(atPath: logFileURL.path),
              let size = attributes[.size] as? NSNumber,
              size.uint64Value > maxLogFileBytes,
              let data = try? Data(contentsOf: logFileURL)
        else {
            return
        }

        let pruned = Self.prunedTail(of: data, toAtMost: Int(pruneTargetBytes))
        // Nothing droppable (e.g. one oversized line with no usable
        // boundary) → leave the file as-is rather than rewrite it whole.
        guard pruned.count < data.count else { return }
        try? pruned.write(to: logFileURL, options: [.atomic])
    }

    /// Returns the suffix of `data` that fits within `target` bytes, cut on
    /// an NDJSON line boundary so the oldest *whole* lines are dropped and
    /// no partial leading line remains. Returns `data` unchanged when it
    /// already fits, or when it is a single line with no usable boundary.
    ///
    /// Pure and `nonisolated` so it is unit-testable in isolation.
    nonisolated static func prunedTail(of data: Data, toAtMost target: Int) -> Data {
        guard target > 0, data.count > target else { return data }

        let bytes = [UInt8](data)
        // Earliest byte we could keep and still fit within `target`.
        var cut = bytes.count - target
        // Advance to the next line boundary so only whole lines are dropped.
        while cut < bytes.count, bytes[cut] != 0x0A {
            cut += 1
        }
        cut += 1  // step past the newline; the kept tail starts after it.
        guard cut < bytes.count else { return data }  // no clean boundary → leave as-is
        return Data(bytes[cut...])
    }

    /// Generation 0 means the current log file; 1+ is a rotated copy from
    /// the legacy rotation scheme (used only for migration/cleanup now).
    nonisolated private func rotatedFileName(forGeneration generation: Int) -> String {
        generation == 0 ? Self.logFileName : "\(Self.logFileName).\(generation)"
    }

    // MARK: - Directory Resolution

    /// Returns the directory that holds the persistent log file.
    /// Under the macOS App Sandbox this resolves to
    /// `~/Library/Containers/<bundle-id>/Data/Documents/JamfDashboardDiagnostics/`.
    /// Falls back to the system temp directory if Documents is
    /// unavailable (shouldn't happen on any real device, but keeps
    /// the diagnostics reporter crash-free regardless).
    private func diagnosticsDirectoryURL(createIfMissing: Bool) throws -> URL {
        let base = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        let dir = base.appending(path: "JamfDashboardDiagnostics", directoryHint: .isDirectory)
        if createIfMissing, fileManager.fileExists(atPath: dir.path) == false {
            try fileManager.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        return dir
    }

    // MARK: - Helpers

    private func loggerFor(category: String) -> Logger {
        if let logger = loggersByCategory[category] {
            return logger
        }
        let logger = Logger(subsystem: Self.subsystem, category: category)
        loggersByCategory[category] = logger
        return logger
    }

    private struct DiagnosticExportPayload: Codable {
        let appName: String
        let exportedAt: Date
        let eventCount: Int
        let events: [DiagnosticEvent]
    }

    private nonisolated func exportFileName(
        referenceDate: Date = Date(),
        extension fileExtension: String
    ) -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        return "jamf-dashboard-diagnostics-\(formatter.string(from: referenceDate)).\(fileExtension)"
    }

    private nonisolated func renderMarkdownReport(
        events: [DiagnosticEvent],
        exportedAt: Date
    ) -> String {
        let isoFormatter = ISO8601DateFormatter()
        isoFormatter.formatOptions = [.withInternetDateTime]

        let errorCount = events.filter { $0.severity == .error }.count
        let warningCount = events.filter { $0.severity == .warning }.count
        let infoCount = events.filter { $0.severity == .info }.count

        var lines: [String] = []
        lines.append("# Jamf Dashboard Diagnostics")
        lines.append("")
        lines.append("- **Exported:** \(isoFormatter.string(from: exportedAt))")
        lines.append("- **Total events:** \(events.count)")
        lines.append("- **Errors:** \(errorCount)")
        lines.append("- **Warnings:** \(warningCount)")
        lines.append("- **Info:** \(infoCount)")
        lines.append("")

        if events.isEmpty {
            lines.append("_No diagnostic events recorded._")
            lines.append("")
            return lines.joined(separator: "\n")
        }

        let highlights = events.filter { $0.severity == .error || $0.severity == .warning }
        if highlights.isEmpty == false {
            lines.append("## Highlights")
            lines.append("")
            lines.append("Errors and warnings, most recent first:")
            lines.append("")
            for event in highlights.reversed() {
                lines.append(contentsOf: markdownEntryLines(for: event, isoFormatter: isoFormatter))
            }
        }

        lines.append("## Event Log")
        lines.append("")
        lines.append("Full chronological log (oldest first):")
        lines.append("")
        for event in events {
            lines.append(contentsOf: markdownEntryLines(for: event, isoFormatter: isoFormatter))
        }

        return lines.joined(separator: "\n")
    }

    private nonisolated func markdownEntryLines(
        for event: DiagnosticEvent,
        isoFormatter: ISO8601DateFormatter
    ) -> [String] {
        var lines: [String] = []
        let badge = event.severity.rawValue.uppercased()
        lines.append("### [\(badge)] \(isoFormatter.string(from: event.timestamp)) — \(event.source) / \(event.category)")
        lines.append("")
        lines.append("> \(escapeMarkdown(event.message))")
        lines.append("")

        if event.metadata.isEmpty == false {
            for key in event.metadata.keys.sorted() {
                let value = event.metadata[key] ?? ""
                lines.append("- **\(escapeMarkdown(key)):** \(escapeMarkdown(value))")
            }
            lines.append("")
        }

        return lines
    }

    private nonisolated func escapeMarkdown(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\r\n", with: " ")
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "|", with: "\\|")
            .replacingOccurrences(of: "`", with: "\\`")
    }
}

//endofline
