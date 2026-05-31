import XCTest
@testable import Forsetti

/// Regression coverage for the Export JSON / Markdown path and for
/// the disk-persistence invariants.
///
/// Each test creates a fresh `DiagnosticsCenter` and immediately calls
/// `clear()` before recording events — the center loads any existing
/// NDJSON log from disk on first access, so without a clean start
/// tests would observe events from previous runs. `clear()` deletes
/// the file outright, giving each test a known-empty baseline.
final class DiagnosticsCenterExportTests: XCTestCase {

    // MARK: - currentEvents round-trip

    func test_reportThenCurrentEvents_returnsReportedEvent() async {
        let center = DiagnosticsCenter()
        await center.clear()

        await center.report(
            source: "tests.export",
            category: "smoke",
            severity: .info,
            message: "hello diagnostics",
            metadata: ["k1": "v1"]
        )

        let events = await center.currentEvents()
        XCTAssertEqual(events.count, 1)
        XCTAssertEqual(events.first?.source, "tests.export")
        XCTAssertEqual(events.first?.message, "hello diagnostics")
        XCTAssertEqual(events.first?.metadata["k1"], "v1")
    }

    // MARK: - Render JSON / Markdown

    func test_renderJSONReportData_containsReportedEvents() async throws {
        let center = DiagnosticsCenter()
        await center.clear()

        await center.report(
            source: "tests.export",
            category: "json",
            severity: .warning,
            message: "a payload to round-trip",
            metadata: ["ticket": "JAMF-123"]
        )

        let jsonBytes = try await center.renderJSONReportData()
        XCTAssertFalse(jsonBytes.isEmpty)

        guard let decoded = try JSONSerialization.jsonObject(with: jsonBytes) as? [String: Any] else {
            XCTFail("Rendered JSON is not an object")
            return
        }
        XCTAssertEqual(decoded["appName"] as? String, "Forsetti")
        XCTAssertEqual(decoded["eventCount"] as? Int, 1)

        guard let events = decoded["events"] as? [[String: Any]], events.count == 1 else {
            XCTFail("Expected exactly one event in the rendered JSON")
            return
        }
        XCTAssertEqual(events[0]["source"] as? String, "tests.export")
        XCTAssertEqual(events[0]["severity"] as? String, "warning")
        XCTAssertEqual(events[0]["message"] as? String, "a payload to round-trip")
        XCTAssertEqual((events[0]["metadata"] as? [String: String])?["ticket"], "JAMF-123")
    }

    func test_renderMarkdownReportData_mentionsReportedEvent() async throws {
        let center = DiagnosticsCenter()
        await center.clear()

        await center.report(
            source: "tests.markdown",
            category: "rendering",
            severity: .error,
            message: "boom — something broke",
            metadata: ["code": "E42"]
        )

        let markdownBytes = try await center.renderMarkdownReportData()
        XCTAssertFalse(markdownBytes.isEmpty)

        guard let markdown = String(data: markdownBytes, encoding: .utf8) else {
            XCTFail("Markdown bytes aren't valid UTF-8")
            return
        }

        XCTAssertTrue(markdown.contains("# Forsetti Diagnostics"))
        XCTAssertTrue(markdown.contains("tests.markdown"))
        XCTAssertTrue(markdown.contains("boom — something broke"))
        XCTAssertTrue(markdown.contains("E42"))
        XCTAssertTrue(markdown.contains("[ERROR]"))
    }

    func test_reportRedactsSensitiveMetadataBeforeExport() async throws {
        let center = DiagnosticsCenter()
        await center.clear()

        await center.report(
            source: "tests.redaction",
            category: "security",
            severity: .warning,
            message: "queued command",
            metadata: [
                "management_id": "uuid-secret",
                "payload_preview": #"{"pin":"123456","clientManagementIds":["uuid-secret"]}"#,
                "ticket": "JAMF-456"
            ]
        )

        let events = await center.currentEvents()
        XCTAssertEqual(events.first?.metadata["management_id"], "<redacted>")
        XCTAssertEqual(events.first?.metadata["payload_preview"], "<redacted>")
        XCTAssertEqual(events.first?.metadata["ticket"], "JAMF-456")

        let jsonBytes = try await center.renderJSONReportData()
        let json = String(data: jsonBytes, encoding: .utf8) ?? ""
        XCTAssertFalse(json.contains("uuid-secret"))
        XCTAssertFalse(json.contains("123456"))
        XCTAssertTrue(json.contains("JAMF-456"))
    }

    func test_reportRedactsSensitiveMetadataValuesBeforeExport() async throws {
        let center = DiagnosticsCenter()
        await center.clear()

        await center.report(
            source: "tests.redaction",
            category: "security",
            severity: .warning,
            message: "queued command",
            metadata: [
                "endpoint": "api/v2/local-admin-password/123e4567-e89b-12d3-a456-426614174000/account/admin/rotate",
                "note": "Bearer super-secret-token",
                "sample": #"{"serialNumber":"C02ABC123XYZ"}"#,
                "ticket": "JAMF-789"
            ]
        )

        let events = await center.currentEvents()
        XCTAssertEqual(events.first?.metadata["endpoint"], "<redacted>")
        XCTAssertEqual(events.first?.metadata["note"], "<redacted>")
        XCTAssertEqual(events.first?.metadata["sample"], "<redacted>")
        XCTAssertEqual(events.first?.metadata["ticket"], "JAMF-789")

        let jsonBytes = try await center.renderJSONReportData()
        let json = String(data: jsonBytes, encoding: .utf8) ?? ""
        XCTAssertFalse(json.contains("123e4567-e89b-12d3-a456-426614174000"))
        XCTAssertFalse(json.contains("super-secret-token"))
        XCTAssertFalse(json.contains("C02ABC123XYZ"))
        XCTAssertTrue(json.contains("JAMF-789"))
    }

    // MARK: - Filename / clear

    func test_clear_drainsInMemoryBuffer() async {
        let center = DiagnosticsCenter()
        await center.clear()

        await center.report(source: "a", category: "b", severity: .info, message: "x", metadata: [:])
        await center.report(source: "a", category: "b", severity: .info, message: "y", metadata: [:])

        var events = await center.currentEvents()
        XCTAssertEqual(events.count, 2)

        await center.clear()

        events = await center.currentEvents()
        XCTAssertEqual(events.count, 0)
    }

    func test_suggestedExportFileName_hasCorrectPatternAndExtension() async {
        let center = DiagnosticsCenter()
        let name = await center.suggestedExportFileName(extension: "json")
        XCTAssertTrue(name.hasPrefix("forsetti-diagnostics-"))
        XCTAssertTrue(name.hasSuffix(".json"))

        let timestamp = name
            .replacingOccurrences(of: "forsetti-diagnostics-", with: "")
            .replacingOccurrences(of: ".json", with: "")
        XCTAssertEqual(timestamp.count, 15, "Expected YYYYMMDD-HHmmss, got \(timestamp)")
    }

    // MARK: - Disk persistence (the v3.12.x regression the user caught)

    /// Reported events must survive a fresh actor instance — i.e.,
    /// the app quitting and relaunching. The previous in-memory-only
    /// design lost every event on quit; a persistent NDJSON log on
    /// disk is the fix.
    func test_reportedEvents_persistAcrossFreshActorInstance() async {
        let firstCenter = DiagnosticsCenter()
        await firstCenter.clear()

        await firstCenter.report(
            source: "tests.persistence",
            category: "relaunch",
            severity: .error,
            message: "must survive quit",
            metadata: ["case": "1"]
        )
        await firstCenter.report(
            source: "tests.persistence",
            category: "relaunch",
            severity: .warning,
            message: "second event",
            metadata: ["case": "2"]
        )

        // Simulate app relaunch by dropping the first actor and
        // creating a new one that points at the same on-disk file.
        // No `clear()` here — we want to see the persisted events.
        let secondCenter = DiagnosticsCenter()
        let events = await secondCenter.currentEvents()

        XCTAssertEqual(events.count, 2, "Both reported events must load from disk on fresh actor")

        // Events come back sorted newest-first; verify payload fields.
        let byCase = Dictionary(uniqueKeysWithValues: events.map { ($0.metadata["case"] ?? "", $0) })
        XCTAssertEqual(byCase["1"]?.message, "must survive quit")
        XCTAssertEqual(byCase["1"]?.severity, .error)
        XCTAssertEqual(byCase["2"]?.message, "second event")
        XCTAssertEqual(byCase["2"]?.severity, .warning)
    }

    /// Clear must delete the on-disk log, so a fresh actor after
    /// clear() sees no historical events (not even persisted ones).
    func test_clear_deletesOnDiskLog() async {
        let firstCenter = DiagnosticsCenter()
        await firstCenter.clear()
        await firstCenter.report(source: "a", category: "b", severity: .error, message: "should vanish", metadata: [:])
        await firstCenter.clear()

        let secondCenter = DiagnosticsCenter()
        let events = await secondCenter.currentEvents()
        XCTAssertEqual(events.count, 0, "Cleared log must not resurrect on fresh actor")
    }

    /// `persistentLogFileURL()` must return a writable path that the
    /// technician can share or reveal in Finder. Returning nil would
    /// hide the log from the UI entirely, so the path must always
    /// resolve on a real device.
    func test_persistentLogFileURL_returnsAPathThatExistsAfterReport() async {
        let center = DiagnosticsCenter()
        await center.clear()
        await center.report(source: "a", category: "b", severity: .info, message: "write me", metadata: [:])

        guard let url = await center.persistentLogFileURL() else {
            XCTFail("persistentLogFileURL returned nil on a system where FileManager.default.urls works")
            return
        }

        XCTAssertTrue(url.path.hasSuffix("forsetti-diagnostics.ndjson"))
        XCTAssertTrue(
            FileManager.default.fileExists(atPath: url.path),
            "NDJSON file must exist on disk after a report"
        )

        // Content sanity check: the file should contain exactly one JSON
        // line that decodes to a DiagnosticEvent with our message.
        guard let contents = try? String(contentsOf: url, encoding: .utf8) else {
            XCTFail("NDJSON file isn't valid UTF-8")
            return
        }
        let lines = contents.split(separator: "\n", omittingEmptySubsequences: true)
        XCTAssertEqual(lines.count, 1, "Expected one NDJSON line, got \(lines.count)")
        XCTAssertTrue(contents.contains("\"message\":\"write me\""))
    }
}

//endofline
