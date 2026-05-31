# Forsetti 3.24 Rebase Implementation Plan

## Goal

Align the retail app with the sanitized 3.24.0 baseline, preserve the completed Forsetti UI direction, and close the Computer Search parity gap that the sanitized baseline does not actually provide.

## Merge Rules

| Area | Rule |
|---|---|
| Product version metadata | Prefer sanitized 3.24.0. |
| Product behavior and API correctness | Prefer 3.24.0 requirements and Jamf API research. |
| Retail UI and theme | Preserve current Forsetti UI unless product logic requires a targeted merge. |
| Branding and sanitation | Forsetti-neutral only. |
| Framework boundaries | Use app-owned UI and existing framework service contracts. |

## Tasks

### Task 1: Version Metadata

Files:
- `VERSION`
- `Forsetti.xcodeproj/project.pbxproj`

Steps:
1. Update `VERSION`, `CURRENT_PROJECT_VERSION`, and `MARKETING_VERSION` from 3.23.2 to 3.24.0.
2. Run the package static gate and the local source-marker guard.

### Task 2: Computer Search Data Parity Tests

Files:
- `ForsettiTests/ComputerSearchParityTests.swift`
- `ForsettiApp/Modules/ComputerSearch/Models/ComputerRecord.swift`
- `ForsettiApp/Modules/ComputerSearch/Models/ComputerField.swift`

Steps:
1. Add failing tests proving `ComputerRecord` exposes dynamic field values for selected catalog fields.
2. Add failing tests proving extension-attribute values decode into dynamic field lookups.
3. Add failing tests proving hardware summary fields are available for a detail card.
4. Implement the smallest model changes needed to pass.

### Task 3: Computer Advanced Search Composition

Files:
- `ForsettiTests/ComputerSearchParityTests.swift`
- `ForsettiApp/Modules/ComputerSearch/Models/ComputerField.swift`
- `ForsettiApp/Framework/Networking/JamfRSQLComposer.swift`
- `ForsettiApp/Modules/ComputerSearch/ViewModels/ComputerSearchViewModel.swift`

Steps:
1. Add failing tests for composing server-side computer RSQL from typed advanced criteria.
2. Add field metadata needed by the composer: data type, filterable flag, server-filterable flag, and response paths.
3. Add a computer compose path without disrupting the existing mobile compose path.
4. Add an advanced-search execution path in `ComputerSearchViewModel` that sends raw RSQL through the existing paginated request pipeline.

### Task 4: Computer Search Smart Filters and UI Entry

Files:
- `ForsettiApp/Modules/ComputerSearch/Models/ComputerSearchProfile.swift`
- `ForsettiApp/Modules/ComputerSearch/Persistence/ComputerSearchProfileStore.swift`
- `ForsettiApp/Modules/ComputerSearch/ViewModels/ComputerSearchViewModel.swift`
- `ForsettiApp/Modules/ComputerSearch/Views/ComputerSearchView.swift`

Steps:
1. Add failing tests for saving and loading a computer smart filter.
2. Reuse the existing advanced query model for computer filters.
3. Add a Computer Search `Advanced` entry and smart-filter section using the current Forsetti button and list styling.

### Task 5: Computer Detail and Hardware Presentation

Files:
- `ForsettiApp/Modules/ComputerSearch/Views/ComputerSearchView.swift`
- `ForsettiApp/Modules/ComputerSearch/Views/ComputerDetailView.swift`
- `ForsettiApp/Modules/ComputerSearch/Views/ComputerHardwareInfoCard.swift`
- `ForsettiApp/Modules/ComputerSearch/ViewModels/ComputerSearchViewModel.swift`

Steps:
1. Add a typed computer detail route.
2. Add a detail view that reuses the selected record and renders hardware, identity, user, location, and extension-attribute details.
3. Add a targeted hardware refresh if a safe endpoint is already available; otherwise document the current list-response detail behavior as the first 3.24-compatible pass.
4. Preserve the current Forsetti list styling and dark retail surface.

### Task 6: Reports and Gates

Files:
- `reports/computer-search-3.24-parity-report.md`
- `reports/ui-preservation-report.md`
- `reports/static-gates-output.txt`
- `reports/build-output.txt`
- `reports/test-output.txt`
- `reports/screenshots/`
- `reports/final-3.24-rebase-report.md`

Steps:
1. Run the package static gates and write sanitized output.
2. Run focused tests, then full Xcode tests.
3. Launch the app and capture required screenshots.
4. Write final parity, UI preservation, compliance, sanitation, and diff summaries.

## Verification Order

1. Focused Computer Search parity tests.
2. Package static gates.
3. Local source-marker guard.
4. Full Xcode test suite.
5. App launch and screenshot pass.
6. Final PR checks and review-thread audit.
