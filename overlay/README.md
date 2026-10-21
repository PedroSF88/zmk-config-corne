# Corne Layer Overlay

A small always-on-top widget (Windows) that shows the Corne keymap for the
layer the keyboard is on, and lights up keys as you press them. Works over
USB and Bluetooth. Click-through: it never takes focus or blocks the mouse.

## Run

Double-click `Start-Overlay.cmd`, or:

```powershell
powershell -ExecutionPolicy Bypass -File .\overlay\Start-LayerOverlay.ps1
```

Options: `-Anchor TopLeft|TopRight|BottomLeft|BottomRight` (default
BottomRight), `-Scale 1.2`, `-OverlayOpacity 0.8`.

Tray icon (right-click): hide/show, move to another corner, reset to Base,
exit. Double-click the tray icon to hide/show. Only one copy runs at a time.

To start it with Windows: press Win+R, type `shell:startup`, and put a
shortcut to `Start-Overlay.cmd` in that folder.

## How it works

- Layer tracking: every layer key in `config/corne.keymap` is a `to_layerN`
  macro that switches layer and taps F13+N (F13 = Base ... F16 = System).
  The overlay catches F13-F16 with a low-level keyboard hook and swallows
  them, so other apps never see them. This needs the firmware built from this
  keymap on the LEFT half.
- Key lighting: every keystroke Windows receives is matched to its position
  on the current layer (Shift-aware, so `=` and `+` light different keys).
  A keystroke that no key on the layer sends is matched to a combo, and the
  combo's keys light up with its name in the top-right corner.
- Everything it draws comes from `corne-layout.json`. After editing the
  keymap, regenerate it: `python tools\generate_overlay_layout.py`.

## Limits

- The overlay starts on Base. If the keyboard is on another layer when the
  overlay starts, or the keyboard wakes from deep sleep (which resets it to
  Base), the overlay is in sync again after the next layer key. Tray ->
  "Reset to Base" also fixes it.
- Key lighting comes from what Windows receives, so the laptop's own
  keyboard lights keys too, and keys that send nothing to the PC (Bluetooth,
  bootloader, Studio unlock) never light.
- Keymap changes made in ZMK Studio are not seen; the overlay shows the
  keymap from the repo.

## Unused

`src/`, `Kconfig` and `CMakeLists.txt` are the earlier USB-serial approach
(firmware prints layer changes on the Studio serial port). They are no longer
built (`zephyr/module.yml` does not load them) and can be deleted. Same for
`overlay/CorneStudioRpc.ps1` and `overlay/Test-DeviceKeymap.ps1` (read the
live keymap over the USB Studio connection; the overlay no longer uses them).
