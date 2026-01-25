# ---------- Helper: Get Item Size ----------
function Get-ItemSize {
    param ($Item)

    if ($Item.PSIsContainer) {
        $size = Get-ChildItem -LiteralPath $Item.FullName -Recurse -File -ErrorAction SilentlyContinue |
            Measure-Object Length -Sum |
            Select-Object -ExpandProperty Sum
    }
    else {
        $size = $Item.Length
    }

    [PSCustomObject]@{
        Path      = $Item.FullName
        SizeBytes = $size
    }
}

# ---------- Helper: Convert Size ----------
function Convert-Size {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory, ValueFromPipeline)]
        [long]$Bytes,

        [ValidateSet(
            "AutoB", "AutoiB",
            "B", "KB", "MB", "GB", "TB",
            "KiB", "MiB", "GiB", "TiB"
        )]
        [string]$Unit = "AutoB"
    )

    if ($Bytes -lt 0) {
        throw "Bytes value cannot be negative. Actual value: $Bytes"
    }

    # Detect auto mode
    $isAuto = $Unit -like 'Auto*'

    # Determine base by unit suffix only
    $isBinary = $Unit -match 'iB$'
    $base     = if ($isBinary) { 1024 } else { 1000 }

    # Unit table
    $units = if ($isBinary) {
        @("B", "KiB", "MiB", "GiB", "TiB")
    } else {
        @("B", "KB", "MB", "GB", "TB")
    }

    # Auto-select unit
    if ($isAuto) {
        $index = 0
        while (
            $Bytes -ge [math]::Pow($base, $index + 1) -and
            $index -lt $units.Count - 1
        ) {
            $index++
        }
        $Unit = $units[$index]
    }

    # Resolve power
    $power = $units.IndexOf($Unit)
    if ($power -lt 0) {
        throw "Unit '$Unit' is not compatible with base $base."
    }

    # Calculate value
    $value = if ($Unit -eq "B") {
        $Bytes
    } else {
        [math]::Round($Bytes / [math]::Pow($base, $power), 2)
    }

    [PSCustomObject]@{
        Bytes = $Bytes
        Value = $value
        Unit  = $Unit
        Base  = $base
        Text  = "$value $Unit"
    }
}

Export-ModuleMember -Function @(
    'Get-ItemSize'
    'Convert-Size'
)
