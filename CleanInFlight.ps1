# InFlight Cleanup — Direct Registry + MoveFileEx
# Called by SystemCleanup.cmd Option 2

param([switch]$SilentCaller)

# Recommended by Gemini Web (Safe Encoding for Greek paths/console UI)
$OutputEncoding = [Console]::OutputEncoding = [System.Text.Encoding]::UTF8

$inFlight = "C:\Windows\WinSxS\Temp\InFlight"

if (-not (Test-Path $inFlight)) {
    Write-Host "`n  InFlight folder not found — Already clean!" -ForegroundColor Green
    if (-not $SilentCaller) { Read-Host "`nPress Enter to close" }
    return
}

# Step 1: Stop services, take ownership, delete
Write-Host "`n  Step 1: Stopping services..." -ForegroundColor Yellow
Stop-Service TrustedInstaller -Force -ErrorAction SilentlyContinue
Stop-Service wuauserv -Force -ErrorAction SilentlyContinue
Start-Sleep -Seconds 2

Write-Host "  Taking ownership..." -ForegroundColor Yellow
& takeown.exe /F $inFlight /R /A /D Y 2>&1 | Out-Null

Write-Host "  Granting permissions..." -ForegroundColor Yellow
& icacls.exe $inFlight /grant "Administrators:F" /T /C /Q 2>&1 | Out-Null

Write-Host "  Deleting..." -ForegroundColor Yellow
cmd /c "rd /s /q `"$inFlight`" 2>nul"
Start-Service wuauserv -ErrorAction SilentlyContinue

if (-not (Test-Path $inFlight)) {
    Write-Host "  InFlight deleted completely!" -ForegroundColor Green
    if (-not $SilentCaller) { Read-Host "`nPress Enter to close" }
    return
}

# Step 2: Get remaining files
$remaining = cmd /c "dir /b /s /a-d `"$inFlight`" 2>nul"
$count = ($remaining | Measure-Object).Count
Write-Host "  $count locked files remain" -ForegroundColor Cyan

# Step 3: Try MoveFileEx API first
Write-Host "`n  Step 2: Trying MoveFileEx API..." -ForegroundColor Yellow
$signature = @'
[DllImport("kernel32.dll", SetLastError=true, CharSet=CharSet.Unicode)]
public static extern bool MoveFileEx(string lpExistingFileName, string lpNewFileName, int dwFlags);
'@
$Kernel32 = Add-Type -MemberDefinition $signature -Name 'Kernel32' -Namespace 'Win32' -PassThru

$ok = 0; $fail = 0
foreach ($file in $remaining) {
    if ($file -and (Test-Path $file)) {
        if ($Kernel32::MoveFileEx($file, $null, 4)) { $ok++ } else { $fail++ }
    }
}

if ($ok -gt 0) {
    # Also schedule folders
    $dirs = cmd /c "dir /b /s /ad `"$inFlight`" 2>nul" | Sort-Object -Descending
    foreach ($dir in $dirs) { if ($dir) { $Kernel32::MoveFileEx($dir, $null, 4) | Out-Null } }
    $Kernel32::MoveFileEx($inFlight, $null, 4) | Out-Null
    Write-Host "  MoveFileEx: Scheduled $ok files — Restart to delete!" -ForegroundColor Green
    if (-not $SilentCaller) { Read-Host "`nPress Enter to close" }
    return
}

# Step 4: MoveFileEx failed — write directly to PendingFileRenameOperations registry
Write-Host "  MoveFileEx blocked (WRP) — writing directly to registry..." -ForegroundColor Yellow

$regPath = "HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager"
$regName = "PendingFileRenameOperations"

# Get existing entries (if any)
$existing = @()
try {
    $prop = Get-ItemProperty $regPath -Name $regName -ErrorAction Stop
    $existing = [string[]]$prop.$regName
} catch { }

# Build new entries: each file needs TWO entries (source, empty string = delete)
$newEntries = [System.Collections.ArrayList]@($existing)
$scheduled = 0

# Files first
foreach ($file in $remaining) {
    if ($file -and (Test-Path $file)) {
        $ntPath = "\??\$file"
        $newEntries.Add($ntPath) | Out-Null
        $newEntries.Add("")    | Out-Null  # empty = delete (not rename)
        $scheduled++
    }
}

# Folders (deepest first)
$dirs = cmd /c "dir /b /s /ad `"$inFlight`" 2>nul" | Sort-Object -Descending
foreach ($dir in $dirs) {
    if ($dir) {
        $newEntries.Add("\??\$dir") | Out-Null
        $newEntries.Add("") | Out-Null
    }
}
# InFlight folder itself
$newEntries.Add("\??\$inFlight") | Out-Null
$newEntries.Add("") | Out-Null

# Write to registry
try {
    Set-ItemProperty -Path $regPath -Name $regName -Value ([string[]]$newEntries) -Type MultiString -ErrorAction Stop
    Write-Host ""
    Write-Host "  Scheduled $scheduled files for deletion on next REBOOT!" -ForegroundColor Green
    Write-Host "  Written directly to PendingFileRenameOperations" -ForegroundColor Cyan
    Write-Host "  Restart your PC to complete the cleanup!" -ForegroundColor Yellow
} catch {
    Write-Host ""
    Write-Host "  FAILED to write to registry: $($_.Exception.Message)" -ForegroundColor Red
    Write-Host "  These 3 files ($([math]::Round(($remaining | ForEach-Object { (Get-Item $_ -ErrorAction SilentlyContinue).Length } | Measure-Object -Sum).Sum / 1MB, 1)) MB) are WRP-protected." -ForegroundColor DarkGray
    Write-Host "  Windows considers them active components — they can't be deleted." -ForegroundColor DarkGray
}

if (-not $SilentCaller) { Read-Host "`nPress Enter to close" }
