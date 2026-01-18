<#
.SYNOPSIS
Scans folders at a specific depth and calculates their total size.

.DESCRIPTION
This script scans a specified base path and identifies folders that exist at an
exact depth ("Floor") relative to that base path. For each matching folder, the
script recursively calculates the total size of all contained files.

The results can be filtered by minimum size, sorted by folder size, displayed
in different units (MB, GB, TB), and optionally exported to CSV, JSON, or TXT
files. A progress bar and quiet mode are also supported.

.PARAMETER Path
The base directory to scan. This parameter is mandatory.

.PARAMETER Floor
The folder depth relative to the base path. Only folders at this exact depth
will be processed. This parameter is mandatory.

.PARAMETER MinSizeMB
Minimum folder size (in MB) to include in the results.
Folders smaller than this value will be skipped.
Default value is 0.

.PARAMETER Unit
The unit used for displaying folder size.
Valid values are MB, GB, and TB.
Default value is MB.

.PARAMETER Sort
If specified, the results will be sorted by folder size.

.PARAMETER Desc
If specified together with -Sort, results will be sorted in descending order
(from largest to smallest).

.PARAMETER Directory
Specifies that only directories (folders) should be returned.

.PARAMETER File
Specifies that only files should be returned.

.PARAMETER Shallow
If specified, only immediate child folders are discovered.
Subfolders will not be recursively enumerated when identifying target folders.

.PARAMETER Progress
Displays a progress bar while scanning folders.

.PARAMETER Quiet
Suppresses console output. Useful when exporting results to files only.

.PARAMETER OutCsv
Path to a CSV file where the results will be exported.

.PARAMETER OutJson
Path to a JSON file where the results will be exported.

.PARAMETER OutTxt
Path to a TXT file where the formatted results will be exported.

.EXAMPLE
Scan second-level folders under D:\Data and display sizes in MB.

    .\Scan-FolderSize.ps1 -Path "D:\Data" -Floor 2

.EXAMPLE
Scan first-level folders larger than 500 MB and sort by size in descending order.

    .\Scan-FolderSize.ps1 -Path "D:\Data" -Floor 1 -MinSizeMB 500 -Sort -Desc

.EXAMPLE
Scan third-level folders under D:\Projects, display sizes in GB, and show progress.

    .\Scan-FolderSize.ps1 -Path "D:\Projects" -Floor 3 -Unit GB -Progress

.EXAMPLE
Export scan results to CSV and JSON without displaying console output.

    .\Scan-FolderSize.ps1 -Path "C:\Logs" -Floor 2 -Sort `
        -OutCsv "folders.csv" -OutJson "folders.json" -Quiet

.EXAMPLE
Scan only immediate subfolders (non-recursive folder discovery).

    .\Scan-FolderSize.ps1 -Path "C:\Temp" -Floor 1 -Shallow

.NOTES
- Folder size is calculated by recursively summing file sizes.
- Size filtering (MinSizeMB) is always based on MB, regardless of output unit.
- Files or folders that cause access errors are silently skipped.
- Requires Windows PowerShell 5.1 or PowerShell 7+.

Author: Chen-Xian-Sheng | https://github.com/XIAN-SHENG-576692
Creation Date: 2026-01-18
Version: 1.0
#>

param (
    [Parameter(Mandatory)]
    [string]$Path,

    [Parameter(Mandatory)]
    [int]$Floor,

    [int]$MinSizeMB = 0,

    [ValidateSet("MB","GB","TB")]
    [string]$Unit = "MB",

    [switch]$Sort,
    [switch]$Desc,

    [string]$OutCsv,
    [string]$OutJson,
    [string]$OutTxt,

    [switch]$Quiet,
    [switch]$Progress,
    [switch]$Directory,
    [switch]$File,
    [switch]$Shallow
)

# ---------- Normalize ----------
$BasePath  = (Resolve-Path $Path).Path
$BaseDepth = ($BasePath -split '[\\/]').Count

# ---------- Get folders ----------
$FolderParams = @{ LiteralPath = $BasePath }
if ($Directory) { $FolderParams.Directory = $true }
if ($File) { $FolderParams.File = $true }
if (-not $Shallow) { $FolderParams.Recurse = $true }

$Folders = Get-ChildItem @FolderParams | Where-Object {
    (($_.FullName -split '[\\/]').Count - $BaseDepth) -le $Floor
}

$total = $Folders.Count
$index = 0

# ---------- Scan ----------
$Results = foreach ($Folder in $Folders) {

    $index++
    if ($Progress) {
        Write-Progress -Activity "Scanning folders" `
            -Status $Folder.FullName `
            -PercentComplete (($index / $total) * 100)
    }

    $SizeBytes = (Get-ChildItem -LiteralPath $Folder.FullName -Recurse -File -ErrorAction SilentlyContinue |
        Measure-Object Length -Sum).Sum

    if (-not $SizeBytes) { $SizeBytes = 0 }

    $SizeMB = [math]::Round($SizeBytes / 1MB, 2)
    if ($SizeMB -lt $MinSizeMB) { continue }

    switch ($Unit) {
        "GB" { $SizeOut = [math]::Round($SizeBytes / 1GB, 2) }
        "TB" { $SizeOut = [math]::Round($SizeBytes / 1TB, 2) }
        default { $SizeOut = $SizeMB }
    }

    [PSCustomObject]@{
        Size = $SizeOut
        Unit = $Unit
        Path = $Folder.FullName
    }
}

# ---------- Sort ----------
if ($Sort) {
    $Results = $Results | Sort-Object Size -Descending:$Desc
}

# ---------- Export ----------
if ($OutCsv) {
    $Results | Export-Csv $OutCsv -NoTypeInformation -Encoding UTF8
}

if ($OutJson) {
    $Results | ConvertTo-Json -Depth 3 | Out-File $OutJson -Encoding UTF8
}

if ($OutTxt) {
    $Results | Format-Table Size,Unit,Path -AutoSize | Out-String | Out-File $OutTxt
}

# ---------- Display ----------
if (-not $Quiet) {
    $Results | Format-Table Size, Unit, Path -AutoSize
}
