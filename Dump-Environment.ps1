param(
    # Distinguishes which terminal a dump came from, e.g. "task" (the
    # auto-created runOn:folderOpen terminal) vs "manual" (Terminal > New
    # Terminal). Purely a filename label.
    [string]$Label = "manual"
)

$dumpPath = Join-Path $env:TEMP "OpenFolderInVSCode-env-$Label-$(Get-Date -Format 'yyyyMMdd-HHmmss').txt"

# These dumps land in %TEMP% and have previously carried real secrets
# (e.g. CLOUDFLARE_API_TOKEN) verbatim - mask any variable whose NAME looks
# credential-shaped so the file is safe to leave lying around or paste
# elsewhere. This masks by name only, not by scanning values, so it won't
# catch a secret stashed in an oddly-named variable - don't treat an
# unmasked dump as a guarantee it's clean.
$secretNamePattern = 'TOKEN|SECRET|PASSWORD|PASS|KEY|AUTH|COOKIE|CREDENTIAL'
function Get-MaskedValue {
    param([string]$Name, [string]$Value)
    if ($Name -match $secretNamePattern) {
        if ([string]::IsNullOrEmpty($Value)) { return $Value }
        $hash = [System.BitConverter]::ToString(
            [System.Security.Cryptography.SHA256]::Create().ComputeHash([System.Text.Encoding]::UTF8.GetBytes($Value))
        ).Replace('-', '').Substring(0, 12)
        return "<masked, len=$($Value.Length), sha256[0:12]=$hash>"
    }
    return $Value
}

$lines = [System.Collections.Generic.List[string]]::new()

# --- Identity: PID, parent chain, host, cwd, TTY state ---
function Get-ParentChain {
    param([int]$StartPid)
    $chain = [System.Collections.Generic.List[string]]::new()
    $currentPid = $StartPid
    $depth = 0
    while ($currentPid -and $depth -lt 12) {
        $proc = Get-CimInstance Win32_Process -Filter "ProcessId=$currentPid" -ErrorAction SilentlyContinue
        if (-not $proc) {
            $chain.Add("  #$depth PID=$currentPid  (process exited / not found)")
            break
        }
        $chain.Add("  #$depth PID=$currentPid  Name=$($proc.Name)  CommandLine=$($proc.CommandLine)")
        if (-not $proc.ParentProcessId -or $proc.ParentProcessId -eq $currentPid) { break }
        $currentPid = $proc.ParentProcessId
        $depth++
    }
    return $chain
}

$lines.Add("# ==== Identity ====")
$lines.Add("# PID=$PID")
$lines.Add("# PWD (PowerShell)=$($PWD.Path)")
$lines.Add("# [Environment]::CurrentDirectory (.NET)=$([System.Environment]::CurrentDirectory)")
$lines.Add("# PSVersion=$($PSVersionTable.PSVersion)  Host=$($Host.Name)  HostVersion=$($Host.Version)")
$lines.Add("# StdinIsRedirected=$([Console]::IsInputRedirected)  StdoutIsRedirected=$([Console]::IsOutputRedirected)  StderrIsRedirected=$([Console]::IsErrorRedirected)")
$lines.Add("#")
$lines.Add("# Process parent chain (this process -> ... -> root):")
Get-ParentChain -StartPid $PID | ForEach-Object { $lines.Add("#$_") }
$lines.Add("")

# Two independent ways to read the environment, deliberately: PowerShell's
# Env: PSDrive provider vs .NET's own API straight to the OS. If these ever
# disagree, the difference is in PowerShell's own provider layer, not in
# what the OS actually handed this process - and any non-PowerShell child
# process (e.g. claude.exe/node) would see whatever the .NET/OS number says,
# not the Env: one.
$viaEnvDrive = @(Get-ChildItem Env: -ErrorAction SilentlyContinue)
$viaDotNet = [System.Environment]::GetEnvironmentVariables()
$lines.Add("# ==== Environment read-method comparison ====")
$lines.Add("# Env:-drive count=$($viaEnvDrive.Count)  [System.Environment]::GetEnvironmentVariables() count=$($viaDotNet.Count)")
$lines.Add("")

# --- Vars most likely to explain VS Code Task vs Terminal / Claude Code
# resume differences: put these up front, unmissable, sourced from the
# authoritative .NET dictionary regardless of whether Env: is broken here. ---
$interestingPrefixes = @('VSCODE', 'TERM', 'CLAUDE', 'SESSION')
$lines.Add("# ==== VSCODE_* / TERM* / CLAUDE* / SESSION* (via .NET API) ====")
$interestingNames = @($viaDotNet.Keys) | Where-Object {
    $name = $_
    $interestingPrefixes | Where-Object { $name -like "$_*" }
} | Sort-Object
if ($interestingNames.Count -eq 0) {
    $lines.Add("(none found)")
} else {
    foreach ($name in $interestingNames) {
        $lines.Add("$name=$(Get-MaskedValue -Name $name -Value $viaDotNet[$name])")
    }
}
$lines.Add("")

$lines.Add("# ==== Full environment (via .NET API; falls back to Env:-drive if that API is empty; credential-shaped names masked) ====")
if ($viaDotNet.Count -gt 0) {
    foreach ($name in ($viaDotNet.Keys | Sort-Object)) {
        $lines.Add("$name=$(Get-MaskedValue -Name $name -Value $viaDotNet[$name])")
    }
} else {
    $viaEnvDrive | Sort-Object Name | ForEach-Object { $lines.Add("$($_.Name)=$(Get-MaskedValue -Name $_.Name -Value $_.Value)") }
}

Set-Content -LiteralPath $dumpPath -Value $lines -Encoding UTF8
Write-Host "Environment dumped to $dumpPath"
