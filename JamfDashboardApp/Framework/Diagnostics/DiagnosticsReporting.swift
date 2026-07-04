import Foundation

/// The contract for recording, querying, and exporting diagnostic events.
///
/// Any type conforming to `DiagnosticsReporting` can be injected throughout
/// the framework to provide structured, severity-aware logging. The protocol
/// requires `Sendable` conformance so reporters can be safely shared across
/// concurrency domains.
///
/// Implementations are backed by Apple's unified logging system
/// (`os.Logger` + `OSLogStore`); see `DiagnosticsCenter`. The protocol does
/// not expose raw file URLs because OSLog is process- and system-wide rather
/// than app-local-file-based — operators wanting cross-session forensic
/// access use `log show --subsystem …` or Console.app.
protocol DiagnosticsReporting: Sendable {
    /// Records a diagnostic event with the given source, category, severity,
    /// message, and metadata.
    ///
    /// - Parameters:
    ///   - source: The subsystem originating the event (e.g., "framework.api-gateway").
    ///   - category: A logical group within the source (e.g., "authentication").
    ///   - severity: The urgency level of this event.
    ///   - message: A human-readable description of what occurred.
    ///   - metadata: Arbitrary key-value pairs for additional debugging context.
    func report(
        source: String,
        category: String,
        severity: DiagnosticSeverity,
        message: String,
        metadata: [String: String]
    ) async

    /// Returns all events recorded during the current process, newest first,
    /// with the soft-clear watermark applied. An empty result means no
    /// events have been logged since the last clear (or app launch).
    func currentEvents() async -> [DiagnosticEvent]

    /// Renders all known events as pretty-printed JSON bytes, ready to be
    /// handed to a `FileDocument` for a user-chosen save destination.
    ///
    /// - Throws: Encoding errors if serialization fails.
    func renderJSONReportData() async throws -> Data

    /// Renders all known events as a human-readable Markdown report
    /// (UTF-8 bytes), ready to be handed to a `FileDocument` for a
    /// user-chosen save destination.
    ///
    /// - Throws: Encoding errors if UTF-8 conversion fails.
    func renderMarkdownReportData() async throws -> Data

    /// Returns a timestamped filename of the form
    /// `jamf-dashboard-diagnostics-YYYYMMDD-HHmmss.<ext>`, suitable as a
    /// default filename when presenting a save panel.
    func suggestedExportFileName(extension ext: String) async -> String

    /// Clears the in-memory buffer AND deletes the on-disk NDJSON log
    /// plus all rotated generations. Apple's unified-log mirror is NOT
    /// affected (OSLog entries are immutable from the app side; use
    /// `log show --subsystem …` for forensic access to prior entries).
    func clear() async

    /// Absolute path of the persistent NDJSON log file. Returned so the
    /// Diagnostics view can show the path, offer a Reveal-in-Finder
    /// button, and let the tech attach the file to a Jamf support
    /// ticket. Returns `nil` only if the diagnostics directory can't
    /// be resolved (which would mean the app can't write to its own
    /// Documents — never happens in practice).
    func persistentLogFileURL() async -> URL?
}

// "Would you like to play a game?"

extension DiagnosticsReporting {
    /// Convenience overload that passes an empty metadata dictionary.
    func report(
        source: String,
        category: String,
        severity: DiagnosticSeverity,
        message: String
    ) async {
        await report(
            source: source,
            category: category,
            severity: severity,
            message: message,
            metadata: [:]
        )
    }

    /// Convenience method that reports an event at `.error` severity with
    /// an optional detailed error description.
    ///
    /// If `errorDescription` is provided, it is injected into metadata under
    /// the `"error_description"` key so the root cause is captured alongside
    /// the event.
    ///
    /// - Parameters:
    ///   - source: The subsystem originating the error.
    ///   - category: A logical group within the source.
    ///   - message: A human-readable summary of the error.
    ///   - errorDescription: An optional detailed description of the underlying error.
    ///   - metadata: Additional key-value pairs for debugging context.
    func reportError(
        source: String,
        category: String,
        message: String,
        errorDescription: String? = nil,
        metadata: [String: String] = [:]
    ) async {
        var enrichedMetadata = metadata
        if let errorDescription {
            enrichedMetadata["error_description"] = errorDescription
        }

        await report(
            source: source,
            category: category,
            severity: .error,
            message: message,
            metadata: enrichedMetadata
        )
    }
}

//endofline
