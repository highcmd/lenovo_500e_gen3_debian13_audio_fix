# lenovo_500e_gen3_debian13_audio_fix

Fix for audio (speakers, headphones, HDMI) on the **Lenovo 500e Chromebook Gen 3**
(Google "Boten", Jasper Lake) running **Debian 13**.

After a fresh Linux install the `sof-rt5682` card is detected, ALSA lists the
devices, mixers are turned up — and the speakers stay dead silent.
`fix-chromebook-audio.sh` gets audio into a working state in a single run.

## What's actually wrong

Two separate problems stack up:

1. **Missing UCM configuration** — the SOF driver doesn't know how to map this
   board's audio paths on its own (Speaker / Headphones / auto-switching on jack
   insertion). Those profiles live in ChromeOS and have to be installed separately.
2. **The rt1015 amplifiers boot muted** — the *Left/Right Bypass Boost* controls
   default to `off`. Worse, DAPM blocks writes to them while the amp is active, so
   a plain `amixer set ... on` with PipeWire/PulseAudio running silently does
   nothing. They have to be set **while the audio server is stopped**.

## What the script does

1. Sanity-checks the environment (non-root, `sudo`, `alsactl`, `sof-rt5682` card)
   and installs `git` if it's missing.
2. Clones and runs [WeirdTreeThing/chromebook-linux-audio](https://github.com/WeirdTreeThing/chromebook-linux-audio),
   which installs the ChromeOS UCM configurations system-wide.
3. Stops PipeWire/PulseAudio to free the card, then applies the rt1015 init
   sequence:

   | numid | Control               | Value        |
   |-------|-----------------------|--------------|
   | 10    | Left Bypass Boost     | on           |
   | 16    | Right Bypass Boost    | on           |
   | 9     | Left Mono LR Select   | 0 (Left)     |
   | 15    | Right Mono LR Select  | 1 (Right)    |
   | 20    | Left Spk Switch       | on           |
   | 21    | Right Spk Switch      | on           |

4. Verifies that Bypass Boost really took effect and persists the state with
   `alsactl store`, so `alsa-restore` replays it on every boot.
5. Restarts the audio server.

The script is idempotent — just run it again if, for example, the card was busy
the first time.

## Requirements

- Lenovo 500e Chromebook Gen 3 (or another board with a `sof-rt5682` card + rt1015 amps)
- Debian 13 (should work on other `apt`-based distros too)
- `sudo`, `alsa-utils`, `python3`
- Internet access (it clones the UCM repo)

## Usage

Run it **as a regular user**, not under `sudo` — the script elevates itself only
where it needs to:

```bash
bash ~/fix-chromebook-audio.sh
```

Reboot afterwards to confirm everything comes up cleanly. Speakers, headphones
(with auto-switching on jack insert) and HDMI output should all work.

## Troubleshooting

**"Bypass Boost did not apply"** — some process was still holding the card.
Close media players / your browser and run the script again. To see who's
holding it: `fuser -v /dev/snd/*`.

**Silence after a reboot** — check that `alsa-restore` is actually running
(`systemctl status alsa-restore`) and that the state was saved:

```bash
amixer -c 0 cget numid=10   # should report values=on
```

**A different card than `sof-rt5682`** — the `numid` values are specific to this
board and will point at completely unrelated controls on other hardware. Check
yours with `amixer -c 0 controls` before running the script.

## Credits

The heavy lifting (ChromeOS UCM configurations) is done by
[WeirdTreeThing/chromebook-linux-audio](https://github.com/WeirdTreeThing/chromebook-linux-audio).
This script just wraps it and adds the missing rt1015 piece.
