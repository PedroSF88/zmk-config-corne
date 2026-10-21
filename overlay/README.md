# Corne Layer Overlay

This is a Windows-only first-pass overlay that talks to the left half over USB
serial and redraws a translucent Corne widget.

## Run

```powershell
powershell -ExecutionPolicy Bypass -File .\overlay\Start-LayerOverlay.ps1
```

To test only the live keymap fetch without starting the overlay:

```powershell
powershell -ExecutionPolicy Bypass -File .\overlay\Test-DeviceKeymap.ps1
```

By default the script stays dormant until it detects the left/central Corne USB
serial device and confirms the keyboard name is `CorneWireless2`. On connect it
tries to load the live keymap from the device through ZMK Studio RPC. If Studio
is locked, it keeps using the repo-generated layout and retries every few
seconds after you press your Studio Unlock key. If you want to pin it to a
specific port, pass `-PortName COM4`.

## Layer Change Message Format

The future overlay firmware emits lines like this when the highest active layer
changes:

```text
ZMK_OVERLAY|LAYER|1|NavNum
```

## Notes

- This first version is USB-only.
- It uses the same CDC ACM serial endpoint as the Studio UART transport, so do
  not use it at the same time as ZMK Studio over USB.
- The overlay first tries to load the keymap from the device. The generated
  `overlay/corne-layout.json` file is the fallback when the device is locked or
  unavailable.
- When no matching Corne keyboard is detected, the overlay remains hidden.
- When the keyboard is detected, the overlay opens on the top/default layer and
  then updates only when a layer-change message arrives.
