<p align="center">
  <img src="https://img.shields.io/badge/Platform-Windows_10%2F11-0078D6?style=for-the-badge&logo=windows&logoColor=white" alt="Platform">
  <img src="https://img.shields.io/badge/Shell-CMD_%2B_PowerShell-5391FE?style=for-the-badge&logo=powershell&logoColor=white" alt="Language">
  <img src="https://img.shields.io/badge/Dependencies-Zero-2ea44f?style=for-the-badge" alt="Dependencies">
</p>

<h1 align="center">🛠️ SystemCleanup</h1>

<p align="center">
  <b>One-click system maintenance, repair & update management from your desktop context menu</b><br>
  <sub>SFC · DISM · WinSxS cleanup · Windows Update hiding — all in one tool, zero dependencies</sub>
</p>

---

## ✨ What's Inside

| # | Tool | Description |
|:-:|------|-------------|
| 🔧 | **[Full Cleanup](#-full-cleanup)** | SFC → DISM → WinSxS Temp cleanup in a single automated flow |
| ⚡ | **[InFlight Cleanup](#-inflight-cleanup)** | Quick-clean locked files from `WinSxS\Temp` using `MoveFileEx` |
| 🔄 | **[Windows Update Manager](#-windows-update-manager)** | Hide/unhide/list updates, reset cache — no external tools needed |

---

## 🔧 Full Cleanup

> Automated system image repair: SFC scan, DISM component store maintenance, and WinSxS Temp cleanup — all sequenced correctly with logging.

### The Problem

- Running `sfc /scannow`, multiple `dism` commands, and cleanup scripts **manually** is tedious and error-prone
- You need to **remember the right order** — SFC before DISM restore, component cleanup after, verification scan last
- `WinSxS\Temp` accumulates orphaned files that Windows never cleans up on its own
- No single built-in tool does all of this together

### The Solution

The full cleanup orchestrates everything in the correct sequence with automatic logging:

```
┌─────────────────────────────────────────────────────────────┐
│                    FULL CLEANUP FLOW                        │
│                                                             │
│  ① Reset TrustedInstaller service                          │
│  ② SFC /scannow  (initial scan)                            │
│  ③ DISM AnalyzeComponentStore                               │
│  ④ DISM RestoreHealth                                       │
│  ⑤ DISM StartComponentCleanup                               │
│  ⑥ CleanInFlight.ps1  (WinSxS\Temp deep clean)             │
│  ⑦ Reset TrustedInstaller + SFC /scannow  (verification)   │
│                                                             │
│  📄 All output logged to D:\Temp\SystemCleanup\             │
└─────────────────────────────────────────────────────────────┘
```

Each step reports exit codes with clear status indicators: `+++ OK`, `[~] FIXED`, or `[X] FAILED`.

### Usage

**From context menu** — *Right-click desktop or folder background → System Tools → Windows Update CleanUp → Option 1*

**From terminal:**

```cmd
:: Run full cleanup directly
SystemCleanup.cmd
```

⏱ Takes approximately 20–40 minutes depending on system state.

---

## ⚡ InFlight Cleanup

> Surgically removes orphaned files locked inside `WinSxS\Temp` using increasingly aggressive strategies.

### The Problem

- `C:\Windows\WinSxS\Temp` accumulates orphaned files from interrupted updates and servicing operations
- These files are **owned by TrustedInstaller** — you can't just `del` them
- Even with correct ownership, some files are **actively locked** by running services
- Windows never cleans these up automatically

### The Solution

A multi-strategy approach that escalates until files are removed:

```
┌──────────────────────────────────────────────────┐
│            INFLIGHT CLEANUP STRATEGY             │
│                                                  │
│  Step 1: Stop services → takeown → icacls → del │
│          ↓ (if files survive)                    │
│  Step 2: MoveFileEx API (schedule on reboot)     │
│          ↓ (if WRP blocks it)                    │
│  Step 3: Direct PendingFileRenameOperations      │
│          registry write                          │
│                                                  │
│  🔒 Temp FOLDER preserved — only contents       │
│     are removed                                  │
└──────────────────────────────────────────────────┘
```

Uses the Win32 `MoveFileEx` API with `MOVEFILE_DELAY_UNTIL_REBOOT` flag, and falls back to direct `PendingFileRenameOperations` registry injection when Windows Resource Protection blocks the API.

### Usage

**From context menu** — *Right-click desktop or folder background → System Tools → Windows Update CleanUp → Option 2*

**From terminal:**

```powershell
# Standalone run
pwsh -NoProfile -ExecutionPolicy Bypass -File .\CleanInFlight.ps1

# Silent mode (called from SystemCleanup.cmd)
pwsh -NoProfile -ExecutionPolicy Bypass -File .\CleanInFlight.ps1 -SilentCaller
```

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `-SilentCaller` | `switch` | `$false` | Suppresses the "Press Enter to close" prompt — used when called from the main menu |

---

## 🔄 Windows Update Manager

> Hide unwanted Windows Updates permanently using the native COM API — no `wushowhide.diagcab` needed.

### The Problem

- Windows pushes updates that **fail repeatedly** or aren't relevant (e.g. fake WSL update on non-WSL systems)
- The only built-in way to hide updates is the **`wushowhide.diagcab`** GUI tool — slow and manual
- Hiding an update *before* clearing the cache doesn't stick — the flag gets wiped on next cache reset
- Cache reset leaves behind **`.old` backup folders** that accumulate and waste disk space

### The Solution

A full interactive submenu using the native `Microsoft.Update.Session` COM API — zero external dependencies:

```
┌──────────────────────────────────────────────────────────┐
│              WINDOWS UPDATE MANAGER MENU                 │
│                                                          │
│  💡 To permanently hide an update:                       │
│     [5] Reset Cache → Reboot → [2] Hide Updates          │
│                                                          │
│  [1]  List Pending Updates                               │
│  [2]  Hide Update(s)        ← by number or keyword       │
│  [3]  Show Hidden Updates                                │
│  [4]  Unhide Update(s)      ← restore hidden             │
│  ──────────────────────────────────────────               │
│  [5]  Reset Update Cache    ← stops services + cleanup    │
│  [6]  Clean Stale Backups   ← remove .old_* folders       │
│  ──────────────────────────────────────────               │
│  [X]  Back / Exit                                        │
└──────────────────────────────────────────────────────────┘
```

The COM API's `IUpdate.IsHidden` property is what `wushowhide.diagcab` uses internally — same mechanism, fully scriptable.

### ⚠️ Critical: Correct Workflow Order

Hiding updates only works reliably when done **after** a cache reset and reboot:

```
  ┌─────────┐      ┌──────────┐      ┌──────────────┐
  │ [5]     │      │          │      │ [2]          │
  │ Reset   │ ───→ │  REBOOT  │ ───→ │ Hide Updates │
  │ Cache   │      │          │      │ (fresh list) │
  └─────────┘      └──────────┘      └──────────────┘
```

If you hide first then reset, the `IsHidden` flag is stored in `SoftwareDistribution` — resetting destroys it and the update reappears.

### Usage

**From context menu** — *Right-click desktop or folder background → System Tools → Windows Update CleanUp → Option 3*

**From terminal:**

```powershell
# Interactive mode
pwsh -NoProfile -ExecutionPolicy Bypass -File .\ManageUpdates.ps1

# Silent mode (no pause on exit)
pwsh -NoProfile -ExecutionPolicy Bypass -File .\ManageUpdates.ps1 -SilentCaller
```

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `-SilentCaller` | `switch` | `$false` | Suppresses the "Press Enter to close" prompt |

**Hide by number or keyword:**

```
Selection: 1,3          ← hide updates #1 and #3
Selection: 'Linux'      ← hide all updates matching "Linux"
Selection: 'KB5034441'  ← hide by KB number
```

---

## 📦 Installation

### Quick Setup

```powershell
# Install (registers context menu + copies files)
pwsh -NoProfile -ExecutionPolicy Bypass -File .\Install.ps1 -Action Install

# Verify installation
pwsh -NoProfile -ExecutionPolicy Bypass -File .\Install.ps1 -Action Install
# → installer will detect existing install and show status

# Update from GitHub
pwsh -NoProfile -ExecutionPolicy Bypass -File .\Install.ps1 -Action Update

# Uninstall (removes registry + files)
pwsh -NoProfile -ExecutionPolicy Bypass -File .\Install.ps1 -Action Uninstall -Force
```

### Requirements

| Requirement | Details |
|-------------|---------|
| **OS** | Windows 10 / 11 |
| **PowerShell** | pwsh 7+ preferred, falls back to Windows PowerShell 5.1 |
| **Privileges** | Admin — auto-requested via UAC elevation prompt |
| **Dependencies** | None — uses only built-in Windows tools and COM APIs |

### What the Installer Does

- Copies runtime files to `%LOCALAPPDATA%\SystemCleanupContext\`
- Registers context menu under **System Tools** submenu (desktop + folder backgrounds)
- Adds uninstall entry to Programs & Features
- Supports GitHub-based updates with branch selection

---

## 📁 Project Structure

```
SystemCleanup/
├── SystemCleanup.cmd      # Main menu launcher (CMD, auto-elevates)
├── CleanInFlight.ps1      # WinSxS\Temp cleanup with MoveFileEx fallback
├── ManageUpdates.ps1      # Windows Update Manager (COM API)
├── Install.ps1            # Installer/updater/uninstaller (InstallerCore)
├── SystemCleanup.reg      # Static registry sample (manual import)
├── .gitattributes         # Enforces CRLF for .cmd and .reg files
├── .gitignore             # Excludes legacy/test artifacts
├── PROJECT_RULES.md       # Decision log and project guardrails
└── README.md              # You are here
```

---

## 🧠 Technical Notes

<details>
<summary><b>Why CMD for the main launcher instead of PowerShell?</b></summary>

`SystemCleanup.cmd` is the entry point because CMD batch files can **self-elevate** cleanly via `Start-Process -Verb RunAs`, display ANSI-colored menus, and orchestrate `sfc`/`dism` commands natively. PowerShell scripts launched from context menus often flash a console window or have execution policy issues — the CMD wrapper avoids all of that.

</details>

<details>
<summary><b>Why MoveFileEx instead of just deleting files?</b></summary>

Files in `WinSxS\Temp` are often **locked by TrustedInstaller** or Windows Update services even after stopping them. The `MoveFileEx` API with `MOVEFILE_DELAY_UNTIL_REBOOT` (flag `0x4`) schedules deletion in the kernel's boot-time cleanup — before any services start. If even that fails (WRP-protected files), the script falls back to writing `PendingFileRenameOperations` directly in the registry.

</details>

<details>
<summary><b>Why native COM API for update hiding instead of PSWindowsUpdate module?</b></summary>

The `PSWindowsUpdate` PowerShell module is a popular choice but requires **installing a third-party dependency**. The built-in `Microsoft.Update.Session` COM object provides the exact same `IsHidden` property that Microsoft's own `wushowhide.diagcab` uses internally. Zero dependencies means the tool works on any Windows machine without setup.

</details>

<details>
<summary><b>Why does Reset → Reboot → Hide need to be in that exact order?</b></summary>

The `IsHidden` flag is stored in the **Windows Update metadata cache** inside `C:\Windows\SoftwareDistribution`. When you reset the cache (rename/delete that folder), all metadata — including hidden flags — is destroyed. After reboot, Windows rebuilds the cache with a fresh scan. Hiding updates on this fresh list ensures the flag persists until the next intentional reset.

</details>

---

<p align="center">
  <sub>Built for Windows 10/11 · Zero external dependencies · Admin rights auto-requested when needed</sub>
</p>
