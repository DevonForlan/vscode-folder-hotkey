param(
    [string]$Hotkey = "CTRL+SHIFT+ALT+O"
)

$repoRoot = $PSScriptRoot
$vbsPath = Join-Path $repoRoot "OpenFolderInVSCode.vbs"

if (-not (Test-Path $vbsPath)) {
    Write-Error "Could not find $vbsPath. Make sure install.ps1 and OpenFolderInVSCode.vbs are in the same folder."
    exit 1
}

if (-not (Get-Command code -ErrorAction SilentlyContinue)) {
    Write-Warning "Could not find the 'code' command on PATH. Install VS Code with 'Add to PATH' enabled, or add the VS Code bin directory to PATH manually."
}

# 1. Create the Start Menu shortcut and set its hotkey
$shortcutPath = Join-Path $env:APPDATA "Microsoft\Windows\Start Menu\Programs\Open Folder in VS Code.lnk"
$WshShell = New-Object -ComObject WScript.Shell
$Shortcut = $WshShell.CreateShortcut($shortcutPath)
$Shortcut.TargetPath = Join-Path $env:SystemRoot "System32\wscript.exe"
$Shortcut.Arguments = "`"$vbsPath`""
$Shortcut.WorkingDirectory = $repoRoot
$Shortcut.WindowStyle = 7

$codeExe = (Get-Command code -ErrorAction SilentlyContinue).Source
if ($codeExe) {
    $codeDir = Split-Path (Split-Path $codeExe -Parent) -Parent
    $iconPath = Join-Path $codeDir "Code.exe"
    if (Test-Path $iconPath) { $Shortcut.IconLocation = "$iconPath,0" }
}

$Shortcut.Hotkey = $Hotkey
$Shortcut.Description = "Open Folder in VS Code"
$Shortcut.Save()

Write-Output "Shortcut created with hotkey: $Hotkey"
Write-Output "Shortcut location: $shortcutPath"

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
Write-Output "Install complete! Press $Hotkey to open the folder picker and launch VS Code."
