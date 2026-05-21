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

## Tuning (environment variables)

| Variable | Default | Meaning |
|---|---|---|
| `GEIGER_ENABLED` | `1` | `0` to silence without uninstalling |
| `GEIGER_TOKENS_PER_CLICK` | `40` | Fewer = more clicks |
| `GEIGER_MAX_CLICKS` | `15` | Cap per poll (stops huge context loads machine-gunning) |
| `GEIGER_WINDOW` | `0.9` | Seconds to spread a burst over |
| `GEIGER_COUNT` | `total` | `total` (input+output) or `output` only |
| `GEIGER_SOUND` | `./click.wav` | Any file your player can play |
| `GEIGER_PLAYER` | auto | Player command; auto-detected if unset |
| `GEIGER_STATE_DIR` | `$TMPDIR/claude-geiger` | Per-session last-count storage |

Set these in your shell, or in the statusLine block via an `"env"` object.

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
