# ManageUpdates.ps1 — Windows Update Manager (Native COM API)
# Called by SystemCleanup.cmd Option 3
# Zero external dependencies — uses built-in Microsoft.Update.Session COM

param([switch]$SilentCaller)

# 🔸 Force UTF-8 Encoding
$OutputEncoding = [Console]::OutputEncoding = [System.Text.Encoding]::UTF8

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
# 🔵 MAIN MENU LOOP
# ─────────────────────────────────────────────
do {
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
    Write-Host "  [X]  Back / Exit" -ForegroundColor DarkGray
    Write-Host ""
    $choice = Read-Host "  Choose"
    
    switch ($choice) {
        "1" {
            $r = Get-PendingUpdates
            Show-UpdateList -Results $r -Header "PENDING UPDATES" | Out-Null
            Write-Host "`n  Press any key..." -ForegroundColor Gray
            $null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
        }
        "2" {
            Hide-SelectedUpdates
            Write-Host "`n  Press any key..." -ForegroundColor Gray
            $null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
        }
        "3" {
            $r = Get-HiddenUpdates
            Show-UpdateList -Results $r -Header "HIDDEN UPDATES" | Out-Null
            Write-Host "`n  Press any key..." -ForegroundColor Gray
            $null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
        }
        "4" {
            Unhide-SelectedUpdates
            Write-Host "`n  Press any key..." -ForegroundColor Gray
            $null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
        }
        "5" {
            Reset-UpdateCache
            Write-Host "`n  Press any key..." -ForegroundColor Gray
            $null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
        }
        "6" {
            Write-Host ""
            Remove-StaleOldFolders
            Write-Host "`n  Press any key..." -ForegroundColor Gray
            $null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
        }
        { $_ -match '^[Xx]$' } { 
            if (-not $SilentCaller) { break }
            return
        }
    }
} while ($choice -notmatch '^[Xx]$')

if (-not $SilentCaller) { 
    Write-Host ""
}
