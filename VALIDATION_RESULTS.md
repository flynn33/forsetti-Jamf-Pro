# Validation Results

## Environment

- Repository: `/Users/jimdaley/github/forsetti-jamf-pro`
- Forsetti framework package: `/Users/jimdaley/github/Forsetti-Framework-Mac-iOS-main`
- `xcode-select -p`: `/Library/Developer/CommandLineTools`
- Xcode used for tests: `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer`
- Xcode version: `Xcode 26.6`, build `17F113`
- Xcode project package user-state was cleaned before validation. Xcode may recreate ignored `xcuserdata` when the project is opened.
- UI/UX rebuild source: local Obsidian Operations Cockpit handoff package.

## Commands

### Manifest Static Validation

Command:

```bash
python3 scripts/validate-forsetti-manifests.py --manifests JamfDashboardApp/Resources/ForsettiManifests --expect-one-ui-module com.forsetti.jamfdashboard.ui
```

Result: passed.

Output:

```text
Validated 11 Forsetti manifests.
```

### App Guardrails

Command:

```bash
./scripts/verify-forsetti-jamf-pro-guardrails.sh
```

Result: passed.

Output:

```text
Validated 11 Forsetti manifests.
Verified registry coverage for 11 entry points.
Forsetti Jamf Pro guardrails passed.
```

### Project File Lint

Command:

```bash
plutil -lint 'Jamf Dashboard.xcodeproj/project.pbxproj'
```

Result: passed.

Output:

```text
Jamf Dashboard.xcodeproj/project.pbxproj: OK
```

### Xcode Scheme and Package Resolution

Command:

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -list -project 'Jamf Dashboard.xcodeproj'
```

Result: passed.

Key output:

```text
Resolved source packages:
  ForsettiFramework: /Users/jimdaley/GitHub/Forsetti-Framework-Mac-iOS-main @ local

Schemes:
  ForsettiCore
  ForsettiHostTemplate
  ForsettiPlatform
  Jamf Dashboard
  JamfDashboardAppTests
```

### Xcode GUI Open

Command:

```bash
open -a /Applications/Xcode.app 'Jamf Dashboard.xcodeproj'
osascript -e 'tell application "Xcode" to get name of windows'
```

Result: passed.

Output:

```text
Jamf Dashboard — JamfDashboardModuleRegistry.swift, App Shortcuts Preview
```

### Project Version and Build Settings

Command:

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project 'Jamf Dashboard.xcodeproj' -scheme 'Jamf Dashboard' -showBuildSettings
```

Result: passed.

Key output:

```text
CURRENT_PROJECT_VERSION = 3.32.1
MARKETING_VERSION = 3.32.1
PRODUCT_BUNDLE_IDENTIFIER = com.forsetti.jamfdashboard
SWIFT_VERSION = 5.0
```

### macOS Debug App Build

Command:

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project 'Jamf Dashboard.xcodeproj' -scheme 'Jamf Dashboard' -configuration Debug -destination 'platform=macOS,arch=arm64' -derivedDataPath /tmp/Forsetti-Jamf-Pro-DerivedData-uiux-build CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY=- build
```

Result: passed.

Key output:

```text
** BUILD SUCCEEDED **
```

### iOS Simulator Debug App Build

Command:

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project 'Jamf Dashboard.xcodeproj' -scheme 'Jamf Dashboard' -configuration Debug -destination 'generic/platform=iOS Simulator' -derivedDataPath /tmp/Forsetti-Jamf-Pro-DerivedData-uiux-ios CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY=- build
```

Result: passed.

Key output:

```text
** BUILD SUCCEEDED **
```

### macOS XCTest Suite

Command:

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild test -project 'Jamf Dashboard.xcodeproj' -scheme 'JamfDashboardAppTests' -destination 'platform=macOS,arch=arm64' -derivedDataPath /tmp/Forsetti-Jamf-Pro-DerivedData-uiux-tests CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY=-
```

Result: passed.

Key output:

```text
Test Suite 'JamfDashboardAppTests.xctest' passed
Executed 494 tests, with 0 failures (0 unexpected)
** TEST SUCCEEDED **
```

Notes:

- A first test attempt without signing overrides failed before execution because the local keychain does not contain the configured `Mac Development` certificate for team `2Y25RTLZET`.
- The successful app build and test commands disable signing for local validation only. No final/release app build was performed.
- Xcode emitted a non-blocking AppIntents metadata warning because the app target has no AppIntents framework dependency.

### Focused Regression Rerun

Command:

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild test -project 'Jamf Dashboard.xcodeproj' -scheme 'JamfDashboardAppTests' -destination 'platform=macOS' -only-testing:JamfDashboardAppTests/TemporaryAdminElevationArchitectureTests CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY=-
```

Result: passed.

Key output:

```text
Test Suite 'TemporaryAdminElevationArchitectureTests' passed
Executed 5 tests, with 0 failures (0 unexpected)
** TEST SUCCEEDED **
```

### SwiftLint

Command:

```bash
swiftlint lint --strict --config .swiftlint.yml
```

Result: unavailable in this environment.

Output:

```text
zsh:1: command not found: swiftlint
```
