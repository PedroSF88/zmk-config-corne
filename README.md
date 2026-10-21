# Now change the keymap using ZMK.studio 
1. Go to zmk.studio
2. plug in left half of the keyboard via USB to computer
3. select USB once at zmk.studio
4. this will open a list of connected devices. Find CorneWireless and connect
5. Unlock keyboard by going to the last layer on your keyboard and use the zmk studio unlock key as shown in the keymap picture.


![IMG_0446](https://github.com/user-attachments/assets/1f24f8bd-588f-4f2e-bc61-a1301dc8450f)

Want an easy way to customize the keymap?  I have a guide https://www.keyboardhoarders.com/post/1288093071901/zmk-change-keymap-walkthrough


![zmkmy_keymap (7)](https://github.com/user-attachments/assets/23712dff-27b2-407d-b222-d315543dbef9)



How to switch bluetooth devices.

![bluetoothpair-guide](https://github.com/user-attachments/assets/d777bf4e-a7e3-4429-8638-2b11e7558153)

## Layer Overlay

[`overlay/`](./overlay) has a small Windows widget that shows the keymap of
the layer the keyboard is on, lights up keys as you type on the Corne, and
shows the left half's battery, over USB or Bluetooth. Double-click
`overlay\Start-Overlay.cmd`. Details and limits:
[`overlay/README.md`](./overlay/README.md).

Layer keys in the keymap are `to_layerN` macros: they switch layer and tap
F13+N so the overlay can follow. Keep that pattern when adding layer keys.

The overlay picks up keymap edits by itself. To regenerate its layout data
by hand:

```powershell
python .\tools\generate_overlay_layout.py
```

## Build and flash

1. Push to GitHub. Actions builds the firmware (about 3 minutes).
2. Download the build (the `firmware\` folder is not committed):

   ```powershell
   gh run download <run id> -D firmware\build-<run id>
   ```

3. Flash both halves from the same build. The script waits for the half,
   checks it is the one you named (only the left firmware contains ZMK
   Studio), copies the file, and confirms the half restarted:

   ```powershell
   powershell -ExecutionPolicy Bypass -File .\tools\Flash-Corne.ps1 -Half left
   powershell -ExecutionPolicy Bypass -File .\tools\Flash-Corne.ps1 -Half right
   ```

   Bootloader mode: plug the half in by USB and double-tap its reset button.
   If the halves stop talking to each other afterwards, flash `-Half reset`
   on both, then the normal firmware again, and re-pair with the PC.
