#!/bin/zsh
STATE_FILE="/Library/Application Support/JamfDashboard/TemporaryAdmin/active.state"

if [[ ! -f "$STATE_FILE" ]]; then
  echo "<result>Not Reported</result>"
  exit 0
fi

state_value() {
  local key="$1"
  /usr/bin/awk -F= -v k="$key" '$1==k {print substr($0, length(k)+2)}' "$STATE_FILE" | /usr/bin/tail -1
}

status="$(state_value status)"
expires_epoch="$(state_value expires_epoch)"
now_epoch="$(/bin/date +%s)"

if [[ "$status" == "elevated" && -n "$expires_epoch" && "$expires_epoch" =~ '^[0-9]+$' && "$expires_epoch" -le "$now_epoch" ]]; then
  echo "<result>expired_pending_demotion</result>"
elif [[ -z "$status" ]]; then
  echo "<result>Not Reported</result>"
else
  echo "<result>${status}</result>"
fi
