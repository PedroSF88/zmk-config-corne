@echo off
rem Double-click to start the Corne layer overlay (no console window).
start "" powershell.exe -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "%~dp0Start-LayerOverlay.ps1" %*
