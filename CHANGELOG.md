# Changelog

All notable user-facing changes for `SystemCleanup` are recorded here.

## [2026-03-10]

### Changed

- Hardened `Reset Update Cache` so it now waits for service stop/start transitions, verifies the `SoftwareDistribution` and `catroot2` move, and reports a partial reset instead of a false success.
- Updated the Windows 11 block toggle to verify registry writes by readback and to distinguish `Policy active`, `Policy mismatch`, and `Not configured` states in the menu.

## [2026-03-12]

### Added

- Added `Live SoftwareDistribution Cleanup` to the Windows Update Manager so the live `SoftwareDistribution\Download` cache can be cleaned without doing a full reset of `SoftwareDistribution` and `catroot2`.
- Added a new main-menu `Windows Update Cleanup (Disk Cleanup Utility)` action that runs an isolated `cleanmgr /sagerun:88` pass and shows `AnalyzeComponentStore` status before and after the run.

### Changed

- Shifted the Windows Update Manager menu so `Clean Stale Backup Folders` moved to `[7]` and `Block Windows 11 Upgrade` moved to `[8]`.
- Updated `Live SoftwareDistribution Cleanup` to show the current `SoftwareDistribution\Download` size before the confirmation prompt, while still reporting before/after/freed sizes after the run.
- Updated the `[6] Live SoftwareDistribution Cleanup` menu line to show the current live `Download` cache size directly in the gray description text.
- Promoted `Live SoftwareDistribution Cleanup` out of the Windows Update Manager and into main-menu option `[3]`, where the gray description line now shows the current live `Download` cache size.
- Moved `Windows Update Manager` to main-menu option `[5]` and simplified its submenu back to hide/unhide/list, reset cache, stale backup cleanup, and Windows 11 block actions.
- Fixed the main-menu live cache size probe in `SystemCleanup.cmd` so CMD launches the PowerShell one-liner correctly instead of showing a `'pwsh"... is not recognized` quoting error.
- Replaced the main-menu live cache size one-liner with a dedicated `ManageUpdates.ps1 -Action LiveCleanupStatus` call so CMD no longer breaks on inline PowerShell quoting or string-token parsing.
- Fixed the main-menu ANSI palette so option `[4]` uses explicit magenta and option `[5]` uses blue instead of both rendering as default white.
- Changed the main `SystemCleanup.cmd` launcher to show `[ESC] Close / Cancel` and read the actual Escape key via `ManageUpdates.ps1`, instead of showing `[X]` with `set /p`.
- Replaced the misleading `Takes 20-40 minutes` text under main-menu option `[1] Full Cleanup` with a plain description of what the action actually runs.
- Reworked the isolated `cleanmgr /sagerun:88` slot handling to use `reg.exe` instead of the PowerShell registry provider, avoiding the earlier `Argument types do not match` failure path and surfacing clear access errors when the process is not elevated.
- Added a `wt.exe` host relay to `SystemCleanup.cmd` on the `wt` branch: when Windows Terminal is available and the system is not in Safe Mode, the existing CMD UI now relaunches inside Windows Terminal while keeping the classic console as fallback.
- Simplified the `wt.exe` relay on the `wt` branch to launch through a temporary `.cmd` trampoline instead of an inline `call ... --wt-hosted` command string, reducing Windows Terminal argument-parsing glitches during startup.
- Added a new `SystemCleanup.ps1` main launcher on the `wt` branch and switched the installer / `.reg` command path to `pwsh.exe -File SystemCleanup.ps1`, removing `cmd.exe` from the primary interactive launch path.
- Removed the stale `.gitignore` entry that used to hide `SystemCleanup.ps1`, so the new PowerShell launcher can actually be tracked on the `wt` branch.
- Updated the `wt` launcher logging path so it prefers `D:\Temp\SystemCleanup` but automatically falls back to a writable local path when a machine only has `C:` or the `D:` drive is not ready.
- Updated the `wt` launcher so `Full Cleanup` runs the `SFC` and `DISM` stages through `cmd.exe`, preserving the normal native progress display inside Windows Terminal.
- Fixed `CleanInFlight.ps1` so its empty-folder checks are array-safe under strict PowerShell execution and no longer crash on single-item results with `The property 'Count' cannot be found on this object`.
- Updated the experimental `wt` branch so main-menu option `[1] Full Cleanup` now opens in a dedicated Windows Terminal split pane backed by `FullCleanup.cmd`, instead of trying to run the whole servicing flow inline in the menu pane.

