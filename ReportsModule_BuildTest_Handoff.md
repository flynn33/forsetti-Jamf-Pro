# Reports Module Build and Test Handoff

## Release Summary

Release version: `3.21.0`

Project path:

```text
/Users/jimdaley/Documents/Jamf Dashboard/Projects/Jamf-Dashboard-main/Jamf Dashboard.xcodeproj
```

Xcode scheme:

```text
Jamf Dashboard
```

Targets:

```text
Jamf Dashboard
JamfDashboardAppTests
```

The `3.21.0` update adds a bundled Reports module for Jamf Pro inventory reporting. The module is registered as a protected bundled default module and appears alongside the existing Computer Search, Mobile Device Search, Support Technician, and Prestage Director modules.

The implementation follows the existing native Swift and SwiftUI architecture, uses the shared `JamfAPIGateway`, and keeps the report code modular across models, services, rendering, export, view models, and views.

## Primary Functional Scope

The Reports module provides:

- Fleet inventory counts by device type.
- Default buckets for Mac, iPad, iPhone, Other, Unknown, and Total.
- Computer and mobile inventory loading through the shared Jamf API gateway.
- Device identity normalization using Jamf payload fields and the local Apple device model catalog.
- Criteria-based report building across shared inventory fields.
- Client-side matching for report criteria that should not be pushed into Jamf server filters.
- Segmented gauge visualization for device-type distribution.
- Metal-backed gauge rendering with SwiftUI fallback.
- Visual report pages containing summary metrics, distribution views, ranked group counts, and matching records.
- Export support for `.csv`, `.txt`, `.md`, Word-readable `.doc`, and `.pdf`.
- Visual aids included in DOC and PDF export paths.

## Requirement Mapping

| Requirement | Implementation |
| --- | --- |
| Add bundled Reports module | `ReportsModule`, `FeaturePackageManifest`, `FeaturePackageCatalogManager`, and `FeaturePackageTemplates/reports.json` |
| Use Jamf Modern API through existing gateway | `ReportsInventoryService` uses `JamfAPIGateway` |
| Default counts for Mac, iPad, iPhone, Other, Unknown, Total | `ReportsAggregator`, `ReportDeviceType`, `ReportAggregate` |
| Visual segmented gauge | `ReportsDeviceTypeGaugeView`, `ReportsDeviceTypeGaugeRenderer`, `ReportsDeviceTypeGaugeFallbackView` |
| Metal with fallback | Metal renderer backed by SwiftUI fallback |
| New Report builder with criteria | `ReportBuilderView`, `ReportCriteriaModels`, `ReportsFieldCatalog`, `ReportsQueryPlanner` |
| Visual report page | `GeneratedReportView`, `ReportVisualizationViews` |
| Export CSV/TXT/MD/DOC/PDF | Export renderers under `JamfDashboardApp/Modules/Reports/Export` |
| DOC and PDF visual aids | `ReportsVisualizationSnapshotRenderer`, `ReportDocRenderer`, `ReportPDFRenderer` |
| Version bump | `VERSION`, project `MARKETING_VERSION`, project `CURRENT_PROJECT_VERSION`, README, WIKI, CHANGELOG |
| Documentation updates | `README.md`, `WIKI.md`, `CHANGELOG.md` |

## Registration and Packaging

Reports is registered as a module type:

```swift
case reports = "reports"
```

Bundled package ID:

```text
com.jamftool.modules.reports
```

Manifest template:

```text
FeaturePackageTemplates/reports.json
```

The feature package manager returns `ReportsModule` for `.reports`, using the same dependency injection path as existing modules. `ReportsModule` receives `FeatureWorkspaceContext`, then wires:

- `apiGateway`
- `credentialsStore`
- `diagnosticsReporter`

## File Map

### Module Entrypoint

```text
JamfDashboardApp/Modules/Reports/ReportsModule.swift
JamfDashboardApp/Modules/Reports/ReportsDiscoveryNotes.md
```

### Models

```text
JamfDashboardApp/Modules/Reports/Models/ReportAggregate.swift
JamfDashboardApp/Modules/Reports/Models/ReportCoreModels.swift
JamfDashboardApp/Modules/Reports/Models/ReportCriteriaModels.swift
JamfDashboardApp/Modules/Reports/Models/ReportsFieldCatalog.swift
```

Key model responsibilities:

- `ReportDeviceRecord`: normalized report row used by aggregation, report building, and export.
- `ReportDeviceIdentity`: normalized device identity and inferred type.
- `ReportAggregate`: total counts, type buckets, gauge segments, and inferred record count.
- `ReportRequest`: report name, domain, criteria, grouping, chart preference, and requested fields.
- `GeneratedReport`: report result object consumed by visualization and export.
- `ReportsFieldCatalog`: reportable field definitions and lookup metadata.

### Services

```text
JamfDashboardApp/Modules/Reports/Services/ReportDeviceIdentityResolver.swift
JamfDashboardApp/Modules/Reports/Services/ReportsAggregator.swift
JamfDashboardApp/Modules/Reports/Services/ReportsInventoryService.swift
JamfDashboardApp/Modules/Reports/Services/ReportsPaginationPolicy.swift
JamfDashboardApp/Modules/Reports/Services/ReportsQueryPlanner.swift
```

Key service responsibilities:

- `ReportsInventoryService`: loads computer and mobile inventory pages through `JamfAPIGateway`.
- `ReportDeviceIdentityResolver`: resolves device type and identity confidence from domain, model, model identifier, and platform hints.
- `ReportsAggregator`: computes default counts and gauge data.
- `ReportsQueryPlanner`: validates criteria and separates server-filterable logic from client-side filtering.
- `ReportsPaginationPolicy`: central page-size and stop-condition policy for Jamf inventory reads.

### Rendering

```text
JamfDashboardApp/Modules/Reports/Rendering/ReportsChartPalette.swift
JamfDashboardApp/Modules/Reports/Rendering/ReportsDeviceTypeGaugeFallbackView.swift
JamfDashboardApp/Modules/Reports/Rendering/ReportsDeviceTypeGaugeRenderer.swift
JamfDashboardApp/Modules/Reports/Rendering/ReportsDeviceTypeGaugeView.swift
JamfDashboardApp/Modules/Reports/Rendering/ReportsVisualizationSnapshotRenderer.swift
```

Rendering notes:

- `ReportsDeviceTypeGaugeView` chooses Metal rendering when available.
- `ReportsDeviceTypeGaugeRenderer` owns the `MTKViewDelegate` implementation.
- `ReportsDeviceTypeGaugeFallbackView` provides native SwiftUI rendering when Metal is unavailable.
- `ReportsVisualizationSnapshotRenderer` renders static gauge imagery for DOC and PDF exports.

### Export

```text
JamfDashboardApp/Modules/Reports/Export/ReportCSVRenderer.swift
JamfDashboardApp/Modules/Reports/Export/ReportDocRenderer.swift
JamfDashboardApp/Modules/Reports/Export/ReportExportCoordinator.swift
JamfDashboardApp/Modules/Reports/Export/ReportExportDocument.swift
JamfDashboardApp/Modules/Reports/Export/ReportExportFilenameBuilder.swift
JamfDashboardApp/Modules/Reports/Export/ReportExportFormat.swift
JamfDashboardApp/Modules/Reports/Export/ReportMarkdownRenderer.swift
JamfDashboardApp/Modules/Reports/Export/ReportPDFRenderer.swift
JamfDashboardApp/Modules/Reports/Export/ReportTextRenderer.swift
```

Export notes:

- CSV uses explicit escaping for commas, quotes, and newlines.
- TXT and Markdown provide readable structured text output.
- DOC export is HTML-based and Word-readable.
- PDF export uses Core Graphics and includes rendered visual report aids.
- Export file names are sanitized and timestamped.

### View Model

```text
JamfDashboardApp/Modules/Reports/ViewModels/ReportsViewModel.swift
```

View model responsibilities:

- Initial module refresh.
- Inventory load coordination.
- Default count aggregation.
- Report request validation and execution.
- Export payload preparation.
- Export completion tracking.
- User-facing error state.

### Views

```text
JamfDashboardApp/Modules/Reports/Views/GeneratedReportView.swift
JamfDashboardApp/Modules/Reports/Views/ReportBuilderView.swift
JamfDashboardApp/Modules/Reports/Views/ReportVisualizationViews.swift
JamfDashboardApp/Modules/Reports/Views/ReportsView.swift
```

View responsibilities:

- `ReportsView`: module landing page, refresh action, gauge, device-type summary, and report builder entry.
- `ReportBuilderView`: criteria builder, grouping, chart preference, and report execution controls.
- `GeneratedReportView`: report display and export workflow.
- `ReportVisualizationViews`: reusable visual panels for report pages.

## Jamf API Behavior

### Computer Inventory

The computer path reads paginated computer inventory data through the shared gateway. Endpoint selection uses fallback handling so tenants with different Jamf Pro versions or privilege scopes still have a chance to return data.

Expected behavior:

- Page size defaults to `200`.
- Pagination stops when Jamf reports no more records, a short page is returned, total count is reached, or the safety cap is reached.
- Computer records are normalized into `ReportDeviceRecord`.
- Computer records default to Mac classification unless Jamf data indicates otherwise.

### Mobile Inventory

The mobile path reads mobile device inventory data through the shared gateway, including fallback section behavior.

Expected behavior:

- Page size defaults to `200`.
- Mobile detail reads try modern section names, legacy section names, then no-section fallback where needed.
- Device type uses model identifier lookup first when available.
- iPad and iPhone classification should be reliable for known Apple identifiers.
- Ambiguous mobile records fall back to Other or Unknown with confidence metadata.

### Diagnostics

Reports inventory loading emits diagnostics for:

- Load start.
- Load completion.
- Page-level activity.
- Endpoint fallback failures.
- Parsing or request errors.

Diagnostics use the existing centralized diagnostics pipeline.

## Device Type Classification

Device type output values:

```text
Mac
iPad
iPhone
Other
Unknown
```

Classification inputs:

- Inventory domain.
- Jamf model string.
- Jamf model identifier.
- Platform hint.
- Local Apple device model catalog lookup.

Confidence values:

```text
catalog
payload
domain
unknown
```

Expected examples:

- Computer domain with no extra model data resolves to Mac.
- `iPad14,5` resolves to iPad.
- `iPhone17,3` resolves to iPhone.
- `Apple TV` resolves to Other.
- Empty or contradictory values may resolve to Unknown.

## Report Builder Behavior

The report builder supports:

- Report name.
- Inventory domain selection.
- Grouping field selection.
- Chart preference selection.
- Criteria rows using typed field metadata.
- Operators constrained by field data type.
- Report execution once validation passes.

Supported comparison families include:

- Text comparisons.
- Numeric comparisons.
- Boolean comparisons.
- Contains, starts-with, and ends-with logic where appropriate.
- Empty and non-empty checks where appropriate.

Server-filterable criteria are composed into Jamf-compatible RSQL where safe. Criteria that require local interpretation remain client-side.

## Export Behavior

Supported formats:

```text
.csv
.txt
.md
.doc
.pdf
```

Export workflow:

1. User opens a visual report page.
2. User selects an export format.
3. `ReportsViewModel` prepares a `ReportExportPayload`.
4. `ReportExportCoordinator` selects the renderer.
5. The SwiftUI file exporter presents the save destination.

Expected export content:

- Report title.
- Export timestamp.
- Summary totals.
- Device-type distribution.
- Grouped counts where applicable.
- Matching records.
- Visual gauge aid for DOC and PDF.

The DOC output is intentionally Word-readable rich HTML with a `.doc` extension, not `.docx`.

## Version and Documentation Updates

Version values now use `3.21.0`:

```text
VERSION
Jamf Dashboard.xcodeproj/project.pbxproj
```

Documentation updated:

```text
README.md
WIKI.md
CHANGELOG.md
```

Project package template updated:

```text
FeaturePackageTemplates/reports.json
```

## Automated Test Coverage

Reports tests live in:

```text
JamfDashboardAppTests/ReportsModuleTests.swift
```

Covered areas:

- Device type classification from domain, model, and model identifier.
- Apple catalog-backed identity resolution.
- Aggregation counts for Mac, iPad, iPhone, Other, Unknown, and Total.
- Inferred record counting.
- Query planner server filter selection.
- Query planner client criteria routing.
- Pagination stop conditions.
- CSV escaping.
- TXT, Markdown, DOC, and PDF renderer smoke output.
- Export file name sanitation.
- Export output scan for blocked authorship wording.

Full suite status from local verification:

```text
96 tests executed
0 failures
```

## Build and Test Commands

Run from the project root:

```sh
cd "/Users/jimdaley/Documents/Jamf Dashboard/Projects/Jamf-Dashboard-main"
```

List project schemes:

```sh
xcodebuild -list -project "Jamf Dashboard.xcodeproj"
```

Run the full test suite without signing:

```sh
xcodebuild -project "Jamf Dashboard.xcodeproj" \
  -scheme "Jamf Dashboard" \
  -destination 'platform=macOS' \
  CODE_SIGNING_ALLOWED=NO \
  test
```

Build without signing:

```sh
xcodebuild -project "Jamf Dashboard.xcodeproj" \
  -scheme "Jamf Dashboard" \
  -destination 'platform=macOS' \
  CODE_SIGNING_ALLOWED=NO \
  build
```

Run only Reports tests:

```sh
xcodebuild -project "Jamf Dashboard.xcodeproj" \
  -scheme "Jamf Dashboard" \
  -destination 'platform=macOS' \
  CODE_SIGNING_ALLOWED=NO \
  test \
  -only-testing:JamfDashboardAppTests/ReportsModuleTests
```

Run the prior crash-focused test:

```sh
xcodebuild -project "Jamf Dashboard.xcodeproj" \
  -scheme "Jamf Dashboard" \
  -destination 'platform=macOS' \
  CODE_SIGNING_ALLOWED=NO \
  test \
  -only-testing:JamfDashboardAppTests/ReportsModuleTests/test_identityResolverMarksCatalogResolvedValues
```

## Signing Constraint

The signing-disabled build and test commands pass locally.

Normal signed macOS build currently fails in this local environment because the required signing identity is unavailable:

```text
No signing certificate "Mac Development" found for team ID "2Y25RTLZET"
```

Build team action:

- Install or select a valid Mac Development certificate for team `2Y25RTLZET`.
- Re-run the normal signed build after the signing identity is present.

## Manual QA Checklist

### Module Availability

1. Launch the app.
2. Verify Reports appears on the dashboard with the bundled default modules.
3. Open Settings.
4. Open Feature Packages.
5. Verify Reports appears as a bundled default package.
6. Verify Reports cannot be removed if protected defaults are enforced in the UI.

Expected result:

- Reports is visible and opens successfully.
- Existing bundled modules remain visible.
- Existing feature package workflows still work.

### Initial Reports Load

1. Configure valid Jamf Pro credentials.
2. Open Reports.
3. Trigger refresh.
4. Wait for inventory loading to complete.

Expected result:

- Total count is shown.
- Mac, iPad, iPhone, Other, and Unknown counts are shown.
- The segmented gauge renders.
- Empty tenants or restricted roles show a clear error or zero-state message without a crash.
- Diagnostics include Reports load events.

### Device Type Accuracy

Use a tenant with known mixed inventory:

- Macs.
- iPads.
- iPhones.
- At least one non-iPad/iPhone mobile device if available.
- At least one record with missing or unusual model data if available.

Expected result:

- Macs count under Mac.
- iPads count under iPad.
- iPhones count under iPhone.
- Non-iPad/iPhone records count under Other.
- Ambiguous records count under Unknown.
- Total equals the sum of all type buckets.

### Gauge Rendering

Run on hardware with Metal available:

1. Open Reports.
2. Confirm the segmented gauge renders with visible segments.
3. Resize the window if testing on macOS.
4. Navigate into a report page and confirm visual aids remain stable.

Fallback check:

- Use an environment where Metal is unavailable or force the fallback path during development review.
- Confirm the SwiftUI fallback gauge renders equivalent segment proportions.

Expected result:

- No blank gauge.
- No overlapping labels.
- Segment proportions match count distribution.
- Gauge remains stable during refresh.

### Report Builder

1. Open Reports.
2. Open New Report.
3. Enter a report name.
4. Select an inventory domain.
5. Add criteria using text, numeric, and boolean fields where data is available.
6. Select a grouping field.
7. Select a chart preference.
8. Run the report.

Expected result:

- Invalid criteria are blocked with a clear validation message.
- Valid criteria run successfully.
- Report results match the selected domain and filters.
- Group counts align with matching records.
- Report page opens after execution.

### Export Workflow

For the same report, export each format:

```text
CSV
TXT
Markdown
DOC
PDF
```

Expected result:

- File exporter opens.
- Suggested file names are sanitized.
- CSV opens in Numbers or Excel with valid columns.
- TXT is readable and includes summary counts.
- Markdown renders with tables and summary sections.
- DOC opens in Word or Pages and includes visual aids.
- PDF opens in Preview and includes visual aids.
- Exported records match the on-screen report.

### Restricted Privilege Tenant

Use a Jamf role with limited inventory privileges:

1. Open Reports.
2. Refresh inventory.
3. Build a simple report.

Expected result:

- Endpoint fallback behavior is visible in diagnostics when needed.
- Privilege failures do not crash the app.
- User-facing errors remain actionable.

### Large Tenant

Use a tenant with more than 200 devices:

1. Open Reports.
2. Refresh inventory.
3. Confirm pagination completes.
4. Build a report with grouping.
5. Export PDF and CSV.

Expected result:

- Pagination continues beyond page 0.
- Safety cap is not hit under expected fleet size.
- UI remains responsive.
- Counts match Jamf inventory expectations.
- Exports complete within acceptable time.

## Regression Checklist

Validate existing modules after Reports registration:

- Computer Search opens and searches.
- Mobile Device Search opens and searches.
- Support Technician opens and searches.
- Prestage Director opens and loads pre-stage data.
- Settings opens.
- Jamf Credentials verify and save workflow still works.
- Diagnostics export still works.
- Feature Package install/import view still works.

## Known Risks and Focus Areas

### Jamf Payload Shape Variation

Jamf Pro tenants may return inventory payloads with different field placement or section availability. The Reports service uses tolerant JSON parsing and endpoint fallback, but QA should test against more than one Jamf tenant if possible.

### Privilege-Scoped Fields

Some report fields may be absent for restricted roles. Missing fields should display as empty or Unknown, not fail report execution.

### Device Identity Ambiguity

Unknown or newly released Apple model identifiers depend on local catalog coverage. Records with model identifiers not present in the catalog should still classify through domain and payload fallback where possible.

### Export Visual Fidelity

PDF and DOC visual aids are rendered separately from the live SwiftUI view. QA should compare on-screen gauge proportions against exported visual aid proportions.

### Signing

Signed build validation depends on local certificate setup. The current local blocker is certificate availability, not compile failure.

## Verification Already Completed

The following commands were run locally from the project root.

Full tests:

```sh
xcodebuild -project "Jamf Dashboard.xcodeproj" \
  -scheme "Jamf Dashboard" \
  -destination 'platform=macOS' \
  CODE_SIGNING_ALLOWED=NO \
  test
```

Result:

```text
TEST SUCCEEDED
96 tests executed
0 failures
```

Signing-disabled build:

```sh
xcodebuild -project "Jamf Dashboard.xcodeproj" \
  -scheme "Jamf Dashboard" \
  -destination 'platform=macOS' \
  CODE_SIGNING_ALLOWED=NO \
  build
```

Result:

```text
BUILD SUCCEEDED
```

Normal signed build:

```sh
xcodebuild -project "Jamf Dashboard.xcodeproj" \
  -scheme "Jamf Dashboard" \
  -destination 'platform=macOS' \
  build
```

Result:

```text
BUILD FAILED
No signing certificate "Mac Development" found for team ID "2Y25RTLZET"
```

## Handoff Notes

- The folder is not currently a Git repository, so no local commit hash or diff summary is available from `git status`.
- No remote push was performed.
- Testers should use the Xcode project directly at the path listed above.
- Use signing-disabled commands for compile and unit test verification until the correct signing identity is installed.
- Use a real Jamf Pro tenant for full manual QA because inventory counts, endpoint fallback, and privilege behavior depend on tenant data and role permissions.
