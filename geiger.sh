#!/usr/bin/env bash
# claude-geiger — turn token consumption into geiger-counter clicks.
#
# Use as a Claude Code statusLine command. Claude Code pipes session JSON
# on stdin after each assistant message (and on the refreshInterval timer);
# this script reads the cumulative token count, works out how many tokens
# were consumed since the last poll, and fires that many (capped) clicks in
# the background. It performs NO network calls and consumes NO API tokens —
# it only observes counts Claude Code already tracks locally.
#
# Config via env (set them in settings.json's statusLine.env or your shell):
#   GEIGER_ENABLED           1 to click, 0 to stay silent (default 1)
#   GEIGER_SOUND             path to a sound file (default ./click.wav)
#   GEIGER_TOKENS_PER_CLICK  tokens per tick (default 40)
#   GEIGER_MAX_CLICKS        cap per poll, so a big context load doesn't
#                            machine-gun (default 15)
#   GEIGER_WINDOW            seconds to spread a burst over (default 0.9)
#   GEIGER_COUNT             "total" | "output" — which tokens to count
#                            (default total: input+output)
#   GEIGER_STATE_DIR         where last-counts are stored
#                            (default $TMPDIR/claude-geiger)
#   GEIGER_PLAYER            audio player command; auto-detected if unset
#                            (afplay/paplay/ffplay/play; aplay has no volume)
#   GEIGER_VOLUME            playback loudness, 1.0 = full, 0.15 = 15%
#                            (default 1.0)
#   GEIGER_CONFIG_DIR        dir holding live config files: "enabled" (mute
#                            toggle) and "volume" (default ~/.config/claude-geiger)

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

GEIGER_ENABLED="${GEIGER_ENABLED:-1}"
GEIGER_VOLUME="${GEIGER_VOLUME:-1.0}"
GEIGER_CONFIG_DIR="${GEIGER_CONFIG_DIR:-$HOME/.config/claude-geiger}"

# Config files in GEIGER_CONFIG_DIR override the env defaults, and are re-read
# every poll so changes take effect live (no Claude Code restart). This is also
# how settings persist: a statusLine can't inject env vars, so put config here.
#   enabled  -> "1"/"0", written by the menu bar app (mute toggle)
#   volume   -> playback loudness, e.g. "0.15"
if [ -f "$GEIGER_CONFIG_DIR/enabled" ]; then
  GEIGER_ENABLED="$(cat "$GEIGER_CONFIG_DIR/enabled" 2>/dev/null)"
  GEIGER_ENABLED="${GEIGER_ENABLED:-1}"
fi
if [ -f "$GEIGER_CONFIG_DIR/volume" ]; then
  GEIGER_VOLUME="$(cat "$GEIGER_CONFIG_DIR/volume" 2>/dev/null)"
  GEIGER_VOLUME="${GEIGER_VOLUME:-1.0}"
fi
export GEIGER_VOLUME   # play-clicks.sh (launched below) reads it from the env
GEIGER_SOUND="${GEIGER_SOUND:-$SCRIPT_DIR/click.wav}"
GEIGER_TOKENS_PER_CLICK="${GEIGER_TOKENS_PER_CLICK:-40}"
GEIGER_MAX_CLICKS="${GEIGER_MAX_CLICKS:-15}"
GEIGER_WINDOW="${GEIGER_WINDOW:-0.9}"
GEIGER_COUNT="${GEIGER_COUNT:-total}"
GEIGER_STATE_DIR="${GEIGER_STATE_DIR:-${TMPDIR:-/tmp}/claude-geiger}"

# Fall back to a macOS system sound if click.wav is missing — but only on
# macOS, since that .aiff isn't playable by Linux players like paplay/aplay.
if [ ! -f "$GEIGER_SOUND" ] && [ -f "/System/Library/Sounds/Pop.aiff" ]; then
  GEIGER_SOUND="/System/Library/Sounds/Pop.aiff"
fi

input="$(cat)"

# Parse with jq when available; fall back to grep for zero-dependency use.
if command -v jq >/dev/null 2>&1; then
  read -r in_tok out_tok pct session < <(
    printf '%s' "$input" | jq -r '
      [ (.context_window.total_input_tokens  // 0),
        (.context_window.total_output_tokens // 0),
        (.context_window.used_percentage     // 0),
        (.session_id // "default") ] | @tsv' 2>/dev/null | tr '\t' ' '
  )
else
  num() { printf '%s' "$input" | grep -o "\"$1\"[[:space:]]*:[[:space:]]*[0-9]*" | head -n1 | grep -o '[0-9]*$'; }
  in_tok="$(num total_input_tokens)"
  out_tok="$(num total_output_tokens)"
  pct="$(num used_percentage)"
  session="$(printf '%s' "$input" | grep -o '"session_id"[[:space:]]*:[[:space:]]*"[^"]*"' | head -n1 | sed 's/.*"\([^"]*\)"$/\1/')"
fi

in_tok="${in_tok:-0}"; out_tok="${out_tok:-0}"; pct="${pct:-0}"; session="${session:-default}"

if [ "$GEIGER_COUNT" = "output" ]; then
  total=$(( out_tok ))
else
  total=$(( in_tok + out_tok ))
fi

# Track the previous count per session so concurrent sessions don't collide.
mkdir -p "$GEIGER_STATE_DIR" 2>/dev/null
state_file="$GEIGER_STATE_DIR/${session}.last"
prev=0
[ -f "$state_file" ] && prev="$(cat "$state_file" 2>/dev/null)"
prev="${prev:-0}"
printf '%s' "$total" > "$state_file"

delta=$(( total - prev ))
(( delta < 0 )) && delta=0   # new session or post-/compact reset

if [ "$GEIGER_ENABLED" = "1" ] && [ "$delta" -gt 0 ] && [ -f "$GEIGER_SOUND" ]; then
  clicks=$(( delta / GEIGER_TOKENS_PER_CLICK ))
  (( clicks < 1 )) && clicks=1
  (( clicks > GEIGER_MAX_CLICKS )) && clicks=$GEIGER_MAX_CLICKS
  # Fire-and-forget: never block the statusline render.
  nohup bash "$SCRIPT_DIR/play-clicks.sh" "$clicks" "$GEIGER_WINDOW" "$GEIGER_SOUND" >/dev/null 2>&1 &
  disown 2>/dev/null
fi

# Statusline text. printf with thousands separators where the locale allows.
printf "\xE2\x98\xA2 %'d tok  %s%% ctx" "$total" "$pct" 2>/dev/null \
  || printf "\xE2\x98\xA2 %d tok  %s%% ctx" "$total" "$pct"
