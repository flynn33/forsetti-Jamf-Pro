# Source Inventory

> Historical source-baseline record captured before the Forsetti Jamf Pro remediation and the later Deployment Tracker extraction. Current project guidance is indexed in [`../docs/README.md`](../docs/README.md).

Required package label: Jamf Dashboard v3.34.0

Authorized source override: the user confirmed the sanitized local source package as the source of truth. That source reports `VERSION` value `3.32.1`; this inventory records it under the package-required filename so the remediation trail stays complete.

## Source Evidence

- Source root: sanitized local source package supplied by the user.
- Version file hash: `34e122706aa530de90c30a1ad180685cf489ad806c04b71d39e9ddb2340703e7`
- Changelog hash: `56c48b68e9711c788ef2598a9cbd641dcda5237c1a86ed51805b73731f978e08`
- Xcode project hash: `e7271773f781a5764f3f2d66cd8f394a34fac57cc64d1597c96ca8cdf0182fab`

## Observed Product Surface

- Main source folder: `JamfDashboardApp`
- Test folder: `JamfDashboardAppTests`
- Project: `Jamf Dashboard.xcodeproj`
- Modules observed: `ComputerSearch`, `DeploymentTracker`, `MobileDeviceSearch`, `PermissionsMatrix`, `PrestageDirector`, `Reports`, `SupportTechnician`
- Test coverage observed: model catalogs, command renderer, computer search, mobile search, diagnostics, API gateway, credentials, RSQL, reports, deployment tracker, permissions matrix, prestage sharing, support technician, remote support, temporary admin, and sharing helpers.

## Carry-Forward Scope

The A1.0.0 remediation kept the product behavior from the authorized source while changing identity, runtime ownership, manifests, and validation posture to the Forsetti Jamf Pro target contract.

## Post-Inventory Change

On 2026-07-27, Deployment Tracker was removed from the Forsetti Jamf Pro host and preserved as a non-runnable source snapshot under [`../Standalone/DeploymentTracker`](../Standalone/DeploymentTracker/README.md). Its inclusion in the observed product surface above remains accurate for this historical inventory.
