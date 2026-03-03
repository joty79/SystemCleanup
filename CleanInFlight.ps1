# InFlight Cleanup — Direct Registry + MoveFileEx
# Called by SystemCleanup.cmd Option 2

param([switch]$SilentCaller)

# Recommended by Gemini Web (Safe Encoding for Greek paths/console UI)
$OutputEncoding = [Console]::OutputEncoding = [System.Text.Encoding]::UTF8

$winsxsTemp = "C:\Windows\WinSxS\Temp"

if (-not (Test-Path $winsxsTemp)) {
    Write-Host "`n  WinSxS\Temp not found — Already clean!" -ForegroundColor Green
    if (-not $SilentCaller) { Read-Host "`nPress Enter to close" }
    return
}

# Check if Temp has any contents
$tempContents = Get-ChildItem -LiteralPath $winsxsTemp -Force -ErrorAction SilentlyContinue
if (-not $tempContents -or $tempContents.Count -eq 0) {
    Write-Host "`n  WinSxS\Temp is empty — Already clean!" -ForegroundColor Green
    if (-not $SilentCaller) { Read-Host "`nPress Enter to close" }
    return
}

# Step 1: Stop services, take ownership, delete contents of WinSxS\Temp
Write-Host "`n  Step 1: Stopping services..." -ForegroundColor Yellow
Stop-Service TrustedInstaller -Force -ErrorAction SilentlyContinue
Stop-Service wuauserv -Force -ErrorAction SilentlyContinue

Write-Host "  Taking ownership of WinSxS\Temp contents..." -ForegroundColor Yellow
& takeown.exe /F $winsxsTemp /R /A /D Y > $null 2>&1

Write-Host "  Granting permissions..." -ForegroundColor Yellow
& icacls.exe $winsxsTemp /grant "Administrators:F" /T /C /Q > $null 2>&1

Write-Host "  Deleting contents of WinSxS\Temp..." -ForegroundColor Yellow
# Delete each child inside Temp (but keep the Temp folder itself)
foreach ($child in (Get-ChildItem -LiteralPath $winsxsTemp -Force -ErrorAction SilentlyContinue)) {
    cmd /c "rd /s /q `"$($child.FullName)`" 2>nul"
    if (Test-Path -LiteralPath $child.FullName) {
        Remove-Item -LiteralPath $child.FullName -Force -Recurse -ErrorAction SilentlyContinue
    }
}
Start-Service wuauserv -ErrorAction SilentlyContinue

# Check if everything was deleted
$remainingCheck = Get-ChildItem -LiteralPath $winsxsTemp -Force -ErrorAction SilentlyContinue
if (-not $remainingCheck -or $remainingCheck.Count -eq 0) {
    Write-Host "  WinSxS\Temp cleaned completely!" -ForegroundColor Green
    if (-not $SilentCaller) { Read-Host "`nPress Enter to close" }
    return
}

# Step 2: Get remaining locked files across all of WinSxS\Temp
$remaining = cmd /c "dir /b /s /a-d `"$winsxsTemp`" 2>nul"
$count = ($remaining | Measure-Object).Count
Write-Host "  $count locked files remain in WinSxS\Temp" -ForegroundColor Cyan

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
    # Also schedule folders (deepest first)
    $dirs = cmd /c "dir /b /s /ad `"$winsxsTemp`" 2>nul" | Sort-Object -Descending
    foreach ($dir in $dirs) { if ($dir) { [void]$Kernel32::MoveFileEx($dir, $null, 4) } }
    # Don't delete the Temp folder itself — just its contents
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
        [void]$newEntries.Add($ntPath)
        [void]$newEntries.Add("")    # empty = delete (not rename)
        $scheduled++
    }
}

# Folders (deepest first) — don't schedule the Temp folder itself
$dirs = cmd /c "dir /b /s /ad `"$winsxsTemp`" 2>nul" | Sort-Object -Descending
foreach ($dir in $dirs) {
    if ($dir) {
        [void]$newEntries.Add("\??\$dir")
        [void]$newEntries.Add("")
    }
}

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
    Write-Host "  Some files are WRP-protected and cannot be deleted." -ForegroundColor DarkGray
    Write-Host "  Windows considers them active components." -ForegroundColor DarkGray
}

if (-not $SilentCaller) { Read-Host "`nPress Enter to close" }
