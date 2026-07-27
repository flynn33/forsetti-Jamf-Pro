# Forsetti Jamf Pro Notes

This repository is organized as a self-contained Forsetti Pattern B application.

The app target owns the Forsetti Jamf Pro experience, runtime, module contracts, service adapters, and SwiftUI workspace. The Forsetti framework repository is a reference implementation only and is not a build dependency.

Feature views remain user-facing Forsetti Jamf Pro UI and are reached through the dedicated UI module route catalog. Feature and platform responsibilities are represented by Forsetti service modules and app-owned service adapters.

The production runtime contains 10 manifests and one UI module: `com.forsetti.jamfpro.ui.workspace`.

Deployment Tracker was removed from the host runtime and product surface on 2026-07-27. Its non-runnable source snapshot is preserved under [`Standalone/DeploymentTracker`](Standalone/DeploymentTracker/README.md) for development as a separate application.

The repository is proprietary and permits only the source inspection and limited individual evaluation described in [`LICENSE`](LICENSE). Public product release remains blocked until the 30-day evaluation lock and purchase verification in [`docs/PUBLIC_RELEASE_CHECKLIST.md`](docs/PUBLIC_RELEASE_CHECKLIST.md) are implemented and tested.

See [`docs/README.md`](docs/README.md) for the current documentation map. Historical reports may retain earlier Jamf Dashboard names and paths when they describe the predecessor source baseline.
