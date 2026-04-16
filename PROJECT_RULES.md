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

### Entry - 2026-03-12 (wt branch: run Full Cleanup in a dedicated WT cmd pane)
- Date: 2026-03-12
### Entry - 2026-04-16 (Promote SystemCleanup to current UI + installer contract)
- Date: 2026-04-16
- Problem: `SystemCleanup` had fallen behind the newer PowerShell UI and InstallerCore contract used by newer tools, so the repo still relied on an older launcher presentation, no canonical app metadata file, and a profile drift between `InstallerCore` and the downstream generated installer.
- Root cause: Most recent UI/template improvements landed first in `WinAppManager` and `InstallerCore`, but this older repo was never migrated forward to those shared patterns.
- Guardrail/rule: `SystemCleanup` should use `app-metadata.json` as the canonical source for app name/version/repo, keep `SystemCleanup.ps1` as the primary launcher/UI entrypoint, and treat `Install.ps1` as generated output from the current `InstallerCore` profile/template rather than a bespoke downstream script.
- Files affected: `app-metadata.json`, `SystemCleanup.ps1`, `Install.ps1`, `.gitignore`, `README.md`, `CHANGELOG.md`, `PROJECT_RULES.md`
- Validation/tests run: PowerShell parser validation on `SystemCleanup.ps1` and regenerated `Install.ps1`; static review of updated `InstallerCore` profile and repo-local metadata contract.
- Problem: Simply invoking `cmd.exe /c ...` from inside the PowerShell-hosted WT menu was not enough; option `[1]` still behaved like an inline PowerShell run and did not give the intended separate native-servicing view.
- Root cause: The previous experiment changed the process used for native commands, but not the actual pane host or pane lifecycle.
- Guardrail/rule: On the `wt` branch, when `WT_SESSION` is present, main-menu option `[1] Full Cleanup` should open a dedicated Windows Terminal split pane and run `FullCleanup.cmd` there. Keep the menu pane separate, and keep `FullCleanup.cmd` installer-tracked so installed copies can use the same split-pane flow.
- Files affected: `SystemCleanup.ps1`, `FullCleanup.cmd`, `Install.ps1`, `README.md`, `CHANGELOG.md`, `PROJECT_RULES.md`
- Validation/tests run: PowerShell parser validation on `SystemCleanup.ps1`; static review of WT `split-pane` argument flow and installer deploy lists.

### Entry - 2026-03-12 (wt branch: preserve classic Full Cleanup look in split pane)
- Date: 2026-03-12
- Problem: The first `FullCleanup.cmd` runner looked visually flatter than the original CMD flow and failed by trying to execute the quoted step title instead of the real `SFC` / `DISM` command.
- Root cause: The quick split-pane runner used plain `echo` output and a broken `call %*` helper that treated the quoted title as the executable token.
- Guardrail/rule: On the `wt` branch, `FullCleanup.cmd` should preserve the classic CMD full-cleanup styling as closely as possible and invoke step commands through an explicit command argument (`%~2`), not by replaying the entire raw argument list.
- Files affected: `FullCleanup.cmd`, `CHANGELOG.md`, `PROJECT_RULES.md`
- Validation/tests run: Static review of ANSI styling, batch command dispatch, and log-write guard.

### Entry - 2026-03-12 (wt branch: pane should close after final keypress)
- Date: 2026-03-12
- Problem: After `Full Cleanup` finished in the WT split pane, pressing a key returned to a plain `C:\...>` prompt instead of closing the pane.
- Root cause: The pane was launched with `cmd.exe /k`, which keeps the shell open even after `FullCleanup.cmd` exits.
- Guardrail/rule: For the `wt` branch split-pane full cleanup flow, launch the runner with `cmd.exe /c`, not `/k`, so the pane closes cleanly after the final `pause`/keypress.
- Files affected: `SystemCleanup.ps1`, `CHANGELOG.md`, `PROJECT_RULES.md`
- Validation/tests run: Static review of WT split-pane argument list.

### Entry - 2026-03-12 (strict-safe size summary for live SoftwareDistribution cleanup)
- Date: 2026-03-12
- Problem: Main-menu option `[3] Live SoftwareDistribution Cleanup` could complete the actual cleanup successfully but then crash while printing the final `Before / After / Freed` size summary.
- Root cause: The size helper in `ManageUpdates.ps1` accessed `.Sum` directly on the `Measure-Object` result, which is brittle under strict execution when the property/value is absent or null.
- Guardrail/rule: In this repo, size-summary helpers should read measured properties through `PSObject.Properties[...]` and treat missing/null values as `0` instead of assuming `.Sum` is always safe to access directly.
- Files affected: `ManageUpdates.ps1`, `CHANGELOG.md`, `PROJECT_RULES.md`
- Validation/tests run: PowerShell parser validation on `ManageUpdates.ps1`; static review of strict-safe size-summary path.

### Entry - 2026-03-13 (Targeted debug logging for Windows Update Cleanup)
- Date: 2026-03-13
- Problem: `Windows Update Cleanup (Disk Cleanup Utility)` showed machine-specific hangs/weird focus behavior under WT-backed sessions, but the existing output gave no visibility into slot state or process lifecycle.
- Root cause: The `cleanmgr /sagerun:88` path had no targeted diagnostics for `VolumeCaches` slot isolation, spawned `cleanmgr` PIDs, or lingering processes after the visible UI stopped responding.
- Guardrail/rule: Keep troubleshooting output for option `[4]` in a dedicated debug log under `%LOCALAPPDATA%\SystemCleanupContext\logs`. Record `StateFlags` snapshots before/after isolate and restore, `cleanmgr` process snapshots, and periodic heartbeats while waiting, instead of turning on verbose logging globally.
- Files affected: `ManageUpdates.ps1`, `README.md`, `CHANGELOG.md`, `PROJECT_RULES.md`
- Validation/tests run: PowerShell parser validation on `ManageUpdates.ps1`; static review of debug-log path, slot snapshots, and heartbeat logging.

### Entry - 2026-03-13 (WT-safe launch mode for Windows Update Cleanup)
- Date: 2026-03-13
- Problem: Debug logs showed that option `[4]` isolated the `Update Cleanup` slot correctly, but `cleanmgr` could still hang/focus-stall when it was launched and waited inline from a WT-hosted session.
- Root cause: The issue was not the `StateFlags0088` isolation; it was the `cleanmgr` GUI/process lifecycle under `WT_SESSION`, especially on first run on some machines.
- Guardrail/rule: For option `[4]`, when `WT_SESSION` is present, launch `cleanmgr /sagerun:88` via an external classic `cmd` window and clear WT-specific environment variables for that child process. Keep the existing direct path only for non-WT sessions.
- Files affected: `ManageUpdates.ps1`, `README.md`, `CHANGELOG.md`, `PROJECT_RULES.md`
- Validation/tests run: PowerShell parser validation on `ManageUpdates.ps1`; static review of WT-session detection and external `cmd` launch path.

### Entry - 2026-03-13 (Accurate child-process debug for external cleanmgr launch)
- Date: 2026-03-13
- Problem: The first targeted debug log for option `[4]` could misleadingly report the external `cmd` wrapper PID as if it were the real `cleanmgr` process.
- Root cause: In WT-safe fallback mode the code waited on the wrapper process but did not distinguish that wrapper from newly spawned `cleanmgr` children.
- Guardrail/rule: For external `cmd` launches of `cleanmgr`, capture a baseline of existing `cleanmgr` PIDs, log the wrapper PID separately, and record newly observed `cleanmgr` child PIDs via snapshot diff so the troubleshooting log reflects the real process lifecycle.
- Files affected: `ManageUpdates.ps1`, `CHANGELOG.md`, `PROJECT_RULES.md`
- Validation/tests run: PowerShell parser validation on `ManageUpdates.ps1`; static review of baseline-vs-child process logging.

### Entry - 2026-03-13 (Direct cleanmgr launch + auto-activation via SetForegroundWindow)
- Date: 2026-03-13
- Problem: Option `[4]` Windows Update Cleanup launched `cleanmgr` via an external `cmd` window (WT-safe fallback), but on laptops and older PCs the `cleanmgr` GUI would hang indefinitely until manually clicked/focused. The external `cmd` window was also unwanted visual noise.
- Root cause: `cleanmgr /sagerun` on some machines spawns a progress dialog that requires window focus/activation before it starts processing. The external cmd wrapper also exited before `cleanmgr` children finished, causing the script to restore the registry slot prematurely.
- Guardrail/rule: For option `[4]`, always launch `cleanmgr` directly (no external `cmd` wrapper). After launch, use Win32 `SetForegroundWindow` + `ShowWindow(SW_RESTORE)` via P/Invoke to auto-activate any `cleanmgr` GUI windows. After the parent process exits, enter a tail-wait loop that monitors and activates any detached child `cleanmgr` processes. Also: never use `$pid` as a variable name inside helper functions — it is a read-only PowerShell automatic variable.
- Files affected: `ManageUpdates.ps1`, `PROJECT_RULES.md`
- Validation/tests run: Live run from WT session confirmed `cleanmgr` completes without manual interaction; debug log verified direct launch + immediate exit when no cleanup needed.

### Entry - 2026-03-25 (Full Cleanup must include DISM /ResetBase)
- Date: 2026-03-25
- Problem: The repo described `Full Cleanup` as the user's preferred aggressive servicing flow, but the actual runtime paths still stopped at plain `DISM StartComponentCleanup`, leaving the `/ResetBase` step out entirely.
- Root cause: The earlier decision to prefer the more reliable `DISM /ResetBase` servicing cleanup over the flaky `cleanmgr` path never got propagated into all three shipped Full Cleanup entrypoints.
- Guardrail/rule: In this repo, `Full Cleanup` means `SFC -> DISM AnalyzeComponentStore -> DISM RestoreHealth -> DISM StartComponentCleanup /ResetBase -> CleanInFlight -> final SFC`. Keep `SystemCleanup.cmd`, `FullCleanup.cmd`, `SystemCleanup.ps1`, and the README flow text aligned with that exact sequence. Treat the separate `Windows Update Cleanup (Disk Cleanup Utility)` action as an optional legacy `cleanmgr` path, not the primary component-store cleanup path.
- Files affected: `SystemCleanup.cmd`, `FullCleanup.cmd`, `SystemCleanup.ps1`, `README.md`, `CHANGELOG.md`, `PROJECT_RULES.md`
- Validation/tests run: PowerShell parser validation on `SystemCleanup.ps1`; static review of CMD/README sequence alignment.

### Entry - 2026-03-25 (Remove cleanmgr path from the main GUI)
- Date: 2026-03-25
- Problem: The main-menu `Windows Update Cleanup (Disk Cleanup Utility)` action remained flaky and random in real use, so keeping it in the visible GUI kept inviting users into an unreliable path we had already decided not to rely on.
- Root cause: The repo had kept the `cleanmgr /sagerun:88` action exposed in the launcher even after `Full Cleanup` was updated to use the preferred `DISM /ResetBase` servicing path.
- Guardrail/rule: Do not expose `Windows Update Cleanup (Disk Cleanup Utility)` in the main `SystemCleanup` GUI. Keep `cleanmgr` non-primary and undocumented in the normal user flow. The current main-menu maintenance surface may grow, but `cleanmgr` must stay out of the visible primary launcher.
- Files affected: `SystemCleanup.ps1`, `SystemCleanup.cmd`, `README.md`, `CHANGELOG.md`, `PROJECT_RULES.md`
- Validation/tests run: PowerShell parser validation on `SystemCleanup.ps1`; static review of main-menu numbering and README menu references.

### Entry - 2026-03-25 (Show actionable DISM failure details)
- Date: 2026-03-25
- Problem: Generic `[X] FAILED` output was too vague when `DISM` failed on custom/VM images, forcing manual log hunting before the real servicing error became visible.
- Root cause: The launcher only reported a pass/fail banner and logged the numeric code internally, without surfacing the `DISM`/`CBS` log locations or likely servicing-path hints in the console UI.
- Guardrail/rule: When a `DISM` stage fails, print the native exit code in the console, point directly to `C:\Windows\Logs\DISM\dism.log` and `C:\Windows\Logs\CBS\CBS.log`, and include a short hint for `Error 3 / 0x80070003` servicing-path failures. Keep this behavior aligned across `SystemCleanup.ps1`, `SystemCleanup.cmd`, and `FullCleanup.cmd`.
- Files affected: `SystemCleanup.ps1`, `SystemCleanup.cmd`, `FullCleanup.cmd`, `README.md`, `CHANGELOG.md`, `PROJECT_RULES.md`
- Validation/tests run: PowerShell parser validation on `SystemCleanup.ps1`; static review of CMD/PowerShell DISM failure messaging.

### Entry - 2026-03-25 (Surface recent DISM/CBS error lines after DISM failure)
- Date: 2026-03-25
- Problem: Even after adding exit-code/log-path hints, users still had to open `dism.log` and `CBS.log` manually to see the actual failure lines, slowing diagnosis on VMs and custom images.
- Root cause: The launcher exposed where the logs were, but not the most relevant recent `DISM` / `CBS` lines that explain the failure.
- Guardrail/rule: After a `DISM` stage fails, automatically print a short tail of recent relevant `DISM` and `CBS` log lines in the console. Keep the summary concise and aligned across `SystemCleanup.ps1`, `SystemCleanup.cmd`, and `FullCleanup.cmd` by using the shared `ManageUpdates.ps1` action.
- Files affected: `ManageUpdates.ps1`, `SystemCleanup.ps1`, `SystemCleanup.cmd`, `FullCleanup.cmd`, `README.md`, `CHANGELOG.md`, `PROJECT_RULES.md`
- Validation/tests run: PowerShell parser validation on `SystemCleanup.ps1` and `ManageUpdates.ps1`; static review of shared log-summary invocation.

### Entry - 2026-03-25 (Prioritize real CBS missing-path clues over finalize noise)
- Date: 2026-03-25
- Problem: The first automatic `CBS` summaries could still surface low-signal finalize/cleanup lines instead of the actual root-cause clues such as missing `InFlight` paths or the failing filename.
- Root cause: The summary picker selected the latest matching lines, not the highest-signal lines.
- Guardrail/rule: Rank recent `DISM`/`CBS` matches so root-cause clues like `RBDSTAMIL99`, `WinSxS\Temp\InFlight`, `STATUS_OBJECT_PATH_NOT_FOUND`, and `ERROR_PATH_NOT_FOUND` appear before generic finalize noise. Keep the output short, but prefer specificity over recency.
- Files affected: `ManageUpdates.ps1`, `README.md`, `CHANGELOG.md`, `PROJECT_RULES.md`
- Validation/tests run: PowerShell parser validation on `ManageUpdates.ps1`; local invocation of `ManageUpdates.ps1 -Action DismFailureSummary`.

### Entry - 2026-03-25 (Keep DISM/CBS failure clues narrow-pane friendly)
- Date: 2026-03-25
- Problem: Even prioritized raw log lines still looked bad in narrow Windows Terminal split panes because long `DISM` / `CBS` records wrapped across many console rows.
- Root cause: The summary still echoed full log lines instead of compact human-readable clues.
- Guardrail/rule: For the automatic `DISM` failure summary, prefer concise clue lines over raw log lines. Extract the missing path, HRESULT, or action summary when possible, and shorten long `InFlight` paths so the output remains readable in WT split panes.
- Files affected: `ManageUpdates.ps1`, `README.md`, `CHANGELOG.md`, `PROJECT_RULES.md`
- Validation/tests run: PowerShell parser validation on `ManageUpdates.ps1`; local invocation of `ManageUpdates.ps1 -Action DismFailureSummary`.

### Entry - 2026-03-25 (Expose non-compact servicing details from the main menu)
- Date: 2026-03-25
- Problem: The compact `WT`-friendly `DISM` failure summary works well in split panes, but users still need an easy way to open a wider non-compact servicing log view from the main menu.
- Root cause: The launcher only exposed the compact on-failure summary and had no dedicated main-menu route for a wider `DISM` / `CBS` detail view.
- Guardrail/rule: Keep the on-failure `DISM`/`CBS` summary compact for split panes, and also expose a main-menu option `[6] Last DISM/CBS Failure Details` that shows a wider non-compact recent servicing log view. Keep this aligned across `SystemCleanup.ps1`, `SystemCleanup.cmd`, and the shared `ManageUpdates.ps1` action set.
- Files affected: `ManageUpdates.ps1`, `SystemCleanup.ps1`, `SystemCleanup.cmd`, `README.md`, `CHANGELOG.md`, `PROJECT_RULES.md`
- Validation/tests run: PowerShell parser validation on `SystemCleanup.ps1` and `ManageUpdates.ps1`; static review of main-menu numbering and shared action wiring.

### Entry - 2026-03-25 (Safe Delivery Optimization cleanup + disable path)
- Date: 2026-03-25
- Problem: Users wanted a visible main-menu way to see whether Delivery Optimization peer sharing is off, see the current cache size, and reclaim Delivery Optimization cache space without manually hunting through Settings or raw folders.
- Root cause: The repo had no Delivery Optimization status probe or cleanup action, and a naive implementation could have disabled the `DoSvc` service directly instead of using the safer supported peer-disable path.
- Guardrail/rule: In this repo, Delivery Optimization "disable" means forcing `DODownloadMode = 0 (CdnOnly)` so peer-to-peer caching is off while Windows Update / Microsoft Store downloads still work from Microsoft/CDN. Prefer the native Delivery Optimization cmdlets (`Get-DOConfig`, `Get-DeliveryOptimizationPerfSnap`, `Delete-DeliveryOptimizationCache`) for status/cache handling instead of manual cache-folder deletion or direct `DoSvc` service disable. Expose this as main-menu option `[4]` with a live `Disabled/Enabled + cache size` description line.
- Files affected: `ManageUpdates.ps1`, `SystemCleanup.ps1`, `SystemCleanup.cmd`, `README.md`, `CHANGELOG.md`, `PROJECT_RULES.md`
- Validation/tests run: PowerShell parser validation on `ManageUpdates.ps1` and `SystemCleanup.ps1`; local non-admin status probe via `Get-DOConfig` / `Get-DeliveryOptimizationPerfSnap`; static review of main-menu wiring.

### Entry - 2026-03-25 (Launcher-level InstallerCore self-update shortcut)
- Date: 2026-03-25
- Problem: The repo already shipped a working InstallerCore-generated `Install.ps1` with `Update` / `UpdateGitHub` / `DownloadLatest`, but the main interactive launcher had no easy self-update entrypoint, so users had to remember installer actions separately.
- Root cause: Installer behavior lived in the sibling generated installer, while the main runtime launcher had no generic bridge into that updater flow.
- Guardrail/rule: For InstallerCore-onboarded launcher repos, prefer a launcher-level self-update shortcut that reuses the sibling `Install.ps1` instead of inventing a second updater. Detect mode generically: git repo copy -> `DownloadLatest`, installed copy with `state\install-meta.json` -> `UpdateGitHub`, portable fallback -> `DownloadLatest`. Keep the helper naming/tooling generic enough that the same pattern can later be lifted into the `InstallerCore` template or copied into other PowerShell main-menu tools.
- Files affected: `ManageUpdates.ps1`, `SystemCleanup.ps1`, `SystemCleanup.cmd`, `README.md`, `CHANGELOG.md`, `PROJECT_RULES.md`
- Validation/tests run: PowerShell parser validation on `ManageUpdates.ps1` and `SystemCleanup.ps1`; local non-admin status probe via `ManageUpdates.ps1 -Action ToolSelfUpdateStatus`; static review of main-menu wiring and sibling `Install.ps1` detection.

### Entry - 2026-03-25 (Self-update UI must expose InstallerCore defaults, not backend action names)
- Date: 2026-03-25
- Problem: The first launcher self-update bridge surfaced backend action names like `UpdateGitHub` and did not offer an easy way to switch source/branch without remembering InstallerCore arguments.
- Root cause: The launcher exposed internal action labels instead of user-facing InstallerCore terms and treated alternate source/branch selection as an implementation detail.
- Guardrail/rule: For launcher-level self-update, present defaults using user-facing InstallerCore labels such as `Installer Mode`, `GitHub branch`, and `Local source`. Keep `Enter = use displayed defaults`, `E = open the standard sibling Install.ps1 interactive menu`, and `ESC = cancel`. Do not duplicate Local/GitHub/branch chooser logic inside the launcher when InstallerCore already owns that UI.
- Files affected: `ManageUpdates.ps1`, `README.md`, `CHANGELOG.md`, `PROJECT_RULES.md`
- Validation/tests run: PowerShell parser validation on `ManageUpdates.ps1`; local non-admin status probe via `ManageUpdates.ps1 -Action ToolSelfUpdateStatus`; static review of Enter/E/ESC flow.

### Entry - 2026-03-25 (Self-update prompt should explain persistence and keep choices scannable)
- Date: 2026-03-25
- Problem: Even after switching to `Installer Mode` / `GitHub branch`, the self-update choice line was still dense, and it was unclear whether a changed GitHub branch or Local/GitHub selection would persist to the next run.
- Root cause: The launcher compressed all choices into one sentence and did not surface the difference between installed-copy saved defaults and repo-copy branch detection.
- Guardrail/rule: Keep the self-update choice prompt split into separate colored lines for `Enter`, `E`, and `ESC`. Also explain persistence directly in the self-update panel: installed-copy InstallerCore updates save `package_source` / `github_ref` to `state\install-meta.json`, while repo-copy defaults follow the current checked-out git branch instead of storing separate launcher state.
- Files affected: `ManageUpdates.ps1`, `README.md`, `CHANGELOG.md`, `PROJECT_RULES.md`
- Validation/tests run: PowerShell parser validation on `ManageUpdates.ps1`; static review against `Install.ps1` `SaveMeta` / `PreparePackageSource` flow.

### Entry - 2026-03-25 (Cache expensive main-menu status probes once per launcher session)
- Date: 2026-03-25
- Problem: The main menu developed a visible delay because the live status text for `Live SoftwareDistribution Cleanup` and `Delivery Optimization Cleanup + Disable` was recomputed on every menu render.
- Root cause: Both launchers re-ran the expensive PowerShell status probes each time the main menu repainted; Delivery Optimization status in particular can take noticeably longer than a normal menu draw.
- Guardrail/rule: Cache the `[3]` and `[4]` main-menu status lines after the first successful probe in each launcher session. Refresh only after the corresponding action actually runs, not on every return to the menu. Keep self-update status live if needed; the once-per-session cache rule applies specifically to the expensive folder/cache status probes.
- Files affected: `SystemCleanup.ps1`, `SystemCleanup.cmd`, `CHANGELOG.md`, `PROJECT_RULES.md`
- Validation/tests run: Static review of launcher menu flow; local timing probe for `ManageUpdates.ps1 -Action LiveCleanupStatus` and `DeliveryOptimizationStatus`; PowerShell parser validation on `SystemCleanup.ps1`.

### Entry - 2026-03-25 (Self-update ESC should bypass the generic return pause)
- Date: 2026-03-25
- Problem: Cancelling the self-update choice panel with `ESC` still fell through to the launcher's generic `Press any key to return to menu...` pause, which felt wrong because the user had already chosen to back out immediately.
- Root cause: The launcher treated `ToolSelfUpdate` like every other direct action and always applied the normal return-to-menu pause after the child script returned.
- Guardrail/rule: When `ESC` cancels the self-update choice panel, return straight to the main menu with no extra pause. Use an explicit signal from `ManageUpdates.ps1` back to the PowerShell launcher instead of guessing from console text.
- Files affected: `ManageUpdates.ps1`, `SystemCleanup.ps1`, `README.md`, `CHANGELOG.md`, `PROJECT_RULES.md`
- Validation/tests run: PowerShell parser validation on `ManageUpdates.ps1` and `SystemCleanup.ps1`; static review of the launcher return-to-menu flow.

### Entry - 2026-03-25 (Main-menu actions should clear the menu before showing full-screen panels)
- Date: 2026-03-25
- Problem: Several PowerShell main-menu actions left the old menu visible above the action panel, which made the screen feel cluttered and unfinished.
- Root cause: Some actions relied on the child script/function to render new content without first clearing the launcher view, and not every direct action did its own `Clear-Host`.
- Guardrail/rule: Treat main-menu actions as full-screen panels. Clear the launcher view before dispatching each option, and keep direct-action functions (`Live SoftwareDistribution Cleanup`, `Delivery Optimization Cleanup + Disable`, `Tool Self-Update`) defensive by clearing their own screen too. Highlight the active self-update values (`Detected mode`, `Installer Mode`, `GitHub branch` / `Local source`) with bright value colors so the eye lands on the important state immediately.
- Files affected: `SystemCleanup.ps1`, `ManageUpdates.ps1`, `CHANGELOG.md`, `PROJECT_RULES.md`
- Validation/tests run: PowerShell parser validation on `ManageUpdates.ps1` and `SystemCleanup.ps1`; static review of main-menu dispatch flow and self-update panel rendering.

### Entry - 2026-03-25 (Use the self-update Enter/ESC choice blueprint for Delivery Optimization too)
- Date: 2026-03-25
- Problem: `Delivery Optimization Cleanup + Disable` still used a plain `Proceed? (Y/N)` prompt, which felt inconsistent next to the newer self-update panel and did not support the same clean `ESC` cancel behavior.
- Root cause: The newer choice-panel pattern had only been applied to the updater flow, leaving the Delivery Optimization action on the older text prompt style.
- Guardrail/rule: Reuse the same Enter/ESC choice blueprint for Delivery Optimization confirmation: `Enter` runs the action, `ESC` returns to the main menu, and the active Delivery Optimization values (`Mode`, `Provider`, `Cache size`, `Cache path`, `Policy mode`) should be rendered with bright value colors so the eye lands on the live state quickly.
- Files affected: `ManageUpdates.ps1`, `SystemCleanup.ps1`, `README.md`, `CHANGELOG.md`, `PROJECT_RULES.md`
- Validation/tests run: PowerShell parser validation on `ManageUpdates.ps1` and `SystemCleanup.ps1`; static review of the Delivery Optimization confirmation flow.

### Entry - 2026-03-25 (All primary main-menu actions should require Enter to start)
- Date: 2026-03-25
- Problem: Entering several main-menu options could immediately launch work or jump into a submenu, which made the top-level menu feel risky to navigate casually.
- Root cause: Confirmation UX had been added incrementally to a few actions only, leaving the main menu inconsistent.
- Guardrail/rule: Treat the action-oriented `SystemCleanup` main-menu entries as two-step starts. `[1]`, `[2]`, `[3]`, `[4]`, and `[7]` should first open a confirmation panel that uses the same `Enter = start` and `ESC = back to main menu` blueprint. Do not force that extra step on submenu/info-only entries like `[5] Windows Update Manager` and `[6] Last DISM/CBS Failure Details`; those should open directly.
- Files affected: `SystemCleanup.ps1`, `ManageUpdates.ps1`, `README.md`, `CHANGELOG.md`, `PROJECT_RULES.md`
- Validation/tests run: PowerShell parser validation on `SystemCleanup.ps1` and `ManageUpdates.ps1`; static review of all main-menu dispatch paths.

### Entry - 2026-03-25 (Explicitly render returned servicing summary lines in the launcher)
- Date: 2026-03-25
- Problem: The dedicated `[6] Last DISM/CBS Failure Details` view could show only the log paths/header even though the summary helper returned lines, making the panel look empty.
- Root cause: The launcher relied on implicit output rendering from a nested `ManageUpdates.ps1` call instead of explicitly writing the returned strings to the host.
- Guardrail/rule: For launcher-side troubleshooting views and failure banners, collect returned summary strings from child scripts and print them explicitly with `Write-Host` instead of relying on implicit pipeline rendering.
- Files affected: `SystemCleanup.ps1`, `CHANGELOG.md`, `PROJECT_RULES.md`
- Validation/tests run: PowerShell parser validation on `SystemCleanup.ps1`; static review of launcher-side servicing summary rendering.

### Entry - 2026-03-25 (Filter DISM source-noise from servicing summaries and search deeper in CBS)
- Date: 2026-03-25
- Problem: The full `[6]` servicing view could still show useless `DISM` `EnumeratePathEx / FindFirstFile failed` lines for setup/source probe paths, while the actual `CBS` root-cause lines were missed.
- Root cause: The summary matcher used broad `Error` / `path specified` patterns on a shallow tail window, so low-signal `DISM` source-noise could outrank or crowd out the more relevant `CBS` lines.
- Guardrail/rule: Exclude common low-signal `DISM` source-probe lines like `EnumeratePathEx: FindFirstFile failed ...` from the summary picker, and search deeper into `CBS.log` than `dism.log` because the real root-cause clues often sit further back in the servicing log.
- Files affected: `ManageUpdates.ps1`, `CHANGELOG.md`, `PROJECT_RULES.md`
- Validation/tests run: PowerShell parser validation on `ManageUpdates.ps1`; static review of `DISM` exclude patterns and expanded `CBS` tail scan.

### Entry - 2026-03-25 (App-driven installed updates should relaunch SystemCleanup with an explicit Explorer choice)
- Date: 2026-03-25
- Problem: Running self-update from inside the installed app did not need the installer's old Explorer-folder reopen behavior; what users actually need after the update is the app itself restarted on the updated files.
- Root cause: The launcher reused InstallerCore update actions directly, so the installed-update path still behaved like a generic installer session instead of an in-app self-update lifecycle.
- Guardrail/rule: For self-update started from an installed `SystemCleanup` session, call `Install.ps1` with `-NoExplorerRestart`, then ask the user how to come back up after a successful installed update: `Enter = relaunch app only`, any other key = `restart Explorer + relaunch app`. The Explorer-refresh path must not reopen a folder window and must avoid `Start-Process explorer.exe`; rely on the shell auto-restart path instead to reduce ghost/zombie Explorer instances. For WT-capable relaunch, do not target the existing WT window with `-w 0`, because that can create a second tab beside the old app. Use a detached helper that clears inherited `WT_SESSION`, opens a fresh WT window via the official new-window targeting syntax, and then closes the old WT window handle so the updated app replaces the previous terminal session; only fall back to plain `pwsh.exe -File ...` when `wt.exe` is unavailable.
- Files affected: `ManageUpdates.ps1`, `SystemCleanup.ps1`, `README.md`, `CHANGELOG.md`, `PROJECT_RULES.md`
- Validation/tests run: PowerShell parser validation on `ManageUpdates.ps1` and `SystemCleanup.ps1`; static review of installed-copy self-update argument flow and relaunch token handling.
