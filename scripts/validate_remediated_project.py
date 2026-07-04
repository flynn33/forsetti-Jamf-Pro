#!/usr/bin/env python3
from __future__ import annotations
import argparse, json, re, sys
from pathlib import Path

FORBIDDEN_TEXT = [
    (re.compile(r"XCLocalSwiftPackageReference"), "No local Swift package references are allowed for Forsetti Framework."),
    (re.compile(r"XCRemoteSwiftPackageReference.*Forsetti", re.I), "No remote Forsetti package dependency is allowed."),
    (re.compile(r"Forsetti-Framework-Mac-iOS-main"), "Framework repository must not be referenced by the project/build."),
    (re.compile(r"^\s*import Forsetti(Core|Platform|HostTemplate)\b", re.M), "Do not import Forsetti package products."),
    (re.compile(r"productName\s*=\s*Forsetti(Core|Platform|HostTemplate)"), "Do not link Forsetti package products."),
]
SERVICE_UI_IMPORTS = re.compile(r"^\s*import\s+(SwiftUI|UIKit|AppKit|Metal|MetalKit|StoreKit)\b", re.M)
VERSION_RE = re.compile(r"^A[1-9][0-9]*\.[0-9]+\.[0-9]+$")


def read(path: Path) -> str:
    try:
        return path.read_text(errors="ignore")
    except Exception:
        return ""


def fail(msg: str) -> None:
    print(f"FATAL: {msg}", file=sys.stderr)
    sys.exit(2)


def collect_text_files(root: Path):
    for p in root.rglob("*"):
        if not p.is_file():
            continue
        if ".git" in p.parts or "DerivedData" in p.parts or "__MACOSX" in p.parts or p.name.startswith("._"):
            continue
        if p.suffix in {".swift", ".md", ".json", ".plist", ".yml", ".yaml", ".sh", ".txt"} or p.name == "project.pbxproj":
            yield p


def main() -> int:
    parser = argparse.ArgumentParser(description="Validate remediated Forsetti Jamf Pro A1.0.0 project guardrails.")
    parser.add_argument("--project-root", required=True)
    parser.add_argument("--expected-version", default="A1.0.0")
    parser.add_argument("--allow-marketing-version-fallback", action="store_true", help="Allow numeric MARKETING_VERSION only if FORSETTI_APP_VERSION carries A-version.")
    args = parser.parse_args()
    root = Path(args.project_root).resolve()
    if not root.exists():
        fail(f"Project root not found: {root}")

    failures = []
    for p in collect_text_files(root):
        text = read(p)
        rel = p.relative_to(root)
        for rx, why in FORBIDDEN_TEXT:
            if rx.search(text):
                failures.append(f"{rel}: {why}")

    version_file = root / "VERSION"
    if not version_file.exists():
        failures.append("VERSION file is missing.")
    else:
        version = read(version_file).strip()
        if version != args.expected_version or not VERSION_RE.match(version):
            failures.append(f"VERSION must be {args.expected_version}; observed {version!r}.")

    xcodeproj = root / "Forsetti Jamf Pro.xcodeproj" / "project.pbxproj"
    if not xcodeproj.exists():
        failures.append("Required Xcode project missing: Forsetti Jamf Pro.xcodeproj/project.pbxproj")
    else:
        txt = read(xcodeproj)
        if "Jamf Dashboard.xcodeproj" in txt:
            failures.append("Project still contains legacy Jamf Dashboard project identity.")
        marketing = sorted(set(re.findall(r"MARKETING_VERSION\s*=\s*([^;]+);", txt)))
        current = sorted(set(re.findall(r"CURRENT_PROJECT_VERSION\s*=\s*([^;]+);", txt)))
        if args.expected_version not in marketing and not args.allow_marketing_version_fallback:
            failures.append(f"MARKETING_VERSION must include {args.expected_version}; observed {marketing}")
        if args.expected_version not in current:
            failures.append(f"CURRENT_PROJECT_VERSION must include {args.expected_version}; observed {current}")

    manifests_dir = root / "ForsettiJamfProApp" / "Resources" / "ForsettiManifests"
    if not manifests_dir.exists():
        failures.append("Manifest directory missing: ForsettiJamfProApp/Resources/ForsettiManifests")
    else:
        ui_modules = []
        module_ids = []
        for p in sorted(manifests_dir.glob("*.json")):
            try:
                data = json.loads(read(p))
            except Exception as exc:
                failures.append(f"{p.relative_to(root)}: invalid JSON: {exc}")
                continue
            module_id = data.get("moduleID")
            if module_id in module_ids:
                failures.append(f"Duplicate manifest moduleID: {module_id}")
            module_ids.append(module_id)
            if data.get("moduleType") == "ui":
                ui_modules.append(module_id)
            if data.get("appVersion") != args.expected_version:
                failures.append(f"{p.relative_to(root)}: appVersion must be {args.expected_version}.")
        if len(ui_modules) != 1:
            failures.append(f"Exactly one UI module manifest required; observed {len(ui_modules)}: {ui_modules}")

    for service_dir_name in ["Services", "ServiceModules"]:
        for p in (root / "ForsettiJamfProApp" / "ForsettiModules" / service_dir_name).rglob("*.swift") if (root / "ForsettiJamfProApp" / "ForsettiModules" / service_dir_name).exists() else []:
            if SERVICE_UI_IMPORTS.search(read(p)):
                failures.append(f"{p.relative_to(root)} imports UI/platform presentation frameworks from service layer.")

    if failures:
        print("Guardrail failures:", file=sys.stderr)
        for f in failures:
            print(f"- {f}", file=sys.stderr)
        return 2

    print(json.dumps({"status":"PASS", "project_root":str(root), "expected_version":args.expected_version}, indent=2))
    return 0

if __name__ == "__main__":
    raise SystemExit(main())
