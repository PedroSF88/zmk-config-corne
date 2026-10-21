param(
    [string]$PortName,
    [string]$KeyboardName = 'CorneWireless2'
)

. (Join-Path $PSScriptRoot 'CorneStudioRpc.ps1')

function Get-ActiveSerialPorts {
    return @(
        (Get-ItemProperty 'HKLM:\HARDWARE\DEVICEMAP\SERIALCOMM').PSObject.Properties |
            Where-Object { $_.Name -notlike 'PS*' } |
            ForEach-Object { $_.Value } |
            Sort-Object -Unique
    )
}

function Resolve-CornePort {
    if ($PortName) {
        return $PortName
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

    return @($registeredCornePorts | Where-Object { $_ -in $activePorts } | Select-Object -First 1)
}

$resolvedPort = Resolve-CornePort
if (-not $resolvedPort) {
    Write-Host "No active Corne USB serial port detected."
    exit 1
}

$serialPort = New-Object System.IO.Ports.SerialPort $resolvedPort, 115200, ([System.IO.Ports.Parity]::None), 8, ([System.IO.Ports.StopBits]::One)
$serialPort.ReadTimeout = 250
$serialPort.WriteTimeout = 250
$serialPort.DtrEnable = $true
$serialPort.RtsEnable = $true

try {
    $serialPort.Open()
    $result = Get-CorneStudioLayout -SerialPort $serialPort -KeyboardName $KeyboardName

    if (-not $result.Success) {
        Write-Host "Live keymap fetch failed: $($result.Reason)"
        exit 2
    }

    Write-Host "Live keymap loaded from $resolvedPort"
    foreach ($layer in $result.Layout.layers) {
        Write-Host "L$($layer.index): $($layer.name)"
        Write-Host ("  " + (($layer.rows[0]) -join ' '))
    }
} finally {
    if ($serialPort.IsOpen) {
        $serialPort.Close()
    }
    $serialPort.Dispose()
}
