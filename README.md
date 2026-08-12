# vscode-folder-hotkey

按一個全域快速鍵，跳出資料夾選擇視窗，選完直接用 VS Code 開啟該資料夾，並自動打開一個工作目錄正確的整合終端機。僅支援 Windows。

## 功能

- 按下快速鍵（預設 `Ctrl+Shift+Alt+O`）→ 跳出原生「瀏覽資料夾」視窗
- 選好資料夾 → VS Code 開啟該資料夾
- 自動在該資料夾寫入 `.vscode/tasks.json`（`runOn: folderOpen`），VS Code 開啟時會自動彈出一個位在該資料夾的終端機
- 若該資料夾已經有 `tasks.json`，不會被覆蓋，只會補上這個工作；重複執行也不會重複加入

## 安裝

需求：Windows、VS Code 的 `code` 指令要在 PATH 裡（安裝 VS Code 時勾選「加入 PATH」就會有）。

```powershell
git clone https://github.com/<your-username>/vscode-folder-hotkey.git
cd vscode-folder-hotkey
./install.ps1
```

預設會設定 `Ctrl+Shift+Alt+O`，也可以自訂：

```powershell
./install.ps1 -Hotkey "CTRL+ALT+O"
```

## 為什麼預設用三個修飾鍵？

`Ctrl+Alt+<字母>` 這種兩鍵組合，很容易被中文輸入法（新注音、微軟拼音等）自己的鍵盤鉤子搶先攔截，導致快速鍵沒反應。改成三個修飾鍵（`Ctrl+Shift+Alt+<字母>`）較少跟輸入法衝突。如果你不用中文輸入法，可以自行改成兩鍵組合。

## 原理

- `install.ps1` 在「開始功能表 \ Programs」底下建立一個捷徑，並設定捷徑的「快速鍵」屬性——這是 Windows 內建的全域快捷鍵機制，不需要額外安裝任何軟體
- 捷徑指向 `OpenFolderInVSCode.vbs`，透過 `wscript.exe` 隱藏執行，避免跳出黑色的命令視窗
- `.vbs` 再以隱藏視窗模式呼叫 `OpenFolderInVSCode.ps1`：跳出資料夾選擇視窗，選好後呼叫 `code <資料夾>`
- `install.ps1` 也會把 VS Code 使用者設定的 `task.allowAutomaticTasks` 開成 `on`，這樣每次開新資料夾都不會再跳「是否允許自動執行工作」的確認視窗。如果不想全自動，可以把這個設定改回預設，那樣每個新資料夾第一次會跳一次確認，之後 VS Code 會記住你的選擇

## 卸載

1. 刪除捷徑：`%APPDATA%\Microsoft\Windows\Start Menu\Programs\Open Folder in VS Code.lnk`
2. （可選）從 VS Code 使用者設定移除 `task.allowAutomaticTasks`
