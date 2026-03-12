# ManageUpdates.ps1 — Windows Update Manager + Update Cleanup Actions
# Called by SystemCleanup.cmd main menu and submenu actions
# Zero external dependencies — uses built-in Microsoft.Update.Session COM and Windows cleanup tools

param(
    [switch]$SilentCaller,
    [ValidateSet('Menu', 'LiveCleanup', 'WindowsUpdateCleanup', 'LiveCleanupStatus', 'ReadMainMenuChoice')]
    [string]$Action = 'Menu'
)

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

function Format-CleanMgrSlotValueName {
    param([int]$Slot)
    return ('StateFlags{0:D4}' -f $Slot)
}

function Get-SystemCleanupLogDirectory {
    $candidatePaths = @(
        (Join-Path $env:LOCALAPPDATA 'SystemCleanupContext\logs'),
        (Join-Path $env:TEMP 'SystemCleanup')
    ) | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }

    foreach ($candidatePath in $candidatePaths) {
        try {
            if (-not (Test-Path -LiteralPath $candidatePath)) {
                New-Item -Path $candidatePath -ItemType Directory -Force -ErrorAction Stop | Out-Null
            }
            return $candidatePath
        }
        catch {
            continue
        }
    }

    return ''
}

function New-WindowsUpdateCleanupDebugLogPath {
    $logDirectory = Get-SystemCleanupLogDirectory
    if ([string]::IsNullOrWhiteSpace($logDirectory)) {
        return ''
    }

    return (Join-Path $logDirectory ("WindowsUpdateCleanup_debug_{0}.log" -f (Get-Date -Format 'yyyyMMdd_HHmmss')))
}

function Write-WindowsUpdateCleanupDebugLog {
    param(
        [string]$Path,
        [string]$Message
    )

    if ([string]::IsNullOrWhiteSpace($Path)) {
        return
    }

    try {
        $line = '{0} | {1}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss.fff'), $Message
        Add-Content -LiteralPath $Path -Value $line -Encoding UTF8 -ErrorAction Stop
    }
    catch {
    }
}

function Get-CleanMgrProcessSnapshot {
    $rows = @()

    foreach ($process in @(Get-Process -Name cleanmgr -ErrorAction SilentlyContinue)) {
        $rows += [pscustomobject]@{
            Id = $process.Id
            ProcessName = $process.ProcessName
            MainWindowTitle = [string]$process.MainWindowTitle
            Responding = if ($null -ne $process.Responding) { [string]$process.Responding } else { '' }
            StartTime = try { $process.StartTime.ToString('yyyy-MM-dd HH:mm:ss') } catch { '' }
        }
    }

    return $rows
}

function Get-NewCleanMgrProcesses {
    param([int[]]$BaselineIds = @())

    $baseline = @($BaselineIds)
    return @(
        Get-CleanMgrProcessSnapshot | Where-Object { $baseline -notcontains [int]$_.Id }
    )
}

function Get-VolumeCachesSlotSnapshot {
    param([int]$Slot = 88)

    $volumeCachesRoot = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\VolumeCaches'
    $valueName = Format-CleanMgrSlotValueName -Slot $Slot
    $rows = @()

    foreach ($subKey in @(Get-ChildItem -LiteralPath $volumeCachesRoot -ErrorAction SilentlyContinue)) {
        $existing = Get-ItemProperty -LiteralPath $subKey.PSPath -Name $valueName -ErrorAction SilentlyContinue
        $hasValue = $null -ne $existing -and $null -ne $existing.$valueName
        if ($hasValue) {
            $rows += [pscustomobject]@{
                KeyName = $subKey.PSChildName
                ValueName = $valueName
                Value = [int]$existing.$valueName
            }
        }
    }

    return $rows
}

function Write-StructuredDebugBlock {
    param(
        [string]$Path,
        [string]$Title,
        [object[]]$Rows
    )

    Write-WindowsUpdateCleanupDebugLog -Path $Path -Message ('--- {0} ---' -f $Title)
    if (-not $Rows -or @($Rows).Count -eq 0) {
        Write-WindowsUpdateCleanupDebugLog -Path $Path -Message '(none)'
        return
    }

    foreach ($row in @($Rows)) {
        Write-WindowsUpdateCleanupDebugLog -Path $Path -Message (($row | ConvertTo-Json -Compress -Depth 5))
    }
}

function Invoke-RegCommand {
    param(
        [string[]]$Arguments,
        [switch]$AllowNonZeroExit
    )

    $output = (& reg.exe @Arguments 2>&1 | Out-String).Trim()
    $exitCode = $LASTEXITCODE

    if (-not $AllowNonZeroExit -and $exitCode -ne 0) {
        $message = if ([string]::IsNullOrWhiteSpace($output)) {
            "reg.exe failed with exit code $exitCode."
        }
        else {
            $output
        }
        throw $message
    }

    return [pscustomobject]@{
        ExitCode = $exitCode
        Output = $output
    }
}

function Get-LiveDownloadCacheStatusLine {
    $downloadPath = 'C:\Windows\SoftwareDistribution\Download'
    if (-not (Test-Path -LiteralPath $downloadPath)) {
        return 'Download cache path not found'
    }

    $sizeMB = Get-DirectorySizeMB -Path $downloadPath
    return "Clean live Download cache files ($sizeMB MB)"
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
function Get-StaleOldFoldersStatusLine {
    $sdParent = 'C:\Windows'
    $crParent = 'C:\Windows\System32'
    $sdOldDirs = @(Get-ChildItem -Path $sdParent -Directory -Filter 'SoftwareDistribution.old*' -ErrorAction SilentlyContinue)
    $crOldDirs = @(Get-ChildItem -Path $crParent -Directory -Filter 'catroot2.old*' -ErrorAction SilentlyContinue)
    $allOld = @()
    if ($sdOldDirs.Count -gt 0) { $allOld += $sdOldDirs }
    if ($crOldDirs.Count -gt 0) { $allOld += $crOldDirs }

    if ($allOld.Count -eq 0) {
        return 'No .old_* folders found'
    }

    $totalSizeMB = 0
    foreach ($d in $allOld) {
        $totalSizeMB += (Get-DirectorySizeMB -Path $d.FullName)
    }

    return ('{0} folder(s) found ({1} MB)' -f $allOld.Count, $totalSizeMB)
}

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

function Wait-ServiceState {
    param(
        [string]$Name,
        [ValidateSet('Stopped', 'Running')]
        [string]$DesiredStatus,
        [int]$TimeoutSeconds = 15
    )

    $svc = Get-Service -Name $Name -ErrorAction SilentlyContinue
    if ($null -eq $svc) { return $false }

    $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
    while ((Get-Date) -lt $deadline) {
        $svc.Refresh()
        if ($svc.Status.ToString() -eq $DesiredStatus) {
            return $true
        }
        Start-Sleep -Milliseconds 500
    }

    $svc.Refresh()
    return ($svc.Status.ToString() -eq $DesiredStatus)
}

function Stop-UpdateServices {
    param(
        [string[]]$ServiceNames,
        [switch]$Optional
    )

    $allStopped = $true
    foreach ($svcName in $ServiceNames) {
        $svc = Get-Service -Name $svcName -ErrorAction SilentlyContinue
        if ($null -eq $svc) { continue }

        if ($svc.Status -eq 'Stopped') {
            Write-Host "  • $svcName already stopped." -ForegroundColor DarkGray
            continue
        }

        Write-Host "  • Stopping $svcName..." -ForegroundColor Gray
        try {
            Stop-Service -Name $svcName -Force -ErrorAction Stop
        }
        catch {
            net stop $svcName > $null 2>&1
        }

        if (Wait-ServiceState -Name $svcName -DesiredStatus 'Stopped' -TimeoutSeconds 15) {
            Write-Host "    ✅ $svcName stopped." -ForegroundColor Green
        }
        else {
            if ($Optional) {
                Write-Host "    ⚠️ $svcName did not fully stop (continuing)." -ForegroundColor Yellow
            }
            else {
                Write-Host "    ⚠️ $svcName did not fully stop." -ForegroundColor Red
                $allStopped = $false
            }
        }
    }

    return $allStopped
}

function Start-UpdateServices {
    param([string[]]$ServiceNames)

    foreach ($svcName in $ServiceNames) {
        $svc = Get-Service -Name $svcName -ErrorAction SilentlyContinue
        if ($null -eq $svc) { continue }

        if ($svc.Status -eq 'Running') {
            Write-Host "  • $svcName already running." -ForegroundColor DarkGray
            continue
        }

        Write-Host "  • Starting $svcName..." -ForegroundColor Gray
        try {
            Start-Service -Name $svcName -ErrorAction Stop
        }
        catch {
            net start $svcName > $null 2>&1
        }

        if (Wait-ServiceState -Name $svcName -DesiredStatus 'Running' -TimeoutSeconds 15) {
            Write-Host "    ✅ $svcName running." -ForegroundColor Green
        }
        else {
            Write-Host "    ⚠️ $svcName did not report Running yet." -ForegroundColor Yellow
        }
    }
}

function Get-DirectorySizeMB {
    param([string]$Path)

    if (-not (Test-Path -LiteralPath $Path)) {
        return 0
    }

    $measure = Get-ChildItem -LiteralPath $Path -Recurse -Force -File -ErrorAction SilentlyContinue | Measure-Object -Property Length -Sum
    if ($null -eq $measure) {
        return 0
    }

    $sumProperty = $measure.PSObject.Properties['Sum']
    if ($null -eq $sumProperty -or $null -eq $sumProperty.Value) {
        return 0
    }

    $sum = [double]$sumProperty.Value
    return [math]::Round(($sum / 1MB), 1)
}

function Get-ComponentStoreCleanupInfo {
    $result = [ordered]@{
        BackupsAndDisabledFeatures = ''
        ReclaimablePackages = ''
        CleanupRecommended = ''
        RawOutput = ''
        Succeeded = $false
        ErrorMessage = ''
    }

    try {
        $rawOutput = (& dism.exe /Online /Cleanup-Image /AnalyzeComponentStore 2>&1 | Out-String)
        $result.RawOutput = $rawOutput.Trim()

        foreach ($line in ($rawOutput -split "`r?`n")) {
            if ($line -match 'Backups and Disabled Features\s*:\s*(.+)$') {
                $result.BackupsAndDisabledFeatures = $Matches[1].Trim()
                continue
            }
            if ($line -match 'Number of Reclaimable Packages\s*:\s*(.+)$') {
                $result.ReclaimablePackages = $Matches[1].Trim()
                continue
            }
            if ($line -match 'Component Store Cleanup Recommended\s*:\s*(.+)$') {
                $result.CleanupRecommended = $Matches[1].Trim()
            }
        }

        $result.Succeeded = -not [string]::IsNullOrWhiteSpace($result.BackupsAndDisabledFeatures)
    }
    catch {
        $result.ErrorMessage = $_.Exception.Message
    }

    return [pscustomobject]$result
}

function Show-ComponentStoreCleanupInfo {
    param(
        [object]$Info,
        [string]$Title
    )

    Write-Host "  $Title" -ForegroundColor Cyan
    Write-Host "  $('─' * 40)" -ForegroundColor DarkGray

    if (-not $Info -or -not $Info.Succeeded) {
        $message = if ($Info -and -not [string]::IsNullOrWhiteSpace($Info.ErrorMessage)) {
            $Info.ErrorMessage
        }
        else {
            'Could not read DISM component store status.'
        }
        Write-Host "     $message" -ForegroundColor Yellow
        return
    }

    Write-Host "     Reclaimable packages: $($Info.ReclaimablePackages)" -ForegroundColor Gray
    Write-Host "     Backups and Disabled Features: $($Info.BackupsAndDisabledFeatures)" -ForegroundColor Gray
    Write-Host "     Cleanup recommended: $($Info.CleanupRecommended)" -ForegroundColor Gray
}

function Set-IsolatedUpdateCleanupSlot {
    param([int]$Slot = 88)

    $volumeCachesRoot = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\VolumeCaches'
    $targetKey = 'HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\VolumeCaches\Update Cleanup'
    $valueName = Format-CleanMgrSlotValueName -Slot $Slot
    $snapshot = New-Object System.Collections.Generic.List[object]

    foreach ($subKey in @(Get-ChildItem -LiteralPath $volumeCachesRoot -ErrorAction Stop)) {
        $existing = Get-ItemProperty -LiteralPath $subKey.PSPath -Name $valueName -ErrorAction SilentlyContinue
        $hasValue = $null -ne $existing -and $null -ne $existing.$valueName
        $snapshot.Add([pscustomobject]@{
                Path = $subKey.Name
                HasValue = $hasValue
                Value = if ($hasValue) { [int]$existing.$valueName } else { $null }
            })

        [void](Invoke-RegCommand -Arguments @('delete', $subKey.Name, '/v', $valueName, '/f') -AllowNonZeroExit)
    }

    [void](Invoke-RegCommand -Arguments @('add', $targetKey, '/v', $valueName, '/t', 'REG_DWORD', '/d', '2', '/f'))

    return [pscustomobject]@{
        ValueName = $valueName
        Snapshot = $snapshot.ToArray()
    }
}

function Restore-IsolatedUpdateCleanupSlot {
    param([object]$State)

    if (-not $State) {
        return
    }

    foreach ($entry in @($State.Snapshot)) {
        [void](Invoke-RegCommand -Arguments @('delete', $entry.Path, '/v', $State.ValueName, '/f') -AllowNonZeroExit)
        if ($entry.HasValue) {
            [void](Invoke-RegCommand -Arguments @('add', $entry.Path, '/v', $State.ValueName, '/t', 'REG_DWORD', '/d', ([string][int]$entry.Value), '/f'))
        }
    }
}

function Ensure-SetForegroundWindowApi {
    if ('Win32.CleanMgrFocus' -as [type]) {
        return [Win32.CleanMgrFocus]
    }

    $signature = @'
[DllImport("user32.dll")]
[return: MarshalAs(UnmanagedType.Bool)]
public static extern bool SetForegroundWindow(IntPtr hWnd);

[DllImport("user32.dll")]
[return: MarshalAs(UnmanagedType.Bool)]
public static extern bool ShowWindow(IntPtr hWnd, int nCmdShow);
'@

    return Add-Type -MemberDefinition $signature -Name 'CleanMgrFocus' -Namespace 'Win32' -PassThru
}

function Invoke-CleanMgrWindowActivation {
    param(
        [int[]]$BaselineIds = @(),
        [string]$DebugLogPath = ''
    )

    $api = Ensure-SetForegroundWindowApi
    $activated = [System.Collections.Generic.HashSet[int]]::new()

    foreach ($proc in @(Get-Process -Name cleanmgr -ErrorAction SilentlyContinue)) {
        $procId = $proc.Id
        if (@($BaselineIds) -contains $procId) { continue }
        if ($activated.Contains($procId)) { continue }

        $hwnd = $proc.MainWindowHandle
        if ($hwnd -eq [IntPtr]::Zero) { continue }

        # SW_SHOW = 5, SW_RESTORE = 9
        $null = $api::ShowWindow($hwnd, 9)
        $null = $api::SetForegroundWindow($hwnd)
        [void]$activated.Add($procId)

        Write-WindowsUpdateCleanupDebugLog -Path $DebugLogPath -Message (
            "Activated cleanmgr window: PID={0} hWnd=0x{1:X} Title='{2}'" -f $procId, $hwnd.ToInt64(), $proc.MainWindowTitle
        )
    }

    return $activated.Count
}

function Invoke-IsolatedWindowsUpdateCleanup {
    param(
        [int]$Slot = 88,
        [string]$DebugLogPath = ''
    )

    $cleanMgrPath = Join-Path $env:SystemRoot 'System32\cleanmgr.exe'
    if (-not (Test-Path -LiteralPath $cleanMgrPath)) {
        throw "cleanmgr.exe was not found at $cleanMgrPath"
    }

    $slotState = $null
    try {
        Write-WindowsUpdateCleanupDebugLog -Path $DebugLogPath -Message "Starting isolated cleanmgr run. Path=$cleanMgrPath Slot=$Slot WT_SESSION=$($env:WT_SESSION)"
        Write-StructuredDebugBlock -Path $DebugLogPath -Title 'StateFlags before isolate' -Rows (Get-VolumeCachesSlotSnapshot -Slot $Slot)
        $baselineCleanMgrRows = @(Get-CleanMgrProcessSnapshot)
        $baselineCleanMgrIds = @($baselineCleanMgrRows | ForEach-Object { [int]$_.Id })
        Write-StructuredDebugBlock -Path $DebugLogPath -Title 'cleanmgr processes before start' -Rows $baselineCleanMgrRows

        $slotState = Set-IsolatedUpdateCleanupSlot -Slot $Slot
        Write-StructuredDebugBlock -Path $DebugLogPath -Title 'StateFlags after isolate' -Rows (Get-VolumeCachesSlotSnapshot -Slot $Slot)

        # Always launch cleanmgr directly — no external cmd window
        Write-WindowsUpdateCleanupDebugLog -Path $DebugLogPath -Message "Launching cleanmgr directly."
        $process = Start-Process -FilePath $cleanMgrPath -ArgumentList "/sagerun:$Slot" -PassThru
        Write-WindowsUpdateCleanupDebugLog -Path $DebugLogPath -Message "Started cleanmgr PID=$($process.Id)"

        $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
        $nextHeartbeatSeconds = 5
        $seenNewCleanMgrIds = [System.Collections.Generic.HashSet[int]]::new()
        $activationAttempted = $false

        while (-not $process.HasExited) {
            Start-Sleep -Seconds 1
            try { $process.Refresh() } catch {}

            foreach ($newRow in @(Get-NewCleanMgrProcesses -BaselineIds $baselineCleanMgrIds)) {
                $newId = [int]$newRow.Id
                if ($seenNewCleanMgrIds.Add($newId)) {
                    Write-WindowsUpdateCleanupDebugLog -Path $DebugLogPath -Message ("Observed cleanmgr child PID={0} Title='{1}' Responding={2}" -f $newRow.Id, $newRow.MainWindowTitle, $newRow.Responding)
                }
            }

            # After 2 seconds, try to auto-activate/focus any cleanmgr windows
            # so the GUI starts processing immediately instead of hanging
            if (-not $activationAttempted -and $stopwatch.Elapsed.TotalSeconds -ge 2) {
                $activated = Invoke-CleanMgrWindowActivation -BaselineIds $baselineCleanMgrIds -DebugLogPath $DebugLogPath
                if ($activated -gt 0) {
                    $activationAttempted = $true
                }
            }

            if ($stopwatch.Elapsed.TotalSeconds -ge $nextHeartbeatSeconds) {
                Write-WindowsUpdateCleanupDebugLog -Path $DebugLogPath -Message ("Heartbeat: PID={0} alive after {1:N0}s" -f $process.Id, $stopwatch.Elapsed.TotalSeconds)
                Write-StructuredDebugBlock -Path $DebugLogPath -Title 'cleanmgr processes heartbeat' -Rows (Get-CleanMgrProcessSnapshot)

                # Retry activation on each heartbeat in case the window appeared late
                if (-not $activationAttempted) {
                    $activated = Invoke-CleanMgrWindowActivation -BaselineIds $baselineCleanMgrIds -DebugLogPath $DebugLogPath
                    if ($activated -gt 0) {
                        $activationAttempted = $true
                    }
                }

                $nextHeartbeatSeconds += 5
            }
        }

        Write-WindowsUpdateCleanupDebugLog -Path $DebugLogPath -Message "Primary cleanmgr process exited. PID=$($process.Id) ExitCode=$($process.ExitCode)"
        Write-StructuredDebugBlock -Path $DebugLogPath -Title 'cleanmgr processes after exit' -Rows (Get-CleanMgrProcessSnapshot)

        # ── Wait for any surviving cleanmgr children ──
        # cleanmgr often detaches: the parent exits immediately but a child
        # process does the real cleanup work.  We must keep waiting here.
        $tailMaxSeconds = 600          # 10 min hard cap
        $tailStopwatch = [System.Diagnostics.Stopwatch]::StartNew()
        $tailNextHeartbeat = 5
        $loggedTailStart = $false
        $tailActivationDone = $false

        while ($tailStopwatch.Elapsed.TotalSeconds -lt $tailMaxSeconds) {
            $liveCleanMgr = @(Get-CleanMgrProcessSnapshot | Where-Object {
                $baseline = @($baselineCleanMgrIds)
                $baseline -notcontains [int]$_.Id
            })

            if ($liveCleanMgr.Count -eq 0) {
                break
            }

            if (-not $loggedTailStart) {
                Write-WindowsUpdateCleanupDebugLog -Path $DebugLogPath -Message (
                    "Launcher exited but {0} cleanmgr child(ren) still running. Entering tail-wait." -f $liveCleanMgr.Count
                )
                $loggedTailStart = $true
            }

            # Activate child windows too (the detached child is the one with the GUI)
            if (-not $tailActivationDone -and $tailStopwatch.Elapsed.TotalSeconds -ge 1) {
                $activated = Invoke-CleanMgrWindowActivation -BaselineIds $baselineCleanMgrIds -DebugLogPath $DebugLogPath
                if ($activated -gt 0) {
                    $tailActivationDone = $true
                }
            }

            Start-Sleep -Seconds 1

            if ($tailStopwatch.Elapsed.TotalSeconds -ge $tailNextHeartbeat) {
                Write-WindowsUpdateCleanupDebugLog -Path $DebugLogPath -Message (
                    "Tail-wait heartbeat: {0:N0}s elapsed, {1} cleanmgr process(es) alive" -f $tailStopwatch.Elapsed.TotalSeconds, $liveCleanMgr.Count
                )
                Write-StructuredDebugBlock -Path $DebugLogPath -Title 'cleanmgr tail-wait heartbeat' -Rows $liveCleanMgr

                # Retry activation if not done yet
                if (-not $tailActivationDone) {
                    $activated = Invoke-CleanMgrWindowActivation -BaselineIds $baselineCleanMgrIds -DebugLogPath $DebugLogPath
                    if ($activated -gt 0) {
                        $tailActivationDone = $true
                    }
                }

                $tailNextHeartbeat += 10
            }
        }

        if ($loggedTailStart) {
            Write-WindowsUpdateCleanupDebugLog -Path $DebugLogPath -Message (
                "Tail-wait finished after {0:N0}s" -f $tailStopwatch.Elapsed.TotalSeconds
            )
            Write-StructuredDebugBlock -Path $DebugLogPath -Title 'cleanmgr processes after tail-wait' -Rows (Get-CleanMgrProcessSnapshot)
        }

        return [pscustomobject]@{
            ExitCode = $process.ExitCode
            Slot = $Slot
            DebugLogPath = $DebugLogPath
        }
    }
    finally {
        Restore-IsolatedUpdateCleanupSlot -State $slotState
        Write-StructuredDebugBlock -Path $DebugLogPath -Title 'StateFlags after restore' -Rows (Get-VolumeCachesSlotSnapshot -Slot $Slot)
    }
}

function Ensure-MoveFileExApi {
    if ('Win32.Kernel32' -as [type]) {
        return [Win32.Kernel32]
    }

    $signature = @'
[DllImport("kernel32.dll", SetLastError=true, CharSet=CharSet.Unicode)]
public static extern bool MoveFileEx(string lpExistingFileName, string lpNewFileName, int dwFlags);
'@

    return Add-Type -MemberDefinition $signature -Name 'Kernel32' -Namespace 'Win32' -PassThru
}

function Schedule-PathsForDeletionOnReboot {
    param([string[]]$Paths)

    $existingPaths = @($Paths | Where-Object { $_ -and (Test-Path -LiteralPath $_) })
    if ($existingPaths.Count -eq 0) {
        return [pscustomobject]@{
            ScheduledFiles = 0
            ScheduledDirectories = 0
            UsedRegistryFallback = $false
            Failed = @()
        }
    }

    $files = @($existingPaths | Where-Object { Test-Path -LiteralPath $_ -PathType Leaf })
    $directories = @($existingPaths | Where-Object { Test-Path -LiteralPath $_ -PathType Container } | Sort-Object Length -Descending)
    $api = Ensure-MoveFileExApi

    $scheduledFiles = 0
    $scheduledDirectories = 0
    $failed = [System.Collections.ArrayList]::new()

    foreach ($filePath in $files) {
        if ($api::MoveFileEx($filePath, $null, 4)) {
            $scheduledFiles++
        }
        else {
            [void]$failed.Add($filePath)
        }
    }

    foreach ($dirPath in $directories) {
        if ($api::MoveFileEx($dirPath, $null, 4)) {
            $scheduledDirectories++
        }
        else {
            [void]$failed.Add($dirPath)
        }
    }

    if ($failed.Count -eq 0) {
        return [pscustomobject]@{
            ScheduledFiles = $scheduledFiles
            ScheduledDirectories = $scheduledDirectories
            UsedRegistryFallback = $false
            Failed = @()
        }
    }

    $regPath = 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager'
    $regName = 'PendingFileRenameOperations'
    $existingEntries = @()

    try {
        $prop = Get-ItemProperty -Path $regPath -Name $regName -ErrorAction Stop
        $existingEntries = [string[]]$prop.$regName
    }
    catch {
    }

    $newEntries = [System.Collections.ArrayList]::new()
    foreach ($entry in $existingEntries) {
        [void]$newEntries.Add($entry)
    }

    foreach ($failedPath in $failed) {
        [void]$newEntries.Add("\??\$failedPath")
        [void]$newEntries.Add('')
    }

    New-ItemProperty -Path $regPath -Name $regName -PropertyType MultiString -Value ([string[]]$newEntries) -Force | Out-Null

    return [pscustomobject]@{
        ScheduledFiles = $scheduledFiles + @($failed | Where-Object { Test-Path -LiteralPath $_ -PathType Leaf }).Count
        ScheduledDirectories = $scheduledDirectories + @($failed | Where-Object { Test-Path -LiteralPath $_ -PathType Container }).Count
        UsedRegistryFallback = $true
        Failed = @()
    }
}

function Remove-LiveSoftwareDistributionDownload {
    $downloadPath = 'C:\Windows\SoftwareDistribution\Download'

    Write-Host "`n  🔵 LIVE SOFTWAREDISTRIBUTION CLEANUP" -ForegroundColor Cyan
    Write-Host "  $('─' * 40)" -ForegroundColor DarkGray
    Write-Host "  ⚠️  This will:" -ForegroundColor Yellow
    Write-Host "      • Stop update services temporarily" -ForegroundColor Gray
    Write-Host "      • Clean the live SoftwareDistribution\\Download cache" -ForegroundColor Gray
    Write-Host "      • Keep DataStore / update history intact" -ForegroundColor Gray
    Write-Host "      • Restart services" -ForegroundColor Gray
    Write-Host ""
    Write-Host "  💡 Use this after updates to reclaim disk space." -ForegroundColor Cyan
    Write-Host "     For hide/troubleshooting workflow, keep using [5] Reset Update Cache." -ForegroundColor DarkGray
    Write-Host ""

    if (-not (Test-Path -LiteralPath $downloadPath)) {
        Write-Host "  ℹ️ $downloadPath not found." -ForegroundColor DarkGray
        return
    }

    $beforeSizeMB = Get-DirectorySizeMB -Path $downloadPath
    Write-Host "  Current Download cache size: $beforeSizeMB MB" -ForegroundColor Gray
    Write-Host ""

    $confirm = Read-Host "  Proceed? (Y/N)"
    if ($confirm -notmatch '^[Yy]') {
        Write-Host "  Cancelled." -ForegroundColor DarkGray
        return
    }

    $children = @(Get-ChildItem -LiteralPath $downloadPath -Force -ErrorAction SilentlyContinue)
    if ($children.Count -eq 0) {
        Write-Host "`n  Download cache is already empty." -ForegroundColor Green
        return
    }

    $optionalStopServices = @('UsoSvc', 'DoSvc')
    $coreServices = @('wuauserv', 'cryptSvc', 'bits', 'msiserver')

    Write-Host "`n  Stopping services..." -ForegroundColor Yellow
    $null = Stop-UpdateServices -ServiceNames $optionalStopServices -Optional
    $coreStopped = Stop-UpdateServices -ServiceNames $coreServices

    Write-Host "`n  Deleting live download cache contents..." -ForegroundColor Yellow
    $deletedCount = 0
    foreach ($child in $children) {
        try {
            if ($child.PSIsContainer) {
                cmd /c "rd /s /q `"$($child.FullName)`" 2>nul"
            }
            else {
                cmd /c "del /f /q `"$($child.FullName)`" 2>nul"
            }

            if (Test-Path -LiteralPath $child.FullName) {
                Remove-Item -LiteralPath $child.FullName -Recurse -Force -ErrorAction Stop
            }

            if (-not (Test-Path -LiteralPath $child.FullName)) {
                $deletedCount++
            }
        }
        catch {
        }
    }

    $remaining = @(Get-ChildItem -LiteralPath $downloadPath -Force -ErrorAction SilentlyContinue)
    $scheduled = $null
    if ($remaining.Count -gt 0) {
        Write-Host "  ⚠️ $($remaining.Count) item(s) remained locked. Scheduling them for next reboot..." -ForegroundColor Yellow
        $scheduled = Schedule-PathsForDeletionOnReboot -Paths $remaining.FullName
    }

    Write-Host "`n  Starting services..." -ForegroundColor Yellow
    Start-UpdateServices -ServiceNames $coreServices

    $afterSizeMB = Get-DirectorySizeMB -Path $downloadPath
    $freedMB = [math]::Round([math]::Max(0, $beforeSizeMB - $afterSizeMB), 1)

    Write-Host ""
    if ($coreStopped) {
        Write-Host "  ✅ Live SoftwareDistribution cleanup finished." -ForegroundColor Green
    }
    else {
        Write-Host "  ⚠️ Live cleanup finished with service-stop warnings." -ForegroundColor Yellow
    }
    Write-Host "     Before: $beforeSizeMB MB" -ForegroundColor DarkGray
    Write-Host "     After:  $afterSizeMB MB" -ForegroundColor DarkGray
    Write-Host "     Freed:  $freedMB MB" -ForegroundColor DarkGray

    if ($deletedCount -gt 0) {
        Write-Host "  ✅ Deleted $deletedCount item(s) immediately." -ForegroundColor Green
    }

    if ($scheduled) {
        $scheduledTotal = $scheduled.ScheduledFiles + $scheduled.ScheduledDirectories
        if ($scheduledTotal -gt 0) {
            Write-Host "  💡 Scheduled $scheduledTotal leftover item(s) for deletion on next reboot." -ForegroundColor Cyan
            if ($scheduled.UsedRegistryFallback) {
                Write-Host "     Registry fallback was needed for some locked paths." -ForegroundColor DarkGray
            }
        }
    }

    Write-Host "  ℹ️ Windows may recreate some files later after scans or new downloads." -ForegroundColor DarkGray
}

function Invoke-WindowsUpdateCleanup {
    $slot = 88
    $debugLogPath = New-WindowsUpdateCleanupDebugLogPath

    Write-Host "`n  🔵 WINDOWS UPDATE CLEANUP (DISK CLEANUP UTILITY)" -ForegroundColor Cyan
    Write-Host "  $('─' * 54)" -ForegroundColor DarkGray
    Write-Host "  ⚠️  This will:" -ForegroundColor Yellow
    Write-Host "      • Run Disk Cleanup Utility: cleanmgr /sagerun:$slot" -ForegroundColor Gray
    Write-Host "      • Clean superseded WinSxS / component store update leftovers" -ForegroundColor Gray
    Write-Host "      • May also scavenge WinSxS\\Temp\\PendingDeletes leftovers" -ForegroundColor Gray
    Write-Host "      • Leave live SoftwareDistribution alone" -ForegroundColor Gray
    Write-Host ""
    Write-Host "  💡 Best used after Windows Updates are installed and the PC has rebooted." -ForegroundColor Cyan
    Write-Host "     Use this for extra post-update disk cleanup, not for hide/reset troubleshooting." -ForegroundColor DarkGray
    Write-Host ""

    $beforeInfo = Get-ComponentStoreCleanupInfo
    Show-ComponentStoreCleanupInfo -Info $beforeInfo -Title 'Current component store status'
    Write-Host ""
    if (-not [string]::IsNullOrWhiteSpace($debugLogPath)) {
        Write-Host "  Debug log: $debugLogPath" -ForegroundColor DarkGray
        Write-Host ""
    }

    $confirm = Read-Host "  Proceed? (Y/N)"
    if ($confirm -notmatch '^[Yy]') {
        Write-Host "  Cancelled." -ForegroundColor DarkGray
        return
    }

    Write-Host "`n  Running cleanmgr /sagerun:$slot ..." -ForegroundColor Yellow
    try {
        $runResult = Invoke-IsolatedWindowsUpdateCleanup -Slot $slot -DebugLogPath $debugLogPath
    }
    catch {
        Write-Host "  Failed to run Disk Cleanup Utility: $($_.Exception.Message)" -ForegroundColor Red
        if (-not [string]::IsNullOrWhiteSpace($debugLogPath)) {
            Write-Host "  Debug log: $debugLogPath" -ForegroundColor DarkGray
        }
        return
    }

    $afterInfo = Get-ComponentStoreCleanupInfo

    Write-Host ""
    if ($runResult.ExitCode -eq 0) {
        Write-Host "  ✅ Windows Update Cleanup finished." -ForegroundColor Green
    }
    else {
        Write-Host "  ⚠️ Windows Update Cleanup finished with exit code $($runResult.ExitCode)." -ForegroundColor Yellow
    }
    Write-Host "     Command: cleanmgr /sagerun:$slot" -ForegroundColor DarkGray
    if (-not [string]::IsNullOrWhiteSpace($runResult.DebugLogPath)) {
        Write-Host "     Debug log: $($runResult.DebugLogPath)" -ForegroundColor DarkGray
    }
    Write-Host ""

    Show-ComponentStoreCleanupInfo -Info $beforeInfo -Title 'Before cleanup'
    Write-Host ""
    Show-ComponentStoreCleanupInfo -Info $afterInfo -Title 'After cleanup'
}

function Move-UpdateCacheFolder {
    param(
        [string]$Path,
        [string]$Timestamp
    )

    if (-not (Test-Path -LiteralPath $Path)) {
        return [pscustomobject]@{
            Path = $Path
            BackupPath = ''
            Success = $true
            Skipped = $true
            Message = 'Path not found; nothing to move.'
        }
    }

    $parentPath = Split-Path -Path $Path -Parent
    $leafName = Split-Path -Path $Path -Leaf
    $backupPath = Join-Path $parentPath ("{0}.old_{1}" -f $leafName, $Timestamp)

    try {
        Move-Item -LiteralPath $Path -Destination $backupPath -Force -ErrorAction Stop
    }
    catch {
        return [pscustomobject]@{
            Path = $Path
            BackupPath = $backupPath
            Success = $false
            Skipped = $false
            Message = $_.Exception.Message
        }
    }

    $moved = (-not (Test-Path -LiteralPath $Path)) -and (Test-Path -LiteralPath $backupPath)
    return [pscustomobject]@{
        Path = $Path
        BackupPath = $backupPath
        Success = $moved
        Skipped = $false
        Message = if ($moved) { 'Moved and verified.' } else { 'Move command returned without a verified folder transition.' }
    }
}

# ─────────────────────────────────────────────
# 🔵 ACTION: Reset Windows Update Cache
# ─────────────────────────────────────────────
function Reset-UpdateCache {
    Write-Host "`n  🔵 RESETTING WINDOWS UPDATE CACHE" -ForegroundColor Cyan
    Write-Host "  $('─' * 40)" -ForegroundColor DarkGray
    
    Write-Host "  ⚠️  This will:" -ForegroundColor Yellow
    Write-Host "      • Stop core update services and try to quiet update orchestrators" -ForegroundColor Gray
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
    
    $optionalStopServices = @('UsoSvc', 'DoSvc')
    $coreServices = @('wuauserv', 'cryptSvc', 'bits', 'msiserver')
    
    Write-Host "`n  Stopping services..." -ForegroundColor Yellow
    $null = Stop-UpdateServices -ServiceNames $optionalStopServices -Optional
    $coreStopped = Stop-UpdateServices -ServiceNames $coreServices

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
    $sdMove = Move-UpdateCacheFolder -Path $sdPath -Timestamp $ts
    if ($sdMove.Skipped) {
        Write-Host "  ℹ️ SoftwareDistribution not found." -ForegroundColor DarkGray
    }
    elseif ($sdMove.Success) {
        Write-Host "  ✅ SoftwareDistribution moved to $($sdMove.BackupPath)." -ForegroundColor Green
    }
    else {
        Write-Host "  ⚠️ Could not move SoftwareDistribution: $($sdMove.Message)" -ForegroundColor Red
    }
    
    Write-Host "  Renaming catroot2..." -ForegroundColor Yellow
    $crMove = Move-UpdateCacheFolder -Path $crPath -Timestamp $ts
    if ($crMove.Skipped) {
        Write-Host "  ℹ️ catroot2 not found." -ForegroundColor DarkGray
    }
    elseif ($crMove.Success) {
        Write-Host "  ✅ catroot2 moved to $($crMove.BackupPath)." -ForegroundColor Green
    }
    else {
        Write-Host "  ⚠️ Could not move catroot2: $($crMove.Message)" -ForegroundColor Red
    }
    
    Write-Host "`n  Starting services..." -ForegroundColor Yellow
    Start-UpdateServices -ServiceNames $coreServices

    $resetSucceeded = $coreStopped -and $sdMove.Success -and $crMove.Success
    Write-Host ""
    if ($resetSucceeded) {
        Write-Host "  ✅ Windows Update cache reset complete!" -ForegroundColor Green
        Write-Host "     Fresh cache folders may be recreated immediately after services restart." -ForegroundColor DarkGray
    }
    else {
        Write-Host "  ⚠️ Windows Update cache reset was partial." -ForegroundColor Yellow
        if (-not $coreStopped) {
            Write-Host "     One or more core services did not stop cleanly before the move step." -ForegroundColor DarkGray
        }
        if (-not $sdMove.Success) {
            Write-Host "     SoftwareDistribution was not fully reset." -ForegroundColor DarkGray
        }
        if (-not $crMove.Success) {
            Write-Host "     catroot2 was not fully reset." -ForegroundColor DarkGray
        }
        Write-Host "     Reboot and run the reset again if Windows Update still behaves inconsistently." -ForegroundColor DarkGray
    }
    Write-Host ""
    Write-Host "  ╔════════════════════════════════════════════════════════════╗" -ForegroundColor Cyan
    Write-Host "  ║  💡  NEXT STEPS:                                         ║" -ForegroundColor Cyan
    Write-Host "  ║                                                          ║" -ForegroundColor Cyan
    Write-Host "  ║   1. REBOOT your PC now                                  ║" -ForegroundColor Cyan
    Write-Host "  ║   2. After reboot, open this tool again                  ║" -ForegroundColor Cyan
    Write-Host "  ║   3. Use [2] Hide Updates on the fresh update list        ║" -ForegroundColor Cyan
    Write-Host "  ║                                                          ║" -ForegroundColor Cyan
        Write-Host "  ║  The .old backup folders will be auto-cleaned on the     ║" -ForegroundColor Cyan
        Write-Host "  ║  next reset, or use [7] to clean them manually.          ║" -ForegroundColor Cyan
        Write-Host "  ╚════════════════════════════════════════════════════════════╝" -ForegroundColor Cyan
}

# ─────────────────────────────────────────────
# 🔵 ACTION: Block / Unblock Windows 11 Upgrade
# ─────────────────────────────────────────────
function Get-Win10TargetReleaseVersion {
    return '22H2'
}

function Set-RegistryPolicyValue {
    param(
        [string]$Path,
        [string]$Name,
        [object]$Value,
        [ValidateSet('String', 'DWord')]
        [string]$PropertyType
    )

    Remove-ItemProperty -Path $Path -Name $Name -ErrorAction SilentlyContinue
    New-ItemProperty -Path $Path -Name $Name -PropertyType $PropertyType -Value $Value -Force | Out-Null
}

function Get-Win11BlockState {
    $policyPath = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate'
    $expectedTarget = Get-Win10TargetReleaseVersion
    $state = [ordered]@{
        PolicyPath = $policyPath
        ExpectedTargetReleaseVersionInfo = $expectedTarget
        TargetReleaseVersion = ''
        TargetReleaseVersionInfo = ''
        ProductVersion = ''
        IsBlocked = $false
        StatusLabel = 'Not configured'
    }

    if (-not (Test-Path $policyPath)) {
        return [pscustomobject]$state
    }

    $props = Get-ItemProperty -Path $policyPath -ErrorAction SilentlyContinue
    if ($null -eq $props) {
        return [pscustomobject]$state
    }

    $trvRaw = $props.PSObject.Properties['TargetReleaseVersion']
    $trviRaw = $props.PSObject.Properties['TargetReleaseVersionInfo']
    $pvRaw  = $props.PSObject.Properties['ProductVersion']

    if ($null -ne $trvRaw) {
        $state.TargetReleaseVersion = ([string]$trvRaw.Value).Trim()
    }
    if ($null -ne $trviRaw) {
        $state.TargetReleaseVersionInfo = ([string]$trviRaw.Value).Trim()
    }
    if ($null -ne $pvRaw) {
        $state.ProductVersion = ([string]$pvRaw.Value).Trim()
    }

    $trvMatch = $state.TargetReleaseVersion -eq '1'
    $trviMatch = $state.TargetReleaseVersionInfo -ieq $expectedTarget
    $pvMatch  = $state.ProductVersion -ieq 'Windows 10'

    if ($trvMatch -and $trviMatch -and $pvMatch) {
        $state.IsBlocked = $true
        $state.StatusLabel = 'Policy active'
    }
    elseif ($state.TargetReleaseVersion -or $state.TargetReleaseVersionInfo -or $state.ProductVersion) {
        $state.StatusLabel = 'Policy mismatch'
    }

    return [pscustomobject]$state
}

function Get-Win11BlockStatus {
    return (Get-Win11BlockState).IsBlocked
}

function Set-Win11Block {
    param([bool]$Block)

    $policyPath = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate'

    if ($Block) {
        $targetRelease = Get-Win10TargetReleaseVersion

        Write-Host "`n  🔵 BLOCKING WINDOWS 11 UPGRADE" -ForegroundColor Cyan
        Write-Host "  $('─' * 40)" -ForegroundColor DarkGray
        Write-Host "  Setting Windows Update policy to stay on Windows 10 ($targetRelease)..." -ForegroundColor Gray

        if (-not (Test-Path $policyPath)) {
            New-Item -Path $policyPath -Force | Out-Null
        }
        Set-RegistryPolicyValue -Path $policyPath -Name 'TargetReleaseVersion' -Value 1 -PropertyType DWord
        Set-RegistryPolicyValue -Path $policyPath -Name 'TargetReleaseVersionInfo' -Value $targetRelease -PropertyType String
        Set-RegistryPolicyValue -Path $policyPath -Name 'ProductVersion' -Value 'Windows 10' -PropertyType String

        $state = Get-Win11BlockState

        Write-Host ""
        if (-not $state.IsBlocked) {
            Write-Host "  ❌ Policy write/readback verification failed." -ForegroundColor Red
            Write-Host "      TargetReleaseVersion     = $($state.TargetReleaseVersion)" -ForegroundColor DarkGray
            Write-Host "      TargetReleaseVersionInfo = $($state.TargetReleaseVersionInfo)" -ForegroundColor DarkGray
            Write-Host "      ProductVersion           = $($state.ProductVersion)" -ForegroundColor DarkGray
            Write-Host "      Expected target          = $($state.ExpectedTargetReleaseVersionInfo)" -ForegroundColor DarkGray
            return
        }

        Write-Host "  ✅ Windows 11 upgrade policy configured." -ForegroundColor Green
        Write-Host "      TargetReleaseVersion     = $($state.TargetReleaseVersion)" -ForegroundColor DarkGray
        Write-Host "      TargetReleaseVersionInfo = $($state.TargetReleaseVersionInfo)" -ForegroundColor DarkGray
        Write-Host "      ProductVersion           = $($state.ProductVersion)" -ForegroundColor DarkGray
        Write-Host ""
        Write-Host "  Refreshing Group Policy..." -ForegroundColor Gray
        gpupdate /force 2>&1 | Out-Null
        Write-Host "  ✅ Group Policy refreshed." -ForegroundColor Green
        Write-Host ""
        Write-Host "  💡 This blocks the Windows 11 feature upgrade offer by policy." -ForegroundColor Cyan
        Write-Host "     If Windows Update already cached the offer, reboot and check again." -ForegroundColor DarkGray
        Write-Host "     Eligibility/info banners may still appear even when the feature upgrade is blocked." -ForegroundColor DarkGray
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

        $state = Get-Win11BlockState

        Write-Host ""
        if ($state.IsBlocked) {
            Write-Host "  ❌ Policy removal verification failed." -ForegroundColor Red
            return
        }

        Write-Host "  ✅ Windows 11 block policy removed." -ForegroundColor Green
        Write-Host ""
        Write-Host "  Refreshing Group Policy..." -ForegroundColor Gray
        gpupdate /force 2>&1 | Out-Null
        Write-Host "  ✅ Group Policy refreshed." -ForegroundColor Green
        Write-Host ""
        Write-Host "  ⚠️  Windows Update may now offer Windows 11 if your hardware is compatible." -ForegroundColor Yellow
    }
}

function Toggle-Win11Block {
    $state = Get-Win11BlockState

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

    if ($state.IsBlocked) {
        Write-Host ""
        Write-Host "  Current status: " -ForegroundColor White -NoNewline
        Write-Host "POLICY ACTIVE ✅" -ForegroundColor Green
        Write-Host "  Windows 11 feature upgrade is currently blocked via policy." -ForegroundColor DarkGray
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
        if ($state.StatusLabel -eq 'Policy mismatch') {
            Write-Host "POLICY MISMATCH ⚠️" -ForegroundColor Yellow
            Write-Host "  The registry contains partial/invalid Win11 block values." -ForegroundColor DarkGray
            Write-Host "      TargetReleaseVersion     = $($state.TargetReleaseVersion)" -ForegroundColor DarkGray
            Write-Host "      TargetReleaseVersionInfo = $($state.TargetReleaseVersionInfo)" -ForegroundColor DarkGray
            Write-Host "      ProductVersion           = $($state.ProductVersion)" -ForegroundColor DarkGray
            Write-Host "      Expected target          = $($state.ExpectedTargetReleaseVersionInfo)" -ForegroundColor DarkGray
        }
        else {
            Write-Host "NOT CONFIGURED ⚠️" -ForegroundColor Yellow
            Write-Host "  Windows Update may offer Windows 11 if your hardware is compatible." -ForegroundColor DarkGray
        }
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
$directActionCompleted = $false
switch ($Action) {
    'ReadMainMenuChoice' {
        $key = $Host.UI.RawUI.ReadKey('NoEcho,IncludeKeyDown')
        if ($key.VirtualKeyCode -eq 27) {
            Write-Host 'ESC'
            Write-Output 'ESC'
            return
        }

        $char = [string]$key.Character
        if (-not [string]::IsNullOrWhiteSpace($char)) {
            Write-Host $char
            Write-Output $char
        }
        else {
            Write-Host ''
            Write-Output ''
        }
        return
    }
    'LiveCleanupStatus' {
        Write-Output (Get-LiveDownloadCacheStatusLine)
        return
    }
    'LiveCleanup' {
        Remove-LiveSoftwareDistributionDownload
        $directActionCompleted = $true
    }
    'WindowsUpdateCleanup' {
        Invoke-WindowsUpdateCleanup
        $directActionCompleted = $true
    }
}

if ($directActionCompleted) {
    if (-not $SilentCaller) {
        Wait-ReturnToMenu
        Write-Host ""
    }
    return
}

$menuLoop = $true
while ($menuLoop) {
    Clear-Host
    $win11State = Get-Win11BlockState
    $win11Status = switch ($win11State.StatusLabel) {
        'Policy active' { '🟢 Policy active' }
        'Policy mismatch' { '🟡 Policy mismatch' }
        default { '🔴 Not configured' }
    }
    $win11StatusColor = switch ($win11State.StatusLabel) {
        'Policy active' { 'Green' }
        'Policy mismatch' { 'Yellow' }
        default { 'Yellow' }
    }

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
    Write-Host "         Reset SoftwareDistribution + catroot2" -ForegroundColor DarkGray
    $oldFoldersStatus = Get-StaleOldFoldersStatusLine
    Write-Host "  [6]  Clean Stale Backup Folders" -ForegroundColor Magenta
    Write-Host "         $oldFoldersStatus" -ForegroundColor DarkGray
    Write-Host "  $('─' * 42)" -ForegroundColor DarkGray
    Write-Host "  [7]  Block Windows 11 Upgrade  " -ForegroundColor Cyan -NoNewline
    Write-Host "[$win11Status]" -ForegroundColor $win11StatusColor
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
