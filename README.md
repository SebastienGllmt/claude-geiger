# claude-geiger ☢

Turn Claude Code's token consumption into geiger-counter clicks. The more
tokens a turn burns, the faster it ticks.

## How it works

Claude Code has **no per-token event** — nothing fires while the model is
streaming. What it *does* expose is a [statusLine](https://code.claude.com/docs/en/statusline)
command that receives the running session state (including cumulative token
counts) as JSON on stdin, re-invoked after each assistant message and on a
1-second timer.

So this isn't literally one click per token. It's a **rate counter**, like a
real geiger counter: each poll, `geiger.sh` reads the cumulative token total,
subtracts the previous poll's total, and fires a burst of clicks proportional
to the delta (one click per `GEIGER_TOKENS_PER_CLICK` tokens, capped). From a
few feet away it sounds continuous.

**Cost: $0.** It only reads counts Claude Code already tracks locally — no API
calls, no extra tokens.

> Note: this is a Claude Code **statusLine command**, not a packaged plugin —
> you point your statusLine at `geiger.sh` and it rides the existing 1s poll.

## Install

```bash
git clone https://github.com/sebastiengllmt/claude-geiger.git
cd claude-geiger
./install.sh          # generates click.wav, wires up ~/.claude/settings.json
```

Then start a new Claude Code session.

**If you already have a different statusLine configured**, `install.sh` shows
it and asks before replacing it (`Replace it? [y/N]`, defaulting to no). When
it can't ask — e.g. a piped `curl | bash` install — it refuses rather than
overwrite; pass `-y` (or set `GEIGER_FORCE=1`) to confirm up front:

```bash
./install.sh -y      # replace any existing statusLine without prompting
```

Either way it backs up your `settings.json` to `settings.json.bak.<timestamp>`
before writing. To get your old statusLine back, restore that `.bak`, or run
`./uninstall.sh` (which only removes geiger's own entry).

To wire it up by hand instead, add the following to `~/.claude/settings.json`,
using the **absolute path** to `geiger.sh` in your clone:

```json
{
  "statusLine": {
    "type": "command",
    "command": "/absolute/path/to/claude-geiger/geiger.sh",
    "refreshInterval": 1
  }
}
```

## Uninstall

```bash
./uninstall.sh        # removes the statusLine entry (only if it's geiger's)
```

It backs up `settings.json` first and won't touch a statusLine pointing
somewhere else. Restart Claude Code afterward.

## Menu bar toggle (macOS)

Don't want to fiddle with env vars to silence it mid-session? Build the menu
bar app and you get a ☢ in the top-right of your screen — click it to mute or
unmute on the fly:

```bash
./menubar.sh           # builds (needs swiftc) and launches the menu bar app
./menubar.sh --login   # ...and start it automatically at login
./menubar.sh --stop    # quit it
./menubar.sh --logout  # remove the login item
```

The toggle is **live**: clicking it writes `~/.config/claude-geiger/enabled`
(`1`/`0`), which `geiger.sh` re-reads every poll — so muting takes effect
immediately, no Claude Code restart. The icon dims when muted. The app has no
Dock icon and makes no network calls. It's a SwiftUI
[`MenuBarExtra`](https://developer.apple.com/documentation/swiftui/menubarextra)
app, built locally with `swiftc` (macOS 13+). macOS only; on Linux, write `0`
to that file by hand to mute.

Note that muting (the toggle) and installing (the statusLine) are independent:
uninstalling stops the clicks by removing the statusLine, while the toggle just
flips the enabled flag. The menu bar app works regardless of whether geiger is
installed.

### The icon doesn't appear?

If `menubar.sh` reports the app is running but no icon shows up — and it isn't
hidden behind the notch or a menu bar manager — macOS's menu bar agent has
likely gotten into a state where it stops surfacing *newly launched* apps'
items (existing ones keep working). This affects any menu bar app, not just
this one. Reset it:

```bash
killall SystemUIServer; killall ControlCenter   # both relaunch automatically
```

Then relaunch with `./menubar.sh`. If it still doesn't show, logging out and
back in (or a reboot) clears it for good.

## Tuning (environment variables)

| Variable | Default | Meaning |
|---|---|---|
| `GEIGER_ENABLED` | `1` | `0` to silence without uninstalling (the menu bar toggle / config file overrides this) |
| `GEIGER_TOKENS_PER_CLICK` | `40` | Fewer = more clicks |
| `GEIGER_MAX_CLICKS` | `15` | Cap per poll (stops huge context loads machine-gunning) |
| `GEIGER_WINDOW` | `0.9` | Seconds to spread a burst over |
| `GEIGER_COUNT` | `total` | `total` (input+output) or `output` only |
| `GEIGER_SOUND` | `./click.wav` | Any file your player can play |
| `GEIGER_VOLUME` | `1.0` | Playback loudness; `0.15` = 15%, for quiet background ticks |
| `GEIGER_PLAYER` | auto | Player command; auto-detected if unset |
| `GEIGER_STATE_DIR` | `$TMPDIR/claude-geiger` | Per-session last-count storage |
| `GEIGER_CONFIG_DIR` | `~/.config/claude-geiger` | Where the live config files live |

A statusLine command **can't** be given environment variables from
`settings.json` (there's no `env` field for statusLine — it's ignored). So to
make a setting stick across sessions, drop a file in `GEIGER_CONFIG_DIR` —
`geiger.sh` reads these every poll, live, overriding the env defaults:

```bash
mkdir -p ~/.config/claude-geiger
echo 0.15 > ~/.config/claude-geiger/volume    # quiet background ticks
echo 0    > ~/.config/claude-geiger/enabled   # mute (same as the menu bar toggle)
```

(The env vars above still work if you export them in a shell that launches
Claude Code; the config files are the reliable way to persist them.)

## Limitations

- Resolution is ~1s and counts land *after* a message renders, so a long
  generation ticks in chunks rather than smoothly.
- Needs a command-line audio player. `play-clicks.sh` auto-detects `afplay`
  (macOS) or `paplay`/`aplay`/`ffplay`/`play` (Linux); install one (e.g.
  `pulseaudio-utils` for `paplay`, `alsa-utils` for `aplay`) or set
  `GEIGER_PLAYER` if yours isn't found. With no player it stays silent.

## Files

- `geiger.sh` — the statusLine command (parse JSON, compute delta, fire clicks)
- `play-clicks.sh` — plays N jittered clicks over a window, backgrounded
- `make-click.py` — synthesizes `click.wav`
- `install.sh` — merges the statusLine config into your settings
- `uninstall.sh` — removes the statusLine config again
- `geigerbar.swift` — macOS menu bar toggle (☢ icon, mute/unmute live)
- `menubar.sh` — build/launch/stop the menu bar app, optional login item
