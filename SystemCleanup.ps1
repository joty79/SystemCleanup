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
    Write-Host '  Enter choice (1/2/3/4/5/ESC): ' -ForegroundColor White -NoNewline
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

function Get-LiveDownloadCacheStatusLine {
    $manageUpdatesPath = Join-Path $PSScriptRoot 'ManageUpdates.ps1'
    try {
        return (& $manageUpdatesPath -Action LiveCleanupStatus -SilentCaller | Out-String).Trim()
    }
    catch {
        return 'Clean live Download cache files'
    }
}

function Reset-TrustedInstaller {
    Write-Host ''
    Write-Host '  Refreshing TrustedInstaller Service...' -ForegroundColor DarkGray
    & net.exe stop trustedinstaller *> $null
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
        '--title', 'SystemCleanup Full Cleanup',
        'cmd.exe',
        '/k',
        $runnerPath
    )

    if (-not [string]::IsNullOrWhiteSpace($script:LogFile)) {
        $argList += $script:LogFile
    }

    Start-Process -FilePath $wtCommand.Source -ArgumentList $argList | Out-Null
    return $true
}

function Invoke-FullCleanup {
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
    [void](Invoke-CmdNativeStep -Title 'DISM StartComponentCleanup' -CommandLine 'dism.exe /Online /Cleanup-Image /StartComponentCleanup')

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
    & (Join-Path $PSScriptRoot 'CleanInFlight.ps1') -SilentCaller
    Wait-ReturnToMenu
}

function Show-MainMenu {
    Clear-Host
    $liveDownloadCacheLine = Get-LiveDownloadCacheStatusLine

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
    Write-Host '   [ 4 ] Windows Update Cleanup (Disk Cleanup Utility)' -ForegroundColor Magenta
    Write-Host '         cleanmgr /sagerun:88 (best after updates + reboot)' -ForegroundColor DarkGray
    Write-Host ''
    Write-Host '   [ 5 ] Windows Update Manager' -ForegroundColor Blue
    Write-Host '         Hide/unhide/list updates, reset cache, block Win11' -ForegroundColor DarkGray
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
            Invoke-FullCleanup
            continue
        }
        '^2$' {
            Invoke-InFlightOnly
            continue
        }
        '^3$' {
            & (Join-Path $PSScriptRoot 'ManageUpdates.ps1') -Action LiveCleanup -SilentCaller
            Wait-ReturnToMenu
            continue
        }
        '^4$' {
            & (Join-Path $PSScriptRoot 'ManageUpdates.ps1') -Action WindowsUpdateCleanup -SilentCaller
            Wait-ReturnToMenu
            continue
        }
        '^5$' {
            & (Join-Path $PSScriptRoot 'ManageUpdates.ps1') -Action Menu -SilentCaller
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
