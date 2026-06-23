#!/usr/bin/env bash
#
# Install (or reinstall) the daily recap as a macOS launchd agent.
# Runs recap.sh every day at the time set in config.sh (default 08:55 local).

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_FILE="$SCRIPT_DIR/config.sh"
LABEL="com.parkito.dailyrecap"
PLIST="$HOME/Library/LaunchAgents/$LABEL.plist"
LOG_FILE="$SCRIPT_DIR/recap.log"

if [ ! -f "$CONFIG_FILE" ]; then
  echo "Missing config.sh. Run:  cp config.example.sh config.sh  then edit it." >&2
  exit 1
fi
# shellcheck source=/dev/null
. "$CONFIG_FILE"
: "${RECAP_HOUR:=8}"
: "${RECAP_MINUTE:=55}"
: "${SKIP_WEEKENDS:=true}"

if [ -z "${DISCORD_WEBHOOK_URL:-}" ] || [ "${DISCORD_WEBHOOK_URL:-}" = "PASTE_YOUR_DISCORD_WEBHOOK_URL_HERE" ]; then
  echo "WARNING: DISCORD_WEBHOOK_URL is not set in config.sh — the job will error until you set it."
fi

mkdir -p "$HOME/Library/LaunchAgents"

# PATH for launchd's minimal environment (homebrew + user-local bin first)
PATH_LINE="$HOME/.local/bin:/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"

# Build the schedule. SKIP_WEEKENDS=true -> only Mon–Fri (Weekday 1..5); else daily.
if [ "$SKIP_WEEKENDS" = "true" ]; then
  ITEMS=""
  for wd in 1 2 3 4 5; do
    ITEMS="$ITEMS
        <dict>
            <key>Weekday</key>
            <integer>$wd</integer>
            <key>Hour</key>
            <integer>$RECAP_HOUR</integer>
            <key>Minute</key>
            <integer>$RECAP_MINUTE</integer>
        </dict>"
  done
  SCHEDULE_BLOCK="    <key>StartCalendarInterval</key>
    <array>$ITEMS
    </array>"
  SCHEDULE_DESC="weekdays (Mon-Fri)"
else
  SCHEDULE_BLOCK="    <key>StartCalendarInterval</key>
    <dict>
        <key>Hour</key>
        <integer>$RECAP_HOUR</integer>
        <key>Minute</key>
        <integer>$RECAP_MINUTE</integer>
    </dict>"
  SCHEDULE_DESC="every day"
fi

cat > "$PLIST" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>$LABEL</string>
    <key>ProgramArguments</key>
    <array>
        <string>/bin/bash</string>
        <string>$SCRIPT_DIR/recap.sh</string>
    </array>
$SCHEDULE_BLOCK
    <key>EnvironmentVariables</key>
    <dict>
        <key>PATH</key>
        <string>$PATH_LINE</string>
        <key>HOME</key>
        <string>$HOME</string>
    </dict>
    <key>StandardOutPath</key>
    <string>$LOG_FILE</string>
    <key>StandardErrorPath</key>
    <string>$LOG_FILE</string>
    <key>RunAtLoad</key>
    <false/>
    <key>ProcessType</key>
    <string>Background</string>
</dict>
</plist>
EOF

UID_NUM="$(id -u)"
launchctl bootout "gui/$UID_NUM/$LABEL" 2>/dev/null || true
if ! launchctl bootstrap "gui/$UID_NUM" "$PLIST" 2>/dev/null; then
  launchctl load -w "$PLIST" 2>/dev/null || true
fi
launchctl enable "gui/$UID_NUM/$LABEL" 2>/dev/null || true

printf 'Installed %s — runs %s at %02d:%02d local time.\n' "$LABEL" "$SCHEDULE_DESC" "$RECAP_HOUR" "$RECAP_MINUTE"
echo "Plist:    $PLIST"
echo "Run now:  launchctl kickstart -k gui/$UID_NUM/$LABEL    (or: $SCRIPT_DIR/recap.sh)"
echo "Logs:     $LOG_FILE"
