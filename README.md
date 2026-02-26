# SystemCleanup

`SystemCleanup` is a Windows desktop context-menu tool that runs:
- `SFC` checks
- `DISM` component cleanup/repair
- WinSxS `InFlight` cleanup flow

## Core Files
- `SystemCleanup.reg` (context-menu integration)
- `SystemCleanup.cmd` (main menu + execution flow)
- `CleanInFlight.ps1` (locked file cleanup logic)
- `Install.ps1` (template-generated installer/uninstaller)

## Install
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
