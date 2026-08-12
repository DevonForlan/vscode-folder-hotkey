Add-Type -AssemblyName System.Windows.Forms

Add-Type @"
using System;
using System.Runtime.InteropServices;
public class Win32Focus {
    [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr hWnd);
    [DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr hWnd, int nCmdShow);
    [DllImport("user32.dll")] public static extern bool IsIconic(IntPtr hWnd);
    [DllImport("user32.dll")] public static extern IntPtr GetForegroundWindow();
    [DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr hWnd, out uint processId);
    [DllImport("user32.dll")] public static extern bool AttachThreadInput(uint idAttach, uint idAttachTo, bool fAttach);
    [DllImport("kernel32.dll")] public static extern uint GetCurrentThreadId();
    [DllImport("user32.dll")] public static extern void keybd_event(byte bVk, byte bScan, uint dwFlags, UIntPtr dwExtraInfo);
}
"@

function Force-ForegroundWindow {
    param($hwnd)
    if (-not $hwnd -or $hwnd -eq [IntPtr]::Zero) { return }

    # Tap Alt so Windows treats us as having just received input (bypasses the foreground lock)
    [Win32Focus]::keybd_event(0x12, 0, 0, [UIntPtr]::Zero)
    [Win32Focus]::keybd_event(0x12, 0, 2, [UIntPtr]::Zero)

    if ([Win32Focus]::IsIconic($hwnd)) {
        [Win32Focus]::ShowWindow($hwnd, 9)
    } else {
        [Win32Focus]::ShowWindow($hwnd, 6)
        Start-Sleep -Milliseconds 100
        [Win32Focus]::ShowWindow($hwnd, 9)
    }

    $fgWindow = [Win32Focus]::GetForegroundWindow()
    $fgThread = 0
    [void][Win32Focus]::GetWindowThreadProcessId($fgWindow, [ref]$fgThread)
    $curThread = [Win32Focus]::GetCurrentThreadId()
    [void][Win32Focus]::AttachThreadInput($fgThread, $curThread, $true)
    [Win32Focus]::SetForegroundWindow($hwnd)
    [void][Win32Focus]::AttachThreadInput($fgThread, $curThread, $false)
}

$dialog = New-Object System.Windows.Forms.FolderBrowserDialog
$dialog.Description = "Select a folder to open in VS Code"
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

    try {
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
    } catch {
        # Auto-terminal setup is a nice-to-have. If the folder isn't writable
        # (network share, permissions, etc.), still open VS Code below.
    }

    Start-Process "code" -ArgumentList @($targetFolder) -WindowStyle Hidden

    # code.cmd returns before the actual window exists/updates, and Windows
    # blocks this hidden background process from stealing foreground focus
    # by default - poll briefly for the matching window, then force it forward.
    $leafName = Split-Path -Leaf $targetFolder
    $deadline = (Get-Date).AddSeconds(8)
    $codeProc = $null
    while ((Get-Date) -lt $deadline) {
        $codeProc = Get-Process -Name "Code" -ErrorAction SilentlyContinue |
            Where-Object { $_.MainWindowTitle -like "*$leafName*" } |
            Select-Object -First 1
        if ($codeProc) { break }
        Start-Sleep -Milliseconds 400
    }

    if ($codeProc) {
        Force-ForegroundWindow -hwnd $codeProc.MainWindowHandle
    }
}
