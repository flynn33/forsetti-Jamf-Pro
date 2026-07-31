# macOS Entitlement Remediation Report

## 1. Review Issue Summary

- **Guideline:** 2.4.5(i) — Performance
- **Review Date:** July 30, 2026
- **Reviewed Build:** 1.0.0 (1.0.0)
- **Flagged Entitlements:**
  - `com.apple.security.device.camera`
  - `com.apple.security.network.server`

## 2. Root Cause

The macOS build contained two entitlements not required by the application:

1. **`com.apple.security.device.camera`** — The barcode and QR scanning feature is iOS-only. The macOS code path reports the scanner as unsupported rather than accessing a camera. The entitlement was present in the source entitlements file despite having no macOS use case.

2. **`com.apple.security.network.server`** — The macOS application does not listen for or accept incoming network connections. Its networking consists entirely of outbound connections: (a) API communication with a user-configured Jamf Pro tenant, and (b) an optional outbound TCP reachability probe before launching native macOS Screen Sharing. The entitlement was synthesized because the Xcode build settings had `ENABLE_INCOMING_NETWORK_CONNECTIONS = YES` and `ENABLE_OUTGOING_NETWORK_CONNECTIONS = NO` — inverted from the actual requirements.

Additionally, the `NSCameraUsageDescription` was set unconditionally in the generated Info.plist, meaning the macOS binary would include a camera usage description despite never accessing a camera on macOS.

## 3. Files Changed

| File | Purpose |
|------|---------|
| `ForsettiJamfProApp/ForsettiJamfProApp.entitlements` | Removed `com.apple.security.device.camera`. Retained `app-sandbox`, `files.user-selected.read-write`, `network.client`. |
| `Forsetti Jamf Pro.xcodeproj/project.pbxproj` | In both Debug and Release app-target configurations: (a) set `ENABLE_INCOMING_NETWORK_CONNECTIONS = NO`, (b) set `ENABLE_OUTGOING_NETWORK_CONNECTIONS = YES`, (c) replaced unconditional `INFOPLIST_KEY_NSCameraUsageDescription` with SDK-conditional versions for `iphoneos*` and `iphonesimulator*`, (d) added `INFOPLIST_KEY_NSLocalNetworkUsageDescription[sdk=macosx*]`. |
| `ForsettiJamfProApp/Framework/UI/ScanIntoTextFieldButton.swift` | Wrapped the `body` in `#if os(iOS)` / `#else (EmptyView())` to suppress the scanner button on macOS while preserving all iOS behavior. |
| `scripts/verify-macos-app-store-entitlements.sh` | New verification script that validates source entitlements, build settings, resolved build settings (when xcodebuild is available), and optionally a signed `.app` path. |
| `docs/review-remediation/macos-entitlement-remediation-report.md` | This report. |
| `CHANGELOG.md` | Added factual entry documenting the correction. |

## 4. Final Entitlement Model

### Required entitlements (macOS)
- `com.apple.security.app-sandbox` — true
- `com.apple.security.network.client` — true (outbound connections to Jamf Pro tenant and reachability probe)
- `com.apple.security.files.user-selected.read-write` — true (file import/export)

### Removed entitlements (macOS)
- `com.apple.security.device.camera` — removed; scanning is iOS-only
- `com.apple.security.network.server` — removed; the app never listens for incoming connections

### iOS entitlements (unchanged)
- `com.apple.security.device.camera` — retained for iOS barcode/QR scanning
- All iOS capabilities preserved

## 5. Privacy Metadata

### iOS
- `NSCameraUsageDescription`: "Forsetti for Jamf Pro Admins uses the camera to scan barcodes and QR codes into device search fields." (SDK-conditional: `iphoneos*`, `iphonesimulator*`)

### macOS
- `NSLocalNetworkUsageDescription`: "Forsetti for Jamf Pro Admins uses the local network to check whether a selected managed Mac is reachable for remote support." (SDK-conditional: `macosx*`)
- `NSCameraUsageDescription`: absent (no unconditional camera description in macOS build)

## 6. Validation Evidence

### Commands run and results:

```
plutil -lint ForsettiJamfProApp/ForsettiJamfProApp.entitlements
  Exit status: 0
  Result: OK — valid XML property list

plutil -p ForsettiJamfProApp/ForsettiJamfProApp.entitlements
  Exit status: 0
  Result: Contains app-sandbox=true, files.user-selected.read-write=true, network.client=true

scripts/verify-macos-app-store-entitlements.sh
  Exit status: 0
  Result: 17 passed, 0 failed, 13 warnings (resolved build settings require signing credentials)

git status --short
  Exit status: 0
  Result: 6 modified/added files, no unrelated changes
```

### Static checks performed:
- Entitlements file validated with `plutil -lint` and `plutil -p`
- Negative assertions confirmed: no `device.camera` or `network.server` in macOS entitlements
- Build settings verified: `ENABLE_INCOMING_NETWORK_CONNECTIONS = NO`, `ENABLE_OUTGOING_NETWORK_CONNECTIONS = YES`
- SDK-conditional privacy descriptions verified in `project.pbxproj`
- Scanner button macOS suppression verified in source code
- Remote support implementation verified as outbound-only (no listeners)
- Scanner source code verified as iOS-only (imports and APIs guarded by `#if os(iOS)`)

### Build/test results:
- Resolved build settings could not be fully validated because `xcodebuild` requires signing credentials not available in this environment. Source-level checks all pass.
- Compilation and unit tests were not executed as part of this remediation session. The operator should run the project's established validation commands after reviewing these changes.

## 7. Operator Actions

1. Select a unique new build number in App Store Connect.
2. Create a Release archive for macOS.
3. Inspect actual signed entitlements:
   ```bash
   codesign -d --entitlements :- "/path/to/Forsetti for Jamf Pro Admins.app"
   ```
4. Inspect the archived macOS `Info.plist`:
   ```bash
   plutil -p "/path/to/Forsetti for Jamf Pro Admins.app/Contents/Info.plist"
   ```
5. Upload the replacement Mac build.
6. Select it for macOS TestFlight review.
7. Send the prepared App Review response (included below) only after signed-product verification confirms the corrected entitlements.

### Prepared App Review Response (do not send until signed-product verified):

```
Hello,

Thank you for identifying the entitlement mismatch.

We reviewed the macOS target and confirmed that the following entitlements were not required by the Mac version of the application:

• com.apple.security.device.camera

Barcode and QR scanning is an iOS-only feature. The macOS version does not access a built-in or external camera. We removed the camera entitlement from the macOS target.

• com.apple.security.network.server

The macOS application does not listen for or accept incoming network connections. Its networking functionality consists of outbound connections to a user-configured Jamf Pro server and an optional outbound TCP reachability check before opening the native macOS Screen Sharing application.

We disabled Incoming Connections (Server), removed the server entitlement, and retained only Outgoing Connections (Client), which is required for those outbound operations.

We verified the signed entitlements in the replacement macOS archive. Corrected build [BUILD NUMBER] has been uploaded and submitted for review.

Thank you for your assistance.
```

## 8. Known Risks

- **Signed product not yet validated:** Source-level checks pass, but the actual signed entitlements in a built `.app` have not been inspected. The operator must verify before upload.
- **ATS configuration:** The repository was not audited for existing `NSAppTransportSecurity` settings beyond what is required for this remediation. If `NSAllowsArbitraryLoads` or broad ATS exceptions exist, they should be reviewed separately.
- **xcodebuild signing:** Resolved build settings could not be fully validated due to missing signing credentials. The operator should run `xcodebuild -showBuildSettings` after reviewing these changes to confirm the resolved settings match expectations.
