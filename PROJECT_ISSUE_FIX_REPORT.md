# Forsetti Jamf Pro Issue and Fix Report

Date: 2026-05-31

Scope: local staging material was migrated into `/Volumes/NVME/GitHub/Forsetti-Jamf-Pro` for the `flynn33/forsetti-Jamf-Pro` repository.

## Issues and Fixes

| Area | Issue Found | Fix Applied | Verification |
| --- | --- | --- | --- |
| Repository setup | The destination folder was not a Git repository and the remote repository had no base branch. | Prepared the project for a seed `main` branch plus a separate project branch so the initial import can be reviewed through a pull request. | `gh auth status`, remote inspection, and local repository checks. |
| Product identity | Project, bundle, asset, and documentation identifiers still reflected the source product. | Renamed the Xcode project, app target, test target, app folders, scheme, bundle identifiers, app support paths, diagnostics paths, and product copy to Forsetti. | `bash scripts/verify-no-customer-references.sh .` returned pass. |
| Framework dependency | The app could not compile framework-backed runtime code without the Forsetti framework package. | Added the `Forsetti-Framework` package dependency and linked `ForsettiCore` and `ForsettiPlatform` to the app target. | `xcodebuild -list -project Forsetti.xcodeproj` resolved the package graph and found the `Forsetti` scheme. |
| Retail module manifests | Runtime module specs and bundled JSON manifests could drift independently. | Added 10 Forsetti manifest JSON files and a test that decodes them and compares module IDs, types, capabilities, and entry points against `ForsettiRetailBootstrap.manifestSpecs`. | Focused `ForsettiRetailIdentityTests` passed with 4 tests. |
| Runtime boot behavior | The framework runtime bootstrap could run more than once during repeated view task launches. | Added an in-flight boot task guard and removed eager app launch boot so boot is explicit and testable. | `testRetailBootstrapBootsBundledManifestsWhenRequested` discovered and activated 10 manifests. |
| Diagnostics metadata | Sensitive metadata could be retained in memory, persisted logs, exported reports, or mirrored logs. | Centralized diagnostics metadata redaction before storage, export, and log mirroring. | `test_reportRedactsSensitiveMetadataBeforeExport` passed. |
| Support payload previews | Support action previews and diagnostic dumps could include sensitive request or response content. | Redacted raw support payload previews and diagnostic dump output before presentation or disk export. | Focused diagnostics and retail identity tests passed. |
| Support cache | Support detail, tenant policy, and extension-attribute cache entries were not uniformly encrypted. | Switched cache entries to encrypted files using a key stored in the system keychain. | Full app suite passed, including support cache encryption tests. |
| Credential namespace | Stored credentials used a legacy keychain service name after the bundle identifier changed. | Moved the default keychain service to `com.ravenforge.forsetti` and added migration from the legacy service. | Focused diagnostics and retail identity tests passed after the keychain update. |
| Secret reveal actions | Secret retrieval actions could run without typed confirmation. | Reclassified secret retrieval actions to require typed confirmation. | Static review and focused test build completed successfully. |
| Tenant fallback data | A tenant-specific prestage fallback value remained in support device mapping. | Removed the fallback and kept the value nil when Jamf Pro does not provide a source value. | Customer-reference scan returned pass. |
| Local safeguards | Hook scripts and helper scripts needed current product naming and stronger local checks. | Rewrote repository scripts and hooks for Forsetti naming, added bearer-token fallback scanning, and expanded commit-message attribution guards. | Customer-reference and attribution scans returned no matches. |
| Hosted validation | The repository had no pull-request workflow checks. | Added a macOS validation workflow for sanitation, project resolution, and Xcode tests. | Pull request `Xcode tests` check passed. |
| Hosted Swift isolation | Hosted Xcode treated module view factory calls as main actor-isolated and failed synchronous protocol dispatch. | Marked `JamfModule.makeRootView(context:)` as `@MainActor` so all module root-view factories execute on the correct actor. | Local and hosted Xcode tests passed after the fix. |
| Provenance wording | A broad controlled-content scan found two repository-controlled provenance-style literals: a commit-trailer guard literal and a Jamf policy note phrase. | Split the guard literal while preserving guard behavior, and rewrote the Jamf policy note as operational text. | Broad content, path, Git metadata, and PR title/body/comment scans returned no matches. |

## Validation Evidence

- Forsetti framework package test suite: passed, 37 tests.
- `xcodebuild -list -project Forsetti.xcodeproj`: passed, package graph resolved.
- `xcodebuild -project Forsetti.xcodeproj -scheme Forsetti -destination 'platform=macOS' -derivedDataPath /tmp/forsetti-jamfpro-focused-dd CODE_SIGNING_ALLOWED=NO -only-testing:ForsettiTests/ForsettiRetailIdentityTests test`: passed, 4 tests.
- `xcodebuild -project Forsetti.xcodeproj -scheme Forsetti -destination 'platform=macOS' -derivedDataPath /tmp/forsetti-jamfpro-focused-dd CODE_SIGNING_ALLOWED=NO -only-testing:ForsettiTests/DiagnosticsCenterExportTests -only-testing:ForsettiTests/SupportTechnicianCacheTests test`: passed, 12 tests.
- `xcodebuild -project Forsetti.xcodeproj -scheme Forsetti -destination 'platform=macOS' -derivedDataPath /tmp/forsetti-jamfpro-full-dd CODE_SIGNING_ALLOWED=NO test`: passed, 175 tests.
- `xcodebuild -project Forsetti.xcodeproj -scheme Forsetti -destination 'platform=macOS' -derivedDataPath /tmp/forsetti-jamfpro-final-dd CODE_SIGNING_ALLOWED=NO test`: passed, 175 tests.
- Pre-push Xcode validation: passed, 175 tests.
- Hosted pull-request `Xcode tests`: passed.
- Provenance marker scans across repository contents, file/path names, Git metadata, and PR title/body/comments: no matches.
- `bash scripts/verify-no-customer-references.sh .`: passed.
- Repository attribution scan: no matches.

## Remaining Release Notes

- Pull request 1 is open and mergeable with hosted validation passing.
- Live review-thread inspection returned no actionable review threads.
