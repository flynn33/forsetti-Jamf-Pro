# UI/UX Implementation Plan

## Baseline

- Branch: `retail-uiux-foundation`
- Baseline build: macOS scheme build passed
- Baseline tests: macOS scheme test suite passed
- Current gap: the app still compiles the earlier cyan theme name and dashboard grid, while the handoff package requires the Forsetti Obsidian Data Stream visual system.

## Implementation Scope

1. Update the retail theme tokens to the Obsidian Data Stream palette and keep existing semantic aliases stable for the rest of the app.
2. Expand the command activity model and status bar visuals to cover preparation, tenant wait, status polling, cancellation, failure, and completion states.
3. Add reusable retail shell components for metric strips, status rows, navigation rail content, and diagnostics surfaces.
4. Replace the dashboard grid-first home screen with a command-center workspace that exposes module navigation, tenant state, operations metrics, diagnostics, and the activity bar.
5. Preserve the single app-owned retail UI module boundary and keep SwiftUI views focused on rendering state and forwarding intent.

## Verification Gates

- Focused retail UI foundation tests
- Full macOS scheme build
- Full macOS scheme test suite
- Repository marker guard
- Customer carryover checks
- Corrective package static gates
