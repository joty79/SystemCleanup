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
