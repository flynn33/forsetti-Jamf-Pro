#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

fail() {
  printf 'error: %s\n' "$1" >&2
  exit 1
}

required_runtime_file="ForsettiJamfProApp/ForsettiRuntime/ForsettiRuntimeCore.swift"
[[ -f "$required_runtime_file" ]] || fail "app-owned runtime file missing"
for symbol in SemVer ModuleManifest ModuleDescriptor ManifestLoader Capability ModuleType ModuleRegistry RuntimeController ServiceContainer EventBus CompatibilityChecker CapabilityPolicy ActivationStore; do
  if ! rg -q "(struct|enum|class|protocol)[[:space:]]+$symbol\\b" "$required_runtime_file"; then
    fail "missing app-owned runtime symbol: $symbol"
  fi
done

for removed_path in \
  "ForsettiJamfProApp/Modules/DeploymentTracker" \
  "ForsettiJamfProApp/ForsettiModules/UI/Features/DeploymentTracker" \
  "ForsettiJamfProApp/ForsettiModules/Services/DeploymentTrackerServiceModule.swift" \
  "ForsettiJamfProApp/Resources/ForsettiManifests/DeploymentTrackerServiceModule.json"; do
  [[ ! -e "$removed_path" ]] || fail "Deployment Tracker remains in the host target: $removed_path"
done

for preserved_path in \
  "Standalone/DeploymentTracker/Sources/DeploymentTracker/Domain/Models/DeploymentTrackerCoreModels.swift" \
  "Standalone/DeploymentTracker/Sources/DeploymentTracker/UI/DeploymentTrackerRootView.swift" \
  "Standalone/DeploymentTracker/Tests/DeploymentTrackerDemoSafetyTests.swift"; do
  [[ -f "$preserved_path" ]] || fail "preserved Deployment Tracker source is missing: $preserved_path"
done

if ! (
  cd Standalone/DeploymentTracker
  shasum -a 256 -c SOURCE_MANIFEST.sha256 >/dev/null
); then
  fail "preserved Deployment Tracker source does not match SOURCE_MANIFEST.sha256"
fi

if rg -n 'deploymentTracker|DeploymentTrackerServiceModule|com\.forsetti\.jamfpro\.feature\.deployment-tracker' \
  ForsettiJamfProApp/ForsettiModules/JamfDashboardModuleIDs.swift \
  ForsettiJamfProApp/ForsettiModules/JamfDashboardModuleRegistry.swift \
  ForsettiJamfProApp/ForsettiModules/UI/JamfDashboardRoute.swift \
  ForsettiJamfProApp/Resources/ForsettiManifests \
  scripts/validate-forsetti-manifests.py; then
  fail "Deployment Tracker remains attached to the Forsetti host runtime"
fi

if rg -n 'DashboardFeatureWorkspace|FeatureWorkspaceContext|DashboardFeatureCatalog|FeaturePackage|ModulePackage|ModulePackageTemplates' ForsettiJamfProApp ForsettiJamfProTests scripts README.md WIKI.md --glob '!**/Resources/**' --glob '!scripts/verify-forsetti-jamf-pro-guardrails.sh'; then
  fail "legacy dashboard module/package runtime symbols remain"
fi

if find ForsettiJamfProApp -path '*/Sources/ForsettiCore/*' -o -path '*/Sources/ForsettiPlatform/*' -o -path '*/Sources/ForsettiHostTemplate/*' | grep -q .; then
  fail "Forsetti framework source appears to be copied into the app"
fi

if rg -n 'ForsettiModulesExample' ForsettiJamfProApp ForsettiJamfProTests 'Forsetti Jamf Pro.xcodeproj' scripts README.md WIKI.md --glob '!scripts/verify-forsetti-jamf-pro-guardrails.sh'; then
  fail "ForsettiModulesExample must not be linked or referenced"
fi

local_package_marker='XCLocal''SwiftPackageReference'
remote_package_marker='XCRemote''SwiftPackageReference'
framework_path_marker='Forsetti-Framework''-Mac-iOS-main'
if rg -n "$local_package_marker|$remote_package_marker.*Forsetti|$framework_path_marker" 'Forsetti Jamf Pro.xcodeproj' ForsettiJamfProApp ForsettiJamfProTests scripts --glob '!**/*.md' --glob '!scripts/verify-forsetti-jamf-pro-guardrails.sh' --glob '!scripts/validate_remediated_project.py'; then
  fail "reference runtime repository is referenced as a build dependency"
fi

for product in ForsettiCore ForsettiPlatform ForsettiHostTemplate; do
  if rg -n "productName = $product;|^import $product\\b" 'Forsetti Jamf Pro.xcodeproj/project.pbxproj' ForsettiJamfProApp ForsettiJamfProTests; then
    fail "external runtime product remains: $product"
  fi
done

python3 scripts/validate-forsetti-manifests.py \
  --manifests ForsettiJamfProApp/Resources/ForsettiManifests \
  --expect-one-ui-module com.forsetti.jamfpro.ui.workspace

python3 - <<'PY'
import json
from pathlib import Path

manifest_dir = Path("ForsettiJamfProApp/Resources/ForsettiManifests")
entry_points = {
    json.loads(path.read_text(encoding="utf-8"))["entryPoint"]
    for path in manifest_dir.glob("*.json")
}
registry = Path("ForsettiJamfProApp/ForsettiModules/JamfDashboardModuleRegistry.swift").read_text(encoding="utf-8")
missing = sorted(entry for entry in entry_points if entry not in registry)
if missing:
    raise SystemExit(f"registry coverage missing entry points: {missing}")
print(f"Verified registry coverage for {len(entry_points)} entry points.")
PY

if rg -n '^import SwiftUI' ForsettiJamfProApp/ForsettiModules/Services; then
  fail "service modules must not import SwiftUI"
fi

printf 'Forsetti Jamf Pro guardrails passed.\n'
