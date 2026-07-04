#!/bin/zsh
set -euo pipefail

STATE_DIR="/Library/Application Support/JamfDashboard/TemporaryAdmin"
STATE_FILE="${STATE_DIR}/active.state"
LOG_DIR="/Library/Logs/JamfDashboard"
LOG_FILE="${LOG_DIR}/temporary-admin-elevation.log"
DEMOTE_SCRIPT="${STATE_DIR}/demote-temporary-admin.zsh"
RUN_RECON="${TEMP_ADMIN_RUN_RECON:-true}"

mkdir -p "$LOG_DIR"
touch "$LOG_FILE"
chown root:wheel "$LOG_FILE"
chmod 600 "$LOG_FILE"

log() {
  /bin/echo "$(/bin/date -u +"%Y-%m-%dT%H:%M:%SZ") $*" >> "$LOG_FILE"
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
  log "ERROR demote_now_not_root"
  exit 1
fi

if [[ ! -f "$STATE_FILE" ]]; then
  log "INFO demote_now_no_state"
  run_recon
  exit 0
fi

if [[ -x "$DEMOTE_SCRIPT" ]]; then
  "$DEMOTE_SCRIPT"
  exit $?
fi

target_user="$(state_value user || true)"
was_admin="$(state_value was_admin || true)"

if [[ -z "$target_user" ]]; then
  log "ERROR demote_now_missing_user"
  run_recon
  exit 2
fi

if [[ "$was_admin" != "true" ]]; then
  if /usr/sbin/dseditgroup -o checkmember -m "$target_user" admin | /usr/bin/grep -qi "yes"; then
    /usr/sbin/dseditgroup -o edit -d "$target_user" -t user admin
    log "INFO demote_now_removed_admin user=${target_user}"
  fi
else
  log "INFO demote_now_skipped_original_admin user=${target_user}"
fi

label_user="$(/bin/echo "$target_user" | /usr/bin/tr -cd '[:alnum:]_.-')"
plist="/Library/LaunchDaemons/com.jamfdashboard.temporary-admin.demote.${label_user}.plist"
if [[ -f "$plist" ]]; then
  /bin/launchctl bootout system "$plist" >/dev/null 2>&1 || true
  /bin/rm -f "$plist"
fi

tmp="${STATE_FILE}.tmp"
/usr/bin/awk -F= '$1!="status" && $1!="demoted_epoch" && $1!="demoted_iso" && $1!="last_change_epoch" && $1!="last_change_iso" {print}' "$STATE_FILE" > "$tmp"
{
  echo "status=demoted"
  echo "demoted_epoch=$(/bin/date +%s)"
  echo "demoted_iso=$(/bin/date -u +"%Y-%m-%dT%H:%M:%SZ")"
  echo "last_change_epoch=$(/bin/date +%s)"
  echo "last_change_iso=$(/bin/date -u +"%Y-%m-%dT%H:%M:%SZ")"
} >> "$tmp"
chown root:wheel "$tmp"
chmod 600 "$tmp"
/bin/mv "$tmp" "$STATE_FILE"

run_recon
exit 0
