#!/usr/bin/env bash
set -euo pipefail

MODE="${1:-run}"
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROJECT_PATH="$ROOT_DIR/Forsetti Jamf Pro.xcodeproj"
SCHEME="Forsetti Jamf Pro"
APP_NAME="Forsetti Jamf Pro"
BUNDLE_ID="com.forsetti.jamfpro"
DERIVED_DATA="$ROOT_DIR/build/DerivedData"
APP_BUNDLE="$DERIVED_DATA/Build/Products/Debug/$APP_NAME.app"
APP_BINARY="$APP_BUNDLE/Contents/MacOS/$APP_NAME"

kill_existing() {
  /usr/bin/pkill -x "$APP_NAME" >/dev/null 2>&1 || true
}

build_app() {
  DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}" \
  /usr/bin/xcodebuild \
    -project "$PROJECT_PATH" \
    -scheme "$SCHEME" \
    -configuration Debug \
    -destination "platform=macOS" \
    -derivedDataPath "$DERIVED_DATA" \
    CODE_SIGN_STYLE=Manual \
    CODE_SIGN_IDENTITY=- \
    CODE_SIGNING_ALLOWED=YES \
    build
}

open_app() {
  if [[ ! -d "$APP_BUNDLE" ]]; then
    echo "App bundle not found: $APP_BUNDLE" >&2
    exit 1
  fi
  /usr/bin/open -n "$APP_BUNDLE"
}

verify_running() {
  sleep 2
  if /usr/bin/pgrep -x "$APP_NAME" >/dev/null; then
    echo "$APP_NAME is running."
    return 0
  fi

  echo "$APP_NAME did not remain running after launch." >&2
  exit 1
}

usage() {
  echo "usage: $0 [run|--debug|--logs|--telemetry|--verify]" >&2
}

kill_existing
build_app

case "$MODE" in
  run)
    open_app
    ;;
  --debug|debug)
    /usr/bin/lldb -- "$APP_BINARY"
    ;;
  --logs|logs)
    open_app
    /usr/bin/log stream --info --style compact --predicate "process == \"$APP_NAME\""
    ;;
  --telemetry|telemetry)
    open_app
    /usr/bin/log stream --info --style compact --predicate "subsystem == \"$BUNDLE_ID\""
    ;;
  --verify|verify)
    open_app
    verify_running
    ;;
  *)
    usage
    exit 2
    ;;
esac
