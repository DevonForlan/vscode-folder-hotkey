param(
    [string]$Hotkey = "CTRL+SHIFT+ALT+O"
)

$repoRoot = $PSScriptRoot
$vbsPath = Join-Path $repoRoot "OpenFolderInVSCode.vbs"

if (-not (Test-Path $vbsPath)) {
    Write-Error "找不到 $vbsPath，請確認 install.ps1 與 OpenFolderInVSCode.vbs 在同一個資料夾。"
    exit 1
}

if (-not (Get-Command code -ErrorAction SilentlyContinue)) {
    Write-Warning "在 PATH 中找不到 'code' 指令。請先安裝 VS Code，並在安裝時勾選「加入 PATH」，或手動將 VS Code 的 bin 目錄加入 PATH。"
}

# 1. 建立 Start Menu 捷徑並設定快速鍵
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

Write-Output "已建立捷徑並設定快速鍵：$Hotkey"
Write-Output "捷徑位置：$shortcutPath"

# 2. 允許 VS Code 自動執行 tasks.json 中 runOn: folderOpen 的工作（用於自動開終端機），避免每個新資料夾都跳確認視窗
$vsSettingsPath = Join-Path $env:APPDATA "Code\User\settings.json"
if (Test-Path $vsSettingsPath) {
    try {
        $settings = Get-Content $vsSettingsPath -Raw | ConvertFrom-Json
        if (-not ($settings.PSObject.Properties.Name -contains "task.allowAutomaticTasks")) {
            $settings | Add-Member -NotePropertyName "task.allowAutomaticTasks" -NotePropertyValue "on"
            $settings | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $vsSettingsPath -Encoding UTF8
            Write-Output "已在 VS Code 使用者設定中加入 task.allowAutomaticTasks: on"
        } else {
            Write-Output "VS Code 設定中已有 task.allowAutomaticTasks，未變更。"
        }
    } catch {
        Write-Warning "無法自動修改 VS Code settings.json（可能含註解或格式異常），請手動加入：`"task.allowAutomaticTasks`": `"on`""
    }
} else {
    Write-Warning "找不到 VS Code 使用者設定檔（$vsSettingsPath），略過此步驟。"
}

Write-Output ""
Write-Output "安裝完成！按下 $Hotkey 即可開啟資料夾選擇視窗並用 VS Code 開啟。"
