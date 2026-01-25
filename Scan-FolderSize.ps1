<#
.SYNOPSIS
Scan directories or files and calculate their sizes with PowerShell 5.x / 7+ compatibility.

.DESCRIPTION
This script scans a target path and calculates the size of directories and/or files.
It supports exact-depth scanning via the Floor parameter.

Floor definition:
- Floor = 1 : immediate children of Path
- Floor = 2 : grandchildren of Path
- etc.

The script automatically detects the PowerShell version at runtime:
- PowerShell 7+: uses parallel processing
- PowerShell 5.x: uses sequential processing

.PARAMETER Path
The base path to scan. This parameter is mandatory.

.PARAMETER Floor
Specifies the exact directory depth (relative to Path) to scan.
Only items at this depth will be evaluated.

.PARAMETER MinSizeMB
Minimum size in MB required for an item to be included in the results.

.PARAMETER Unit
Unit used to display sizes.

.PARAMETER Sort
Sorting order: default, Asc, or Desc.

.PARAMETER ExportPath
Base export path. Default is current directory + yyyy-MM-dd.

.PARAMETER ExportCSV
If specified, exports the scan results to a CSV file.
The output file will be saved to the path defined by ExportPath with a .csv extension.

.PARAMETER ExportJSON
If specified, exports the scan results to a JSON file.
The output file will be saved to the path defined by ExportPath with a .json extension.

.PARAMETER ExportTXT
If specified, exports the scan results to a plain text file.
The output file will be saved to the path defined by ExportPath with a .txt extension.

.PARAMETER ThrottleLimit
Specifies the maximum number of parallel threads used during scanning.
This parameter is effective only in PowerShell 7 or later.
The default value is 4.

.PARAMETER OutputMode
Quiet | Result | Progress

.PARAMETER ItemType
Directory | File | Both

.PARAMETER Force
If specified, allows the cmdlet to get items that otherwise can't be accessed by the user, such as hidden or system files.

.PARAMETER Shallow
If specified, disables recursion (Floor must be 1).

.EXAMPLE
Scan directories under C:\Data and show results:
PS> .\Scan-FolderSize.ps1 -Path C:\Data

.EXAMPLE
Scan files only, show progress, and sort descending:
PS> .\Scan-FolderSize.ps1 -Path C:\Data -ItemType File -OutputMode Progress -Sort Desc

.EXAMPLE
Export directory sizes larger than 100 MB to CSV and JSON:
PS> .\Scan-FolderSize.ps1 -Path C:\Data -MinSizeMB 100 -ExportCSV -ExportJSON

.NOTES
Author: Chen-Xian-Sheng | https://github.com/XIAN-SHENG-576692
Creation Date: 2026-01-25
Version: 1.1
#>

param (
    [Parameter(Mandatory)]
    [string]$Path,

    [int]$Floor = 1,

    [int]$MinSizeMB = 0,

    [ValidateSet(
        "AutoB", "AutoiB",
        "B", "KB", "MB", "GB", "TB",
        "KiB", "MiB", "GiB", "TiB"
    )]
    [string]$Unit = "AutoiB",

    [ValidateSet("", "Asc", "Desc")]
    [string]$Sort = "",

    [string]$ExportPath = (Join-Path (Get-Location) (Get-Date -Format "yyyy-MM-dd_HH-mm-ss")),

    [switch]$ExportCSV,
    [switch]$ExportJSON,
    [switch]$ExportTXT,

    [int]$ThrottleLimit = 4,

    [ValidateSet("Quiet","Result","Progress")]
    [string]$OutputMode = "Progress",

    [ValidateSet("Directory","File","Both")]
    [string]$ItemType = "Both",
    [switch]$Force,
    [switch]$Shallow
)

Import-Module "$PSScriptRoot\Scan-FolderSize.psm1" -Force
# Get-Command -Module Scan-FolderSize

# ---------- Normalize ----------
$ResolvedPath = (Resolve-Path -Path $Path).Path
$BaseDepth = ($ResolvedPath.TrimEnd('\').Split('\')).Count

# ---------- Processing ----------
$AccessErrors = @()

$items = Get-ChildItem `
    -LiteralPath $ResolvedPath `
    -Recurse:(!$Shallow) `
    -Force:($Force) `
    -ErrorAction SilentlyContinue `
    -ErrorVariable +AccessErrors |
    Where-Object {
        $depth = ($_.FullName.TrimEnd('\').Split('\')).Count - $BaseDepth
        $depth -le $Floor -and (
            ($ItemType -eq "Directory" -and $_.PSIsContainer) -or
            ($ItemType -eq "File" -and -not $_.PSIsContainer) -or
            ($ItemType -eq "Both")
        )
    }

$AccessErrorDetails = foreach ($err in $AccessErrors) {
    [PSCustomObject]@{
        Time       = Get-Date
        Path       = $err.TargetObject
        ErrorType  = $err.Exception.GetType().Name
        Message    = $err.Exception.Message
        Category   = $err.CategoryInfo.Category
        ErrorId    = $err.FullyQualifiedErrorId
    }
}

if ($OutputMode -eq "Progress" -and $AccessErrors.Count -gt 0) {
    Write-Warning "Skipped $($AccessErrors.Count) inaccessible paths."
    $AccessErrorDetails | Format-Table -AutoSize
}

if ($OutputMode -eq "Progress") {
    $i = 0
    $total = $items.Count
}

if ($PSVersionTable.PSVersion.Major -ge 7) {
    $results = $items | ForEach-Object -Parallel {
        Import-Module "$using:PSScriptRoot\Scan-FolderSize.psm1"
        Get-ItemSize $_
    } -ThrottleLimit $ThrottleLimit
}
else {
    $results = foreach ($item in $items) {
        if ($OutputMode -eq "Progress") {
            $i++
            Write-Progress -Activity "Scanning" -Status $item.FullName -PercentComplete (($i/$total)*100)
        }
        Get-ItemSize $item
    }
}

$results = $results |
    Where-Object { ($_.SizeBytes / 1MB) -ge $MinSizeMB } |
    ForEach-Object {
        $size = Convert-Size -Bytes $_.SizeBytes -Unit $Unit
        [PSCustomObject]@{
            Size = $size.Value
            Unit = $size.Unit
            Path = $_.Path
        }
    }

# ---------- Sort ----------
switch ($Sort) {
    "Asc"  { $results = $results | Sort-Object Size }
    "Desc" { $results = $results | Sort-Object Size -Descending }
}

# ---------- Export ----------
if ($ExportCSV)  { $results | Export-Csv "$ExportPath.csv" -NoTypeInformation }
if ($ExportJSON) { $results | ConvertTo-Json -Depth 3 | Out-File "$ExportPath.json" }
if ($ExportTXT)  { $results | Out-File "$ExportPath.txt" }

# ---------- Display ----------
if ($OutputMode -ne "Quiet") { $results }
