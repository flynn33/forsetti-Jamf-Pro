#!/usr/bin/env bash
set -euo pipefail

# sync-wiki.sh — Generates comprehensive wiki pages from project source
# Usage: sync-wiki.sh <wiki-dir> <repo-dir>

WIKI_DIR="${1:?Usage: sync-wiki.sh <wiki-dir> <repo-dir>}"
REPO_DIR="${2:?Usage: sync-wiki.sh <wiki-dir> <repo-dir>}"

VERSION=$(cat "$REPO_DIR/VERSION" | tr -d '[:space:]')
REPO_URL="https://github.com/jim-daley_cwgs/Jamf-Dashboard"

echo "Generating wiki pages for v${VERSION}..."

# ══════════════════════════════════════════════════════════
# _Sidebar.md
# ══════════════════════════════════════════════════════════
cat > "$WIKI_DIR/_Sidebar.md" << 'SIDEBAR_EOF'
## 📖 Navigation

**Overview**
- [[Home]]
- [[Getting Started]]

**Architecture**
- [[Architecture]]
- [[Module System]]
- [[API Reference]]

**Modules**
- [[Computer Search]]
- [[Mobile Device Search]]
- [[Prestage Director]]
- [[Support Technician]]
- [[Reports]]
- [[Deployment Tracker]]

**Platform**
- [[Security]]
- [[Diagnostics]]

---

<sub>Updated by the Jamf Dashboard wiki sync script</sub>
SIDEBAR_EOF

# ══════════════════════════════════════════════════════════
# _Footer.md
# ══════════════════════════════════════════════════════════
cat > "$WIKI_DIR/_Footer.md" << EOF
---
<p align="center">
  <strong>Jamf Dashboard v${VERSION}</strong> · Developed by Jim Daley for Jamf Dashboard<br>
  <a href="${REPO_URL}">Repository</a> · <a href="${REPO_URL}/blob/main/CHANGELOG.md">Changelog</a> · <a href="${REPO_URL}/blob/main/LICENSE">License</a>
</p>
EOF

# ══════════════════════════════════════════════════════════
# Home.md
# ══════════════════════════════════════════════════════════
cat > "$WIKI_DIR/Home.md" << EOF
# 🏠 Jamf Dashboard Wiki

<table>
  <tr>
    <td><strong>Version</strong></td>
    <td><code>v${VERSION}</code></td>
  </tr>
  <tr>
    <td><strong>Platform</strong></td>
    <td>iOS 26.0+ · macOS (Catalyst)</td>
  </tr>
  <tr>
    <td><strong>Language</strong></td>
    <td>Swift · SwiftUI</td>
  </tr>
  <tr>
    <td><strong>License</strong></td>
    <td>Proprietary (Jim Daley / Jamf Dashboard)</td>
  </tr>
</table>

---

## About

Jamf Dashboard is a **modular iOS support application** for Jamf Pro technicians. It provides a unified interface for device inventory search, support ticket workflows, and pre-stage enrollment management through a plugin-style module system.

## Quick Links

| Topic | Description |
|-------|-------------|
| [[Getting Started]] | Requirements, setup, and first run |
| [[Architecture]] | Framework design, service layer, data flow |
| [[Module System]] | How modules work, contracts, package manifests |
| [[API Reference]] | API gateway, authentication, endpoints |
| [[Security]] | Keychain storage, credential lifecycle, entitlements |
| [[Diagnostics]] | Event reporting, export, persistent error logging |

## Built-In Modules

| Module | Purpose |
|--------|---------|
| [[Computer Search]] | Query computer inventory with field profiles and endpoint fallbacks |
| [[Mobile Device Search]] | Query mobile device inventory with section encoding fallbacks |
| [[Prestage Director]] | Manage pre-stage enrollment profiles and device assignments |
| [[Support Technician]] | Metal-powered support pane with category frames, fifteen MDM commands, persistent cache |
| [[Reports]] | Criteria-driven inventory reports with CSV / TXT / Markdown / DOC / PDF export |
| [[Deployment Tracker]] | Apple deployment workflow, Inventory Preload export, ABM verification, shipping |

---

> **Tip:** Use the sidebar navigation to jump between sections, or follow the links above to explore specific topics.
EOF

# ══════════════════════════════════════════════════════════
# Getting-Started.md
# ══════════════════════════════════════════════════════════
cat > "$WIKI_DIR/Getting-Started.md" << 'EOF'
# 🚀 Getting Started

## Requirements

| Requirement | Details |
|-------------|---------|
| **IDE** | Xcode 26+ |
| **Deployment Target** | iOS 26.0+ |
| **Jamf Pro Server** | Valid server URL |
| **Authentication** | API Client credentials **or** Username/Password |

## Setup

1. Clone the repository
2. Open `Jamf Dashboard.xcodeproj` in Xcode
3. Build and run on an iOS 26.0+ target (or Mac Catalyst)

## First Run

```
Settings → Jamf Credentials → Enter server URL
    → Select authentication method
    → Enter credentials
    → Verify Connection ✓
    → Save Credentials
    → Return to Dashboard
```

### Authentication Methods

| Method | Fields | Endpoint |
|--------|--------|----------|
| **API Client** | `client_id` + `client_secret` | `api/v1/oauth/token` |
| **Username/Password** | `username` + `password` | `api/v1/auth/token` |

> **Important:** Credentials are only saved after a successful verification. The credential store persists only the fields relevant to the selected authentication method.

## Local Data Paths

| Data | Location |
|------|----------|
| Credentials | Keychain (`com.jamfdashboard.app`) |
| Module packages | `~/Library/Application Support/JamfDashboard/installed-module-packages.json` |
| Computer search profiles | `~/Library/Application Support/JamfDashboard/computer-search-profiles.json` |
| Mobile device search profiles | `~/Library/Application Support/JamfDashboard/mobile-device-search-profiles.json` |
| Diagnostics export | `~/Documents/JamfDashboardDiagnostics/` |
| Persistent error log | `~/Documents/JamfDashboardDiagnostics/jamf-dashboard-errors.ndjson` |
EOF

# ══════════════════════════════════════════════════════════
# Architecture.md
# ══════════════════════════════════════════════════════════
cat > "$WIKI_DIR/Architecture.md" << 'EOF'
# 🏗️ Architecture

## High-Level Design

Jamf Dashboard uses a **two-tier architecture**: a centralized **Framework Layer** providing shared services, and a **Module Layer** delivering feature-specific workflows.

```mermaid
graph TD
    subgraph App["Application Layer"]
        A["JamfDashboardApp (@main)"]
        DV["DashboardView (Module grid)"]
    end

    subgraph Framework["Framework Layer"]
        FC["JamfFrameworkContainer (Orchestrator)"]
        AG["JamfAPIGateway (HTTP actor)"]
        AS["JamfAuthenticationService (Token actor)"]
        CS["JamfCredentialsStore (Keychain)"]
        DC["DiagnosticsCenter (Event actor)"]
        MR["ModuleRegistry (Catalog)"]
        PM["ModulePackageManager (Lifecycle)"]
    end

    subgraph Modules["Module Layer"]
        M1[Computer Search]
        M2[Mobile Device Search]
        M3[Prestage Director]
        M4[Support Technician]
    end

    A --> FC
    A --> DV
    FC --> AG
    FC --> AS
    FC --> CS
    FC --> DC
    FC --> MR
    FC --> PM
    AG --> AS
    AS --> CS

    MR --> M1
    MR --> M2
    MR --> M3
    MR --> M4

    style Framework fill:#e8f4fd,stroke:#2196f3
    style Modules fill:#e8f5e9,stroke:#4caf50
    style App fill:#fff3e0,stroke:#ff9800
```

## Directory Structure

```
JamfDashboardApp/
├── App/                          # Application entry point
│   ├── JamfDashboardApp.swift    # @main struct
│   └── JamfFrameworkContainer.swift
├── DesignSystem/                 # Jamf Dashboard visual identity
│   ├── DashboardColors.swift
│   ├── DashboardTheme.swift
│   ├── DashboardMetalBackgroundView.swift
│   ├── DashboardSearchResultTypography.swift
│   └── ViewModifiers/
│       └── DashboardButtonStyle.swift
├── Framework/
│   ├── Core/                     # Contracts, models, errors
│   ├── Networking/               # API gateway + auth service
│   ├── Security/                 # Keychain storage
│   ├── Diagnostics/              # Event reporting
│   ├── Modules/                  # Module registry + package manager
│   ├── UI/                       # Dashboard, Settings, Diagnostics views
│   └── Scanning/                 # Barcode/QR scanner
└── Modules/
    ├── ComputerSearch/
    ├── MobileDeviceSearch/
    ├── PrestageDirector/
    └── SupportTechnician/
```

## Swift Concurrency Model

The codebase uses Swift structured concurrency with clear isolation boundaries:

| Type | Isolation | Purpose |
|------|-----------|---------|
| `JamfAPIGateway` | `actor` | Thread-safe HTTP request dispatch |
| `JamfAuthenticationService` | `actor` | Token lifecycle management |
| `DiagnosticsCenter` | `actor` | Event stream and persistence |
| `ModulePackageStore` | `actor` | Package file I/O |
| `JamfFrameworkContainer` | `@MainActor` | UI-bound service orchestration |
| `JamfCredentialsStore` | `@MainActor` | Observable credential state |
| `ModuleRegistry` | `@MainActor` | Observable module catalog |
| `ModulePackageManager` | `@MainActor` | Observable package state |
| All ViewModels | `@MainActor` | UI state management |

## Data Flow

```mermaid
flowchart LR
    subgraph User["User Action"]
        U[Search Query]
    end

    subgraph Module["Module Layer"]
        VM[ViewModel]
        SVC[API Service]
    end

    subgraph Framework["Framework Services"]
        AG[API Gateway]
        AUTH[Auth Service]
        DIAG[Diagnostics]
    end

    subgraph External["External"]
        JAMF[Jamf Pro Server]
        KC[Keychain]
    end

    U --> VM
    VM --> SVC
    SVC --> AG
    AG --> AUTH
    AUTH --> KC
    AUTH --> JAMF
    AG --> JAMF
    AG --> DIAG
    JAMF --> AG
    AG --> SVC
    SVC --> VM
    VM --> U

    style User fill:#fff3e0,stroke:#ff9800
    style Module fill:#e8f5e9,stroke:#4caf50
    style Framework fill:#e8f4fd,stroke:#2196f3
    style External fill:#fce4ec,stroke:#e91e63
```

## Design System

The **Dashboard Design System** provides visual consistency:

| Component | Purpose |
|-----------|---------|
| `DashboardColors` | App colors (BluePrimary, BlueSecondary, GreenPrimary) |
| `DashboardTheme` | Spacing, radii, gradients, and semantic tokens |
| `DashboardButtonStyle` | Primary (gradient), Secondary (outlined), Danger (red) |
| `DashboardMetalBackgroundView` | GPU-accelerated background effects |
| `DashboardSearchResultTypography` | Consistent search result formatting |
| View Modifiers | `.dashboardAppBackground()`, `.dashboardRoundedTypography()`, `.dashboardURLKeyboard()` |
EOF

# ══════════════════════════════════════════════════════════
# Module-System.md
# ══════════════════════════════════════════════════════════
cat > "$WIKI_DIR/Module-System.md" << 'EOF'
# 🧩 Module System

## Overview

The module system enables **plugin-style feature delivery**. Each module is a self-contained workflow that receives framework services through dependency injection.

## Module Lifecycle

```mermaid
sequenceDiagram
    participant App as JamfDashboardApp
    participant FC as FrameworkContainer
    participant PM as PackageManager
    participant PS as PackageStore
    participant MR as ModuleRegistry

    App->>FC: init()
    FC->>PM: bootstrap()
    PM->>PS: loadPackages()
    PS-->>PM: [ModulePackageManifest]

    Note over PM: Ensure bundled defaults exist

    PM->>MR: register(modules)
    MR-->>App: modules available

    Note over App: DashboardView renders module grid

    App->>MR: module(withID:)
    MR-->>App: JamfModule
    App->>App: makeRootView(context:)
```

## Module Contract

All modules implement the `JamfModule` protocol:

```swift
protocol JamfModule {
    var id: String { get }
    var title: String { get }
    var subtitle: String { get }
    var iconSystemName: String { get }
    func makeRootView(context: ModuleContext) -> AnyView
}
```

## Dependency Injection

Modules receive shared services through `ModuleContext`:

```swift
struct ModuleContext {
    let apiGateway: JamfAPIGateway
    let credentialsStore: JamfCredentialsStore
    let diagnosticsReporter: any DiagnosticsReporting
}
```

This ensures modules are **loosely coupled** to the framework — they depend on protocols, not concrete implementations.

## Package Management

### Package Manifest Format

Minimum required fields:

```json
{
  "package_id": "com.jamftool.modules.example",
  "module_type": "computer-search",
  "package_version": "1.0.0"
}
```

Optional fields:

| Field | Type | Description |
|-------|------|-------------|
| `module_display_name` | String | Human-readable module name |
| `module_subtitle` | String | Short description |
| `icon_system_name` | String | SF Symbols icon name |

### Supported Module Types

| Type | Module |
|------|--------|
| `computer-search` | Computer Search |
| `mobile-device-search` | Mobile Device Search |
| `support-technician` | Support Technician |
| `prestage-director` | Prestage Director |
| `reports` | Reports |
| `deployment-tracker` | Deployment Tracker |

### Package Operations

```mermaid
flowchart TD
    A[App Launch] --> B{Packages exist?}
    B -->|No| C[Bootstrap bundled defaults]
    B -->|Yes| D{Defaults missing?}
    C --> E[Register modules]
    D -->|Yes| F[Re-apply missing defaults]
    D -->|No| E
    F --> E

    G[User imports manifest] --> H{Duplicate ID?}
    H -->|Yes| I[Reject with error]
    H -->|No| J[Install package]
    J --> K[Update registry]

    style A fill:#fff3e0,stroke:#ff9800
    style E fill:#e8f5e9,stroke:#4caf50
    style I fill:#fce4ec,stroke:#e91e63
```

### Persistence

Installed packages are persisted to:
```
~/Library/Application Support/JamfDashboard/installed-module-packages.json
```

Bundled default modules are **protected** — they cannot be removed and are automatically re-applied if missing during bootstrap.
EOF

# ══════════════════════════════════════════════════════════
# Computer-Search.md
# ══════════════════════════════════════════════════════════
cat > "$WIKI_DIR/Computer-Search.md" << 'EOF'
# 💻 Computer Search Module

**Package ID:** `com.jamftool.modules.computer-search`
**Icon:** `desktopcomputer`

## Features

- Search computers by **name**, **serial number**, **username**, or **email**
- Customizable **field catalog** for selective column display
- **Reusable search profiles** — save and restore field selections
- **Pre-stage enrichment** — displays pre-stage enrollment status alongside results

## API Endpoint Fallback Strategy

The module implements a resilient multi-version endpoint fallback:

```mermaid
flowchart TD
    A[Search Request] --> B[Try Jamf Pro API v3]
    B -->|Success| C[Parse & Display Results]
    B -->|Failure| D[Try Jamf Pro API v2]
    D -->|Success| C
    D -->|Failure| E[Try Jamf Pro API v1]
    E -->|Success| C
    E -->|Failure| F[Report Error to User]

    B --> |401| G[Refresh Token & Retry]
    G --> B

    style C fill:#e8f5e9,stroke:#4caf50
    style F fill:#fce4ec,stroke:#e91e63
    style G fill:#fff3e0,stroke:#ff9800
```

## Field Catalog

The field catalog organizes inventory data into sections:

| Section | Examples |
|---------|----------|
| General | Name, Serial Number, Asset Tag, Last Inventory |
| Hardware | Model, Processor, RAM, Storage |
| Operating System | OS Name, OS Version, OS Build |
| User & Location | Username, Email, Department, Building |
| Security | FileVault Status, SIP Status, Gatekeeper |
| Purchasing | Purchase Date, Warranty Expiration |

## Search Profiles

Profiles persist field selections for quick reuse:

```
~/Library/Application Support/JamfDashboard/computer-search-profiles.json
```

Each profile contains:
- **ID** (UUID)
- **Name** (user-defined)
- **Field Keys** (selected inventory fields)

## Fallback Behavior

When the Jamf Pro instance has restricted API privileges:
1. Query/filter strategies are progressively simplified
2. Unavailable sections display privilege-aware messaging
3. All fallback events are reported to diagnostics
EOF

# ══════════════════════════════════════════════════════════
# Mobile-Device-Search.md
# ══════════════════════════════════════════════════════════
cat > "$WIKI_DIR/Mobile-Device-Search.md" << 'EOF'
# 📱 Mobile Device Search Module

**Package ID:** `com.jamftool.modules.mobile-device-search`
**Icon:** `ipad.and.iphone`

## Features

- Search mobile devices by **serial number** or **username**
- Customizable **field catalog** with flexible field selection
- **Reusable search profiles** for saved field configurations
- **Pre-stage enrichment** with caching for pre-stage name resolution

## Search Fallback Strategy

```mermaid
flowchart TD
    A[Search Request] --> B[Wildcard Query]
    B -->|Success| C[Parse Results]
    B -->|No Results| D[Exact-Match Fallback]
    D -->|Success| C
    D -->|Failure| E[Report Error]

    C --> F{Section Encoding}
    F --> G[Modern Section Names]
    G -->|Success| H[Display Results]
    G -->|Failure| I[Legacy Section Names]
    I -->|Success| H
    I -->|Failure| J[No-Section Fallback]
    J --> H

    style H fill:#e8f5e9,stroke:#4caf50
    style E fill:#fce4ec,stroke:#e91e63
```

## Field Catalog Sections

| Section | Examples |
|---------|----------|
| General | Name, Serial Number, UDID, Wi-Fi MAC |
| Location | Username, Email, Department |
| Hardware | Model, Capacity, Battery Level |
| Security | Managed Status, Supervised, Encrypted |
| Applications | Installed Apps, App Count |

## Pre-Stage Enrichment

The module resolves pre-stage enrollment profile names for each device:
1. Check local cache for known pre-stage mappings
2. If cache miss, query Jamf Pro API for pre-stage detail
3. Cache result for subsequent lookups
4. Display pre-stage name/ID alongside device results

## Search Profiles

```
~/Library/Application Support/JamfDashboard/mobile-device-search-profiles.json
```
EOF

# ══════════════════════════════════════════════════════════
# Prestage-Director.md
# ══════════════════════════════════════════════════════════
cat > "$WIKI_DIR/Prestage-Director.md" << 'EOF'
# 🎯 Prestage Director Module

**Package ID:** `com.jamftool.modules.prestage-director`
**Icon:** `list.bullet.clipboard`

## Features

- List all **pre-stage enrollment profiles** from Jamf Pro
- View **assigned devices** per profile
- **Filter devices** by serial number
- **Multi-select operations** with progress reporting
- **Rollback handling** for failed move operations

## Operations Workflow

```mermaid
flowchart TD
    A[Select Pre-Stage Profile] --> B[Load Assigned Devices]
    B --> C[Filter / Select Devices]
    C --> D{Operation}

    D -->|Remove| E[Remove from Current Pre-Stage]
    D -->|Move| F[Select Target Pre-Stage]

    F --> G[Remove from Source]
    G -->|Success| H[Add to Target]
    G -->|Failure| I[Report Error]

    H -->|Success| J[Operation Complete]
    H -->|Failure| K[Attempt Rollback]
    K --> L[Re-add to Source]

    E --> J

    style J fill:#e8f5e9,stroke:#4caf50
    style I fill:#fce4ec,stroke:#e91e63
    style K fill:#fff3e0,stroke:#ff9800
```

## Data Model

| Model | Fields |
|-------|--------|
| `PrestageSummary` | ID, Name, Version Lock |
| `PrestageAssignedDevice` | ID, Serial Number, Device Name, UDID, Model |
| `PrestageDirectorOperationProgress` | Title, Detail, Fraction Completed |

## Move Operation Safety

The move operation is a **two-phase process**:

1. **Phase 1:** Remove selected devices from the source pre-stage
2. **Phase 2:** Add devices to the target pre-stage

If Phase 2 fails, the module **attempts rollback** by re-adding devices to the source pre-stage. Progress is reported throughout both phases via the `PrestageDirectorOperationProgress` model.
EOF

# ══════════════════════════════════════════════════════════
# Support-Technician.md
# ══════════════════════════════════════════════════════════
cat > "$WIKI_DIR/Support-Technician.md" << 'EOF'
# 🔧 Support Technician Module

**Package ID:** `com.jamftool.modules.support-technician`
**Icon:** `wrench.and.screwdriver`

## Features

- **Unified search** across computers and mobile devices from one screen — by **username** or **serial number**, scope-filterable to All / Computers / Mobile Devices.
- Detail pane built as a stack of independently scrollable **category frames** with an animated Metal backdrop (`DashboardMetalBackgroundView`).
- Full Jamf v1 / v2 / typed-platform-nest payload-shape support — iPhone, iPad, Apple TV, Vision Pro, Watch, and Mac all populate correctly.
- Persistent on-disk cache for device-detail payloads and the tenant policy list, with Refresh + Clear Cache controls.
- Fifteen MDM commands across Mac and mobile.
- Inventory verification polling for state-changing commands (Restart / Shutdown / Erase / ClearPasscode / LogOut).
- Verbose privilege-denial popup names the specific Jamf privilege a failed command requires.
- Metal-rendered command-lifecycle indicator with a SwiftUI fallback (the `DesignSystem/Commands` widget).

## Search Workflow

```mermaid
flowchart TD
    A[Enter Search Query] --> B{Search Scope}
    B -->|All| C[Search Computers + Mobile Devices]
    B -->|Computers| D[Search Computers Only]
    B -->|Mobile Devices| E[Search Mobile Devices Only]

    C --> F[Unified Results List]
    D --> F
    E --> F

    F --> G[Select Device]
    G --> H{Cached payload fresh?}
    H -->|Yes < 5 min| I[Load from on-disk cache]
    H -->|No| J[Fetch from Jamf Pro]
    J --> K[Write to cache]
    I --> L[Render category frames]
    K --> L

    style F fill:#e8f4fd,stroke:#2196f3
    style L fill:#e8f5e9,stroke:#4caf50
    style K fill:#fff8e1,stroke:#ffa000
```

## Category Frames

| Frame | Contents |
|-------|----------|
| **General** | Tappable card grid — Model, CPU, GPU, RAM, plus a Storage gauge + Battery ring row. Tap any card to open `HardwareDetailSheet`. Footer: Restart Device, Shutdown. |
| **OS** | Version, build, supplemental build, RSR. Footer: Schedule OS Update. |
| **Security** | Traffic-light status cards + Posture subsection drawn from security-relevant diagnostics. |
| **Network** | IP / Wi-Fi MAC / Bluetooth MAC / IMEI / MEID / ICCID / EID / carrier. |
| **Applications** | Installed app list with up to 60 names + "Showing first 60 of N" tail on mobile. Application Manager sheet on Mac. |
| **Profiles** | Typed configuration-profile records with name, identifier, scope. Falls back to legacy categorised view when the typed extractor returns nothing. |
| **Groups** | Per-device group membership (smart vs static badge). |
| **Policy** | Tenant-wide policy list, lazy-loaded on first appearance, cached per session, refreshable. |
| **Extension Attributes** | Tenant EA list with each device's value or `(not reported)` placeholder. |
| **User Accounts** | Role-grouped: Jamf Management, Admin, User, Other. |
| **Command History** | Pending / completed / failed / not-now bucket counts + chronological list. |
| **Diagnostics** | App count, OS version, battery level, connectivity, FileVault / Supervision / Encryption posture. |
| **Last Action** | Always-present indicator of the last MDM command and its lifecycle phase. |

## General Frame — Hardware Cards

Five tappable cards in a two-column grid:

| Card | Source | Detail-sheet contents |
|------|--------|-----------------------|
| Model | `hardware.model` / `ios.model` / catalog lookup | Model name, identifier, number, chip |
| CPU | `hardware.cpuType` (Mac) / `AppleDeviceModelCatalog` (mobile) | Chip name, clock speed, cores |
| GPU | Catalog | GPU and Neural-engine core counts |
| RAM | `hardware.totalRamMegabytes` / catalog | Total memory (with M-series iPad Pro 8 GB / 16 GB split-tier logic) |
| Storage + Battery row | `storage.disks[].partitions[].sizeMegabytes`, `hardware.batteryCapacityPercent` / `hardware.batteryLevel`, `hardware.batteryHealth` | Capacity, available, used, used %, level, health |

## Security Frame — Status Cards

Two-column `LazyVGrid` of state cards. Cards whose underlying value is `nil` are omitted entirely.

| Color | Meaning |
|-------|---------|
| 🟢 Green | Enabled / compliant / capable |
| 🔴 Red | Disabled / non-compliant / not-capable / jailbreak-detected |
| 🟡 Yellow | Not configured |
| 🟠 Orange | Unknown |

Cards rendered: Encrypted, Firewall, Supervised, Activation Lock, Lost Mode, Passcode Set, Passcode Compliant, Recovery Lock, Block Encryption, File Encryption, Jailbroken.

The "Posture" subsection below the cards lists security-relevant diagnostics extracted from the always-on Diagnostics card (FileVault, Encryption, Supervision, Activation Lock, Passcode, Recovery Lock, Lost Mode, Jailbroken, Gatekeeper, SIP, XProtect, Firewall, Compliant).

## User Accounts Frame — Role Grouping

| Group | Members | Footer actions |
|-------|---------|----------------|
| Jamf Management | `jssmanage`, `jamfmanage`, `jamfadmin` — tagged with a `jssmanage` chip and `gearshape.circle.fill` icon | View jssmanage Password, View LAPS Password, View Device Lock PIN, Rotate LAPS Password |
| Admin Accounts | Non-system accounts with `isAdmin = true` | Log Out User, Clear Passcode, Clear Restrictions Password |
| User Accounts | Non-system, non-admin accounts | (shared footer) |
| Other accounts (N) | Collapsed `DisclosureGroup` containing system / service / hidden accounts — UID < 500 and `_`-prefixed usernames are treated as system | — |

## MDM Commands

| Command | Mac | Mobile | API path |
|---------|:---:|:------:|----------|
| Update Inventory | ✅ | ✅ | DDM sync with `POST /JSSResource/computercommands/command/UpdateInventory/id/{id}` Classic fallback |
| Blank Push | ✅ | ✅ | v2 |
| Discover Applications | ✅ | ✅ | v2 |
| Restart Device | ✅ | ✅ | v2 |
| Shutdown | ✅ | ✅ | v2 |
| Lock Device | ✅ | ✅ | v2 |
| Log Out User | ✅ | — | v2 |
| Clear Passcode | — | ✅ | v2 |
| Clear Restrictions Password | — | ✅ | v2 |
| Erase Device | ✅ | ✅ | v2 (typed `confirm` required) |
| View FileVault Recovery Key | ✅ | — | v2 |
| View Recovery Lock | ✅ | — | v2 |
| View Device Lock PIN | ✅ | — | v2 |
| View LAPS Password | ✅ | — | v2 |
| Rotate LAPS Password | ✅ | — | v2 (typed `confirm` required) |
| View jssmanage Password | ✅ | — | `GET /api/v2/local-admin-password/{clientManagementId}/account/jssmanage/password` |
| Enable FileVault | ✅ | — | v2 |
| Redeploy Management Framework | ✅ | — | `POST /api/v1/jamf-management-framework/redeploy/{computerId}` |
| Enable / Disable Remote Management | ✅ | — | v2 (typed `confirm` required for enable) |
| Disable Remote Desktop | ✅ | — | v2 |
| Settings Sync | ✅ | — | v2 |
| Bluetooth on / off | ✅ | ✅ | Classic `Settings…Bluetooth` |
| Wi-Fi on / off | ✅ | ✅ | Classic `Settings…Wifi` |
| Schedule OS Update | ✅ | ✅ | v2 |
| Enable Lost Mode | — | ✅ | v2 |
| Disable Lost Mode | — | ✅ | v2 |
| Play Lost Mode Sound | — | ✅ | v2 |
| Request Device Location | — | ✅ | v2 |
| Refresh Cellular Plans | — | ✅ | v2 |

Destructive actions flow through `SupportTypedConfirmationSheet` requiring the lowercase phrase `confirm`. Read-only credential-view actions (FileVault Key, Recovery Lock, Device Lock PIN, LAPS Password) skip confirmation because no state changes.

## Command Lifecycle

```mermaid
stateDiagram-v2
    [*] --> idle
    idle --> sending : invoke()
    sending --> queued : Jamf 202
    queued --> verifying : verifying action
    queued --> succeeded : non-verifying action
    verifying --> succeeded : lastInventoryUpdate advanced
    verifying --> timedOut : 30s × 20 attempts elapsed
    sending --> failed : non-2xx
    queued --> failed : Jamf error
    succeeded --> idle : Dismiss
    failed --> idle : Dismiss
    timedOut --> idle : Dismiss
```

- Minimum dwells: ~700ms at `.sending`, ~600ms at `.queued` (verifying actions exempt).
- Inventory verification budget: 30 s × 20 attempts (10 minutes).
- Indicator color: blue = in-flight, green = succeeded, red = failed, amber = timed out.

## Persistent Cache

| File | Contents | Default freshness |
|------|----------|-------------------|
| `~/Library/Containers/com.forsetti.jamfdashboard/Data/Library/Caches/SupportTechnician/device-detail-<id>.json` | Full raw payload per device | 5 minutes |
| `~/Library/Containers/com.forsetti.jamfdashboard/Data/Library/Caches/SupportTechnician/tenant-policies.json` | `/JSSResource/policies` response | 5 minutes |

| Control | Behaviour |
|---------|-----------|
| Refresh | Re-fetches the currently-selected device's payload bypassing the cache |
| Clear Cache | Wipes every cached file so the next read re-pulls from Jamf Pro |

## Diagnostic Payload Dump

Every device-detail fetch writes `last-detail-payload-<deviceID>.json` to `~/Library/Containers/com.forsetti.jamfdashboard/Data/Documents/JamfDashboardDiagnostics/` so the operator can verify exactly what Jamf returned for the selected device without rebuilding.

## Privilege-Denial Popup

When a command fails with `403` / `INVALID_PRIVILEGE`, the modal shows:

- Action title
- The specific Jamf privilege the role likely needs (mapped per command in `likelyPrivilege(for:)`)
- A remediation suggestion
- Raw Jamf response body for advanced debugging

Non-privilege failures (404, 405, missing-management-identifier) get tailored remediation text.

> **Note:** Action availability is determined dynamically based on device type, available fields, and the command's `requiredTypedPhrase` / `confirmationStrength`. Commands needing a `managementID` still render in the action list — invoking one without it surfaces the privilege-denial popup naming the missing field instead of silently hiding the action.
EOF

# ══════════════════════════════════════════════════════════
# Reports.md
# ══════════════════════════════════════════════════════════
cat > "$WIKI_DIR/Reports.md" << 'EOF'
# 📊 Reports Module

**Package ID:** `com.jamftool.modules.reports`
**Icon:** `chart.bar.doc.horizontal`

## Features

- **Default device-type counts** — Mac, iPad, iPhone, Other, Unknown, Total — summarised on module open.
- **Criteria-driven report builder** with reusable fields, grouping, and chart preferences.
- **Visual report pages** with segmented device-type gauges (Metal-backed with a SwiftUI fallback), distribution bars, and tabular records.
- **In-memory inventory cache** keeps a single fetched snapshot for the module session so iterating on reports does not re-hit Jamf Pro per change.
- **Five export formats** — `.csv`, `.txt`, `.md`, Word-readable `.doc`, and `.pdf`. DOC and PDF include visual aids.

## Workflow

```mermaid
flowchart TD
    A[Open Reports module] --> B{Cache built?}
    B -->|No| C[Fetch all inventory<br/>computers + mobile]
    B -->|Yes| D[Use cached snapshot]
    C --> E[Cache snapshot in-memory]
    E --> F[Render default counts]
    D --> F

    F --> G[New Report sheet]
    G --> H[Pick domain<br/>computer / mobile / both]
    H --> I[Pick frames<br/>columns to include]
    I --> J[Build criteria<br/>field + operator + value]
    J --> K[Validate]
    K -->|OK| L[Generate Report]
    K -->|Errors| G

    L --> M[Apply criteria<br/>client-side from cache]
    M --> N[Render report page]
    N --> O{Export?}
    O --> P[CSV]
    O --> Q[TXT]
    O --> R[MD]
    O --> S[DOC]
    O --> T[PDF]

    U[Refresh toolbar] --> V[Invalidate cache] --> C

    style E fill:#fff8e1,stroke:#ffa000
    style L fill:#e8f5e9,stroke:#4caf50
```

## Inventory Cache

The first time the user opens the module the `ReportsInventoryService` actor builds an in-memory snapshot of the tenant's inventory:

| Domain | Sections fetched |
|--------|------------------|
| Computers | `general`, `hardware`, `operatingSystem`, `userAndLocation`, `extensionAttributes` |
| Mobile devices | `general`, `hardware`, `location`, `security`, `extensionAttributes` |

Every subsequent `loadReport` call filters that snapshot client-side via `ReportsQueryPlanner.matches(record:criteria:)` rather than issuing another paginated fetch. Heavy or unused sections (plugins, fonts, packages, applications, …) are deliberately excluded from the cache build.

Memory footprint: a 10 000-device tenant holds roughly 30–80 MB of cached records depending on Extension Attribute population.

The cache lives for the `ReportsInventoryService` actor instance, which `ReportsModule.makeRootView(context:)` constructs per module open. Closing and re-opening the Reports module gets a fresh cache. The toolbar **Refresh** button is the only in-session invalidation.

## Diagnostics

| Event | Emitted when | Includes |
|-------|--------------|----------|
| `cache-build-start` | First inventory pull begins | — |
| `cache-build-finish` | First inventory pull completes | `computer_count`, `mobile_count`, `elapsed_seconds` |
| `computer-pages` / `mobile-pages` | During cache build | Pagination details with "for cache" message |
| `load-start` | Any `loadReport` call | `cache_hit: bool` |
| `load-finish` | Any `loadReport` call | `cache_hit`, `candidate_count`, `filtered_record_count` |

## New Report Sheet

The sheet uses the project's standard `List` + `.dashboardInsetGroupedListStyle()` + sticky-bottom-bar pattern that `AdvancedSearchView` and `AdvancedFieldPickerView` use.

| Section | Contents |
|---------|----------|
| Report | Name, domain (computers / mobile / both), chart preferences |
| Frames | Toggle rows for each available column/frame |
| Criteria | Field + operator + value rows, multi-criteria with AND/OR combinator |
| Validation | Error list (rendered in the bottom bar above the Generate button when present) |

## Export Formats

| Format | Visual aids | Use case |
|--------|:-----------:|----------|
| `.csv` | — | Spreadsheet import |
| `.txt` | — | Tab-separated plain text |
| `.md` | — | Markdown table |
| `.doc` | ✅ | Word-readable HTML — gauges + distribution bars embedded |
| `.pdf` | ✅ | Print / archive — gauges + distribution bars embedded |
EOF

# ══════════════════════════════════════════════════════════
# Deployment-Tracker.md
# ══════════════════════════════════════════════════════════
cat > "$WIKI_DIR/Deployment-Tracker.md" << 'EOF'
# 🚚 Deployment Tracker Module

**Package ID:** `com.jamftool.modules.deployment-tracker`
**Icon:** `shippingbox.and.arrow.backward`

## Purpose

Tracks Apple deployments end-to-end: vendor order import, Jamf Inventory Preload generation, ABM verification, SD+ exports, and shipping workflows. Built to give the deployment technician one workspace from a vendor's order-confirmation file to the device records landing in Jamf Pro.

## Architecture

```mermaid
flowchart LR
    A[Vendor order CSV] --> B[DeploymentVendorImportParser]
    B --> C[DeploymentVendorImportModels]
    C --> D[Workflow Engine]

    E[Model identifier] --> F[DeploymentHardwareDerivationService]
    F --> G[DeploymentAppleDeviceModelCatalog]
    G --> H[Marketing name<br/>chip family<br/>RAM<br/>storage tier]
    H --> D

    D --> I[Workbench]
    I --> J[CoreDataDeploymentTrackerStore]

    I --> K[RecordsManagementExportService]
    K --> L[Jamf Inventory Preload CSV]

    I --> M[KPI Ring View<br/>Metal renderer]
    M -.fallback.-> N[KPI Ring Fallback View<br/>pure SwiftUI]

    style B fill:#e8f4fd,stroke:#2196f3
    style G fill:#fff8e1,stroke:#ffa000
    style K fill:#e8f5e9,stroke:#4caf50
    style J fill:#fce4ec,stroke:#e91e63
```

## Sub-areas

| Sub-area | File(s) | Purpose |
|----------|---------|---------|
| Module composition root | `Modules/DeploymentTracker/DeploymentTrackerModule.swift` | Wires framework services into the tracker view model |
| Workflow engine | `Workflow/DeploymentWorkflowEngine.swift` | Drives the deployment state machine |
| Core models | `Models/DeploymentTrackerCoreModels.swift`, `Models/DeploymentTrackerFieldModels.swift` | Deployment records, field metadata |
| Workbench | `Workbench/DeploymentWorkbenchModels.swift` | Technician's current working set |
| Workbench views | `Views/DeploymentWorkbenchViews.swift`, `Views/DeploymentWorkspaceViews.swift` | Workspace UI |
| Guide view | `Views/DeploymentTrackerGuideView.swift` | First-time onboarding / help |
| Apple catalog | `AppleCatalog/DeploymentAppleDeviceModelCatalog.swift`, `DeploymentAppleCatalogService.swift` | Local model-identifier → marketing-name catalog |
| Hardware derivation | `AppleCatalog/DeploymentHardwareDerivationService.swift` | Resolves chip family, RAM, storage tier without a network round trip |
| Vendor imports | `Imports/DeploymentVendorImportParser.swift`, `Imports/DeploymentVendorImportModels.swift` | Parses order-confirmation files from Apple resellers |
| Records management | `Records/RecordsManagementExportService.swift`, `Records/RecordsManagementModels.swift` | Writes Jamf Inventory Preload CSVs |
| Persistence | `Persistence/DeploymentTrackerStore.swift`, `Persistence/CoreDataDeploymentTrackerStore.swift` | Local Core Data store for in-flight deployments |
| KPI ring rendering | `Rendering/DeploymentKPIRingRenderer.swift`, `Rendering/DeploymentKPIRingView.swift`, `Rendering/DeploymentKPIRingFallbackView.swift` | Metal ring gauge with SwiftUI fallback |

## Apple Device Catalog

`DeploymentAppleDeviceModelCatalog` is a compile-time table of every Apple model identifier the deployment process is likely to see. Lookup happens in-process so the technician does not have to wait on a network round trip while importing a vendor file.

The hardware derivation service combines the catalog entry with the order-line storage tier and any vendor-supplied configuration codes to produce:

- Marketing name (e.g. "MacBook Pro 14-inch, M4")
- Chip family + variant
- RAM (with M-series iPad Pro 8 GB / 16 GB split-tier logic)
- Storage tier

## Vendor Imports

The parser reads order-confirmation files from common Apple resellers. Each line becomes a typed `DeploymentVendorImportLine` with a serial number, model identifier (when present), purchase order reference, and any vendor-specific fields the format exposes.

When the model identifier is absent the parser falls through to text-match-based catalog inference so the workbench can still derive the marketing name.

## Records Management Export

Writes Jamf Inventory Preload CSVs that can be uploaded directly to Jamf Pro. The export service maps the workbench's deployment records into the exact column order and value formatting Jamf Pro's Inventory Preload importer requires.

## Persistence

`CoreDataDeploymentTrackerStore` keeps in-flight deployments locally so the technician can pause and resume a deployment across app launches. Storage lives in the app's Core Data store at the standard sandbox location.

## KPI Ring Gauge

The Metal-rendered ring gauge (`DeploymentKPIRingRenderer` + `DeploymentKPIRingView`) shows progress toward a deployment milestone. On devices where Metal init fails the SwiftUI fallback (`DeploymentKPIRingFallbackView`) preserves the same semantics and visual language.

## Tests

| Test target | Coverage |
|-------------|----------|
| `DeploymentTrackerModuleTests` | Module wiring, workflow engine, imports, catalog derivation, records export |
| `DeploymentTrackerGuideTests` | Onboarding guide flow |
EOF

# ══════════════════════════════════════════════════════════
# API-Reference.md
# ══════════════════════════════════════════════════════════
cat > "$WIKI_DIR/API-Reference.md" << 'EOF'
# 🔌 API Reference

## JamfAPIGateway

The `JamfAPIGateway` is a Swift **actor** that centralizes all HTTP communication with the Jamf Pro server.

### Request Interface

```swift
func request(
    path: String,
    method: HTTPMethod = .get,
    queryItems: [URLQueryItem] = [],
    body: Data? = nil,
    additionalHeaders: [String: String] = [:]
) async throws -> Data
```

### Supported HTTP Methods

| Method | Usage |
|--------|-------|
| `GET` | Inventory queries, profile listings, device details |
| `POST` | Token requests, management commands |
| `PUT` | Pre-stage scope updates |
| `PATCH` | Partial record updates |
| `DELETE` | Scope removal operations |

### Request Flow

```mermaid
sequenceDiagram
    participant Module
    participant Gateway as API Gateway
    participant Auth as Auth Service
    participant Server as Jamf Pro

    Module->>Gateway: request(path, method, ...)
    Gateway->>Auth: getToken()

    alt Token Cached & Valid
        Auth-->>Gateway: Bearer token
    else Token Expired
        Auth->>Server: POST /api/v1/oauth/token
        Server-->>Auth: New token
        Auth-->>Gateway: Bearer token
    end

    Gateway->>Server: HTTP request + Bearer token

    alt 2xx Success
        Server-->>Gateway: Response data
        Gateway-->>Module: Data
    else 401 Unauthorized
        Gateway->>Auth: invalidateToken()
        Auth->>Server: POST /api/v1/oauth/token
        Server-->>Auth: New token
        Gateway->>Server: Retry request
        Server-->>Gateway: Response data
        Gateway-->>Module: Data
    else Other Error
        Server-->>Gateway: Error response
        Gateway->>Gateway: Report to diagnostics
        Gateway-->>Module: JamfFrameworkError
    end
```

## Authentication Endpoints

| Flow | Endpoint | Body |
|------|----------|------|
| **API Client** | `POST /api/v1/oauth/token` | `grant_type=client_credentials&client_id=...&client_secret=...` |
| **Username/Password** | `POST /api/v1/auth/token` | Basic auth header |

### Token Behavior

- Tokens are cached with expiration tracking
- Default expiration: **15 minutes** (if not specified by server)
- Cache is invalidated when the credential signature changes
- ISO 8601 date parsing supports both standard and fractional-second formats

## Error Types

| Error | Description |
|-------|-------------|
| `invalidServerURL` | Server URL could not be parsed |
| `missingCredentials` | No credentials stored in Keychain |
| `invalidCredentials` | Credential fields are incomplete |
| `authenticationFailed` | Token request returned an error |
| `networkFailure(statusCode:message:)` | Non-2xx HTTP response |
| `decodingFailure` | Response JSON could not be decoded |
| `keychainFailure(status:)` | Keychain operation failed |
| `persistenceFailure(message:)` | File I/O error |
| `invalidModulePackage(message:)` | Package manifest validation failed |
| `duplicateModulePackage(packageID:)` | Package ID already installed |
| `unsupportedModulePackageType(type:)` | Unknown module type |

## Jamf Pro API Versions Used

| Module | Endpoints |
|--------|-----------|
| Computer Search | `api/v1`, `api/v2`, `api/v3` (with fallback) |
| Mobile Device Search | Modern API with section encoding fallback |
| Support Technician | Modern API for search, detail, and management commands |
| Prestage Director | Pre-stage enrollment API |
EOF

# ══════════════════════════════════════════════════════════
# Security.md
# ══════════════════════════════════════════════════════════
cat > "$WIKI_DIR/Security.md" << 'EOF'
# 🔒 Security

## Credential Lifecycle

```mermaid
flowchart TD
    A[User Opens Settings] --> B[Enter Server URL]
    B --> C{Auth Method}
    C -->|API Client| D[Enter Client ID + Secret]
    C -->|Username/Password| E[Enter Username + Password]
    D --> F[Verify Connection]
    E --> F
    F -->|Success| G[Sanitize Credentials]
    F -->|Failure| H[Show Error]
    G --> I[Save to Keychain]
    H --> B

    style G fill:#e8f5e9,stroke:#4caf50
    style H fill:#fce4ec,stroke:#e91e63
    style I fill:#e8f4fd,stroke:#2196f3
```

## Keychain Storage

| Property | Value |
|----------|-------|
| **Service** | `com.jamfdashboard.app` |
| **Key** | `jamf.credentials` |
| **Accessibility** | `kSecAttrAccessibleWhenUnlockedThisDeviceOnly` |
| **Class** | `kSecClassGenericPassword` |

### Security Properties

- Data is accessible **only when the device is unlocked**
- Data is **bound to this device** — not transferred during backup/restore
- Stored as encoded `JamfCredentials` struct (JSON)

## Credential Sanitization

Before saving, credentials are **sanitized** to remove unused fields:

| Auth Method Selected | Fields Stored | Fields Cleared |
|---------------------|---------------|----------------|
| API Client | Server URL, Client ID, Client Secret | Username, Password |
| Username/Password | Server URL, Username, Password | Client ID, Client Secret |

This prevents accidental leakage of credentials from a previously selected authentication method.

## App Entitlements

```xml
<key>com.apple.security.app-sandbox</key>       <true/>
<key>com.apple.security.network.client</key>     <true/>
<key>com.apple.security.device.camera</key>      <true/>
```

| Entitlement | Purpose |
|-------------|---------|
| App Sandbox | Process isolation |
| Network Client | Outbound HTTPS to Jamf Pro server |
| Camera | Barcode/QR code scanning |

## Token Security

- Bearer tokens are held **in-memory only** (never persisted)
- Tokens are invalidated on credential change
- Automatic refresh on 401 response prevents stale token usage
- Token decoding failures are reported to diagnostics
EOF

# ══════════════════════════════════════════════════════════
# Diagnostics.md
# ══════════════════════════════════════════════════════════
cat > "$WIKI_DIR/Diagnostics.md" << 'EOF'
# 📊 Diagnostics

## Overview

The `DiagnosticsCenter` is a Swift **actor** that provides centralized event reporting, in-memory streaming, and persistent error logging.

## Event Model

```mermaid
classDiagram
    class DiagnosticEvent {
        +UUID id
        +Date timestamp
        +String source
        +String category
        +DiagnosticSeverity severity
        +String message
        +Dictionary metadata
    }

    class DiagnosticSeverity {
        <<enumeration>>
        info
        warning
        error
    }

    DiagnosticEvent --> DiagnosticSeverity
```

### Event Fields

| Field | Type | Example |
|-------|------|---------|
| `id` | UUID | Auto-generated |
| `timestamp` | Date | ISO 8601 |
| `source` | String | `"framework.api-gateway"`, `"module.computer-search"` |
| `category` | String | `"authentication"`, `"request"`, `"search"` |
| `severity` | Enum | `.info`, `.warning`, `.error` |
| `message` | String | Human-readable description |
| `metadata` | [String: String] | Additional key-value context |

## In-Memory Stream

- Maximum **2,000 events** retained in memory
- Oldest events are evicted when the limit is reached
- Accessible via `currentEvents()` for UI display

## Persistent Error Log

Error-severity events are appended to a persistent NDJSON file:

```
~/Documents/JamfDashboardDiagnostics/jamf-dashboard-errors.ndjson
```

Each line is a complete JSON object representing one error event.

## JSON Export

Full diagnostics can be exported as a timestamped JSON file:

```
~/Documents/JamfDashboardDiagnostics/jamf-dashboard-diagnostics-<timestamp>.json
```

### Export Payload Structure

```json
{
  "appName": "Jamf Dashboard",
  "exportedAt": "2026-04-15T10:30:00Z",
  "eventCount": 42,
  "events": [
    {
      "id": "...",
      "timestamp": "...",
      "source": "framework.api-gateway",
      "category": "request",
      "severity": "error",
      "message": "Request failed with status 403",
      "metadata": { "path": "/api/v1/computers", "statusCode": "403" }
    }
  ]
}
```

## Diagnostic Operations

| Operation | Method | Description |
|-----------|--------|-------------|
| Report | `report(source:category:severity:message:metadata:)` | Add event to stream + persist if error |
| View | `currentEvents()` | Read in-memory event stream |
| Export | `exportToJSONFile()` | Generate shareable JSON file |
| Error Log | `persistentErrorLogFileURL()` | Get path to NDJSON error log |
| Clear | `clear()` | Reset both in-memory and persistent logs |
EOF

echo "Wiki pages generated successfully (12 pages)"
echo "pages_generated=true"
