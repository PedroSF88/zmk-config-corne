param(
    [Parameter(Mandatory = $true)]
    [ValidateSet('left', 'right', 'reset')]
    [string]$Half,
    # Folder with the .uf2 files (default: the newest firmware\build-* folder)
    [string]$FirmwareDir,
    [int]$TimeoutMinutes = 30,
    # Skip the left/right check (only for a half whose firmware is broken)
    [switch]$Force
)

# Flash one half of the Corne (nice!nano, no nice!view).
# 1. Waits for the bootloader drive NICENANO. To get it: plug the half in by
#    USB and double-tap its reset button.
# 2. Checks it is the half you asked for: only LEFT firmware contains ZMK
#    Studio, so the drive's CURRENT.UF2 tells left from right.
# 3. Copies the .uf2 and waits for the half to restart (the drive goes away).
# Exit codes: 0 done, 2 wrong half / cannot tell, 3 timed out, 4 not accepted.

$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path $PSScriptRoot -Parent

if (-not $FirmwareDir) {
    $newest = Get-ChildItem (Join-Path $repoRoot 'firmware') -Directory -Filter 'build-*' -ErrorAction SilentlyContinue |
        Sort-Object LastWriteTime -Descending | Select-Object -First 1
    if (-not $newest) { throw 'No firmware\build-* folder. Download a build first (see README).' }
    $FirmwareDir = $newest.FullName
}
$names = @{
    left  = 'corne_left-nice_nano_v2-zmk.uf2'
    right = 'corne_right-nice_nano_v2-zmk.uf2'
    reset = 'settings_reset-nice_nano_v2-zmk.uf2'
}
$file = Get-ChildItem $FirmwareDir -Recurse -Filter $names[$Half] | Select-Object -First 1
if (-not $file) { throw "$($names[$Half]) not found under $FirmwareDir" }
Write-Host "Firmware: $($file.FullName)"

function Get-BootDrive {
    foreach ($drive in [IO.DriveInfo]::GetDrives()) {
        try {
            if ($drive.IsReady -and $drive.VolumeLabel -eq 'NICENANO') { return $drive.RootDirectory.FullName }
        } catch { }
    }
    return $null
}

function Test-HasStudio([string]$uf2Path) {
    # join the UF2 block payloads (so no string is split at a block edge), then search
    $bytes = [IO.File]::ReadAllBytes($uf2Path)
    $payload = New-Object IO.MemoryStream
    for ($i = 0; $i + 512 -le $bytes.Length; $i += 512) {
        $n = [BitConverter]::ToInt32($bytes, $i + 16)
        if ($n -gt 0 -and $n -le 476) { $payload.Write($bytes, $i + 32, $n) }
    }
    return [Text.Encoding]::ASCII.GetString($payload.ToArray()).Contains('zmk_studio')
}

Write-Host "Waiting for the $($Half.ToUpper()) half in bootloader mode: plug it in by USB and double-tap its reset button."
$deadline = (Get-Date).AddMinutes($TimeoutMinutes)
$drive = Get-BootDrive
while (-not $drive) {
    if ((Get-Date) -gt $deadline) {
        Write-Host 'Timed out waiting for the NICENANO drive.'
        exit 3
    }
    Start-Sleep -Milliseconds 500
    $drive = Get-BootDrive
}
Write-Host "Bootloader drive found: $drive"
Start-Sleep -Seconds 1

if ($Half -ne 'reset' -and -not $Force) {
    $current = Join-Path $drive 'CURRENT.UF2'
    if (-not (Test-Path $current)) {
        Write-Host 'No CURRENT.UF2 on the drive, so this cannot tell which half it is. Nothing written.'
        Write-Host 'Press reset once to leave bootloader mode. Re-run with -Force only if you are sure.'
        exit 2
    }
    $actual = if (Test-HasStudio $current) { 'left' } else { 'right' }
    if ($actual -ne $Half) {
        Write-Host "This is the $($actual.ToUpper()) half, not the $($Half.ToUpper()) half. Nothing written."
        Write-Host 'Press reset once to leave bootloader mode, then put the other half in bootloader mode.'
        exit 2
    }
    Write-Host "Check passed: this is the $($Half.ToUpper()) half."
}

$target = Join-Path $drive $file.Name
Write-Host "Copying $($file.Name) ..."
$data = [IO.File]::ReadAllBytes($file.FullName)
try {
    $stream = New-Object IO.FileStream($target, [IO.FileMode]::Create, [IO.FileAccess]::Write, [IO.FileShare]::None, 4096, [IO.FileOptions]::WriteThrough)
    try {
        $stream.Write($data, 0, $data.Length)
        $stream.Flush($true)
    } finally {
        $stream.Dispose()
    }
} catch {
    # The half restarts as soon as it has the whole image, which can cut the
    # copy off at the very end. The drive going away below is the real check.
    Write-Host "(copy ended with: $($_.Exception.Message))"
}

$wait = (Get-Date).AddSeconds(30)
while (Get-BootDrive) {
    if ((Get-Date) -gt $wait) {
        Write-Host 'The drive is still there after 30 s: the half did not take the firmware.'
        exit 4
    }
    Start-Sleep -Milliseconds 500
}
Write-Host "Done: the $($Half.ToUpper()) half restarted with the new firmware."
exit 0
