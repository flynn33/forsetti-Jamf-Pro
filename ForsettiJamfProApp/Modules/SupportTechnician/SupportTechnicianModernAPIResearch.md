# Support Technician Module: Jamf Pro Modern API Research

Last reviewed: 2026-02-27

## Scope

This research maps Jamf Pro Modern API capabilities needed by the Support Technician module:

- unified username/serial search across computers and mobile devices
- full device detail retrieval
- diagnostics signal extraction for support workflows
- management actions from one screen (inventory update, app discovery, restart, wipe/unmanage, key/password retrieval)

## Primary Endpoint Set

### Unified search and detail

- Computers (paginated inventory): `GET /api/v3/computers-inventory`
- Computers (single record detail): `GET /api/v3/computers-inventory-detail/{id}`
- Mobile devices (paginated inventory detail): `GET /api/v2/mobile-devices/detail`
- Mobile device (single record detail): `GET /api/v2/mobile-devices/{id}/detail`

Implementation note:

- The module uses `v3` first for computer inventory and then compatibility fallback to `v2` and `v1` only when required by older servers.

### Management commands and controls

- Queue MDM commands: `POST /api/v2/mdm/commands`
- Computer erase: `POST /api/v1/computer-inventory/{id}/erase`
- Computer remove MDM profile: `POST /api/v1/computer-inventory/{id}/remove-mdm-profile`
- Mobile unmanage: `POST /api/v2/mobile-devices/{id}/unmanage`

### Recovery and security secrets

- FileVault key: `GET /api/v3/computers-inventory/{id}/filevault`
- Recovery lock password: `GET /api/v3/computers-inventory/{id}/view-recovery-lock-password`
- Device lock PIN: `GET /api/v3/computers-inventory/{id}/view-device-lock-pin`

### LAPS (local admin password)

- List LAPS-capable accounts: `GET /api/v2/local-admin-password/{clientManagementId}/accounts`
- View account password: `GET /api/v2/local-admin-password/{clientManagementId}/account/{username}/password`
- Rotate/set password: `PUT /api/v2/local-admin-password/{clientManagementId}/set-password`

## Version and deprecation observations

- Jamf privileges/deprecations mapping indicates `v1` computer inventory endpoints are deprecated with date `2025-06-30`.
- The same mapping shows `v2` computer inventory endpoints as deprecated for several routes with date `2025-11-06`.
- Jamf changelog for `11.23.0 Deprecations` additionally lists `v2` computer inventory routes (including `computers-inventory` and `computers-inventory-detail`) as deprecated.

Inference:

- For 2026+ environments, `v3` computer inventory endpoints should be treated as primary.
- Fallback behavior remains useful for mixed tenant versions and staged upgrades.

## MDM command capability observations

- Jamf changelog (`11.23.0 Changes`) notes `INSTALLED_APPLICATION_LIST` added to `POST /v1/mdm/commands`.
- Jamf changelog (`11.24 Changes`) notes `defaultApplications` support added for settings payload on `POST /v2/mdm/commands`.
- `POST /v2/mdm/commands` remains the preferred queue endpoint for this module.

Inference:

- Application discovery workflows should use queued MDM commands and tolerate shape differences in command payloads across tenant versions.

## Privilege model considerations

The module depends on API roles that include, at minimum, privileges for:

- reading computer inventory and mobile inventory
- queuing MDM commands
- viewing disk encryption recovery key / recovery lock / device lock PIN
- viewing and rotating local admin passwords
- sending unmanage / erase commands

Practical effect:

- The module must degrade gracefully per action when a role lacks a specific command privilege.

## Source links

- [Privileges and Deprecations](https://developer.jamf.com/jamf-pro/docs/privileges-and-deprecations)
- [Deprecation of Classic API Computer Inventory Endpoints](https://developer.jamf.com/jamf-pro/docs/deprecation-of-classic-api-computer-inventory-endpoints)
- [Post a command for creation and queuing (`/api/v2/mdm/commands`)](https://developer.jamf.com/jamf-pro/reference/post_v2-mdm-commands)
- [Get paginated mobile device inventory records (`/api/v2/mobile-devices/detail`)](https://developer.jamf.com/jamf-pro/v11.4.0/reference/get_v2-mobile-devices-detail)
- [Get mobile device detail (`/api/v2/mobile-devices/{id}/detail`)](https://developer.jamf.com/jamf-pro/reference/get_v2-mobile-devices-id-detail)
- [Erase a computer (`/api/v1/computer-inventory/{id}/erase`)](https://developer.jamf.com/jamf-pro/reference/post_v1-computer-inventory-id-erase)
- [Remove a computer's MDM profile (`/api/v1/computer-inventory/{id}/remove-mdm-profile`)](https://developer.jamf.com/jamf-pro/reference/post_v1-computer-inventory-id-remove-mdm-profile)
- [Unmanage a Mobile Device (`/api/v2/mobile-devices/{id}/unmanage`)](https://developer.jamf.com/jamf-pro/reference/post_v2-mobile-devices-id-unmanage)
- [Return a computer's Device Lock PIN (`v1` reference page)](https://developer.jamf.com/jamf-pro/reference/get_v1-computers-inventory-id-view-device-lock-pin)
- [Get LAPS capable admin accounts (`/api/v2/local-admin-password/{clientManagementId}/accounts`)](https://developer.jamf.com/jamf-pro/reference/get_v2-local-admin-password-clientmanagementid-accounts)
- [Get current LAPS password (`/api/v2/local-admin-password/{clientManagementId}/account/{username}/password`)](https://developer.jamf.com/jamf-pro/reference/get_v2-local-admin-password-clientmanagementid-account-username-password)
- [Set/rotate LAPS password (`/api/v2/local-admin-password/{clientManagementId}/set-password`)](https://developer.jamf.com/jamf-pro/reference/put_v2-local-admin-password-clientmanagementid-set-password)
- [Jamf Pro Changelog index (11.23/11.24 command changes)](https://developer.jamf.com/jamf-pro/v11.20.0/changelog)
- [11.23.0 Deprecations](https://developer.jamf.com/jamf-pro/v11.14.0/changelog/11230-deprecations)
