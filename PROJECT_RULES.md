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
