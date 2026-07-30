# App Store Review Demo Mode

Forsetti Jamf Pro ships a built-in **App Store Review demo mode** so Apple’s review team can exercise the Mac and iOS apps **without a live Jamf Pro tenant**.

## Goals

- No Jamf Pro server URL, API client, username, or password required
- Works offline (no external network dependency for demo paths)
- Hard safety gate: while demo is on, `JamfAPIGateway` never opens a live connection
- Management actions (POST/PUT/DELETE) return **simulated** success only — no production data can change
- Obvious UI chrome so review never confuses sample data with a real fleet

## How reviewers enter demo

1. Launch the app on Mac or iOS.
2. From the Command Center, open **Settings** (gear) **or** **Jamf Credentials**.
3. Tap/click **Explore App Store Demo**.
4. An orange banner appears:  
   `APP STORE DEMO — SAMPLE DATA ONLY — NO LIVE JAMF PRO CONNECTION`
5. All modules unlock against built-in sample devices.

### Suggested review paths

| Module | What to try |
|--------|-------------|
| Computer Search | Search `MacBook` or leave blank → Search. Open **Reviewer MacBook Pro** (`C02DEMO0001`). |
| Mobile Device Search | Search `iPad` or leave blank → Search. Open **Reviewer iPad Pro** (`F9FDEMO0001`). |
| Support Technician | Full walkthrough below. |
| Prestage Director | Browse **Demo Mac PreStage** / **Demo iPad PreStage** and scoped sample devices. |
| Reports | Refresh counts / generate a report against sample inventory. |
| Permissions Matrix | Browse commands, endpoints, privileges; Runtime Check uses demo privileges. |

## Support Technician walkthrough (App Review)

This is the deepest path for evaluating day-to-day technician UX. **No live MDM commands are sent** — every management action returns a local simulation success.

### 1. Open the module

Command Center → **Support Technician**.

### 2. Search for a Mac

1. Scope: **Computers** (or **All**).
2. Query: `C02DEMO0001` (or `reviewer`, `MacBook`).
3. Run search.
4. Select **Reviewer MacBook Pro**.

Expected: detail loads with general identity, hardware, OS, security, storage, local users, configuration profiles, groups, and sample extension attributes. Management ID is present so action buttons enable.

### 3. Browse detail frames

Scroll or open the available frames (names may vary slightly by layout):

| Frame | What you should see |
|-------|---------------------|
| General / identity | Name, serial `C02DEMO0001`, user `app.reviewer`, last contact timestamps |
| Hardware / storage | MacBook Pro model, RAM, disk capacity / free space |
| Security | FileVault / SIP / firewall sample flags |
| Applications | Safari, Chrome, Slack, Word (demo list) |
| Command History | Sample pending / completed / failed MDM rows |
| Policies | Demo policy index (Install Chrome, Wi‑Fi, Inventory, Security Baseline) |

### 4. Simulate management actions (safe)

On the Mac detail, try a non-destructive action first:

1. **Refresh Inventory** or **Blank Push** (or equivalent labels in the Management frame).
2. Confirm if prompted.
3. Expect a **success / queued** style result for the demo device.

Optional (still simulated only — no real device is contacted):

- Restart Device  
- Log Out User  
- Discover Applications  

Destructive-looking actions (Erase, Device Lock, etc.) are also **simulated** in demo mode. Prefer non-destructive ones for review notes.

### 5. Application Manager (Mac)

1. Open the Application Manager / applications UI for the selected Mac.
2. Confirm the installed list populates from sample inventory.
3. Privilege preflight should succeed (demo token privileges include Application Manager–related grants).

### 6. Search for a mobile device

1. Scope: **Mobile**.
2. Query: `F9FDEMO0001` (or `iPad`).
3. Select **Reviewer iPad Pro**.
4. Browse hardware, security, network, apps, profiles.
5. Try **Blank Push** or **Refresh Inventory** — simulated only.

### 7. What review should *not* require

- A real Jamf Pro URL  
- API client or username/password  
- Network access to any Jamf host  
- Trust that management buttons change a production fleet (they cannot while demo is on)

### Sample serials (copy/paste)

| Platform | Display name | Serial |
|----------|--------------|--------|
| Mac | Reviewer MacBook Pro | `C02DEMO0001` |
| Mac | Floor iMac — Demo Store 12 | `C02DEMO0002` |
| Mac | Warehouse Mac mini | `C02DEMO0003` |
| iPad | Reviewer iPad Pro | `F9FDEMO0001` |
| iPhone | POS iPhone — Demo Lane 3 | `F9FDEMO0002` |
| iPad | Training iPad Air | `F9FDEMO0003` |

### Exit demo

**Settings → App Store Demo Mode → Exit Demo Mode**  
(or the same control on the credentials screen).

Exiting demo does **not** delete any real Keychain credentials the operator may have saved earlier. Live modules require real verified credentials again when demo is off.

## Architecture (safety)

```
UI (ribbon / Explore Demo)
        │
        ▼
AppStoreReviewDemoMode  ── UserDefaults flag only (not Keychain)
        │
        ▼
JamfAPIGateway.request / uploadMultipart / fetchTokenAuthorizations
        │
        ├─ demo ON  → AppStoreDemoResponseRouter (fixtures) → never URLSession
        └─ demo OFF → normal auth + live Jamf Pro
```

### Guarantees

| Guarantee | Enforcement |
|-----------|-------------|
| No live Jamf traffic in demo | First branch in `JamfAPIGateway.request` |
| No Keychain required in demo | Demo path skips `currentCredentials()` |
| Mutations are local-only | Router returns `externalDataChanged: false` for POST/PUT/DELETE |
| Session “ready” without login | `JamfSessionAvailability` ORs demo with stored credentials |

## App Store Connect — Review Notes (paste)

Copy from `AppStoreReviewDemoMode.appReviewNotes` or use:

```
App Store Review Demo Mode

No Jamf Pro server, API client, username, or password is required.

On first launch:
1. Open Settings (gear) from the Command Center, or open Jamf Credentials.
2. Tap or click “Explore App Store Demo”.
3. An orange demo banner appears. All modules use built-in sample data.

Suggested paths:
• Computer Search — search “MacBook” or leave blank and run Search
• Mobile Device Search — search “iPad” or leave blank and run Search
• Support Technician — search serial C02DEMO0001, open Reviewer MacBook Pro,
  browse Hardware / Security / Applications / Command History, then run
  Refresh Inventory or Blank Push (simulated only). Mobile: F9FDEMO0001.
• Prestage Director, Reports, and Permissions Matrix — open and browse

Exit demo: Settings → App Store Demo Mode → Exit Demo Mode
(or the same control on the credentials screen).

Live credentials remain optional and are never required for review.
```

## Sample data (fictional)

| Kind | Identity |
|------|----------|
| Mac | Reviewer MacBook Pro — `C02DEMO0001` |
| Mac | Floor iMac — Demo Store 12 — `C02DEMO0002` |
| Mac | Warehouse Mac mini — `C02DEMO0003` |
| iPad | Reviewer iPad Pro — `F9FDEMO0001` |
| iPhone | POS iPhone — Demo Lane 3 — `F9FDEMO0002` |
| iPad | Training iPad Air — `F9FDEMO0003` |

All names, emails (`@example.com`), and serials are synthetic.

## Tests

`ForsettiJamfProTests/AppStoreReviewDemoModeTests.swift` covers:

- Toggle persistence
- Computer/mobile fixture decoding
- Auth privilege fixture for runtime checks
- Simulated mutations with `externalDataChanged == false`
- Gateway demo path with a URLSession that fails if used (proves hard offline gate)

## Non-goals

- Not a multi-tenant sandbox or full Jamf API simulator
- Not a substitute for QA against a real Jamf Pro lab
- Not related to the preserved standalone Deployment Tracker demo package under `Standalone/DeploymentTracker`
