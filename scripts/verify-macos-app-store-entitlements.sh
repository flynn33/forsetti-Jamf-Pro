#!/bin/sh
# verify-macos-app-store-entitlements.sh
# Validates macOS App Store entitlement configuration for Forsetti for Jamf Pro.
# Usage:
#   ./scripts/verify-macos-app-store-entitlements.sh
#   ./scripts/verify-macos-app-store-entitlements.sh "/path/to/Forsetti for Jamf Pro.app"

set -eu

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

ENTITLEMENTS_FILE="ForsettiJamfProApp/ForsettiJamfProApp.entitlements"
PROJECT_FILE="Forsetti Jamf Pro.xcodeproj/project.pbxproj"
SCHEME="Forsetti Jamf Pro"

PASS=0
FAIL=0
WARN=0

pass() { PASS=$((PASS + 1)); echo "  PASS: $1"; }
fail() { FAIL=$((FAIL + 1)); echo "  FAIL: $1"; }
warn() { WARN=$((WARN + 1)); echo "  WARN: $1"; }

echo "=== Forsetti for Jamf Pro — macOS App Store Entitlement Verification ==="
echo ""

# --- 1. Validate entitlements file exists and is valid XML ---
echo "--- Source Entitlements ---"
if [ ! -f "$REPO_ROOT/$ENTITLEMENTS_FILE" ]; then
    fail "Entitlements file not found: $ENTITLEMENTS_FILE"
else
    if plutil -lint "$REPO_ROOT/$ENTITLEMENTS_FILE" >/dev/null 2>&1; then
        pass "Entitlements file is valid XML"
    else
        fail "Entitlements file is not valid XML"
    fi
fi

# Check required entitlements
ENTITLEMENT_CONTENT=$(cat "$REPO_ROOT/$ENTITLEMENTS_FILE" 2>/dev/null || echo "")

if echo "$ENTITLEMENT_CONTENT" | grep -q "com.apple.security.app-sandbox"; then
    if echo "$ENTITLEMENT_CONTENT" | grep -A1 "com.apple.security.app-sandbox" | grep -q "<true/>"; then
        pass "com.apple.security.app-sandbox = true"
    else
        fail "com.apple.security.app-sandbox is not true"
    fi
else
    fail "com.apple.security.app-sandbox not found"
fi

if echo "$ENTITLEMENT_CONTENT" | grep -q "com.apple.security.network.client"; then
    if echo "$ENTITLEMENT_CONTENT" | grep -A1 "com.apple.security.network.client" | grep -q "<true/>"; then
        pass "com.apple.security.network.client = true"
    else
        fail "com.apple.security.network.client is not true"
    fi
else
    fail "com.apple.security.network.client not found"
fi

# Check forbidden entitlements are absent
if echo "$ENTITLEMENT_CONTENT" | grep -q "com.apple.security.device.camera"; then
    fail "com.apple.security.device.camera found in entitlements (must be removed)"
else
    pass "com.apple.security.device.camera absent from entitlements"
fi

if echo "$ENTITLEMENT_CONTENT" | grep -q "com.apple.security.network.server"; then
    fail "com.apple.security.network.server found in entitlements (must be removed)"
else
    pass "com.apple.security.network.server absent from entitlements"
fi

echo ""

# --- 2. Validate project.pbxproj build settings ---
echo "--- Build Settings ---"
if [ ! -f "$REPO_ROOT/$PROJECT_FILE" ]; then
    fail "Project file not found: $PROJECT_FILE"
else
    pass "Project file found"
fi

PBXPROJ_CONTENT=$(cat "$REPO_ROOT/$PROJECT_FILE" 2>/dev/null || echo "")

# Check for forbidden build settings in app target configurations
# The app target configurations are A1B2C3D4E5F6000000000012 (Debug) and A1B2C3D4E5F6000000000013 (Release)
# We check the entire file for these settings outside the app target scope

# Check ENABLE_INCOMING_NETWORK_CONNECTIONS is NO (not YES) in app target
if echo "$PBXPROJ_CONTENT" | grep -q "ENABLE_INCOMING_NETWORK_CONNECTIONS = YES"; then
    fail "ENABLE_INCOMING_NETWORK_CONNECTIONS = YES found in app target (must be NO)"
else
    pass "ENABLE_INCOMING_NETWORK_CONNECTIONS is not YES in app target"
fi

# Check ENABLE_OUTGOING_NETWORK_CONNECTIONS is YES (not NO) in app target
if echo "$PBXPROJ_CONTENT" | grep -q "ENABLE_OUTGOING_NETWORK_CONNECTIONS = NO"; then
    fail "ENABLE_OUTGOING_NETWORK_CONNECTIONS = NO found in app target (must be YES)"
else
    pass "ENABLE_OUTGOING_NETWORK_CONNECTIONS is not NO in app target"
fi

# Check ENABLE_APP_SANDBOX is YES
if echo "$PBXPROJ_CONTENT" | grep -q "ENABLE_APP_SANDBOX = YES"; then
    pass "ENABLE_APP_SANDBOX = YES"
else
    fail "ENABLE_APP_SANDBOX is not YES"
fi

# Check ENABLE_HARDENED_RUNTIME is YES
if echo "$PBXPROJ_CONTENT" | grep -q "ENABLE_HARDENED_RUNTIME = YES"; then
    pass "ENABLE_HARDENED_RUNTIME = YES"
else
    fail "ENABLE_HARDENED_RUNTIME is not YES"
fi

# Check ENABLE_RESOURCE_ACCESS_CAMERA is NO
if echo "$PBXPROJ_CONTENT" | grep -q "ENABLE_RESOURCE_ACCESS_CAMERA = NO"; then
    pass "ENABLE_RESOURCE_ACCESS_CAMERA = NO"
else
    fail "ENABLE_RESOURCE_ACCESS_CAMERA is not NO"
fi

# Check NSLocalNetworkUsageDescription exists for macOS
if echo "$PBXPROJ_CONTENT" | grep -q 'INFOPLIST_KEY_NSLocalNetworkUsageDescription\[sdk=macosx\*\]'; then
    pass "NSLocalNetworkUsageDescription present for macOS"
else
    fail "NSLocalNetworkUsageDescription missing for macOS"
fi

# Check NSCameraUsageDescription is SDK-conditional (not unconditional) for iOS
if echo "$PBXPROJ_CONTENT" | grep -q 'INFOPLIST_KEY_NSCameraUsageDescription = '; then
    fail "Unconditional INFOPLIST_KEY_NSCameraUsageDescription found (must be SDK-conditional)"
else
    pass "No unconditional NSCameraUsageDescription"
fi

if echo "$PBXPROJ_CONTENT" | grep -q 'INFOPLIST_KEY_NSCameraUsageDescription\[sdk=iphoneos\*\]'; then
    pass "SDK-conditional NSCameraUsageDescription for iphoneos"
else
    fail "SDK-conditional NSCameraUsageDescription for iphoneos missing"
fi

if echo "$PBXPROJ_CONTENT" | grep -q 'INFOPLIST_KEY_NSCameraUsageDescription\[sdk=iphonesimulator\*\]'; then
    pass "SDK-conditional NSCameraUsageDescription for iphonesimulator"
else
    fail "SDK-conditional NSCameraUsageDescription for iphonesimulator missing"
fi

echo ""

# --- 3. Validate resolved build settings (if xcodebuild available) ---
echo "--- Resolved Build Settings ---"
if command -v xcodebuild >/dev/null 2>&1; then
    for config in Debug Release; do
        echo ""
        echo "  Configuration: $config"
        BUILD_SETTINGS=$(xcodebuild -project "$REPO_ROOT/$PROJECT_FILE" -scheme "$SCHEME" -configuration "$config" -destination "generic/platform=macOS" -showBuildSettings 2>/dev/null || echo "")

        if [ -z "$BUILD_SETTINGS" ]; then
            warn "Could not resolve build settings for $config (xcodebuild may require signing)"
            continue
        fi

        # Check required settings
        for setting in "ENABLE_APP_SANDBOX" "ENABLE_HARDENED_RUNTIME" "ENABLE_INCOMING_NETWORK_CONNECTIONS" "ENABLE_OUTGOING_NETWORK_CONNECTIONS" "ENABLE_RESOURCE_ACCESS_CAMERA"; do
            VALUE=$(echo "$BUILD_SETTINGS" | grep "^${setting} =" | head -1 | sed 's/.*= *//' | tr -d ' ')
            if [ -n "$VALUE" ]; then
                echo "    $setting = $VALUE"
            else
                warn "$setting not found in resolved $config settings"
            fi
        done

        # Check macOS-specific Info.plist keys
        NSLND_VAL=$(echo "$BUILD_SETTINGS" | grep "INFOPLIST_KEY_NSLocalNetworkUsageDescription" | head -1 | sed 's/.*= *//' | tr -d '"')
        if [ -n "$NSLND_VAL" ]; then
            echo "    NSLocalNetworkUsageDescription (macOS) = $NSLND_VAL"
        else
            warn "NSLocalNetworkUsageDescription not found in resolved $config settings"
        fi

        NSCD_VAL=$(echo "$BUILD_SETTINGS" | grep "INFOPLIST_KEY_NSCameraUsageDescription[^[]*" | head -1 | sed 's/.*= *//' | tr -d '"')
        if [ -n "$NSCD_VAL" ]; then
            warn "Unconditional NSCameraUsageDescription found in resolved $config: $NSCD_VAL"
        else
            pass "No unconditional NSCameraUsageDescription in resolved $config"
        fi
    done
else
    warn "xcodebuild not available — skipping resolved build settings check"
fi

echo ""

# --- 4. Validate signed .app (if path provided) ---
if [ $# -ge 1 ] && [ -n "$1" ]; then
    APP_PATH="$1"
    echo "--- Signed Product Validation ---"
    if [ ! -d "$APP_PATH" ]; then
        fail "App path not found: $APP_PATH"
    else
        pass "App path exists: $APP_PATH"

        # Extract signed entitlements
        SIGNED_ENTS=$(codesign -d --entitlements :- "$APP_PATH" 2>/dev/null || echo "")

        if [ -n "$SIGNED_ENTS" ]; then
            # Check required
            if echo "$SIGNED_ENTS" | grep -q "com.apple.security.app-sandbox"; then
                pass "Signed app contains com.apple.security.app-sandbox"
            else
                fail "Signed app missing com.apple.security.app-sandbox"
            fi

            if echo "$SIGNED_ENTS" | grep -q "com.apple.security.network.client"; then
                pass "Signed app contains com.apple.security.network.client"
            else
                fail "Signed app missing com.apple.security.network.client"
            fi

            # Check forbidden
            if echo "$SIGNED_ENTS" | grep -q "com.apple.security.device.camera"; then
                fail "Signed app contains FORBIDDEN com.apple.security.device.camera"
            else
                pass "Signed app does not contain com.apple.security.device.camera"
            fi

            if echo "$SIGNED_ENTS" | grep -q "com.apple.security.network.server"; then
                fail "Signed app contains FORBIDDEN com.apple.security.network.server"
            else
                pass "Signed app does not contain com.apple.security.network.server"
            fi

            # Check Info.plist
            INFO_PLIST="$APP_PATH/Contents/Info.plist"
            if [ -f "$INFO_PLIST" ]; then
                INFO_CONTENT=$(plutil -p "$INFO_PLIST" 2>/dev/null || echo "")
                if echo "$INFO_CONTENT" | grep -q "NSLocalNetworkUsageDescription"; then
                    pass "Info.plist contains NSLocalNetworkUsageDescription"
                else
                    fail "Info.plist missing NSLocalNetworkUsageDescription"
                fi

                if echo "$INFO_CONTENT" | grep -q "NSCameraUsageDescription"; then
                    fail "Info.plist contains NSCameraUsageDescription (forbidden for macOS)"
                else
                    pass "Info.plist does not contain NSCameraUsageDescription"
                fi
            else
                warn "Info.plist not found in app bundle"
            fi
        else
            fail "Could not extract entitlements from signed app (codesign failed)"
        fi
    fi
else
    echo "--- Signed Product Validation ---"
    warn "No .app path provided — skipping signed product validation"
    echo "  To validate a signed product, run:"
    echo "    $0 \"/path/to/Forsetti for Jamf Pro Admins.app\""
fi

echo ""
echo "=== Summary ==="
echo "  Passed: $PASS"
echo "  Failed: $FAIL"
echo "  Warnings: $WARN"
echo ""

if [ "$FAIL" -gt 0 ]; then
    echo "RESULT: FAIL — $FAIL requirement(s) not met"
    exit 1
else
    echo "RESULT: PASS — All source-level requirements met"
    exit 0
fi
