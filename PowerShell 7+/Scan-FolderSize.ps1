<#
.SYNOPSIS
Calculates folder sizes at a specific directory depth with optional parallel processing
and adaptive thread control based on disk I/O load.

.DESCRIPTION
This script scans subfolders at a specified depth ("floor") under a base path and
calculates the total size of each folder. It supports parallel execution to improve
performance and can dynamically adjust the number of parallel threads based on the
current disk I/O queue length.

Results can be filtered by minimum size, sorted, displayed in different units,
and exported to CSV, JSON, or TXT formats.

.PARAMETER Path
The base directory path to scan. This path is resolved to an absolute path before processing.

.PARAMETER Floor
The directory depth (relative to the base path) to evaluate.
For example, Floor 1 refers to immediate subdirectories of Path.

.PARAMETER MinSizeMB
Minimum folder size (in MB) required to be included in the results.
Default is 0 (no filtering).

.PARAMETER Unit
Output size unit. Supported values are MB, GB, and TB.
Default is MB.

.PARAMETER Sort
Sort the results by folder size.

.PARAMETER Desc
Sort results in descending order. Only effective when -Sort is specified.

.PARAMETER OutCsv
Exports results to a CSV file at the specified path.

.PARAMETER OutJson
Exports results to a JSON file at the specified path.

.PARAMETER OutTxt
Exports results to a formatted text file at the specified path.

.PARAMETER Quiet
Suppresses progress and console output. Export options are still honored.

.PARAMETER Directory
Specifies that only directories (folders) should be returned.

.PARAMETER File
Specifies that only files should be returned.

.PARAMETER Shallow
Disables recursive folder enumeration. Only direct child folders are considered.

.PARAMETER DynamicThreads
Enables dynamic adjustment of parallel thread count based on disk I/O queue length.

.PARAMETER MinThreads
Minimum number of parallel threads when DynamicThreads is enabled.
Default is 1.

.PARAMETER MaxThreads
Maximum number of parallel threads.
Default is 16.

.PARAMETER BatchSize
Number of folders processed per batch.
If not specified, defaults to MaxThreads * 2.

.PARAMETER QueueHigh
Upper threshold of disk average queue length.
If exceeded, the number of threads is reduced.
Default is 2.0.

.PARAMETER QueueLow
Lower threshold of disk average queue length.
If below this value, the number of threads may be increased.
Default is 1.0.

.EXAMPLE
.\Scan-FolderSize.ps1 -Path C:\Data -Floor 2

Calculates sizes of folders at depth 2 under C:\Data and displays results in MB.

.EXAMPLE
.\Scan-FolderSize.ps1 -Path D:\Share -Floor 1 -MinSizeMB 500 -Unit GB -Sort -Desc

Lists first-level subfolders larger than 500 MB, displays size in GB,
and sorts results in descending order.

.EXAMPLE
.\Scan-FolderSize.ps1 -Path E:\Logs -Floor 3 -DynamicThreads -OutCsv result.csv

Scans third-level folders using adaptive parallelism and exports results to CSV.

.NOTES
Requires PowerShell 7 or later for ForEach-Object -Parallel support.

Disk I/O load is measured using the performance counter:
\PhysicalDisk(_Total)\Avg. Disk Queue Length

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
    [switch]$Directory,
    [switch]$File,
    [switch]$Shallow,

    [switch]$DynamicThreads,

    [int]$MinThreads = 1,
    [int]$MaxThreads = 16,

    [int]$BatchSize,

    [double]$QueueHigh = 2.0,
    [double]$QueueLow  = 1.0
)

# ---------- Resolve ----------
$BasePath  = (Resolve-Path $Path).Path
$BaseDepth = ($BasePath -split '[\\/]').Count

if (-not $BatchSize) {
    $BatchSize = $MaxThreads * 2
}

# ---------- Get folders ----------
$FolderParams = @{ LiteralPath = $BasePath }
if ($Directory) { $FolderParams.Directory = $true }
if ($File) { $FolderParams.File = $true }
if (-not $Shallow) { $FolderParams.Recurse = $true }

$Folders = Get-ChildItem @FolderParams | Where-Object {
    (($_.FullName -split '[\\/]').Count - $BaseDepth) -le $Floor
}

if ($Folders.Count -eq 0) {
    Write-Warning "No folders found at floor $Floor"
    return
}

# ---------- Helper: Get Disk Queue ----------
function Get-DiskQueue {
    try {
        (Get-Counter '\PhysicalDisk(_Total)\Avg. Disk Queue Length' `
            -SampleInterval 1 -MaxSamples 1).CounterSamples.CookedValue
    } catch {
        return 0
    }
}

# ---------- Processing ----------
$Results = @()
$Threads = $MaxThreads

for ($i = 0; $i -lt $Folders.Count; $i += $BatchSize) {

    if ($DynamicThreads) {

        $Queue = Get-DiskQueue

        if ($Queue -gt $QueueHigh) {
            $Threads = [math]::Max($Threads - 1, $MinThreads)
        }
        elseif ($Queue -lt $QueueLow) {
            $Threads = [math]::Min($Threads + 1, $MaxThreads)
        }

        if (-not $Quiet) {
            Write-Host ("[IO Queue={0:N2}] Threads={1}" -f $Queue, $Threads) `
                -ForegroundColor Cyan
        }
    }

    $Batch = $Folders[$i..([math]::Min($i + $BatchSize - 1, $Folders.Count - 1))]

    $BatchResults = $Batch | ForEach-Object -Parallel {

        $Folder     = $_
        $MinSizeMB  = $using:MinSizeMB
        $Unit       = $using:Unit

        $SizeBytes = (
            Get-ChildItem -LiteralPath $Folder.FullName -Recurse -File `
                -ErrorAction SilentlyContinue |
            Measure-Object Length -Sum
        ).Sum

        if (-not $SizeBytes) { $SizeBytes = 0 }

        $SizeMB = [math]::Round($SizeBytes / 1MB, 2)
        if ($SizeMB -lt $MinSizeMB) { return }

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

    } -ThrottleLimit $Threads

    $Results += $BatchResults
}

# ---------- Sort ----------
if ($Sort) {
    $Results = $Results | Sort-Object Size -Descending:$Desc
}

# ---------- Export ----------
if ($OutCsv)  { $Results | Export-Csv $OutCsv -NoTypeInformation -Encoding UTF8 }
if ($OutJson) { $Results | ConvertTo-Json -Depth 3 | Out-File $OutJson }
if ($OutTxt)  {
    $Results | Format-Table Size,Unit,Path -AutoSize |
        Out-String | Out-File $OutTxt
}

# ---------- Display ----------
if (-not $Quiet) {
    $Results | Format-Table Size, Unit, Path -AutoSize
}
