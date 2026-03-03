# SystemCleanup

`SystemCleanup` ειναι ενα Windows context-menu tool για system maintenance, repair, και update management.
Αντι να τρεχεις χειροκινητα πολλα commands καθε φορα, σου δινει ενα σταθερο flow απο desktop right-click.

## Τι κανει

### 🔧 Full Cleanup (Option 1)
- Τρεχει `SFC` scan πριν και μετα το cleanup.
- Τρεχει βασικα `DISM` βηματα για component store health.
- Κανει cleanup στο `WinSxS\Temp` με fallback strategy για locked files.
- Γραφει logs για troubleshooting.

### ⚡ InFlight Cleanup (Option 2)
- Γρηγορο cleanup μονο για `WinSxS\Temp` locked files.
- Χρησιμοποιει `MoveFileEx` (schedule-on-reboot) ως fallback.

### 🔄 Windows Update Manager (Option 3)
- **List Pending Updates** — δειξε ποια updates περιμενουν.
- **Hide Updates** — κρυψε ανεπιθυμητα updates (π.χ. fake WSL update) χρησιμοποιωντας native COM API.
- **Show/Unhide Hidden Updates** — δες ή επαναφερε κρυμμενα updates.
- **Reset Update Cache** — σταματα services, αυτο-καθαρισε `.old` backups, μετονομασε `SoftwareDistribution` + `catroot2`.
- **Clean Stale Backup Folders** — χειροκινητη διαγραφη `.old_*` φακελων.

## ⚠️ Σωστη Σειρα για Hide Updates

> Αν εχεις ηδη update στα Windows Update και θελεις να το κρυψεις μονιμα:
>
> 1. **[5] Reset Update Cache**
> 2. **Reboot** τον υπολογιστη
> 3. **[2] Hide Updates** — επιλεξε τι θα κρυψεις στη φρεσκια λιστα
>
> ⚠️ Αν κανεις hide πρωτα και μετα reset, το hidden flag χανεται και το update ξαναεμφανιζεται!

## Γιατι να το χρησιμοποιησεις
- Ενα entry point για ολα τα βασικα repair + update management actions.
- Ιδιο behavior σε καθε μηχανημα με installer-driven setup.
- Ευκολο update απο GitHub (`master`) χωρις manual αντιγραφες αρχειων.
- Καθαρο uninstall χωρις orphan context-menu entries.
- Zero external dependencies — χρησιμοποιει μονο native Windows COM API.

## Πως δουλευει
- Context menu key: `DesktopBackground\Shell\SystemTools\shell\SystemCleanup`
- Launcher: `SystemCleanup.cmd`
- InFlight cleanup: `CleanInFlight.ps1`
- Update manager: `ManageUpdates.ps1`
- Installer/Updater: `Install.ps1`

## Core Files
| File | Purpose |
|------|---------|
| `Install.ps1` | Installer, updater, uninstall workflow |
| `SystemCleanup.cmd` | Interactive menu + orchestration (SFC/DISM/InFlight/Updates) |
| `CleanInFlight.ps1` | Locked-file cleanup flow |
| `ManageUpdates.ps1` | Windows Update hide/unhide/reset (native COM API) |
| `SystemCleanup.reg` | Static registry sample (manual use) |

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
- Τα `.old_*` backup folders (απο reset cache) σβηνονται αυτοματα στο επομενο reset, ή χειροκινητα μεσω `[6]`.
