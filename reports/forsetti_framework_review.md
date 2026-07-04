# Framework Review

The framework repository was reviewed as a reference implementation only. The remediation package requires the application to own its runtime layer, module manifests, activation rules, capability policy, service container, event bus, diagnostics logging, and UI surface routing.

## Applicable Pattern

- Pattern B applies: one UI module plus multiple service and feature modules.
- Service modules are isolated from UI frameworks and remain app-owned.
- The UI module owns SwiftUI and visual composition, including the Obsidian Data Stream theme.
- Manifests are local app resources and must be validated before activation.

## Rules Applied

- The app must not depend on the reference package at build time.
- The app may mirror manifest structure and module lifecycle concepts.
- Runtime constructs must live in the app source tree.
- The project file must not contain a local package entry or framework product dependencies.
- Tests should assert app-owned runtime behavior instead of the presence of the reference framework.

## Design Translation

The target implementation will provide local equivalents for module descriptors, manifest decoding, semantic version comparison, module registration, capability policy, activation storage, runtime coordination, service registration, event dispatch, and UI contribution routing. This keeps the project self-contained while preserving the modular architecture.
