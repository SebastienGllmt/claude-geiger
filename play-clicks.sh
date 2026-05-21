#!/usr/bin/env bash
# play-clicks.sh <count> <window-seconds> <sound-file>
#
# Plays <count> click sounds spread (with random jitter, for an organic
# geiger feel) across <window> seconds. Each click is backgrounded so
# overlapping ticks don't queue up. Meant to be launched fire-and-forget
# by geiger.sh so it never blocks the statusline render.
#
# Audio player is auto-detected so this works on macOS and Linux alike.
# Override with GEIGER_PLAYER (just the command name, e.g. "paplay").

count="${1:-1}"
window="${2:-0.9}"
sound="${3:?sound file required}"

[ "$count" -lt 1 ] && count=1

# Pick an audio player: explicit override, else the first one installed.
# macOS ships afplay; Linux commonly has paplay (PulseAudio/PipeWire),
# aplay (ALSA), ffplay (ffmpeg) or play (sox).
player="${GEIGER_PLAYER:-}"
if [ -z "$player" ]; then
  for p in afplay paplay aplay ffplay play; do
    if command -v "$p" >/dev/null 2>&1; then player="$p"; break; fi
  done
fi
[ -z "$player" ] && exit 0   # nothing to play with; stay silent

# Play one sound, backgrounded and quiet. Each player wants different flags.
play_one() {
  case "$player" in
    afplay) afplay "$sound" ;;
    paplay) paplay "$sound" ;;
    aplay)  aplay -q "$sound" ;;
    ffplay) ffplay -nodisp -autoexit -loglevel quiet "$sound" ;;
    play)   play -q "$sound" ;;
    *)      "$player" "$sound" ;;
  esac >/dev/null 2>&1
}

# Base spacing between ticks.
interval="$(awk -v w="$window" -v c="$count" 'BEGIN { if (c <= 1) print 0; else print w / c }')"

for ((i = 0; i < count; i++)); do
  play_one &
  if [ "$i" -lt $((count - 1)) ]; then
    # Sleep a jittered fraction of the interval (0.5x–1.5x) so ticks sound
    # irregular rather than metronomic.
    sleep "$(awk -v iv="$interval" 'BEGIN { srand(); print iv * (0.5 + rand()) }')"
  fi
done

wait
