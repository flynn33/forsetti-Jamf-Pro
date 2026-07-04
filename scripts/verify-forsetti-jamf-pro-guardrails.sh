#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

fail() {
  printf 'error: %s\n' "$1" >&2
  exit 1
}

if rg -n '(^|[^A-Za-z])(struct|enum|class)[[:space:]]+(SemVer|ModuleManifest|ModuleDescriptor|ManifestLoader|Capability|ModuleType|ModuleRegistry|ForsettiRuntime|ForsettiContext)([^A-Za-z]|$)' JamfDashboardApp --glob '!**/Generated/**'; then
  fail "app code defines local Forsetti model/runtime types"
fi

if rg -n 'DashboardFeatureWorkspace|FeatureWorkspaceContext|DashboardFeatureCatalog|FeaturePackage|ModulePackage|ModulePackageTemplates' JamfDashboardApp JamfDashboardAppTests scripts README.md WIKI.md --glob '!**/Resources/**' --glob '!scripts/verify-forsetti-jamf-pro-guardrails.sh'; then
  fail "legacy dashboard module/package runtime symbols remain"
fi

if find JamfDashboardApp -path '*/Sources/ForsettiCore/*' -o -path '*/Sources/ForsettiPlatform/*' -o -path '*/Sources/ForsettiHostTemplate/*' | grep -q .; then
  fail "Forsetti framework source appears to be copied into the app"
fi

if rg -n 'ForsettiModulesExample' JamfDashboardApp JamfDashboardAppTests 'Jamf Dashboard.xcodeproj' scripts README.md WIKI.md --glob '!scripts/verify-forsetti-jamf-pro-guardrails.sh'; then
  fail "ForsettiModulesExample must not be linked or referenced"
fi

if rg -n 'Jamf-Dashboard-Sanitized|XCLocalSwiftPackageReference.*Jamf-Dashboard|XCRemoteSwiftPackageReference.*Jamf|git@.*Jamf-Dashboard|github.com/.*/Jamf-Dashboard' 'Jamf Dashboard.xcodeproj' JamfDashboardApp JamfDashboardAppTests scripts --glob '!**/*.md' --glob '!scripts/verify-forsetti-jamf-pro-guardrails.sh'; then
  fail "Jamf Dashboard source repository is referenced as a build dependency"
fi

for product in ForsettiCore ForsettiPlatform ForsettiHostTemplate; do
  if ! rg -q "$product" 'Jamf Dashboard.xcodeproj/project.pbxproj' JamfDashboardApp; then
    fail "missing required Forsetti public product reference: $product"
  fi
done

python3 scripts/validate-forsetti-manifests.py \
  --manifests JamfDashboardApp/Resources/ForsettiManifests \
  --expect-one-ui-module com.forsetti.jamfdashboard.ui

python3 - <<'PY'
import json
from pathlib import Path

manifest_dir = Path("JamfDashboardApp/Resources/ForsettiManifests")
entry_points = {
    json.loads(path.read_text(encoding="utf-8"))["entryPoint"]
    for path in manifest_dir.glob("*.json")
}
registry = Path("JamfDashboardApp/ForsettiModules/JamfDashboardModuleRegistry.swift").read_text(encoding="utf-8")
missing = sorted(entry for entry in entry_points if entry not in registry)
if missing:
    raise SystemExit(f"registry coverage missing entry points: {missing}")
print(f"Verified registry coverage for {len(entry_points)} entry points.")
PY

if rg -n '^import SwiftUI' JamfDashboardApp/ForsettiModules/Services; then
  fail "service modules must not import SwiftUI"
fi

printf 'Forsetti Jamf Pro guardrails passed.\n'
