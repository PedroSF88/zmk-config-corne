# Corne Layer Overlay

A small always-on-top widget (Windows) that shows the Corne keymap for the
layer the keyboard is on, lights up keys as you press them on the Corne,
shows its combos, and shows both halves' battery. Works over USB and
Bluetooth. Click-through: it never takes focus or blocks the mouse.

## Run

Double-click `Start-Overlay.cmd`, or:

```powershell
powershell -ExecutionPolicy Bypass -File .\overlay\Start-LayerOverlay.ps1
```

Options: `-Anchor TopLeft|TopRight|BottomLeft|BottomRight` (default
BottomRight), `-Scale 1.2`, `-OverlayOpacity 0.8`, `-AllKeyboards` (light
keys from every keyboard, not only the Corne; turns off layer guessing).

Tray icon (right-click): hide/show, move to another corner, reset to Base,
exit. Double-click the tray icon to hide/show. Hover it for the battery
level. Only one copy runs at a time.

To start it with Windows: press Win+R, type `shell:startup`, and put a
shortcut to `Start-Overlay.cmd` in that folder.

## How it works

- Corne only: keystrokes are read with Windows raw input, which says which
  keyboard each key came from. Only keyboards whose device name matches
  ZMK's IDs (`VID 1D50 / PID 615E`, USB or Bluetooth) light up keys. The
  laptop keyboard is ignored.
- Layer signal: every layer key in `config/corne.keymap` is a `to_layerN`
  macro that switches layer and taps F13+N (F13 = Base ... F16 = System).
  A low-level keyboard hook catches F13-F16 and swallows them, so other apps
  never see them. Needs the firmware built from this keymap on the LEFT half.
- Layer guess: if the Corne sends a key the shown layer cannot send (say `7`
  while Base is shown), the overlay switches to the layer that has it
  (NavNum). This also works with firmware that has no layer signal, and
  puts the overlay right again after the keyboard wakes from sleep.
- Key lighting: each keystroke is matched to its position on the shown
  layer (Shift-aware, so `=` and `+` light different keys). A keystroke that
  no key on the layer sends is matched to a combo; the combo's keys light up
  with its name in the top-right corner.
- Combos on the map (only those active on the shown layer). Two keys side
  by side: a small label in the gap between them (BSPC between O and P).
  Keys further apart: a small tag with the combo's name on each of its keys
  (ESC on A and on V). Labels and tags light up when you use the combo.
  Tray -> "Show combos" turns them off.
- Keymap edits show up by themselves: when `config/corne.keymap` is saved,
  the overlay re-runs `tools/generate_overlay_layout.py` in the background
  (needs Python) and reloads within about 2 seconds ("keymap updated"). If
  the keymap has an error, it keeps the last good layout and shows the error.
  The overlay updates before the keyboard does: flash the new firmware too.
- Battery, both halves: read from the keyboard over Bluetooth every minute
  (every 5 s while it cannot be read), on a separate thread so typing is
  never held up. The left half reports its own level and passes on the
  right half's (`config/corne.conf`). "--" means not known right now, e.g.
  while a half restarts. A tray notification warns at 20% and again at 10%
  for each half. If the Bluetooth read fails, the left level falls back to
  what Windows shows in Settings.

## Test

```powershell
powershell -ExecutionPolicy Bypass -File .\overlay\Start-LayerOverlay.ps1 -SelfTest
```

Feeds scripted Corne keystrokes through the key handling (layer guess, layer
signals, combos, transparent keys, Shift) and prints PASS/FAIL per step. It
includes a baseline: with guessing off, the same keystroke must not move the
overlay.

```powershell
powershell -ExecutionPolicy Bypass -File .\overlay\Start-LayerOverlay.ps1 -BatteryTest
```

Reads both halves' battery once, the same way the overlay does, and prints
it next to what Windows shows. Use it when a battery level is missing.

## Limits

- Without the layer signal (old firmware), the overlay only changes layer
  once you type a key that exists on the new layer, not when you press the
  layer key. Keys that exist on both layers (Space, Enter, Shift) do not
  move it.
- Keys that send nothing to the PC (layer keys, Bluetooth, bootloader,
  Studio unlock) never light. Volume keys do not light either (they arrive
  as media keys, not keyboard keys).
- Keymap changes made in ZMK Studio are not seen; the overlay shows the
  keymap from the repo.
- Battery: only over Bluetooth. The right half's level needs the left half
  flashed with this repo's firmware (it passes the level on).

## Unused

`src/`, `Kconfig` and `CMakeLists.txt` are the earlier USB-serial approach
(firmware prints layer changes on the Studio serial port). They are no longer
built (`zephyr/module.yml` does not load them) and can be deleted. Same for
`overlay/CorneStudioRpc.ps1` and `overlay/Test-DeviceKeymap.ps1` (read the
live keymap over the USB Studio connection; the overlay no longer uses them).
