param(
    [string]$Before,
    [string]$After
)

# With no paths given, compare the two most recent dumps in %TEMP% - the
# common case is "just ran Dump-Environment.ps1 in two terminals, now diff
# them" without having to go find the filenames.
if (-not $Before -or -not $After) {
    $recent = Get-ChildItem (Join-Path $env:TEMP "OpenFolderInVSCode-env-*.txt") |
        Sort-Object LastWriteTime -Descending |
        Select-Object -First 2
    if ($recent.Count -lt 2) {
        Write-Error "Need at least two dumps in `$env:TEMP (found $($recent.Count)). Run Dump-Environment.ps1 in each terminal first, or pass -Before/-After explicitly."
        exit 1
    }
    # Older of the two most-recent files first, so output reads task-then-manual
    # or whichever order they were actually captured in.
    $After = $recent[0].FullName
    $Before = $recent[1].FullName
}

Write-Output "Before: $Before"
Write-Output "After:  $After"
Write-Output ""

function Read-EnvDump {
    param([string]$Path)
    $map = [ordered]@{}
    $meta = @()
    foreach ($line in Get-Content -LiteralPath $Path) {
        if ($line -match '^#') { $meta += $line; continue }
        if (-not $line) { continue }
        $idx = $line.IndexOf('=')
        if ($idx -gt 0) {
            $map[$line.Substring(0, $idx)] = $line.Substring($idx + 1)
        }
    }
    return @{ Vars = $map; Meta = $meta }
}

$beforeDump = Read-EnvDump -Path $Before
$afterDump = Read-EnvDump -Path $After

Write-Output "--- Metadata (PID/PSVersion/TTY state) ---"
Write-Output "Before:"
$beforeDump.Meta | ForEach-Object { Write-Output "  $_" }
Write-Output "After:"
$afterDump.Meta | ForEach-Object { Write-Output "  $_" }
Write-Output ""

Write-Output "--- Environment variable differences ---"
$allKeys = @($beforeDump.Vars.Keys) + @($afterDump.Vars.Keys) | Sort-Object -Unique
$anyDiff = $false
foreach ($key in $allKeys) {
    $b = $beforeDump.Vars[$key]
    $a = $afterDump.Vars[$key]
    if ($b -eq $a) { continue }
    $anyDiff = $true
    if ($null -eq $b) {
        Write-Output "+ $key = $a"
    } elseif ($null -eq $a) {
        Write-Output "- $key = $b"
    } else {
        Write-Output "~ $key"
        Write-Output "    before: $b"
        Write-Output "    after:  $a"
    }
}
if (-not $anyDiff) {
    Write-Output "(no differences)"
}
