# Changelog

All notable user-facing changes for `SystemCleanup` are recorded here.

## [2026-04-16]

### Changed

- Migrated the primary launcher to the newer PowerShell UI pattern with a versioned header, WT-safe rendering, arrow-key main-menu navigation, and number shortcuts.
- Fixed the main-menu `ESC`/`Close / Cancel` path so it now exits the launcher host cleanly instead of just breaking the inner menu switch.
- Extended the new versioned header style into submenu screens such as `Full Cleanup`, `InFlight Cleanup`, `DISM/CBS Failure Details`, and `Windows Update Manager`, so the app no longer drops back to the older pre-template visual language after leaving the main menu.
- Switched the context-menu launch path to a hidden `Launch-SystemCleanup.vbs` wrapper so Explorer no longer flashes a visible intermediate `pwsh` window before handing off to Windows Terminal.
- Added canonical `app-metadata.json` so the app version and GitHub repo now come from a single shared metadata file instead of being hardcoded only inside scripts.
- Regenerated `Install.ps1` from the current `InstallerCore` template/profile so the installer now matches the modern SystemCleanup runtime contract again.
- Synced the `InstallerCore` SystemCleanup profile to the current launcher reality: `SystemCleanup.ps1` is the primary entrypoint, and `app-metadata.json`, `FullCleanup.cmd`, and `ManageUpdates.ps1` are now part of the generated installer contract.
- Added `logs/` and `state/` to `.gitignore` so runtime logs and update-status cache do not dirty the workspace repo.
- Cleaned stale merge-conflict markers from `README.md` and `CHANGELOG.md` and aligned the docs with the current PowerShell launcher/update flow.

## [2026-03-25]

### Changed

- Updated all `Full Cleanup` runtime paths to run `dism.exe /Online /Cleanup-Image /StartComponentCleanup /ResetBase` instead of the plain `StartComponentCleanup` pass.
- Removed the flaky main-menu `Windows Update Cleanup (Disk Cleanup Utility)` GUI entry so the launcher no longer exposes the unreliable `cleanmgr /sagerun:88` path.
- Reordered the main menu so the current post-update / maintenance flow is `[3] Live SoftwareDistribution Cleanup`, `[4] Delivery Optimization Cleanup + Disable`, `[5] Windows Update Manager`, `[6] Last DISM/CBS Failure Details`, and `[7] Update This Tool (InstallerCore)`.
- Updated the README to stop advertising the removed `Windows Update Cleanup` main-menu path and to reflect the new main-menu numbering.
- Expanded `DISM` failure output so the launcher now prints the native exit code, points directly to `dism.log` / `CBS.log`, and gives a targeted hint for `Error 3 / 0x80070003` servicing-path failures.
- Added a short `DISM` / `CBS` log summary to `DISM` failure output so the launcher now surfaces the most relevant recent error lines automatically after a failed servicing step.
- Refined the `CBS`/`DISM` log summary ranking so missing-path clues such as `InFlight`, `STATUS_OBJECT_PATH_NOT_FOUND`, and `RBDSTAMIL99` are prioritized ahead of low-signal finalize noise.
- Compressed the automatic `DISM` / `CBS` failure summary into short human-readable clues so the output stays readable inside narrow Windows Terminal split panes.
- Added a launcher-level self-update option `[7] Update This Tool (InstallerCore)` that reuses the sibling `Install.ps1` and auto-detects whether to run `DownloadLatest` or `UpdateGitHub`.
- Added a live updater status probe so the main menu shows the detected InstallerCore update mode directly in the gray description line.
- Refined the self-update screen to show user-facing InstallerCore defaults as `Installer Mode` / `GitHub branch` or `Local source`, with `Enter` using those defaults and `E` opening the standard `Install.ps1` menu for alternate Local/GitHub/branch choices.
- Reformatted the self-update choice prompt into clearer per-line colored actions and added an explicit note about when source/branch selections are persisted for the next run.
- Reduced main-menu delay by caching the expensive live status lines for `Live SoftwareDistribution Cleanup` and `Delivery Optimization Cleanup + Disable` after the first menu render, then refreshing only after those actions actually run.
- Changed self-update `ESC` cancel handling so it returns straight to the main menu instead of stopping on the generic `Press any key to return to menu...` pause.
- Cleared the main-menu screen before launching each main-menu action and highlighted the active self-update values (`Detected mode`, `Installer Mode`, `GitHub branch` / `Local source`) in bright green with clearer icons.
- Applied the same Enter/ESC interaction blueprint to `Delivery Optimization Cleanup + Disable`, replacing the old `Proceed? (Y/N)` prompt and highlighting the active Delivery Optimization values in bright green.
- Extended the safe Enter/ESC confirmation pattern across the main menu so `Full Cleanup`, `InFlight Cleanup`, `Live SoftwareDistribution Cleanup`, `Windows Update Manager`, and `Last DISM/CBS Failure Details` now open a confirmation panel before starting/opening.
- Trimmed that confirmation pattern back for `[5] Windows Update Manager` and `[6] Last DISM/CBS Failure Details`, so submenu/info-only entries open directly again while the real cleanup/update actions remain two-step.
- Fixed the launcher-side `DISM / CBS` detail panels to explicitly render the returned summary lines instead of relying on implicit nested-script output, so menu `[6]` consistently shows the full servicing summary again.
- Tightened the servicing-summary selector so menu `[6]` ignores common noisy `DISM` `EnumeratePathEx / FindFirstFile failed` setup probes and scans deeper into `CBS.log`, making root-cause clues more likely to appear than generic source-noise lines.
- Changed app-driven installed self-updates to skip the old Explorer-folder reopen path and, after a successful installed update, ask whether to relaunch only the app (`Enter`) or relaunch the app plus restart Explorer without reopening a folder window.
- Adjusted installed self-update relaunch to use the same context-menu style launch path through a detached helper that clears `WT_SESSION`, so the updated app can reopen correctly in Windows Terminal instead of inheriting the old WT child environment.
- Refined the WT self-update relaunch again so, when `wt.exe` is available, the updated app opens in a **new Windows Terminal window** (`wt -w new`) instead of appearing as a second tab in the existing WT window.
- Updated the WT self-update relaunch helper to close the previous WT window after opening the replacement window, so the app relaunch behaves like a real handoff instead of leaving the old terminal behind.

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
- Restyled `FullCleanup.cmd` on the `wt` branch to match the familiar CMD full-cleanup look more closely and fixed its quoted-command dispatch so the split-pane runner executes `SFC` / `DISM` correctly.
- Changed the WT split-pane launcher for `Full Cleanup` from `cmd.exe /k` to `cmd.exe /c`, so after the final `Press any key to close this pane...` prompt the pane actually closes instead of dropping to a `C:\...>` prompt.
- Fixed `Live SoftwareDistribution Cleanup` so its before/after/freed size summary no longer crashes under strict PowerShell execution when reading the measured size result.
- Added targeted debug logging around `Windows Update Cleanup (Disk Cleanup Utility)` so `cleanmgr /sagerun:88` runs now record slot snapshots, process heartbeats, and post-run state in a dedicated troubleshooting log.
- Changed `Windows Update Cleanup` on the experimental `wt` branch to launch `cleanmgr` through an external classic `cmd` window when running inside Windows Terminal, avoiding the WT-hosted first-run hang/focus issue seen on some machines.
- Improved the `Windows Update Cleanup` debug log so external-`cmd` runs now distinguish the `cmd` wrapper PID from the real `cleanmgr` child process and log newly observed `cleanmgr` PIDs explicitly.
- Reworked `Windows Update Cleanup` on the `wt` branch again so it now launches `cleanmgr` directly, auto-activates the Disk Cleanup GUI window when needed, and tail-waits detached child `cleanmgr` processes instead of relying on the earlier external-`cmd` fallback.
- Updated the `Windows Update Manager` menu so option `[6] Clean Stale Backup Folders` shows a live `.old_*` folder count/size summary instead of a generic static description.

