param(
    # Daemon mode: stay resident, own the global hotkey, and handle every press
    # in this already-running process. Launching a fresh powershell.exe per
    # press costs ~500ms of interpreter startup no matter how fast the script
    # itself is; staying resident removes that entirely.
    [switch]$Daemon,

    # Hotkey used in daemon mode. Modifiers are fixed at Ctrl+Shift+Alt; this
    # is just the letter.
    [string]$HotkeyLetter = "O"
)

Add-Type -AssemblyName System.Windows.Forms

# Must run before any window is created. In daemon mode the hidden hotkey
# window is created at startup, so this cannot live inside the picker function.
[System.Windows.Forms.Application]::EnableVisualStyles()

# Errors raised inside a WinForms event handler are swallowed by the message
# loop, which would leave a daemon that silently does nothing on every press.
# Record them instead.
$script:ErrorLogPath = Join-Path $env:TEMP "OpenFolderInVSCode-error.log"

function Write-ErrorLog {
    param([System.Management.Automation.ErrorRecord]$ErrorRecord)
    try {
        $lines = @(
            "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')  $($ErrorRecord.Exception.GetType().FullName): $($ErrorRecord.Exception.Message)"
            $ErrorRecord.ScriptStackTrace
            ''
        )
        $lines | Add-Content -LiteralPath $script:ErrorLogPath
    } catch { }
}

# Compiling inline C# costs ~900ms the first time in a process. In daemon mode
# that happens once at login; in one-shot mode it's deferred until after the
# folder is picked, so it overlaps VS Code's own startup instead of delaying
# the picker.
function Register-Win32FocusType {
    if ('Win32Focus' -as [type]) { return }
    Add-Type @"
using System;
using System.Text;
using System.Runtime.InteropServices;

public class Win32Focus {
    public delegate bool EnumWindowsProc(IntPtr hWnd, IntPtr lParam);

    [DllImport("user32.dll")] public static extern bool EnumWindows(EnumWindowsProc lpEnumFunc, IntPtr lParam);
    [DllImport("user32.dll")] public static extern int GetWindowText(IntPtr hWnd, StringBuilder lpString, int nMaxCount);
    [DllImport("user32.dll")] public static extern int GetWindowTextLength(IntPtr hWnd);
    [DllImport("user32.dll")] public static extern bool IsWindowVisible(IntPtr hWnd);
    [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr hWnd);
    [DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr hWnd, int nCmdShow);
    [DllImport("user32.dll")] public static extern bool IsIconic(IntPtr hWnd);
    [DllImport("user32.dll")] public static extern IntPtr GetForegroundWindow();
    [DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr hWnd, out uint processId);
    [DllImport("user32.dll")] public static extern bool AttachThreadInput(uint idAttach, uint idAttachTo, bool fAttach);
    [DllImport("kernel32.dll")] public static extern uint GetCurrentThreadId();
    [DllImport("user32.dll")] public static extern void keybd_event(byte bVk, byte bScan, uint dwFlags, UIntPtr dwExtraInfo);
    [DllImport("user32.dll")] public static extern void SwitchToThisWindow(IntPtr hWnd, bool fAltTab);
    [DllImport("user32.dll")] public static extern bool BringWindowToTop(IntPtr hWnd);

    // Process.MainWindowHandle only ever exposes one window per process and
    // misses the rest when several VS Code windows are open - enumerate every
    // real top-level window instead.
    public static IntPtr FindWindow(string titleSubstring, string processName) {
        IntPtr found = IntPtr.Zero;
        EnumWindows(delegate(IntPtr hWnd, IntPtr lParam) {
            if (!IsWindowVisible(hWnd)) return true;
            int len = GetWindowTextLength(hWnd);
            if (len == 0) return true;
            StringBuilder sb = new StringBuilder(len + 1);
            GetWindowText(hWnd, sb, sb.Capacity);
            if (sb.ToString().IndexOf(titleSubstring, StringComparison.OrdinalIgnoreCase) < 0) return true;

            uint procId;
            GetWindowThreadProcessId(hWnd, out procId);
            try {
                if (System.Diagnostics.Process.GetProcessById((int)procId).ProcessName.Equals(processName, StringComparison.OrdinalIgnoreCase)) {
                    found = hWnd;
                    return false;
                }
            } catch { }
            return true;
        }, IntPtr.Zero);
        return found;
    }
}
"@
}

function Focus-VSCodeWindow {
    param([string]$LeafName)

    # Code.exe returns before its window exists or its title updates, so poll.
    $hwnd = [IntPtr]::Zero
    $deadline = (Get-Date).AddSeconds(8)
    while ((Get-Date) -lt $deadline) {
        $hwnd = [Win32Focus]::FindWindow($LeafName, "Code")
        if ($hwnd -ne [IntPtr]::Zero) { break }
        Start-Sleep -Milliseconds 200
    }
    if ($hwnd -eq [IntPtr]::Zero) { return }

    if ([Win32Focus]::IsIconic($hwnd)) { [Win32Focus]::ShowWindow($hwnd, 9) }

    # Windows blocks background processes from stealing focus, so this needs
    # several tricks together, retried a few times.
    for ($attempt = 0; $attempt -lt 4; $attempt++) {
        if ([Win32Focus]::GetForegroundWindow() -eq $hwnd) { break }

        # Tap Alt so Windows treats us as having just received input.
        [Win32Focus]::keybd_event(0x12, 0, 0, [UIntPtr]::Zero)
        [Win32Focus]::keybd_event(0x12, 0, 2, [UIntPtr]::Zero)

        [Win32Focus]::ShowWindow($hwnd, 6)
        Start-Sleep -Milliseconds 80
        [Win32Focus]::ShowWindow($hwnd, 9)

        $fgThread = 0
        [void][Win32Focus]::GetWindowThreadProcessId([Win32Focus]::GetForegroundWindow(), [ref]$fgThread)
        $curThread = [Win32Focus]::GetCurrentThreadId()
        [void][Win32Focus]::AttachThreadInput($fgThread, $curThread, $true)

        [void][Win32Focus]::BringWindowToTop($hwnd)
        [Win32Focus]::SwitchToThisWindow($hwnd, $true)
        [void][Win32Focus]::SetForegroundWindow($hwnd)

        [void][Win32Focus]::AttachThreadInput($fgThread, $curThread, $false)

        Start-Sleep -Milliseconds 150
    }
}

function Set-AutoTerminalTask {
    param([string]$TargetFolder)

    $vscodeDir = Join-Path $TargetFolder ".vscode"
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
}

function Invoke-OpenFolderInVSCode {
    $dialog = New-Object System.Windows.Forms.FolderBrowserDialog
    $dialog.Description = "Select a folder to open in VS Code"
    $dialog.ShowNewFolderButton = $true

    # The daemon owns no visible window, so an unowned dialog opens *behind*
    # whatever the user is looking at - it appears not to have worked at all.
    # Give it a 1x1 off-screen top-most owner and push that to the foreground
    # first; the dialog then comes up with it. Windows permits the foreground
    # change here because this process just received the hotkey.
    $owner = New-Object System.Windows.Forms.Form
    $owner.StartPosition = [System.Windows.Forms.FormStartPosition]::Manual
    $owner.Left = -32000
    $owner.Top = -32000
    $owner.Width = 1
    $owner.Height = 1
    $owner.ShowInTaskbar = $false
    $owner.TopMost = $true

    try {
        $owner.Show()
        $owner.Activate()

        # Only available once the C# helper is compiled - true in daemon mode
        # (compiled at startup). In one-shot mode it isn't compiled yet, and
        # deliberately isn't compiled here: that costs ~900ms and would delay
        # the picker, which a normally-launched process doesn't need anyway.
        if ('Win32Focus' -as [type]) {
            [void][Win32Focus]::SetForegroundWindow($owner.Handle)
        }

        $result = $dialog.ShowDialog($owner)
    }
    finally {
        $owner.Close()
        $owner.Dispose()
    }

    if ($result -ne [System.Windows.Forms.DialogResult]::OK) { return }
    $targetFolder = $dialog.SelectedPath

    # Auto-terminal setup is a nice-to-have. If the folder isn't writable
    # (network share, permissions, etc.), still open VS Code below.
    try { Set-AutoTerminalTask -TargetFolder $targetFolder } catch {}

    # Windows PowerShell 5.1's Start-Process does not reliably quote array
    # elements containing spaces, so a path like "OneDrive - Company Name\..."
    # gets split into multiple broken arguments. Quote it ourselves instead.
    Start-Process "code" -ArgumentList "`"$targetFolder`"" -WindowStyle Hidden

    # No-op in daemon mode (already compiled at startup); in one-shot mode this
    # runs while VS Code is starting, so its cost overlaps that wait.
    Register-Win32FocusType

    Focus-VSCodeWindow -LeafName (Split-Path -Leaf $targetFolder)
}

if (-not $Daemon) {
    Invoke-OpenFolderInVSCode
    return
}

# ---------------- daemon mode ----------------

# Only one daemon may own the hotkey at a time. Held in a script-scope variable
# so the mutex isn't garbage collected (which would release it) while we run.
$script:DaemonMutex = New-Object System.Threading.Mutex($false, "OpenFolderInVSCodeDaemon")
$acquired = $false
try { $acquired = $script:DaemonMutex.WaitOne(0) }
catch [System.Threading.AbandonedMutexException] { $acquired = $true }
if (-not $acquired) { return }

# Pay the inline-C# compile cost once, now, rather than on the first hotkey press.
Register-Win32FocusType

Add-Type -ReferencedAssemblies System.Windows.Forms -TypeDefinition @"
using System;
using System.Runtime.InteropServices;
using System.Windows.Forms;

// A window that never becomes visible, existing only to receive WM_HOTKEY.
public class HotkeyWindow : Form {
    [DllImport("user32.dll")] static extern bool RegisterHotKey(IntPtr hWnd, int id, uint fsModifiers, uint vk);
    [DllImport("user32.dll")] static extern bool UnregisterHotKey(IntPtr hWnd, int id);

    const int WM_HOTKEY = 0x0312;
    const int HOTKEY_ID = 1;

    public event EventHandler HotkeyPressed;

    protected override void SetVisibleCore(bool value) {
        // Force handle creation without ever showing the window.
        if (!this.IsHandleCreated) this.CreateHandle();
        base.SetVisibleCore(false);
    }

    public bool Register(uint modifiers, uint virtualKey) {
        return RegisterHotKey(this.Handle, HOTKEY_ID, modifiers, virtualKey);
    }

    protected override void WndProc(ref Message m) {
        if (m.Msg == WM_HOTKEY) {
            EventHandler handler = HotkeyPressed;
            if (handler != null) handler(this, EventArgs.Empty);
        }
        base.WndProc(ref m);
    }

    protected override void Dispose(bool disposing) {
        if (disposing && this.IsHandleCreated) UnregisterHotKey(this.Handle, HOTKEY_ID);
        base.Dispose(disposing);
    }
}
"@

$MOD_ALT = 0x0001
$MOD_CONTROL = 0x0002
$MOD_SHIFT = 0x0004
$MOD_NOREPEAT = 0x4000   # don't re-fire while the key is held down

$modifiers = $MOD_ALT -bor $MOD_CONTROL -bor $MOD_SHIFT -bor $MOD_NOREPEAT
$virtualKey = [int][char]($HotkeyLetter.ToUpperInvariant())

$window = New-Object HotkeyWindow
$null = $window.Handle   # force the handle to exist before registering

if (-not $window.Register($modifiers, $virtualKey)) {
    # Almost always means something else already owns this combination - most
    # likely a Start Menu shortcut still carrying the same "Shortcut key".
    [System.Windows.Forms.MessageBox]::Show(
        "Could not register the hotkey Ctrl+Shift+Alt+$HotkeyLetter.`n`nAnother application (or a Start Menu shortcut with the same 'Shortcut key') already owns it.",
        "Open Folder in VS Code") | Out-Null
    return
}

$window.add_HotkeyPressed({
    try { Invoke-OpenFolderInVSCode }
    catch { Write-ErrorLog -ErrorRecord $_ }
})

[System.Windows.Forms.Application]::Run((New-Object System.Windows.Forms.ApplicationContext))

# Keeps the mutex referenced (and therefore held) for the daemon's whole life.
$script:DaemonMutex.ReleaseMutex()
