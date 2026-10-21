param(
    [string]$LayoutPath = (Join-Path $PSScriptRoot 'corne-layout.json'),
    # When this keymap changes, the layout is regenerated and reloaded
    [string]$KeymapPath = (Join-Path (Split-Path $PSScriptRoot -Parent) 'config\corne.keymap'),
    [string]$GeneratorPath = (Join-Path (Split-Path $PSScriptRoot -Parent) 'tools\generate_overlay_layout.py'),
    [ValidateSet('TopLeft', 'TopRight', 'BottomLeft', 'BottomRight')]
    [string]$Anchor = 'BottomRight',
    [double]$OverlayOpacity = 0.9,
    [double]$Scale = 1.0,
    # Keyboard device names that count as the Corne (ZMK's USB and Bluetooth IDs)
    [string]$DevicePattern = 'VID[_&](0[12])?1D50[&_]PID[_&]615E',
    # Light keys from every keyboard instead of only the Corne (no layer guessing)
    [switch]$AllKeyboards,
    # Feed scripted keystrokes through the key handling, print PASS/FAIL, exit
    [switch]$SelfTest
)

# Corne layer overlay.
# - Follows the active layer two ways:
#   1. Signal: the keymap's to_layerN macros tap F13+N on every layer switch.
#      A low-level keyboard hook catches those keys and swallows them, so apps
#      never see them. Works over USB and Bluetooth.
#   2. Guess: a key from the Corne that is not on the shown layer but is on
#      another one switches the overlay to that layer. Covers older firmware
#      and the keyboard waking from sleep (which resets it to Base).
# - Lights up keys: keystrokes from the Corne only (raw input, filtered by
#   device name) are matched to positions on the shown layer, or to a combo.
# Regenerate the layout after keymap edits: python tools/generate_overlay_layout.py

$ErrorActionPreference = 'Stop'

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
Add-Type -TypeDefinition (Get-Content -Raw (Join-Path $PSScriptRoot 'CorneInput.cs')) `
    -ReferencedAssemblies ([System.Windows.Forms.Form].Assembly.Location)

$script:Python = Get-Command python -ErrorAction SilentlyContinue
if (-not $script:Python) { $script:Python = Get-Command py -ErrorAction SilentlyContinue }

function Import-Layout {
    $data = Get-Content -Raw $LayoutPath | ConvertFrom-Json
    if (-not $data.layers -or -not $data.layers[0].keys) {
        throw "Layout file is in the old format. Run: python tools\generate_overlay_layout.py"
    }
    $script:layout = $data
    # vk -> layer index, for the F13+N layer signals
    $script:SignalLayer = @{}
    [CorneHook]::SignalVks.Clear()
    foreach ($signal in $data.signals) {
        $script:SignalLayer[[int]$signal.vk] = [int]$signal.layer
        [void][CorneHook]::SignalVks.Add([int]$signal.vk)
    }
    # layers the keyboard can reach: Base plus every layer-key target
    $script:ReachableLayers = @(@(0) + @($data.signals | ForEach-Object { [int]$_.layer }) | Sort-Object -Unique)
    $script:LayoutStamp = (Get-Item $LayoutPath).LastWriteTimeUtc
}

if (-not (Test-Path $LayoutPath) -and $script:Python -and (Test-Path $KeymapPath) -and (Test-Path $GeneratorPath)) {
    & $script:Python.Source $GeneratorPath $KeymapPath $LayoutPath | Out-Null
}
if (-not (Test-Path $LayoutPath)) {
    throw "Layout file not found: $LayoutPath. Run: python tools\generate_overlay_layout.py"
}
Import-Layout

# ---- look ------------------------------------------------------------------

function New-Color([int]$r, [int]$g, [int]$b, [int]$a = 255) {
    return [System.Drawing.Color]::FromArgb($a, $r, $g, $b)
}

$script:LayerAccents = @(
    (New-Color 88 166 255),   # Base
    (New-Color 63 185 80),    # NavNum
    (New-Color 240 136 62),   # Symbols
    (New-Color 248 81 73),    # System
    (New-Color 188 140 255)   # extra
)
$colorBackground = New-Color 18 22 30
$colorKey = New-Color 36 44 58
$colorKeyEmpty = New-Color 26 31 41
$colorText = New-Color 236 241 250
$colorTextDim = New-Color 120 132 152
$colorTextFaint = New-Color 74 84 102

# Draw at the screen's real resolution (crisp on 150%/200% displays).
[void][CorneHook]::SetProcessDPIAware()
$screenGraphics = [System.Drawing.Graphics]::FromHwnd([IntPtr]::Zero)
$dpiFactor = $screenGraphics.DpiX / 96.0
$screenGraphics.Dispose()

function S([double]$v) { return [float]($v * $Scale * $dpiFactor) }   # pixels
function P([double]$v) { return [float]($v * $Scale) }                # font points

$keyW = S 40
$keyH = S 30
$gap = S 4
$split = S 26
$margin = S 10
$headerH = S 26
# column stagger (Corne: pinky lowest, middle finger highest)
$stagger = @(8, 4, 0, 3, 5, 5, 3, 0, 4, 8) | ForEach-Object { S $_ }

$script:KeyRects = @{}
for ($row = 0; $row -lt 3; $row++) {
    for ($ci = 0; $ci -lt 10; $ci++) {
        $x = $margin + $ci * ($keyW + $gap)
        if ($ci -ge 5) { $x += $split }
        $y = $margin + $headerH + $row * ($keyH + $gap) + $stagger[$ci]
        $pos = $row * 12 + $ci + 1
        $script:KeyRects[$pos] = New-Object System.Drawing.RectangleF($x, $y, $keyW, $keyH)
    }
}
$thumbY = $margin + $headerH + 3 * ($keyH + $gap) + (S 10)
$thumbCols = @(2, 3, 4, 5, 6, 7)
for ($t = 0; $t -lt 6; $t++) {
    $ci = $thumbCols[$t]
    $x = $margin + $ci * ($keyW + $gap)
    if ($ci -ge 5) { $x += $split }
    $script:KeyRects[36 + $t] = New-Object System.Drawing.RectangleF($x, $thumbY, $keyW, $keyH)
}
$formW = [int]($margin * 2 + 10 * $keyW + 9 * $gap + $split)
$formH = [int]($thumbY + $keyH + $margin)

$fontKey = New-Object System.Drawing.Font('Segoe UI Semibold', (P 8.5), [System.Drawing.FontStyle]::Regular, [System.Drawing.GraphicsUnit]::Point)
$fontKeySmall = New-Object System.Drawing.Font('Segoe UI Semibold', (P 6.5), [System.Drawing.FontStyle]::Regular, [System.Drawing.GraphicsUnit]::Point)
$fontSub = New-Object System.Drawing.Font('Segoe UI', (P 6), [System.Drawing.FontStyle]::Regular, [System.Drawing.GraphicsUnit]::Point)
$fontLayer = New-Object System.Drawing.Font('Segoe UI Semibold', (P 11), [System.Drawing.FontStyle]::Regular, [System.Drawing.GraphicsUnit]::Point)
$fontInfo = New-Object System.Drawing.Font('Segoe UI', (P 8.5), [System.Drawing.FontStyle]::Regular, [System.Drawing.GraphicsUnit]::Point)
$centered = New-Object System.Drawing.StringFormat
$centered.Alignment = [System.Drawing.StringAlignment]::Center
$centered.LineAlignment = [System.Drawing.StringAlignment]::Center
$centered.FormatFlags = [System.Drawing.StringFormatFlags]::NoWrap

function Get-FittingFont($g, [string]$text, [float]$width) {
    if ($g.MeasureString($text, $fontKey).Width -le $width - (S 3)) { return $fontKey }
    return $fontKeySmall
}

function New-RoundedPath([System.Drawing.RectangleF]$r, [float]$radius) {
    $d = $radius * 2
    $path = New-Object System.Drawing.Drawing2D.GraphicsPath
    $path.AddArc($r.X, $r.Y, $d, $d, 180, 90)
    $path.AddArc($r.Right - $d, $r.Y, $d, $d, 270, 90)
    $path.AddArc($r.Right - $d, $r.Bottom - $d, $d, $d, 0, 90)
    $path.AddArc($r.X, $r.Bottom - $d, $d, $d, 90, 90)
    $path.CloseFigure()
    return $path
}

# ---- state -----------------------------------------------------------------

$script:Layer = 0
$script:Lit = @{}        # position -> release time (DateTime) or $null while held
$script:Held = @{}       # vk -> @{ Positions; Since }
$script:LastKey = ''
$script:GuessLayers = $false
$script:RawInput = $null
$minGlowMs = 160
$modifierVks = @(0xA0, 0xA1, 0xA2, 0xA3, 0xA4, 0xA5, 0x5B, 0x5C)
$script:InfoUntil = $null          # when the top-right message disappears
$script:NextFileCheck = [DateTime]::UtcNow
$script:Generator = $null          # running layout generator process, if any
$script:GeneratorFor = $null       # keymap timestamp it is generating from
$script:FailedKeymapStamp = $null  # keymap timestamp the generator failed on
$script:GeneratedFor = $null       # keymap timestamp the shown layout was made from
$script:Battery = -1               # left half battery %, -1 = unknown / not on Bluetooth
$script:BatteryMac = $null         # the Corne's Bluetooth address, from its raw input name
$script:BatteryWarned = 100        # lowest threshold already warned about
$script:NextBatteryCheck = [DateTime]::UtcNow
if ((Test-Path $KeymapPath) -and (Get-Item $KeymapPath).LastWriteTimeUtc -le $script:LayoutStamp) {
    $script:GeneratedFor = (Get-Item $KeymapPath).LastWriteTimeUtc   # layout already up to date
}

function Get-LayerData([int]$index) {
    $match = $layout.layers | Where-Object { [int]$_.index -eq $index } | Select-Object -First 1
    if ($match) { return $match }
    return $layout.layers[0]
}

function Find-Positions([int]$vk, [bool]$shift) {
    $keys = (Get-LayerData $script:Layer).keys
    $exact = New-Object System.Collections.ArrayList
    $loose = New-Object System.Collections.ArrayList
    for ($pos = 0; $pos -lt $keys.Count; $pos++) {
        foreach ($entry in $keys[$pos].vks) {
            if ([int]$entry.vk -ne $vk) { continue }
            if ([bool]$entry.shift -eq $shift) { [void]$exact.Add($pos) } else { [void]$loose.Add($pos) }
        }
    }
    if ($exact.Count -gt 0) { return [pscustomobject]@{ Positions = @($exact); Label = '' } }
    if ($loose.Count -gt 0) { return [pscustomobject]@{ Positions = @($loose); Label = '' } }

    foreach ($combo in $layout.combos) {
        if ($combo.layers -and -not ($combo.layers -contains $script:Layer)) { continue }
        foreach ($entry in $combo.vks) {
            if ([int]$entry.vk -eq $vk) {
                return [pscustomobject]@{ Positions = @($combo.positions | ForEach-Object { [int]$_ }); Label = "$($combo.label) (combo)" }
            }
        }
    }
    return [pscustomobject]@{ Positions = @(); Label = '' }
}

function Test-LayerHasKey([int]$index, [int]$vk, [bool]$shift, [bool]$exact) {
    foreach ($key in (Get-LayerData $index).keys) {
        foreach ($entry in $key.vks) {
            if ([int]$entry.vk -eq $vk -and (-not $exact -or [bool]$entry.shift -eq $shift)) { return $true }
        }
    }
    foreach ($combo in $layout.combos) {
        if ($combo.layers -and -not ($combo.layers -contains $index)) { continue }
        foreach ($entry in $combo.vks) {
            if ([int]$entry.vk -eq $vk) { return $true }
        }
    }
    return $false
}

function Set-Layer([int]$index) {
    $script:Layer = $index
    $script:Lit.Clear()
    $script:Held.Clear()
    $script:LastKey = ''
}

function Show-Info([string]$text, [int]$seconds = 4) {
    $script:LastKey = $text
    $script:InfoUntil = [DateTime]::UtcNow.AddSeconds($seconds)
}

# Keymap file edited -> regenerate the layout in a separate process (so the
# keyboard hook on this thread is never held up) -> reload it.
# Returns $true when the overlay must redraw.
function Update-LayoutFromFiles {
    $now = [DateTime]::UtcNow
    if ($now -lt $script:NextFileCheck) { return $false }
    $script:NextFileCheck = $now.AddMilliseconds(1000)

    # 1. generator running: wait for it, then load what it wrote right away
    if ($script:Generator) {
        if (-not $script:Generator.HasExited) { return $false }
        $code = $script:Generator.ExitCode
        $errorText = $script:Generator.StandardError.ReadToEnd()
        $script:Generator.Dispose()
        $script:Generator = $null
        if ($code -ne 0) {
            # keep showing the last good layout; retry when the keymap changes again
            $script:FailedKeymapStamp = $script:GeneratorFor
            $lastLine = @($errorText -split "`r?`n" | Where-Object { $_ -match '\S' } | Select-Object -Last 1)
            Show-Info ('keymap error: ' + (($lastLine -join '') -replace '^\w+Error: ', '')) 20
            return $true
        }
        $script:GeneratedFor = $script:GeneratorFor
        return (Update-OverlayLayout)
    }

    # 2. keymap saved since the last generation: regenerate
    if ($script:Python -and (Test-Path $KeymapPath) -and (Test-Path $GeneratorPath)) {
        $keymapStamp = (Get-Item $KeymapPath).LastWriteTimeUtc
        if ($keymapStamp -ne $script:GeneratedFor -and $keymapStamp -ne $script:FailedKeymapStamp) {
            $start = New-Object System.Diagnostics.ProcessStartInfo
            $start.FileName = $script:Python.Source
            $start.Arguments = '"{0}" "{1}" "{2}"' -f $GeneratorPath, $KeymapPath, $LayoutPath
            $start.UseShellExecute = $false
            $start.CreateNoWindow = $true
            $start.RedirectStandardError = $true
            $start.RedirectStandardOutput = $true
            $script:GeneratorFor = $keymapStamp
            $script:Generator = [System.Diagnostics.Process]::Start($start)
            return $false
        }
    }

    # 3. layout file replaced some other way (generator run by hand): reload
    if ((Test-Path $LayoutPath) -and (Get-Item $LayoutPath).LastWriteTimeUtc -ne $script:LayoutStamp) {
        return (Update-OverlayLayout)
    }
    return $false
}

# Battery of the left (central) half, as Windows reports it over Bluetooth.
# Checked once a minute; warns in the tray at 20% and again at 10%.
# Returns $true when the overlay must redraw.
function Update-Battery {
    $now = [DateTime]::UtcNow
    if ($now -lt $script:NextBatteryCheck) { return $false }
    $script:NextBatteryCheck = $now.AddSeconds(60)

    if (-not $script:BatteryMac) {
        foreach ($name in [CorneRawInput]::KeyboardNames()) {
            if ($name -match $DevicePattern -and $name -match '_([0-9a-f]{12})&col') {
                $script:BatteryMac = $Matches[1]
                break
            }
        }
    }
    $level = [CorneBattery]::Read($script:BatteryMac)
    if ($level -eq $script:Battery) { return $false }
    $script:Battery = $level

    $tray.Text = if ($level -ge 0) { "Corne overlay - left half battery $level%" } else { 'Corne layer overlay' }
    foreach ($threshold in @(10, 20)) {
        if ($level -ge 0 -and $level -le $threshold -and $script:BatteryWarned -gt $threshold) {
            $script:BatteryWarned = $threshold
            $tray.ShowBalloonTip(8000, 'Corne battery low', "Left half at $level%. Plug it in to charge.", [System.Windows.Forms.ToolTipIcon]::Warning)
            break
        }
    }
    if ($level -gt $script:BatteryWarned + 5) { $script:BatteryWarned = 100 }   # charged again: re-arm
    return $true
}

function Update-OverlayLayout {
    try {
        Import-Layout
    } catch {
        return $false   # unreadable right now: try again on the next check
    }
    Set-Layer $(if ($script:Layer -lt @($script:layout.layers).Count) { $script:Layer } else { 0 })
    Show-Info 'keymap updated'
    return $true
}

# A key the shown layer cannot send means the keyboard is on another layer:
# switch to the first reachable layer that has it (exact Shift match first).
function Update-LayerGuess([int]$vk, [bool]$shift) {
    if (-not $script:GuessLayers -or $modifierVks -contains $vk) { return }
    if (Test-LayerHasKey $script:Layer $vk $shift $false) { return }
    foreach ($exact in @($true, $false)) {
        foreach ($index in $script:ReachableLayers) {
            if ($index -eq $script:Layer) { continue }
            if (Test-LayerHasKey $index $vk $shift $exact) {
                Set-Layer $index
                return
            }
        }
    }
}

function Process-Events {
    $changed = $false
    $keyEvent = New-Object CorneKeyEvent
    $shiftPositions = $null
    while ([CorneHook]::Events.TryDequeue([ref]$keyEvent)) {
        $vk = $keyEvent.Vk
        if ($keyEvent.Signal) {
            if ($keyEvent.Down) { Set-Layer $script:SignalLayer[$vk] }
            $changed = $true
            continue
        }

        if ($keyEvent.Down) {
            if ($script:Held.ContainsKey($vk)) { continue }   # auto-repeat
            Update-LayerGuess $vk $keyEvent.Shift
            $found = Find-Positions $vk $keyEvent.Shift
            $script:Held[$vk] = @{ Positions = $found.Positions; Since = [DateTime]::UtcNow }
            foreach ($pos in $found.Positions) { $script:Lit[$pos] = $null }
            if ($found.Label) { Show-Info $found.Label }

            if ($vk -eq 0xA0 -or $vk -eq 0xA1) {
                $shiftPositions = $found.Positions
            } elseif ($keyEvent.Shift -and $shiftPositions) {
                # Shift sent by the keyboard together with a symbol key
                # (e.g. '@' on Symbols): only the symbol key should light.
                foreach ($pos in $shiftPositions) { [void]$script:Lit.Remove($pos) }
                $shiftPositions = $null
            }
            $changed = $true
        } else {
            if ($script:Held.ContainsKey($vk)) {
                $held = $script:Held[$vk]
                $release = $held.Since.AddMilliseconds($minGlowMs)
                if ($release -lt [DateTime]::UtcNow) { $release = [DateTime]::UtcNow }
                foreach ($pos in $held.Positions) {
                    if ($script:Lit.ContainsKey($pos)) { $script:Lit[$pos] = $release }
                }
                $script:Held.Remove($vk)
                $changed = $true
            }
        }
    }

    $now = [DateTime]::UtcNow
    foreach ($pos in @($script:Lit.Keys)) {
        $release = $script:Lit[$pos]
        if ($release -and $release -le $now) {
            $script:Lit.Remove($pos)
            $changed = $true
        }
    }
    if ($script:InfoUntil -and $now -ge $script:InfoUntil) {
        $script:InfoUntil = $null
        $script:LastKey = ''
        $changed = $true
    }
    return $changed
}

# ---- self-test -------------------------------------------------------------

if ($SelfTest) {
    # Each step: keystrokes as "vk" or "+vk" (with Shift held) or "!vk"
    # (layer signal), then the expected layer and lit positions after the
    # key-downs. Positions: row * 12 + column, thumbs 36-41.
    function Invoke-Step([string[]]$keys) {
        foreach ($phase in @($true, $false)) {
            $order = if ($phase) { $keys } else { $keys[($keys.Count - 1)..0] }
            foreach ($k in $order) {
                $ev = New-Object CorneKeyEvent
                $ev.Signal = $k.StartsWith('!')
                $ev.Shift = $k.StartsWith('+')
                $ev.Vk = [Convert]::ToInt32($k.TrimStart('!', '+'), 16)
                $ev.Down = $phase
                [CorneHook]::Events.Enqueue($ev)
            }
            [void](Process-Events)
            if ($phase) {
                $script:SeenLit = (@($script:Lit.Keys | Sort-Object) -join ',')
                $script:SeenLayer = [string](Get-LayerData $script:Layer).name
                $script:SeenInfo = $script:LastKey
            }
        }
        Start-Sleep -Milliseconds ($minGlowMs + 20)
        [void](Process-Events)
    }

    $steps = @(
        @{ Name = 'Q on Base';                      Keys = @('51');           Layer = 'Base';    Lit = '1' },
        @{ Name = '7 -> guess NavNum';              Keys = @('37');           Layer = 'NavNum';  Lit = '7' },
        @{ Name = 'Space on NavNum stays (trans)';  Keys = @('20');           Layer = 'NavNum';  Lit = '39,40' },
        @{ Name = 'Q -> guess Base';                Keys = @('51');           Layer = 'Base';    Lit = '1' },
        @{ Name = 'Shift+2 (@) -> guess Symbols';   Keys = @('A0', '+32');    Layer = 'Symbols'; Lit = '6' },
        @{ Name = 'signal F13 -> Base';             Keys = @('!7C');          Layer = 'Base';    Lit = '' },
        @{ Name = 'Backspace combo stays on Base';  Keys = @('08');           Layer = 'Base';    Lit = '9,10' },
        @{ Name = 'dash combo stays on Base';       Keys = @('BD');           Layer = 'Base';    Lit = '19,20' },
        @{ Name = 'signal F16 -> System';           Keys = @('!7F');          Layer = 'System';  Lit = '' },
        @{ Name = 'F1 on System stays';             Keys = @('70');           Layer = 'System';  Lit = '6' },
        @{ Name = 'Shift alone lights Shift';       Keys = @('A1');           Layer = 'System';  Lit = '34' }
    )

    $failed = 0
    $script:GuessLayers = $true
    Set-Layer 0
    foreach ($step in $steps) {
        Invoke-Step $step.Keys
        $ok = ($script:SeenLayer -eq $step.Layer) -and ($script:SeenLit -eq $step.Lit)
        if (-not $ok) { $failed++ }
        '{0}  {1,-32} layer={2,-8} lit=[{3}] {4}' -f $(if ($ok) { 'PASS' } else { 'FAIL' }), $step.Name, $script:SeenLayer, $script:SeenLit, $script:SeenInfo
    }

    # Baseline: with guessing off, the same '7' must NOT move the overlay.
    $script:GuessLayers = $false
    Set-Layer 0
    Invoke-Step @('37')
    $ok = ($script:SeenLayer -eq 'Base') -and ($script:SeenLit -eq '')
    if (-not $ok) { $failed++ }
    '{0}  {1,-32} layer={2,-8} lit=[{3}]' -f $(if ($ok) { 'PASS' } else { 'FAIL' }), 'baseline: no guess, 7 stays Base', $script:SeenLayer, $script:SeenLit

    "$failed failed"
    exit $failed
}

# ---- window ----------------------------------------------------------------

$mutex = New-Object System.Threading.Mutex($false, 'Local\CorneLayerOverlay')
if (-not $mutex.WaitOne(0)) {
    Write-Host 'Corne overlay is already running (see the tray icon).'
    exit 0
}

$form = New-Object System.Windows.Forms.Form
$form.Text = 'Corne Layer Overlay'
$form.FormBorderStyle = [System.Windows.Forms.FormBorderStyle]::None
$form.StartPosition = [System.Windows.Forms.FormStartPosition]::Manual
$form.TopMost = $true
$form.ShowInTaskbar = $false
$form.BackColor = $colorBackground
$form.ClientSize = New-Object System.Drawing.Size($formW, $formH)
$form.GetType().GetProperty('DoubleBuffered', [Reflection.BindingFlags]'NonPublic,Instance').SetValue($form, $true, $null)

$script:Anchor = $Anchor
function Set-OverlayPosition([string]$corner) {
    $script:Anchor = $corner
    $area = [System.Windows.Forms.Screen]::PrimaryScreen.WorkingArea
    $m = 16
    $x = if ($corner -like '*Left') { $area.Left + $m } else { $area.Right - $form.Width - $m }
    $y = if ($corner -like 'Top*') { $area.Top + $m } else { $area.Bottom - $form.Height - $m }
    $form.Location = New-Object System.Drawing.Point($x, $y)
}
Set-OverlayPosition $Anchor

$form.Add_Paint({
        param($sender, $e)
        $g = $e.Graphics
        $g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
        $g.TextRenderingHint = [System.Drawing.Text.TextRenderingHint]::ClearTypeGridFit

        $layer = Get-LayerData $script:Layer
        $accent = $script:LayerAccents[[Math]::Min($script:Layer, $script:LayerAccents.Count - 1)]

        $accentBrush = New-Object System.Drawing.SolidBrush($accent)
        $g.FillEllipse($accentBrush, $margin, $margin + (S 7), (S 10), (S 10))
        $g.DrawString([string]$layer.name, $fontLayer, $accentBrush, $margin + (S 14), $margin + (S 1))
        $infoRight = $formW - $margin
        if ($script:Battery -ge 0) {
            # "L [###] 88%" at the right end of the header: left half battery
            $level = $script:Battery
            $batteryColor = if ($level -lt 20) { $script:LayerAccents[3] } elseif ($level -lt 50) { New-Color 230 180 60 } else { $script:LayerAccents[1] }
            $batteryBrush = New-Object System.Drawing.SolidBrush($batteryColor)
            $labelBrush = New-Object System.Drawing.SolidBrush($colorTextDim)
            $outline = New-Object System.Drawing.Pen($colorTextDim, [float](S 1))
            $text = "$level%"
            $textW = $g.MeasureString($text, $fontInfo).Width
            $textX = $formW - $margin - $textW
            $g.DrawString($text, $fontInfo, $labelBrush, $textX, $margin + (S 4))
            $bw = S 18; $bh = S 9
            $bx = $textX - (S 3) - (S 2) - $bw
            $by = $margin + (S 9)
            $g.DrawRectangle($outline, $bx, $by, $bw, $bh)
            $g.FillRectangle($labelBrush, ($bx + $bw), ($by + $bh * 0.3), (S 2), ($bh * 0.4))
            $g.FillRectangle($batteryBrush, ($bx + (S 1.5)), ($by + (S 1.5)), [float][Math]::Max(1, ($bw - (S 3)) * $level / 100), ($bh - (S 3)))
            $lw = $g.MeasureString('L', $fontInfo).Width
            $g.DrawString('L', $fontInfo, $labelBrush, ($bx - (S 2) - $lw), $margin + (S 4))
            $infoRight = $bx - (S 2) - $lw - (S 10)
            $batteryBrush.Dispose(); $labelBrush.Dispose(); $outline.Dispose()
        }

        if ($script:LastKey) {
            # right-aligned between the layer name and the battery, cut with "..."
            $infoBrush = New-Object System.Drawing.SolidBrush($colorTextDim)
            $left = $margin + (S 14) + $g.MeasureString([string]$layer.name, $fontLayer).Width + (S 10)
            $infoRect = New-Object System.Drawing.RectangleF($left, ($margin + (S 4)), ($infoRight - $left), (S 18))
            $infoFormat = New-Object System.Drawing.StringFormat
            $infoFormat.Alignment = [System.Drawing.StringAlignment]::Far
            $infoFormat.Trimming = [System.Drawing.StringTrimming]::EllipsisCharacter
            $infoFormat.FormatFlags = [System.Drawing.StringFormatFlags]::NoWrap
            $g.DrawString($script:LastKey, $fontInfo, $infoBrush, $infoRect, $infoFormat)
            $infoFormat.Dispose()
            $infoBrush.Dispose()
        }

        $litFill = New-Object System.Drawing.SolidBrush($accent)
        $keyFill = New-Object System.Drawing.SolidBrush($colorKey)
        $emptyFill = New-Object System.Drawing.SolidBrush($colorKeyEmpty)
        $textBrush = New-Object System.Drawing.SolidBrush($colorText)
        $dimBrush = New-Object System.Drawing.SolidBrush($colorTextDim)
        $faintBrush = New-Object System.Drawing.SolidBrush($colorTextFaint)
        $darkBrush = New-Object System.Drawing.SolidBrush($colorBackground)

        foreach ($pos in $script:KeyRects.Keys) {
            $rect = $script:KeyRects[$pos]
            $key = $layer.keys[$pos]
            $isLit = $script:Lit.ContainsKey($pos)
            $path = New-RoundedPath $rect (S 5)

            if ($isLit) { $fill = $litFill }
            elseif ($key.kind -eq 'none') { $fill = $emptyFill }
            else { $fill = $keyFill }
            $g.FillPath($fill, $path)
            $path.Dispose()

            if ($isLit) { $brush = $darkBrush }
            elseif ($key.kind -eq 'trans') { $brush = $faintBrush }
            elseif ($key.kind -eq 'layer') { $brush = $accentBrush }
            elseif ($key.kind -eq 'system') { $brush = $dimBrush }
            else { $brush = $textBrush }

            if ($key.sub) {
                $top = New-Object System.Drawing.RectangleF($rect.X, $rect.Y, $rect.Width, ($rect.Height * 0.68))
                $bottom = New-Object System.Drawing.RectangleF($rect.X, ($rect.Y + $rect.Height * 0.56), $rect.Width, ($rect.Height * 0.44))
                $g.DrawString([string]$key.label, (Get-FittingFont $g ([string]$key.label) $rect.Width), $brush, $top, $centered)
                $g.DrawString([string]$key.sub, $fontSub, $(if ($isLit) { $darkBrush } else { $dimBrush }), $bottom, $centered)
            } else {
                $g.DrawString([string]$key.label, (Get-FittingFont $g ([string]$key.label) $rect.Width), $brush, $rect, $centered)
            }
        }

        foreach ($b in @($accentBrush, $litFill, $keyFill, $emptyFill, $textBrush, $dimBrush, $faintBrush, $darkBrush)) { $b.Dispose() }
    })

# ---- tray ------------------------------------------------------------------

$iconBitmap = New-Object System.Drawing.Bitmap(32, 32)
$ig = [System.Drawing.Graphics]::FromImage($iconBitmap)
$ig.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
$ig.Clear([System.Drawing.Color]::Transparent)
$iconBrush = New-Object System.Drawing.SolidBrush($script:LayerAccents[0])
foreach ($ix in @(2, 12, 22)) {
    $ig.FillRectangle($iconBrush, $ix, 6, 8, 8)
    $ig.FillRectangle($iconBrush, $ix, 18, 8, 8)
}
$ig.Dispose()

$tray = New-Object System.Windows.Forms.NotifyIcon
$tray.Icon = [System.Drawing.Icon]::FromHandle($iconBitmap.GetHicon())
$tray.Text = 'Corne layer overlay'
$menu = New-Object System.Windows.Forms.ContextMenuStrip

$modeItem = $menu.Items.Add('Lights keys from: Corne only')
$modeItem.Enabled = $false
[void]$menu.Items.Add('-')

$toggleItem = $menu.Items.Add('Hide overlay')
$toggleItem.Add_Click({
        if ($form.Visible) { $form.Hide(); $toggleItem.Text = 'Show overlay' }
        else { $form.Show(); $toggleItem.Text = 'Hide overlay' }
    })
$tray.Add_DoubleClick({ $toggleItem.PerformClick() })

$cornerMenu = New-Object System.Windows.Forms.ToolStripMenuItem('Corner')
foreach ($corner in @('TopLeft', 'TopRight', 'BottomLeft', 'BottomRight')) {
    $item = $cornerMenu.DropDownItems.Add($corner)
    $item.Tag = $corner
    $item.Add_Click({ param($s, $a) Set-OverlayPosition ([string]$s.Tag) })
}
[void]$menu.Items.Add($cornerMenu)

$resetItem = $menu.Items.Add('Reset to Base layer')
$resetItem.Add_Click({ Set-Layer 0; $form.Invalidate() })

[void]$menu.Items.Add('-')
$exitItem = $menu.Items.Add('Exit')
$exitItem.Add_Click({ $form.Close() })
$tray.ContextMenuStrip = $menu
$tray.Visible = $true

# ---- run -------------------------------------------------------------------

$timer = New-Object System.Windows.Forms.Timer
$timer.Interval = 30
$timer.Add_Tick({
        try {
            $redraw = Process-Events
            if (Update-LayoutFromFiles) { $redraw = $true }
            if (Update-Battery) { $redraw = $true }
            if ($redraw) { $form.Invalidate() }
        } catch {
            $script:LastKey = 'error: ' + $_.Exception.Message
            $form.Invalidate()
        }
    })

$form.Add_Shown({
        [CorneHook]::MakeOverlayWindow($form.Handle, $OverlayOpacity)
        # Launched with -WindowStyle Hidden, Windows hides the first window the
        # process shows; showing it a second time makes it visible.
        $form.Hide()
        $form.Show()
        if (-not [CorneHook]::Start()) {
            $script:LastKey = 'keyboard hook failed'
        }
        if ($AllKeyboards) {
            [CorneHook]::AllKeys = $true
            $modeItem.Text = 'Lights keys from: all keyboards'
        } else {
            try {
                $script:RawInput = [CorneRawInput]::new($DevicePattern)
                $script:GuessLayers = $true
            } catch {
                [CorneHook]::AllKeys = $true
                $modeItem.Text = 'Lights keys from: all keyboards'
                $script:LastKey = 'Corne filter failed: ' + $_.Exception.Message
            }
        }
        $timer.Start()
    })

$form.Add_FormClosed({
        $timer.Stop()
        [CorneHook]::Stop()
        if ($script:RawInput) { $script:RawInput.Dispose() }
        $tray.Visible = $false
        $tray.Dispose()
    })

try {
    [System.Windows.Forms.Application]::Run($form)
} finally {
    [CorneHook]::Stop()
    $mutex.ReleaseMutex()
}
