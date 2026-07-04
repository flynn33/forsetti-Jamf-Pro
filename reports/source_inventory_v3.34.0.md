# Source Inventory

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

The remediation keeps the product behavior from the authorized source while changing identity, runtime ownership, manifests, and validation posture to the Forsetti Jamf Pro A1.0.0 target contract.
