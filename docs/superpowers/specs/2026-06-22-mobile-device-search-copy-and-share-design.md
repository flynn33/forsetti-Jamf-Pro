# Copy Icons & Record Sharing — Design Spec

- **Date:** 2026-06-22
- **Status:** Implemented in v3.27.0
- **Pilot module:** Mobile Device Search (`JamfDashboardApp/Modules/MobileDeviceSearch`)
- **Reusable layer:** App framework (`JamfDashboardApp/Framework`)

## 1. Summary

Add two capabilities, built as **reusable framework components** so every module can
adopt them with minimal module-local code:

1. **Inline copy icons** next to a record's key identifiers — Serial Number, Assigned
   Username, Email Address, IP Address — in the **detail view** of Mobile Device Search.
2. **Whole-record sharing** as a generated **Markdown file** handed to the native system
   share sheet (Messages / Mail / Teams / Save to Files, etc.):
   - **Detail view:** a top-right toolbar Share button shares the one device being viewed.
   - **Results view:** a top-right toolbar Share button enters a **multi-select mode**
     (selection circles to the left of each row); the technician picks records and confirms
     to share/save a Markdown file of the selected devices.
   - **macOS** additionally offers a native **Save** panel (`.fileExporter`) in both views,
     since the macOS share menu has no "Save to Files" entry (iOS gets Save to Files from the
     share sheet).

Mobile Device Search is the pilot. After it is validated, other modules adopt the same
framework components by conforming their record type to one small protocol.

## 2. Goals

- Reusable, framework-level building blocks (shareable-record contract, Markdown export,
  copy button, selection-circle atom). Sharing itself uses Apple's native `ShareLink` directly
  — no custom share-sheet presenter.
- Prefer Apple-native APIs over custom implementations throughout (easier to read and maintain);
  platform-split (`#if os(...)`) only where a single API genuinely cannot cover both, and even
  then Apple-native, modular, and well-commented.
- A module adopts the feature by (a) conforming its record type to `ShareableRecord`
  and (b) wiring the framework atoms into its existing views — no duplicated copy/share/
  markdown logic per module.
- Cross-platform: iOS/iPadOS 26 and macOS 14 (the app's deployment targets).
- Consistent output: single-record and multi-record sharing use the **same** Markdown
  formatter and the **same** share-sheet presentation path.

## 3. Non-Goals

- **No inline copy icons in the results rows.** The results view's only sharing/copy
  affordance is the toolbar Share button → selection mode. `MobileDeviceResultRow` is left
  visually unchanged.
- No per-app integrations (Messages/Mail/Teams). We generate a `.md` file and hand it to
  the OS share sheet; the OS surfaces installed destinations.
- No rollout to other modules in this change. The framework layer is built to make that
  easy later, but only Mobile Device Search is wired up now.
- No git commits as part of this work (per explicit instruction). The spec and code are
  produced but left uncommitted until the user decides otherwise.

## 4. Background — current state

Key files (all read and confirmed):

- `Modules/MobileDeviceSearch/Views/MobileDeviceSearchView.swift` — the results screen: a
  `List` of `NavigationLink(value: MobileDeviceRecordRoute(id:))` rows, `.dashboardInsetGroupedListStyle()`,
  with `.navigationDestination(for: MobileDeviceRecordRoute.self)`. No `.toolbar` today.
- `Modules/MobileDeviceSearch/Views/MobileDeviceResultRow.swift` — renders device name +
  active-profile field lines. Receives `record` and `fields`.
- `Modules/MobileDeviceSearch/Views/MobileDeviceDetailView.swift` — identity header
  (serial + UDID), `HardwareInfoCard`, and inventory details grouped by section. Iterates
  `MobileDeviceField.catalog.filter { record.value(for: $0.key)?.isEmpty == false }`.
- `Modules/MobileDeviceSearch/Models/MobileDeviceRecord.swift` — the record model;
  `value(for: fieldKey) -> String?` resolves any catalog field (dictionary first, then
  first-class properties).
- `Modules/MobileDeviceSearch/Models/MobileDeviceField.swift` (+ `…Catalog+Generated.swift`) —
  `MobileDeviceField { key, displayName, description, section, … }` and the ordered
  `MobileDeviceField.catalog`. Confirmed field metadata:
  - `serialNumber` → "Serial Number" (`.hardware`)
  - `username` → "Assigned Username" (`.location`)
  - `emailAddress` → "Email Address" (`.location`)
  - `ipAddress` → "IP Address" (`.general`)

Framework conventions (confirmed):

- `Framework/UI/SwiftUIPlatformCompat.swift` already provides `DashboardClipboard.copy(_:)`
  (`UIPasteboard` on iOS, `NSPasteboard` on macOS via `#if canImport(UIKit)/AppKit)`).
- `Framework/Core/ModuleContracts.swift` is where framework protocols live (e.g. `DashboardFeatureWorkspace`).
- Framework UI atoms are simple `struct … : View` files in `Framework/UI/` (e.g.
  `ScanIntoTextFieldButton.swift`), using `.dashboardSecondary` / `.dashboardPrimary` button styles.
- `ShareLink` is already used in the framework (`DiagnosticsView.swift`).
- Xcode synchronized groups: new files added under these directories are auto-included in
  the target — no `.pbxproj` edits needed.

## 5. Architecture

### 5.1 Framework — the shareable-record contract

`Framework/Core/SharingContracts.swift` (new):

```swift
/// One labeled value to be rendered when a record is copied/exported.
struct ShareField: Hashable, Sendable {
    let label: String
    let value: String
}

/// A record that can be exported to Markdown and shared via the system share sheet.
/// Modules conform their domain record (e.g. MobileDeviceRecord) to this protocol.
protocol ShareableRecord {
    /// Heading text for the record (rendered as a Markdown "## <title>").
    var shareTitle: String { get }
    /// Ordered, already-populated fields (empty values omitted by the conformer).
    var shareFields: [ShareField] { get }
}
```

### 5.2 Framework — Markdown export (pure, testable)

`Framework/UI/RecordMarkdown.swift` (new):

```swift
enum RecordMarkdown {
    /// Builds a Markdown document: one "## <title>" + "| Field | Value |" table per record.
    static func document(for records: [any ShareableRecord]) -> String

    /// Writes `document(for:)` to a uniquely named .md file in the temporary directory
    /// and returns its URL. Throws on write failure.
    static func temporaryFile(
        for records: [any ShareableRecord],
        fileName: String
    ) throws -> URL
}
```

Formatting rules:

- Document order = the order of `records` passed in (results order / single record).
- Each record:
  ```
  ## <shareTitle>

  | Field | Value |
  | --- | --- |
  | <label> | <value> |
  …
  ```
- Records separated by a blank line.
- **Value sanitization:** escape `|` as `\|` and replace embedded newlines with `<br>` so
  the Markdown table stays well-formed. Trim trailing whitespace.
- A record with no `shareFields` still emits its `## <shareTitle>` heading (so an explicitly
  shared device is never silently empty).
- File name: caller supplies a base; the writer appends a disambiguating suffix and `.md`
  (e.g. `Devices.md`, `Devices-3.md`). `Date.now`-based names are avoided (no wall-clock in
  pure code paths); use a stable base + record count, falling back to `UUID` only if needed.

### 5.3 Framework — inline copy button atom

`Framework/UI/CopyButton.swift` (new):

```swift
/// A compact "copy to clipboard" affordance. Shows `doc.on.doc`; on tap copies `value`
/// via DashboardClipboard and briefly swaps to `checkmark` (~1s) for confirmation.
struct CopyButton: View {
    let value: String
    var accessibilityLabel: String = "Copy"
    // @State private var copied = false
    // Button { DashboardClipboard.copy(value); animate checkmark } label: { Image(systemName: …) }
    //   .buttonStyle(.borderless)   // isolates the tap from any enclosing row/NavigationLink
}
```

Behavior details:

- `.buttonStyle(.borderless)` (or `.plain`) so the tap does not trigger an enclosing
  `NavigationLink`/row selection.
- Checkmark feedback driven by `@State private var copied` flipped back after ~1s via a
  cancellable `Task`; symbol swap only (no layout shift). Honor reduce-motion by keeping the
  change instantaneous if needed.
- Accessibility label defaults to "Copy"; callers may pass e.g. "Copy serial number".

### 5.4 Framework — selection-circle atom

`Framework/UI/SelectionCircle.swift` (new):

```swift
/// Leading multi-select toggle used by list rows in selection mode.
/// Renders `circle` when unselected and `checkmark.circle.fill` (accent) when selected.
struct SelectionCircle: View {
    let isSelected: Bool
}
```

### 5.5 Framework — sharing primitive (Apple-native `ShareLink`)

**Decision:** sharing uses SwiftUI's native `ShareLink` directly — no custom share-sheet
presenter. `ShareLink` is cross-platform (iOS 16+/macOS 13+; the app targets iOS 26/macOS 14)
and internally drives `UIActivityViewController` on iOS/iPadOS and `NSSharingServicePicker` on
macOS, so Apple owns all anchoring and dismissal. This removes the only piece of the earlier
design that carried real risk, keeps one understandable primitive, and adds **no** AppKit/UIKit
plumbing for us to maintain.

There is therefore **no `ShareSheet` framework file.** The reusable sharing layer is:

- `ShareableRecord` (§5.1) — what a record contributes.
- `RecordMarkdown` (§5.2) — builds the Markdown string (and, for tests/other callers, a temp `.md` URL).

**Share = text; Save = file.** The two intents are split across two affordances rather than
mixed on one share action:

- **Share** shares the Markdown **text** (a plain `String`): `ShareLink(item: RecordMarkdown.document(for:))`.
  Because the shared item is text, the share sheet's **Copy** behaves as normal copy/paste, and
  Messages / Mail / Teams insert the text inline. (Earlier attempts shared a `.md` *file* — a bare
  file URL, then a dual text+file `Transferable` — but on macOS the share sheet's **Copy** kept
  putting a *file* on the pasteboard, which would not paste as text. Sharing plain text is the
  reliable, predictable behavior.)
- **Save** writes the **`.md` file** via `.fileExporter` (§5.5.1).

Views build the share text inline from current state (`RecordMarkdown.document(for:)` is a cheap
pure string build), so there is **no** `exportURL` state or regenerate-on-change wiring.

### 5.5.1 Framework — Save (Apple-native `.fileExporter`, both platforms)

**Save** uses SwiftUI's native `.fileExporter`, presented on **both iOS and macOS** (since Share
no longer puts a file on the share sheet, iOS gets an explicit Save too — `.fileExporter` shows
the Files save UI on iOS and the save panel on macOS). It writes the `.md` directly to the chosen
location (no temp file on this path).

`.fileExporter` needs a `FileDocument`, so the framework provides a small reusable one:

```swift
/// A minimal UTF-8 text document for exporting generated text (e.g. Markdown) via .fileExporter.
struct TextFileDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.dashboardMarkdown, .plainText] }
    static var writableContentTypes: [UTType] { [.dashboardMarkdown] }   // saved as .md
    var text: String
    init(text: String) { self.text = text }
    init(configuration: ReadConfiguration) throws { … }          // for round-trip conformance
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper { … }
}
```

Views present it on both platforms:

```swift
.fileExporter(
    isPresented: $isExporting,
    document: TextFileDocument(text: RecordMarkdown.document(for: recordsToSave)),
    contentType: .dashboardMarkdown,
    defaultFilename: "Devices"
) { _ in isExporting = false }
```

Because `recordsToSave` is read from SwiftUI state at present time, the saved document always
reflects the current single record (detail) or current selection (results).

### 5.6 Module — MobileDeviceSearch integration

**Conformance** — `Modules/MobileDeviceSearch/Models/MobileDeviceRecord+Shareable.swift` (new):

```swift
extension MobileDeviceRecord: ShareableRecord {
    var shareTitle: String { deviceName }
    var shareFields: [ShareField] {
        MobileDeviceField.catalog.compactMap { field in
            guard let v = value(for: field.key), v.isEmpty == false else { return nil }
            return ShareField(label: field.displayName, value: v)
        }
    }
}
```

This yields **all populated catalog fields in catalog (section) order** — the agreed
"all populated fields" content. From the results list a record carries fewer populated
fields than after the detail view's hardware refresh; that difference is expected.

**Copyable key set** — one module-local constant so it is easy to extend:

```swift
private let copyableFieldKeys: Set<String> = ["serialNumber", "username", "emailAddress", "ipAddress"]
```

**Detail view (`MobileDeviceDetailView.swift`):**

- Identity header: place a `CopyButton(value: record.serialNumber)` next to the serial line.
- Inventory rows (`sectionGroup`): when `field.key` ∈ `copyableFieldKeys` and the value is
  non-empty, append a trailing `CopyButton(value:)` to that row's `HStack`.
- Toolbar — Share: a native `ShareLink(item: RecordMarkdown.document(for: [record]))` — shares
  the Markdown **text**, built inline from the cached `record` (no `exportURL` state) so Share is
  usable immediately; after the hardware refresh updates `record`, the text rebuilds on the next
  render with richer fields. A disabled placeholder shows only while `record` is `nil`.
- Toolbar — Save (both platforms): a Save button (`square.and.arrow.down`) sets
  `@State var isExporting = true`, presenting `.fileExporter` with
  `TextFileDocument(text: RecordMarkdown.document(for: [record]))` and a `defaultFilename`
  of `RecordMarkdown.sanitizedFileName(deviceName)` (a raw Jamf name may contain `/` or `:`,
  which a save panel would mangle).

**Results view (`MobileDeviceSearchView.swift`):**

- Local UI state: `@State private var isSelecting = false`,
  `@State private var selectedIDs: Set<String> = []`, `@State private var isExporting = false`.
- Toolbar (cross-platform placement, `.primaryAction` / `.automatic`):
  - Not selecting: a Share button (`square.and.arrow.up`) → sets `isSelecting = true`.
  - Selecting: **Cancel** (clears `isSelecting` + `selectedIDs`), a **Select All / Deselect All**
    toggle, and the confirm controls:
    - Share — a native `ShareLink(item: RecordMarkdown.document(for: selectedRecords))` (shares the
      selected records' Markdown **text**), built inline from the current selection; a disabled
      placeholder button when `selectedIDs` is empty.
    - Save (both platforms) — a Save button (`square.and.arrow.down`), enabled when
      `selectedIDs` is non-empty, sets `isExporting = true` to present `.fileExporter` with
      `TextFileDocument(text: RecordMarkdown.document(for: selectedRecords))` and
      `defaultFilename: "Devices"`.
- No `exportURL` / regenerate-on-change wiring: the `ShareLink` item is the Markdown text built
  inline from `selectedRecords` each render (a pure string build).
- Results `ForEach`: render rows conditionally.
  - Not selecting: the existing `NavigationLink(value:) { MobileDeviceResultRow(...) }`,
    unchanged.
  - Selecting: a `Button` row = `HStack { SelectionCircle(isSelected:) ; MobileDeviceResultRow(...) }`
    that toggles membership in `selectedIDs`; **navigation is suppressed** while selecting.
- Selection persists after a share. Apple's native `ShareLink` exposes **no** completion
  callback (the trade-off of choosing the native API), so selection mode is not auto-exited on
  share — and persisting it is useful (re-share the same set to another destination). Selection
  is cleared by **Cancel** or by a new search (the `searchResults` change handler below).
- `MobileDeviceResultRow.swift` is **not** modified (no inline copy icons in results).

## 6. Detailed behavior & UX

- **Copy feedback:** icon → checkmark for ~1s, then reverts; no toast, no layout shift.
- **Detail share content:** one device, all its populated fields.
- **Results share content:** the selected devices, all populated fields each, in list order.
- **Selection entry/exit:** toolbar Share enters selection; **Cancel** or a new search exits.
  Sharing does not exit selection (`ShareLink` has no completion callback; persisting the
  selection lets the tech re-share to another destination).
- **Empty selection:** Share (N) disabled at 0 selected.
- **Markdown destinations:** whatever the OS share sheet offers for a `.md` file — Messages,
  Mail, Teams (if installed), Save to Files / save panel, Copy, AirDrop, etc.

## 7. Cross-platform considerations

- Toolbar placement uses a placement that resolves on both platforms (`.primaryAction` or
  `.automatic`); avoid iOS-only `.topBarTrailing`.
- Selection mode is a **custom** `isSelecting`/`selectedIDs` approach (not UIKit `EditMode`,
  which is iOS-only) so behavior is identical on macOS and iOS/iPadOS.
- Sharing is Apple's native `ShareLink`; Apple handles the per-platform presenter internally,
  so we write no `#if os(...)` for the share UI itself.
- Sharing (text) and saving (`.fileExporter`) are both Apple-native and presented on **both**
  platforms — no `#if os(...)` for either. Apple handles each per-platform UI internally.
- `CopyButton`, `SelectionCircle`, and `TextFileDocument` are pure SwiftUI/Foundation and
  platform-agnostic.

## 8. Edge cases

- Values containing `|` or newlines → sanitized by the Markdown writer (§5.2).
- A device with no populated fields → heading-only Markdown section (never silently empty).
- Share-sheet **Copy**: because Share shares plain **text**, Copy puts text on the pasteboard and
  pastes normally (sharing a `.md` file URL or a text+file `Transferable` did not — Copy grabbed
  the file; that was the reported bug). The Share control is disabled when there's nothing to
  share (`record == nil` / empty selection).
- Rapid repeated copy taps → the checkmark `Task` is cancellable/restartable.
- Selecting, then the underlying `searchResults` changing (e.g. a new search) → on results
  refresh, clear `selectedIDs` and exit selection mode to avoid stale ids.
- Tap isolation: copy buttons use `.borderless` so taps never trigger row navigation.
- Re-share reflects current state: the `ShareLink` text is rebuilt from live state each render,
  so a second share always matches the current record/selection.
- Saving the `.md` file is a separate **Save** affordance (`.fileExporter`, both platforms).
- `.fileExporter` cancel → no file written, `isExporting` reset to false, no error.

## 9. Testing plan

- **Framework unit tests (macOS test bundle)** for `RecordMarkdown.document(for:)` using a
  stub `ShareableRecord`:
  - single record → correct `## title`, header row, one `| label | value |` per field;
  - empty values omitted by the conformer are absent; heading-only record renders heading;
  - multi-record order preserved;
  - `|` and newline sanitization;
  - `temporaryFile(for:fileName:)` writes a readable `.md` whose contents equal `document(for:)`.
- **Builds:** macOS (`platform=macOS`) and `generic/platform=iOS Simulator`. (Per project
  note, the XCTest bundle runs on macOS; iOS/iPad are build-only here.)
- **Manual verification:**
  - Detail: copy each of serial/username/email/IP → clipboard holds the exact value; checkmark
    appears. Toolbar **Share** → share sheet; choosing **Copy** then pasting into a text field
    shows the Markdown **text** (regression guard for the file-pasteboard bug); Messages/Mail
    insert the text inline. **Save** → `.fileExporter` writes the `.md` to the chosen location
    with the device-name default.
  - Results: toolbar Share → selection circles appear; navigation suppressed; select several;
    Share (N) → share sheet shares the selected devices' Markdown text (Copy pastes as text);
    **Save** → `.fileExporter` writes the multi-device `.md`; Cancel exits cleanly.
  - Confirm a second Share and a cancelled `.fileExporter` both behave (no stuck state), on iOS
    and macOS.

## 10. File manifest

**New (framework):**
- `Framework/Core/SharingContracts.swift` — `ShareField`, `ShareableRecord`.
- `Framework/Core/RecordMarkdown.swift` — Markdown builder + temp-file writer.
- `Framework/UI/CopyButton.swift` — inline copy icon atom.
- `Framework/UI/SelectionCircle.swift` — selection toggle atom.
- `Framework/UI/TextFileDocument.swift` — `FileDocument` for the `.fileExporter` Save.
- (No custom share-sheet / `Transferable` file — Share shares the Markdown text via `ShareLink(item: String)`.)

**New (module):**
- `Modules/MobileDeviceSearch/Models/MobileDeviceRecord+Shareable.swift` — protocol conformance.

**Modified (module):**
- `Modules/MobileDeviceSearch/Views/MobileDeviceDetailView.swift` — inline copy icons +
  toolbar `ShareLink` (Markdown text) + `.fileExporter` Save (both platforms).
- `Modules/MobileDeviceSearch/Views/MobileDeviceSearchView.swift` — toolbar Share, selection
  mode, conditional rows, toolbar `ShareLink` (Markdown text) + `.fileExporter` Save (both platforms).

**New (tests):**
- `JamfDashboardAppTests/RecordMarkdownTests.swift` — formatter/writer unit tests.

**Unchanged:** `MobileDeviceResultRow.swift`.

## 11. Versioning & process

- Feature shipped in **3.27.0** (`feature/mobile-search-copy-share`, merged #43). Share-sheet
  **Copy** then needed fixing: **3.27.1** (#45) tried a text+file `Transferable` but macOS Copy
  still grabbed the file; **3.27.2** (`fix/share-copy-as-text`) settled on Share = Markdown text +
  a cross-platform `.fileExporter` Save, so Copy pastes normally. All via `scripts/bump-version.sh`
  with CHANGELOG/README prose by hand.
- **No AI attribution of any kind** in code, comments, files, commit messages, or PRs.
- Prefer Apple-native APIs; all new code is modular and well-commented in the style of the
  surrounding framework/module files.

## 12. Future global rollout (informational)

Once validated here, another module adopts the feature by:
1. Conforming its record type to `ShareableRecord` (`shareTitle` + populated `shareFields`).
2. Adding `CopyButton`s next to its copyable fields in its detail view.
3. Adding a toolbar `ShareLink(item: RecordMarkdown.document(for:))` (shares Markdown text) +
   selection mode (the same `isSelecting`/`selectedIDs` pattern + `SelectionCircle`) to its
   results view, and a `.fileExporter` Save using `TextFileDocument` (both platforms).

No copy/share/markdown logic is duplicated — only the thin per-module wiring above.
