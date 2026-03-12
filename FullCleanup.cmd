@echo off
setlocal EnableExtensions

set "SCRIPTROOT=%~dp0"
set "LOGFILE=%~1"

echo.
echo ==========================================
echo    FULL SYSTEM CLEANUP
echo ==========================================
echo.
if not "%LOGFILE%"=="" (
  echo Logs saved to: %LOGFILE%
  echo.
)

echo   Refreshing TrustedInstaller Service...
net.exe stop trustedinstaller >nul 2>&1

call :RunStep "SFC (Initial Scan)" sfc.exe /scannow
call :RunStep "DISM AnalyzeComponentStore" dism.exe /Online /Cleanup-Image /AnalyzeComponentStore
call :RunStep "DISM RestoreHealth" dism.exe /Online /Cleanup-Image /RestoreHealth
call :RunStep "DISM StartComponentCleanup" dism.exe /Online /Cleanup-Image /StartComponentCleanup

echo.
echo === Cleaning WinSxS Temp ===
pwsh.exe -NoProfile -ExecutionPolicy Bypass -File "%SCRIPTROOT%CleanInFlight.ps1" -SilentCaller
if errorlevel 1 (
  echo.
  echo   [X]   FAILED: WinSxS Temp cleanup returned an error.
) else (
  echo.
  echo   +++   OK: Step completed.
)

echo.
echo   Refreshing TrustedInstaller Service...
net.exe stop trustedinstaller >nul 2>&1

call :RunStep "SFC (Final Verification)" sfc.exe /scannow

echo.
echo ==========================================
echo    ALL STEPS COMPLETED
echo ==========================================
echo.
echo  Press any key to close this pane...
pause >nul
exit /b 0

:RunStep
set "STEPTITLE=%~1"
shift
echo.
echo === %STEPTITLE% ===
echo.
call %*
set "STEPEXIT=%ERRORLEVEL%"
if "%STEPEXIT%"=="0" (
  echo.
  echo   +++   OK: Step completed.
) else (
  echo.
  echo   [X]   FAILED: Found issues but could NOT fix them!
)
exit /b %STEPEXIT%
