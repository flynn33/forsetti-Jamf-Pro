# Issues and Fixes Report

| Issue found | Fix applied | Verification |
|---|---|---|
| Product metadata still reported 3.23.2. | Updated `VERSION`, `CURRENT_PROJECT_VERSION`, and `MARKETING_VERSION` to 3.24.0. | Package static gates passed. |
| Computer Search had no computer-specific advanced-search execution path. | Added computer RSQL composition, raw-filter pagination, and client criteria evaluation. | `ComputerSearchParityTests` and full Xcode tests passed. |
| Computer Search did not load tenant computer extension-attribute metadata. | Added `ComputerExtensionAttribute`, metadata loading from the researched modern endpoint, and dynamic field merging. | Focused tests validate client-only extension-attribute fields and dynamic values. |
| Computer records only exposed a small fixed field set. | Added dynamic catalog path extraction for nested objects and arrays. | Focused tests validate disk encryption, local-user arrays, and extension-attribute aggregates. |
| Computer Search result rows lacked detail navigation and hardware visibility. | Added typed detail route, detail refresh, grouped inventory view, and hardware card using the existing storage and battery visuals. | Xcode build and screenshot pass completed. |
| Review thread found identifier fields inferred as numeric search fields. | Tightened field typing to use terminal path components and known numeric keys, keeping UDID, model identifiers, MAC addresses, and directory identifiers string-typed. | Added regression assertions to `ComputerSearchParityTests`; focused parity tests passed. |
| Dashboard layout clipped content at compact and default window sizes. | Moved dashboard body, inspector, and diagnostics into one responsive workspace scroll region; added wrapping header and card text; made top and side navigation scrollable; reduced Mac minimum sizes to match compact behavior. | Xcode build passed; compact and default screenshots captured under `reports/screenshots`. |
| Local check commands initially failed on report content and interpreter mismatch. | Sanitized the static gate transcript and ran the marker guard through Python. | Marker guard and customer-reference checks passed. |
| Package framework-compliance gate emitted a non-failing UI-boundary warning. | Documented the boundary decision and kept new module UI inside the Computer Search module. | Package static gates passed with the same documented warning. |
