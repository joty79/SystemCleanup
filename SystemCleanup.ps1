#requires -version 7.0
[CmdletBinding()]
param(
    [switch]$WtHosted
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$OutputEncoding = [Console]::OutputEncoding = [System.Text.Encoding]::UTF8

$script:LogDir = ''
$script:LogFile = ''
$script:CachedLiveDownloadCacheLine = $null
$script:CachedDeliveryOptimizationLine = $null
$script:SkipReturnToMenuToken = '__SYSTEMCLEANUP_SKIP_RETURN_TO_MENU__'
$script:PwshExe = if (Get-Command pwsh.exe -ErrorAction SilentlyContinue) {
    (Get-Command pwsh.exe -ErrorAction SilentlyContinue).Source
}
else {
    Join-Path $PSHOME 'pwsh.exe'
}

function Ensure-Directory {
    param([string]$Path)
    if (-not (Test-Path -LiteralPath $Path)) {
        New-Item -Path $Path -ItemType Directory -Force -ErrorAction Stop | Out-Null
    }
}

function Initialize-Logging {
    $logName = "SystemCleanup_{0}.log" -f (Get-Date -Format 'yyyyMMdd_HHmmss')
    $candidates = @(
        'D:\Temp\SystemCleanup',
        (Join-Path $env:LOCALAPPDATA 'SystemCleanupContext\logs'),
        (Join-Path $env:TEMP 'SystemCleanup')
    ) | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }

    foreach ($candidate in $candidates) {
        try {
            Ensure-Directory -Path $candidate
            $probePath = Join-Path $candidate ([guid]::NewGuid().ToString('N') + '.tmp')
            Set-Content -LiteralPath $probePath -Value '' -Encoding UTF8 -ErrorAction Stop
            Remove-Item -LiteralPath $probePath -Force -ErrorAction Stop
            $script:LogDir = $candidate
            $script:LogFile = Join-Path $candidate $logName
            return
        }
        catch {
            continue
        }
    }

    $script:LogDir = ''
    $script:LogFile = ''
}

function Test-IsAdmin {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = [Security.Principal.WindowsPrincipal]::new($identity)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Start-PreferredHost {
    $scriptPath = $PSCommandPath
    $wtCommand = Get-Command wt.exe -ErrorAction SilentlyContinue
    $hasWindowsTerminal = $null -ne $wtCommand
    $alreadyInWt = $WtHosted -or -not [string]::IsNullOrWhiteSpace($env:WT_SESSION)

    if (-not (Test-IsAdmin)) {
        if ($hasWindowsTerminal) {
            Start-Process -FilePath $wtCommand.Source -Verb RunAs -ArgumentList @(
                '-w', '0', 'new-tab',
                $script:PwshExe,
                '-NoProfile',
                '-ExecutionPolicy', 'Bypass',
                '-File', $scriptPath,
                '-WtHosted'
            ) | Out-Null
            return $true
        }

        Start-Process -FilePath $script:PwshExe -Verb RunAs -ArgumentList @(
            '-NoProfile',
            '-ExecutionPolicy', 'Bypass',
            '-File', $scriptPath
        ) | Out-Null
        return $true
    }

    if ($hasWindowsTerminal -and -not $alreadyInWt) {
        Start-Process -FilePath $wtCommand.Source -ArgumentList @(
            '-w', '0', 'new-tab',
            $script:PwshExe,
            '-NoProfile',
            '-ExecutionPolicy', 'Bypass',
            '-File', $scriptPath,
            '-WtHosted'
        ) | Out-Null
        return $true
    }

    return $false
}

function Write-Log {
    param(
        [string]$Level,
        [string]$Message
    )

    if ([string]::IsNullOrWhiteSpace($script:LogFile)) {
        return
    }

    $line = '{0} | {1} | {2}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss.fff'), $Level, $Message
    try {
        Ensure-Directory -Path $script:LogDir
        Add-Content -Path $script:LogFile -Value $line -Encoding UTF8 -ErrorAction Stop
    }
    catch {}
}

function Read-MainMenuKey {
    Write-Host '  Enter choice (1/2/3/4/5/6/7/ESC): ' -ForegroundColor White -NoNewline
    $key = $Host.UI.RawUI.ReadKey('NoEcho,IncludeKeyDown')
    if ($key.VirtualKeyCode -eq 27) {
        Write-Host 'ESC' -ForegroundColor DarkGray
        return 'ESC'
    }

    $char = [string]$key.Character
    if (-not [string]::IsNullOrWhiteSpace($char)) {
        Write-Host $char
        return $char
    }

    Write-Host ''
    return ''
}

function Wait-ReturnToMenu {
    Write-Host ''
    Write-Host '  Press any key to return to menu...' -ForegroundColor Gray
    $null = $Host.UI.RawUI.ReadKey('NoEcho,IncludeKeyDown')
}

function Read-EnterOrEscChoice {
    param(
        [string]$EnterLabel = 'Proceed',
        [string]$EnterDescription = '',
        [string]$EscLabel = 'Back to main menu'
    )

    Write-Host '  Choices:' -ForegroundColor White
    Write-Host ("  ✅ [Enter] {0}" -f $EnterLabel) -ForegroundColor Green
    if (-not [string]::IsNullOrWhiteSpace($EnterDescription)) {
        Write-Host ("           {0}" -f $EnterDescription) -ForegroundColor DarkGray
    }
    Write-Host ("  ❌ [ESC]   {0}" -f $EscLabel) -ForegroundColor Red
    Write-Host ''
    Write-Host '  Choice: ' -ForegroundColor White -NoNewline

    while ($true) {
        $key = $Host.UI.RawUI.ReadKey('NoEcho,IncludeKeyDown')
        if ($key.VirtualKeyCode -eq 13) {
            Write-Host 'Enter' -ForegroundColor DarkGray
            return 'ENTER'
        }
        if ($key.VirtualKeyCode -eq 27) {
            Write-Host 'ESC' -ForegroundColor DarkGray
            return 'ESC'
        }

        $char = [string]$key.Character
        if ([string]::IsNullOrWhiteSpace($char)) {
            continue
        }

        Write-Host $char
        Write-Host '  Invalid choice. Use Enter or ESC.' -ForegroundColor Yellow
        Write-Host '  Choice: ' -ForegroundColor Gray -NoNewline
    }
}

function Get-LiveDownloadCacheStatusLine {
    $manageUpdatesPath = Join-Path $PSScriptRoot 'ManageUpdates.ps1'
    try {
        return (& $manageUpdatesPath -Action LiveCleanupStatus -SilentCaller | Out-String).Trim()
    }
    catch {
        return 'Clean live Download cache files'
    }
}

function Get-DeliveryOptimizationStatusLine {
    $manageUpdatesPath = Join-Path $PSScriptRoot 'ManageUpdates.ps1'
    try {
        return (& $manageUpdatesPath -Action DeliveryOptimizationStatus -SilentCaller | Out-String).Trim()
    }
    catch {
        return 'Delivery Optimization status unavailable'
    }
}

function Get-ToolSelfUpdateStatusLine {
    $manageUpdatesPath = Join-Path $PSScriptRoot 'ManageUpdates.ps1'
    try {
        return (& $manageUpdatesPath -Action ToolSelfUpdateStatus -SilentCaller | Out-String).Trim()
    }
    catch {
        return 'InstallerCore updater unavailable'
    }
}

function Reset-TrustedInstaller {
    Write-Host ''
    Write-Host '  Refreshing TrustedInstaller Service...' -ForegroundColor DarkGray
    & net.exe stop trustedinstaller *> $null
}

function Show-NativeFailureDetails {
    param(
        [string]$Title,
        [int]$ExitCode
    )

    Write-Host ''
    Write-Host ("  Exit code: {0}" -f $ExitCode) -ForegroundColor DarkYellow

    if ($Title -match 'DISM') {
        Write-Host '  DISM log: C:\Windows\Logs\DISM\dism.log' -ForegroundColor DarkGray
        Write-Host '  CBS log:  C:\Windows\Logs\CBS\CBS.log' -ForegroundColor DarkGray
        Write-Host '  Hint: Error 3 / 0x80070003 often means a missing servicing path under WinSxS\Temp\InFlight.' -ForegroundColor DarkYellow
        Write-Host '  Hint: stripped/custom Windows images may fail RestoreHealth even when SFC is clean.' -ForegroundColor DarkYellow
        try {
            & (Join-Path $PSScriptRoot 'ManageUpdates.ps1') -Action DismFailureSummary -SilentCaller
        }
        catch {
            Write-Host '  Recent servicing log lines: unavailable.' -ForegroundColor DarkGray
        }
    }
}

function Invoke-NativeStep {
    param(
        [string]$Title,
        [string]$FilePath,
        [string[]]$ArgumentList
    )

    Write-Host ''
    Write-Host ("=== {0} ===" -f $Title) -ForegroundColor Cyan
    Write-Host ''
    Write-Log -Level 'INFO' -Message ("STARTING: {0}" -f $Title)

    & $FilePath @ArgumentList
    $exitCode = $LASTEXITCODE

    if ($exitCode -eq 0) {
        Write-Host ''
        Write-Host '  +++   OK: Step completed.' -ForegroundColor Green
        Write-Log -Level 'INFO' -Message ("SUCCESS: {0}" -f $Title)
        return 0
    }

    Write-Host ''
    Write-Host '  [X]   FAILED: Found issues but could NOT fix them!' -ForegroundColor Red
    Show-NativeFailureDetails -Title $Title -ExitCode $exitCode
    Write-Log -Level 'ERROR' -Message ("FAILED: {0} - Code: {1}" -f $Title, $exitCode)
    return $exitCode
}

function Invoke-CmdNativeStep {
    param(
        [string]$Title,
        [string]$CommandLine
    )

    Write-Host ''
    Write-Host ("=== {0} ===" -f $Title) -ForegroundColor Cyan
    Write-Host ''
    Write-Log -Level 'INFO' -Message ("STARTING: {0}" -f $Title)

    & cmd.exe /d /c $CommandLine
    $exitCode = $LASTEXITCODE

    if ($exitCode -eq 0) {
        Write-Host ''
        Write-Host '  +++   OK: Step completed.' -ForegroundColor Green
        Write-Log -Level 'INFO' -Message ("SUCCESS: {0}" -f $Title)
        return 0
    }

    Write-Host ''
    Write-Host '  [X]   FAILED: Found issues but could NOT fix them!' -ForegroundColor Red
    Show-NativeFailureDetails -Title $Title -ExitCode $exitCode
    Write-Log -Level 'ERROR' -Message ("FAILED: {0} - Code: {1}" -f $Title, $exitCode)
    return $exitCode
}

function Start-FullCleanupInWtPane {
    if (-not $env:WT_SESSION) {
        return $false
    }

    $wtCommand = Get-Command wt.exe -ErrorAction SilentlyContinue
    if ($null -eq $wtCommand) {
        return $false
    }

    $runnerPath = Join-Path $PSScriptRoot 'FullCleanup.cmd'
    if (-not (Test-Path -LiteralPath $runnerPath)) {
        return $false
    }

    $argList = @(
        '-w', '0',
        'split-pane',
        '-V',
        'cmd.exe',
        '/c',
        $runnerPath
    )

    if (-not [string]::IsNullOrWhiteSpace($script:LogFile)) {
        $argList += $script:LogFile
    }

    Start-Process -FilePath $wtCommand.Source -ArgumentList $argList | Out-Null
    return $true
}

function Invoke-FullCleanup {
    Clear-Host
    Write-Host ''
    Write-Host '==========================================' -ForegroundColor Cyan
    Write-Host '   FULL SYSTEM CLEANUP' -ForegroundColor White
    Write-Host '==========================================' -ForegroundColor Cyan
    Write-Host ''
    Write-Host '  ⚠️  This will:' -ForegroundColor Yellow
    Write-Host '      • Run the full SFC + DISM + WinSxS Temp sequence' -ForegroundColor Gray
    Write-Host '      • Use the aggressive DISM /StartComponentCleanup /ResetBase path' -ForegroundColor Gray
    Write-Host '      • Open a dedicated WT split pane when available' -ForegroundColor Gray
    Write-Host '      • Take a while depending on image health and component-store size' -ForegroundColor Gray
    Write-Host ''
    if ([string]::IsNullOrWhiteSpace($script:LogFile)) {
        Write-Host '  Logs: unavailable (no writable log directory found)' -ForegroundColor DarkYellow
    }
    else {
        Write-Host ("  📄 Logs: {0}" -f $script:LogFile) -ForegroundColor Green
    }
    Write-Host ''
    $confirm = Read-EnterOrEscChoice -EnterLabel 'Start Full Cleanup' -EnterDescription 'Run the full servicing and cleanup flow now'
    if ($confirm -eq 'ESC') {
        Write-Host '  Cancelled.' -ForegroundColor DarkGray
        return $script:SkipReturnToMenuToken
    }

    if (Start-FullCleanupInWtPane) {
        Write-Host ''
        Write-Host '  Full Cleanup opened in a Windows Terminal split pane.' -ForegroundColor Green
        Write-Host '  Run and watch the native progress there. Close that pane when finished.' -ForegroundColor DarkGray
        Wait-ReturnToMenu
        return
    }

    Clear-Host
    Write-Host ''
    Write-Host '==========================================' -ForegroundColor Cyan
    Write-Host '   FULL SYSTEM CLEANUP' -ForegroundColor White
    Write-Host '==========================================' -ForegroundColor Cyan
    Write-Host ''
    if ([string]::IsNullOrWhiteSpace($script:LogFile)) {
        Write-Host 'Logs disabled: no writable log directory was available.' -ForegroundColor DarkYellow
    }
    else {
        Write-Host ("Logs saved to: {0}" -f $script:LogFile) -ForegroundColor DarkGray
    }
    Write-Host ''

    Reset-TrustedInstaller
    [void](Invoke-CmdNativeStep -Title 'SFC (Initial Scan)' -CommandLine 'sfc.exe /scannow')
    [void](Invoke-CmdNativeStep -Title 'DISM AnalyzeComponentStore' -CommandLine 'dism.exe /Online /Cleanup-Image /AnalyzeComponentStore')
    [void](Invoke-CmdNativeStep -Title 'DISM RestoreHealth' -CommandLine 'dism.exe /Online /Cleanup-Image /RestoreHealth')
    [void](Invoke-CmdNativeStep -Title 'DISM StartComponentCleanup /ResetBase' -CommandLine 'dism.exe /Online /Cleanup-Image /StartComponentCleanup /ResetBase')

    Write-Host ''
    Write-Host '=== Cleaning WinSxS Temp ===' -ForegroundColor Cyan
    & (Join-Path $PSScriptRoot 'CleanInFlight.ps1') -SilentCaller

    Reset-TrustedInstaller
    [void](Invoke-CmdNativeStep -Title 'SFC (Final Verification)' -CommandLine 'sfc.exe /scannow')

    Write-Host ''
    Write-Host '==========================================' -ForegroundColor Green
    Write-Host '   ALL STEPS COMPLETED' -ForegroundColor White
    Write-Host '==========================================' -ForegroundColor Green
    Write-Host ''
    Write-Host ' Status Legend:' -ForegroundColor Yellow
    Write-Host '  +++   OK: No issues found' -ForegroundColor Green
    Write-Host '  [~]   FIXED: Repaired issues' -ForegroundColor Yellow
    Write-Host '  [X]   FAILED: Could not repair' -ForegroundColor Red
    Wait-ReturnToMenu
}

function Invoke-InFlightOnly {
    Clear-Host
    Write-Host ''
    Write-Host '==========================================' -ForegroundColor Cyan
    Write-Host '   INFLIGHT CLEANUP (MoveFileEx/Registry)' -ForegroundColor White
    Write-Host '==========================================' -ForegroundColor Cyan
    Write-Host ''
    Write-Host '  ⚠️  This will:' -ForegroundColor Yellow
    Write-Host '      • Run the standalone WinSxS Temp / InFlight cleanup path' -ForegroundColor Gray
    Write-Host '      • Delete what it can now and schedule locked leftovers for reboot-time removal' -ForegroundColor Gray
    Write-Host '      • Skip the SFC / DISM stages completely' -ForegroundColor Gray
    Write-Host ''
    $confirm = Read-EnterOrEscChoice -EnterLabel 'Run InFlight Cleanup only' -EnterDescription 'Start the standalone WinSxS Temp cleanup now'
    if ($confirm -eq 'ESC') {
        Write-Host '  Cancelled.' -ForegroundColor DarkGray
        return $script:SkipReturnToMenuToken
    }

    & (Join-Path $PSScriptRoot 'CleanInFlight.ps1') -SilentCaller
    Wait-ReturnToMenu
}

function Show-DetailedServicingLogs {
    Clear-Host
    Write-Host ''
    Write-Host '==========================================' -ForegroundColor Cyan
    Write-Host '   DISM / CBS FAILURE DETAILS' -ForegroundColor White
    Write-Host '==========================================' -ForegroundColor Cyan
    Write-Host ''
    Write-Host '  DISM log: C:\Windows\Logs\DISM\dism.log' -ForegroundColor DarkGray
    Write-Host '  CBS log:  C:\Windows\Logs\CBS\CBS.log' -ForegroundColor DarkGray
    Write-Host ''

    try {
        & (Join-Path $PSScriptRoot 'ManageUpdates.ps1') -Action DismFailureSummaryFull -SilentCaller
    }
    catch {
        Write-Host '  Unable to read recent servicing log lines.' -ForegroundColor Yellow
    }

    Wait-ReturnToMenu
}

function Open-WindowsUpdateManager {
    Clear-Host
    & (Join-Path $PSScriptRoot 'ManageUpdates.ps1') -Action Menu -SilentCaller
}

function Show-MainMenu {
    Clear-Host
    if ($null -eq $script:CachedLiveDownloadCacheLine) {
        $script:CachedLiveDownloadCacheLine = Get-LiveDownloadCacheStatusLine
    }
    if ($null -eq $script:CachedDeliveryOptimizationLine) {
        $script:CachedDeliveryOptimizationLine = Get-DeliveryOptimizationStatusLine
    }

    $liveDownloadCacheLine = $script:CachedLiveDownloadCacheLine
    $deliveryOptimizationLine = $script:CachedDeliveryOptimizationLine
    $toolSelfUpdateLine = Get-ToolSelfUpdateStatusLine

    Write-Host ''
    Write-Host '==========================================' -ForegroundColor Cyan
    Write-Host '   SYSTEM CLEANUP AND REPAIR TOOL' -ForegroundColor White
    Write-Host '==========================================' -ForegroundColor Cyan
    Write-Host ''
    Write-Host '  Choose an option:' -ForegroundColor White
    Write-Host ''
    Write-Host '   [ 1 ] Full Cleanup (SFC + DISM + InFlight)' -ForegroundColor Green
    Write-Host '         Run SFC, DISM, and WinSxS Temp cleanup' -ForegroundColor DarkGray
    Write-Host ''
    Write-Host '   [ 2 ] InFlight Cleanup Only (MoveFileEx)' -ForegroundColor Yellow
    Write-Host '         Quick — schedules locked files for deletion on reboot' -ForegroundColor DarkGray
    Write-Host ''
    Write-Host '   [ 3 ] Live SoftwareDistribution Cleanup' -ForegroundColor Cyan
    Write-Host "         $liveDownloadCacheLine" -ForegroundColor DarkGray
    Write-Host ''
    Write-Host '   [ 4 ] Delivery Optimization Cleanup + Disable' -ForegroundColor White
    Write-Host "         $deliveryOptimizationLine" -ForegroundColor DarkGray
    Write-Host ''
    Write-Host '   [ 5 ] Windows Update Manager' -ForegroundColor Blue
    Write-Host '         Hide/unhide/list updates, reset cache, block Win11' -ForegroundColor DarkGray
    Write-Host ''
    Write-Host '   [ 6 ] Last DISM/CBS Failure Details' -ForegroundColor Magenta
    Write-Host '         Full-width recent servicing log view' -ForegroundColor DarkGray
    Write-Host ''
    Write-Host '   [ 7 ] Update This Tool (InstallerCore)' -ForegroundColor Cyan
    Write-Host "         $toolSelfUpdateLine" -ForegroundColor DarkGray
    Write-Host ''
    Write-Host '   [ ESC ] Close / Cancel' -ForegroundColor Red
    Write-Host ''
}

if (Start-PreferredHost) {
    return
}

Initialize-Logging

while ($true) {
    Show-MainMenu
    $choice = Read-MainMenuKey

    switch -Regex ($choice) {
        '^1$' {
            Clear-Host
            [void](Invoke-FullCleanup)
            continue
        }
        '^2$' {
            Clear-Host
            [void](Invoke-InFlightOnly)
            continue
        }
        '^3$' {
            Clear-Host
            $liveCleanupResult = & (Join-Path $PSScriptRoot 'ManageUpdates.ps1') -Action LiveCleanup -SilentCaller
            if ($liveCleanupResult -ne $script:SkipReturnToMenuToken) {
                $script:CachedLiveDownloadCacheLine = Get-LiveDownloadCacheStatusLine
                Wait-ReturnToMenu
            }
            continue
        }
        '^4$' {
            Clear-Host
            $deliveryOptimizationResult = & (Join-Path $PSScriptRoot 'ManageUpdates.ps1') -Action DeliveryOptimizationCleanup -SilentCaller
            if ($deliveryOptimizationResult -ne '__SYSTEMCLEANUP_SKIP_RETURN_TO_MENU__') {
                $script:CachedDeliveryOptimizationLine = Get-DeliveryOptimizationStatusLine
                Wait-ReturnToMenu
            }
            continue
        }
        '^5$' {
            Clear-Host
            [void](Open-WindowsUpdateManager)
            continue
        }
        '^6$' {
            Clear-Host
            [void](Show-DetailedServicingLogs)
            continue
        }
        '^7$' {
            Clear-Host
            $toolSelfUpdateResult = & (Join-Path $PSScriptRoot 'ManageUpdates.ps1') -Action ToolSelfUpdate -SilentCaller
            if ($toolSelfUpdateResult -ne '__SYSTEMCLEANUP_SKIP_RETURN_TO_MENU__') {
                Wait-ReturnToMenu
            }
            continue
        }
        '^ESC$' {
            break
        }
        default {
            Write-Host '  Invalid choice.' -ForegroundColor Red
            Start-Sleep -Seconds 1
        }
    }
}
