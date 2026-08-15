# vscode-folder-hotkey

Press a global hotkey, pick a folder from a native picker, and it opens directly in VS Code with an integrated terminal already open at the right path. Windows only.

## Features

- Press the hotkey (default `Ctrl+Shift+Alt+O`) → a native "Browse For Folder" dialog pops up
- Pick a folder → VS Code opens it
- Automatically writes a `.vscode/tasks.json` in that folder (`runOn: folderOpen`), so opening it in VS Code also opens an integrated terminal already `cd`'d into that folder
- If the folder already has a `tasks.json`, it's not overwritten — the task is merged in, and running it again won't add a duplicate
- Forces the new VS Code window to the foreground even though Windows normally blocks background processes from stealing focus

## Install

Requirements: Windows, and VS Code's `code` command available on PATH (enabled by default when installing VS Code).

```powershell
git clone https://github.com/<your-username>/vscode-folder-hotkey.git
cd vscode-folder-hotkey
./install.ps1
```

Defaults to `Ctrl+Shift+Alt+O`. You can set a different hotkey:

```powershell
./install.ps1 -Hotkey "CTRL+ALT+O"
```

## Why three modifier keys by default?

Two-modifier combos like `Ctrl+Alt+<letter>` are commonly intercepted by Chinese IMEs (e.g. New Phonetic, Microsoft Pinyin) through their own keyboard hooks, so the hotkey silently does nothing. A three-modifier combo (`Ctrl+Shift+Alt+<letter>`) collides with IME shortcuts far less often. If you don't use a Chinese IME, feel free to use a two-key combo instead.

## How it works

- `install.ps1` creates a shortcut under Start Menu \ Programs and sets its "Shortcut key" property — a built-in Windows global-hotkey mechanism, no extra software required
- The shortcut runs `powershell.exe -WindowStyle Hidden -File OpenFolderInVSCode.ps1`: it shows the folder picker, then runs `code <folder>` and forces that window to the foreground
- `install.ps1` also turns on `task.allowAutomaticTasks` in your VS Code user settings, so opening a new folder never prompts you to confirm the automatic task. If you'd rather keep that confirmation, revert the setting — VS Code will ask once per folder and remember your choice

## Performance

Measured on a corporate Windows 11 machine with endpoint security software, hotkey press → folder picker visible:

| Version | Time |
|---|---|
| Original (`wscript.exe` → `.vbs` → hidden `powershell.exe`) | ~3.7s |
| Current (shortcut → `powershell.exe` directly) | ~0.5–1.1s |

Two things mattered, and one thing that sounds obvious didn't:

- **Dropping the `.vbs`/`wscript.exe` wrapper was the big win.** It existed only to hide the console window, which `powershell.exe -WindowStyle Hidden` already does. That chain — VBScript silently spawning a hidden PowerShell — is a classic malware pattern, so security software inspects it heavily; removing it cut roughly 3 seconds.
- **Deferring `Add-Type`.** The foreground-focus workaround needs a small C# type compiled at runtime, which costs ~900ms on first use per process. It now compiles *after* you've picked a folder, overlapping with VS Code's own startup instead of delaying the picker.
- **Rewriting the whole thing as a compiled `.exe` made it worse, not better.** In theory a .NET exe starts in ~50ms versus PowerShell's ~500ms. Measured on the same machine, the freshly compiled unsigned exe took **2.5–3.4s per launch** — antivirus scans unsigned executables in user-writable locations on every run, and that cost dwarfed the startup savings. Reverted.

What remains (~500ms) is essentially `powershell.exe` startup itself, which no script-level change can avoid.

## Uninstall

1. Delete the shortcut: `%APPDATA%\Microsoft\Windows\Start Menu\Programs\Open Folder in VS Code.lnk`
2. (Optional) Remove `task.allowAutomaticTasks` from your VS Code user settings
