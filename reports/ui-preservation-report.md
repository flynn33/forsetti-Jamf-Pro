# UI Preservation Report

## Result

The completed Forsetti retail visual direction was preserved. The 3.24 work added behavior inside the existing obsidian/cyan workspace rather than replacing the shell with baseline list styling.

## Preserved surfaces

- Command Center shell, sidebar, status pills, module cards, and diagnostics panel.
- Existing retail color tokens and glass/metal presentation.
- Existing Computer Search list styling, field catalog sheet, scan button, profile menu, and primary/secondary button styling.
- Existing Mobile Device Search advanced-query components and storage/battery visualization components.

## Added UI surfaces

- Computer Search now includes an Advanced button beside Fields.
- Saved smart filters appear as a section using the existing list row pattern.
- Computer search results now navigate through a typed detail route.
- The new computer detail view uses `forsettiAppBackground`, `forsettiCardSurface`, `HardwareStorageGaugeView`, and `HardwareBatteryRingView`.

## Framework warning disposition

The package gate warns that app-specific UI markers remain under `ForsettiApp/Framework/UI` and `ForsettiApp/Framework/Scanning`. Those files are pre-existing app shell and platform compatibility surfaces in this repository. Moving them during this rebase would create unrelated churn and risk regressions outside the 3.24 Computer Search objective. The final implementation keeps this boundary unchanged and confines new UI work to `ForsettiApp/Modules/ComputerSearch/Views`.

## Screenshot

Main window screenshot: `reports/screenshots/forsetti-3.24-main.png`.
