import XCTest
@testable import ForsettiJamfProApp

/// Minimal conformer so the exporter can be tested without a domain model.
private struct StubShareable: ShareableRecord {
    let shareTitle: String
    let shareFields: [ShareField]
}

/// Verifies the `RecordMarkdown` formatter and temp-file writer.
final class RecordMarkdownTests: XCTestCase {

    func test_singleRecord_rendersHeadingAndTable() {
        let record = StubShareable(
            shareTitle: "Jane's iPad",
            shareFields: [
                ShareField(label: "Serial Number", value: "DMPABC123"),
                ShareField(label: "Email Address", value: "jane@example.com"),
            ]
        )
        XCTAssertEqual(RecordMarkdown.document(for: [record]), """
        ## Jane's iPad

        | Field | Value |
        | --- | --- |
        | Serial Number | DMPABC123 |
        | Email Address | jane@example.com |
        """)
    }

    func test_recordWithNoFields_rendersHeadingOnly() {
        let record = StubShareable(shareTitle: "Empty Device", shareFields: [])
        XCTAssertEqual(RecordMarkdown.document(for: [record]), "## Empty Device")
    }

    func test_multipleRecords_preserveOrderSeparatedByBlankLine() {
        let a = StubShareable(shareTitle: "A", shareFields: [ShareField(label: "K", value: "1")])
        let b = StubShareable(shareTitle: "B", shareFields: [ShareField(label: "K", value: "2")])
        XCTAssertEqual(RecordMarkdown.document(for: [a, b]), """
        ## A

        | Field | Value |
        | --- | --- |
        | K | 1 |

        ## B

        | Field | Value |
        | --- | --- |
        | K | 2 |
        """)
    }

    func test_pipeAndNewlineAreSanitized() {
        let record = StubShareable(
            shareTitle: "Dev",
            shareFields: [ShareField(label: "Note", value: "a|b\nc")]
        )
        XCTAssertTrue(RecordMarkdown.document(for: [record]).contains("| Note | a\\|b<br>c |"))
    }

    func test_temporaryFile_writesReadableMarkdown() throws {
        let record = StubShareable(shareTitle: "Dev", shareFields: [ShareField(label: "K", value: "V")])
        let url = try RecordMarkdown.temporaryFile(for: [record], fileName: "Devices")
        defer { try? FileManager.default.removeItem(at: url) }
        XCTAssertEqual(url.pathExtension, "md")
        XCTAssertEqual(try String(contentsOf: url, encoding: .utf8), RecordMarkdown.document(for: [record]))
    }
}

//endofline
