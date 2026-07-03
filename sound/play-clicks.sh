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
# GEIGER_VOLUME scales playback loudness: 1.0 = full, 0.15 = 15%, etc.

count="${1:-1}"
window="${2:-0.9}"
sound="${3:?sound file required}"
volume="${GEIGER_VOLUME:-1.0}"

[ "$count" -lt 1 ] && count=1

# ---- single-flight: never let two bursts play at once ---------------------
# geiger.sh fires a fresh burst every poll (~1s), each spread over a ~0.9s
# window; on WSL the Windows player's startup latency makes consecutive bursts
# overlap. Overlapping bursts sum amplitudes, so coincident ticks sound randomly
# louder ("sometimes loud, sometimes quiet"). A burst is just a rate indicator,
# so if one is already sounding we skip this one rather than stack on top.
#
# mkdir is the portable atomic lock (macOS has no flock). We record our PID so a
# crashed holder's lock can be reclaimed (kill -0 tests liveness).
lock_dir="${GEIGER_STATE_DIR:-${TMPDIR:-/tmp}/claude-geiger}/play.lock"
mkdir -p "$(dirname "$lock_dir")" 2>/dev/null
acquire_lock() {
  if mkdir "$lock_dir" 2>/dev/null; then           # won the race
    printf '%s' "$$" > "$lock_dir/pid"
    return 0
  fi
  # Lock exists. Reclaim ONLY if it is clearly dead — never on a missing/empty
  # PID, which just means the holder is mid-startup (the mkdir-before-pid gap);
  # treating that as stale is what lets concurrent bursts leak through. As a
  # backstop for a crash inside that gap, also reclaim a lock older than 1 min
  # (a burst lasts a few seconds at most).
  local holder; holder="$(cat "$lock_dir/pid" 2>/dev/null)"
  if { [ -n "$holder" ] && ! kill -0 "$holder" 2>/dev/null; } \
     || [ -n "$(find "$lock_dir" -maxdepth 0 -mmin +1 2>/dev/null)" ]; then
    rm -rf "$lock_dir" 2>/dev/null
    if mkdir "$lock_dir" 2>/dev/null; then printf '%s' "$$" > "$lock_dir/pid"; return 0; fi
  fi
  return 1
}
acquire_lock || exit 0   # a burst is already playing — skip this one
trap 'rm -rf "$lock_dir"' EXIT

# ---- WSL2: play through the Windows audio stack ---------------------------
# Under WSL the Linux-native route (paplay -> WSLg PulseAudio -> RDP -> Windows)
# is unreliable: it can report success (exit 0, sink RUNNING) while the Windows
# host plays nothing. Going through Windows directly — powershell.exe + .NET's
# WPF MediaPlayer — hits the default playback device and just works.
#
# Two non-obvious requirements learned the hard way:
#   1. WSL env vars do NOT cross into Windows processes (only WSLENV does), so
#      the WAV path must be interpolated into the command, not passed via env —
#      otherwise the player gets $null and throws when it opens the file.
#   2. Playing straight off the \\wsl.localhost share can be blocked by
#      Windows' network-zone guard, so we copy the WAV to the Windows-local
#      %TEMP% first and play from there.
# The whole jittered sequence runs in one PowerShell call, so we pay its
# startup cost once. GEIGER_VOLUME is honored via WPF MediaPlayer's .Volume
# (a 0..1 gain, the same scale as `afplay -v` on macOS) — the simpler
# System.Media.SoundPlayer has no volume control, so we use MediaPlayer instead.
is_wsl() { grep -qiE 'microsoft|wsl' /proc/version 2>/dev/null; }

play_via_windows() {
  command -v powershell.exe >/dev/null 2>&1 || return 1
  command -v wslpath        >/dev/null 2>&1 || return 1
  local src_win win_vol
  src_win="$(wslpath -aw "$sound" 2>/dev/null)" || return 1
  [ -n "$src_win" ] || return 1
  # Clamp GEIGER_VOLUME into MediaPlayer's 0..1 range (matches afplay -v).
  win_vol="$(awk -v v="$volume" 'BEGIN { if (v < 0) v = 0; if (v > 1) v = 1; printf "%.4f", v }')"
  # Pass the script as an inline -Command string (the `-Command -` stdin form
  # silently fails to execute under some WSL/PowerShell builds). The string is
  # bash double-quoted, so bash fills in $src_win/$win_vol/$count/$window and
  # every PowerShell '$' is escaped as '\$'; the Windows path's backslashes sit
  # inside a PS single-quoted literal, where they're taken verbatim. Numbers are
  # parsed with InvariantCulture so a comma-decimal locale can't break them.
  # We copy the WAV to a Windows-local %TEMP% first (playing straight off the
  # \\wsl.localhost share can trip Windows' network-zone guard), then drive it
  # with MediaPlayer so .Volume applies.
  powershell.exe -NoProfile -NonInteractive -Command "
    \$ErrorActionPreference = 'Stop'
    \$ic = [Globalization.CultureInfo]::InvariantCulture
    try {
      \$src = '$src_win'
      # Per-sound temp file: all catalog ticks are the same byte length, so a
      # single shared name + size-only cache check would keep replaying the first
      # sound copied. Name the cache after the source and also refresh it when
      # the source is newer (so retuning a sound in place isn't stale either).
      \$dst = Join-Path \$env:TEMP ('claude-geiger-' + (Split-Path -Leaf \$src))
      if (-not (Test-Path -LiteralPath \$dst) -or
          (Get-Item -LiteralPath \$dst).Length -ne (Get-Item -LiteralPath \$src).Length -or
          (Get-Item -LiteralPath \$dst).LastWriteTime -lt (Get-Item -LiteralPath \$src).LastWriteTime) {
        Copy-Item -LiteralPath \$src -Destination \$dst -Force
      }
      Add-Type -AssemblyName PresentationCore
      \$mp = New-Object System.Windows.Media.MediaPlayer
      \$mp.Open([Uri]\$dst)
      \$mp.Volume = [double]::Parse('$win_vol', \$ic)
      Start-Sleep -Milliseconds 200   # let the media open before the first play
      \$count    = [int]'$count'
      \$window   = [double]::Parse('$window', \$ic)
      \$interval = if (\$count -le 1) { 0 } else { \$window / \$count }
      \$rng = New-Object System.Random
      for (\$i = 0; \$i -lt \$count; \$i++) {
        \$mp.Position = [TimeSpan]::Zero
        \$mp.Play()
        if (\$i -lt \$count - 1) {
          # jittered 0.5x-1.5x gap so ticks sound irregular, not metronomic
          \$ms = [int](\$interval * (0.5 + \$rng.NextDouble()) * 1000)
          if (\$ms -gt 0) { Start-Sleep -Milliseconds \$ms }
        }
      }
      Start-Sleep -Milliseconds 250   # let the last click finish before exit
    } catch { exit 1 }
  " >/dev/null 2>&1
}

# GEIGER_PLAYER=windows forces this path; on WSL it is also the default. Either
# way, fall through to the Linux players below if it is unavailable or fails.
if [ "${GEIGER_PLAYER:-}" = "windows" ]; then
  play_via_windows && exit 0
  GEIGER_PLAYER=""   # explicit request failed; let auto-detect try Linux
elif [ -z "${GEIGER_PLAYER:-}" ] && is_wsl; then
  play_via_windows && exit 0
fi

# WSL fallback / native Linux: the WSLg PulseAudio server is the only sink that
# bridges to Windows, so point libpulse at it when nothing else was requested.
if [ -z "${PULSE_SERVER:-}" ] && [ -S /mnt/wslg/PulseServer ]; then
  export PULSE_SERVER="unix:/mnt/wslg/PulseServer"
fi

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

# Play one sound, backgrounded and quiet. Each player takes volume differently:
# afplay/sox want a 0..1 gain, ffplay a 0..100 int, paplay a 0..65536 int.
# aplay has no per-play volume, so it ignores GEIGER_VOLUME (use the mixer).
pa_vol="$(awk -v v="$volume" 'BEGIN { printf "%d", v * 65536 }')"
ff_vol="$(awk -v v="$volume" 'BEGIN { printf "%d", v * 100 }')"
play_one() {
  case "$player" in
    afplay) afplay -v "$volume" "$sound" ;;
    paplay) paplay --volume="$pa_vol" "$sound" ;;
    aplay)  aplay -q "$sound" ;;
    ffplay) ffplay -nodisp -autoexit -loglevel quiet -volume "$ff_vol" "$sound" ;;
    play)   play -q -v "$volume" "$sound" ;;
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
