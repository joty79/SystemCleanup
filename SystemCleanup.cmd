@echo off
setlocal EnableDelayedExpansion

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

set "LogDir=D:\Temp\SystemCleanup"
if not exist "%LogDir%" mkdir "%LogDir%"

REM Generate Log Filename
for /f "tokens=2-4 delims=/ " %%a in ('date /t') do (set mydate=%%c%%a%%b)
for /f "tokens=1-2 delims=/:" %%a in ('time /t') do (set mytime=%%a%%b)
set "LogFile=%LogDir%\SystemCleanup_%mydate%_%mytime%.log"

REM ---------------------------------------------------------
REM MENU SCREEN
REM ---------------------------------------------------------
cls
echo.
echo %cCyan%==========================================%cReset%
echo    %cBold%  SYSTEM CLEANUP AND REPAIR TOOL%cReset%
echo %cCyan%==========================================%cReset%
echo.
echo  %cWhite%  Choose an option:%cReset%
echo.
echo    %cGreen%[ 1 ]%cReset% Full Cleanup (SFC + DISM + InFlight)
echo          %cGray%Takes 20-40 minutes%cReset%
echo.
echo    %cYellow%[ 2 ]%cReset% InFlight Cleanup Only (MoveFileEx)
echo          %cGray%Quick — schedules locked files for deletion on reboot%cReset%
echo.
echo    %cRed%[ X ]%cReset% Close / Cancel
echo.
set /p "CHOICE=  Enter choice (1/2/X): "

if /i "%CHOICE%"=="2" goto :InFlightOnly
if /i "%CHOICE%"=="X" exit /b
if "%CHOICE%" NEQ "1" (
    echo  %cRed%Invalid choice.%cReset%
    pause
    exit /b
)

REM ---------------------------------------------------------
REM MAIN EXECUTION (OPTION 1)
REM ---------------------------------------------------------
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
call :RunStep " DISM StartComponentCleanup" "dism.exe /Online /Cleanup-Image /StartComponentCleanup"

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
exit /b

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
exit /b

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
echo [%date% %time%] FAILED: !StepTitle! - Code: %EXITCODE% >> "%LogFile%"
exit /b
