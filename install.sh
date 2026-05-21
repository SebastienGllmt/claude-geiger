#!/usr/bin/env bash
# install.sh — wire claude-geiger into your Claude Code statusLine.
#
# Merges a statusLine entry into ~/.claude/settings.json (backing up first),
# pointing at geiger.sh in this folder with a 1s refresh. Re-running is safe.
#
# If a *different* statusLine is already configured, you'll be asked to
# confirm before it's replaced. Pass -y/--force (or set GEIGER_FORCE=1) to
# skip the prompt — useful for non-interactive installs.

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SETTINGS="${CLAUDE_SETTINGS:-$HOME/.claude/settings.json}"
GEIGER="$SCRIPT_DIR/geiger.sh"

FORCE="${GEIGER_FORCE:-0}"
case "${1:-}" in -y|--force|--yes) FORCE=1 ;; esac

chmod +x "$SCRIPT_DIR/geiger.sh" "$SCRIPT_DIR/play-clicks.sh" 2>/dev/null || true

# Generate the click sound if it's not there yet and python3 is available.
if [ ! -f "$SCRIPT_DIR/click.wav" ] && command -v python3 >/dev/null 2>&1; then
  python3 "$SCRIPT_DIR/make-click.py" || true
fi

mkdir -p "$(dirname "$SETTINGS")"
[ -f "$SETTINGS" ] || echo '{}' > "$SETTINGS"

if ! command -v jq >/dev/null 2>&1; then
  cat <<EOF
jq not found. Add this to $SETTINGS manually:

  "statusLine": {
    "type": "command",
    "command": "$GEIGER",
    "refreshInterval": 1
  }
EOF
  exit 0
fi

# If a *different* statusLine is already configured, don't clobber it without
# asking. Confirm interactively; abort if we can't ask (e.g. piped install)
# unless the user opted into -y/--force/GEIGER_FORCE.
existing="$(jq -r '.statusLine.command // empty' "$SETTINGS")"
if [ -n "$existing" ] && [ "$existing" != "$GEIGER" ] && [ "$FORCE" != "1" ]; then
  echo "You already have a statusLine configured:"
  echo "  $existing"
  echo "claude-geiger will replace it (your settings.json is backed up first)."
  if [ -t 0 ]; then
    printf "Replace it? [y/N] "
    read -r reply
    case "$reply" in
      [yY]|[yY][eE][sS]) ;;
      *) echo "Aborted. No changes made."; exit 0 ;;
    esac
  else
    echo "Refusing to overwrite non-interactively. Re-run with -y to confirm,"
    echo "or run ./uninstall.sh on your current statusLine first."
    exit 0
  fi
fi

cp "$SETTINGS" "$SETTINGS.bak.$(date +%s)"
tmp="$(mktemp)"
jq --arg cmd "$GEIGER" '
  .statusLine = { "type": "command", "command": $cmd, "refreshInterval": 1 }
' "$SETTINGS" > "$tmp" && mv "$tmp" "$SETTINGS"

echo "Installed. statusLine -> $GEIGER  (backup saved alongside $SETTINGS)"
echo "Start a new Claude Code session to hear it. Toggle off with: GEIGER_ENABLED=0"
echo "Remove it later with: ./uninstall.sh"
