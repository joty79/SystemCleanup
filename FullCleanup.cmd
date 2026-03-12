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

call :ResetService

call :RunStep " SFC (Initial Scan)" "sfc.exe /scannow"
call :RunStep " DISM AnalyzeComponentStore" "dism.exe /Online /Cleanup-Image /AnalyzeComponentStore"
call :RunStep " DISM RestoreHealth" "dism.exe /Online /Cleanup-Image /RestoreHealth"
call :RunStep " DISM StartComponentCleanup" "dism.exe /Online /Cleanup-Image /StartComponentCleanup"

echo.
echo %cCyan%=== Cleaning WinSxS Temp ===%cReset%
pwsh.exe -NoProfile -ExecutionPolicy Bypass -File "%SCRIPTROOT%CleanInFlight.ps1" -SilentCaller
if errorlevel 1 (
  echo.
  echo   %cRed%[X]   FAILED: WinSxS Temp cleanup returned an error.%cReset%
) else (
  echo.
  echo   %cGreen%+++   OK: Step completed.%cReset%
)

call :ResetService

call :RunStep " SFC (Final Verification)" "sfc.exe /scannow"

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

:ResetService
echo.
echo  %cGray%  Refreshing TrustedInstaller Service...%cReset%
net.exe stop trustedinstaller >nul 2>&1
ver >nul
exit /b

:RunStep
set "STEPTITLE=%~1"
echo.
echo %cCyan%=== !STEPTITLE! ===%cReset%
echo.
call :WriteLog "STARTING: !STEPTITLE!"
call %~2
set "STEPEXIT=!ERRORLEVEL!"
if "!STEPEXIT!"=="0" (
  echo.
  echo    %cGreen%+++   OK: No issues found.%cReset%
  call :WriteLog "SUCCESS: !STEPTITLE! - Clean"
) else (
  echo.
  echo    %cRed%[X]   FAILED: Found issues but could NOT fix them!%cReset%
  call :WriteLog "FAILED: !STEPTITLE! - Code: !STEPEXIT!"
)
exit /b !STEPEXIT!

:WriteLog
if "%LOGFILE%"=="" exit /b 0
>> "%LOGFILE%" echo [%date% %time%] %~1
exit /b 0
