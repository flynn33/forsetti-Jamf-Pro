# Forsetti Rebuild Notes

## Runtime Boundary

- The app now depends on the local Forsetti framework package and imports only `ForsettiCore` and `ForsettiPlatform`.
- Runtime boot uses `ForsettiRuntimeBootstrap`, public manifest loading, public module registration, and public service registration.
- The app starts through one UI module and activates service and feature modules through the framework runtime.

## Manifest Namespace

- The rebuild package listed `forsetti.*` module IDs.
- The public manifest loader rejects the `forsetti.` prefix as reserved.
- Runtime manifests therefore use `com.forsetti.jamfpro.*` module IDs so the app stays on strict public validation instead of bypassing the loader.

## Feature Parity

- Sanitized feature source and tests were restored for Computer Search, Mobile Device Search, Support Technician, PreStage Director, Reports, Deployment Tracker, and Permissions Helper.
- Stale prior-only tests that conflicted with the restored sanitized source were removed.
- Package defaults and templates now use the app-owned module namespace.

## Validation Snapshot

- macOS build: passing.
- macOS tests: passing, 505 tests.
- iOS generic build: passing.
- Customer-reference guard: passing.
- Provenance-marker guard: passing.
- SwiftLint: not installed in this environment.
