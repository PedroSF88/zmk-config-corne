# Corne keyboard (zmk-config-corne) -- status

## NOW
Updated: 2026-10-21 -- Claude Opus 4.8 (VS Code)
Goal: a small Windows overlay that shows the Corne's layer, keymap, combos and battery, plus a cleaner keymap. Done.
Stage: Done (flo, 10/21). Both halves on ZMK v0.3; overlay running on this PC. `layer-overlay` merged into `master` on the fork and pushed.
Next step: none. On another Windows PC: clone the repo (now on `master`) or copy the `overlay\` folder, then run `overlay\Start-Overlay.cmd`. Launch on this PC with Ctrl+Alt+C (Start Menu shortcut "Corne Overlay").
Waiting on flo: nothing
Saved: all work committed and pushed to PedroSF88/zmk-config-corne on both `layer-overlay` and `master`, through the status commit
Inbox: empty

## On the keyboard (2026-10-21)

- Left half: Actions build 39659851116 (commit c7b9525): Ctrl and Backspace
  thumbs, layer-signal macros, passes on the right half's battery.
- Right half: Actions build 39653002595 (commit 464f5e5).
- Rollback: the older `.uf2` files in `firmware/` (not committed).
- Flash again with `tools/Flash-Corne.ps1` (steps in the README). Keymap
  changes need only the left half.

## Decisions (flo, 2026-10-21)

- Keep QWERTY letters. Layers stay tap-to-switch (no hold-to-use layers).
  No Spanish accent keys. No key-count logging.
- Thumbs: left Alt/?, Ctrl, Enter; right Space, Backspace, NavNum.
  Combos unchanged (O+P is still Backspace, I+O still one-shot Ctrl).

## Log

- 2026-10-21 -- VS Code, Claude Opus 4.8. Pushed `layer-overlay` and merged it
  into `master` on the fork (fast-forward). Added a Start Menu launch shortcut
  (Ctrl+Alt+C) and documented installing the overlay on another Windows PC.
- 2026-10-21 -- VS Code, Claude Opus 5.5 (built and tested by Claude). Took
  the project out of its April prototype state: layer overlay (layer signals
  over USB and Bluetooth, Corne-only key lighting, layer guess, combos on the
  map, both halves' battery, auto-reload on keymap edits, -SelfTest and
  -BatteryTest), flash helper, keymap fixes; flashed both halves.
