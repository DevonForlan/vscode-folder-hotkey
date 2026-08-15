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
./install.ps1 -HotkeyLetter "P"
```

## Why three modifier keys by default?

Two-modifier combos like `Ctrl+Alt+<letter>` are commonly intercepted by Chinese IMEs (e.g. New Phonetic, Microsoft Pinyin) through their own keyboard hooks, so the hotkey silently does nothing. A three-modifier combo (`Ctrl+Shift+Alt+<letter>`) collides with IME shortcuts far less often. If you don't use a Chinese IME, feel free to use a two-key combo instead.

## How it works

- `install.ps1` puts a shortcut in your Startup folder that launches `OpenFolderInVSCode.ps1 -Daemon` at login. The daemon is a hidden, resident process that claims the hotkey with the Win32 `RegisterHotKey` API and handles every press in-process
- On a press it shows the folder picker, writes `.vscode/tasks.json` if needed, runs `code <folder>`, and forces that window to the foreground
- It also installs a Start Menu shortcut as a manual launcher. That shortcut deliberately has **no** "Shortcut key" set — only one thing can own a given key combination, and the daemon owns it
- `install.ps1` also turns on `task.allowAutomaticTasks` in your VS Code user settings, so opening a new folder never prompts you to confirm the automatic task. If you'd rather keep that confirmation, revert the setting — VS Code will ask once per folder and remember your choice

## Performance

Measured on a corporate Windows 11 machine with endpoint security software, hotkey press → folder picker visible:

| Version | Time |
|---|---|
| Original (`wscript.exe` → `.vbs` → hidden `powershell.exe`) | ~3.7s |
| Shortcut → `powershell.exe` directly | ~0.5–1.1s |
| Resident daemon (current) | effectively instant |

Getting here took three changes and one measured dead end:

- **Dropping the `.vbs`/`wscript.exe` wrapper.** It existed only to hide the console window, which `powershell.exe -WindowStyle Hidden` already does. That chain — VBScript silently spawning a hidden PowerShell — is a classic malware pattern, so security software inspects it heavily; removing it cut roughly 3 seconds.
- **Deferring `Add-Type`.** The foreground-focus workaround needs a small C# type compiled at runtime, ~900ms on first use per process. In one-shot mode it now compiles *after* you pick a folder, overlapping VS Code's startup; in daemon mode it's compiled once at login.
- **Going resident.** Even a perfectly optimized script can't avoid `powershell.exe`'s own ~500ms startup when a new process is spawned per keypress. The daemon pays that once at login instead.
- **Dead end: rewriting it as a compiled `.exe`.** In theory a .NET exe starts in ~50ms versus PowerShell's ~500ms. Measured on the same machine, the freshly compiled unsigned exe took **2.5–3.4s per launch** — antivirus rescans unsigned executables in user-writable locations on every run, dwarfing the startup savings. Reverted.

### Gotchas found while building the daemon

Two bugs here produced the same symptom — "pressing the hotkey does nothing" — for completely different reasons, and both are easy to hit again:

- **A dialog with no owner window opens behind everything.** The daemon has no visible window of its own, so the picker was appearing instantly but underneath whatever the user was looking at. It now shows the dialog owned by a 1×1 off-screen top-most form that is pushed to the foreground first. (A process that just received a registered hotkey is permitted to take the foreground, which is what makes this work.)
- **Exceptions inside a WinForms event handler are swallowed by the message loop.** A daemon that throws on every press looks identical to one whose hotkey never registered. The handler now logs failures to `%TEMP%\OpenFolderInVSCode-error.log`. The original throw was `Application.EnableVisualStyles()` being called after a window already existed — it now runs once at the top of the script, before anything is created.

### Tradeoffs of the daemon

- One resident `powershell.exe`, roughly 40–60MB of RAM
- If it's killed, the hotkey stops working until you log in again or re-run the Startup shortcut
- One-shot mode still works: running `OpenFolderInVSCode.ps1` with no arguments does a single pick-and-open, no daemon involved

## Uninstall

1. Delete the Startup shortcut: `%APPDATA%\Microsoft\Windows\Start Menu\Programs\Startup\Open Folder in VS Code (hotkey daemon).lnk`
2. Stop the running daemon (it's the `powershell.exe` whose command line contains `-Daemon`), or just log out
3. Delete the Start Menu shortcut: `%APPDATA%\Microsoft\Windows\Start Menu\Programs\Open Folder in VS Code.lnk`
4. (Optional) Remove `task.allowAutomaticTasks` from your VS Code user settings
