# Reports Discovery Notes

## Repository State

- Local app version before Reports work: `3.20.2`.
- Xcode project uses file-system synchronized groups for app and test targets.
- The active module registration path is `ModulePackageManifest.bundledDefaults` plus `ModulePackageManager.makeModule(from:)`.

## Confirmed Patterns

- Networking must use `JamfAPIGateway`.
- Diagnostics must use `DiagnosticsReporting`.
- Module roots conform to `JamfModule` and create a SwiftUI root view from `ModuleContext`.
- Current Metal visuals use a SwiftUI wrapper, an `MTKView` representable, a renderer object, shared GPU resources, and a SwiftUI fallback.
- Existing export flow prepares bytes first, then presents one SwiftUI file exporter from view-owned state.
- Computer and mobile inventory catalogs already expose field and section metadata that Reports can adapt.

## Implementation Guardrails

- No remote GitHub action is part of this work.
- Reports must remain read-only against Jamf Pro inventory.
- Inferred hardware identity must carry confidence metadata in UI and exports.
