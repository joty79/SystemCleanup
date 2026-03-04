# PROJECT_RULES - SystemCleanup

## Scope
- Repo: `D:\Users\joty79\scripts\SystemCleanup`
- Purpose: desktop context-menu tool for Windows component cleanup (`SFC`, `DISM`, `InFlight` cleanup).

## Guardrails
- Keep file ownership explicit from registry chain: `SystemCleanup.reg` -> `SystemCleanup.cmd` -> `CleanInFlight.ps1`.
- Keep context-menu target under `DesktopBackground\Shell\SystemCleanup` for install writes.
- Keep installer behavior template-driven via generated `Install.ps1` from InstallerCore.
- Do not remove legacy/test artifacts unless explicitly requested; exclude them from repo tracking by default.

## Decision Log

### Entry - 2026-02-26 (Initial repo onboarding)
- Date: 2026-02-26
- Problem: Workspace had mixed production and legacy/test files with no repository baseline.
- Root cause: Project existed as a working folder without strict tracked-file boundaries or template installer contract.
- Guardrail/rule: Track only core runtime files + generated installer/docs in git baseline; keep extras untracked unless promoted intentionally.
- Files affected: `Install.ps1`, `SystemCleanup.cmd`, `CleanInFlight.ps1`, `SystemCleanup.reg`, `README.md`, `.gitignore`.
- Validation/tests run: Generated installer parse validation via `Parser::ParseFile`.

### Entry - 2026-03-02 (Move SystemCleanup under shared System Tools submenu)
- Date: 2026-03-02
- Problem: `SystemCleanup` still installed as a standalone desktop-background verb and its installer lagged behind the current `InstallerCore` template behavior.
- Root cause: Manual `.reg` and embedded installer profile still targeted `DesktopBackground\Shell\SystemCleanup` directly instead of the shared submenu host, and the generated installer was from an older template snapshot.
- Guardrail/rule: In this repo, `SystemCleanup` is child-only under `HKCU\Software\Classes\DesktopBackground\Shell\SystemTools\shell\SystemCleanup`; the host parent is owned by `SystemTools`. Keep the manual `.reg` path aligned with the current repo path (`D:\Users\joty79\scripts\SystemCleanup`) and regenerate `Install.ps1` from current `InstallerCore` after template/profile changes.
- Files affected: `Install.ps1`, `SystemCleanup.reg`, `PROJECT_RULES.md`.
- Validation/tests run: Regenerated installer from `InstallerCore`; parser validation on `Install.ps1`; static review of manual `.reg`.

### Entry - 2026-03-03 (Adopt Download Latest template action)
- Date: 2026-03-03
- Problem: Local repo workflows needed a way to refresh `SystemCleanup` from GitHub in place without installing to `%LOCALAPPDATA%` or touching registry state.
- Root cause: Older generated installer snapshot predated the new `InstallerCore` `DownloadLatest` action.
- Guardrail/rule: Keep `Install.ps1` regenerated from current `InstallerCore` when template action flow changes; `DownloadLatest` is a local working-copy sync action that updates `$PSScriptRoot`, skips install side effects, and relaunches the updated installer.
- Files affected: `Install.ps1`, `PROJECT_RULES.md`.
- Validation/tests run: Regenerated `Install.ps1` from current `InstallerCore`; parser validation via `Parser::ParseFile`.

### Entry - 2026-03-03 (Download Latest menu order sync)
- Date: 2026-03-03
- Problem: `DownloadLatest` needed to appear directly below `Uninstall` during local repo testing, not after the open/log utility actions.
- Root cause: Older generated installer snapshot used the first template menu ordering for the new action.
- Guardrail/rule: Regenerate `Install.ps1` when template menu ordering changes; in this repo the `DownloadLatest` option should stay grouped with the core lifecycle actions.
- Files affected: `Install.ps1`, `PROJECT_RULES.md`.
- Validation/tests run: Regenerated `Install.ps1` from current `InstallerCore`; parser validation via `Parser::ParseFile`.

### Entry - 2026-03-03 (Add folder background support under System Tools)
- Date: 2026-03-03
- Problem: `SystemCleanup` only appeared under `System Tools` on desktop background; it was missing on folder background.
- Root cause: Both the manual `.reg` and the embedded installer profile only registered `DesktopBackground\Shell\SystemTools\shell\SystemCleanup`.
- Guardrail/rule: In this repo, `SystemCleanup` must register both background child branches under the shared host:
  - `HKCU\Software\Classes\Directory\Background\shell\SystemTools\shell\SystemCleanup`
  - `HKCU\Software\Classes\DesktopBackground\Shell\SystemTools\shell\SystemCleanup`
- Files affected: `Install.ps1`, `SystemCleanup.reg`, `PROJECT_RULES.md`.
- Validation/tests run: Static review of `.reg` and embedded installer profile; parser validation on `Install.ps1`.

### Entry - 2026-03-03 (Interactive installer must support Local source)
- Date: 2026-03-03
- Problem: Running local `Install.ps1` still forced the interactive user flow into GitHub branch selection, so local registry changes could not be tested from the menu path.
- Root cause: The generated installer snapshot in this repo still hard-forced `PackageSource = 'GitHub'` for `Install` and `Update`.
- Guardrail/rule: In this repo, interactive `Install` and `Update` must prompt for package source first (`GitHub` or `Local`) and only show branch selection when `GitHub` is selected.
- Files affected: `Install.ps1`, `PROJECT_RULES.md`.
- Validation/tests run: Parser validation on `Install.ps1`; static review of action switch flow.

### Entry - 2026-03-03 (Batch and .reg files must stay CRLF)
- Date: 2026-03-03
- Problem: Launching `SystemCleanup.cmd` from the context menu produced broken `cmd.exe` parsing such as `'setlocal' is not recognized` and fragmented commands.
- Root cause: `SystemCleanup.cmd` had LF/mixed line endings. `cmd.exe` is fragile with LF-only batch files and can tokenize commands incorrectly.
- Guardrail/rule: In this repo, keep `*.cmd`, `*.bat`, and `*.reg` files in CRLF. Enforce with `.gitattributes` and normalize affected runtime artifacts before testing/installing.
- Files affected: `.gitattributes`, `SystemCleanup.cmd`, `SystemCleanup.reg`, `PROJECT_RULES.md`.
- Validation/tests run: `git ls-files --eol`; byte-level CR/LF count check on `SystemCleanup.cmd`.

### Entry - 2026-03-03 (CleanInFlight performance fix + WinSxS\Temp scope)
- Date: 2026-03-03
- Problem: `CleanInFlight.ps1` was significantly slower than `Manage_Ownership.ps1` for taking ownership of `WinSxS\Temp` contents.
- Root cause: Three performance bottlenecks: (1) `| Out-Null` on `takeown /R` and `icacls /T` forced full pipeline buffering of thousands of output lines before discarding, (2) unnecessary `Start-Sleep -Seconds 2` after service stop, (3) `ArrayList.Add() | Out-Null` in loops. Additionally, scope was limited to `InFlight` subfolder instead of all `WinSxS\Temp` contents.
- Guardrail/rule: Always use `> $null 2>&1` or `[void]` cast for output suppression in hot paths instead of `| Out-Null`; keep `WinSxS\Temp` folder itself intact but clean all contents inside it.
- Files affected: `CleanInFlight.ps1`, `PROJECT_RULES.md`.
- Validation/tests run: Static review of output suppression patterns and cleanup scope.

### Entry - 2026-03-03 (Add Windows Update Manager — menu option 3)
- Date: 2026-03-03
- Problem: Hiding unwanted Windows Updates (e.g. fake WSL update) required manual use of `wushowhide.diagcab` GUI tool and sometimes full update cache reset.
- Root cause: No programmatic way to hide/unhide updates was integrated into the SystemCleanup tool.
- Guardrail/rule: `ManageUpdates.ps1` uses native `Microsoft.Update.Session` COM API (zero external dependencies) with `IUpdate.IsHidden` property. Menu option `[3]` in `SystemCleanup.cmd` launches it. The existing `Reset update services.ps1` functionality is subsumed by the Reset Update Cache submenu option inside the new script.
- Files affected: `ManageUpdates.ps1` (new), `SystemCleanup.cmd`, `PROJECT_RULES.md`.
- Validation/tests run: PowerShell parser syntax validation on `ManageUpdates.ps1`; static review of COM API usage and menu integration.

### Entry - 2026-03-03 (Update hiding workflow & stale .old cleanup)
- Date: 2026-03-03
- Problem: Hiding updates only works reliably if the update cache is reset first and the PC is rebooted before hiding. Hiding first then resetting wipes the hidden flag and the update reappears. Also, `Reset-UpdateCache` left `.old_*` backup folders accumulating forever.
- Root cause: The Windows Update COM API `IsHidden` flag is stored alongside the cached update metadata. Resetting the cache (renaming `SoftwareDistribution`) destroys that metadata, so the hide must happen on a fresh post-reboot scan.
- Guardrail/rule: The correct workflow is: **[5] Reset Cache → Reboot → [2] Hide Updates**. Both the main menu and the Hide function display this warning prominently. `Reset-UpdateCache` now auto-purges any existing `.old_*` backup folders before creating new ones, and a new menu option `[6] Clean Stale Backup Folders` allows manual cleanup.
- Files affected: `ManageUpdates.ps1`, `PROJECT_RULES.md`.
- Validation/tests run: Static review of workflow warnings, `Remove-StaleOldFolders` function, and menu integration.

### Entry - 2026-03-04 (ManageUpdates.ps1 missing from InstallerCore profile)
- Date: 2026-03-04
- Problem: Option `[3] Windows Update Manager` failed with "not recognized as a script file" when running from the installed location (`%LOCALAPPDATA%\SystemCleanupContext\`), but worked from the source repo.
- Root cause: `ManageUpdates.ps1` was never added to the `InstallerCore` profile's `required_package_entries`, `deploy_entries`, or `verify_core_files`. The installer never copied it to the install directory.
- Guardrail/rule: When adding new scripts that are called by existing scripts (like `SystemCleanup.cmd`), always update the InstallerCore profile to include them in deploy/verify lists, then regenerate the installer.
- Files affected: `InstallerCore/profiles/SystemCleanup.json`, `Install.ps1` (regenerated), `PROJECT_RULES.md`.
- Validation/tests run: Verified `ManageUpdates.ps1` absent from installed directory; confirmed profile update adds it to all 3 lists; re-install required to deploy the missing file.

### Entry - 2026-03-04 (ESC returns to main menu + menu loop)
- Date: 2026-03-04
- Problem: Pressing `[X]` in `ManageUpdates.ps1` submenus or the CMD main menu closed the entire tool. Users wanted to navigate back instead of exiting.
- Root cause: The CMD script used `exit /b` after each option, and `ManageUpdates.ps1` used `Read-Host` for menu input which required Enter.
- Guardrail/rule: `SystemCleanup.cmd` now loops on all options via `goto :Menu` instead of `exit /b`. `ManageUpdates.ps1` uses `ReadKey` for menu navigation so ESC instantly returns to the CMD main menu. Both `ESC` and `X` exit the PS script loop.
- Files affected: `SystemCleanup.cmd`, `ManageUpdates.ps1`, `PROJECT_RULES.md`.
- Validation/tests run: Static review of `goto` flow and ReadKey-based menu input.

### Entry - 2026-03-04 (Block Windows 11 upgrade via Group Policy)
- Date: 2026-03-04
- Problem: Users on Windows 10 wanted to prevent Windows 11 from being offered via Windows Update.
- Root cause: No built-in toggle — requires manual Group Policy registry edits.
- Guardrail/rule: New option `[7]` in `ManageUpdates.ps1` toggles `TargetReleaseVersion` / `TargetReleaseVersionInfo` / `ProductVersion` under `HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate`. Auto-detects current Win10 build. Shows live status indicator on menu (blocked/not blocked). Warns if already on Windows 11. Runs `gpupdate /force` after changes. On unblock, cleans up the registry key entirely if empty.
- Files affected: `ManageUpdates.ps1`, `PROJECT_RULES.md`.
- Validation/tests run: Static review of registry operations and toggle logic; OS build detection via `OSVersion.Version.Build`.
