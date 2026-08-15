param(
    # Modifiers are fixed at Ctrl+Shift+Alt; this is just the letter.
    [string]$HotkeyLetter = "O"
)

$repoRoot = $PSScriptRoot
$scriptPath = Join-Path $repoRoot "OpenFolderInVSCode.ps1"

if (-not (Test-Path $scriptPath)) {
    Write-Error "Could not find $scriptPath. Make sure install.ps1 and OpenFolderInVSCode.ps1 are in the same folder."
    exit 1
}

if (-not (Get-Command code -ErrorAction SilentlyContinue)) {
    Write-Warning "Could not find the 'code' command on PATH. Install VS Code with 'Add to PATH' enabled, or add the VS Code bin directory to PATH manually."
}

$psExe = Join-Path $env:SystemRoot "System32\WindowsPowerShell\v1.0\powershell.exe"
$WshShell = New-Object -ComObject WScript.Shell

$codeExe = (Get-Command code -ErrorAction SilentlyContinue).Source
$iconPath = $null
if ($codeExe) {
    $candidate = Join-Path (Split-Path (Split-Path $codeExe -Parent) -Parent) "Code.exe"
    if (Test-Path $candidate) { $iconPath = $candidate }
}

# 1. Start Menu shortcut - a manual launcher only. It deliberately carries NO
# "Shortcut key": the resident daemon below owns the hotkey instead, and only
# one thing can own a given combination at a time.
$shortcutPath = Join-Path $env:APPDATA "Microsoft\Windows\Start Menu\Programs\Open Folder in VS Code.lnk"
$Shortcut = $WshShell.CreateShortcut($shortcutPath)
$Shortcut.TargetPath = $psExe
$Shortcut.Arguments = "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$scriptPath`""
$Shortcut.WorkingDirectory = $repoRoot
$Shortcut.WindowStyle = 7
$Shortcut.Hotkey = ""
$Shortcut.Description = "Open Folder in VS Code"
if ($iconPath) { $Shortcut.IconLocation = "$iconPath,0" }
$Shortcut.Save()

Write-Output "Start Menu shortcut created (manual launcher): $shortcutPath"

# 2. Startup shortcut for the resident hotkey daemon.
#
# Launching a fresh powershell.exe per keypress costs ~500ms of interpreter
# startup before any of this script runs, which is most of the perceived delay.
# The daemon starts once at login and handles every press in-process, so the
# picker appears immediately.
$startupDir = Join-Path $env:APPDATA "Microsoft\Windows\Start Menu\Programs\Startup"
$daemonLnkPath = Join-Path $startupDir "Open Folder in VS Code (hotkey daemon).lnk"
$daemonLnk = $WshShell.CreateShortcut($daemonLnkPath)
$daemonLnk.TargetPath = $psExe
$daemonLnk.Arguments = "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$scriptPath`" -Daemon -HotkeyLetter $HotkeyLetter"
$daemonLnk.WorkingDirectory = $repoRoot
$daemonLnk.WindowStyle = 7
$daemonLnk.Description = "Resident global hotkey listener for Open Folder in VS Code"
if ($iconPath) { $daemonLnk.IconLocation = "$iconPath,0" }
$daemonLnk.Save()

Write-Output "Startup shortcut created (hotkey daemon): $daemonLnkPath"

# 3. Start the daemon now so the hotkey works without waiting for a re-login.
Start-Process -FilePath $psExe -WindowStyle Hidden -ArgumentList @(
    "-NoProfile", "-ExecutionPolicy", "Bypass", "-WindowStyle", "Hidden",
    "-File", "`"$scriptPath`"", "-Daemon", "-HotkeyLetter", $HotkeyLetter
)
Write-Output "Hotkey daemon started (Ctrl+Shift+Alt+$HotkeyLetter)"

# 2. Allow VS Code to auto-run folderOpen tasks (used to auto-open the terminal), so new folders don't prompt for confirmation
$vsSettingsPath = Join-Path $env:APPDATA "Code\User\settings.json"
if (Test-Path $vsSettingsPath) {
    try {
        $settings = Get-Content $vsSettingsPath -Raw | ConvertFrom-Json
        if (-not ($settings.PSObject.Properties.Name -contains "task.allowAutomaticTasks")) {
            $settings | Add-Member -NotePropertyName "task.allowAutomaticTasks" -NotePropertyValue "on"
            $settings | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $vsSettingsPath -Encoding UTF8
            Write-Output "Added task.allowAutomaticTasks: on to VS Code user settings"
        } else {
            Write-Output "task.allowAutomaticTasks is already set in VS Code settings, left unchanged."
        }
    } catch {
        Write-Warning "Could not automatically edit VS Code settings.json (it may contain comments or invalid JSON). Please add manually: `"task.allowAutomaticTasks`": `"on`""
    }
} else {
    Write-Warning "Could not find the VS Code user settings file ($vsSettingsPath), skipping this step."
}

Write-Output ""
Write-Output "Install complete! Press Ctrl+Shift+Alt+$HotkeyLetter to open the folder picker and launch VS Code."
