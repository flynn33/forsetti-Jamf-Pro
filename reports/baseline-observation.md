# Forsetti 3.24 Baseline Observation

## Source Roots

| Source | Location | Version |
|---|---|---|
| 3.23 reference | `/tmp/forsetti-rebase/3.23-reference/Jamf-Dashboard-main` | 3.23.0 |
| 3.24 sanitized baseline | `/tmp/forsetti-rebase/3.24-sanitized/Jamf-Dashboard-Sanitized-3.24.0` | 3.24.0 |
| Current retail snapshot | `/tmp/forsetti-rebase/current-retail-snapshot` | 3.23.2 |
| Current retail worktree | `/Volumes/NVME/GitHub/Forsetti-Jamf-Pro` | 3.23.2 |

## Raw Diff Reports

| Report | Lines | Purpose |
|---|---:|---|
| `reports/current-retail-vs-3.23.diff.txt` | 41 | Identifies current retail renames, UI work, governance gates, and sanitation deltas over 3.23.0. |
| `reports/3.24-vs-3.23.diff.txt` | 65 | Identifies sanitized baseline deltas over 3.23.0. |
| `reports/final-retail-vs-3.24.diff.txt` | 43 | Tracks current retail differences from the sanitized 3.24.0 source baseline before implementation. |

## Observed Source Map

The current retail tree uses `ForsettiApp`, `ForsettiTests`, and `Forsetti.xcodeproj`. The baseline archives use `JamfDashboardApp`, `JamfDashboardAppTests`, and `Jamf Dashboard.xcodeproj`.

The current retail tree has 168 Swift app files. Both baseline trees have 162 Swift app files. The extra current files are retail UI and governance work that must be preserved unless a direct product-behavior conflict is found.

## 3.24 Baseline Findings

The sanitized 3.24.0 archive sets `VERSION` to `3.24.0` and replaces the legacy branded design-system names with Forsetti names. Its Computer Search file set is the same shape as the 3.23.0 reference:

- `ComputerSearchModule.swift`
- `Models/ComputerField.swift`
- `Models/ComputerRecord.swift`
- `Models/ComputerSearchProfile.swift`
- `Persistence/ComputerSearchProfileStore.swift`
- `ViewModels/ComputerSearchViewModel.swift`
- `Views/ComputerFieldCatalogView.swift`
- `Views/ComputerSearchView.swift`

The direct 3.24-vs-3.23 Computer Search source diff shows theme-symbol changes in `ComputerFieldCatalogView.swift` and `ComputerSearchView.swift`; it does not add advanced search, smart filters, computer detail navigation, hardware cards, or extension-attribute metadata loading.

## Current Retail Findings

Current retail already includes:

- Forsetti naming and app identity.
- Obsidian/cyan retail shell and glass/metal UI.
- Module-level governance checks for source-marker and customer residue.
- Paginated Computer Search inventory requests across v3, v2, and v1 endpoints.
- PreStage enrichment for Computer Search results.
- Existing static gates pass the package heuristic checks.

Current retail still needs:

- Version metadata alignment to 3.24.0.
- Computer Search parity work beyond the sanitized baseline: advanced query composition, smart-filter persistence, detail navigation, hardware presentation, and extension-attribute metadata support or documented equivalents.
- Final architecture justification for existing app-owned UI files under `ForsettiApp/Framework/UI`, or a scoped move if that is safer.

## Initial Static Gate Result

The package gate script completed successfully against the current tree. It reported:

- Sanitized baseline version check passed.
- Forbidden legacy branding scan passed.
- Computer Search heuristic indicators were detected.
- Framework compliance heuristic warned that app-specific UI markers appear in `ForsettiApp/Framework/UI` and `ForsettiApp/Framework/Scanning`.

The warning is non-failing but must be handled in the final compliance report.
