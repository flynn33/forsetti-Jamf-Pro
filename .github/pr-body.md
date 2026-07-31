## Summary

Corrected macOS sandbox capabilities to resolve App Review Guideline 2.4.5(i) — Performance.

## Changes

- **Entitlements:** Removed `com.apple.security.device.camera` from the macOS entitlements file. Retained `app-sandbox`, `files.user-selected.read-write`, and `network.client`.
- **Build settings:** Set `ENABLE_INCOMING_NETWORK_CONNECTIONS = NO` and `ENABLE_OUTGOING_NETWORK_CONNECTIONS = YES` in both Debug and Release configurations (previously inverted).
- **Privacy descriptions:** Replaced unconditional `NSCameraUsageDescription` with SDK-conditional versions (iphoneos*/iphonesimulator*) for iOS only. Added `NSLocalNetworkUsageDescription` for macOS.
- **Scanner button:** Suppressed the scanner button on macOS via `#if os(iOS)` in `ScanIntoTextFieldButton.swift` while preserving all iOS scanning behavior.
- **Verification:** Added `scripts/verify-macos-app-store-entitlements.sh` (passes 17/17 source-level checks).
- **Documentation:** Added remediation report and changelog entry.

## Files Changed

1. `ForsettiJamfProApp/ForsettiJamfProApp.entitlements`
2. `Forsetti Jamf Pro.xcodeproj/project.pbxproj`
3. `ForsettiJamfProApp/Framework/UI/ScanIntoTextFieldButton.swift`
4. `scripts/verify-macos-app-store-entitlements.sh` (new)
5. `docs/review-remediation/macos-entitlement-remediation-report.md` (new)
6. `CHANGELOG.md`

## Validation

- `plutil -lint` confirms valid entitlements XML.
- `scripts/verify-macos-app-store-entitlements.sh` passes 17/17 source-level checks.
- Signed product validation requires building an archive (operator action).

## Remaining Operator Actions

1. Build a Release archive
2. Inspect signed entitlements: `codesign -d --entitlements :- "/path/to/Forsetti for Jamf Pro Admins.app"`
3. Upload the replacement Mac build to App Store Connect
4. Select for TestFlight beta review
5. Send the prepared App Review response (included in the remediation report)
