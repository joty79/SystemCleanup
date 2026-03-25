@echo off
setlocal EnableDelayedExpansion

set "SYSTEMCLEANUP_WT_HOSTED=0"
if /i "%~1"=="--wt-hosted" (
    set "SYSTEMCLEANUP_WT_HOSTED=1"
    shift
)
if defined WT_SESSION set "SYSTEMCLEANUP_WT_HOSTED=1"

REM Resolve PowerShell host (pwsh preferred, fallback to Windows PowerShell)
where pwsh.exe >nul 2>&1
if "%errorlevel%"=="0" (
    set "PS_EXE=pwsh"
) else (
    set "PS_EXE=powershell"
)

REM Define ANSI Colors
for /F %%a in ('echo prompt $E^| cmd') do set "ESC=%%a"
set "cReset=%ESC%[0m"
set "cCyan=%ESC%[36m"
set "cGreen=%ESC%[92m"
set "cYellow=%ESC%[93m"
set "cBlue=%ESC%[94m"
set "cMagenta=%ESC%[95m"
set "cRed=%ESC%[91m"
set "cGray=%ESC%[90m"
set "cWhite=%ESC%[37m"
set "cBold=%ESC%[1m"

REM Force UTF-8 Encoding for Icons
chcp 65001 >nul

REM Check Admin Privileges (Safe Mode Compatible)
net session >nul 2>&1
if "%errorLevel%" == "0" goto :IsAdmin

fsutil dirty query %systemdrive% >nul 2>&1
if "!errorLevel!" == "0" goto :IsAdmin

echo %cYellow%Requesting Administrative Privileges...%cReset%
"%PS_EXE%" -NoProfile -ExecutionPolicy Bypass -Command "Start-Process -FilePath '%~f0' -Verb RunAs"
if not "%errorlevel%"=="0" (
    echo %cRed%Elevation failed or was canceled.%cReset%
    pause
)
exit /b

:IsAdmin

set "SYSTEMCLEANUP_IN_SAFE_MODE=0"
if defined SAFEBOOT_OPTION set "SYSTEMCLEANUP_IN_SAFE_MODE=1"

if "%SYSTEMCLEANUP_WT_HOSTED%"=="0" if "%SYSTEMCLEANUP_IN_SAFE_MODE%"=="0" (
    where wt.exe >nul 2>&1
    if "%errorlevel%"=="0" goto :RelaunchInWindowsTerminal
)

set "LogDir=D:\Temp\SystemCleanup"
if not exist "%LogDir%" mkdir "%LogDir%"

REM Generate Log Filename
for /f "tokens=2-4 delims=/ " %%a in ('date /t') do (set mydate=%%c%%a%%b)
for /f "tokens=1-2 delims=/:" %%a in ('time /t') do (set mytime=%%a%%b)
set "LogFile=%LogDir%\SystemCleanup_%mydate%_%mytime%.log"

REM ---------------------------------------------------------
REM MENU SCREEN
REM ---------------------------------------------------------
:Menu
cls
set "LiveDownloadCacheLine=Clean live Download cache files"
set "DeliveryOptimizationLine=Delivery Optimization status unavailable"
for /f "delims=" %%a in ('%PS_EXE% -NoProfile -ExecutionPolicy Bypass -File "%~dp0ManageUpdates.ps1" -Action LiveCleanupStatus -SilentCaller') do set "LiveDownloadCacheLine=%%a"
for /f "delims=" %%a in ('%PS_EXE% -NoProfile -ExecutionPolicy Bypass -File "%~dp0ManageUpdates.ps1" -Action DeliveryOptimizationStatus -SilentCaller') do set "DeliveryOptimizationLine=%%a"
echo.
echo %cCyan%==========================================%cReset%
echo    %cBold%  SYSTEM CLEANUP AND REPAIR TOOL%cReset%
echo %cCyan%==========================================%cReset%
echo.
echo  %cWhite%  Choose an option:%cReset%
echo.
echo    %cGreen%[ 1 ]%cReset% Full Cleanup (SFC + DISM + InFlight)
echo          %cGray%Run SFC, DISM, and WinSxS Temp cleanup%cReset%
echo.
echo    %cYellow%[ 2 ]%cReset% InFlight Cleanup Only (MoveFileEx)
echo          %cGray%Quick — schedules locked files for deletion on reboot%cReset%
echo.
echo    %cCyan%[ 3 ]%cReset% Live SoftwareDistribution Cleanup
echo          %cGray%!LiveDownloadCacheLine!%cReset%
echo.
echo    %cBlue%[ 4 ]%cReset% Windows Update Manager
echo          %cGray%Hide/unhide/list updates, reset cache, block Win11%cReset%
echo.
echo    %cMagenta%[ 5 ]%cReset% Last DISM/CBS Failure Details
echo          %cGray%Full-width recent servicing log view%cReset%
echo.
echo    %cWhite%[ 6 ]%cReset% Delivery Optimization Cleanup + Disable
echo          %cGray%!DeliveryOptimizationLine!%cReset%
echo.
echo    %cRed%[ ESC ]%cReset% Close / Cancel
echo.
<nul set /p "=  Enter choice (1/2/3/4/5/6/ESC): "
for /f "delims=" %%a in ('%PS_EXE% -NoProfile -ExecutionPolicy Bypass -File "%~dp0ManageUpdates.ps1" -Action ReadMainMenuChoice -SilentCaller') do set "CHOICE=%%a"

if /i "%CHOICE%"=="2" goto :InFlightOnly
if /i "%CHOICE%"=="3" goto :LiveSoftwareDistribution
if /i "%CHOICE%"=="4" goto :ManageUpdates
if /i "%CHOICE%"=="5" goto :DismFailureDetails
if /i "%CHOICE%"=="6" goto :DeliveryOptimizationCleanup
if /i "%CHOICE%"=="ESC" exit /b
if /i "%CHOICE%"=="X" exit /b
if "%CHOICE%" NEQ "1" (
    echo  %cRed%Invalid choice.%cReset%
    timeout /t 2 /nobreak >nul
    goto :Menu
)
goto :FullCleanup

REM ---------------------------------------------------------
REM WINDOWS TERMINAL HOST RELAUNCH
REM ---------------------------------------------------------
:RelaunchInWindowsTerminal
echo %cCyan%Launching in Windows Terminal...%cReset%
set "WT_LAUNCHER=%TEMP%\SystemCleanup_wt_%RANDOM%%RANDOM%.cmd"
(
    echo @echo off
    echo call "%~f0" --wt-hosted
    echo del "%%~f0" ^>nul 2^>^&1
) > "%WT_LAUNCHER%"
"%PS_EXE%" -NoProfile -ExecutionPolicy Bypass -Command "Start-Process -FilePath 'wt.exe' -ArgumentList @('-w','0','new-tab','cmd.exe','/k','""%WT_LAUNCHER%""')"
if not "%errorlevel%"=="0" (
    echo %cYellow%Windows Terminal launch failed. Falling back to classic console.%cReset%
    timeout /t 2 /nobreak >nul
)
exit /b

REM ---------------------------------------------------------
REM MAIN EXECUTION (OPTION 1)
REM ---------------------------------------------------------
:FullCleanup
cls
echo.
echo %cCyan%==========================================%cReset%
echo    %cBold%  FULL SYSTEM CLEANUP%cReset%
echo %cCyan%==========================================%cReset%
echo.
echo %cGray%Logs saved to: %LogFile%%cReset%
echo.

REM Phase 1: SFC
call :ResetService
call :RunStep " SFC (Initial Scan)" "sfc /scannow"
set "SFC_EXIT=%EXITCODE%"

REM Phase 2: DISM Core Maintenance
call :RunStep " DISM AnalyzeComponentStore" "dism.exe /Online /Cleanup-Image /AnalyzeComponentStore"
call :RunStep " DISM RestoreHealth" "dism.exe /Online /Cleanup-Image /RestoreHealth"
call :RunStep " DISM StartComponentCleanup /ResetBase" "dism.exe /Online /Cleanup-Image /StartComponentCleanup /ResetBase"

REM Phase 3: InFlight Call
echo.
echo %cCyan%=== Cleaning WinSxS Temp ===%cReset%
"%PS_EXE%" -NoProfile -ExecutionPolicy Bypass -File "%~dp0CleanInFlight.ps1" -SilentCaller

REM Phase 4: Final Verification
call :ResetService
call :RunStep " SFC (Final Verification)" "sfc /scannow"

echo.
echo %cGreen%==========================================%cReset%
echo    %cBold%  ALL STEPS COMPLETED%cReset%
echo %cGreen%==========================================%cReset%
echo.
echo %cYellow% Status Legend:%cReset%
echo   %cGreen%  +++   OK: No issues found%cReset%             %cGray%(Clean)%cReset%
echo   %cYellow%  [~]   FIXED: Repaired issues%cReset%         %cGray%(Fixed)%cReset%
echo   %cRed%  [X]   FAILED: Could not repair%cReset%        %cGray%(Failed)%cReset%
echo.
pause
goto :Menu

REM ---------------------------------------------------------
REM OPTION 2: InFlight Cleanup Only (MoveFileEx)
REM ---------------------------------------------------------
:InFlightOnly
cls
echo.
echo %cCyan%==========================================%cReset%
echo    %cBold%  INFLIGHT CLEANUP (MoveFileEx/Registry)%cReset%
echo %cCyan%==========================================%cReset%
echo.
"%PS_EXE%" -NoProfile -ExecutionPolicy Bypass -File "%~dp0CleanInFlight.ps1"
echo.
pause
goto :Menu

REM ---------------------------------------------------------
REM OPTION 3: Live SoftwareDistribution Cleanup
REM ---------------------------------------------------------
:LiveSoftwareDistribution
cls
echo.
echo %cCyan%==========================================%cReset%
echo    %cBold%  LIVE SOFTWAREDISTRIBUTION CLEANUP%cReset%
echo %cCyan%==========================================%cReset%
echo.
"%PS_EXE%" -NoProfile -ExecutionPolicy Bypass -File "%~dp0ManageUpdates.ps1" -Action LiveCleanup
echo.
goto :Menu

REM ---------------------------------------------------------
REM OPTION 4: Windows Update Manager
REM ---------------------------------------------------------
:ManageUpdates
cls
echo.
echo %cCyan%==========================================%cReset%
echo    %cBold%  WINDOWS UPDATE MANAGER%cReset%
echo %cCyan%==========================================%cReset%
echo.
"%PS_EXE%" -NoProfile -ExecutionPolicy Bypass -File "%~dp0ManageUpdates.ps1" -Action Menu
echo.
goto :Menu

REM ---------------------------------------------------------
REM OPTION 5: Last DISM/CBS Failure Details
REM ---------------------------------------------------------
:DismFailureDetails
cls
echo.
echo %cCyan%==========================================%cReset%
echo    %cBold%  DISM / CBS FAILURE DETAILS%cReset%
echo %cCyan%==========================================%cReset%
echo.
echo %cGray%DISM log: C:\Windows\Logs\DISM\dism.log%cReset%
echo %cGray%CBS log:  C:\Windows\Logs\CBS\CBS.log%cReset%
echo.
"%PS_EXE%" -NoProfile -ExecutionPolicy Bypass -File "%~dp0ManageUpdates.ps1" -Action DismFailureSummaryFull -SilentCaller
echo.
pause
goto :Menu

REM ---------------------------------------------------------
REM OPTION 6: Delivery Optimization Cleanup + Disable
REM ---------------------------------------------------------
:DeliveryOptimizationCleanup
cls
echo.
echo %cCyan%==========================================%cReset%
echo    %cBold%  DELIVERY OPTIMIZATION CLEANUP + DISABLE%cReset%
echo %cCyan%==========================================%cReset%
echo.
"%PS_EXE%" -NoProfile -ExecutionPolicy Bypass -File "%~dp0ManageUpdates.ps1" -Action DeliveryOptimizationCleanup
echo.
goto :Menu

REM ---------------------------------------------------------
REM HELPER FUNCTIONS
REM ---------------------------------------------------------

:ResetService
echo.
echo  %cGray%  Refreshing TrustedInstaller Service...%cReset%
net stop trustedinstaller >nul 2>&1
ver > nul
exit /b

:RunStep
set "StepTitle=%~1"
set "StepCmd=%~2"

echo.
echo %cCyan%=== !StepTitle! ===%cReset%
echo.
echo [%date% %time%] STARTING: !StepTitle! >> "%LogFile%"

REM Run command directly (no pipe to powershell, this was causing crashes)
%StepCmd%
set "EXITCODE=!errorlevel!"

REM Result detection (robust EXITCODE evaluation)
set "RESULT_STATUS=UNKNOWN"

REM Check if command contains SFC
echo !StepCmd! | find /i "sfc" >nul 2>&1
if "!errorlevel!"=="0" goto :EvaluateCode
goto :EvaluateCode

:EvaluateCode
REM Evaluate native exit code cleanly
if "%EXITCODE%"=="0" set "RESULT_STATUS=CLEAN"
if "%EXITCODE%" NEQ "0" set "RESULT_STATUS=FAILED"

:ShowResult
REM Print outcome
if "%RESULT_STATUS%"=="CLEAN" goto :ResClean
if "%RESULT_STATUS%"=="REPAIRED" goto :ResRepaired
if "%RESULT_STATUS%"=="FAILED" goto :ResFailed

REM Default
echo.
echo    %cGreen%+++   OK: Step completed.%cReset%
echo [%date% %time%] SUCCESS: !StepTitle! >> "%LogFile%"
exit /b

:ResClean
echo.
echo    %cGreen%+++   OK: No issues found.%cReset%
echo [%date% %time%] SUCCESS: !StepTitle! - Clean >> "%LogFile%"
exit /b

:ResRepaired
echo.
echo    %cYellow%[~]   FIXED: Found issues and repaired them.%cReset%
echo [%date% %time%] REPAIRED: !StepTitle! - Issues found and fixed >> "%LogFile%"
exit /b

:ResFailed
echo.
echo    %cRed%[X]   FAILED: Found issues but could NOT fix them!%cReset%
echo    %cYellow%Exit code: %EXITCODE%%cReset%
echo [%date% %time%] FAILED: !StepTitle! - Code: %EXITCODE% >> "%LogFile%"
echo !StepTitle! | find /i "DISM" >nul 2>&1
if not errorlevel 1 (
    echo    %cGray%DISM log: C:\Windows\Logs\DISM\dism.log%cReset%
    echo    %cGray%CBS log:  C:\Windows\Logs\CBS\CBS.log%cReset%
    echo    %cYellow%Hint: Error 3 / 0x80070003 often means a missing servicing path under WinSxS\Temp\InFlight.%cReset%
    echo    %cYellow%Hint: stripped/custom Windows images may fail RestoreHealth even when SFC is clean.%cReset%
    "%PS_EXE%" -NoProfile -ExecutionPolicy Bypass -File "%~dp0ManageUpdates.ps1" -Action DismFailureSummary -SilentCaller
)
exit /b
