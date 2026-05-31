import Foundation
import Combine
import UniformTypeIdentifiers

/// The view model for `DiagnosticsView`.
///
/// Owns the data layer — reads events from the diagnostics reporter, prepares
/// byte payloads for export, invokes token-privilege introspection, clears
/// logs. Does NOT own `.fileExporter` presentation state; the View owns that
/// in pure `@State` so the exporter's parameters are stable at present time
/// and there is no cross-actor binding in the presentation path.
///
/// Simplified in v3.10.x: the diagnostics reporter is now backed by Apple's
/// unified logging system (`os.Logger` + `OSLogStore`) rather than a pair of
/// hand-rolled NDJSON files. All the file-URL plumbing this view model used
/// to expose (`persistentErrorLogFileURL`, `telemetryLogFileURL`, the
/// `prepareErrorLogExport()` / `prepareTelemetryLogExport()` methods) is
/// gone — there are no files to point at. The JSON and Markdown export
/// methods carry every event the user would have pulled from those files.
///
/// Runs on `@MainActor` so all `@Published` updates happen on the main thread.
@MainActor
final class DiagnosticsViewModel: ObservableObject {
    /// A prepared export payload ready to be handed to the View's `.fileExporter`.
    /// Returned by the two `prepare*Export()` methods — NOT held as state on
    /// this view model. The View receives it synchronously after the async
    /// prepare call, places it in its own `@State`, and triggers presentation.
    struct PreparedExport {
        let data: Data
        let filename: String
        let contentType: UTType
        /// Short human-readable label for the completion status message.
        let description: String
    }

    @Published private(set) var entries: [DiagnosticEvent] = []
    @Published private(set) var persistentLogFileURL: URL?
    @Published var statusMessage: String?
    @Published var errorMessage: String?
    @Published private(set) var tokenPrivileges: [String] = []
    @Published private(set) var tokenPrivilegesCheckedAt: Date?
    @Published private(set) var isCheckingTokenPrivileges = false

    private let diagnosticsReporter: any DiagnosticsReporting
    private let apiGateway: JamfAPIGateway?

    init(diagnosticsReporter: any DiagnosticsReporting, apiGateway: JamfAPIGateway? = nil) {
        self.diagnosticsReporter = diagnosticsReporter
        self.apiGateway = apiGateway
    }

    /// Reloads the event list from the diagnostics reporter and
    /// refreshes the cached persistent-log file URL (in case the
    /// diagnostics directory has been recreated since last load).
    func refresh() async {
        entries = await diagnosticsReporter.currentEvents()
        persistentLogFileURL = await diagnosticsReporter.persistentLogFileURL()
    }

    /// Renders the merged diagnostics as pretty-printed JSON bytes and returns
    /// a `PreparedExport` the View can hand to `.fileExporter`. Returns `nil`
    /// on failure; the `errorMessage` property is set with the reason.
    func prepareJSONExport() async -> PreparedExport? {
        do {
            let data = try await diagnosticsReporter.renderJSONReportData()
            let filename = await diagnosticsReporter.suggestedExportFileName(extension: "json")
            entries = await diagnosticsReporter.currentEvents()
            errorMessage = nil
            return PreparedExport(data: data, filename: filename, contentType: .json, description: "JSON export")
        } catch {
            statusMessage = nil
            errorMessage = "Failed to render diagnostics JSON: \(error.localizedDescription)"
            return nil
        }
    }

    /// Renders the merged diagnostics as a UTF-8 Markdown report.
    func prepareMarkdownExport() async -> PreparedExport? {
        do {
            let data = try await diagnosticsReporter.renderMarkdownReportData()
            let filename = await diagnosticsReporter.suggestedExportFileName(extension: "md")
            entries = await diagnosticsReporter.currentEvents()
            errorMessage = nil
            return PreparedExport(data: data, filename: filename, contentType: .plainText, description: "Markdown export")
        } catch {
            statusMessage = nil
            errorMessage = "Failed to render diagnostics Markdown: \(error.localizedDescription)"
            return nil
        }
    }

    /// Called by the View after its `.fileExporter` completes. The View owns
    /// the pending-export state; this call lets the VM record a completion
    /// status or error message.
    func recordExportCompletion(result: Result<URL, Error>, description: String) {
        switch result {
        case .success(let url):
            statusMessage = "Saved \(description) to \(url.lastPathComponent)."
            errorMessage = nil
        case .failure(let error):
            if (error as? CocoaError)?.code == .userCancelled {
                return
            }
            statusMessage = nil
            errorMessage = "Failed to save \(description): \(error.localizedDescription)"
        }
    }

    /// Invalidates the cached auth token and queries `GET /api/v1/auth` to report
    /// the privileges granted to the current API client.
    func checkTokenPrivileges() async {
        guard let apiGateway else {
            errorMessage = "Token privilege check is unavailable (no API gateway configured)."
            return
        }

        isCheckingTokenPrivileges = true
        defer { isCheckingTokenPrivileges = false }

        do {
            let privileges = try await apiGateway.fetchTokenAuthorizations()
            tokenPrivileges = privileges
            tokenPrivilegesCheckedAt = Date()
            errorMessage = nil
            statusMessage = privileges.isEmpty
                ? "Token returned no privileges. The server may not expose the authorizations array."
                : "Token reports \(privileges.count) privileges."
            entries = await diagnosticsReporter.currentEvents()
        } catch {
            statusMessage = nil
            errorMessage = "Failed to fetch token privileges: \(error.localizedDescription)"
        }
    }

    var canCheckTokenPrivileges: Bool {
        apiGateway != nil
    }

    /// Clears both the in-memory buffer AND the persistent NDJSON log
    /// file (including rotated generations). Apple's unified-log
    /// entries remain accessible via `log show --subsystem …` for
    /// forensic analysis; only the app-owned log is removed.
    func clearLog() async {
        await diagnosticsReporter.clear()
        statusMessage = "Diagnostics cleared: in-memory buffer emptied and on-disk log deleted. Unified-log entries (visible via `log show --subsystem com.ravenforge.forsetti.diagnostics`) are unaffected."
        errorMessage = nil
        await refresh()
    }
}

//endofline
