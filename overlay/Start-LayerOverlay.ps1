param(
    [string]$PortName,
    [string]$LayoutPath = (Join-Path $PSScriptRoot 'corne-layout.json'),
    [ValidateSet('TopLeft', 'TopRight', 'BottomLeft', 'BottomRight')]
    [string]$Anchor = 'TopRight',
    [double]$OverlayOpacity = 0.86,
    [string]$KeyboardName = 'CorneWireless2'
)

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

$studioRpcPath = Join-Path $PSScriptRoot 'CorneStudioRpc.ps1'
if (Test-Path $studioRpcPath) {
    . $studioRpcPath
}

Add-Type @"
using System;
using System.Runtime.InteropServices;

public static class CorneOverlayNative {
    [DllImport("user32.dll")]
    public static extern int GetWindowLong(IntPtr hWnd, int nIndex);

    [DllImport("user32.dll")]
    public static extern int SetWindowLong(IntPtr hWnd, int nIndex, int dwNewLong);

    public const int GWL_EXSTYLE = -20;
    public const int WS_EX_LAYERED = 0x00080000;
    public const int WS_EX_TRANSPARENT = 0x00000020;
    public const int WS_EX_TOOLWINDOW = 0x00000080;
    public const int WS_EX_NOACTIVATE = 0x08000000;
}
"@

function Get-ActiveSerialPorts {
    return @(
        (Get-ItemProperty 'HKLM:\HARDWARE\DEVICEMAP\SERIALCOMM').PSObject.Properties |
            Where-Object { $_.Name -notlike 'PS*' } |
            ForEach-Object { $_.Value } |
            Sort-Object -Unique
    )
}

function Test-CorneKeyboardPresent {
    param([string]$ExpectedKeyboardName)

    $matches = @(
        Get-ChildItem 'HKLM:\SYSTEM\CurrentControlSet\Enum\USB\VID_1D50&PID_615E' -ErrorAction SilentlyContinue |
            ForEach-Object {
                $deviceInfo = Get-ItemProperty $_.PSPath -ErrorAction SilentlyContinue
                if ($deviceInfo.DeviceDesc -eq $ExpectedKeyboardName) {
                    $true
                }
            }
    )

    return $matches.Count -gt 0
}

function Get-CornePortNames {
    param([string]$ExpectedKeyboardName)

    if (-not (Test-CorneKeyboardPresent -ExpectedKeyboardName $ExpectedKeyboardName)) {
        return @()
    }

    $activePorts = Get-ActiveSerialPorts
    $registeredCornePorts = @(
        Get-ChildItem 'HKLM:\SYSTEM\CurrentControlSet\Enum\USB\VID_1D50&PID_615E&MI_00' -ErrorAction SilentlyContinue |
            ForEach-Object {
                $deviceParamsPath = Join-Path $_.PSPath 'Device Parameters'
                $deviceParams = Get-ItemProperty $deviceParamsPath -ErrorAction SilentlyContinue
                if ($deviceParams.PortName) {
                    $deviceParams.PortName
                }
            } |
            Sort-Object -Unique
    )

    return @($registeredCornePorts | Where-Object { $_ -in $activePorts })
}

function Resolve-TargetPort {
    param(
        [string]$ExplicitPortName,
        [string]$ExpectedKeyboardName
    )

    if ($ExplicitPortName) {
        return $ExplicitPortName
    }

    $cornePorts = Get-CornePortNames -ExpectedKeyboardName $ExpectedKeyboardName
    if ($cornePorts.Count -gt 0) {
        return $cornePorts[0]
    }

    return $null
}

function Get-LayerByIndex {
    param(
        [object]$Layout,
        [int]$LayerIndex
    )

    $matched = $Layout.layers | Where-Object { [int]$_.index -eq $LayerIndex } | Select-Object -First 1
    if ($matched) {
        return $matched
    }

    return $Layout.layers | Select-Object -First 1
}

function Set-ClickThrough {
    param([System.Windows.Forms.Form]$Form)

    $styles = [CorneOverlayNative]::GetWindowLong($Form.Handle, [CorneOverlayNative]::GWL_EXSTYLE)
    $styles = $styles -bor [CorneOverlayNative]::WS_EX_LAYERED
    $styles = $styles -bor [CorneOverlayNative]::WS_EX_TRANSPARENT
    $styles = $styles -bor [CorneOverlayNative]::WS_EX_TOOLWINDOW
    $styles = $styles -bor [CorneOverlayNative]::WS_EX_NOACTIVATE
    [CorneOverlayNative]::SetWindowLong($Form.Handle, [CorneOverlayNative]::GWL_EXSTYLE, $styles) | Out-Null
}

if (-not (Test-Path $LayoutPath)) {
    throw "Layout file not found: $LayoutPath"
}

$layout = Get-Content -Raw $LayoutPath | ConvertFrom-Json
$script:OverlayLayout = $layout
$resolvedPortName = Resolve-TargetPort -ExplicitPortName $PortName -ExpectedKeyboardName $KeyboardName

$form = New-Object System.Windows.Forms.Form
$form.Text = 'Corne Layer Overlay'
$form.FormBorderStyle = [System.Windows.Forms.FormBorderStyle]::None
$form.StartPosition = [System.Windows.Forms.FormStartPosition]::Manual
$form.TopMost = $true
$form.ShowInTaskbar = $false
$form.Opacity = $OverlayOpacity
$form.BackColor = [System.Drawing.Color]::FromArgb(20, 24, 32)
$form.ClientSize = New-Object System.Drawing.Size(840, 320)

$screenBounds = [System.Windows.Forms.Screen]::PrimaryScreen.WorkingArea
$margin = 18
switch ($Anchor) {
    'TopLeft' {
        $form.Location = New-Object System.Drawing.Point($screenBounds.Left + $margin, $screenBounds.Top + $margin)
    }
    'TopRight' {
        $form.Location = New-Object System.Drawing.Point($screenBounds.Right - $form.Width - $margin, $screenBounds.Top + $margin)
    }
    'BottomLeft' {
        $form.Location = New-Object System.Drawing.Point($screenBounds.Left + $margin, $screenBounds.Bottom - $form.Height - $margin)
    }
    'BottomRight' {
        $form.Location = New-Object System.Drawing.Point($screenBounds.Right - $form.Width - $margin, $screenBounds.Bottom - $form.Height - $margin)
    }
}

$headerLabel = New-Object System.Windows.Forms.Label
$headerLabel.Text = 'Corne'
$headerLabel.ForeColor = [System.Drawing.Color]::FromArgb(238, 243, 255)
$headerLabel.Font = New-Object System.Drawing.Font('Segoe UI Semibold', 18, [System.Drawing.FontStyle]::Bold)
$headerLabel.Location = New-Object System.Drawing.Point(20, 16)
$headerLabel.AutoSize = $true
$form.Controls.Add($headerLabel)

$statusLabel = New-Object System.Windows.Forms.Label
$statusLabel.Text = if ($resolvedPortName) { "Waiting for $KeyboardName on $resolvedPortName" } else { "No $KeyboardName keyboard detected" }
$statusLabel.ForeColor = [System.Drawing.Color]::FromArgb(160, 176, 204)
$statusLabel.Font = New-Object System.Drawing.Font('Segoe UI', 9)
$statusLabel.Location = New-Object System.Drawing.Point(24, 48)
$statusLabel.AutoSize = $true
$form.Controls.Add($statusLabel)

$layerLabel = New-Object System.Windows.Forms.Label
$layerLabel.Text = 'Base'
$layerLabel.ForeColor = [System.Drawing.Color]::FromArgb(120, 214, 255)
$layerLabel.Font = New-Object System.Drawing.Font('Segoe UI Semibold', 16)
$layerLabel.Location = New-Object System.Drawing.Point(720, 18)
$layerLabel.AutoSize = $true
$form.Controls.Add($layerLabel)

$panels = New-Object System.Collections.Generic.List[object]
$rowTop = @(82, 132, 182)
$thumbTop = 248
$keyWidth = 56
$keyHeight = 38
$gap = 6
$rowStartX = 20
$thumbPositions = @(214, 276, 338, 400, 462, 524)

for ($rowIndex = 0; $rowIndex -lt 3; $rowIndex++) {
    for ($columnIndex = 0; $columnIndex -lt 12; $columnIndex++) {
        $panel = New-Object System.Windows.Forms.Panel
        $panel.Size = New-Object System.Drawing.Size($keyWidth, $keyHeight)
        $panel.Location = New-Object System.Drawing.Point($rowStartX + (($keyWidth + $gap) * $columnIndex), $rowTop[$rowIndex])
        $panel.BackColor = [System.Drawing.Color]::FromArgb(34, 42, 56)

        $label = New-Object System.Windows.Forms.Label
        $label.Dock = [System.Windows.Forms.DockStyle]::Fill
        $label.TextAlign = [System.Drawing.ContentAlignment]::MiddleCenter
        $label.ForeColor = [System.Drawing.Color]::FromArgb(236, 240, 248)
        $label.Font = New-Object System.Drawing.Font('Segoe UI Semibold', 9)
        $panel.Controls.Add($label)

        $form.Controls.Add($panel)
        $panels.Add([pscustomobject]@{
                Panel = $panel
                Label = $label
            })
    }
}

for ($thumbIndex = 0; $thumbIndex -lt 6; $thumbIndex++) {
    $panel = New-Object System.Windows.Forms.Panel
    $panel.Size = New-Object System.Drawing.Size($keyWidth, $keyHeight)
    $panel.Location = New-Object System.Drawing.Point($thumbPositions[$thumbIndex], $thumbTop)
    $panel.BackColor = [System.Drawing.Color]::FromArgb(34, 42, 56)

    $label = New-Object System.Windows.Forms.Label
    $label.Dock = [System.Windows.Forms.DockStyle]::Fill
    $label.TextAlign = [System.Drawing.ContentAlignment]::MiddleCenter
    $label.ForeColor = [System.Drawing.Color]::FromArgb(236, 240, 248)
    $label.Font = New-Object System.Drawing.Font('Segoe UI Semibold', 9)
    $panel.Controls.Add($label)

    $form.Controls.Add($panel)
    $panels.Add([pscustomobject]@{
            Panel = $panel
            Label = $label
        })
}

$script:ActiveLayerIndex = -1
$script:ConnectedPortName = $null
$script:SerialBuffer = ''
$script:SerialPort = $null
$script:LiveLayoutLoaded = $false
$script:NextLiveLayoutAttempt = Get-Date

function Set-OverlayLayer {
    param(
        [int]$LayerIndex,
        [string]$LayerNameOverride
    )

    $layer = Get-LayerByIndex -Layout $script:OverlayLayout -LayerIndex $LayerIndex
    $layerName = if ($LayerNameOverride) { $LayerNameOverride } else { [string]$layer.name }
    $layerLabel.Text = $layerName

    $flatRows = @()
    foreach ($row in $layer.rows) {
        foreach ($binding in $row) {
            $flatRows += [string]$binding
        }
    }

    for ($i = 0; $i -lt $panels.Count; $i++) {
        $binding = if ($i -lt $flatRows.Count) { $flatRows[$i] } else { '' }
        $panels[$i].Label.Text = $binding

        if ([string]::IsNullOrWhiteSpace($binding)) {
            $panels[$i].Panel.BackColor = [System.Drawing.Color]::FromArgb(24, 30, 40)
            $panels[$i].Label.ForeColor = [System.Drawing.Color]::FromArgb(90, 102, 124)
        } else {
            $panels[$i].Panel.BackColor = [System.Drawing.Color]::FromArgb(38, 52, 71)
            $panels[$i].Label.ForeColor = [System.Drawing.Color]::FromArgb(240, 245, 252)
        }
    }

    $headerLabel.Text = "Corne  L$LayerIndex"
    $script:ActiveLayerIndex = $LayerIndex
}

function New-OverlaySerialPort {
    param([string]$TargetPortName)

    $port = New-Object System.IO.Ports.SerialPort $TargetPortName, 115200, ([System.IO.Ports.Parity]::None), 8, ([System.IO.Ports.StopBits]::One)
    $port.NewLine = "`n"
    $port.ReadTimeout = 50
    $port.WriteTimeout = 250
    $port.DtrEnable = $true
    $port.RtsEnable = $true
    return $port
}

function Close-KeyboardConnection {
    if ($script:SerialPort -and $script:SerialPort.IsOpen) {
        $script:SerialPort.Close()
    }

    if ($script:SerialPort) {
        $script:SerialPort.Dispose()
        $script:SerialPort = $null
    }

    $script:ConnectedPortName = $null
    $script:SerialBuffer = ''
    $script:OverlayLayout = $layout
    $script:LiveLayoutLoaded = $false
    $script:NextLiveLayoutAttempt = Get-Date
    $statusLabel.Text = "No $KeyboardName keyboard detected"
    $form.Hide()
}

function Open-KeyboardConnection {
    param([string]$TargetPortName)

    if ([string]::IsNullOrWhiteSpace($TargetPortName)) {
        return
    }

    try {
        $script:SerialPort = New-OverlaySerialPort -TargetPortName $TargetPortName
        $script:SerialPort.Open()
        $script:ConnectedPortName = $TargetPortName
        $statusLabel.Text = "Listening for $KeyboardName on $TargetPortName"
        $form.Show()
        Set-OverlayLayer -LayerIndex ([int]$initialLayer.index) -LayerNameOverride ([string]$initialLayer.name)
        $script:LiveLayoutLoaded = $false
        $script:NextLiveLayoutAttempt = Get-Date
        Try-LoadLiveLayout
    } catch {
        $statusLabel.Text = "Failed to open $TargetPortName"
        if ($script:SerialPort) {
            $script:SerialPort.Dispose()
            $script:SerialPort = $null
        }
    }
}

function Try-LoadLiveLayout {
    if ($script:LiveLayoutLoaded -or -not $script:SerialPort -or -not $script:SerialPort.IsOpen) {
        return
    }

    if (-not (Get-Command Get-CorneStudioLayout -ErrorAction SilentlyContinue)) {
        return
    }

    $result = Get-CorneStudioLayout -SerialPort $script:SerialPort -KeyboardName $KeyboardName
    if ($result.Success -and $result.Layout) {
        $script:OverlayLayout = $result.Layout
        $script:LiveLayoutLoaded = $true
        $statusLabel.Text = "Loaded live keymap from $KeyboardName on $($script:ConnectedPortName)"
        Set-OverlayLayer -LayerIndex ([int]$initialLayer.index) -LayerNameOverride $null
    } else {
        $statusLabel.Text = "Using repo layout - $($result.Reason)"
        $script:NextLiveLayoutAttempt = (Get-Date).AddSeconds(5)
    }
}

$pollTimer = New-Object System.Windows.Forms.Timer
$pollTimer.Interval = 100
$pollTimer.Add_Tick({
        $targetPortName = Resolve-TargetPort -ExplicitPortName $PortName -ExpectedKeyboardName $KeyboardName

        if (-not $script:ConnectedPortName) {
            if ($targetPortName) {
                Open-KeyboardConnection -TargetPortName $targetPortName
            } else {
                $statusLabel.Text = "No $KeyboardName keyboard detected"
            }
            return
        }

        if (-not $script:LiveLayoutLoaded -and (Get-Date) -ge $script:NextLiveLayoutAttempt) {
            Try-LoadLiveLayout
        }

        if (-not $targetPortName -or $targetPortName -ne $script:ConnectedPortName) {
            Close-KeyboardConnection
            return
        }

        if (-not $script:SerialPort -or -not $script:SerialPort.IsOpen) {
            Close-KeyboardConnection
            return
        }

        try {
            $chunk = $script:SerialPort.ReadExisting()
        } catch {
            Close-KeyboardConnection
            return
        }

        if ([string]::IsNullOrEmpty($chunk)) {
            return
        }

        $script:SerialBuffer += $chunk

        while ($script:SerialBuffer.Contains("`n")) {
            $line, $remainder = $script:SerialBuffer -split "`n", 2
            $script:SerialBuffer = $remainder
            $line = $line.Trim()

            if ($line -like 'ZMK_OVERLAY|LAYER|*') {
                $parts = $line -split '\|', 4
                if ($parts.Count -ge 4 -and $parts[2] -match '^\d+$') {
                    $layerIndex = [int]$parts[2]
                    $layerName = $parts[3]
                    Set-OverlayLayer -LayerIndex $layerIndex -LayerNameOverride $layerName
                    $statusLabel.Text = "Listening on $($script:ConnectedPortName) - Updated $(Get-Date -Format 'HH:mm:ss')"
                }
            }
        }
    })

$form.Add_Shown({
        Set-ClickThrough -Form $form
    })

$form.Add_FormClosed({
        $pollTimer.Stop()
        Close-KeyboardConnection
    })

$initialLayer = $layout.layers | Sort-Object index | Select-Object -First 1
Set-OverlayLayer -LayerIndex ([int]$initialLayer.index) -LayerNameOverride ([string]$initialLayer.name)
$form.Hide()

$pollTimer.Start()
[System.Windows.Forms.Application]::Run($form)
