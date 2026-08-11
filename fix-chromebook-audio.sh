#!/usr/bin/env bash
#
# fix-chromebook-audio.sh
#
# Restores speaker audio on this laptop (Google "Boten" Jasper Lake Chromebook,
# sof-rt5682 card + rt1015 amplifiers) after a system reinstall.
#
# What it does:
#   1. Installs git (if missing).
#   2. Clones and runs WeirdTreeThing/chromebook-linux-audio -> installs the
#      ChromeOS UCM configurations (HiFi profile with Speaker/Headphones output).
#   3. Applies the missing piece: rt1015 "Left/Right Bypass Boost" = on
#      (DAPM blocks this control while the amp is playing, so we set it with the
#      audio server stopped) and persists the ALSA state.
#
# Run as a regular user (NOT via sudo) — the script asks for sudo itself:
#   bash ~/fix-chromebook-audio.sh
#
set -euo pipefail

REPO_DIR="${HOME}/chromebook-linux-audio"
CARD="0"

log()  { printf '\033[1;34m==>\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m[!]\033[0m %s\n' "$*"; }
die()  { printf '\033[1;31m[x]\033[0m %s\n' "$*" >&2; exit 1; }

# --- 0. Sanity checks ---------------------------------------------------------
[ "$(id -u)" -eq 0 ] && die "Run as a regular user, not as root/sudo."
command -v sudo >/dev/null || die "sudo is required."

if command -v alsactl >/dev/null 2>&1; then ALSACTL="$(command -v alsactl)"; else ALSACTL="/sbin/alsactl"; fi
[ -x "$ALSACTL" ] || die "alsactl not found (install the alsa-utils package)."

# Warn if this is not the expected card (the script will try anyway)
if command -v aplay >/dev/null 2>&1; then
  aplay -l 2>/dev/null | grep -qi "sof-rt5682" || \
    warn "No 'sof-rt5682' card detected — this script is written for that board."
fi

# --- 1. git -------------------------------------------------------------------
if ! command -v git >/dev/null 2>&1; then
  log "Installing git..."
  sudo apt-get update -qq
  sudo DEBIAN_FRONTEND=noninteractive apt-get install -y -qq git
fi

# --- 2. chromebook-linux-audio (UCM installation) -----------------------------
log "Fetching and running chromebook-linux-audio (installs the ChromeOS UCM configs)..."
if [ -d "$REPO_DIR/.git" ]; then
  git -C "$REPO_DIR" pull --ff-only || true
else
  rm -rf "$REPO_DIR"
  git clone --depth 1 https://github.com/WeirdTreeThing/chromebook-linux-audio "$REPO_DIR"
fi
cd "$REPO_DIR"
# setup-audio elevates itself to root via sudo and installs the UCM files system-wide.
python3 ./setup-audio < /dev/null

# --- 3. rt1015: Bypass Boost = on (the missing piece) -------------------------
# Control numids (fixed for this card):
#   10 = Left Bypass Boost, 16 = Right Bypass Boost
#    9 = Left Mono LR Select (0=Left), 15 = Right Mono LR Select (1=Right)
#   20 = Left Spk Switch,   21 = Right Spk Switch
log "Stopping the audio server to free the card (the amp controls are writable then)..."
# PulseAudio (per-user) or PipeWire — stop whichever one is running.
systemctl --user stop pulseaudio.socket pulseaudio.service 2>/dev/null || true
systemctl --user stop pipewire.socket pipewire.service wireplumber.service 2>/dev/null || true
sleep 1

log "Applying the rt1015 init sequence..."
sudo amixer -c "$CARD" cset numid=10 on >/dev/null   # Left Bypass Boost
sudo amixer -c "$CARD" cset numid=16 on >/dev/null   # Right Bypass Boost
sudo amixer -c "$CARD" cset numid=9  0  >/dev/null    # Left Mono LR Select = Left
sudo amixer -c "$CARD" cset numid=15 1  >/dev/null    # Right Mono LR Select = Right
sudo amixer -c "$CARD" cset numid=20 on >/dev/null   # Left Spk Switch
sudo amixer -c "$CARD" cset numid=21 on >/dev/null   # Right Spk Switch

# Verification
lbb="$(sudo amixer -c "$CARD" cget numid=10 | grep -oE 'values=(on|off)' | head -1)"
rbb="$(sudo amixer -c "$CARD" cget numid=16 | grep -oE 'values=(on|off)' | head -1)"
[ "$lbb" = "values=on" ] && [ "$rbb" = "values=on" ] \
  && log "Bypass Boost: L=$lbb R=$rbb (OK)" \
  || warn "Bypass Boost did not apply (L=$lbb R=$rbb) — was the card busy? Run the script again."

log "Saving the ALSA state (replayed on every boot by alsa-restore)..."
sudo "$ALSACTL" store "$CARD"

# --- 4. Bring audio back up ---------------------------------------------------
log "Restarting the audio server..."
systemctl --user start pulseaudio.socket pulseaudio.service 2>/dev/null || \
systemctl --user start pipewire.socket pipewire.service wireplumber.service 2>/dev/null || true
sleep 2

log "Done. Reboot to make sure everything comes up cleanly."
log "Speakers, headphones (auto-switching on jack insert) and HDMI should now work."
