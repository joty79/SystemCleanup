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

### Entry - 2026-03-10 (Fix false-positive Win11 block status in ManageUpdates)
- Date: 2026-03-10
- Problem: Option `[7] Block Windows 11 Upgrade` could show `Blocked` in the menu even when the effective policy was not correctly configured.
- Root cause: The script used `Set-ItemProperty -Type`, which is invalid in PowerShell 7, and the status check only validated a partial subset of the required policy values.
- Guardrail/rule: For this repo, machine-policy writes in `ManageUpdates.ps1` must use a PowerShell 7-compatible write path with immediate readback verification. The Win11 block status must require all three policy values (`TargetReleaseVersion=1`, `ProductVersion=Windows 10`, `TargetReleaseVersionInfo=22H2`) before the menu reports the policy as active.
- Files affected: `ManageUpdates.ps1`, `PROJECT_RULES.md`.
- Validation/tests run: PowerShell parser validation on `ManageUpdates.ps1`; static review of write/remove verification and menu status flow.

### Entry - 2026-03-10 (Harden Reset-UpdateCache against partial success)
- Date: 2026-03-10
- Problem: `Reset-UpdateCache` could appear to succeed even when the Windows Update cache was only partially reset, leading to inconsistent hide/reset behavior across repeated attempts.
- Root cause: The script used blind `net stop` calls without waiting for service state transitions, used weak rename verification, and always printed a success-style completion path after restarting services.
- Guardrail/rule: In this repo, `Reset-UpdateCache` must wait for core service stop/start transitions, attempt to quiet `UsoSvc`/`DoSvc`, move cache folders with explicit verification, and report partial reset instead of false success when `SoftwareDistribution` or `catroot2` was not fully reset.
- Files affected: `ManageUpdates.ps1`, `PROJECT_RULES.md`.
- Validation/tests run: PowerShell parser validation on `ManageUpdates.ps1`; static review of service wait/move verification logic.

### Entry - 2026-03-10 (Document user-facing behavior changes in README + CHANGELOG)
- Date: 2026-03-10
- Problem: Documentation updates were being handled ad hoc after user-facing fixes, so troubleshooting/status changes could remain only in code and chat context.
- Root cause: The repo had no explicit documentation review rule tied to behavior changes.
- Guardrail/rule: After every user-facing behavior change or troubleshooting-relevant fix, explicitly review whether `README.md` needs an update. Record notable shipped changes in `CHANGELOG.md` even when the README does not need to change.
- Files affected: `README.md`, `CHANGELOG.md`, `PROJECT_RULES.md`.
- Validation/tests run: Static review of README troubleshooting/status sections and changelog entry coverage.

### Entry - 2026-03-12 (Separate live SoftwareDistribution cleanup from reset workflow)
- Date: 2026-03-12
- Problem: `Reset Update Cache` helped with hide/troubleshooting flows, but it did not provide a direct post-update disk cleanup path for the live `SoftwareDistribution\Download` cache that can grow very large after monthly updates.
- Root cause: The repo only implemented rename-based reset semantics for `SoftwareDistribution`, not a separate live-cache cleanup action for reclaiming space without touching `DataStore` history.
- Guardrail/rule: Keep `Reset Update Cache` as the troubleshooting/reset path, and expose live cleanup as a separate menu action. The live cleanup targets `C:\Windows\SoftwareDistribution\Download`, shows the current cache size both in the menu and before confirmation, stops update services temporarily, deletes what it can immediately, and only uses reboot-time deletion as a fallback for locked leftovers.
- Files affected: `ManageUpdates.ps1`, `README.md`, `CHANGELOG.md`, `PROJECT_RULES.md`
- Validation/tests run: PowerShell parser validation on `ManageUpdates.ps1`; static review of menu numbering, live-cache target scope, and reboot-fallback behavior.

### Entry - 2026-03-12 (Promote post-update cleanup actions to main menu)
- Date: 2026-03-12
- Problem: The new live `SoftwareDistribution` cleanup and the planned `Disk Cleanup Utility`-based Windows Update cleanup are post-update disk-recovery actions, not update-management/troubleshooting actions, so keeping them inside the Windows Update Manager submenu made the main workflow harder to follow.
- Root cause: The menu structure was optimized around update-management grouping instead of the user's real post-update cleanup sequence.
- Guardrail/rule: Keep post-update cleanup actions in the main `SystemCleanup.cmd` menu: `Live SoftwareDistribution Cleanup` as option `[3]` and `Windows Update Cleanup (Disk Cleanup Utility)` as option `[4]`. Keep `Windows Update Manager` focused on list/hide/unhide, reset cache, stale backup cleanup, and Win11 policy block. The `cleanmgr` action must run via an isolated dedicated slot (`cleanmgr /sagerun:88`) and show `AnalyzeComponentStore` status before and after execution instead of inventing a fake size estimate.
- Files affected: `SystemCleanup.cmd`, `ManageUpdates.ps1`, `README.md`, `CHANGELOG.md`, `PROJECT_RULES.md`
- Validation/tests run: PowerShell parser validation on `ManageUpdates.ps1`; static review of main-menu numbering, isolated `cleanmgr` slot handling, and updated documentation.

### Entry - 2026-03-12 (Fix CMD quoting for live cache size probe)
- Date: 2026-03-12
- Problem: Opening the main menu could print `'pwsh" -NoProfile ... is not recognized` before rendering the options, and the gray line for main-menu option `[3]` fell back to the generic text instead of the live size.
- Root cause: The `for /f` PowerShell probe in `SystemCleanup.cmd` used broken `cmd.exe` quoting with `usebackq` and an embedded quoted executable token.
- Guardrail/rule: For `cmd.exe` inline PowerShell probes, keep the executable token unquoted when it is a simple command name (`pwsh` / `powershell`), escape pipeline characters with `^|`, and avoid `usebackq` unless it is strictly needed.
- Files affected: `SystemCleanup.cmd`, `CHANGELOG.md`, `PROJECT_RULES.md`
- Validation/tests run: Static review of CMD quoting; `git diff --check`.

### Entry - 2026-03-12 (Prefer file-based PowerShell calls over CMD inline probes)
- Date: 2026-03-12
- Problem: Even after the first quoting fix, the main-menu live cache status probe could still break with `Unexpected token 'Download'` because `cmd.exe` and PowerShell string parsing remained too fragile.
- Root cause: The batch file was still embedding non-trivial PowerShell expressions inline inside `for /f`, which is brittle for quotes, pipes, and strings with spaces.
- Guardrail/rule: In this repo, when `SystemCleanup.cmd` needs computed PowerShell output for menu text, prefer `-File "%~dp0ManageUpdates.ps1" -Action ...` over inline `-Command` snippets. Keep menu-status computation inside PowerShell, not in batch quoting.
- Files affected: `ManageUpdates.ps1`, `SystemCleanup.cmd`, `CHANGELOG.md`, `PROJECT_RULES.md`
- Validation/tests run: PowerShell parser validation on `ManageUpdates.ps1`; `git diff --check`.

### Entry - 2026-03-12 (Define explicit ANSI colors for main-menu options)
- Date: 2026-03-12
- Problem: Main-menu options `[4]` and `[5]` both rendered as white, so the new cleanup actions did not visually separate well.
- Root cause: `SystemCleanup.cmd` referenced `%cMagenta%` without defining it, and option `[5]` reused `%cWhite%`.
- Guardrail/rule: Keep every menu color token explicitly defined in `SystemCleanup.cmd`. For the current main menu, use `magenta` for `[4] Windows Update Cleanup` and `blue` for `[5] Windows Update Manager` so adjacent options stay visually distinct.
- Files affected: `SystemCleanup.cmd`, `CHANGELOG.md`, `PROJECT_RULES.md`
- Validation/tests run: Static review of ANSI variable definitions and menu color usage.

### Entry - 2026-03-12 (Use real ESC key for CMD main menu exit)
- Date: 2026-03-12
- Problem: The main `SystemCleanup.cmd` launcher still advertised `[X] Close / Cancel`, while the rest of the tool had moved toward `ESC`-based navigation.
- Root cause: The CMD launcher still used `set /p`, which cannot read a real Escape keypress directly.
- Guardrail/rule: The main CMD menu should advertise `[ESC] Close / Cancel` and read the actual Escape key through a PowerShell `ReadKey` action, keeping the launcher behavior aligned with the PowerShell submenu navigation.
- Files affected: `SystemCleanup.cmd`, `ManageUpdates.ps1`, `README.md`, `CHANGELOG.md`, `PROJECT_RULES.md`
- Validation/tests run: PowerShell parser validation on `ManageUpdates.ps1`; static review of main-menu key handling.

### Entry - 2026-03-12 (Avoid hardcoded duration promises in main menu)
- Date: 2026-03-12
- Problem: Main-menu option `[1] Full Cleanup` still said `Takes 20-40 minutes`, which is misleading on many systems and looked inconsistent next to the description-style text used by the other menu items.
- Root cause: The original launcher menu used a rough duration estimate instead of describing the action.
- Guardrail/rule: In the main menu, prefer describing what an action does over giving fixed time estimates unless the timing is genuinely stable. For `[1] Full Cleanup`, keep the gray line as a task summary, not a duration promise.
- Files affected: `SystemCleanup.cmd`, `README.md`, `CHANGELOG.md`, `PROJECT_RULES.md`
- Validation/tests run: Static review of main-menu text and README wording.

### Entry - 2026-03-12 (Use reg.exe for isolated cleanmgr slot writes)
- Date: 2026-03-12
- Problem: Running `Windows Update Cleanup (Disk Cleanup Utility)` could fail immediately with `Argument types do not match` before `cleanmgr` even started.
- Root cause: The isolated `StateFlags0088` setup/restore path used the PowerShell registry provider in a way that proved brittle for this `VolumeCaches` workflow and produced poor error behavior.
- Guardrail/rule: For the isolated `cleanmgr /sagerun:88` slot in this repo, use `reg.exe add/delete` for `VolumeCaches` state-flag writes and restores instead of the PowerShell registry provider. If the process is not elevated, surface the access failure directly instead of masking it behind a binder-style exception.
- Files affected: `ManageUpdates.ps1`, `CHANGELOG.md`, `PROJECT_RULES.md`
- Validation/tests run: PowerShell parser validation on `ManageUpdates.ps1`; dry-run helper invocation showed clear `Access is denied` in a non-elevated shell instead of the previous binder exception.

### Entry - 2026-03-12 (wt branch: relay launcher into Windows Terminal when possible)
- Date: 2026-03-12
- Problem: The current CMD launcher preserves the desired layout, but emoji/Nerd Font rendering and overall console appearance are much better in Windows Terminal than in the classic console host.
- Root cause: The context-menu command still launches `SystemCleanup.cmd` through `cmd.exe`, so the tool always starts in the classic console unless it explicitly relaunches itself.
- Guardrail/rule: On the experimental `wt` branch, keep the existing CMD UI and logic, but after elevation relay into `wt.exe` when all three conditions are true: not already inside Windows Terminal, `wt.exe` is available, and the system is not in Safe Mode. If any of those checks fail, continue in the classic console host without breaking the existing workflow.
- Files affected: `SystemCleanup.cmd`, `README.md`, `CHANGELOG.md`, `PROJECT_RULES.md`
- Validation/tests run: Static review of launcher flow, argument relay, and Safe Mode / missing-`wt` fallback conditions.

### Entry - 2026-03-12 (wt branch: prefer temp launcher over inline wt command string)
- Date: 2026-03-12
- Problem: The first `wt.exe` relay attempt could behave like a stuck/looped keypress in the main menu, and Windows Terminal showed a suspicious `cmd.exe - call` tab title.
- Root cause: The inline `cmd.exe /k call "...SystemCleanup.cmd" --wt-hosted` argument string was too fragile for Windows Terminal command parsing.
- Guardrail/rule: On the `wt` branch, when relaunching into Windows Terminal, prefer a temporary `.cmd` trampoline file over an inline `call` command string. This keeps the `cmd.exe` startup command simple and reduces WT argument-parsing surprises.
- Files affected: `SystemCleanup.cmd`, `CHANGELOG.md`, `PROJECT_RULES.md`
- Validation/tests run: Static review of the temp-launcher relay flow.

### Entry - 2026-03-12 (wt branch: switch primary launcher to SystemCleanup.ps1)
- Date: 2026-03-12
- Problem: Even with a `wt.exe` relay, keeping the main interactive UI inside `SystemCleanup.cmd` kept dragging batch-host quirks into the experiment.
- Root cause: The original tool architecture used CMD as the primary menu host and PowerShell only for sub-actions.
- Guardrail/rule: On the `wt` branch, the primary interactive entrypoint is `SystemCleanup.ps1`, not `SystemCleanup.cmd`. Installer profile entries and the static `.reg` command path should target `pwsh.exe -NoProfile -ExecutionPolicy Bypass -File "{InstallRoot}\SystemCleanup.ps1"`. Keep `SystemCleanup.cmd` only as a legacy compatibility artifact while the PowerShell launcher is evaluated.
- Files affected: `SystemCleanup.ps1`, `Install.ps1`, `SystemCleanup.reg`, `.gitignore`, `README.md`, `CHANGELOG.md`, `PROJECT_RULES.md`
- Validation/tests run: PowerShell parser validation on `SystemCleanup.ps1`; static review of installer profile and `.reg` command strings.

### Entry - 2026-03-12 (wt branch: logging must not depend on D: existing)
- Date: 2026-03-12
- Problem: The new PowerShell launcher could fail immediately on machines or VMs that only had a `C:` drive because logging still hardcoded `D:\Temp\SystemCleanup`.
- Root cause: The `wt` branch switched the main menu into `SystemCleanup.ps1`, but its logging path logic still assumed the desktop machine's `D:` layout instead of probing for a writable path.
- Guardrail/rule: On the `wt` branch, `SystemCleanup.ps1` should prefer `D:\Temp\SystemCleanup` for logs but must automatically fall back to a writable local path such as `%LOCALAPPDATA%\SystemCleanupContext\logs` or `%TEMP%\SystemCleanup`. Logging failures must never abort the cleanup flow.
- Files affected: `SystemCleanup.ps1`, `README.md`, `CHANGELOG.md`, `PROJECT_RULES.md`
- Validation/tests run: PowerShell parser validation on `SystemCleanup.ps1`; static review of fallback path selection and no-throw log writes.

### Entry - 2026-03-12 (wt branch: keep native SFC/DISM progress + strict-safe CleanInFlight)
- Date: 2026-03-12
- Problem: In the experimental PowerShell/Windows Terminal launcher, `Full Cleanup` lost the familiar native `SFC` / `DISM` progress display, and `CleanInFlight.ps1` could crash with `The property 'Count' cannot be found on this object`.
- Root cause: Native servicing tools were being launched directly from the PowerShell host, while `CleanInFlight.ps1` still used `.Count` on values that may be a single object under strict execution.
- Guardrail/rule: On the `wt` branch, keep the main menu in `SystemCleanup.ps1`, but run `SFC` and `DISM` stages through `cmd.exe` so the classic progress rendering survives inside Windows Terminal. Also keep `CleanInFlight.ps1` array-safe by using `@(...).Count` for empty-folder checks.
- Files affected: `SystemCleanup.ps1`, `CleanInFlight.ps1`, `README.md`, `CHANGELOG.md`, `PROJECT_RULES.md`
- Validation/tests run: PowerShell parser validation on `SystemCleanup.ps1` and `CleanInFlight.ps1`; static review of `cmd.exe` native-stage invocation.
