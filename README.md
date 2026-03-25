<p align="center">
  <img src="https://img.shields.io/badge/Platform-Windows_10%2F11-0078D6?style=for-the-badge&logo=windows&logoColor=white" alt="Platform">
  <img src="https://img.shields.io/badge/Shell-CMD_%2B_PowerShell-5391FE?style=for-the-badge&logo=powershell&logoColor=white" alt="Language">
  <img src="https://img.shields.io/badge/Dependencies-Zero-2ea44f?style=for-the-badge" alt="Dependencies">
</p>

<h1 align="center">🛠️ SystemCleanup</h1>

<p align="center">
  <b>One-click system maintenance, repair & update management from your desktop context menu</b><br>
  <sub>SFC · DISM · WinSxS cleanup · Windows Update hiding · Win11 upgrade block — all in one tool, zero dependencies</sub>
</p>

---

## ✨ What's Inside

| # | Tool | Description |
|:-:|------|-------------|
| 🔧 | **[Full Cleanup](#-full-cleanup)** | SFC → DISM `/ResetBase` → WinSxS Temp cleanup in a single automated flow |
| ⚡ | **[InFlight Cleanup](#-inflight-cleanup)** | Quick-clean locked files from `WinSxS\Temp` using `MoveFileEx` |
| 💾 | **[Live SoftwareDistribution Cleanup](#-live-softwaredistribution-cleanup)** | Clean the live `SoftwareDistribution\Download` cache without resetting update history |
| 🚚 | **[Delivery Optimization Cleanup + Disable](#-delivery-optimization-cleanup--disable)** | Clear the Delivery Optimization cache and safely force peer-to-peer sharing off |
| 🔄 | **[Windows Update Manager](#-windows-update-manager)** | Hide/unhide/list updates, reset cache, clean stale backups, block Win11 upgrade |
| ⬇️ | **[Self-Update](#-self-update)** | Launch the sibling InstallerCore updater from the main menu with smart repo/install detection |
| 📦 | **[Installer](#-installation)** | One-command setup with context menu registration and GitHub updates |

---

## 🔧 Full Cleanup

> Automated system image repair: SFC scan, DISM component store maintenance with `/ResetBase`, and WinSxS Temp cleanup — all sequenced correctly with logging.

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
│  ⑤ DISM StartComponentCleanup /ResetBase                   │
│  ⑥ CleanInFlight.ps1  (WinSxS\Temp deep clean)             │
│  ⑦ Reset TrustedInstaller + SFC /scannow  (verification)   │
│                                                             │
│  📄 Logs prefer D:\Temp\SystemCleanup\ and fall back        │
│     automatically when D: is not available                  │
└─────────────────────────────────────────────────────────────┘
```

Each step reports exit codes with clear status indicators: `+++ OK`, `[~] FIXED`, or `[X] FAILED`. The main `Full Cleanup` flow now uses `dism.exe /Online /Cleanup-Image /StartComponentCleanup /ResetBase`, so superseded component versions are reclaimed immediately instead of waiting for the plain 30-day cleanup window. After any option completes, the tool **returns to the main menu** — only `ESC` exits the CMD launcher.

The action-oriented main-menu entries now open a confirmation panel first, so entering `[1]` / `[2]` / `[3]` / `[4]` / `[7]` does not immediately start work. `Windows Update Manager` `[5]` still opens directly because it is its own submenu, and `Last DISM/CBS Failure Details` `[6]` opens directly because it is read-only info. The primary action pattern is `Enter = start`, `ESC = back to main menu`.

`/ResetBase` is intentionally more aggressive: after that step, older superseded component versions are no longer uninstallable.

When a `DISM` step fails, the launcher also prints the native exit code, points directly to `C:\Windows\Logs\DISM\dism.log` and `C:\Windows\Logs\CBS\CBS.log`, and shows a short ranked summary of the most relevant recent `DISM` / `CBS` clues in a compact format that remains readable in narrow Windows Terminal panes.

Main-menu option `[6]` opens a wider non-compact `DISM` / `CBS` failure view so the same servicing clues are easier to read outside the WT split-pane flow.

Main-menu option `[4]` shows the live Delivery Optimization state directly in the gray description line and lets you clear the Delivery Optimization cache while safely forcing `DownloadMode = 0 (CdnOnly)` so peer-to-peer sharing stays off.

Main-menu option `[7]` is a launcher-level self-update shortcut. It detects whether the tool is running from a git repo, an installed copy, or a portable copy, then dispatches to the sibling `Install.ps1` with the most sensible `InstallerCore` update action automatically.

On the experimental `wt` branch, the main launcher is now `SystemCleanup.ps1`. It prefers **Windows Terminal** when available, but still falls back to a normal elevated PowerShell host if `wt.exe` is missing. In WT sessions, `Full Cleanup` opens in a dedicated split pane and runs through `cmd.exe`, preserving the familiar native `% progress` display for `SFC` and `DISM`.

### Usage

**From context menu** — *Right-click desktop or folder background → System Tools → Windows Update CleanUp → Option 1*

**From terminal:**

```powershell
pwsh -NoProfile -ExecutionPolicy Bypass -File .\SystemCleanup.ps1
```

Includes SFC, DISM, and WinSxS Temp cleanup with logging in one run. Actual duration varies a lot by system state.

By default the `wt` launcher prefers `D:\Temp\SystemCleanup` for logs, but if that drive is missing or not writable it falls back automatically to a safe local path such as `%LOCALAPPDATA%\SystemCleanupContext\logs`.

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

## 💾 Live SoftwareDistribution Cleanup

> Fast post-update space recovery for the live `C:\Windows\SoftwareDistribution\Download` cache.

- Main menu option `[3]`
- The gray description line shows the current live `Download` cache size directly in the main menu
- Before confirmation, it shows the current live `Download` cache size again so you can decide if it is worth running
- It stops the update services temporarily and cleans only the live `Download` cache
- It intentionally leaves `DataStore` / update history alone, so it is less disruptive than a full cache reset
- If some files stay locked, the tool schedules those leftovers for deletion on the next reboot
- Windows may recreate some files later after a new update scan or download — that is normal

**Best used:** after monthly updates when you want to reclaim space from leftover update downloads.

**From context menu** — *Right-click desktop or folder background → System Tools → Windows Update CleanUp → Option 3*

---

## 🚚 Delivery Optimization Cleanup + Disable

> Clear the Delivery Optimization cache and safely force peer-to-peer Delivery Optimization off without breaking normal Microsoft/CDN downloads.

- The main menu shows the live Delivery Optimization state as `Disabled` / `Enabled` plus the current cache size
- The action uses the native `Delete-DeliveryOptimizationCache` cmdlet instead of manually deleting random files
- Safe disable is implemented as `DODownloadMode = 0 (CdnOnly)`, which disables peer-to-peer caching while still allowing normal Windows Update / Microsoft Store downloads
- The tool also shows the effective mode/provider and the working cache path so VM testing is easier
- The confirmation step now follows the same cleaner interaction blueprint as the self-update panel: `Enter` runs the action, `ESC` cancels back to the main menu, and the active Delivery Optimization values are highlighted in bright green

This is intentionally **not** implemented as `Disable-Service DoSvc`, because that is a riskier way to interfere with the Delivery Optimization stack than simply forcing peer-sharing off.

---

## 🔄 Windows Update Manager

> Hide unwanted Windows Updates, block Windows 11 upgrades, and reset the update cache — all using the native COM API, no external tools needed.

### The Problem

- Windows pushes updates that **fail repeatedly** or aren't relevant (e.g. fake WSL update on non-WSL systems)
- The only built-in way to hide updates is the **`wushowhide.diagcab`** GUI tool — slow and manual
- Hiding an update *before* clearing the cache doesn't stick — the flag gets wiped on next cache reset
- Cache reset leaves behind **`.old` backup folders** that accumulate and waste disk space
- Windows 10 machines get **nagged to upgrade to Windows 11** with no easy off switch

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
│  [5]  Reset Update Cache    ← reset SoftwareDistribution  │
│  [6]  Clean Stale Backups   ← remove .old_* folders       │
│  ──────────────────────────────────────────               │
│  [7]  Block Windows 11      ← policy active/mismatch/off  │
│  ──────────────────────────────────────────               │
│  [ESC] Back to main menu                                 │
└──────────────────────────────────────────────────────────┘
```

The menu uses **single-keypress navigation** — press a number to select, `ESC` to go back to the main SystemCleanup menu. No Enter key needed.

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

### Reset Cache Troubleshooting

- `Reset Update Cache` now distinguishes between a **complete reset** and a **partial reset**
- A partial reset usually means one or more Windows Update services never stopped cleanly, or `SoftwareDistribution` / `catroot2` could not be moved fully
- Fresh cache folders may be recreated immediately after services restart — that alone does **not** mean the reset failed
- If the tool reports a partial reset, reboot and run `[5]` again before hiding updates

### Block Windows 11 Upgrade

Option `[7]` toggles a Group Policy lock that pins the machine to Windows 10:

```
┌──────────────────────────────────────────────────────────┐
│  BLOCK WINDOWS 11 — How It Works                         │
│                                                          │
│  Sets three registry values under:                       │
│  HKLM\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate  │
│                                                          │
│  TargetReleaseVersion     = 1      (DWORD)               │
│  TargetReleaseVersionInfo = 22H2                         │
│  ProductVersion           = Windows 10                   │
│                                                          │
│  + gpupdate /force to apply immediately                  │
│                                                          │
│  Toggle: ON → removes all three values                   │
│  Menu:   Shows [Policy active] / [Policy mismatch] / off │
│  Guard:  Warns if already running Windows 11             │
│  Verify: Writes values and reads them back immediately   │
└──────────────────────────────────────────────────────────┘
```

The tool pins the machine to **Windows 10 22H2**, which is the final Windows 10 feature release. You'll still receive Windows 10 security updates.

> **Note:** The same registry key often contains additional update policy values (e.g. `AUOptions`, `ExcludeWUDriversInQualityUpdate`, `NoAutoRebootWithLoggedOnUsers`). These are set independently via Group Policy or manual registry edits and coexist safely with the Win11 block values. The script only manages the three target-version entries — it never touches your other update policies.

> **Note:** Blocking the feature upgrade does not guarantee that every Windows Update page or banner stops mentioning Windows 11 eligibility. The policy targets the actual feature upgrade offer.

### Usage

**From context menu** — *Right-click desktop or folder background → System Tools → Windows Update CleanUp → Option 4*

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

## ⬇️ Self-Update

> A main-menu shortcut that reuses the existing InstallerCore-generated `Install.ps1` instead of inventing a second updater flow inside the launcher.

- Main menu option `[7]`
- If the launcher is running from a git working copy, it uses `DownloadLatest` against the current repo folder
- If the launcher is running from an installed copy with `state\install-meta.json`, it uses `UpdateGitHub` for the installed tool
- If the launcher is running from a portable folder, it falls back to `DownloadLatest`
- The gray description line shows the detected updater defaults directly in the main menu, for example `Repo copy • GitHub/wt`, `Installed copy • GitHub/master`, or `Installed copy • Local`
- The self-update screen shows the default `Installer Mode` plus either `GitHub branch` or `Local source`
- The choice block is split into clear per-line actions: `Enter` uses shown defaults, `E` opens the normal `Install.ps1` interactive menu, and `ESC` cancels
- Pressing `ESC` in that self-update choice panel returns directly to the main launcher menu without the extra generic pause prompt
- For installed copies, a successful InstallerCore `Install` / `Update` run saves the chosen `package_source` and `github_ref` into `state\install-meta.json`, so the next launcher run reuses those defaults
- For repo copies, the default GitHub branch follows the branch currently checked out in `.git`

This keeps updater logic aligned with `InstallerCore`, avoids duplicating the source/branch chooser inside the launcher, and makes the pattern a good blueprint for other PowerShell main-menu tools that already ship a sibling `Install.ps1`.

---

## 📦 Installation

### Quick Setup

```powershell
# Install (registers context menu + copies files)
pwsh -NoProfile -ExecutionPolicy Bypass -File .\Install.ps1 -Action Install

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
- Supports GitHub-based updates with interactive branch selection

---

## 📁 Project Structure

```
SystemCleanup/
  ├── SystemCleanup.ps1          # Main menu launcher (PowerShell, prefers Windows Terminal)
  ├── FullCleanup.cmd           # WT split-pane runner for native SFC/DISM progress
  ├── SystemCleanup.cmd          # Legacy CMD launcher kept for compatibility / branch work
  ├── CleanInFlight.ps1          # WinSxS\Temp cleanup with MoveFileEx fallback
  ├── ManageUpdates.ps1          # Windows Update Manager + Win11 block (COM API)
  ├── Install.ps1                # Installer/updater/uninstaller (InstallerCore)
  ├── SystemCleanup.reg          # Static registry sample (manual import)
  ├── Reset update services.ps1  # Legacy update services reset script
  ├── .gitattributes             # Enforces CRLF for .cmd and .reg files
  ├── .gitignore                 # Excludes legacy/test artifacts
  ├── CHANGELOG.md               # Notable user-facing changes
  ├── PROJECT_RULES.md           # Decision log and project guardrails
  └── README.md                  # You are here
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

<details>
<summary><b>Why Group Policy for blocking Windows 11 instead of hiding the update?</b></summary>

Simply hiding the Windows 11 upgrade via `IsHidden` doesn't survive cache resets, and Windows can re-offer it through different KB articles over time. The **Group Policy** approach (`TargetReleaseVersion` + `ProductVersion`) tells Windows Update at the policy level to stay on Windows 10 — it's the same mechanism enterprises use, and it doesn't require hiding individual updates. You still receive all Windows 10 security patches.

</details>

<details>
<summary><b>Why can Win11 block show "Policy mismatch"?</b></summary>

`Policy mismatch` means the registry contains only a **partial** or **invalid** Windows 11 block configuration. The tool expects all three values together: `TargetReleaseVersion=1`, `ProductVersion=Windows 10`, and `TargetReleaseVersionInfo=22H2`. If one is missing or different, the menu shows a mismatch instead of claiming the policy is active.

</details>

<details>
<summary><b>Why single-keypress menu navigation?</b></summary>

The Windows Update Manager uses `ReadKey` instead of `Read-Host` for menu input. This means you press a single key (1–8, X, or ESC) and the action fires immediately — no Enter needed. `ESC` returns to the main SystemCleanup CMD menu instead of closing the tool, making the navigation feel responsive and preventing accidental exits.

</details>

<details>
<summary><b>Why can Reset Update Cache report a partial reset?</b></summary>

Windows Update is noisy: even after you ask services to stop, handles can still be open briefly and block `SoftwareDistribution` or `catroot2` from moving. The tool now waits for service state transitions and verifies the cache-folder move. If either folder was not fully reset, it reports a partial reset so you do not mistake it for a clean success.

</details>

---

<p align="center">
  <sub>Built for Windows 10/11 · Zero external dependencies · Admin rights auto-requested · ESC navigates back</sub>
</p>
