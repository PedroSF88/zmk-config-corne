$script:CorneStudioNextRequestId = 1

function New-ByteList {
    return New-Object 'System.Collections.Generic.List[byte]'
}

function Add-VarintBytes {
    param(
        [System.Collections.Generic.List[byte]]$Bytes,
        [UInt64]$Value
    )

    do {
        $next = [byte]($Value -band 0x7f)
        $Value = $Value -shr 7
        if ($Value -ne 0) {
            $next = [byte]($next -bor 0x80)
        }
        $Bytes.Add($next)
    } while ($Value -ne 0)
}

function New-ProtoVarintField {
    param(
        [int]$FieldNumber,
        [UInt64]$Value
    )

    $bytes = New-ByteList
    Add-VarintBytes -Bytes $bytes -Value ([UInt64](($FieldNumber -shl 3) -bor 0))
    Add-VarintBytes -Bytes $bytes -Value $Value
    return [byte[]]$bytes.ToArray()
}

function New-ProtoLengthField {
    param(
        [int]$FieldNumber,
        [byte[]]$Payload
    )

    $bytes = New-ByteList
    Add-VarintBytes -Bytes $bytes -Value ([UInt64](($FieldNumber -shl 3) -bor 2))
    Add-VarintBytes -Bytes $bytes -Value ([UInt64]$Payload.Length)
    $bytes.AddRange($Payload)
    return [byte[]]$bytes.ToArray()
}

function Join-ByteArrays {
    param([byte[][]]$Parts)

    $bytes = New-ByteList
    foreach ($part in $Parts) {
        if ($part) {
            $bytes.AddRange($part)
        }
    }
    return [byte[]]$bytes.ToArray()
}

function Read-ProtoVarint {
    param(
        [byte[]]$Bytes,
        [int]$Offset
    )

    [UInt64]$value = 0
    $shift = 0
    $cursor = $Offset

    while ($cursor -lt $Bytes.Length) {
        $b = [UInt64]$Bytes[$cursor]
        $cursor++
        $value = $value -bor (($b -band 0x7f) -shl $shift)
        if (($b -band 0x80) -eq 0) {
            return [pscustomobject]@{
                Value  = $value
                Offset = $cursor
            }
        }
        $shift += 7
    }

    throw 'Unexpected end of protobuf varint.'
}

function Read-ProtoFields {
    param([byte[]]$Bytes)

    $fields = New-Object System.Collections.Generic.List[object]
    $offset = 0

    while ($offset -lt $Bytes.Length) {
        $keyResult = Read-ProtoVarint -Bytes $Bytes -Offset $offset
        $key = [UInt64]$keyResult.Value
        $offset = [int]$keyResult.Offset

        $fieldNumber = [int]($key -shr 3)
        $wireType = [int]($key -band 0x07)
        $field = [ordered]@{
            FieldNumber = $fieldNumber
            WireType    = $wireType
            Varint      = $null
            Bytes       = $null
        }

        switch ($wireType) {
            0 {
                $valueResult = Read-ProtoVarint -Bytes $Bytes -Offset $offset
                $field.Varint = [UInt64]$valueResult.Value
                $offset = [int]$valueResult.Offset
            }
            1 {
                if (($offset + 8) -gt $Bytes.Length) {
                    throw 'Unexpected end of protobuf fixed64 field.'
                }
                $field.Bytes = [byte[]]$Bytes[$offset..($offset + 7)]
                $offset += 8
            }
            2 {
                $lengthResult = Read-ProtoVarint -Bytes $Bytes -Offset $offset
                $length = [int]$lengthResult.Value
                $offset = [int]$lengthResult.Offset
                if ($length -eq 0) {
                    $field.Bytes = [byte[]]@()
                } else {
                    if (($offset + $length) -gt $Bytes.Length) {
                        throw 'Unexpected end of protobuf length-delimited field.'
                    }
                    $field.Bytes = [byte[]]$Bytes[$offset..($offset + $length - 1)]
                }
                $offset += $length
            }
            5 {
                if (($offset + 4) -gt $Bytes.Length) {
                    throw 'Unexpected end of protobuf fixed32 field.'
                }
                $field.Bytes = [byte[]]$Bytes[$offset..($offset + 3)]
                $offset += 4
            }
            default {
                throw "Unsupported protobuf wire type: $wireType"
            }
        }

        $fields.Add([pscustomobject]$field)
    }

    # @($fields) throws "Argument types do not match" on Windows PowerShell 5.1.
    return $fields.ToArray()
}

function Get-ProtoField {
    param(
        [object[]]$Fields,
        [int]$FieldNumber
    )

    return @($Fields | Where-Object { $_.FieldNumber -eq $FieldNumber })
}

function ConvertFrom-ZigZag32 {
    param([UInt64]$Value)

    if (($Value -band 1) -eq 1) {
        return -1 * ([int]($Value -shr 1) + 1)
    }

    return [int]($Value -shr 1)
}

function New-StudioFrame {
    param([byte[]]$Payload)

    $bytes = New-ByteList
    $bytes.Add([byte]0xab)

    foreach ($b in $Payload) {
        if ($b -eq 0xab -or $b -eq 0xac -or $b -eq 0xad) {
            $bytes.Add([byte]0xac)
        }
        $bytes.Add([byte]$b)
    }

    $bytes.Add([byte]0xad)
    return [byte[]]$bytes.ToArray()
}

function Read-StudioFrame {
    param(
        [System.IO.Ports.SerialPort]$SerialPort,
        [int]$TimeoutMs = 2500
    )

    $payload = New-ByteList
    $state = 'Idle'
    $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()

    while ($stopwatch.ElapsedMilliseconds -lt $TimeoutMs) {
        $available = $SerialPort.BytesToRead
        if ($available -le 0) {
            Start-Sleep -Milliseconds 10
            continue
        }

        $buffer = New-Object byte[] $available
        [void]$SerialPort.Read($buffer, 0, $available)

        foreach ($b in $buffer) {
            switch ($state) {
                'Idle' {
                    if ($b -eq 0xab) {
                        $payload.Clear()
                        $state = 'Data'
                    }
                }
                'Data' {
                    if ($b -eq 0xab) {
                        $payload.Clear()
                    } elseif ($b -eq 0xac) {
                        $state = 'Escaped'
                    } elseif ($b -eq 0xad) {
                        return [byte[]]$payload.ToArray()
                    } else {
                        $payload.Add([byte]$b)
                    }
                }
                'Escaped' {
                    $payload.Add([byte]$b)
                    $state = 'Data'
                }
            }
        }
    }

    return $null
}

function Invoke-ZmkStudioRequest {
    param(
        [System.IO.Ports.SerialPort]$SerialPort,
        [byte[]]$RequestPayload,
        [int]$TimeoutMs = 2500
    )

    $frame = New-StudioFrame -Payload $RequestPayload
    $SerialPort.DiscardInBuffer()
    $SerialPort.Write($frame, 0, $frame.Length)
    $responsePayload = Read-StudioFrame -SerialPort $SerialPort -TimeoutMs $TimeoutMs

    if (-not $responsePayload) {
        throw 'Timed out waiting for a ZMK Studio RPC response.'
    }

    return $responsePayload
}

function New-StudioRequest {
    param(
        [int]$SubsystemFieldNumber,
        [byte[]]$SubsystemPayload
    )

    $requestId = $script:CorneStudioNextRequestId
    $script:CorneStudioNextRequestId++

    return [pscustomobject]@{
        RequestId = $requestId
        Payload   = Join-ByteArrays -Parts @(
            (New-ProtoVarintField -FieldNumber 1 -Value ([UInt64]$requestId)),
            (New-ProtoLengthField -FieldNumber $SubsystemFieldNumber -Payload $SubsystemPayload)
        )
    }
}

function Get-StudioRequestResponseFields {
    param([byte[]]$ResponsePayload)

    $responseFields = Read-ProtoFields -Bytes $ResponsePayload
    $requestResponse = Get-ProtoField -Fields $responseFields -FieldNumber 1 | Select-Object -First 1
    if (-not $requestResponse) {
        throw 'Received a ZMK Studio notification instead of a request response.'
    }

    return Read-ProtoFields -Bytes $requestResponse.Bytes
}

function Get-ZmkStudioMetaError {
    param([object[]]$RequestResponseFields)

    $meta = Get-ProtoField -Fields $RequestResponseFields -FieldNumber 2 | Select-Object -First 1
    if (-not $meta) {
        return $null
    }

    $metaFields = Read-ProtoFields -Bytes $meta.Bytes
    $simpleError = Get-ProtoField -Fields $metaFields -FieldNumber 2 | Select-Object -First 1
    if (-not $simpleError) {
        return $null
    }

    switch ([int]$simpleError.Varint) {
        1 { return 'UNLOCK_REQUIRED' }
        2 { return 'RPC_NOT_FOUND' }
        3 { return 'MSG_DECODE_FAILED' }
        4 { return 'MSG_ENCODE_FAILED' }
        default { return 'GENERIC' }
    }
}

function Invoke-ZmkCoreRequest {
    param(
        [System.IO.Ports.SerialPort]$SerialPort,
        [byte[]]$CorePayload,
        [int]$TimeoutMs = 2500
    )

    $request = New-StudioRequest -SubsystemFieldNumber 3 -SubsystemPayload $CorePayload
    $responsePayload = Invoke-ZmkStudioRequest -SerialPort $SerialPort -RequestPayload $request.Payload -TimeoutMs $TimeoutMs
    return Get-StudioRequestResponseFields -ResponsePayload $responsePayload
}

function Invoke-ZmkKeymapRequest {
    param(
        [System.IO.Ports.SerialPort]$SerialPort,
        [byte[]]$KeymapPayload,
        [int]$TimeoutMs = 4000
    )

    $request = New-StudioRequest -SubsystemFieldNumber 5 -SubsystemPayload $KeymapPayload
    $responsePayload = Invoke-ZmkStudioRequest -SerialPort $SerialPort -RequestPayload $request.Payload -TimeoutMs $TimeoutMs
    return Get-StudioRequestResponseFields -ResponsePayload $responsePayload
}

function Invoke-ZmkBehaviorRequest {
    param(
        [System.IO.Ports.SerialPort]$SerialPort,
        [byte[]]$BehaviorPayload,
        [int]$TimeoutMs = 2500
    )

    $request = New-StudioRequest -SubsystemFieldNumber 4 -SubsystemPayload $BehaviorPayload
    $responsePayload = Invoke-ZmkStudioRequest -SerialPort $SerialPort -RequestPayload $request.Payload -TimeoutMs $TimeoutMs
    return Get-StudioRequestResponseFields -ResponsePayload $responsePayload
}

function Get-ZmkStudioLockState {
    param([System.IO.Ports.SerialPort]$SerialPort)

    $coreRequest = New-ProtoVarintField -FieldNumber 2 -Value 1
    $fields = Invoke-ZmkCoreRequest -SerialPort $SerialPort -CorePayload $coreRequest
    $core = Get-ProtoField -Fields $fields -FieldNumber 3 | Select-Object -First 1
    if (-not $core) {
        return 'UNKNOWN'
    }

    $coreFields = Read-ProtoFields -Bytes $core.Bytes
    $lockState = Get-ProtoField -Fields $coreFields -FieldNumber 2 | Select-Object -First 1
    if (-not $lockState) {
        return 'UNKNOWN'
    }

    if ([int]$lockState.Varint -eq 1) {
        return 'UNLOCKED'
    }

    return 'LOCKED'
}

function Get-ZmkStudioDeviceName {
    param([System.IO.Ports.SerialPort]$SerialPort)

    $coreRequest = New-ProtoVarintField -FieldNumber 1 -Value 1
    $fields = Invoke-ZmkCoreRequest -SerialPort $SerialPort -CorePayload $coreRequest
    $core = Get-ProtoField -Fields $fields -FieldNumber 3 | Select-Object -First 1
    if (-not $core) {
        return $null
    }

    $coreFields = Read-ProtoFields -Bytes $core.Bytes
    $deviceInfo = Get-ProtoField -Fields $coreFields -FieldNumber 1 | Select-Object -First 1
    if (-not $deviceInfo) {
        return $null
    }

    $deviceInfoFields = Read-ProtoFields -Bytes $deviceInfo.Bytes
    $name = Get-ProtoField -Fields $deviceInfoFields -FieldNumber 1 | Select-Object -First 1
    if (-not $name) {
        return $null
    }

    return [System.Text.Encoding]::UTF8.GetString($name.Bytes)
}

function Get-ZmkBehaviorDisplayName {
    param(
        [System.IO.Ports.SerialPort]$SerialPort,
        [int]$BehaviorId
    )

    $detailsRequest = New-ProtoLengthField -FieldNumber 2 -Payload (
        New-ProtoVarintField -FieldNumber 1 -Value ([UInt64]$BehaviorId)
    )

    $fields = Invoke-ZmkBehaviorRequest -SerialPort $SerialPort -BehaviorPayload $detailsRequest
    $error = Get-ZmkStudioMetaError -RequestResponseFields $fields
    if ($error) {
        return $null
    }

    $behaviors = Get-ProtoField -Fields $fields -FieldNumber 4 | Select-Object -First 1
    if (-not $behaviors) {
        return $null
    }

    $behaviorFields = Read-ProtoFields -Bytes $behaviors.Bytes
    $details = Get-ProtoField -Fields $behaviorFields -FieldNumber 2 | Select-Object -First 1
    if (-not $details) {
        return $null
    }

    $detailsFields = Read-ProtoFields -Bytes $details.Bytes
    $displayName = Get-ProtoField -Fields $detailsFields -FieldNumber 2 | Select-Object -First 1
    if (-not $displayName) {
        return $null
    }

    return [System.Text.Encoding]::UTF8.GetString($displayName.Bytes)
}

function Convert-HidUsageToLabel {
    param([UInt64]$Usage)

    $mods = [int](($Usage -shr 24) -band 0xff)
    $base = [int]($Usage -band 0x00ffffff)
    $page = [int](($base -shr 16) -band 0xff)
    $id = [int]($base -band 0xffff)

    $keyLabels = @{
        0x04 = 'A'; 0x05 = 'B'; 0x06 = 'C'; 0x07 = 'D'; 0x08 = 'E'; 0x09 = 'F'; 0x0a = 'G'
        0x0b = 'H'; 0x0c = 'I'; 0x0d = 'J'; 0x0e = 'K'; 0x0f = 'L'; 0x10 = 'M'; 0x11 = 'N'
        0x12 = 'O'; 0x13 = 'P'; 0x14 = 'Q'; 0x15 = 'R'; 0x16 = 'S'; 0x17 = 'T'; 0x18 = 'U'
        0x19 = 'V'; 0x1a = 'W'; 0x1b = 'X'; 0x1c = 'Y'; 0x1d = 'Z'
        0x1e = '1'; 0x1f = '2'; 0x20 = '3'; 0x21 = '4'; 0x22 = '5'; 0x23 = '6'; 0x24 = '7'
        0x25 = '8'; 0x26 = '9'; 0x27 = '0'
        0x28 = 'ENT'; 0x29 = 'ESC'; 0x2a = 'BSPC'; 0x2b = 'TAB'; 0x2c = 'SPC'
        0x2d = '-'; 0x2e = '='; 0x2f = '['; 0x30 = ']'; 0x31 = '\'; 0x32 = '#'
        0x33 = ';'; 0x34 = "'"; 0x35 = '`'; 0x36 = ','; 0x37 = '.'; 0x38 = '/'
        0x39 = 'CAPS'; 0x3a = 'F1'; 0x3b = 'F2'; 0x3c = 'F3'; 0x3d = 'F4'; 0x3e = 'F5'
        0x3f = 'F6'; 0x40 = 'F7'; 0x41 = 'F8'; 0x42 = 'F9'; 0x43 = 'F10'; 0x44 = 'F11'
        0x45 = 'F12'; 0x49 = 'INS'; 0x4a = 'HOME'; 0x4b = 'PGUP'; 0x4c = 'DEL'; 0x4d = 'END'
        0x4e = 'PGDN'; 0x4f = 'RIGHT'; 0x50 = 'LEFT'; 0x51 = 'DOWN'; 0x52 = 'UP'
        0xe0 = 'LCTL'; 0xe1 = 'LSFT'; 0xe2 = 'LALT'; 0xe3 = 'LGUI'; 0xe4 = 'RCTL'
        0xe5 = 'RSFT'; 0xe6 = 'RALT'; 0xe7 = 'RGUI'
    }

    $shiftLabels = @{
        0x1e = '!'; 0x1f = '@'; 0x20 = '#'; 0x21 = '$'; 0x22 = '%'; 0x23 = '^'; 0x24 = '&'
        0x25 = '*'; 0x26 = '('; 0x27 = ')'; 0x2d = '_'; 0x2e = '+'; 0x2f = '{'; 0x30 = '}'
        0x31 = '|'; 0x33 = ':'; 0x34 = '"'; 0x35 = '~'; 0x36 = '<'; 0x37 = '>'; 0x38 = '?'
    }

    $consumerLabels = @{
        0xb5 = 'NEXT'; 0xb6 = 'PREV'; 0xb7 = 'STOP'; 0xcd = 'PLAY'; 0xe2 = 'MUTE'
        0xe9 = 'VOL+'; 0xea = 'VOL-'
    }

    if ($page -eq 0x07) {
        if (($mods -band 0x22) -ne 0 -and $shiftLabels.ContainsKey($id)) {
            return $shiftLabels[$id]
        }

        $label = if ($keyLabels.ContainsKey($id)) { $keyLabels[$id] } else { "K:$($id.ToString('X2'))" }
        $prefixes = @()
        if (($mods -band 0x11) -ne 0) { $prefixes += 'C' }
        if (($mods -band 0x44) -ne 0) { $prefixes += 'A' }
        if (($mods -band 0x88) -ne 0) { $prefixes += 'G' }
        if (($mods -band 0x22) -ne 0 -and -not $shiftLabels.ContainsKey($id)) { $prefixes += 'S' }
        if ($prefixes.Count -gt 0) {
            return "$( ($prefixes -join '+') )+$label".Replace(' ', '')
        }
        return $label
    }

    if ($page -eq 0x0c) {
        if ($consumerLabels.ContainsKey($id)) {
            return $consumerLabels[$id]
        }
        return "C:$($id.ToString('X2'))"
    }

    return "U:$($Usage.ToString('X'))"
}

function Convert-ZmkBindingToLabel {
    param(
        [object]$Binding,
        [hashtable]$BehaviorNames
    )

    if (-not $Binding -or $Binding.BehaviorId -eq 0) {
        return ''
    }

    $name = if ($BehaviorNames.ContainsKey($Binding.BehaviorId)) { $BehaviorNames[$Binding.BehaviorId] } else { '' }
    $normalized = ($name -replace '[^A-Za-z0-9]', '').ToLowerInvariant()

    switch ($normalized) {
        'keypress' { return Convert-HidUsageToLabel -Usage ([UInt64]$Binding.Param1) }
        'keytoggle' { return Convert-HidUsageToLabel -Usage ([UInt64]$Binding.Param1) }
        'modtap' { return Convert-HidUsageToLabel -Usage ([UInt64]$Binding.Param2) }
        'layertap' { return Convert-HidUsageToLabel -Usage ([UInt64]$Binding.Param2) }
        'stickykey' { return Convert-HidUsageToLabel -Usage ([UInt64]$Binding.Param1) }
        'tolayer' { return "L$($Binding.Param1)" }
        'momentarylayer' { return "L$($Binding.Param1)" }
        'togglelayer' { return "TG$($Binding.Param1)" }
        'transparent' { return 'TRNS' }
        'none' { return '' }
        'bootloader' { return 'BOOT' }
        'reset' { return 'RESET' }
        'studiounlock' { return 'STUDIO' }
        'bluetooth' {
            switch ([int]$Binding.Param1) {
                0 { return 'CLR' }
                3 { return "BT$($Binding.Param2)" }
                4 { return 'CLR ALL' }
                default { return 'BT' }
            }
        }
        default {
            if ($normalized -like '*commaperiod*') {
                return ', / .'
            }
            if ([string]::IsNullOrWhiteSpace($name)) {
                return "B$($Binding.BehaviorId)"
            }
            return (($name -replace '\s+', ' ').Trim()).Substring(0, [Math]::Min(10, $name.Trim().Length)).ToUpperInvariant()
        }
    }
}

function Convert-ZmkLayerBytes {
    param([byte[]]$LayerBytes)

    $layerFields = Read-ProtoFields -Bytes $LayerBytes
    $idField = Get-ProtoField -Fields $layerFields -FieldNumber 1 | Select-Object -First 1
    $nameField = Get-ProtoField -Fields $layerFields -FieldNumber 2 | Select-Object -First 1
    $bindingFields = Get-ProtoField -Fields $layerFields -FieldNumber 3

    $bindings = @()
    foreach ($bindingField in $bindingFields) {
        $binding = @{
            BehaviorId = 0
            Param1     = 0
            Param2     = 0
        }
        $bindingSubFields = Read-ProtoFields -Bytes $bindingField.Bytes
        foreach ($field in $bindingSubFields) {
            switch ($field.FieldNumber) {
                1 { $binding.BehaviorId = ConvertFrom-ZigZag32 -Value ([UInt64]$field.Varint) }
                2 { $binding.Param1 = [UInt64]$field.Varint }
                3 { $binding.Param2 = [UInt64]$field.Varint }
            }
        }
        $bindings += [pscustomobject]$binding
    }

    return [pscustomobject]@{
        Id       = if ($idField) { [int]$idField.Varint } else { 0 }
        Name     = if ($nameField) { [System.Text.Encoding]::UTF8.GetString($nameField.Bytes) } else { '' }
        Bindings = $bindings
    }
}

function Get-CorneStudioLayout {
    param(
        [System.IO.Ports.SerialPort]$SerialPort,
        [string]$KeyboardName = 'CorneWireless2'
    )

    try {
        $deviceName = Get-ZmkStudioDeviceName -SerialPort $SerialPort
        if ($deviceName -and $deviceName -ne $KeyboardName) {
            return [pscustomobject]@{
                Success = $false
                Reason  = "Connected device is $deviceName, not $KeyboardName."
                Layout  = $null
            }
        }

        $lockState = Get-ZmkStudioLockState -SerialPort $SerialPort
        if ($lockState -eq 'LOCKED') {
            return [pscustomobject]@{
                Success = $false
                Reason  = 'Studio is locked. Press your Studio Unlock key, then the app will retry.'
                Layout  = $null
            }
        }

        $keymapRequest = New-ProtoVarintField -FieldNumber 1 -Value 1
        $fields = Invoke-ZmkKeymapRequest -SerialPort $SerialPort -KeymapPayload $keymapRequest
        $error = Get-ZmkStudioMetaError -RequestResponseFields $fields
        if ($error) {
            return [pscustomobject]@{
                Success = $false
                Reason  = "Studio keymap request failed: $error"
                Layout  = $null
            }
        }

        $keymapResponse = Get-ProtoField -Fields $fields -FieldNumber 5 | Select-Object -First 1
        if (-not $keymapResponse) {
            return [pscustomobject]@{
                Success = $false
                Reason  = 'Studio did not return a keymap response.'
                Layout  = $null
            }
        }

        $keymapResponseFields = Read-ProtoFields -Bytes $keymapResponse.Bytes
        $keymap = Get-ProtoField -Fields $keymapResponseFields -FieldNumber 1 | Select-Object -First 1
        if (-not $keymap) {
            return [pscustomobject]@{
                Success = $false
                Reason  = 'Studio keymap response did not include keymap data.'
                Layout  = $null
            }
        }

        $keymapFields = Read-ProtoFields -Bytes $keymap.Bytes
        $rawLayers = @(Get-ProtoField -Fields $keymapFields -FieldNumber 1 | ForEach-Object {
                Convert-ZmkLayerBytes -LayerBytes $_.Bytes
            })

        $uniqueBehaviorIds = @(
            $rawLayers |
                ForEach-Object { $_.Bindings } |
                Where-Object { $_.BehaviorId -ne 0 } |
                ForEach-Object { $_.BehaviorId } |
                Sort-Object -Unique
        )

        $behaviorNames = @{}
        foreach ($behaviorId in $uniqueBehaviorIds) {
            try {
                $displayName = Get-ZmkBehaviorDisplayName -SerialPort $SerialPort -BehaviorId ([int]$behaviorId)
                if ($displayName) {
                    $behaviorNames[[int]$behaviorId] = $displayName
                }
            } catch {
                $behaviorNames[[int]$behaviorId] = ''
            }
        }

        $layers = @()
        for ($i = 0; $i -lt $rawLayers.Count; $i++) {
            $rawLayer = $rawLayers[$i]
            $labels = @($rawLayer.Bindings | ForEach-Object {
                    Convert-ZmkBindingToLabel -Binding $_ -BehaviorNames $behaviorNames
                })
            while ($labels.Count -lt 42) {
                $labels += ''
            }

            $layers += [pscustomobject]@{
                index = $i
                id    = $rawLayer.Id
                node  = "device_layer_$($rawLayer.Id)"
                name  = if ($rawLayer.Name) { $rawLayer.Name } else { "Layer $i" }
                rows  = @(
                    @($labels[0..11]),
                    @($labels[12..23]),
                    @($labels[24..35]),
                    @($labels[36..41])
                )
            }
        }

        return [pscustomobject]@{
            Success = $true
            Reason  = "Loaded live keymap from $KeyboardName."
            Layout  = [pscustomobject]@{
                generated_from = 'device:ZMK Studio RPC'
                layers         = $layers
            }
        }
    } catch {
        return [pscustomobject]@{
            Success = $false
            Reason  = $_.Exception.Message
            Layout  = $null
        }
    } finally {
        try {
            $SerialPort.DiscardInBuffer()
        } catch {
        }
    }
}
