# vscode-folder-hotkey

Press a global hotkey, pick a folder from a native picker, and it opens directly in VS Code with an integrated terminal already open at the right path. Windows only.

## Features

- Press the hotkey (default `Ctrl+Shift+Alt+O`) → a native "Browse For Folder" dialog pops up
- Pick a folder → VS Code opens it
- Automatically writes a `.vscode/tasks.json` in that folder (`runOn: folderOpen`), so opening it in VS Code also opens an integrated terminal already `cd`'d into that folder
- If the folder already has a `tasks.json`, it's not overwritten — the task is merged in, and running it again won't add a duplicate

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
- The shortcut points at `OpenFolderInVSCode.vbs`, run hidden via `wscript.exe`, to avoid flashing a console window
- The `.vbs` calls `OpenFolderInVSCode.ps1` with a hidden window: it shows the folder picker, then runs `code <folder>`
- `install.ps1` also turns on `task.allowAutomaticTasks` in your VS Code user settings, so opening a new folder never prompts you to confirm the automatic task. If you'd rather keep that confirmation, revert the setting — VS Code will ask once per folder and remember your choice

## Uninstall

1. Delete the shortcut: `%APPDATA%\Microsoft\Windows\Start Menu\Programs\Open Folder in VS Code.lnk`
2. (Optional) Remove `task.allowAutomaticTasks` from your VS Code user settings
