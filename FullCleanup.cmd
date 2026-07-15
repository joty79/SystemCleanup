@echo off
setlocal EnableExtensions EnableDelayedExpansion

set "SCRIPTROOT=%~dp0"
set "LOGFILE=%~1"
set "EXITCODE=0"

for /F %%a in ('echo prompt $E^| cmd') do set "ESC=%%a"
set "cReset=%ESC%[0m"
set "cCyan=%ESC%[36m"
set "cGreen=%ESC%[92m"
set "cYellow=%ESC%[93m"
set "cRed=%ESC%[91m"
set "cGray=%ESC%[90m"
set "cWhite=%ESC%[37m"
set "cBold=%ESC%[1m"

chcp 65001 >nul

echo.
echo %cCyan%==========================================%cReset%
echo    %cBold%  FULL SYSTEM CLEANUP%cReset%
echo %cCyan%==========================================%cReset%
echo.
if not "%LOGFILE%"=="" (
  echo %cGray%Logs saved to: %LOGFILE%%cReset%
  echo.
)

call :CheckServicingPreflight
if errorlevel 1 goto :AbortCleanup

call :ResetService

call :RunStep " SFC (Initial Scan)" "sfc.exe /scannow"
if errorlevel 1 goto :AbortCleanup
call :RunStep " DISM AnalyzeComponentStore" "dism.exe /Online /Cleanup-Image /AnalyzeComponentStore"
if errorlevel 1 goto :AbortCleanup
call :RunStep " DISM RestoreHealth (local source only)" "dism.exe /Online /Cleanup-Image /RestoreHealth /LimitAccess"
if errorlevel 1 (
  set "LOCALREPAIREXIT=!EXITCODE!"
  call :OfferRestoreHealthRepair
  if "!REPAIRFALLBACKEXIT!"=="0" goto :RepairCompleted
  if not "!REPAIRFALLBACKEXIT!"=="2" set "EXITCODE=!REPAIRFALLBACKEXIT!"
  if "!REPAIRFALLBACKEXIT!"=="2" set "EXITCODE=!LOCALREPAIREXIT!"
  goto :AbortCleanup
)
call :RunStep " DISM StartComponentCleanup /ResetBase" "dism.exe /Online /Cleanup-Image /StartComponentCleanup /ResetBase"
if errorlevel 1 goto :AbortCleanup

echo.
echo %cCyan%=== Cleaning WinSxS Temp ===%cReset%
pwsh.exe -NoProfile -ExecutionPolicy Bypass -File "%SCRIPTROOT%CleanInFlight.ps1" -SilentCaller
set "CLEANEXIT=!ERRORLEVEL!"
if not "!CLEANEXIT!"=="0" (
  echo.
  echo   %cRed%[X]   FAILED: WinSxS Temp cleanup returned an error.%cReset%
  set "EXITCODE=!CLEANEXIT!"
  call :WriteLog "FAILED: WinSxS Temp cleanup - Code: !CLEANEXIT!"
  goto :AbortCleanup
) else (
  echo.
  echo   %cGreen%+++   OK: Step completed.%cReset%
)

call :ResetService

call :RunStep " SFC (Final Verification)" "sfc.exe /scannow"
if errorlevel 1 goto :AbortCleanup

echo.
echo %cGreen%==========================================%cReset%
echo    %cBold%  ALL STEPS COMPLETED%cReset%
echo %cGreen%==========================================%cReset%
echo.
echo %cYellow% Status Legend:%cReset%
echo   %cGreen%  +++   OK: No issues found%cReset%             %cGray%(Clean)%cReset%
echo   %cYellow%  [~]   FIXED: Found issues and repaired them%cReset% %cGray%(Fixed)%cReset%
echo   %cRed%  [X]   FAILED: Found issues but could NOT fix them%cReset% %cGray%(Failed)%cReset%
echo.
echo  Press any key to close this pane...
pause >nul
exit /b 0

:RepairCompleted
set "EXITCODE=0"
echo.
echo %cGreen%==========================================%cReset%
echo    %cBold%  REPAIR COMPLETED - RESTART REQUIRED%cReset%
echo %cGreen%==========================================%cReset%
echo.
echo   %cWhite%The Windows image repair completed successfully.%cReset%
echo   %cYellow%Full Cleanup stopped before /ResetBase and later cleanup stages.%cReset%
echo   %cGray%Restart Windows normally, then run Full Cleanup again.%cReset%
call :WriteLog "REPAIRED: RestoreHealth fallback completed - restart required"
echo.
echo  Press any key to close this pane...
pause >nul
exit /b 0

:AbortCleanup
if not defined EXITCODE set "EXITCODE=1"
echo.
echo %cRed%==========================================%cReset%
echo    %cBold%  FULL CLEANUP STOPPED SAFELY%cReset%
echo %cRed%==========================================%cReset%
echo.
echo   %cYellow%A required step failed or servicing was already pending.%cReset%
echo   %cWhite%No later cleanup steps were started.%cReset%
echo   %cGray%Resolve the reported condition before running Full Cleanup again.%cReset%
call :WriteLog "STOPPED: Full Cleanup aborted safely - Code: !EXITCODE!"
echo.
echo  Press any key to close this pane...
pause >nul
exit /b !EXITCODE!

:CheckServicingPreflight
set "PREFLIGHT_BLOCKED=0"
echo %cGray%Checking pending restart and servicing state...%cReset%

reg.exe query "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing\RebootPending" >nul 2>&1
if not errorlevel 1 (
  echo   %cYellow%[BLOCKED] Windows servicing has a pending restart.%cReset%
  set "PREFLIGHT_BLOCKED=1"
)
reg.exe query "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing\PackagesPending" >nul 2>&1
if not errorlevel 1 (
  echo   %cYellow%[BLOCKED] Windows servicing has pending packages.%cReset%
  set "PREFLIGHT_BLOCKED=1"
)
reg.exe query "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\RebootRequired" >nul 2>&1
if not errorlevel 1 (
  echo   %cYellow%[BLOCKED] Windows Update requires a restart.%cReset%
  set "PREFLIGHT_BLOCKED=1"
)
if exist "%WINDIR%\WinSxS\pending.xml" (
  echo   %cYellow%[BLOCKED] Windows has pending servicing operations.%cReset%
  set "PREFLIGHT_BLOCKED=1"
)

for %%P in (dism.exe DismHost.exe TiWorker.exe) do (
  tasklist.exe /FI "IMAGENAME eq %%P" /NH 2>nul | find.exe /I "%%P" >nul
  if not errorlevel 1 (
    echo   %cYellow%[BLOCKED] Another servicing process is active: %%P%cReset%
    set "PREFLIGHT_BLOCKED=1"
  )
)

if "!PREFLIGHT_BLOCKED!"=="1" (
  set "EXITCODE=20"
  call :WriteLog "BLOCKED: Full Cleanup preflight detected pending or active servicing"
  exit /b 20
)

echo   %cGreen%+++   OK: Servicing preflight passed.%cReset%
exit /b 0

:ResetService
echo.
echo  %cGray%  Refreshing TrustedInstaller Service...%cReset%
net.exe stop trustedinstaller >nul 2>&1
ver >nul
exit /b

:OfferRestoreHealthRepair
echo.
echo %cYellow%The local component store could not complete RestoreHealth.%cReset%
echo %cWhite%A verified ISO repair source can be used, or Windows Update can be allowed explicitly.%cReset%
pwsh.exe -NoProfile -ExecutionPolicy Bypass -File "%SCRIPTROOT%ManageUpdates.ps1" -Action RepairRestoreHealth -SilentCaller
set "REPAIRFALLBACKEXIT=!ERRORLEVEL!"
call :WriteLog "RestoreHealth fallback returned code !REPAIRFALLBACKEXIT!"
exit /b !REPAIRFALLBACKEXIT!

:RunStep
set "STEPTITLE=%~1"
echo.
echo %cCyan%=== !STEPTITLE! ===%cReset%
echo.
call :WriteLog "STARTING: !STEPTITLE!"
call %~2
set "STEPEXIT=!ERRORLEVEL!"
set "EXITCODE=!STEPEXIT!"
if "!STEPEXIT!"=="0" (
  echo.
  echo    %cGreen%+++   OK: No issues found.%cReset%
  call :WriteLog "SUCCESS: !STEPTITLE! - Clean"
) else (
  echo.
  echo    %cRed%[X]   FAILED: Found issues but could NOT fix them!%cReset%
  echo    %cYellow%Exit code: !STEPEXIT!%cReset%
  echo !STEPTITLE! | find /i "DISM" >nul 2>&1
  if not errorlevel 1 (
    echo    %cGray%DISM log: C:\Windows\Logs\DISM\dism.log%cReset%
    echo    %cGray%CBS log:  C:\Windows\Logs\CBS\CBS.log%cReset%
    echo    %cYellow%Hint: Error 3 / 0x80070003 often means a missing servicing path under WinSxS\Temp\InFlight.%cReset%
    echo    %cYellow%Hint: stripped/custom Windows images may fail RestoreHealth even when SFC is clean.%cReset%
    pwsh.exe -NoProfile -ExecutionPolicy Bypass -File "%SCRIPTROOT%ManageUpdates.ps1" -Action DismFailureSummary -SilentCaller
  )
  call :WriteLog "FAILED: !STEPTITLE! - Code: !STEPEXIT!"
)
exit /b !STEPEXIT!

:WriteLog
if "%LOGFILE%"=="" exit /b 0
>> "%LOGFILE%" echo [%date% %time%] %~1
exit /b 0
