# Current Project Violation Audit

This audit records the pre-change state of the local repository before applying the A1.0.0 remediation.

## Project Identity

- The local project used the prior Jamf Dashboard project name and scheme.
- The application target used the old display name and bundle namespace.
- The project build versions were still aligned to the authorized sanitized source version, not the A1.0.0 release label.

## Runtime Dependency

- The Xcode project still carried a local package relationship to the reference framework repository.
- App and test source files imported framework products directly.
- The existing runtime bootstrap delegated app launch composition to the reference host template.
- Architecture tests expected external framework references instead of enforcing their absence.

## Module Manifest Gaps

- Manifest resource IDs used the older dashboard namespace.
- The module set did not yet match the A1.0.0 target ID matrix.
- Version fields needed to be moved to the A1.0.0 application release.
- The UI manifest needed to represent the single workspace UI module required by Pattern B.

## UI/UX Contract Gaps

- The Obsidian Data Stream rebuild was present in the app surface, but contract component names, runtime boundary indicators, and module mix presentation needed to be confirmed and aligned to the remediation package.
- Metal-backed visual effects needed to remain contained in the design system and UI layer with fallbacks.

## Required Corrections

- Rename and retarget the Xcode project, scheme, targets, bundle identifiers, and release version.
- Remove build-time framework package references and replace them with app-owned runtime code.
- Update manifests, module IDs, tests, and validation scripts for A1.0.0.
- Run validation, lint when available, macOS build, iOS simulator build, and macOS tests.
