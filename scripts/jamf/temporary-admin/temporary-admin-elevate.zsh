#!/bin/zsh
set -euo pipefail

DURATION_MINUTES="${4:-15}"
WORKFLOW_LABEL="${5:-temporary-admin-elevation}"
STATE_DIR="/Library/Application Support/JamfDashboard/TemporaryAdmin"
LOG_DIR="/Library/Logs/JamfDashboard"
STATE_FILE="${STATE_DIR}/active.state"
LOG_FILE="${LOG_DIR}/temporary-admin-elevation.log"
DEMOTE_SCRIPT="${STATE_DIR}/demote-temporary-admin.zsh"
RUN_RECON="${TEMP_ADMIN_RUN_RECON:-true}"

mkdir -p "$STATE_DIR" "$LOG_DIR"
chown root:wheel "$STATE_DIR" "$LOG_DIR"
chmod 700 "$STATE_DIR"
touch "$LOG_FILE"
chown root:wheel "$LOG_FILE"
chmod 600 "$LOG_FILE"

log() {
  /bin/echo "$(/bin/date -u +"%Y-%m-%dT%H:%M:%SZ") $*" >> "$LOG_FILE"
}

write_state() {
  local tmp="${STATE_FILE}.tmp"
  /bin/cat > "$tmp"
  chown root:wheel "$tmp"
  chmod 600 "$tmp"
  /bin/mv "$tmp" "$STATE_FILE"
}

state_value() {
  local key="$1"
  [[ -f "$STATE_FILE" ]] || return 0
  /usr/bin/awk -F= -v k="$key" '$1==k {print substr($0, length(k)+2)}' "$STATE_FILE" | /usr/bin/tail -1
}

run_recon() {
  if [[ "$RUN_RECON" == "true" && -x /usr/local/bin/jamf ]]; then
    /usr/local/bin/jamf recon >/dev/null 2>&1 || log "WARN jamf_recon_failed"
  fi
}

if [[ "$(/usr/bin/id -u)" != "0" ]]; then
  log "ERROR not_root"
  exit 1
fi

case "$DURATION_MINUTES" in
  5|15|30|60) ;;
  *)
    log "ERROR invalid_duration value=${DURATION_MINUTES}"
    exit 2
    ;;
esac

console_user="$(/usr/sbin/scutil <<< 'show State:/Users/ConsoleUser' | /usr/bin/awk '/Name :/ && $3 != "loginwindow" { print $3; exit }')"

if [[ -z "${console_user:-}" || "$console_user" == "root" || "$console_user" == "_mbsetupuser" ]]; then
  log "ERROR no_valid_console_user user=${console_user:-empty}"
  write_state <<STATE
status=failed
error=no_valid_console_user
workflow_label=${WORKFLOW_LABEL}
last_change_epoch=$(/bin/date +%s)
last_change_iso=$(/bin/date -u +"%Y-%m-%dT%H:%M:%SZ")
STATE
  run_recon
  exit 3
fi

if ! /usr/bin/id "$console_user" >/dev/null 2>&1; then
  log "ERROR console_user_not_found user=${console_user}"
  write_state <<STATE
status=failed
user=${console_user}
error=console_user_not_found
workflow_label=${WORKFLOW_LABEL}
last_change_epoch=$(/bin/date +%s)
last_change_iso=$(/bin/date -u +"%Y-%m-%dT%H:%M:%SZ")
STATE
  run_recon
  exit 4
fi

now_epoch="$(/bin/date +%s)"
now_iso="$(/bin/date -u +"%Y-%m-%dT%H:%M:%SZ")"
existing_status="$(state_value status || true)"
existing_expires="$(state_value expires_epoch || true)"
existing_user="$(state_value user || true)"

if [[ "$existing_status" == "elevated" && -n "$existing_expires" && "$existing_expires" =~ '^[0-9]+$' && "$existing_expires" -gt "$now_epoch" ]]; then
  log "INFO active_elevation_exists user=${existing_user} expires_epoch=${existing_expires}; refusing_to_extend"
  run_recon
  exit 0
fi

run_id="$(/bin/date -u +"%Y%m%dT%H%M%SZ")-${console_user}"
expires_epoch="$((now_epoch + (DURATION_MINUTES * 60)))"
expires_iso="$(/bin/date -u -r "$expires_epoch" +"%Y-%m-%dT%H:%M:%SZ")"

cat > "$DEMOTE_SCRIPT" <<'DEMOTE'
#!/bin/zsh
set -euo pipefail

STATE_DIR="/Library/Application Support/JamfDashboard/TemporaryAdmin"
LOG_DIR="/Library/Logs/JamfDashboard"
STATE_FILE="${STATE_DIR}/active.state"
LOG_FILE="${LOG_DIR}/temporary-admin-elevation.log"
RUN_RECON="${TEMP_ADMIN_RUN_RECON:-true}"

log() {
  /bin/echo "$(/bin/date -u +"%Y-%m-%dT%H:%M:%SZ") $*" >> "$LOG_FILE"
}

state_value() {
  local key="$1"
  [[ -f "$STATE_FILE" ]] || return 0
  /usr/bin/awk -F= -v k="$key" '$1==k {print substr($0, length(k)+2)}' "$STATE_FILE" | /usr/bin/tail -1
}

write_state_preserving() {
  local tmp="${STATE_FILE}.tmp"
  /usr/bin/awk -F= '$1!="status" && $1!="demoted_epoch" && $1!="demoted_iso" && $1!="last_change_epoch" && $1!="last_change_iso" && $1!="error" {print}' "$STATE_FILE" > "$tmp"
  {
    echo "status=$1"
    echo "demoted_epoch=$(/bin/date +%s)"
    echo "demoted_iso=$(/bin/date -u +"%Y-%m-%dT%H:%M:%SZ")"
    echo "last_change_epoch=$(/bin/date +%s)"
    echo "last_change_iso=$(/bin/date -u +"%Y-%m-%dT%H:%M:%SZ")"
  } >> "$tmp"
  chown root:wheel "$tmp"
  chmod 600 "$tmp"
  /bin/mv "$tmp" "$STATE_FILE"
}

run_recon() {
  if [[ "$RUN_RECON" == "true" && -x /usr/local/bin/jamf ]]; then
    /usr/local/bin/jamf recon >/dev/null 2>&1 || log "WARN jamf_recon_failed"
  fi
}

if [[ "$(/usr/bin/id -u)" != "0" ]]; then
  log "ERROR demote_not_root"
  exit 1
fi

if [[ ! -f "$STATE_FILE" ]]; then
  log "ERROR demote_missing_state"
  exit 2
fi

target_user="$(state_value user || true)"
was_admin="$(state_value was_admin || true)"

if [[ -z "$target_user" ]]; then
  log "ERROR demote_missing_user"
  exit 3
fi

label_user="$(/bin/echo "$target_user" | /usr/bin/tr -cd '[:alnum:]_.-')"
plist="/Library/LaunchDaemons/com.jamfdashboard.temporary-admin.demote.${label_user}.plist"

if [[ "$was_admin" == "true" ]]; then
  log "INFO demote_skipped_original_admin user=${target_user}"
  write_state_preserving "already_admin"
else
  if /usr/sbin/dseditgroup -o checkmember -m "$target_user" admin | /usr/bin/grep -qi "yes"; then
    /usr/sbin/dseditgroup -o edit -d "$target_user" -t user admin
    log "INFO demoted_user user=${target_user}"
  else
    log "INFO user_already_standard user=${target_user}"
  fi
  write_state_preserving "demoted"
fi

if [[ -f "$plist" ]]; then
  /bin/launchctl bootout system "$plist" >/dev/null 2>&1 || true
  /bin/rm -f "$plist"
fi

run_recon
exit 0
DEMOTE

chown root:wheel "$DEMOTE_SCRIPT"
chmod 700 "$DEMOTE_SCRIPT"

if /usr/sbin/dseditgroup -o checkmember -m "$console_user" admin | /usr/bin/grep -qi "yes"; then
  write_state <<STATE
status=already_admin
user=${console_user}
run_id=${run_id}
workflow_label=${WORKFLOW_LABEL}
started_epoch=${now_epoch}
started_iso=${now_iso}
expires_epoch=
expires_iso=
duration_minutes=${DURATION_MINUTES}
was_admin=true
last_change_epoch=${now_epoch}
last_change_iso=${now_iso}
STATE
  log "INFO user_already_admin user=${console_user} run_id=${run_id}"
  run_recon
  exit 0
fi

/usr/sbin/dseditgroup -o edit -a "$console_user" -t user admin

write_state <<STATE
status=elevated
user=${console_user}
run_id=${run_id}
workflow_label=${WORKFLOW_LABEL}
started_epoch=${now_epoch}
started_iso=${now_iso}
expires_epoch=${expires_epoch}
expires_iso=${expires_iso}
duration_minutes=${DURATION_MINUTES}
was_admin=false
last_change_epoch=${now_epoch}
last_change_iso=${now_iso}
STATE

label_user="$(/bin/echo "$console_user" | /usr/bin/tr -cd '[:alnum:]_.-')"
plist="/Library/LaunchDaemons/com.jamfdashboard.temporary-admin.demote.${label_user}.plist"

cat > "$plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>com.jamfdashboard.temporary-admin.demote.${label_user}</string>
    <key>ProgramArguments</key>
    <array>
        <string>${DEMOTE_SCRIPT}</string>
    </array>
    <key>StartInterval</key>
    <integer>$((DURATION_MINUTES * 60))</integer>
    <key>RunAtLoad</key>
    <false/>
</dict>
</plist>
PLIST

chown root:wheel "$plist"
chmod 644 "$plist"
/bin/launchctl bootout system "$plist" >/dev/null 2>&1 || true
/bin/launchctl bootstrap system "$plist"

log "INFO elevated_user user=${console_user} duration_minutes=${DURATION_MINUTES} expires=${expires_iso} run_id=${run_id}"
run_recon
exit 0
