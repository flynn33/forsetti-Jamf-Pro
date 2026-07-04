#!/usr/bin/env python3
import argparse
import json
import sys
from pathlib import Path


REQUIRED_PRODUCTION_MODULE_IDS = {
    "com.forsetti.jamfpro.service.diagnostics",
    "com.forsetti.jamfpro.service.jamf",
    "com.forsetti.jamfpro.service.scanner",
    "com.forsetti.jamfpro.feature.computer-search",
    "com.forsetti.jamfpro.feature.mobile-device-search",
    "com.forsetti.jamfpro.feature.support-technician",
    "com.forsetti.jamfpro.feature.prestage-director",
    "com.forsetti.jamfpro.feature.reports",
    "com.forsetti.jamfpro.feature.deployment-tracker",
    "com.forsetti.jamfpro.feature.permissions-matrix",
    "com.forsetti.jamfpro.ui.workspace",
}

IO_CAPABILITY = {
    "networking": "networking",
    "storage": "storage",
    "secure_storage": "secure_storage",
    "file_export": "file_export",
    "telemetry": "telemetry",
    "shared_database": "shared_database",
    "authentication": "authentication",
    "diagnostics": "diagnostics",
    "api": "api",
    "security": "security",
}

SERVICE_DEFAULT_ROLES = {
    "shared_database",
    "authentication",
    "diagnostics",
    "api",
    "security",
}


def fail(message: str) -> None:
    print(f"error: {message}", file=sys.stderr)
    raise SystemExit(1)


def load_manifests(directory: Path) -> list[dict]:
    if not directory.is_dir():
        fail(f"manifest directory not found: {directory}")

    manifests = []
    for path in sorted(directory.glob("*.json")):
        try:
            data = json.loads(path.read_text(encoding="utf-8"))
        except json.JSONDecodeError as error:
            fail(f"{path.name} is not valid JSON: {error}")

        if not isinstance(data, dict):
            fail(f"{path.name} must contain a JSON object")

        data["_file"] = path.name
        manifests.append(data)

    if not manifests:
        fail(f"no manifest JSON files found in {directory}")

    return manifests


def require_unique(manifests: list[dict], field: str) -> None:
    seen: dict[str, str] = {}
    for manifest in manifests:
        value = manifest.get(field)
        if not isinstance(value, str) or not value.strip():
            fail(f"{manifest['_file']} has missing or invalid {field}")
        if value in seen:
            fail(f"duplicate {field} {value!r} in {seen[value]} and {manifest['_file']}")
        seen[value] = manifest["_file"]


def validate_default_role(manifest: dict) -> None:
    role = manifest.get("defaultModuleRole")
    module_type = manifest.get("moduleType")
    if role is None:
        return
    if role == "ui" and module_type not in {"ui", "app"}:
        fail(f"{manifest['_file']} defaultModuleRole ui is invalid for {module_type}")
    if role in SERVICE_DEFAULT_ROLES and module_type != "service":
        fail(f"{manifest['_file']} defaultModuleRole {role} is invalid for {module_type}")


def validate_io_requirements(manifest: dict) -> None:
    capabilities = set(manifest.get("capabilitiesRequested") or [])
    runtime = manifest.get("runtimeRequirements") or {}
    io_requirements = runtime.get("io") or []
    if not isinstance(io_requirements, list):
        fail(f"{manifest['_file']} runtimeRequirements.io must be an array")

    seen_ids = set()
    for requirement in io_requirements:
        if not isinstance(requirement, dict):
            fail(f"{manifest['_file']} contains a non-object I/O requirement")
        requirement_id = requirement.get("requirementID")
        if not isinstance(requirement_id, str) or not requirement_id.strip():
            fail(f"{manifest['_file']} contains an I/O requirement without requirementID")
        if requirement_id in seen_ids:
            fail(f"{manifest['_file']} repeats I/O requirementID {requirement_id}")
        seen_ids.add(requirement_id)

        kind = requirement.get("kind")
        required_capability = IO_CAPABILITY.get(kind)
        if required_capability is None:
            fail(f"{manifest['_file']} has unsupported I/O kind {kind!r}")
        if required_capability not in capabilities:
            fail(
                f"{manifest['_file']} I/O requirement {requirement_id} requires missing capability "
                f"{required_capability}"
            )


def validate_manifests(manifests: list[dict], expected_ui_module: str) -> None:
    require_unique(manifests, "moduleID")
    require_unique(manifests, "entryPoint")

    for manifest in manifests:
        if manifest.get("schemaVersion") != "1.1":
            fail(f"{manifest['_file']} schemaVersion must be 1.1")
        if manifest.get("manifestTemplateVersion") != "1.1":
            fail(f"{manifest['_file']} manifestTemplateVersion must be 1.1")
        if manifest.get("moduleType") not in {"service", "ui", "app"}:
            fail(f"{manifest['_file']} has invalid moduleType {manifest.get('moduleType')!r}")
        if not isinstance(manifest.get("capabilitiesRequested"), list):
            fail(f"{manifest['_file']} capabilitiesRequested must be an array")
        if manifest.get("moduleType") == "service":
            ui_requirements = (manifest.get("runtimeRequirements") or {}).get("ui")
            if ui_requirements is not None:
                fail(f"{manifest['_file']} is a service module but declares UI requirements")

        validate_default_role(manifest)
        validate_io_requirements(manifest)

    ui_modules = [manifest["moduleID"] for manifest in manifests if manifest.get("moduleType") == "ui"]
    if ui_modules != [expected_ui_module]:
        fail(f"expected exactly one UI module {expected_ui_module}, found {ui_modules}")

    module_ids = {manifest["moduleID"] for manifest in manifests}
    missing = REQUIRED_PRODUCTION_MODULE_IDS - module_ids
    if missing:
        fail(f"missing required production module IDs: {sorted(missing)}")


def main() -> int:
    parser = argparse.ArgumentParser(description="Validate Forsetti Jamf Pro Forsetti manifests.")
    parser.add_argument(
        "--manifests",
        default="ForsettiJamfProApp/Resources/ForsettiManifests",
        help="Directory containing Forsetti manifest JSON files.",
    )
    parser.add_argument(
        "--expect-one-ui-module",
        default="com.forsetti.jamfpro.ui.workspace",
        help="Expected single Pattern B UI module ID.",
    )
    args = parser.parse_args()

    manifests = load_manifests(Path(args.manifests))
    validate_manifests(manifests, args.expect_one_ui_module)
    print(f"Validated {len(manifests)} Forsetti manifests.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
