Add-Type -AssemblyName System.Windows.Forms

$dialog = New-Object System.Windows.Forms.FolderBrowserDialog
$dialog.Description = "選擇要在 VS Code 開啟的資料夾"
$dialog.ShowNewFolderButton = $true

[System.Windows.Forms.Application]::EnableVisualStyles()

if ($dialog.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
    $targetFolder = $dialog.SelectedPath
    $vscodeDir = Join-Path $targetFolder ".vscode"
    $tasksPath = Join-Path $vscodeDir "tasks.json"
    $taskLabel = "Open Terminal Here"

    $autoTerminalTask = [ordered]@{
        label = $taskLabel
        type = "shell"
        command = "powershell"
        options = [ordered]@{ cwd = '${workspaceFolder}' }
        runOptions = [ordered]@{ runOn = "folderOpen" }
        presentation = [ordered]@{
            reveal = "always"
            panel = "new"
            focus = $true
        }
        problemMatcher = @()
    }

    if (Test-Path $tasksPath) {
        $existing = $null
        try { $existing = Get-Content $tasksPath -Raw | ConvertFrom-Json } catch {}
        if ($existing -and $existing.tasks) {
            $hasTask = $existing.tasks | Where-Object { $_.label -eq $taskLabel }
            if (-not $hasTask) {
                $existing.tasks = @($existing.tasks) + $autoTerminalTask
                $existing | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $tasksPath -Encoding UTF8
            }
        }
    } else {
        New-Item -ItemType Directory -Path $vscodeDir -Force | Out-Null
        $tasksJson = [ordered]@{
            version = "2.0.0"
            tasks = @($autoTerminalTask)
        }
        $tasksJson | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $tasksPath -Encoding UTF8
    }

    Start-Process "code" -ArgumentList @($targetFolder) -WindowStyle Hidden
}
