#!/usr/bin/env bash
# uninstall.sh — remove the claude-geiger statusLine from your settings.
#
# Backs up settings.json first, then deletes the statusLine entry IF it
# points at this repo's geiger.sh (so we never clobber a statusline you
# set up yourself). Re-running is safe.

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SETTINGS="${CLAUDE_SETTINGS:-$HOME/.claude/settings.json}"
GEIGER="$SCRIPT_DIR/geiger.sh"

if [ ! -f "$SETTINGS" ]; then
  echo "No settings file at $SETTINGS — nothing to do."
  exit 0
fi

if ! command -v jq >/dev/null 2>&1; then
  echo "jq not found. Remove the \"statusLine\" block from $SETTINGS by hand."
  exit 0
fi

current="$(jq -r '.statusLine.command // empty' "$SETTINGS")"
if [ -z "$current" ]; then
  echo "No statusLine configured — nothing to do."
  exit 0
fi
if [ "$current" != "$GEIGER" ]; then
  echo "statusLine points at something else, leaving it alone:"
  echo "  $current"
  exit 0
fi

cp "$SETTINGS" "$SETTINGS.bak.$(date +%s)"
tmp="$(mktemp)"
jq 'del(.statusLine)' "$SETTINGS" > "$tmp" && mv "$tmp" "$SETTINGS"
echo "Removed geiger statusLine from $SETTINGS (backup saved alongside it)."
echo "Restart Claude Code for it to take effect."
