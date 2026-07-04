# Forsetti Jamf Dashboard

Forsetti Jamf Dashboard is a macOS and iOS Jamf Pro operations app built as a Forsetti Pattern B consumer application.

The app consumes the public Forsetti package products:

- `ForsettiCore`
- `ForsettiPlatform`
- `ForsettiHostTemplate`

The production runtime activates service modules plus one dedicated UI module:

- `com.forsetti.jamfdashboard.service.diagnostics`
- `com.forsetti.jamfdashboard.service.jamf`
- `com.forsetti.jamfdashboard.service.scanner`
- `com.forsetti.jamfdashboard.feature.computer-search`
- `com.forsetti.jamfdashboard.feature.mobile-device-search`
- `com.forsetti.jamfdashboard.feature.support-technician`
- `com.forsetti.jamfdashboard.feature.prestage-director`
- `com.forsetti.jamfdashboard.feature.reports`
- `com.forsetti.jamfdashboard.feature.deployment-tracker`
- `com.forsetti.jamfdashboard.feature.permissions-matrix`
- `com.forsetti.jamfdashboard.ui`

Only `com.forsetti.jamfdashboard.ui` owns application SwiftUI screens. Service modules own Jamf API/authentication, diagnostics, scanner support, and feature/domain responsibilities.

## Validation

Run:

```bash
python3 scripts/validate-forsetti-manifests.py --manifests JamfDashboardApp/Resources/ForsettiManifests --expect-one-ui-module com.forsetti.jamfdashboard.ui
./scripts/verify-forsetti-jamf-pro-guardrails.sh
swiftlint lint --strict --config .swiftlint.yml
xcodebuild -project 'Jamf Dashboard.xcodeproj' -scheme 'Jamf Dashboard' -destination 'platform=macOS' build
xcodebuild -project 'Jamf Dashboard.xcodeproj' -scheme 'Jamf Dashboard' -destination 'generic/platform=iOS Simulator' build
xcodebuild test -project 'Jamf Dashboard.xcodeproj' -scheme 'JamfDashboardAppTests' -destination 'platform=macOS'
```
