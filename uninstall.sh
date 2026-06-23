#!/usr/bin/env bash
#
# Remove the daily recap launchd agent. Does not touch your files or config.

set -uo pipefail

LABEL="com.parkito.dailyrecap"
PLIST="$HOME/Library/LaunchAgents/$LABEL.plist"
UID_NUM="$(id -u)"

launchctl bootout "gui/$UID_NUM/$LABEL" 2>/dev/null || true
rm -f "$PLIST"
echo "Uninstalled $LABEL and removed $PLIST."
echo "(config.sh, recap.sh and logs are left in place.)"
