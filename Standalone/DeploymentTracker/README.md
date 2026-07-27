# Deployment Tracker preservation boundary

Deployment Tracker was detached from Forsetti Jamf Pro on 2026-07-26 and is preserved here as the source snapshot for a future standalone application.

## Status

- Provenance commit: `e0dbcebe2cae13ecaffa2bbcee34aa013656a414`
- This directory is intentionally outside the filesystem-synchronized `ForsettiJamfProApp` and `ForsettiJamfProTests` target roots.
- Nothing here is compiled, bundled, registered, or exposed by the current Forsetti Jamf Pro app.
- This snapshot is not yet a runnable standalone application.
- The preserved installed experience was demo-only, used deterministic in-memory data, and did not perform live Jamf actions.

Do not add this directory to the existing Forsetti Jamf Pro target. Create a separate project or Swift package when standalone application work begins.

## Preserved contents

```text
Standalone/DeploymentTracker/
├── Sources/DeploymentTracker/
│   ├── Domain/                    33 domain, persistence, workflow, and integration files
│   └── UI/                        11 SwiftUI and rendering files
├── Tests/                         3 preserved feature test files
├── LegacyForsettiIntegration/
│   ├── DeploymentTrackerServiceModule.swift
│   └── Resources/DeploymentTrackerServiceModule.json
├── Resources/
│   └── DeploymentTrackerPermissionsContract.json
└── SOURCE_MANIFEST.sha256
```

The permissions contract preserves the 11 former Permissions Helper action definitions and the four source-observed Jamf Inventory Preload endpoints.

## Host dependencies to replace or port

The snapshot still relies on types owned by Forsetti Jamf Pro:

- Jamf networking: `JamfAPIGateway`, multipart upload support, pagination, and `JamfRSQLFilter`
- Diagnostics and errors: `DiagnosticsReporting`, `DiagnosticSeverity`, and `JamfFrameworkError`
- Credentials: `JamfCredentialsStore`
- UI system: `DashboardTheme`, `DashboardColors`, `DashboardMetalBackgroundView`, and `dashboardCardSurface`
- Runtime metadata: the preserved Forsetti service adapter and manifest

System framework dependencies include Foundation, SwiftUI, Combine, Core Data, CryptoKit, Uniform Type Identifiers, MetalKit, and OSLog.

One source-boundary cycle also remains: `DeploymentDemoScenario` refers to `DeploymentTrackerWorkspace`, while that enum currently lives in the SwiftUI workspace file. Move the enum into a UI-independent model before splitting core and UI targets.

## Standalone migration requirements

1. Create a new app project, bundle identifier, signing configuration, and app entry point.
2. Split the snapshot into core, Jamf adapter, persistence, and UI targets.
3. Replace the direct host dependencies with module-owned protocols and standalone implementations.
4. Inject the persistent-store location. The preserved Core Data store currently uses `Application Support/Forsetti Jamf Pro/DeploymentTracker/DeploymentTracker.sqlite`.
5. Decide whether an existing store should be migrated or a new standalone store should start clean.
6. Replace the hard-coded `com.forsetti.jamfpro` rendering log subsystem and legacy runtime identifiers.
7. Supply standalone theme components or replace the Forsetti design-system calls.
8. Move the preserved tests into the new test target and add production-mode integration coverage.

## Extraction acceptance checklist

- The new app builds without importing the Forsetti Jamf Pro app target.
- Core/domain tests run without SwiftUI or host design-system dependencies.
- Demo mode remains incapable of live Jamf writes.
- Production mode has explicit authentication, diagnostics, persistence, and API adapters.
- Store migration behavior is tested before changing the application-support path.
- Jamf Inventory Preload permissions match `Resources/DeploymentTrackerPermissionsContract.json`.
- Bundle identifiers, storage paths, log subsystems, and user-facing names are standalone-specific.
- `SOURCE_MANIFEST.sha256` verifies before the first refactor.
