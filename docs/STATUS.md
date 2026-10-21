# Corne keyboard (zmk-config-corne) -- status

## NOW
Updated: 2026-10-21 -- Claude Opus 5.5 (VS Code)
Goal: a small Windows overlay that shows the Corne's layer, keymap, combos and battery, plus a cleaner keymap. Done.
Stage: Done (flo, 10/21). Both halves on ZMK v0.3; overlay running on this PC.
Next step: none required. Optional: merge `layer-overlay` into `master` on GitHub so edits made there start from this keymap -- who: flo (OK), then claude
Waiting on flo: OK to merge `layer-overlay` -> `master` and push
Saved: all work committed on `layer-overlay` and pushed to PedroSF88/zmk-config-corne, except this status commit (local); `master` not updated
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

- 2026-10-21 -- VS Code, Claude Opus 5.5 (built and tested by Claude). Took
  the project out of its April prototype state: layer overlay (layer signals
  over USB and Bluetooth, Corne-only key lighting, layer guess, combos on the
  map, both halves' battery, auto-reload on keymap edits, -SelfTest and
  -BatteryTest), flash helper, keymap fixes; flashed both halves.
