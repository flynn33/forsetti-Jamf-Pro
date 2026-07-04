# Copy Icons & Record Sharing — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add reusable, framework-level copy-to-clipboard icons and Markdown record sharing, wired into the Mobile Device Search module (detail-view copy icons + single-record share; results-view multi-select share; macOS Save).

**Architecture:** A thin framework layer — a `ShareableRecord` contract, a pure `RecordMarkdown` exporter, a `TextFileDocument` for saving, and two SwiftUI atoms (`CopyButton`, `SelectionCircle`). Sharing uses Apple's native `ShareLink`; macOS Save uses Apple's native `.fileExporter`. `MobileDeviceRecord` conforms to the contract; the module's two views adopt the atoms + native APIs.

**Tech Stack:** Swift, SwiftUI, Foundation, UniformTypeIdentifiers, XCTest. Xcode project `Jamf Dashboard.xcodeproj`, scheme `Jamf Dashboard`, targets `Jamf Dashboard` + `JamfDashboardAppTests`.

**Spec:** `docs/superpowers/specs/2026-06-22-mobile-device-search-copy-and-share-design.md`

---

## ⚠️ Standing constraints (override default skill behavior)

- **DO NOT COMMIT.** The writing-plans/TDD default ends each task with a `git commit`. For this work, **replace every commit with a non-committing checkpoint** (run the build/tests, leave changes in the working tree). No `git add`/`git commit`/`git push` at any point unless the user later says otherwise.
- **No AI attribution** anywhere in code, comments, or files.
- **Apple-native first**, modular, well-commented in the style of the surrounding files. The only intentional platform split is `#if os(macOS)` around the Save affordance.
- New files auto-include in the target (synchronized groups); no `.pbxproj` edits.

## Reference commands (slow — run at checkpoints)

```bash
# Build (macOS)
xcodebuild build -project "Jamf Dashboard.xcodeproj" -scheme "Jamf Dashboard" -destination 'platform=macOS' -quiet
# Build (iOS Simulator, build-only per project convention)
xcodebuild build -project "Jamf Dashboard.xcodeproj" -scheme "Jamf Dashboard" -destination 'generic/platform=iOS Simulator' -quiet
# Run only the new unit tests (macOS test bundle)
xcodebuild test -project "Jamf Dashboard.xcodeproj" -scheme "Jamf Dashboard" -destination 'platform=macOS' \
  -only-testing:JamfDashboardAppTests/RecordMarkdownTests \
  -only-testing:JamfDashboardAppTests/MobileDeviceRecordShareableTests
```

## File structure (what each file is responsible for)

**New (framework / design-system layer):**
- `JamfDashboardApp/Framework/Core/SharingContracts.swift` — `ShareField` value + `ShareableRecord` protocol. The only contract a module implements.
- `JamfDashboardApp/Framework/Core/RecordMarkdown.swift` — pure: records → Markdown string, and string → temp `.md` URL. Fully unit-tested.
- `JamfDashboardApp/Framework/UI/TextFileDocument.swift` — `FileDocument` (+ `UTType.dashboardMarkdown`) for the macOS `.fileExporter` Save. Build/manual-verified (its `*Configuration` types aren't publicly constructible, so no unit test).
- `JamfDashboardApp/Framework/UI/CopyButton.swift` — inline copy icon atom with checkmark feedback.
- `JamfDashboardApp/Framework/UI/SelectionCircle.swift` — leading multi-select toggle atom.

**New (module):**
- `JamfDashboardApp/Modules/MobileDeviceSearch/Models/MobileDeviceRecord+Shareable.swift` — `ShareableRecord` conformance.

**Modified (module):**
- `JamfDashboardApp/Modules/MobileDeviceSearch/Views/MobileDeviceDetailView.swift` — copy icons + toolbar `ShareLink` + macOS `.fileExporter`.
- `JamfDashboardApp/Modules/MobileDeviceSearch/Views/MobileDeviceSearchView.swift` — toolbar Share, selection mode, conditional rows, `.fileExporter`.

**New (tests):**
- `JamfDashboardAppTests/RecordMarkdownTests.swift`
- `JamfDashboardAppTests/MobileDeviceRecordShareableTests.swift`

**Unchanged:** `MobileDeviceResultRow.swift` (no copy icons in results, per spec).

---

## Task 1: Sharing contract

**Files:**
- Create: `JamfDashboardApp/Framework/Core/SharingContracts.swift`

- [ ] **Step 1: Create the contract file**

```swift
import Foundation

/// One labeled value contributed by a record when it is copied or exported.
struct ShareField: Hashable, Sendable {
    /// The human-readable field label (e.g. "Serial Number").
    let label: String
    /// The field's display value.
    let value: String
}

/// A record that can be exported to Markdown and shared via the system share sheet.
///
/// Modules conform their domain record type (e.g. `MobileDeviceRecord`) to this protocol
/// so the shared `RecordMarkdown` exporter and the framework copy/share UI can operate
/// on any module's records without duplicating logic.
protocol ShareableRecord {
    /// Heading text for the record, rendered as a Markdown `## <title>`.
    var shareTitle: String { get }
    /// The record's already-populated fields, in display order. Conformers omit empties.
    var shareFields: [ShareField] { get }
}
```

- [ ] **Step 2: Checkpoint (no commit)** — proceed to Task 2 (compiles as part of Task 2's build).

---

## Task 2: Markdown exporter (TDD)

**Files:**
- Create: `JamfDashboardApp/Framework/Core/RecordMarkdown.swift`
- Test: `JamfDashboardAppTests/RecordMarkdownTests.swift`

- [ ] **Step 1: Create the exporter with a stub (so tests compile and fail on assertions)**

```swift
import Foundation

/// Builds Markdown documents from `ShareableRecord` values and writes them to
/// temporary files for sharing.
///
/// Output: one `## <title>` heading per record followed by a `| Field | Value |` table of
/// that record's `shareFields`. Records are separated by a blank line, in supplied order.
enum RecordMarkdown {

    /// Returns a Markdown document describing `records`.
    static func document(for records: [any ShareableRecord]) -> String {
        ""  // stub — replaced in Step 4
    }

    /// Writes `document(for:)` to a `.md` file in the temporary directory and returns its URL.
    static func temporaryFile(for records: [any ShareableRecord], fileName: String) throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("Export").appendingPathExtension("md")
        try document(for: records).write(to: url, atomically: true, encoding: .utf8)
        return url  // stub naming — replaced in Step 4
    }
}
```

- [ ] **Step 2: Write the failing tests**

```swift
import XCTest
@testable import Jamf_Dashboard

/// Minimal conformer so the exporter can be tested without a domain model.
private struct StubShareable: ShareableRecord {
    let shareTitle: String
    let shareFields: [ShareField]
}

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
```

- [ ] **Step 3: Run tests — verify they FAIL**

Run the test command (see Reference commands, `-only-testing:JamfDashboardAppTests/RecordMarkdownTests`).
Expected: assertion failures (`document(for:)` returns `""`).

- [ ] **Step 4: Replace the stub with the real implementation**

```swift
import Foundation

/// Builds Markdown documents from `ShareableRecord` values and writes them to
/// temporary files for sharing.
///
/// Output: one `## <title>` heading per record followed by a `| Field | Value |` table of
/// that record's `shareFields`. Records are separated by a blank line, in supplied order.
enum RecordMarkdown {

    /// Returns a Markdown document describing `records`.
    static func document(for records: [any ShareableRecord]) -> String {
        records.map(section(for:)).joined(separator: "\n\n")
    }

    /// Writes `document(for:)` to a `.md` file in the temporary directory and returns its URL.
    ///
    /// - Parameters:
    ///   - records: The records to serialize.
    ///   - fileName: Base file name without extension (e.g. "Devices"); sanitized.
    /// - Returns: The URL of the written file.
    /// - Throws: Any error thrown while writing the file.
    static func temporaryFile(for records: [any ShareableRecord], fileName: String) throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(sanitizedFileName(fileName))
            .appendingPathExtension("md")
        try document(for: records).write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    // MARK: - Private

    /// Builds the Markdown section for a single record.
    private static func section(for record: any ShareableRecord) -> String {
        var lines = ["## \(escape(record.shareTitle))"]
        let fields = record.shareFields
        if fields.isEmpty == false {
            lines.append("")
            lines.append("| Field | Value |")
            lines.append("| --- | --- |")
            for field in fields {
                lines.append("| \(escape(field.label)) | \(escape(field.value)) |")
            }
        }
        return lines.joined(separator: "\n")
    }

    /// Escapes characters that would break a Markdown table cell.
    private static func escape(_ value: String) -> String {
        value
            .replacingOccurrences(of: "|", with: "\\|")
            .replacingOccurrences(of: "\r\n", with: "<br>")
            .replacingOccurrences(of: "\n", with: "<br>")
            .replacingOccurrences(of: "\r", with: "<br>")
            .trimmingCharacters(in: .whitespaces)
    }

    /// Reduces an arbitrary string to a filesystem-safe base file name.
    private static func sanitizedFileName(_ name: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_ "))
        let cleaned = String(name.trimmingCharacters(in: .whitespacesAndNewlines).unicodeScalars
            .filter { allowed.contains($0) })
        return cleaned.isEmpty ? "Export" : cleaned
    }
}
```

- [ ] **Step 5: Run tests — verify they PASS**

Run the same `-only-testing:JamfDashboardAppTests/RecordMarkdownTests` command. Expected: all pass.

- [ ] **Step 6: Checkpoint (no commit).**

---

## Task 3: macOS Save document (`TextFileDocument`)

**Files:**
- Create: `JamfDashboardApp/Framework/UI/TextFileDocument.swift`

No unit test: `FileDocument.ReadConfiguration`/`WriteConfiguration` are not publicly constructible. Verified by the macOS build (Task 8) and the macOS Save manual step (Task 9).

- [ ] **Step 1: Create the document + markdown UTType**

```swift
import SwiftUI
import UniformTypeIdentifiers

extension UTType {
    /// Markdown text. Falls back to plain text if the system type is unavailable, so the
    /// export still succeeds (as a `.txt`) on an OS that doesn't declare a `.md` type.
    static var dashboardMarkdown: UTType { UTType(filenameExtension: "md") ?? .plainText }
}

/// A minimal UTF-8 text `FileDocument` for exporting generated text (e.g. Markdown) through
/// SwiftUI's native `.fileExporter`. Read support exists for round-trip conformance; the
/// export path uses only the write side.
struct TextFileDocument: FileDocument {

    static var readableContentTypes: [UTType] { [.dashboardMarkdown, .plainText] }
    static var writableContentTypes: [UTType] { [.dashboardMarkdown] }

    /// The text payload to write.
    var text: String

    /// Creates a document wrapping `text`.
    init(text: String) { self.text = text }

    /// Reads a document's text from its file contents.
    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents,
              let string = String(data: data, encoding: .utf8) else {
            throw CocoaError(.fileReadCorruptFile)
        }
        text = string
    }

    /// Serializes `text` as UTF-8 into a new file wrapper.
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: Data(text.utf8))
    }
}
```

- [ ] **Step 2: Checkpoint (no commit)** — compiles as part of Task 8's build.

---

## Task 4: Copy button atom (`CopyButton`)

**Files:**
- Create: `JamfDashboardApp/Framework/UI/CopyButton.swift`

Build/manual-verified (SwiftUI view). Depends on existing `DashboardClipboard` and `DashboardColors`.

- [ ] **Step 1: Create the view**

```swift
import SwiftUI

/// A compact "copy to clipboard" button. Shows a `doc.on.doc` icon; tapping copies `value`
/// to the system pasteboard and briefly swaps the icon to a `checkmark` for confirmation.
/// Uses a borderless button style so its tap is isolated from any enclosing row or
/// `NavigationLink`.
struct CopyButton: View {

    /// The string copied to the clipboard when tapped.
    let value: String

    /// VoiceOver label; defaults to a generic "Copy".
    var accessibilityLabel: String = "Copy"

    /// Drives the transient checkmark confirmation.
    @State private var didCopy = false

    /// Reverts the checkmark after the confirmation interval.
    @State private var resetTask: Task<Void, Never>?

    var body: some View {
        Button {
            DashboardClipboard.copy(value)
            showConfirmation()
        } label: {
            Image(systemName: didCopy ? "checkmark" : "doc.on.doc")
                .font(.callout)
                .foregroundStyle(didCopy ? DashboardColors.greenPrimary : Color.secondary)
                .contentTransition(.symbolEffect(.replace))
        }
        .buttonStyle(.borderless)
        .accessibilityLabel(didCopy ? "Copied" : accessibilityLabel)
    }

    /// Flips to the checkmark, then restores the copy icon after ~1 second.
    private func showConfirmation() {
        didCopy = true
        resetTask?.cancel()
        resetTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 1_000_000_000)
            if Task.isCancelled == false { didCopy = false }
        }
    }
}
```

- [ ] **Step 2: Checkpoint (no commit).**

---

## Task 5: Selection circle atom (`SelectionCircle`)

**Files:**
- Create: `JamfDashboardApp/Framework/UI/SelectionCircle.swift`

- [ ] **Step 1: Create the view**

```swift
import SwiftUI

/// Leading multi-select toggle used by list rows in selection mode. Renders an empty
/// `circle` when unselected and a filled `checkmark.circle.fill` (accent) when selected.
struct SelectionCircle: View {
    /// Whether the associated row is currently selected.
    let isSelected: Bool

    var body: some View {
        Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
            .font(.title3)
            .foregroundStyle(isSelected ? DashboardColors.bluePrimary : Color.secondary)
            .accessibilityHidden(true)
    }
}
```

- [ ] **Step 2: Checkpoint (no commit).**

---

## Task 6: `MobileDeviceRecord` conformance (TDD)

**Files:**
- Create: `JamfDashboardApp/Modules/MobileDeviceSearch/Models/MobileDeviceRecord+Shareable.swift`
- Test: `JamfDashboardAppTests/MobileDeviceRecordShareableTests.swift`

- [ ] **Step 1: Create the conformance**

```swift
import Foundation

/// Makes `MobileDeviceRecord` exportable through the shared `RecordMarkdown` pipeline.
///
/// The title is the device name; the fields are every catalog field that currently holds a
/// non-empty value, in catalog (section) order — the "all populated fields" content used by
/// copy/share.
extension MobileDeviceRecord: ShareableRecord {
    var shareTitle: String { deviceName }

    var shareFields: [ShareField] {
        MobileDeviceField.catalog.compactMap { field in
            guard let value = value(for: field.key), value.isEmpty == false else { return nil }
            return ShareField(label: field.displayName, value: value)
        }
    }
}
```

- [ ] **Step 2: Write the tests**

```swift
import XCTest
@testable import Jamf_Dashboard

final class MobileDeviceRecordShareableTests: XCTestCase {

    private func makeRecord(fieldValues: [String: String] = [:]) -> MobileDeviceRecord {
        MobileDeviceRecord(
            id: "1", deviceName: "Jane's iPad", serialNumber: "DMP1",
            udid: nil, model: nil, osVersion: nil,
            prestageEnrollmentStatus: nil, prestageEnrollmentProfileName: nil,
            prestageEnrollmentProfileID: nil, fieldValues: fieldValues
        )
    }

    func test_shareTitleIsDeviceName() {
        XCTAssertEqual(makeRecord().shareTitle, "Jane's iPad")
    }

    func test_shareFieldsIncludePopulatedFieldsAndOmitEmpties() {
        let record = makeRecord(fieldValues: ["username": "jdoe", "emailAddress": "j@x.com"])
        let dict = Dictionary(uniqueKeysWithValues: record.shareFields.map { ($0.label, $0.value) })
        XCTAssertEqual(dict["Serial Number"], "DMP1")        // first-class fallback resolves
        XCTAssertEqual(dict["Assigned Username"], "jdoe")
        XCTAssertEqual(dict["Email Address"], "j@x.com")
        XCTAssertNil(dict["IP Address"])                     // unpopulated → omitted
    }
}
```

- [ ] **Step 3: Run tests — verify they PASS**

Run the test command with `-only-testing:JamfDashboardAppTests/MobileDeviceRecordShareableTests`.
Expected: pass. (The conformance already exists; these guard the field mapping.)

- [ ] **Step 4: Checkpoint (no commit).**

---

## Task 7: Detail view — copy icons + Share + macOS Save

**Files:**
- Modify: `JamfDashboardApp/Modules/MobileDeviceSearch/Views/MobileDeviceDetailView.swift`

Build/manual-verified. Apply these edits exactly.

- [ ] **Step 1: Add the UniformTypeIdentifiers import**

Change the top import line:

```swift
import SwiftUI
```
to:
```swift
import SwiftUI
import UniformTypeIdentifiers
```

- [ ] **Step 2: Add state + the copyable key set**

Immediately after the `@State private var refreshError: String?` line, add:

```swift
    /// The temporary `.md` URL backing the toolbar `ShareLink` for this device.
    @State private var exportURL: URL?

#if os(macOS)
    /// Drives the macOS `.fileExporter` Save panel.
    @State private var isExporting = false
#endif

    /// Identifier fields that get an inline copy icon next to their value.
    private let copyableFieldKeys: Set<String> = ["serialNumber", "username", "emailAddress", "ipAddress"]
```

- [ ] **Step 3: Add the toolbar, file exporter, and export refresh to `body`**

Replace the existing `.task(id: recordID)` modifier block:

```swift
        .task(id: recordID) {
            await refreshHardwareDetails()
        }
    }
```
with:
```swift
        .task(id: recordID) {
            await refreshHardwareDetails()
            regenerateExport()
        }
        .toolbar {
            ToolbarItemGroup(placement: .dashboardTopBarTrailing) {
                if let exportURL {
                    ShareLink(item: exportURL) {
                        Label("Share", systemImage: "square.and.arrow.up")
                    }
                } else {
                    Button { } label: { Label("Share", systemImage: "square.and.arrow.up") }
                        .disabled(true)
                }
#if os(macOS)
                Button { isExporting = true } label: {
                    Label("Save", systemImage: "square.and.arrow.down")
                }
                .disabled(record == nil)
#endif
            }
        }
#if os(macOS)
        .fileExporter(
            isPresented: $isExporting,
            document: TextFileDocument(text: RecordMarkdown.document(for: record.map { [$0] } ?? [])),
            contentType: .dashboardMarkdown,
            defaultFilename: record?.deviceName ?? "Device"
        ) { _ in isExporting = false }
#endif
    }

    /// Rebuilds the single-record share file for the current `record`.
    private func regenerateExport() {
        guard let record else { exportURL = nil; return }
        exportURL = try? RecordMarkdown.temporaryFile(for: [record], fileName: record.deviceName)
    }
```

- [ ] **Step 4: Add a copy icon to the serial line in `identityHeader`**

Replace:

```swift
                if record.serialNumber.isEmpty == false {
                    Text("Serial: \(record.serialNumber)")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
```
with:
```swift
                if record.serialNumber.isEmpty == false {
                    HStack(spacing: 4) {
                        Text("Serial: \(record.serialNumber)")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        CopyButton(value: record.serialNumber, accessibilityLabel: "Copy serial number")
                    }
                }
```

- [ ] **Step 5: Add copy icons to the copyable inventory rows in `sectionGroup`**

Replace the `ForEach(fields) { field in ... }` body:

```swift
                ForEach(fields) { field in
                    HStack(alignment: .top, spacing: 12) {
                        Text(field.displayName)
                            .frame(width: 180, alignment: .leading)
                            .foregroundStyle(.secondary)
                            .font(.callout)
                        Text(record.value(for: field.key) ?? "—")
                            .font(.callout)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .padding(.vertical, 6)
                    Divider().opacity(0.3)
                }
```
with:
```swift
                ForEach(fields) { field in
                    let fieldValue = record.value(for: field.key)
                    HStack(alignment: .top, spacing: 12) {
                        Text(field.displayName)
                            .frame(width: 180, alignment: .leading)
                            .foregroundStyle(.secondary)
                            .font(.callout)
                        Text(fieldValue ?? "—")
                            .font(.callout)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        if let fieldValue, fieldValue.isEmpty == false, copyableFieldKeys.contains(field.key) {
                            CopyButton(value: fieldValue, accessibilityLabel: "Copy \(field.displayName)")
                        }
                    }
                    .padding(.vertical, 6)
                    Divider().opacity(0.3)
                }
```

- [ ] **Step 6: Build (macOS) — verify it compiles**

Run the macOS build command. Expected: BUILD SUCCEEDED.

- [ ] **Step 7: Checkpoint (no commit).**

---

## Task 8: Results view — toolbar Share, selection mode, macOS Save

**Files:**
- Modify: `JamfDashboardApp/Modules/MobileDeviceSearch/Views/MobileDeviceSearchView.swift`

- [ ] **Step 1: Add the UniformTypeIdentifiers import**

Change:
```swift
import SwiftUI
```
to:
```swift
import SwiftUI
import UniformTypeIdentifiers
```

- [ ] **Step 2: Add selection/export state**

After the `@State private var advancedSearchViewModel: AdvancedSearchViewModel?` line, add:

```swift
    /// Whether the results list is in multi-select (share) mode.
    @State private var isSelecting = false
    /// IDs of records currently selected for sharing.
    @State private var selectedIDs: Set<String> = []
    /// The temporary `.md` URL backing the "Share (N)" `ShareLink`.
    @State private var exportURL: URL?

#if os(macOS)
    /// Drives the macOS `.fileExporter` Save panel.
    @State private var isExporting = false
#endif
```

- [ ] **Step 3: Replace the Results `ForEach` with a conditional row**

Replace:
```swift
                    ForEach(viewModel.searchResults) { record in
                        NavigationLink(value: MobileDeviceRecordRoute(id: record.id)) {
                            MobileDeviceResultRow(
                                record: record,
                                fields: viewModel.resultFields
                            )
                        }
                    }
```
with:
```swift
                    ForEach(viewModel.searchResults) { record in
                        resultRow(for: record)
                    }
```

- [ ] **Step 4: Add the toolbar, change handlers, file exporter, and helpers**

Insert immediately after the `.dashboardInsetGroupedListStyle()` line:

```swift
        .toolbar {
            if isSelecting {
                ToolbarItem(placement: .dashboardTopBarLeading) {
                    Button("Cancel") { exitSelection() }
                }
                ToolbarItemGroup(placement: .dashboardTopBarTrailing) {
                    Button(allSelected ? "Deselect All" : "Select All") { toggleSelectAll() }
                        .disabled(viewModel.searchResults.isEmpty)

                    if selectedIDs.isEmpty == false, let exportURL {
                        ShareLink(item: exportURL) {
                            Label("Share \(selectedIDs.count)", systemImage: "square.and.arrow.up")
                        }
                    } else {
                        Button { } label: { Label("Share", systemImage: "square.and.arrow.up") }
                            .disabled(true)
                    }

#if os(macOS)
                    Button { isExporting = true } label: {
                        Label("Save", systemImage: "square.and.arrow.down")
                    }
                    .disabled(selectedIDs.isEmpty)
#endif
                }
            } else {
                ToolbarItem(placement: .dashboardTopBarTrailing) {
                    Button { isSelecting = true } label: {
                        Label("Share", systemImage: "square.and.arrow.up")
                    }
                    .disabled(viewModel.searchResults.isEmpty)
                }
            }
        }
        .onChange(of: selectedIDs) { _, _ in regenerateExport() }
        .onChange(of: viewModel.searchResults.map(\.id)) { _, _ in
            if isSelecting { exitSelection() }
        }
#if os(macOS)
        .fileExporter(
            isPresented: $isExporting,
            document: TextFileDocument(text: RecordMarkdown.document(for: selectedRecords)),
            contentType: .dashboardMarkdown,
            defaultFilename: "Devices"
        ) { _ in isExporting = false }
#endif
```

Then add these members to the struct (e.g. just before the closing brace of `MobileDeviceSearchView`):

```swift
    // MARK: - Multi-select sharing

    /// Records currently selected, in results order.
    private var selectedRecords: [MobileDeviceRecord] {
        viewModel.searchResults.filter { selectedIDs.contains($0.id) }
    }

    /// Whether every visible result is selected.
    private var allSelected: Bool {
        viewModel.searchResults.isEmpty == false && selectedIDs.count == viewModel.searchResults.count
    }

    /// A results row: a selectable button in selection mode, otherwise the navigating link.
    @ViewBuilder
    private func resultRow(for record: MobileDeviceRecord) -> some View {
        if isSelecting {
            Button {
                toggleSelection(record.id)
            } label: {
                HStack(spacing: 12) {
                    SelectionCircle(isSelected: selectedIDs.contains(record.id))
                    MobileDeviceResultRow(record: record, fields: viewModel.resultFields)
                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        } else {
            NavigationLink(value: MobileDeviceRecordRoute(id: record.id)) {
                MobileDeviceResultRow(record: record, fields: viewModel.resultFields)
            }
        }
    }

    private func toggleSelection(_ id: String) {
        if selectedIDs.contains(id) { selectedIDs.remove(id) } else { selectedIDs.insert(id) }
    }

    private func toggleSelectAll() {
        if allSelected { selectedIDs.removeAll() }
        else { selectedIDs = Set(viewModel.searchResults.map(\.id)) }
    }

    /// Leaves selection mode and clears all selection/export state.
    private func exitSelection() {
        isSelecting = false
        selectedIDs.removeAll()
        exportURL = nil
    }

    /// Rebuilds the multi-record share file for the current selection.
    private func regenerateExport() {
        guard selectedRecords.isEmpty == false else { exportURL = nil; return }
        exportURL = try? RecordMarkdown.temporaryFile(for: selectedRecords, fileName: "Devices")
    }
```

- [ ] **Step 5: Build (macOS) — verify it compiles**

Run the macOS build command. Expected: BUILD SUCCEEDED.

- [ ] **Step 6: Checkpoint (no commit).**

---

## Task 9: Full verification

**Files:** none (verification only).

- [ ] **Step 1: Run the new unit tests (macOS)**

Run the `xcodebuild test … -only-testing:…RecordMarkdownTests -only-testing:…MobileDeviceRecordShareableTests` command. Expected: all pass.

- [ ] **Step 2: Build for iOS Simulator**

Run the iOS build command. Expected: BUILD SUCCEEDED (no iOS-only/macOS-only symbol leaks across the `#if os(macOS)` boundaries).

- [ ] **Step 3: Build for macOS** (if not already green from Tasks 7–8). Expected: BUILD SUCCEEDED.

- [ ] **Step 4: Manual verification (run the app)**

Detail view:
- Copy icons appear next to Serial (header) and next to Assigned Username / Email Address / IP Address rows when populated; tapping copies the exact value and the icon shows a brief checkmark.
- Toolbar **Share** opens the share sheet with a single-device `.md`.
- macOS: **Save** opens `.fileExporter`; the saved file is `<DeviceName>.md` with the expected table.

Results view:
- **No** copy icons in rows.
- Toolbar **Share** enters selection mode: selection circles appear at the left; tapping a row toggles selection and does **not** navigate. **Select All / Deselect All** and **Cancel** work.
- **Share (N)** opens the share sheet with a multi-device `.md` containing exactly the selected devices (results order).
- macOS: **Save** writes the same multi-device `.md`. Confirm a **second** Share and a **cancelled** `.fileExporter` both behave (no stuck state). Running a new search while selecting exits selection mode.

- [ ] **Step 5: Final checkpoint (no commit).** Leave all changes in the working tree and report results.

---

## Self-review (completed during planning)

- **Spec coverage:** copy icons (detail, 4 fields) → Tasks 4/7; markdown (heading + table, escaping, multi-record) → Task 2; share everywhere via `ShareLink` → Tasks 7/8; macOS Save via `.fileExporter` → Tasks 3/7/8; selection mode (circles, suppress nav, Select All, Cancel, exit on new search) → Tasks 5/8; framework reusability via `ShareableRecord` → Task 1/6; no copy icons in results → Task 8 (row unchanged otherwise). All covered.
- **Placeholder scan:** none — every code/test/command step is concrete.
- **Type consistency:** `ShareField(label:value:)`, `ShareableRecord.shareTitle/shareFields`, `RecordMarkdown.document(for:)`/`temporaryFile(for:fileName:)`, `TextFileDocument(text:)`, `UTType.dashboardMarkdown`, `CopyButton(value:accessibilityLabel:)`, `SelectionCircle(isSelected:)`, and the view helpers (`selectedRecords`, `allSelected`, `regenerateExport`, `exitSelection`) are used identically across tasks.
- **Constraint check:** no commit steps anywhere; the only platform split is `#if os(macOS)`; no AI attribution.
