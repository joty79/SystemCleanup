# SystemCleanup

`SystemCleanup` ειναι ενα Windows context-menu tool για maintenance/repair του system image.
Αντι να τρεχεις χειροκινητα πολλα commands καθε φορα, σου δινει ενα σταθερο flow απο desktop right-click.

## Τι κανει
- Τρεχει `SFC` scan πριν και μετα το cleanup.
- Τρεχει βασικα `DISM` βηματα για component store health.
- Κανει cleanup στο `WinSxS\Temp\InFlight` με fallback strategy για locked files.
- Γραφει logs για troubleshooting.

## Γιατι να το χρησιμοποιησεις
- Ενα entry point για ολα τα βασικα repair actions.
- Ιδιο behavior σε καθε μηχανημα με installer-driven setup.
- Ευκολο update απο GitHub (`master`) χωρις manual αντιγραφες αρχειων.
- Καθαρο uninstall χωρις orphan context-menu entries.

## Πως δουλευει
- Context menu key: `DesktopBackground\Shell\SystemCleanup`
- Launcher: `SystemCleanup.cmd`
- InFlight cleanup logic: `CleanInFlight.ps1`
- Installer/Updater: `Install.ps1`

## Core Files
- `Install.ps1`: installer, updater, uninstall workflow.
- `SystemCleanup.cmd`: interactive menu + orchestration (`SFC`/`DISM`/InFlight).
- `CleanInFlight.ps1`: locked-file cleanup flow.
- `SystemCleanup.reg`: static registry sample (manual use).

## Quick Start
```powershell
pwsh -NoProfile -ExecutionPolicy Bypass -File .\Install.ps1 -Action Install
```

## Update
```powershell
pwsh -NoProfile -ExecutionPolicy Bypass -File .\Install.ps1 -Action Update
```

## Uninstall
```powershell
pwsh -NoProfile -ExecutionPolicy Bypass -File .\Install.ps1 -Action Uninstall -Force
```

## Notes
- Προτεινεται να χρησιμοποιεις `Install.ps1` και οχι manual import του `.reg`, γιατι το installer γραφει dynamic paths.
- Το tool ζητα admin rights οταν χρειαζεται.
- Logs installer: `%LOCALAPPDATA%\SystemCleanupContext\logs\installer.log`
- Logs runtime cleanup: `D:\Temp\SystemCleanup`
