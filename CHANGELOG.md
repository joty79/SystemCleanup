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

