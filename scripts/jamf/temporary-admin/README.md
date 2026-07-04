# Temporary Admin Elevation — Jamf tenant scripts

These scripts run **on the managed Mac** (uploaded to Jamf Pro), not inside the app.
Jamf Dashboard never creates policies or scripts dynamically — a Jamf administrator
pre-creates the objects below, and the app only changes a Mac's membership in a
dedicated request group.

## Scripts

| File | Jamf object | Purpose |
| ---- | ----------- | ------- |
| `temporary-admin-elevate.zsh` | Script: *Jamf Dashboard - Temporary Admin Elevate* | Promotes the current console user to local admin for the duration in **parameter 4** (`5`, `15`, `30`, or `60`), installs a root-owned demotion helper + LaunchDaemon, and writes state. |
| `temporary-admin-demote-now.zsh` | Script: *Jamf Dashboard - Temporary Admin Demote Now* | Immediately demotes the user (via the installed helper, or a safe fallback). |
| `ea-temporary-admin-status.zsh` | Computer Extension Attribute: *Jamf Dashboard - Temporary Admin Status* | Reports the current status (`not_requested`, `elevated`, `already_admin`, `demoted`, `expired_pending_demotion`, `failed`, or `Not Reported`). |
| `ea-temporary-admin-user.zsh` | EA: *Jamf Dashboard - Temporary Admin User* | Reports the elevated user. |
| `ea-temporary-admin-expires-at.zsh` | EA: *Jamf Dashboard - Temporary Admin Expires At* | Reports the ISO-8601 expiry. |
| `ea-temporary-admin-last-change.zsh` | EA: *Jamf Dashboard - Temporary Admin Last Change* | Reports the ISO-8601 last-change time. |
| `ea-temporary-admin-run-id.zsh` | EA: *Jamf Dashboard - Temporary Admin Run ID* | Reports the Mac-side run ID. |

## Safety properties

- Elevation refuses any duration other than `5`, `15`, `30`, `60`.
- Elevation refuses `root`, `loginwindow`, and setup users, and missing/invalid users.
- A user who was **already** an administrator before the workflow is never demoted by it.
- The demotion helper and LaunchDaemon are installed root-owned and not world-writable.
- Extension-attribute scripts only **read** state and print a single `<result>…</result>`.
- Temporary local-admin membership does **not** change Secure Token, Bootstrap Token,
  FileVault recovery access, local passwords, or Jamf Pro permissions.

See the project WIKI ("Temporary Admin Elevation") for the full tenant setup, required
privileges, testing procedure, and rollback runbook.
