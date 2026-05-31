#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(git rev-parse --show-toplevel)"
VERSION_FILE="$REPO_ROOT/VERSION"
PROJECT_FILE="$REPO_ROOT/Forsetti.xcodeproj/project.pbxproj"

usage() {
  echo "Usage: bump-version.sh --type major|minor|patch | --version X.Y.Z" >&2
}

current_version() {
  tr -d '[:space:]' < "$VERSION_FILE"
}

bump_semver() {
  local version="$1"
  local part="$2"
  local major minor patch
  IFS='.' read -r major minor patch <<< "$version"

  case "$part" in
    major) echo "$((major + 1)).0.0" ;;
    minor) echo "${major}.$((minor + 1)).0" ;;
    patch) echo "${major}.${minor}.$((patch + 1))" ;;
    *) usage; exit 1 ;;
  esac
}

new_version=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --type)
      new_version="$(bump_semver "$(current_version)" "$2")"
      shift 2
      ;;
    --version)
      new_version="$2"
      shift 2
      ;;
    *)
      usage
      exit 1
      ;;
  esac
done

if [[ -z "$new_version" ]]; then
  usage
  exit 1
fi

printf '%s\n' "$new_version" > "$VERSION_FILE"
if [[ -f "$PROJECT_FILE" ]]; then
  sed -i '' "s/MARKETING_VERSION = [^;]*/MARKETING_VERSION = ${new_version}/g" "$PROJECT_FILE"
  sed -i '' "s/CURRENT_PROJECT_VERSION = [^;]*/CURRENT_PROJECT_VERSION = ${new_version}/g" "$PROJECT_FILE"
fi

echo "new_version=$new_version"
