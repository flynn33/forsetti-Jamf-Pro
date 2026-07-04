# Temporary Admin Elevation — Implementation Report

## Summary

```text
Feature implemented: Temporary Admin Elevation (Support Technician, Mac-only)
Target version:      3.26.0 (feature bump from 3.25.7)
Branch:              feature/temporary-admin-elevation
Date:                2026-06-14
```

A technician can request a bounded, audited local-administrator elevation for the **current macOS console user** on a selected managed Mac (durations 5 / 15 / 30 / 60 minutes, a required reason, an optionally-required ticket reference). The app never creates Jamf policies or scripts dynamically — it changes the Mac's membership in a **pre-created dedicated request scope** (static computer group); a pre-created policy runs the elevation script at next check-in; the Mac demotes the user automatically when the timer expires; and status is read back through five Computer Extension Attributes. The frame is Mac-only and ships **disabled by default** until a Jamf administrator configures the dedicated request-group IDs.

## Files added

```text
JamfDashboardApp/Modules/SupportTechnician/Models/TemporaryAdminElevationModels.swift
JamfDashboardApp/Modules/SupportTechnician/Models/TemporaryAdminElevationSnapshotParser.swift
JamfDashboardApp/Modules/SupportTechnician/Models/TemporaryAdminUserFacingError+Mapping.swift
JamfDashboardApp/Modules/SupportTechnician/Services/TemporaryAdminElevationService.swift
JamfDashboardApp/Modules/SupportTechnician/ViewModels/TemporaryAdminElevationController.swift
JamfDashboardApp/Modules/SupportTechnician/Views/Frames/TemporaryAdminElevationFrame.swift
JamfDashboardApp/Framework/Networking/JamfComputerRequestScopeService.swift
JamfDashboardAppTests/TemporaryAdminElevationModelTests.swift
JamfDashboardAppTests/TemporaryAdminElevationServiceTests.swift
JamfDashboardAppTests/TemporaryAdminElevationViewModelTests.swift
JamfDashboardAppTests/TemporaryAdminElevationLayoutTests.swift
JamfDashboardAppTests/TemporaryAdminElevationArchitectureTests.swift
JamfDashboardAppTests/TemporaryAdminTestSupport.swift
scripts/jamf/temporary-admin/temporary-admin-elevate.zsh
scripts/jamf/temporary-admin/temporary-admin-demote-now.zsh
scripts/jamf/temporary-admin/ea-temporary-admin-status.zsh
scripts/jamf/temporary-admin/ea-temporary-admin-user.zsh
scripts/jamf/temporary-admin/ea-temporary-admin-expires-at.zsh
scripts/jamf/temporary-admin/ea-temporary-admin-last-change.zsh
scripts/jamf/temporary-admin/ea-temporary-admin-run-id.zsh
scripts/jamf/temporary-admin/README.md
```

## Files modified

```text
JamfDashboardApp/Modules/SupportTechnician/ViewModels/SupportTechnicianViewModel.swift   (owns the controller; builds the service)
JamfDashboardApp/Modules/SupportTechnician/Views/SupportTechnicianView.swift             (renders the Mac-only frame + configure/stop lifecycle)
JamfDashboardApp/Modules/PermissionsMatrix/Resources/jamf_dashboard_permissions_matrix.v4.module_resource.json (new action entry; count 86 → 87)
JamfDashboardAppTests/PermissionsMatrixTests.swift                                        (action-count assertion 86 → 87)
FeaturePackageTemplates/support-technician.json                                            (backward-compatible disabled temporaryAdminElevation block)
README.md, WIKI.md, CHANGELOG.md, VERSION, Jamf Dashboard.xcodeproj/project.pbxproj       (version 3.26.0 + docs)
```

Note: `SupportTechnicianModule.swift` was not modified — its `makeRootView(context:)` is unchanged; the feature wiring lives entirely in `SupportTechnicianViewModel`, which the module already builds from `FeatureWorkspaceContext`. No new registry or module entry point was added.

## Architecture contracts preserved

```text
[x] Uses FeatureWorkspaceContext                         (view model built in SupportTechnicianModule.makeRootView from FeatureWorkspaceContext)
[x] Uses JamfAPIGateway                         (request-scope writes via JamfComputerRequestScopeServicing → gateway; inventory via SupportTechnicianAPIService)
[x] Uses existing auth service                  (gateway handles tokens; feature adds none)
[x] Uses existing Keychain-backed credentials   (gateway/credentials store unchanged)
[x] Uses DiagnosticsCenter                      (via the existing DiagnosticsReporting reporter)
[x] Does not create a separate Jamf client      (no URLSession in any feature file — enforced by architecture test)
[x] Does not create a separate credential store
[x] Does not create a separate auth flow
[x] Does not create a separate diagnostics system
[x] Does not dynamically create Jamf policies or scripts (no policy/script endpoints in feature files — enforced by architecture test)
```

## Tenant setup required

```text
Request groups (static computer groups):
  - Jamf Dashboard - Temp Admin Requests - 5m / 15m / 30m / 60m
  - Jamf Dashboard - Temp Admin Demote Now
Policies (Recurring Check-in, Ongoing, scoped to the matching request group; parameter 4 = duration):
  - Jamf Dashboard - Temporary Admin Elevate - 5 / 15 / 30 / 60 Minutes
  - Jamf Dashboard - Temporary Admin Demote Now
Scripts: scripts/jamf/temporary-admin/temporary-admin-elevate.zsh, temporary-admin-demote-now.zsh
Extension Attributes (Script, String): Status, User, Expires At, Last Change, Run ID
  (scripts/jamf/temporary-admin/ea-temporary-admin-*.zsh)
Required normal-use privileges:
  - Read Computers; Read Computer Extension Attributes;
    Read Static Computer Groups; Update Static Computer Groups (or tenant request-scope equivalents)
  - Optional diagnostics: Read API Roles
Setup-only privileges (administrator):
  - Create/Update Computer Extension Attributes, Scripts, Policies, Static Computer Groups
Configuration: record the request-group IDs in FeaturePackageTemplates/support-technician.json → temporaryAdminElevation.
```

## Tests added or updated

```text
Added (6 files, 56 tests): model/config/validation/parser/error-mapping (20), service request/poll/timeout/cleanup/demote/duplicate
+ request-scope read-modify-write (14), controller/view-model (8), presentation/layout/Reduce-Motion (9), architecture guardrails (6),
shared mocks/fixtures (TemporaryAdminTestSupport).
Updated: PermissionsMatrixTests action-count assertion (86 → 87).
```

## Verification results

```text
macOS build:            ** BUILD SUCCEEDED **
macOS tests:            Executed 401 tests, with 0 failures (0 unexpected)   [345 pre-existing + 56 new]
iOS Simulator build:    ** BUILD SUCCEEDED ** (iphonesimulator SDK — covers iPhone + iPad)
iPad:                   covered by the iphonesimulator build; adaptive layout also covered by deterministic layout/presentation unit tests
Test bundle platform:   macOS-only (SUPPORTED_PLATFORMS = macosx) — the platform-agnostic feature logic runs there
Commands:
  xcodebuild test  -project "Jamf Dashboard.xcodeproj" -scheme "Jamf Dashboard" -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY=""
  xcodebuild build -project "Jamf Dashboard.xcodeproj" -scheme "Jamf Dashboard" -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO
manual smoke test:      NOT PERFORMED — blocker documented below.
```

### Manual smoke test — blocker

A live end-to-end smoke test (request 5-minute elevation on a real managed Mac, confirm the Mac joins the request group, runs the policy, elevates, reports `elevated`, the app removes it from the group, auto-demotion at expiry, demote-now, missing-privilege, and offline-timeout paths) **was not performed**: it requires a live Jamf Pro tenant with the pre-created request groups/policies/scripts/extension attributes and an enrolled test Mac, none of which are available in this environment. The feature ships disabled until those objects are configured. All logic paths are covered by the automated service/parser/controller/architecture tests; the live drill in `docs/08-tests-and-acceptance.md` should be run once a configured test tenant is available.

## Known limitations

```text
- Mac only — no iPhone/iPad elevation (frame is not rendered for mobile devices).
- Current macOS console user only — no arbitrary username entry.
- Requires the Mac to check in with Jamf Pro before the policy can run.
- Extension attributes update only after an inventory update (jamf recon).
- Requires pre-created Jamf tenant objects; disabled until their IDs are configured.
- Does not grant permanent admin, and does not change Jamf Pro privileges, Secure Token, Bootstrap Token, FileVault recovery access, or local passwords.
- The static-group update endpoint (PUT /api/v2/computer-groups/static-groups/{id}) is documented as deprecated; it is isolated behind JamfComputerRequestScopeServicing and should be verified/adapted per tenant.
```

## Rollback notes

```text
App: disable the feature in the Support Technician configuration; remove all Macs from the temp-admin request groups; leave diagnostics + extension attributes intact for audit.
Jamf: clear membership of all temp-admin request groups; disable the temp-admin policies; confirm no policy is scoped to production devices outside the dedicated groups; run inventory on test Macs.
Emergency Mac-side (controlled): dseditgroup -o edit -d <user> -t user admin; rm the demote LaunchDaemon plist; rm the state directory; jamf recon.
Full runbook: WIKI section "Temporary Admin Elevation (Admin Setup) → Rollback".
```

## Final confirmation

```text
[x] No architecture contracts were altered.
[x] No prohibited attribution or implementation-tool markers were added (enforced by an architecture test that scans the feature files).
[x] No direct Jamf credentials were stored outside the existing Keychain path (the feature stores none).
[x] No unbounded or permanent elevation path was added (durations are a closed set; the Mac auto-demotes; the elevation script refuses other durations).
```
