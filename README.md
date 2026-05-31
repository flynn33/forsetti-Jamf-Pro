# Forsetti

Forsetti is an Apple-native Jamf Pro administration application for support, reporting, prestage, inventory, and deployment workflows. The app keeps Jamf Pro credentials in Keychain, centralizes Modern API access, and presents feature workflows through a retail-safe SwiftUI interface.

## Capabilities

- Jamf Pro credential verification and secure storage.
- Computer and mobile device inventory search with saved field profiles.
- Prestage assignment workflows.
- Support technician workflows with guarded device actions.
- Reporting with CSV, text, Markdown, document, and PDF export paths.
- Deployment tracker workflows for inventory preload, validation, and records.
- Diagnostics export with a retail-safe logging subsystem.

## Architecture

Forsetti uses a single visible retail UI module plus service and feature modules behind the Forsetti runtime boundary:

- `forsetti.retail.ui`
- `forsetti.service.jamf`
- `forsetti.service.diagnostics`
- `forsetti.service.scanner`
- `forsetti.feature.computer-search`
- `forsetti.feature.mobile-device-search`
- `forsetti.feature.support-technician`
- `forsetti.feature.prestage-director`
- `forsetti.feature.reports`
- `forsetti.feature.deployment-tracker`

The app depends on the public `ForsettiCore` and `ForsettiPlatform` package products. Framework internals are not copied into this repository.

## Build

Requirements:

- Xcode 26 or newer.
- macOS 14 or newer for the macOS target.
- Access to `https://github.com/flynn33/Forsetti-Framework.git`.

Commands:

```bash
xcodebuild -list -project Forsetti.xcodeproj
xcodebuild -project Forsetti.xcodeproj -scheme Forsetti -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO clean build
xcodebuild -project Forsetti.xcodeproj -scheme Forsetti -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO test
```

## Local Data

Forsetti stores app-managed support files under the app container using these retail-safe paths:

- Application Support: `Forsetti/`
- Diagnostics documents: `ForsettiDiagnostics/`
- Diagnostics filename prefix: `forsetti-diagnostics`

## License

Current license terms require owner approval before public distribution. See `LICENSE` and `LICENSE_REVIEW_REQUIRED.md`.
