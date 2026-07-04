#!/usr/bin/env bash
set -euo pipefail

ROOT="${1:-.}"
cd "$ROOT"

terms=(
  "Camp""ing World"
  "Camp""ingWorld"
  "camp""ingworld"
  "C""WGS"
  "Camp""ing World GS"
  "com.camp""ingworld"
  "rv"".com"
  "me.rv"".com"
)

regex=""
for term in "${terms[@]}"; do
  escaped="$(printf '%s' "$term" | sed -e 's/[.[\*^$()+?{}|\\]/\\&/g')"
  if [[ -z "$regex" ]]; then
    regex="$escaped"
  else
    regex="${regex}|${escaped}"
  fi
done

echo "[Forsetti sanitation] scanning for blocked customer references..."
if grep -RInE \
  --exclude-dir=.git \
  --exclude-dir=.build \
  --exclude-dir=DerivedData \
  --exclude-dir=build \
  --exclude-dir=.swiftpm \
  --exclude='*.xcuserstate' \
  "$regex" .; then
  echo "[FAIL] Blocked customer references remain."
  exit 1
fi

asset_namespace="Assets.xcassets/""C""W"
if find . -path "*${asset_namespace}*" -print | grep -q .; then
  echo "[FAIL] Customer asset namespace remains."
  find . -path "*${asset_namespace}*" -print
  exit 1
fi

legacy_logo_lower="logo-""lockup"
legacy_logo_title="Logo""Lockup"
if find . \( -iname "*${legacy_logo_lower}*" -o -iname "*${legacy_logo_title}*" \) -print | grep -q .; then
  echo "[FAIL] Legacy logo lockup assets or source identifiers remain."
  find . \( -iname "*${legacy_logo_lower}*" -o -iname "*${legacy_logo_title}*" \) -print
  exit 1
fi

echo "[PASS] No blocked customer references found."
