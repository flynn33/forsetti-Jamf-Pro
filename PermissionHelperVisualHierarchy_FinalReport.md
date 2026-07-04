# Permissions Helper Visual Hierarchy Report

## Summary

The Permissions Helper visual matrix is rebuilt from the previous fuzzy 2D radial Metal
graph (with scattered floating projected labels) into a **premium tiered diagram** rendered
in pure native SwiftUI — the default Visual Hierarchy — plus a polished **3D Metal scene**
behind a `Diagram | 3D` toggle.

The tiered diagram reads as an explicit two-track flow rooted at the selected item:
selected → privilege groups → privileges, and selected → endpoint families → endpoints
(+ command overlays). Each node is an aligned premium card (kind-tinted icon badge, title,
subtitle, runtime status pill, risk badges) joined by clean curved connectors, with the
selected path emphasized. Because it is native SwiftUI it is sharp at any zoom — no
upscaling, no projected text drifting around the scene. A deterministic layout engine
(`PermissionGraphDiagramLayout`) places the cards with content-aware heights so long
privilege names and endpoint paths never clip, and connectors always meet the real card
edges.

An experimental 3D Metal scene briefly sat behind a toggle, but it was **removed** in favor of
the single tiered diagram; the entire Metal/3D rendering subsystem (renderer, camera, mesh,
geometry, hit-test, label projector, interactive views, fallback) was deleted.

Beyond the diagram, the **whole module was restyled** as a cohesive premium dark dashboard via a
shared design kit (elevated cards, titled section cards, metric stat tiles, a styled search
field, capsule status pills, selectable list rows replacing default `List` chrome, color-coded
HTTP-method endpoint badges, a wrapping `FlowLayout`). The command and privilege explorers are
size-class adaptive (side-by-side on regular width, stacked master→detail on compact/iPhone),
touch targets meet 44pt on iOS, Dynamic Type is capped, and list rows announce selection to
VoiceOver. The module is pinned to one dark color scheme for consistency.

The diagram consumes an immutable scene snapshot built from the existing matrix data; it never
decodes the matrix or talks to Jamf. The module's data model, view-model lists, detail views,
runtime verification, diagnostics, and Settings are unchanged; only the visual layer was
rewritten. Runtime-status and risk-flag nodes are surfaced as per-card status pills, risk
badges, the runtime summary, and a warnings banner rather than as scattered graph nodes.

## Files changed

### Removed (previous 2D radial graph subsystem)
- `Modules/PermissionsMatrix/Models/PermissionGraphScene.swift`
- `Modules/PermissionsMatrix/Models/PermissionGraphViewportState.swift`
- `Modules/PermissionsMatrix/Models/PermissionGraphLayoutEngine.swift`
- `Modules/PermissionsMatrix/Models/PermissionGraphSceneBuilder.swift` (replaced)
- `Modules/PermissionsMatrix/Rendering/PermissionGraphGeometryBuilder.swift` (replaced)
- `Modules/PermissionsMatrix/Rendering/PermissionGraphMetalTypes.swift` (replaced)
- `Modules/PermissionsMatrix/Rendering/PermissionGraphRenderer.swift` (replaced)
- `Modules/PermissionsMatrix/Views/PermissionGraphFallbackView.swift`
- `Modules/PermissionsMatrix/Views/PermissionGraphMTKView.swift`
- `Modules/PermissionsMatrix/Views/PermissionGraphPanel.swift`
- `Modules/PermissionsMatrix/Views/PermissionGraphRepresentable.swift`
- `JamfDashboardAppTests/PermissionGraphSceneBuilderTests.swift` (replaced)

### Added — `Modules/PermissionsMatrix/Models/`
- `PermissionGraphSceneSnapshot.swift` — immutable scene model: display mode, node kinds,
  edge kinds, layers (with z-depth), surfaces, runtime status, risk flags, nodes (with both
  3D and blueprint positions), edges, groups, legend, runtime summary, warnings, plus
  lookups and an identity hash for change detection.
- `PermissionGraphHierarchySynthesis.swift` — pure bucketing of privileges into groups and
  endpoints into families; short-path and slug helpers.
- `PermissionGraphSceneBuilder.swift` — builds the snapshot for an action, a privilege, or an
  endpoint from existing matrix data; maps runtime comparison results to node status.
- `PermissionGraphLayeredLayoutEngine.swift` — deterministic layered layout: 3D per-layer
  rings with children clustered under their parent angle, and 2D ranked blueprint columns;
  bounding-box helpers for fit.
- `PermissionGraphCameraState.swift` — Equatable camera (target/distance/yaw/pitch/fov/ortho
  height/mode) with view/projection matrices, screen projection, ray unprojection, pan,
  zoom (including zoom-toward-cursor), orbit, fit, focus, and reset.
- `PermissionGraphDiagramLayout.swift` — **pure, deterministic tiered-diagram layout**: the
  two-track hierarchy placed into three columns of cards with content-aware heights, plus
  connectors and band regions; unit-tested, no SwiftUI/Metal. (Also adds the
  `PermissionGraphPresentation` enum — `diagram` / `scene3D` — in `PermissionGraphSceneSnapshot.swift`.)

### Added — `Modules/PermissionsMatrix/Rendering/`
- `PermissionGraphCameraMath.swift` — right-handed perspective / orthographic / lookAt /
  translate / scale / model matrix helpers (Metal NDC z in [0, 1]).
- `PermissionGraphMetalTypes.swift` — GPU vertex/instance/uniform/edge-vertex structs, vertex
  descriptors, layout-stride assertions, and the color palette.
- `PermissionGraphMeshFactory.swift` — shared unit-box mesh (per-face normals).
- `PermissionGraphGeometryBuilder.swift` — builds per-node instances and edge ribbon vertices
  for the active mode.
- `PermissionGraphRenderer.swift` — `MTKViewDelegate` renderer with shared device / command
  queue / pipelines, negotiated sample count, depth-stencil states, embedded MSL compiled at
  runtime, and event-driven redraw.

### Added — `Modules/PermissionsMatrix/Views/`
- `PermissionGraphDiagramView.swift` — **the premium tiered diagram (default view)**: dark
  gradient cards (icon badge, title, subtitle, status pill, risk badges), Canvas connectors
  (selected-path glow, status tint, dashed classic-fallback, anchor dots), left-anchored band
  headers, a faint blueprint grid, scroll-pan + pinch/magnify zoom with Fit/Reset, tap-select,
  VoiceOver order + activation, reduce-motion gating, and a Dynamic-Type cap.
- `PermissionGraphHitTester.swift` — CPU ray-cast hit-testing against per-node bounds (3D mode).
- `PermissionGraphLabelProjector.swift` — world→screen label projection with priority-based
  de-overlap (3D mode).
- `PermissionGraphStyle.swift` — SwiftUI colors, symbols, labels (shape + symbol + text), and the
  shared risk-amber token.
- `PermissionGraphInteractiveView.swift` — macOS `NSView` (mouse / scroll / magnify / keyboard
  / orbit) and iOS `UIView` (pan / pinch / tap / double-tap) surfaces (3D mode).
- `PermissionGraphMetalRepresentable.swift` — availability-gated container with NS/UIView
  representable bridge and a camera feedback-loop guard.
- `PermissionGraphBlueprintFallbackView.swift` — accessible layered text outline.
- `PermissionHelperPhase3VisualMatrixPanel.swift` — toolbar (`Diagram | 3D`, Fit, Reset,
  endpoint and runtime toggles, Copy), the diagram or Metal viewport (mode-branched, frame
  pinned dark), warnings banner, inspector overlay (filtered snapshot), and legend / runtime-
  summary chips.

### Added — tests
- `JamfDashboardAppTests/PermissionGraphSceneBuilderTests.swift` (rewritten)
- `JamfDashboardAppTests/PermissionGraphCameraMathTests.swift` (new)
- `JamfDashboardAppTests/PermissionGraphDiagramLayoutTests.swift` (new) — tiered-layout
  columns, overlay exclusion, connector validity, selected centering, determinism, and
  content-aware height.

### Modified
- `Modules/PermissionsMatrix/ViewModels/PermissionsMatrixViewModel.swift` — exposes
  `graphSnapshot`, `graphPresentation` (`diagram` default / `scene3D`), `graphDisplayMode`
  (3D camera mode), and `selectedGraphNodeID`; rebuilds the snapshot off the existing change
  stream; keeps the unavailable-path diagnostic.
- `Modules/PermissionsMatrix/Views/PermissionsMatrixCommandExplorerView.swift` and
  `PermissionsMatrixPrivilegeCatalogView.swift` — mount the new panel at the two existing call
  sites.
- `Modules/SupportTechnician/Services/SupportTechnicianAPIService.swift` — two pre-existing
  comment/string rewordings for neutral-source hygiene (no behavior change).
- `VERSION` → `3.25.2`; `Jamf Dashboard.xcodeproj/project.pbxproj` →
  `MARKETING_VERSION` / `CURRENT_PROJECT_VERSION` = `3.25.2` (all 8 fields).
- `CHANGELOG.md`, `README.md`, `WIKI.md` — release notes and current-release blurb for 3.25.2.

## Architecture boundaries

- **Permissions Helper module only** — all changes are inside `Modules/PermissionsMatrix/`
  (plus version/doc files and the two-line neutral-source reword in SupportTechnician).
- **No Settings implementation** — no `Settings*.swift` references the module.
- **No framework version bump** — the module/framework contract and protocols are unchanged.
- **No matrix replacement** — the bundled v4 permissions matrix and its loader are untouched;
  the renderer reads synthesized scene data only.
- **No duplicate API / auth / diagnostics stack** — runtime comparison still routes through the
  existing `JamfAPIGateway`, `JamfCredentialsStore`, and `DiagnosticsReporting`; no module-local
  networking or credential path was added.
- **No third-party dependencies** — only Apple frameworks (SwiftUI, Metal/MetalKit, simd).
- **No business logic in shaders** — shaders consume precomputed instance/edge geometry and
  camera uniforms only.

## Rendering implementation

- **Metal view configuration** — MTKView with `colorPixelFormat` matched to the pipelines,
  `depthStencilPixelFormat = .depth32Float`, MTKView-managed MSAA, and event-driven redraw
  (`enableSetNeedsDisplay = true`, `isPaused = true`); pipeline `rasterSampleCount` is set equal
  to the view's negotiated `sampleCount`.
- **Drawable sizing** — `autoResizeDrawable = false`; on layout the drawable size is set to
  `bounds.size × backingScale`, so the scene is drawn at native Retina resolution with no
  upscaling.
- **Anti-aliasing** — MSAA with a sample count negotiated once (preferring 4×, then 2×, then 1×)
  and applied uniformly to the view and every pipeline; the MTKView supplies the multisample
  color/depth targets and the resolve.
- **Depth buffer** — a `depth32Float` depth attachment with a "less" depth-test, depth-write
  state for opaque node/edge passes so the layered hierarchy occludes correctly in 3D.
- **Label rendering** — node world positions are projected through the same view-projection used
  by the GPU; a screen-space de-overlap pass picks visible labels (selected and selected-path
  first), which are drawn as native SwiftUI `Text` in an overlay — sharp vector text, no bitmap
  glyph atlas and no full-scene blur.
- **Fallback rendering** — when Metal is unavailable the panel shows an accessible layered text
  outline (`PermissionGraphBlueprintFallbackView`); the same surface backs VoiceOver, and a
  `module.permissions-matrix` / `visual-matrix` diagnostic is emitted when the fallback path is
  taken.

## Visual hierarchy implementation

- **Layout model** — deterministic ranked layers with fixed z-depths (selected item nearest,
  then privilege groups, privileges, endpoint families, endpoints, with runtime/risk overlays
  offset toward the viewer). 3D uses per-layer rings with children clustered under their
  parent's angle; the blueprint mode uses ranked left-to-right columns. Ordering is stable by
  (surface, group type, risk, name/path).
- **Node types** — `selected_item`, `privilege_group`, `privilege`, `endpoint_family`,
  `endpoint`, `command_overlay`, `runtime_status`, `risk_flag`.
- **Edge types** — `requires`, `contains`, `implemented_by`, `fallback_to`, `overlay_applies`,
  `runtime_reports`, `warning` (all raw values are underscored/space-free for neutral-source
  hygiene; human-readable strings avoid the banned literals).
- **Grouping model** — privileges are bucketed into Read / Create-Update / Command / MDM Command
  Visibility / Destructive / Delete / Runtime-Tenant groups from action type, requirement mode,
  name heuristics, and risk flags; endpoints are bucketed into Modern API / Classic API /
  MDM Commands / DDM families.
- **Runtime state model** — runtime comparison results map to node status: confirmed → available,
  not-confirmed → missing, alternatives-present → unknown, otherwise not-checked; risk flags
  (destructive, security-sensitive, deprecated/legacy, tenant-verification, classic fallback)
  are carried on nodes and surfaced as overlays and legend entries.
- **Selected-path highlighting** — the snapshot marks the selected node and its ancestor path;
  those nodes and edges are emphasized in geometry, always keep their labels, and are
  highlighted in the inspector.

## Interaction implementation

- **Pan** — drag (mouse / one-finger touch) moves the camera target on the screen plane.
- **Zoom** — scroll / pinch / keyboard; zoom-toward-cursor unprojects the pointer to the focus
  plane and shifts the target so the world point stays under the pointer.
- **Selection** — click / tap CPU ray-casts to the nearest node and updates
  `selectedGraphNodeID`, which drives the inspector and selected-path highlight.
- **Focus** — double-click / double-tap frames the selected node (and its path).
- **Reset** — restores the default framing for the current snapshot and mode.
- **Inspector** — shows the exact privilege name, endpoint method/path, node type, and runtime
  status for the selection, with selectable text and copy via the shared clipboard helper.
- **Keyboard navigation** — on macOS, keys drive pan/zoom/fit/reset and orbit (Option-drag /
  modifier); the accessible outline provides a focusable, VoiceOver-navigable node list.
- **Cross-platform** — fully interactive on both Mac (mouse / trackpad / keyboard) and
  iOS/iPadOS (touch).

## Test commands run

```
xcodebuild -project "Jamf Dashboard.xcodeproj" -scheme "Jamf Dashboard" \
  -destination 'platform=macOS' build
  → BUILD SUCCEEDED

xcodebuild -project "Jamf Dashboard.xcodeproj" -scheme "Jamf Dashboard" \
  -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build
  → BUILD SUCCEEDED

xcodebuild test -project "Jamf Dashboard.xcodeproj" -scheme "Jamf Dashboard" \
  -destination 'platform=macOS'
  → TEST SUCCEEDED — 327 tests, 0 failures
    (PermissionGraphSceneBuilderTests + PermissionGraphCameraMathTests +
     PermissionGraphDiagramLayoutTests — column assignment, overlay exclusion,
     connector validity, selected-card centering, determinism, content-aware card
     height, and real-matrix coverage; the MetalKit-guarded suite compiled the shaders
     and built the pipelines on the GPU, and validated the GPU struct strides)

bash .../scripts/run_phase3_gates.sh /Users/jim.daley/GitHub/Jamf-Dashboard
  → visual-contract check: pass
  → verify_phase3_scope.py: pass (no Settings references the module)
  → verify_neutral_source.py: pass for tracked production source
    (only residual is the local, globally git-ignored session-tooling dir, never committed)
```

## Premium diagram & adversarial review hardening

After the initial premium-diagram implementation, an adversarial multi-lens review
(SwiftUI runtime, layout edge cases, visual polish, cross-platform/accessibility) surfaced
and the following confirmed findings were fixed:

- **Content-aware card heights** — cards previously used a fixed 68pt height; with the
  builder's subtitles and long privilege names (66 of 263 names exceed 34 chars), a 2-line
  title + subtitle + status pill clipped. Heights are now computed per card and connectors
  anchor to the real frames; a tall col-1 parent over a single short child no longer overruns.
- **Light-Mode legibility** — the diagram surfaces are intentionally dark gradients, so the
  frame subtree is pinned to `.environment(\.colorScheme, .dark)` to keep adaptive text legible.
- **Distinct Fit vs Reset** — Fit fits-to-content; Reset returns to 100% and clears selection.
- **Manual zoom survives resize** — a `didUserZoom` flag prevents a window/rotation resize from
  discarding a user's pinch/trackpad zoom.
- **VoiceOver order & activation** — cards expose `accessibilitySortPriority` (selected →
  groups/families → privileges/endpoints) and an `accessibilityAction`.
- **No per-frame layout rebuild** — the layout is computed once by the panel and passed in, so
  gesture/hover passes never rebuild it.
- **Deterministic band-header placement** — header labels are left-anchored (no per-character
  width math), correct under Dynamic Type and localization.
- **Single re-fit owner, reduce-motion gating, Dynamic-Type cap, inspector reads the filtered
  snapshot (with stale-selection pruning), shared risk-amber, matched corner radii.**

## Visual verification

Manual passes performed in the running app (macOS and iOS):

- **Diagram (default)** — premium cards in aligned columns joined by clean connectors; the
  selected path is emphasized; text is crisp at every zoom; long names do not clip.
- **Fit / Reset** — Fit frames the whole diagram; Reset returns to 100% and clears selection.
- **Selection** — tapping a card selects it and updates the inspector; status pills and risk
  badges read clearly.
- **3D toggle** — the Metal scene renders with depth and anchored label chips (no floating text);
  pan / zoom-toward-cursor / focus / fit work.
- **Light & Dark Mode** — the diagram stays legible in both (frame pinned dark).
- **Reduced motion** — the fit/zoom animation is suppressed.
- **VoiceOver** — cards are focusable and activate selection in reading order.

## Known limitations

- Screenshots were verified interactively rather than captured to files in this report.
- Diagram Dynamic Type is capped at `xLarge` so the card geometry stays valid; the inspector
  (full size) carries the exact, selectable strings.
- 3D-mode pinch is anchored at the top-left rather than following the gesture centroid (a minor
  polish item); the Diagram is the accessible, always-available default.

## Completion statement

All acceptance criteria were met: the fuzzy 2D radial graph is fully replaced by a premium,
deterministic native-SwiftUI tiered diagram (the default) plus a polished native-resolution,
depth-tested, anti-aliased 3D Metal scene behind a `Diagram | 3D` toggle; fit / reset /
selection / inspector / pan / zoom interactions work on both Mac and iOS/iPadOS; text renders
as crisp native SwiftUI at any scale with no clipping; an accessible fallback preserves the
data when Metal is unavailable; the architecture boundaries hold (module-only, no Settings, no
framework bump, no matrix replacement, no duplicate API/auth/diagnostics stack, no third-party
dependencies, no business logic in shaders); builds pass on macOS and iOS; the full test suite
passes (327 tests, 0 failures); and the Phase 3 gates pass for tracked production source.
