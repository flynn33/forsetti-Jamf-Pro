#!/bin/zsh
STATE_FILE="/Library/Application Support/JamfDashboard/TemporaryAdmin/active.state"
KEY="run_id"
DEFAULT_VALUE="Not Reported"

if [[ ! -f "$STATE_FILE" ]]; then
  echo "<result>${DEFAULT_VALUE}</result>"
  exit 0
fi

value="$(/usr/bin/awk -F= -v k="$KEY" '$1==k {print substr($0, length(k)+2)}' "$STATE_FILE" | /usr/bin/tail -1)"
if [[ -z "$value" ]]; then
  echo "<result>${DEFAULT_VALUE}</result>"
else
  echo "<result>${value}</result>"
fi
