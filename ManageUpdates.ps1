# ManageUpdates.ps1 — Windows Update Manager (Native COM API)
# Called by SystemCleanup.cmd Option 3
# Zero external dependencies — uses built-in Microsoft.Update.Session COM

param([switch]$SilentCaller)

# 🔸 Force UTF-8 Encoding
$OutputEncoding = [Console]::OutputEncoding = [System.Text.Encoding]::UTF8

# ─────────────────────────────────────────────
# 🔵 HELPER: Read single key press (for menu)
# ─────────────────────────────────────────────
function Read-MenuKey {
    param([string]$Prompt = '  Choose')
    Write-Host "$Prompt" -ForegroundColor Gray -NoNewline
    Write-Host ': ' -NoNewline
    $key = $Host.UI.RawUI.ReadKey('NoEcho,IncludeKeyDown')
    if ($key.VirtualKeyCode -eq 27) {
        # Escape pressed
        Write-Host 'ESC' -ForegroundColor DarkGray
        return 'ESC'
    }
    $ch = $key.Character
    if ($ch) {
        Write-Host $ch
        return [string]$ch
    }
    Write-Host ''
    return ''
}

function Wait-ReturnToMenu {
    Write-Host "`n  Press any key to return to menu..." -ForegroundColor Gray
    $null = $Host.UI.RawUI.ReadKey('NoEcho,IncludeKeyDown')
}

# ─────────────────────────────────────────────
# 🔵 HELPER: Search Updates via COM API
# ─────────────────────────────────────────────
function Get-PendingUpdates {
    Write-Host "`n  Searching for pending updates..." -ForegroundColor Cyan
    $session  = New-Object -ComObject Microsoft.Update.Session
    $searcher = $session.CreateUpdateSearcher()
    try {
        $results = $searcher.Search("IsInstalled=0 AND IsHidden=0")
    }
    catch {
        Write-Host "  Failed to search updates: $($_.Exception.Message)" -ForegroundColor Red
        return $null
    }
    return $results
}

function Get-HiddenUpdates {
    Write-Host "`n  Searching for hidden updates..." -ForegroundColor Cyan
    $session  = New-Object -ComObject Microsoft.Update.Session
    $searcher = $session.CreateUpdateSearcher()
    try {
        $results = $searcher.Search("IsInstalled=0 AND IsHidden=1")
    }
    catch {
        Write-Host "  Failed to search hidden updates: $($_.Exception.Message)" -ForegroundColor Red
        return $null
    }
    return $results
}

function Show-UpdateList {
    param(
        [object]$Results,
        [string]$Header
    )
    
    if (-not $Results -or $Results.Updates.Count -eq 0) {
        Write-Host "  No updates found." -ForegroundColor DarkGray
        return $false
    }
    
    Write-Host "`n  $Header" -ForegroundColor Cyan
    Write-Host "  $('─' * 60)" -ForegroundColor DarkGray
    
    for ($i = 0; $i -lt $Results.Updates.Count; $i++) {
        $update = $Results.Updates.Item($i)
        $title  = $update.Title
        $sizeMB = [math]::Round($update.MaxDownloadSize / 1MB, 1)
        
        # Extract KB number if present
        $kb = ""
        if ($update.KBArticleIDs.Count -gt 0) {
            $kb = " (KB$($update.KBArticleIDs.Item(0)))"
        }
        
        $idx = $i + 1
        Write-Host "    [$idx] " -ForegroundColor Yellow -NoNewline
        Write-Host "$title$kb" -ForegroundColor White -NoNewline
        if ($sizeMB -gt 0) {
            Write-Host " — ${sizeMB} MB" -ForegroundColor DarkGray
        } else {
            Write-Host ""
        }
    }
    Write-Host "  $('─' * 60)" -ForegroundColor DarkGray
    return $true
}

# ─────────────────────────────────────────────
# 🔵 ACTION: Hide Update(s)
# ─────────────────────────────────────────────
function Hide-SelectedUpdates {
    # ⚠️ Workflow warning — hiding only works reliably on a fresh update list
    Write-Host "" 
    Write-Host "  ╔════════════════════════════════════════════════════════════╗" -ForegroundColor Yellow
    Write-Host "  ║  ⚠️  CORRECT WORKFLOW TO PERMANENTLY HIDE UPDATES:       ║" -ForegroundColor Yellow
    Write-Host "  ║                                                          ║" -ForegroundColor Yellow
    Write-Host "  ║   1. Reset Update Cache  [5]                             ║" -ForegroundColor Yellow
    Write-Host "  ║   2. REBOOT your PC                                      ║" -ForegroundColor Yellow
    Write-Host "  ║   3. Come back here and Hide Updates  [2]                ║" -ForegroundColor Yellow
    Write-Host "  ║                                                          ║" -ForegroundColor Yellow
    Write-Host "  ║  If you hide FIRST and then reset, the hidden flag       ║" -ForegroundColor Yellow
    Write-Host "  ║  gets wiped and the update will reappear!                ║" -ForegroundColor Yellow
    Write-Host "  ╚════════════════════════════════════════════════════════════╝" -ForegroundColor Yellow
    Write-Host ""
    Write-Host "  Continue anyway? (Y/N)" -ForegroundColor Gray
    $proceed = Read-Host "  Choice"
    if ($proceed -notmatch '^[Yy]') {
        Write-Host "  Cancelled." -ForegroundColor DarkGray
        return
    }

    $results = Get-PendingUpdates
    $hasUpdates = Show-UpdateList -Results $results -Header "PENDING UPDATES (available to hide)"
    
    if (-not $hasUpdates) { return }
    
    Write-Host ""
    Write-Host "  Enter number(s) to hide (comma-separated), or keyword to match:" -ForegroundColor Gray
    Write-Host "  Example: 1,3  or  'Linux'  or  'KB5034441'" -ForegroundColor DarkGray
    $input_val = Read-Host "  Selection"
    
    if ([string]::IsNullOrWhiteSpace($input_val)) { return }
    
    $hiddenCount = 0
    
    # Check if input is numbers (comma-separated)
    $isNumeric = $input_val -match '^[\d,\s]+$'
    
    if ($isNumeric) {
        $indices = $input_val -split ',' | ForEach-Object { $_.Trim() } | Where-Object { $_ -match '^\d+$' }
        foreach ($idx in $indices) {
            $i = [int]$idx - 1
            if ($i -ge 0 -and $i -lt $results.Updates.Count) {
                $update = $results.Updates.Item($i)
                try {
                    $update.IsHidden = $true
                    Write-Host "  ✅ Hidden: $($update.Title)" -ForegroundColor Green
                    $hiddenCount++
                }
                catch {
                    Write-Host "  ⚠️ Cannot hide: $($update.Title) — $($_.Exception.Message)" -ForegroundColor Red
                }
            } else {
                Write-Host "  ⚠️ Invalid number: $idx" -ForegroundColor Red
            }
        }
    }
    else {
        # Keyword match
        $keyword = $input_val.Trim().Trim("'").Trim('"')
        for ($i = 0; $i -lt $results.Updates.Count; $i++) {
            $update = $results.Updates.Item($i)
            $matchTitle = $update.Title -like "*$keyword*"
            $matchKB = $false
            if ($update.KBArticleIDs.Count -gt 0) {
                $matchKB = "KB$($update.KBArticleIDs.Item(0))" -like "*$keyword*"
            }
            
            if ($matchTitle -or $matchKB) {
                try {
                    $update.IsHidden = $true
                    Write-Host "  ✅ Hidden: $($update.Title)" -ForegroundColor Green
                    $hiddenCount++
                }
                catch {
                    Write-Host "  ⚠️ Cannot hide: $($update.Title) — $($_.Exception.Message)" -ForegroundColor Red
                }
            }
        }
        if ($hiddenCount -eq 0) {
            Write-Host "  No updates matching '$keyword' found." -ForegroundColor Yellow
        }
    }
    
    if ($hiddenCount -gt 0) {
        Write-Host "`n  $hiddenCount update(s) hidden successfully!" -ForegroundColor Green
        Write-Host "  They will no longer appear in Windows Update." -ForegroundColor DarkGray
    }
}

# ─────────────────────────────────────────────
# 🔵 ACTION: Unhide Update(s)
# ─────────────────────────────────────────────
function Unhide-SelectedUpdates {
    $results = Get-HiddenUpdates
    $hasUpdates = Show-UpdateList -Results $results -Header "HIDDEN UPDATES (available to restore)"
    
    if (-not $hasUpdates) { return }
    
    Write-Host ""
    Write-Host "  Enter number(s) to unhide (comma-separated), or 'all':" -ForegroundColor Gray
    $input_val = Read-Host "  Selection"
    
    if ([string]::IsNullOrWhiteSpace($input_val)) { return }
    
    $unhiddenCount = 0
    
    if ($input_val.Trim() -eq 'all') {
        for ($i = 0; $i -lt $results.Updates.Count; $i++) {
            $update = $results.Updates.Item($i)
            try {
                $update.IsHidden = $false
                Write-Host "  ✅ Restored: $($update.Title)" -ForegroundColor Green
                $unhiddenCount++
            }
            catch {
                Write-Host "  ⚠️ Cannot restore: $($update.Title) — $($_.Exception.Message)" -ForegroundColor Red
            }
        }
    }
    else {
        $indices = $input_val -split ',' | ForEach-Object { $_.Trim() } | Where-Object { $_ -match '^\d+$' }
        foreach ($idx in $indices) {
            $i = [int]$idx - 1
            if ($i -ge 0 -and $i -lt $results.Updates.Count) {
                $update = $results.Updates.Item($i)
                try {
                    $update.IsHidden = $false
                    Write-Host "  ✅ Restored: $($update.Title)" -ForegroundColor Green
                    $unhiddenCount++
                }
                catch {
                    Write-Host "  ⚠️ Cannot restore: $($update.Title) — $($_.Exception.Message)" -ForegroundColor Red
                }
            } else {
                Write-Host "  ⚠️ Invalid number: $idx" -ForegroundColor Red
            }
        }
    }
    
    if ($unhiddenCount -gt 0) {
        Write-Host "`n  $unhiddenCount update(s) restored — will reappear in Windows Update." -ForegroundColor Green
    }
}

# ─────────────────────────────────────────────
# 🔵 HELPER: Clean stale .old backup folders
# ─────────────────────────────────────────────
function Remove-StaleOldFolders {
    param([switch]$Silent)
    $sdParent = 'C:\Windows'
    $crParent = 'C:\Windows\System32'
    $removedCount = 0

    # Find SoftwareDistribution.old* folders
    $sdOldDirs = Get-ChildItem -Path $sdParent -Directory -Filter 'SoftwareDistribution.old*' -ErrorAction SilentlyContinue
    # Find catroot2.old* folders
    $crOldDirs = Get-ChildItem -Path $crParent -Directory -Filter 'catroot2.old*' -ErrorAction SilentlyContinue

    $allOld = @()
    if ($sdOldDirs) { $allOld += $sdOldDirs }
    if ($crOldDirs) { $allOld += $crOldDirs }

    if ($allOld.Count -eq 0) {
        if (-not $Silent) {
            Write-Host "  No stale .old backup folders found." -ForegroundColor DarkGray
        }
        return 0
    }

    if (-not $Silent) {
        Write-Host "`n  Found $($allOld.Count) stale backup folder(s):" -ForegroundColor Yellow
        foreach ($d in $allOld) {
            $sizeMB = [math]::Round(((Get-ChildItem -Path $d.FullName -Recurse -File -ErrorAction SilentlyContinue | Measure-Object -Property Length -Sum).Sum / 1MB), 1)
            Write-Host "    • $($d.FullName)  ($sizeMB MB)" -ForegroundColor Gray
        }
    }

    foreach ($d in $allOld) {
        try {
            Remove-Item -Path $d.FullName -Recurse -Force -ErrorAction Stop
            if (-not $Silent) {
                Write-Host "  ✅ Deleted: $($d.Name)" -ForegroundColor Green
            }
            $removedCount++
        }
        catch {
            if (-not $Silent) {
                Write-Host "  ⚠️ Cannot delete: $($d.Name) — $($_.Exception.Message)" -ForegroundColor Red
            }
        }
    }
    return $removedCount
}

# ─────────────────────────────────────────────
# 🔵 ACTION: Reset Windows Update Cache
# ─────────────────────────────────────────────
function Reset-UpdateCache {
    Write-Host "`n  🔵 RESETTING WINDOWS UPDATE CACHE" -ForegroundColor Cyan
    Write-Host "  $('─' * 40)" -ForegroundColor DarkGray
    
    Write-Host "  ⚠️  This will:" -ForegroundColor Yellow
    Write-Host "      • Stop update services (wuauserv, cryptSvc, bits, msiserver)" -ForegroundColor Gray
    Write-Host "      • Delete any existing .old backup folders first" -ForegroundColor Gray
    Write-Host "      • Rename SoftwareDistribution and catroot2 folders" -ForegroundColor Gray
    Write-Host "      • Restart services" -ForegroundColor Gray
    Write-Host ""
    Write-Host "  💡 After reset, REBOOT, then use [2] Hide Updates on the fresh list." -ForegroundColor Cyan
    Write-Host ""
    
    $confirm = Read-Host "  Proceed? (Y/N)"
    if ($confirm -notmatch '^[Yy]') {
        Write-Host "  Cancelled." -ForegroundColor DarkGray
        return
    }
    
    $services = @('wuauserv', 'cryptSvc', 'bits', 'msiserver')
    
    Write-Host "`n  Stopping services..." -ForegroundColor Yellow
    foreach ($svc in $services) {
        net stop $svc > $null 2>&1
    }
    
    # Clean up any previous .old backup folders before creating new ones
    Write-Host "`n  Cleaning stale .old backup folders..." -ForegroundColor Yellow
    $cleaned = Remove-StaleOldFolders -Silent
    if ($cleaned -gt 0) {
        Write-Host "  ✅ Removed $cleaned old backup folder(s)." -ForegroundColor Green
    } else {
        Write-Host "  No stale backups to clean." -ForegroundColor DarkGray
    }

    $sdPath = "C:\Windows\SoftwareDistribution"
    $crPath = "C:\Windows\System32\catroot2"
    $ts = Get-Date -Format 'yyyyMMdd_HHmmss'
    
    Write-Host "`n  Renaming SoftwareDistribution..." -ForegroundColor Yellow
    if (Test-Path $sdPath) {
        Rename-Item $sdPath "${sdPath}.old_${ts}" -ErrorAction SilentlyContinue
        if ($?) { Write-Host "  ✅ SoftwareDistribution renamed." -ForegroundColor Green }
        else    { Write-Host "  ⚠️ Could not rename SoftwareDistribution." -ForegroundColor Red }
    }
    
    Write-Host "  Renaming catroot2..." -ForegroundColor Yellow
    if (Test-Path $crPath) {
        Rename-Item $crPath "${crPath}.old_${ts}" -ErrorAction SilentlyContinue
        if ($?) { Write-Host "  ✅ catroot2 renamed." -ForegroundColor Green }
        else    { Write-Host "  ⚠️ Could not rename catroot2." -ForegroundColor Red }
    }
    
    Write-Host "`n  Starting services..." -ForegroundColor Yellow
    foreach ($svc in $services) {
        net start $svc > $null 2>&1
    }
    
    Write-Host "`n  ✅ Windows Update cache reset complete!" -ForegroundColor Green
    Write-Host ""
    Write-Host "  ╔════════════════════════════════════════════════════════════╗" -ForegroundColor Cyan
    Write-Host "  ║  💡  NEXT STEPS:                                         ║" -ForegroundColor Cyan
    Write-Host "  ║                                                          ║" -ForegroundColor Cyan
    Write-Host "  ║   1. REBOOT your PC now                                  ║" -ForegroundColor Cyan
    Write-Host "  ║   2. After reboot, open this tool again                  ║" -ForegroundColor Cyan
    Write-Host "  ║   3. Use [2] Hide Updates on the fresh update list        ║" -ForegroundColor Cyan
    Write-Host "  ║                                                          ║" -ForegroundColor Cyan
    Write-Host "  ║  The .old backup folders will be auto-cleaned on the     ║" -ForegroundColor Cyan
    Write-Host "  ║  next reset, or use [6] to clean them manually.          ║" -ForegroundColor Cyan
    Write-Host "  ╚════════════════════════════════════════════════════════════╝" -ForegroundColor Cyan
}

# ─────────────────────────────────────────────
# 🔵 ACTION: Block / Unblock Windows 11 Upgrade
# ─────────────────────────────────────────────
function Get-Win11BlockStatus {
    $policyPath = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate'
    if (-not (Test-Path $policyPath)) { return $false }
    $trv = Get-ItemProperty -Path $policyPath -Name 'TargetReleaseVersion' -ErrorAction SilentlyContinue
    $pv  = Get-ItemProperty -Path $policyPath -Name 'ProductVersion' -ErrorAction SilentlyContinue
    return ($null -ne $trv -and $trv.TargetReleaseVersion -eq 1 -and $null -ne $pv -and $pv.ProductVersion -eq 'Windows 10')
}

function Set-Win11Block {
    param([bool]$Block)

    $policyPath = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate'

    if ($Block) {
        # Detect current Windows 10 build version (e.g. 22H2)
        $currentBuild = (Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion' -Name 'DisplayVersion' -ErrorAction SilentlyContinue).DisplayVersion
        if ([string]::IsNullOrWhiteSpace($currentBuild)) {
            # Fallback to ReleaseId for older builds
            $currentBuild = (Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion' -Name 'ReleaseId' -ErrorAction SilentlyContinue).ReleaseId
        }
        if ([string]::IsNullOrWhiteSpace($currentBuild)) {
            $currentBuild = '22H2'
        }

        Write-Host "`n  🔵 BLOCKING WINDOWS 11 UPGRADE" -ForegroundColor Cyan
        Write-Host "  $('─' * 40)" -ForegroundColor DarkGray
        Write-Host "  Setting Group Policy to stay on Windows 10 ($currentBuild)..." -ForegroundColor Gray

        if (-not (Test-Path $policyPath)) {
            New-Item -Path $policyPath -Force | Out-Null
        }
        Set-ItemProperty -Path $policyPath -Name 'TargetReleaseVersion' -Value 1 -Type DWord -Force
        Set-ItemProperty -Path $policyPath -Name 'TargetReleaseVersionInfo' -Value $currentBuild -Type String -Force
        Set-ItemProperty -Path $policyPath -Name 'ProductVersion' -Value 'Windows 10' -Type String -Force

        Write-Host ""
        Write-Host "  ✅ Windows 11 upgrade BLOCKED!" -ForegroundColor Green
        Write-Host "      TargetReleaseVersion     = 1" -ForegroundColor DarkGray
        Write-Host "      TargetReleaseVersionInfo = $currentBuild" -ForegroundColor DarkGray
        Write-Host "      ProductVersion           = Windows 10" -ForegroundColor DarkGray
        Write-Host ""
        Write-Host "  Refreshing Group Policy..." -ForegroundColor Gray
        gpupdate /force 2>&1 | Out-Null
        Write-Host "  ✅ Group Policy refreshed." -ForegroundColor Green
        Write-Host ""
        Write-Host "  💡 Windows Update will no longer offer Windows 11." -ForegroundColor Cyan
        Write-Host "     You will still receive Windows 10 security updates." -ForegroundColor DarkGray
    }
    else {
        Write-Host "`n  🔵 REMOVING WINDOWS 11 BLOCK" -ForegroundColor Cyan
        Write-Host "  $('─' * 40)" -ForegroundColor DarkGray
        Write-Host "  Clearing Group Policy target version lock..." -ForegroundColor Gray

        if (Test-Path $policyPath) {
            Remove-ItemProperty -Path $policyPath -Name 'TargetReleaseVersion' -ErrorAction SilentlyContinue
            Remove-ItemProperty -Path $policyPath -Name 'TargetReleaseVersionInfo' -ErrorAction SilentlyContinue
            Remove-ItemProperty -Path $policyPath -Name 'ProductVersion' -ErrorAction SilentlyContinue

            # Clean up the key if it's now empty
            $remaining = Get-ItemProperty -Path $policyPath -ErrorAction SilentlyContinue
            $propCount = @($remaining.PSObject.Properties | Where-Object { $_.Name -notlike 'PS*' }).Count
            if ($propCount -eq 0) {
                Remove-Item -Path $policyPath -Force -ErrorAction SilentlyContinue
            }
        }

        Write-Host ""
        Write-Host "  ✅ Windows 11 block REMOVED!" -ForegroundColor Green
        Write-Host ""
        Write-Host "  Refreshing Group Policy..." -ForegroundColor Gray
        gpupdate /force 2>&1 | Out-Null
        Write-Host "  ✅ Group Policy refreshed." -ForegroundColor Green
        Write-Host ""
        Write-Host "  ⚠️  Windows Update may now offer Windows 11 if your hardware is compatible." -ForegroundColor Yellow
    }
}

function Toggle-Win11Block {
    $isBlocked = Get-Win11BlockStatus

    # Check if we're actually running Windows 10
    $osBuild = [System.Environment]::OSVersion.Version.Build
    $osCaption = (Get-CimInstance Win32_OperatingSystem -Property Caption -ErrorAction SilentlyContinue).Caption

    if ($osBuild -ge 22000) {
        Write-Host ""
        Write-Host "  ⚠️  You are already running Windows 11!" -ForegroundColor Yellow
        Write-Host "      $osCaption (Build $osBuild)" -ForegroundColor DarkGray
        Write-Host "      This option is designed for Windows 10 machines." -ForegroundColor DarkGray
        Write-Host ""
        $continueAnyway = Read-Host "  Continue anyway? (Y/N)"
        if ($continueAnyway -notmatch '^[Yy]') {
            Write-Host "  Cancelled." -ForegroundColor DarkGray
            return
        }
    }

    if ($isBlocked) {
        Write-Host ""
        Write-Host "  Current status: " -ForegroundColor White -NoNewline
        Write-Host "BLOCKED ✅" -ForegroundColor Green
        Write-Host "  Windows 11 upgrade is currently blocked via Group Policy." -ForegroundColor DarkGray
        Write-Host ""
        Write-Host "  Do you want to REMOVE the block? (Y/N)" -ForegroundColor Gray
        $confirm = Read-Host "  Choice"
        if ($confirm -notmatch '^[Yy]') {
            Write-Host "  Cancelled." -ForegroundColor DarkGray
            return
        }
        Set-Win11Block -Block $false
    }
    else {
        Write-Host ""
        Write-Host "  Current status: " -ForegroundColor White -NoNewline
        Write-Host "NOT BLOCKED ⚠️" -ForegroundColor Yellow
        Write-Host "  Windows Update may offer Windows 11 if your hardware is compatible." -ForegroundColor DarkGray
        Write-Host ""
        Write-Host "  Do you want to BLOCK Windows 11 upgrade? (Y/N)" -ForegroundColor Gray
        $confirm = Read-Host "  Choice"
        if ($confirm -notmatch '^[Yy]') {
            Write-Host "  Cancelled." -ForegroundColor DarkGray
            return
        }
        Set-Win11Block -Block $true
    }
}

# ─────────────────────────────────────────────
# 🔵 MAIN MENU LOOP
# ─────────────────────────────────────────────
$menuLoop = $true
while ($menuLoop) {
    # Build the Win11 block status indicator for the menu
    $win11Status = if (Get-Win11BlockStatus) { '🟢 Blocked' } else { '🔴 Not blocked' }

    Write-Host ""
    Write-Host "  ==========================================" -ForegroundColor Cyan
    Write-Host "     WINDOWS UPDATE MANAGER" -ForegroundColor White
    Write-Host "  ==========================================" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "  ┌──────────────────────────────────────────────────────┐" -ForegroundColor DarkYellow
    Write-Host "  │  💡 To permanently hide an update:                  │" -ForegroundColor DarkYellow
    Write-Host "  │     [5] Reset Cache → Reboot → [2] Hide Updates     │" -ForegroundColor DarkYellow
    Write-Host "  └──────────────────────────────────────────────────────┘" -ForegroundColor DarkYellow
    Write-Host ""
    Write-Host "  [1]  List Pending Updates" -ForegroundColor White
    Write-Host "  [2]  Hide Update(s)" -ForegroundColor Yellow
    Write-Host "         Block unwanted updates from appearing" -ForegroundColor DarkGray
    Write-Host "  [3]  Show Hidden Updates" -ForegroundColor White
    Write-Host "  [4]  Unhide Update(s)" -ForegroundColor Green
    Write-Host "         Restore previously hidden updates" -ForegroundColor DarkGray
    Write-Host "  $('─' * 42)" -ForegroundColor DarkGray
    Write-Host "  [5]  Reset Update Cache" -ForegroundColor Red
    Write-Host "         Clears download cache + old backups" -ForegroundColor DarkGray
    Write-Host "  [6]  Clean Stale Backup Folders" -ForegroundColor Magenta
    Write-Host "         Remove leftover .old_* folders" -ForegroundColor DarkGray
    Write-Host "  $('─' * 42)" -ForegroundColor DarkGray
    Write-Host "  [7]  Block Windows 11 Upgrade  " -ForegroundColor Cyan -NoNewline
    Write-Host "[$win11Status]" -ForegroundColor $(if (Get-Win11BlockStatus) { 'Green' } else { 'Yellow' })
    Write-Host "         Pin this PC to Windows 10 via Group Policy" -ForegroundColor DarkGray
    Write-Host "  $('─' * 42)" -ForegroundColor DarkGray
    Write-Host "  [ESC] Back to main menu" -ForegroundColor DarkGray
    Write-Host ""
    $choice = Read-MenuKey -Prompt '  Choose'
    
    switch ($choice) {
        'ESC' {
            $menuLoop = $false
        }
        { $_ -match '^[Xx]$' } {
            $menuLoop = $false
        }
        '1' {
            $r = Get-PendingUpdates
            Show-UpdateList -Results $r -Header "PENDING UPDATES" | Out-Null
            Wait-ReturnToMenu
        }
        '2' {
            Hide-SelectedUpdates
            Wait-ReturnToMenu
        }
        '3' {
            $r = Get-HiddenUpdates
            Show-UpdateList -Results $r -Header "HIDDEN UPDATES" | Out-Null
            Wait-ReturnToMenu
        }
        '4' {
            Unhide-SelectedUpdates
            Wait-ReturnToMenu
        }
        '5' {
            Reset-UpdateCache
            Wait-ReturnToMenu
        }
        '6' {
            Write-Host ""
            Remove-StaleOldFolders
            Wait-ReturnToMenu
        }
        '7' {
            Toggle-Win11Block
            Wait-ReturnToMenu
        }
    }
}

if (-not $SilentCaller) { 
    Write-Host ""
}
