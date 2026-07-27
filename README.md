# Forsetti Jamf Pro

Forsetti Jamf Pro is a macOS and iOS operations app for Jamf Pro environments. It uses a self-contained Forsetti Pattern B architecture: one application-owned SwiftUI workspace module and app-owned service modules coordinated by the local runtime.

## Active runtime

The production runtime activates these 10 modules:

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

## Deployment Tracker separation

Deployment Tracker is no longer compiled, bundled, registered, activated, or shown by Forsetti Jamf Pro. Its unchanged domain and SwiftUI sources, three feature tests, legacy Forsetti service adapter and manifest, and extracted Permissions Helper contract are preserved under [`Standalone/DeploymentTracker`](Standalone/DeploymentTracker/README.md).

The preserved directory is a non-runnable source snapshot for a future standalone application. It is intentionally outside the app and test target roots and must not be added back to the Forsetti Jamf Pro targets.

## Documentation

- [`docs/README.md`](docs/README.md) — documentation map and historical-material boundary
- [`WIKI.md`](WIKI.md) — current architecture notes
- [`Standalone/DeploymentTracker/README.md`](Standalone/DeploymentTracker/README.md) — preservation boundary and extraction checklist
- [`docs/PUBLIC_RELEASE_CHECKLIST.md`](docs/PUBLIC_RELEASE_CHECKLIST.md) — required 30-day evaluation lock and public-release gates
- [`REMEDIATION_REPORT.md`](REMEDIATION_REPORT.md) — A1.0.0 remediation record and post-baseline update
- [`VALIDATION_RESULTS.md`](VALIDATION_RESULTS.md) — current validation results
- [`CHANGELOG.md`](CHANGELOG.md) — release and unreleased changes

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

## Proprietary license and evaluation

Forsetti Jamf Pro is proprietary software. The source is visible on GitHub for inspection. Subject to [`LICENSE`](LICENSE), an individual may clone, compile, and test the software for a single 30-day Evaluation Period beginning on first execution. Continued application use after that period requires a valid purchase through the Apple App Store. Any exception requires a separate signed agreement from the Licensor.

An App Store purchase authorizes use of the official App Store version under its accompanying end-user terms. It does not grant rights to distribute this source code or continue using modified or source-built versions after the Evaluation Period.

The technical 30-day lock and purchase verification are planned release requirements and are not yet implemented. Forsetti Jamf Pro must not be treated as ready for public product release until the gates in [`docs/PUBLIC_RELEASE_CHECKLIST.md`](docs/PUBLIC_RELEASE_CHECKLIST.md) are complete.

Pull requests from outside contributors are not reviewed, approved, or merged. See [`CONTRIBUTING.md`](CONTRIBUTING.md) for the repository policy and [`NOTICE`](NOTICE) for the copyright notice.
