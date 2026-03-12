# Changelog

All notable user-facing changes for `SystemCleanup` are recorded here.

## [2026-03-10]

### Changed

- Hardened `Reset Update Cache` so it now waits for service stop/start transitions, verifies the `SoftwareDistribution` and `catroot2` move, and reports a partial reset instead of a false success.
- Updated the Windows 11 block toggle to verify registry writes by readback and to distinguish `Policy active`, `Policy mismatch`, and `Not configured` states in the menu.

## [2026-03-12]

### Added

- Added `Live SoftwareDistribution Cleanup` to the Windows Update Manager so the live `SoftwareDistribution\Download` cache can be cleaned without doing a full reset of `SoftwareDistribution` and `catroot2`.

### Changed

- Shifted the Windows Update Manager menu so `Clean Stale Backup Folders` moved to `[7]` and `Block Windows 11 Upgrade` moved to `[8]`.
- Updated `Live SoftwareDistribution Cleanup` to show the current `SoftwareDistribution\Download` size before the confirmation prompt, while still reporting before/after/freed sizes after the run.
- Updated the `[6] Live SoftwareDistribution Cleanup` menu line to show the current live `Download` cache size directly in the gray description text.

