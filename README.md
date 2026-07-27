# Forsetti Forsetti Jamf Pro

Forsetti Forsetti Jamf Pro is a macOS and iOS Jamf Pro operations app built as a Forsetti Pattern B consumer application.

The app consumes the public Forsetti package products:

- `ForsettiCore`
- `ForsettiPlatform`
- `ForsettiHostTemplate`

The production runtime activates service modules plus one dedicated UI module:

- `com.forsetti.jamfpro.service.diagnostics`
- `com.forsetti.jamfpro.service.jamf`
- `com.forsetti.jamfpro.service.scanner`
- `com.forsetti.jamfpro.feature.computer-search`
- `com.forsetti.jamfpro.feature.mobile-device-search`
- `com.forsetti.jamfpro.feature.support-technician`
- `com.forsetti.jamfpro.feature.prestage-director`
- `com.forsetti.jamfpro.feature.reports`
- `com.forsetti.jamfpro.feature.permissions-matrix`
- `com.forsetti.jamfpro.ui.workspace`

Only `com.forsetti.jamfpro.ui.workspace` owns application SwiftUI screens. Service modules own Jamf API/authentication, diagnostics, scanner support, and feature/domain responsibilities.

## Preserved standalone work

Deployment Tracker is no longer compiled, bundled, registered, or shown by Forsetti Jamf Pro. Its source, UI, tests, legacy Forsetti integration contract, and permissions metadata are intentionally preserved under [`Standalone/DeploymentTracker`](Standalone/DeploymentTracker/README.md) as the starting point for a separate application.

## Validation

Run:

```bash
python3 scripts/validate-forsetti-manifests.py --manifests ForsettiJamfProApp/Resources/ForsettiManifests --expect-one-ui-module com.forsetti.jamfpro.ui.workspace
./scripts/verify-forsetti-jamf-pro-guardrails.sh
swiftlint lint --strict --config .swiftlint.yml
xcodebuild -project 'Forsetti Jamf Pro.xcodeproj' -scheme 'Forsetti Jamf Pro' -destination 'platform=macOS' build
xcodebuild -project 'Forsetti Jamf Pro.xcodeproj' -scheme 'Forsetti Jamf Pro' -destination 'generic/platform=iOS Simulator' build
xcodebuild test -project 'Forsetti Jamf Pro.xcodeproj' -scheme 'ForsettiJamfProTests' -destination 'platform=macOS'
```
