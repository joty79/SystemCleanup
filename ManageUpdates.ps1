# ManageUpdates.ps1 — Windows Update Manager + Update Cleanup Actions
# Called by SystemCleanup.cmd main menu and submenu actions
# Zero external dependencies — uses built-in Microsoft.Update.Session COM and Windows cleanup tools

param(
    [switch]$SilentCaller,
    [ValidateSet('Menu', 'LiveCleanup', 'WindowsUpdateCleanup', 'LiveCleanupStatus', 'DeliveryOptimizationCleanup', 'DeliveryOptimizationStatus', 'ToolSelfUpdate', 'ToolSelfUpdateStatus', 'ReadMainMenuChoice', 'DismFailureSummary', 'DismFailureSummaryFull', 'RepairSourceStatus', 'RepairRestoreHealth')]
    [string]$Action = 'Menu',
    [AllowEmptyString()]
    [string]$RepairIsoPath = ''
)

$script:SkipReturnToMenuToken = '__SYSTEMCLEANUP_SKIP_RETURN_TO_MENU__'
$script:RelaunchAndExitToken = '__SYSTEMCLEANUP_RELAUNCH_AND_EXIT__'
$script:AppName = 'SystemCleanup'
$script:AppVersion = '1.0.5'
$script:AppMetadataPath = Join-Path $PSScriptRoot 'app-metadata.json'
$script:AppUpdateStatusCachePath = Join-Path $PSScriptRoot 'state\app-update-status.json'
$script:RepairSourceStatePath = Join-Path $PSScriptRoot 'state\repair-source.json'
$script:E = [char]27
$script:Ui = @{
    H1      = "$($script:E)[38;2;90;180;240m"
    Dim     = "$($script:E)[38;2;100;110;120m"
    White   = "$($script:E)[38;2;220;225;230m"
    OK      = "$($script:E)[38;2;46;204;113m"
    Warn    = "$($script:E)[38;2;241;196;15m"
    Fail    = "$($script:E)[38;2;231;76;60m"
    Bold    = "$($script:E)[1m"
    Reset   = "$($script:E)[0m"
}

# 🔸 Force UTF-8 Encoding
$OutputEncoding = [Console]::OutputEncoding = [System.Text.Encoding]::UTF8

function Initialize-SystemCleanupMetadata {
    if (-not (Test-Path -LiteralPath $script:AppMetadataPath -PathType Leaf)) {
        return
    }

    try {
        $metadata = Get-Content -LiteralPath $script:AppMetadataPath -Raw -ErrorAction Stop | ConvertFrom-Json
        if ($metadata.PSObject.Properties['app_name'] -and -not [string]::IsNullOrWhiteSpace([string]$metadata.app_name)) {
            $script:AppName = [string]$metadata.app_name
        }
        if ($metadata.PSObject.Properties['version'] -and -not [string]::IsNullOrWhiteSpace([string]$metadata.version)) {
            $script:AppVersion = [string]$metadata.version
        }
    }
    catch {
    }
}

function Get-SystemCleanupUpdateLabel {
    if (-not (Test-Path -LiteralPath $script:AppUpdateStatusCachePath -PathType Leaf)) {
        return [pscustomobject]@{ Label = 'Status unavailable'; Color = $script:Ui.Dim }
    }

    try {
        $cache = Get-Content -LiteralPath $script:AppUpdateStatusCachePath -Raw -ErrorAction Stop | ConvertFrom-Json
        $branch = if ($cache.PSObject.Properties['Branch'] -and -not [string]::IsNullOrWhiteSpace([string]$cache.Branch)) { "GitHub $($cache.Branch)" } else { 'GitHub' }
        switch ([string]$cache.Status) {
            'UpToDate' { return [pscustomobject]@{ Label = "Up to date with $branch"; Color = $script:Ui.OK } }
            'UpdateAvailable' { return [pscustomobject]@{ Label = 'Update available'; Color = $script:Ui.Warn } }
            'LocalAhead' { return [pscustomobject]@{ Label = 'Workspace ahead'; Color = $script:Ui.Warn } }
            'WorkspaceModified' { return [pscustomobject]@{ Label = 'Workspace modified'; Color = $script:Ui.Warn } }
            'Error' { return [pscustomobject]@{ Label = 'Update check failed'; Color = $script:Ui.Fail } }
            default { return [pscustomobject]@{ Label = 'Status unavailable'; Color = $script:Ui.Dim } }
        }
    }
    catch {
        return [pscustomobject]@{ Label = 'Status unavailable'; Color = $script:Ui.Dim }
    }
}

function Get-ShortGitCommitText {
    param(
        [AllowEmptyString()]
        [string]$Commit
    )

    if ([string]::IsNullOrWhiteSpace($Commit)) {
        return '--'
    }

    $normalizedCommit = $Commit.Trim()
    if ($normalizedCommit.Length -le 7) {
        return $normalizedCommit
    }

    return $normalizedCommit.Substring(0, 7)
}

function Get-SystemCleanupUpdateDetails {
    $details = [ordered]@{
        LocalVersion    = $script:AppVersion
        LatestVersion   = '--'
        LocalCommit     = '--'
        LatestCommit    = '--'
        SourceKind      = 'Unknown'
        HasLocalChanges = $false
        Branch          = '--'
        Status          = 'Unknown'
        Message         = 'Update status has not been checked yet.'
        CheckedAt       = '--'
    }

    if (-not (Test-Path -LiteralPath $script:AppUpdateStatusCachePath -PathType Leaf)) {
        return [pscustomobject]$details
    }

    try {
        $cache = Get-Content -LiteralPath $script:AppUpdateStatusCachePath -Raw -ErrorAction Stop | ConvertFrom-Json
        foreach ($name in @('LocalVersion', 'LatestVersion', 'SourceKind', 'Branch', 'Status', 'Message', 'CheckedAt')) {
            if ($cache.PSObject.Properties[$name] -and -not [string]::IsNullOrWhiteSpace([string]$cache.$name)) {
                $details[$name] = [string]$cache.$name
            }
        }
        if ($cache.PSObject.Properties['LocalCommit']) {
            $details.LocalCommit = Get-ShortGitCommitText -Commit ([string]$cache.LocalCommit)
        }
        if ($cache.PSObject.Properties['LatestCommit']) {
            $details.LatestCommit = Get-ShortGitCommitText -Commit ([string]$cache.LatestCommit)
        }
        if ($cache.PSObject.Properties['HasLocalChanges']) {
            $details.HasLocalChanges = [bool]$cache.HasLocalChanges
        }
    }
    catch {
    }

    return [pscustomobject]$details
}

function Get-UiWidth {
    try {
        $windowWidth = [int]$Host.UI.RawUI.WindowSize.Width
        if ($windowWidth -le 0) {
            return 80
        }
        return [Math]::Max(40, [Math]::Min(100, $windowWidth - 2))
    }
    catch {
        return 80
    }
}

function Get-UiText {
    param(
        [AllowEmptyString()][string]$Text,
        [int]$MaxLength
    )

    if ([string]::IsNullOrEmpty($Text) -or $MaxLength -le 0) {
        return ''
    }

    if ($Text.Length -le $MaxLength) {
        return $Text
    }

    if ($MaxLength -eq 1) {
        return $Text.Substring(0, 1)
    }

    if ($MaxLength -le 3) {
        return $Text.Substring(0, $MaxLength)
    }

    return ($Text.Substring(0, $MaxLength - 1) + '~')
}

function Write-BorderedRow {
    param(
        [AllowEmptyString()][string]$Text,
        [string]$Color = $script:Ui.White,
        [int]$Width = (Get-UiWidth),
        [switch]$Bold
    )

    $contentWidth = [Math]::Max(1, $Width - 2)
    $cell = Get-UiText -Text $Text -MaxLength $contentWidth
    $padding = ' ' * [Math]::Max(0, $contentWidth - $cell.Length)
    $boldPrefix = if ($Bold) { $script:Ui.Bold } else { '' }
    Write-Host "$($script:Ui.H1)$([char]0x2551)$boldPrefix$Color$cell$($script:Ui.Reset)$padding$($script:Ui.H1)$([char]0x2551)$($script:Ui.Reset)"
}

function Write-UiTextLine {
    param(
        [AllowEmptyString()][string]$Text,
        [string]$Prefix = '  ',
        [string]$Color = $script:Ui.Dim,
        [int]$Width = (Get-UiWidth)
    )

    $line = Get-UiText -Text $Text -MaxLength ([Math]::Max(1, $Width - $Prefix.Length - 1))
    Write-Host "$Prefix$Color$line$($script:Ui.Reset)"
}

function Write-UiKeyValue {
    param(
        [Parameter(Mandatory)][string]$Label,
        [AllowEmptyString()][string]$Value,
        [string]$ValueColor = $script:Ui.OK,
        [int]$LabelWidth = 20
    )

    $prefix = '  '
    $labelCell = (Get-UiText -Text $Label -MaxLength $LabelWidth).PadRight($LabelWidth)
    $valueWidth = [Math]::Max(1, (Get-UiWidth) - $prefix.Length - $LabelWidth - 2)
    $valueCell = Get-UiText -Text $Value -MaxLength $valueWidth
    Write-Host "$prefix$($script:Ui.Dim)$labelCell$($script:Ui.Reset)  $ValueColor$valueCell$($script:Ui.Reset)"
}

function Write-UiRule {
    param([int]$Indent = 2)

    $prefix = ' ' * [Math]::Max(0, $Indent)
    $line = [string]::new([char]0x2500, [Math]::Max(1, (Get-UiWidth) - $prefix.Length - 1))
    Write-Host "$prefix$($script:Ui.Dim)$line$($script:Ui.Reset)"
}

function Clear-UiScreen {
    try {
        Clear-Host
    }
    catch {
    }
}

function New-UiShortcutSegment {
    param(
        [Parameter(Mandatory)][string]$Text,
        [Parameter(Mandatory)][string]$Color
    )

    [pscustomobject]@{ Text = $Text; Color = $Color }
}

function Write-UiShortcutSegments {
    param(
        [Parameter(Mandatory)][object[]]$Segments,
        [int]$Width = (Get-UiWidth)
    )

    Write-Host '  ' -NoNewline
    $remaining = [Math]::Max(1, $Width - 3)
    foreach ($segment in $Segments) {
        if ($remaining -le 0) {
            break
        }

        $text = [string]$segment.Text
        if ($text.Length -gt $remaining) {
            $text = if ($remaining -le 3) { $text.Substring(0, $remaining) } else { $text.Substring(0, $remaining - 3) + '...' }
        }

        Write-Host "$($segment.Color)$text$($script:Ui.Reset)" -NoNewline
        $remaining -= $text.Length
    }
    Write-Host ''
}

function Show-SystemCleanupHeader {
    param(
        [Parameter(Mandatory)][string]$SectionTitle,
        [AllowEmptyString()][string]$SectionSubtitle = ''
    )

    try { [Console]::Write("$($script:E)[?2026h") } catch {}
    Clear-UiScreen
    $width = Get-UiWidth
    $innerWidth = [Math]::Max(1, $width - 2)

    $border = [string]::new([char]0x2550, ($width - 2))
    $titleText = " $($script:AppName) v$($script:AppVersion)"
    $subtitleText = ' Repair + Update + Cache Cleanup'
    $updateStatus = Get-SystemCleanupUpdateLabel
    $updateText = " Update: $($updateStatus.Label)"
    $titleText = Get-UiText -Text $titleText -MaxLength $innerWidth
    $subtitleText = Get-UiText -Text $subtitleText -MaxLength $innerWidth
    $updateText = Get-UiText -Text $updateText -MaxLength $innerWidth
    $titlePad = [Math]::Max(0, $innerWidth - $titleText.Length)
    $subtitlePad = [Math]::Max(0, $innerWidth - $subtitleText.Length)
    $updatePad = [Math]::Max(0, $innerWidth - $updateText.Length)

    Write-Host ''
    Write-Host "$($script:Ui.H1)$([char]0x2554)$border$([char]0x2557)$($script:Ui.Reset)"
    Write-Host "$($script:Ui.H1)$([char]0x2551)$($script:Ui.Bold)$($script:Ui.White)$titleText$($script:Ui.Reset)$(' ' * $titlePad)$($script:Ui.H1)$([char]0x2551)$($script:Ui.Reset)"
    Write-Host "$($script:Ui.H1)$([char]0x2551)$($script:Ui.Dim)$subtitleText$($script:Ui.Reset)$(' ' * $subtitlePad)$($script:Ui.H1)$([char]0x2551)$($script:Ui.Reset)"
    Write-Host "$($script:Ui.H1)$([char]0x2551)$($updateStatus.Color)$updateText$($script:Ui.Reset)$(' ' * $updatePad)$($script:Ui.H1)$([char]0x2551)$($script:Ui.Reset)"
    Write-Host "$($script:Ui.H1)$([char]0x255A)$border$([char]0x255D)$($script:Ui.Reset)"
    Write-Host ''
    $sectionPrefix = " $([char]0x25C6) $SectionTitle "
    $sectionLine = [string]::new([char]0x2500, [Math]::Max(0, $width - $sectionPrefix.Length - 1))
    Write-Host "$($script:Ui.H1)$sectionPrefix$($script:Ui.Dim)$sectionLine$($script:Ui.Reset)"
    if (-not [string]::IsNullOrWhiteSpace($SectionSubtitle)) {
        Write-UiTextLine -Text $SectionSubtitle -Color $script:Ui.Dim
    }
    Write-Host ''
    Write-Host "$($script:E)[J" -NoNewline
    try { [Console]::Write("$($script:E)[?2026l") } catch {}
}

Initialize-SystemCleanupMetadata

# ─────────────────────────────────────────────
# 🔵 MATCHED ISO REPAIR SOURCE
# ─────────────────────────────────────────────
function Get-RepairArchitectureName {
    param([int]$Architecture)

    switch ($Architecture) {
        0 { return 'x86' }
        5 { return 'arm' }
        9 { return 'x64' }
        12 { return 'arm64' }
        default { return "unknown ($Architecture)" }
    }
}

function Get-LiveRepairTarget {
    $currentVersion = Get-ItemProperty -LiteralPath 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion' -ErrorAction Stop
    $nativeArchitecture = if (-not [string]::IsNullOrWhiteSpace($env:PROCESSOR_ARCHITEW6432)) {
        $env:PROCESSOR_ARCHITEW6432
    }
    else {
        $env:PROCESSOR_ARCHITECTURE
    }
    $architecture = switch ($nativeArchitecture.ToUpperInvariant()) {
        'AMD64' { 'x64' }
        'ARM64' { 'arm64' }
        'X86' { 'x86' }
        default { "unknown ($nativeArchitecture)" }
    }

    $languageValues = Get-ItemProperty -LiteralPath 'HKLM:\SYSTEM\CurrentControlSet\Control\Nls\Language' -ErrorAction Stop
    $baseLanguage = try {
        $languageId = [Convert]::ToInt32([string]$languageValues.InstallLanguage, 16)
        [System.Globalization.CultureInfo]::GetCultureInfo($languageId).Name
    }
    catch {
        [string](Get-WinSystemLocale -ErrorAction Stop).Name
    }

    [pscustomobject]@{
        EditionId        = [string]$currentVersion.EditionID
        InstallationType = [string]$currentVersion.InstallationType
        Architecture     = $architecture
        Build            = [int]$currentVersion.CurrentBuild
        Revision         = [int]$currentVersion.UBR
        Language         = $baseLanguage
    }
}

function Get-RememberedRepairIsoPath {
    if (-not (Test-Path -LiteralPath $script:RepairSourceStatePath -PathType Leaf)) {
        return ''
    }

    try {
        $state = Get-Content -LiteralPath $script:RepairSourceStatePath -Raw -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
        if ($state.PSObject.Properties['iso_path']) {
            return [string]$state.iso_path
        }
    }
    catch {
    }

    return ''
}

function Save-RememberedRepairIsoPath {
    param([Parameter(Mandatory)][string]$IsoPath)

    $stateDirectory = Split-Path -Parent $script:RepairSourceStatePath
    if (-not (Test-Path -LiteralPath $stateDirectory -PathType Container)) {
        New-Item -ItemType Directory -Path $stateDirectory -Force -ErrorAction Stop | Out-Null
    }

    [ordered]@{
        schema_version = 1
        iso_path       = $IsoPath
        verified_at    = (Get-Date).ToString('o')
    } | ConvertTo-Json | Set-Content -LiteralPath $script:RepairSourceStatePath -Encoding utf8 -ErrorAction Stop
}

function Get-PreferredRepairDriveLetter {
    $usedLetters = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    $fileSystemDrives = @(Get-PSDrive -PSProvider FileSystem -ErrorAction SilentlyContinue)
    foreach ($fileSystemDrive in $fileSystemDrives) {
        if (-not [string]::IsNullOrWhiteSpace([string]$fileSystemDrive.Name)) {
            [void]$usedLetters.Add([string]$fileSystemDrive.Name)
        }
    }

    $logicalDisks = @(Get-CimInstance -ClassName Win32_LogicalDisk -ErrorAction SilentlyContinue)
    foreach ($logicalDisk in $logicalDisks) {
        $driveId = [string]$logicalDisk.DeviceID
        if ($driveId -match '^([A-Z]):$') {
            [void]$usedLetters.Add($Matches[1])
        }
    }

    for ($letterCode = [int][char]'Z'; $letterCode -ge [int][char]'D'; $letterCode--) {
        $candidate = [string][char]$letterCode
        if (-not $usedLetters.Contains($candidate)) {
            return $candidate
        }
    }

    throw 'No free drive letter is available between Z: and D:.'
}

function Open-RepairIso {
    param([Parameter(Mandatory)][string]$IsoPath)

    $resolvedIsoPath = (Resolve-Path -LiteralPath $IsoPath -ErrorAction Stop).Path
    if ([System.IO.Path]::GetExtension($resolvedIsoPath) -ine '.iso') {
        throw 'The selected repair source is not an ISO file.'
    }

    $mountedByScript = $false
    try {
        $diskImage = Get-DiskImage -ImagePath $resolvedIsoPath -ErrorAction SilentlyContinue
        if (-not $diskImage -or -not $diskImage.Attached) {
            $preferredLetter = Get-PreferredRepairDriveLetter
            Mount-DiskImage -ImagePath $resolvedIsoPath -StorageType ISO -Access ReadOnly -ErrorAction Stop | Out-Null
            $mountedByScript = $true

            $volume = $null
            for ($attempt = 0; $attempt -lt 20 -and -not $volume; $attempt++) {
                Start-Sleep -Milliseconds 250
                $volume = Get-DiskImage -ImagePath $resolvedIsoPath | Get-Volume -ErrorAction SilentlyContinue
            }
            if (-not $volume) {
                throw 'Windows mounted the ISO but its volume was not detected.'
            }

            $currentLetter = [string]$volume.DriveLetter
            if ($currentLetter -ne $preferredLetter) {
                $currentDrive = $currentLetter + ':'
                $cimVolume = Get-CimInstance -ClassName Win32_Volume -ErrorAction Stop |
                    Where-Object { $_.DriveLetter -eq $currentDrive } |
                    Select-Object -First 1
                if (-not $cimVolume) {
                    throw "Could not resolve the mounted ISO volume at $currentDrive"
                }
                Set-CimInstance -InputObject $cimVolume -Property @{ DriveLetter = ($preferredLetter + ':') } -ErrorAction Stop | Out-Null
            }
        }

        $volume = Get-DiskImage -ImagePath $resolvedIsoPath | Get-Volume -ErrorAction Stop
        if (-not $volume -or [string]::IsNullOrWhiteSpace([string]$volume.DriveLetter)) {
            throw 'The mounted ISO does not have an accessible drive letter.'
        }

        [pscustomobject]@{
            IsoPath         = $resolvedIsoPath
            DriveLetter     = [string]$volume.DriveLetter
            RootPath        = ([string]$volume.DriveLetter + ':\')
            MountedByScript = $mountedByScript
        }
    }
    catch {
        if ($mountedByScript) {
            Dismount-DiskImage -ImagePath $resolvedIsoPath -ErrorAction SilentlyContinue | Out-Null
        }
        throw
    }
}

function Close-RepairIso {
    param([AllowNull()][psobject]$Mount)

    if ($null -eq $Mount -or -not $Mount.MountedByScript) {
        return
    }

    Dismount-DiskImage -ImagePath $Mount.IsoPath -ErrorAction SilentlyContinue | Out-Null
}

function Get-RepairSourceValidation {
    param([Parameter(Mandatory)][psobject]$Mount)

    $wimPath = Join-Path $Mount.RootPath 'sources\install.wim'
    $esdPath = Join-Path $Mount.RootPath 'sources\install.esd'
    if (Test-Path -LiteralPath $wimPath -PathType Leaf) {
        $imagePath = $wimPath
        $sourceType = 'wim'
    }
    elseif (Test-Path -LiteralPath $esdPath -PathType Leaf) {
        $imagePath = $esdPath
        $sourceType = 'esd'
    }
    else {
        throw 'The ISO has neither sources\install.wim nor sources\install.esd.'
    }

    $live = Get-LiveRepairTarget
    $imageSummaries = @(Get-WindowsImage -ImagePath $imagePath -ErrorAction Stop)
    $rows = @(
        foreach ($imageSummary in $imageSummaries) {
            $image = Get-WindowsImage -ImagePath $imagePath -Index ([int]$imageSummary.ImageIndex) -ErrorAction Stop
            $imageVersion = [version]$image.Version
            $sourceArchitecture = Get-RepairArchitectureName -Architecture ([int]$image.Architecture)
            $sourceLanguages = @($image.Languages | ForEach-Object { [string]$_ })
            $mismatches = [System.Collections.Generic.List[string]]::new()

            if ([string]$image.EditionId -ine $live.EditionId) {
                $mismatches.Add("edition $($image.EditionId) != $($live.EditionId)")
            }
            if ([string]$image.InstallationType -ine $live.InstallationType) {
                $mismatches.Add("installation $($image.InstallationType) != $($live.InstallationType)")
            }
            if ($sourceArchitecture -ine $live.Architecture) {
                $mismatches.Add("architecture $sourceArchitecture != $($live.Architecture)")
            }
            if ($imageVersion.Build -ne $live.Build -or $imageVersion.Revision -ne $live.Revision) {
                $mismatches.Add("build $($imageVersion.Build).$($imageVersion.Revision) != $($live.Build).$($live.Revision)")
            }
            if ($sourceLanguages -inotcontains $live.Language) {
                $mismatches.Add("language $($sourceLanguages -join ',') does not include $($live.Language)")
            }

            [pscustomobject]@{
                Index            = [int]$image.ImageIndex
                Name             = [string]$image.ImageName
                EditionId        = [string]$image.EditionId
                InstallationType = [string]$image.InstallationType
                Architecture     = $sourceArchitecture
                Build            = $imageVersion.Build
                Revision         = $imageVersion.Revision
                Languages        = $sourceLanguages
                IsMatch          = ($mismatches.Count -eq 0)
                MismatchText     = ($mismatches -join '; ')
            }
        }
    )
    $matchingRows = @($rows | Where-Object { $_.IsMatch })

    [pscustomobject]@{
        IsMatch       = ($matchingRows.Count -eq 1)
        Live          = $live
        Images        = $rows
        MatchingImage = if ($matchingRows.Count -eq 1) { $matchingRows[0] } else { $null }
        ImagePath     = $imagePath
        SourceType    = $sourceType
    }
}

function Show-RepairSourceValidation {
    param(
        [Parameter(Mandatory)][psobject]$Mount,
        [Parameter(Mandatory)][psobject]$Validation
    )

    $live = $Validation.Live
    Write-Host ''
    Write-Host '=== Repair source verification ===' -ForegroundColor Cyan
    Write-Host "  ISO:  $($Mount.IsoPath)" -ForegroundColor Gray
    Write-Host "  Mount: $($Mount.DriveLetter):" -ForegroundColor Gray
    Write-Host ("  Live:  {0} / {1} / {2} / {3}.{4} / {5}" -f $live.EditionId, $live.InstallationType, $live.Architecture, $live.Build, $live.Revision, $live.Language) -ForegroundColor White

    foreach ($image in $Validation.Images) {
        $sourceText = "index $($image.Index): $($image.EditionId) / $($image.InstallationType) / $($image.Architecture) / $($image.Build).$($image.Revision) / $($image.Languages -join ',')"
        if ($image.IsMatch) {
            Write-Host "  ISO:   $sourceText" -ForegroundColor Green
            Write-Host '  +++   VERIFIED: ISO exactly matches the live Windows installation.' -ForegroundColor Green
        }
        else {
            Write-Host "  ISO:   $sourceText" -ForegroundColor Yellow
            Write-Host "         Mismatch: $($image.MismatchText)" -ForegroundColor Yellow
        }
    }

    if (-not $Validation.IsMatch) {
        Write-Host '  [BLOCKED] No single exact repair image match was found.' -ForegroundColor Red
    }
}

function Resolve-RepairIsoCandidate {
    param([AllowEmptyString()][string]$RequestedPath)

    if (-not [string]::IsNullOrWhiteSpace($RequestedPath)) {
        return $RequestedPath.Trim().Trim('"')
    }

    $rememberedPath = Get-RememberedRepairIsoPath
    if (-not [string]::IsNullOrWhiteSpace($rememberedPath)) {
        return $rememberedPath
    }

    $attachedImages = @(Get-DiskImage -ErrorAction SilentlyContinue | Where-Object { $_.Attached -and $_.ImagePath -like '*.iso' })
    if ($attachedImages.Count -eq 1) {
        return [string]$attachedImages[0].ImagePath
    }

    return ''
}

function Test-AndRememberRepairIso {
    param([Parameter(Mandatory)][string]$IsoPath)

    $mount = Open-RepairIso -IsoPath $IsoPath
    try {
        $validation = Get-RepairSourceValidation -Mount $mount
        Show-RepairSourceValidation -Mount $mount -Validation $validation
        if ($validation.IsMatch) {
            Save-RememberedRepairIsoPath -IsoPath $mount.IsoPath
        }

        [pscustomobject]@{
            Mount      = $mount
            Validation = $validation
        }
    }
    catch {
        Close-RepairIso -Mount $mount
        throw
    }
}

function Invoke-RepairSourceStatus {
    param([AllowEmptyString()][string]$RequestedPath)

    $candidatePath = Resolve-RepairIsoCandidate -RequestedPath $RequestedPath
    if ([string]::IsNullOrWhiteSpace($candidatePath) -or -not (Test-Path -LiteralPath $candidatePath -PathType Leaf)) {
        Write-Host '  [BLOCKED] No usable ISO path was supplied or remembered.' -ForegroundColor Red
        return 30
    }

    $context = $null
    try {
        $context = Test-AndRememberRepairIso -IsoPath $candidatePath
        if ($context.Validation.IsMatch) {
            return 0
        }
        return 31
    }
    catch {
        Write-Host "  [BLOCKED] ISO verification failed: $($_.Exception.Message)" -ForegroundColor Red
        return 32
    }
    finally {
        if ($context) {
            Close-RepairIso -Mount $context.Mount
        }
    }
}

function Invoke-RepairRestoreHealth {
    param([AllowEmptyString()][string]$RequestedPath)

    $candidatePath = Resolve-RepairIsoCandidate -RequestedPath $RequestedPath
    $context = $null

    try {
        if (-not [string]::IsNullOrWhiteSpace($candidatePath) -and (Test-Path -LiteralPath $candidatePath -PathType Leaf)) {
            try {
                $context = Test-AndRememberRepairIso -IsoPath $candidatePath
            }
            catch {
                Write-Host "  ISO verification failed: $($_.Exception.Message)" -ForegroundColor Red
            }
        }

        while ($true) {
            Write-Host ''
            Write-Host '=== RestoreHealth repair fallback ===' -ForegroundColor Cyan
            if ($context -and $context.Validation.IsMatch) {
                Write-Host '  Enter = repair from the verified ISO (recommended)' -ForegroundColor Green
            }
            else {
                Write-Host '  I     = enter a matching Windows ISO path' -ForegroundColor White
            }
            Write-Host '  W     = explicitly allow Windows Update as the repair source' -ForegroundColor Yellow
            Write-Host '          This can download files and may take a long time.' -ForegroundColor DarkGray
            Write-Host '  Esc   = stop Full Cleanup safely' -ForegroundColor Red

            $key = $Host.UI.RawUI.ReadKey('NoEcho,IncludeKeyDown')
            if ($key.VirtualKeyCode -eq 27) {
                Write-Host '  Cancelled. Windows Update was not contacted.' -ForegroundColor DarkGray
                return 2
            }

            if ($key.VirtualKeyCode -eq 13 -and $context -and $context.Validation.IsMatch) {
                $matchingImage = $context.Validation.MatchingImage
                $sourceArgument = "/Source:$($context.Validation.SourceType):$($context.Validation.ImagePath):$($matchingImage.Index)"
                Write-Host ''
                Write-Host '=== DISM RestoreHealth (verified ISO source) ===' -ForegroundColor Cyan
                & dism.exe /Online /Cleanup-Image /RestoreHealth $sourceArgument /LimitAccess
                $repairExitCode = $LASTEXITCODE
                if ($repairExitCode -eq 0) {
                    Write-Host ''
                    Write-Host '  +++   REPAIR COMPLETED: Restart Windows normally before running Full Cleanup again.' -ForegroundColor Green
                }
                else {
                    Write-Host "  [X] ISO repair failed with exit code $repairExitCode." -ForegroundColor Red
                }
                return $repairExitCode
            }

            $character = ([string]$key.Character).ToUpperInvariant()
            if ($character -eq 'I') {
                if ($context) {
                    Close-RepairIso -Mount $context.Mount
                    $context = $null
                }
                $enteredPath = Read-Host '  ISO path (blank = cancel)'
                if ([string]::IsNullOrWhiteSpace($enteredPath)) {
                    continue
                }
                try {
                    $context = Test-AndRememberRepairIso -IsoPath $enteredPath.Trim().Trim('"')
                }
                catch {
                    Write-Host "  ISO verification failed: $($_.Exception.Message)" -ForegroundColor Red
                }
                continue
            }

            if ($character -eq 'W') {
                if ($context) {
                    Close-RepairIso -Mount $context.Mount
                    $context = $null
                }
                Write-Host ''
                Write-Host '=== DISM RestoreHealth (Windows Update allowed by user) ===' -ForegroundColor Cyan
                & dism.exe /Online /Cleanup-Image /RestoreHealth
                $repairExitCode = $LASTEXITCODE
                if ($repairExitCode -eq 0) {
                    Write-Host ''
                    Write-Host '  +++   REPAIR COMPLETED: Restart Windows normally before running Full Cleanup again.' -ForegroundColor Green
                }
                else {
                    Write-Host "  [X] Online repair failed with exit code $repairExitCode." -ForegroundColor Red
                }
                return $repairExitCode
            }
        }
    }
    finally {
        if ($context) {
            Close-RepairIso -Mount $context.Mount
        }
    }
}

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

function Shorten-ServicingPath {
    param(
        [string]$Path,
        [int]$MaxLength = 78
    )

    if ([string]::IsNullOrWhiteSpace($Path)) {
        return ''
    }

    if ($Path.Length -le $MaxLength) {
        return $Path
    }

    $leafName = Split-Path -Path $Path -Leaf
    $leafLength = [Math]::Min($leafName.Length, 28)
    $trimmedLeaf = if ($leafName.Length -gt $leafLength) { $leafName.Substring($leafName.Length - $leafLength) } else { $leafName }

    if ($Path -match '^(.*?\\InFlight\\)[^\\]+(\\.*)$') {
        $shortened = '{0}...{1}' -f $Matches[1], $Matches[2]
        if ($shortened.Length -le $MaxLength) {
            return $shortened
        }
    }

    $prefixLength = [Math]::Max(12, $MaxLength - $trimmedLeaf.Length - 3)
    $prefix = $Path.Substring(0, [Math]::Min($prefixLength, $Path.Length))
    return '{0}...{1}' -f $prefix, $trimmedLeaf
}

function Convert-ServicingLogLineToSummary {
    param(
        [string]$Label,
        [string]$Line,
        [switch]$Compact
    )

    if ([string]::IsNullOrWhiteSpace($Line)) {
        return ''
    }

    if (-not $Compact) {
        $trimmedLine = ($Line -replace '^\S+\s+\S+\s+', '').Trim()
        if ($trimmedLine.Length -gt 220) {
            $trimmedLine = $trimmedLine.Substring(0, 217) + '...'
        }
        return "  [$Label] $trimmedLine"
    }

    if ($Label -eq 'DISM') {
        if ($Line -match 'CBS HRESULT=([0-9A-Fx]+)') {
            return "  [DISM] CBS error surfaced to DISM ($($Matches[1]))."
        }
        if ($Line -match 'Failed processing package changes with session option CbsSessionOptionRepairStoreCorruption') {
            if ($Line -match 'hr:([0-9A-Fx]+)') {
                return "  [DISM] RestoreHealth repair transaction failed ($($Matches[1]))."
            }
            return '  [DISM] RestoreHealth repair transaction failed.'
        }
        if ($Line -match 'Failed to restore the image health') {
            if ($Line -match 'hr:([0-9A-Fx]+)') {
                return "  [DISM] Failed to restore the image health ($($Matches[1]))."
            }
            return '  [DISM] Failed to restore the image health.'
        }
        if ($Line -match 'HRESULT=([0-9A-Fx]+)') {
            return "  [DISM] DISM command failed (HRESULT=$($Matches[1]))."
        }
        if ($Line -match 'FindFirstFile failed for \[(.+?)\]') {
            return "  [DISM] Missing path probe: $(Shorten-ServicingPath -Path $Matches[1])."
        }
    }

    if ($Label -eq 'CBS') {
        if ($Line -match "on:\[\d+\]'([^']+)'") {
            $shortPath = Shorten-ServicingPath -Path $Matches[1]
            return "  [CBS] Missing servicing path: $shortPath"
        }
        if ($Line -match 'STATUS_OBJECT_PATH_NOT_FOUND') {
            return '  [CBS] STATUS_OBJECT_PATH_NOT_FOUND while opening a servicing path.'
        }
        if ($Line -match 'ERROR_PATH_NOT_FOUND') {
            return '  [CBS] CBS reported ERROR_PATH_NOT_FOUND (0x80070003).'
        }
        if ($Line -match 'RBDSTAMIL99\.dic') {
            return '  [CBS] Tamil dictionary component appears in the failing transaction.'
        }
    }

    $trimmedLine = ($Line -replace '^\S+\s+\S+\s+', '').Trim()
    if ($trimmedLine.Length -gt 110) {
        $trimmedLine = $trimmedLine.Substring(0, 107) + '...'
    }
    return "  [$Label] $trimmedLine"
}

function Get-RecentServicingLogLines {
    param(
        [string]$Path,
        [string]$Label,
        [string[]]$Patterns,
        [string[]]$PriorityPatterns = @(),
        [string[]]$ExcludePatterns = @(),
        [switch]$Compact,
        [int]$TailCount = 250,
        [int]$MaxLines = 4
    )

    if (-not (Test-Path -LiteralPath $Path)) {
        return @("  [$Label] Log not found: $Path")
    }

    try {
        $recentLines = Get-Content -LiteralPath $Path -Tail $TailCount -ErrorAction Stop
    }
    catch {
        return @("  [$Label] Unable to read log: $Path")
    }

    $matchedLines = @()
    for ($lineIndex = 0; $lineIndex -lt $recentLines.Count; $lineIndex++) {
        $recentLine = $recentLines[$lineIndex]
        $isMatch = $false
        foreach ($pattern in $Patterns) {
            if ($recentLine -match $pattern) {
                $isMatch = $true
                break
            }
        }

        if (-not $isMatch) {
            continue
        }

        $isExcluded = $false
        foreach ($excludePattern in $ExcludePatterns) {
            if ($recentLine -match $excludePattern) {
                $isExcluded = $true
                break
            }
        }

        if ($isExcluded) {
            continue
        }

        $score = 0
        if ($recentLine -match 'Error') {
            $score += 100
        }
        if ($recentLine -match 'HRESULT') {
            $score += 25
        }

        for ($priorityIndex = 0; $priorityIndex -lt $PriorityPatterns.Count; $priorityIndex++) {
            if ($recentLine -match $PriorityPatterns[$priorityIndex]) {
                $score += 1000 - ($priorityIndex * 100)
            }
        }

        $matchedLines += [pscustomobject]@{
            Text = $recentLine
            Index = $lineIndex
            Score = $score
        }
    }

    if (@($matchedLines).Count -eq 0) {
        return @("  [$Label] No matching recent error lines found in the last $TailCount lines.")
    }

    $matchedLines = @(
        $matchedLines |
            Sort-Object @{ Expression = 'Score'; Descending = $true }, @{ Expression = 'Index'; Descending = $true } |
            Select-Object -First $MaxLines |
            Sort-Object Index
    )

    return @(
        foreach ($matchedLine in $matchedLines) {
            Convert-ServicingLogLineToSummary -Label $Label -Line $matchedLine.Text -Compact:$Compact
        }
    )
}

function Show-DismFailureSummary {
    param([switch]$Compact)

    $dismLogPath = Join-Path $env:WINDIR 'Logs\DISM\dism.log'
    $cbsLogPath = Join-Path $env:WINDIR 'Logs\CBS\CBS.log'

    $summaryLines = @()
    $summaryLines += if ($Compact) { '  Recent servicing log lines:' } else { '  Detailed servicing log lines:' }
    $summaryLines += Get-RecentServicingLogLines -Path $dismLogPath -Label 'DISM' -Patterns @(
        'Error',
        'HRESULT',
        'RestoreHealth',
        '0x80070003',
        'path specified',
        'Failed'
    ) -PriorityPatterns @(
        'Failed processing package changes with session option CbsSessionOptionRepairStoreCorruption',
        'Failed to restore the image health',
        'HRESULT=80070003',
        '0x80070003',
        'path specified'
    ) -ExcludePatterns @(
        'EnumeratePathEx:\s+FindFirstFile failed',
        'FindFirstFile failed for \[\\\\\?\\C:\\\$WINDOWS\.\~',
        'FindFirstFile failed for \[\\\\\?\\C:\\ESD\\',
        'FindFirstFile failed for \[\\\\\?\\C:\\INPLACE\.\~'
    ) -Compact:$Compact -TailCount 1200 -MaxLines $(if ($Compact) { 4 } else { 6 })
    $summaryLines += Get-RecentServicingLogLines -Path $cbsLogPath -Label 'CBS' -Patterns @(
        'Error',
        'ERROR_PATH_NOT_FOUND',
        '0x80070003',
        'RBDSTAMIL99',
        'InFlight',
        'Failed'
    ) -PriorityPatterns @(
        'RBDSTAMIL99',
        'WinSxS\\Temp\\InFlight',
        'STATUS_OBJECT_PATH_NOT_FOUND',
        'ERROR_PATH_NOT_FOUND',
        'Error'
    ) -Compact:$Compact -TailCount 3000 -MaxLines $(if ($Compact) { 4 } else { 6 })

    $summaryLines | Write-Output
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

function Format-ByteSize {
    param([double]$Bytes)

    if ($Bytes -ge 1GB) {
        return ('{0} GB' -f [math]::Round(($Bytes / 1GB), 2))
    }

    if ($Bytes -ge 1MB) {
        return ('{0} MB' -f [math]::Round(($Bytes / 1MB), 1))
    }

    if ($Bytes -ge 1KB) {
        return ('{0} KB' -f [math]::Round(($Bytes / 1KB), 1))
    }

    return ('{0} B' -f [math]::Round($Bytes, 0))
}

function Get-DeliveryOptimizationState {
    $state = [ordered]@{
        IsAvailable = $false
        StatusLabel = 'Unavailable'
        IsDisabled = $false
        DownloadMode = 'Unknown'
        DownloadModeProvider = 'Unavailable'
        WorkingDirectory = ''
        CacheSizeBytes = 0
        CacheSizeLabel = '0 B'
        Files = 0
        PolicyDownloadMode = $null
        PolicyPath = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\DeliveryOptimization'
        Note = ''
    }

    $config = $null
    $perf = $null
    try {
        $config = Get-DOConfig -Verbose 4>$null
    }
    catch {}

    try {
        $perf = Get-DeliveryOptimizationPerfSnap
    }
    catch {}

    if ($null -ne $config -or $null -ne $perf) {
        $state.IsAvailable = $true
    }

    if ($null -ne $config) {
        if ($config.PSObject.Properties['DownloadMode']) {
            $state.DownloadMode = [string]$config.DownloadMode
        }
        if ($config.PSObject.Properties['DownloadModeProvider']) {
            $state.DownloadModeProvider = [string]$config.DownloadModeProvider
        }
        if ($config.PSObject.Properties['WorkingDirectory']) {
            $state.WorkingDirectory = [string]$config.WorkingDirectory
        }
    }

    if ($null -ne $perf) {
        if ($perf.PSObject.Properties['CacheSizeBytes'] -and $null -ne $perf.CacheSizeBytes) {
            $state.CacheSizeBytes = [double]$perf.CacheSizeBytes
        }
        if ($perf.PSObject.Properties['Files'] -and $null -ne $perf.Files) {
            $state.Files = [int]$perf.Files
        }
        if ($state.DownloadMode -eq 'Unknown' -and $perf.PSObject.Properties['DownloadMode']) {
            $state.DownloadMode = [string]$perf.DownloadMode
        }
    }

    $canInspectWorkingDirectory = $false
    if (-not [string]::IsNullOrWhiteSpace($state.WorkingDirectory)) {
        try {
            $canInspectWorkingDirectory = Test-Path -LiteralPath $state.WorkingDirectory -ErrorAction Stop
        }
        catch {
            $canInspectWorkingDirectory = $false
        }
    }

    if ($state.CacheSizeBytes -eq 0 -and $canInspectWorkingDirectory) {
        try {
            $state.CacheSizeBytes = [double](
                Get-ChildItem -LiteralPath $state.WorkingDirectory -Recurse -File -Force -ErrorAction SilentlyContinue |
                    Measure-Object -Property Length -Sum |
                    Select-Object -ExpandProperty Sum
            )
        }
        catch {}
    }

    try {
        $policyProps = Get-ItemProperty -Path $state.PolicyPath -Name 'DODownloadMode' -ErrorAction Stop
        if ($policyProps.PSObject.Properties['DODownloadMode']) {
            $state.PolicyDownloadMode = [int]$policyProps.DODownloadMode
        }
    }
    catch {}

    $state.CacheSizeLabel = Format-ByteSize -Bytes $state.CacheSizeBytes

    $disabledModes = @('CdnOnly', 'Simple', 'Bypass')
    if ($disabledModes -contains $state.DownloadMode) {
        $state.IsDisabled = $true
        $state.StatusLabel = 'Disabled'
    }
    elseif (@('Lan', 'Group', 'Internet') -contains $state.DownloadMode) {
        $state.IsDisabled = $false
        $state.StatusLabel = 'Enabled'
    }
    elseif ($state.PolicyDownloadMode -eq 0) {
        $state.IsDisabled = $true
        $state.StatusLabel = 'Disabled'
        if ($state.DownloadMode -eq 'Unknown') {
            $state.DownloadMode = 'CdnOnly'
        }
    }
    elseif ($state.IsAvailable) {
        $state.StatusLabel = 'Unknown'
    }

    if ($state.IsDisabled -and $state.PolicyDownloadMode -eq 0) {
        $state.Note = 'Policy enforces CdnOnly'
    }
    elseif ($state.IsDisabled) {
        $state.Note = 'Peer sharing appears off'
    }
    elseif ($state.StatusLabel -eq 'Enabled') {
        $state.Note = 'Peer sharing is allowed'
    }

    return [pscustomobject]$state
}

function Get-DeliveryOptimizationStatusLine {
    $state = Get-DeliveryOptimizationState
    if (-not $state.IsAvailable) {
        return 'Delivery Optimization status unavailable'
    }

    if ($state.IsDisabled) {
        return ('Disabled ({0}) • Cache {1}' -f $state.DownloadMode, $state.CacheSizeLabel)
    }

    if ($state.StatusLabel -eq 'Enabled') {
        return ('Enabled ({0}) • Cache {1}' -f $state.DownloadMode, $state.CacheSizeLabel)
    }

    return ('Status {0} • Cache {1}' -f $state.DownloadMode, $state.CacheSizeLabel)
}

# Generic launcher-side InstallerCore update probe.
# This is intentionally tool-agnostic so the same pattern can be lifted into other main-menu tools later.
function Get-InstallerCoreUpdateState {
    $state = [ordered]@{
        IsAvailable = $false
        InstallScriptPath = ''
        Mode = 'Unavailable'
        InstallerMode = 'GitHub'
        DefaultAction = ''
        GitHubBranch = ''
        LocalSourcePath = ''
        StatusLine = 'InstallerCore updater unavailable'
        RelaunchesInstaller = $false
        Reason = ''
    }

    $installScriptPath = Join-Path $PSScriptRoot 'Install.ps1'
    if (-not (Test-Path -LiteralPath $installScriptPath)) {
        $state.Reason = 'Install.ps1 not found beside the launcher.'
        return [pscustomobject]$state
    }

    $state.IsAvailable = $true
    $state.InstallScriptPath = $installScriptPath

    $gitRoot = Join-Path $PSScriptRoot '.git'
    if (Test-Path -LiteralPath $gitRoot) {
        $state.Mode = 'Repo copy'
        $state.InstallerMode = 'Git fast-forward'
        $state.DefaultAction = 'GitFastForward'
        $state.RelaunchesInstaller = $false

        $gitBranch = ''
        try {
            $gitBranch = (& git.exe -C $PSScriptRoot branch --show-current 2>$null | Out-String).Trim()
        }
        catch {}

        if ([string]::IsNullOrWhiteSpace($gitBranch)) {
            try {
                $gitBranch = (& git.exe -C $PSScriptRoot rev-parse --abbrev-ref HEAD 2>$null | Out-String).Trim()
                if ($gitBranch -eq 'HEAD') {
                    $gitBranch = ''
                }
            }
            catch {}
        }

        $state.GitHubBranch = $gitBranch
        $branchLabel = if ([string]::IsNullOrWhiteSpace($gitBranch)) { 'auto' } else { $gitBranch }
        $state.StatusLine = "Repo copy • Git/$branchLabel"
        return [pscustomobject]$state
    }

    $metaPath = Join-Path $PSScriptRoot 'state\install-meta.json'
    if (Test-Path -LiteralPath $metaPath) {
        $state.Mode = 'Installed copy'
        $state.InstallerMode = 'GitHub'
        $state.DefaultAction = 'UpdateGitHub'

        try {
            $meta = Get-Content -LiteralPath $metaPath -Raw -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
            $packageSource = if ($meta.PSObject.Properties['package_source']) { ([string]$meta.package_source).Trim() } else { '' }
            $sourcePath = if ($meta.PSObject.Properties['source_path']) { ([string]$meta.source_path).Trim() } else { '' }
            $githubBranch = ''
            if ($meta.PSObject.Properties['github_ref'] -and -not [string]::IsNullOrWhiteSpace([string]$meta.github_ref)) {
                $githubBranch = ([string]$meta.github_ref).Trim()
            }
            elseif ($meta.PSObject.Properties['source_path'] -and ([string]$meta.source_path) -match '^github://.+?@(.+)$') {
                $githubBranch = ($Matches[1]).Trim()
            }

            if ($packageSource -eq 'Local' -and -not [string]::IsNullOrWhiteSpace($sourcePath) -and -not ($sourcePath -like 'github://*')) {
                $state.InstallerMode = 'Local'
                $state.DefaultAction = 'Update'
                $state.LocalSourcePath = $sourcePath
            }
            else {
                $state.GitHubBranch = $githubBranch
            }
        }
        catch {
            $state.Reason = 'install-meta.json could not be parsed; falling back to GitHub auto-detect.'
        }

        if ($state.InstallerMode -eq 'Local') {
            $state.StatusLine = 'Installed copy • Local'
        }
        else {
            $branchLabel = if ([string]::IsNullOrWhiteSpace($state.GitHubBranch)) { 'auto' } else { $state.GitHubBranch }
            $state.StatusLine = "Installed copy • GitHub/$branchLabel"
        }
        return [pscustomobject]$state
    }

    $state.Mode = 'Portable copy'
    $state.InstallerMode = 'GitHub'
    $state.DefaultAction = 'DownloadLatest'
    $state.RelaunchesInstaller = $true
    $state.StatusLine = 'Portable copy • GitHub/auto'
    $state.Reason = 'No .git folder and no install-meta.json were found.'
    return [pscustomobject]$state
}

function Get-InstallerCoreUpdateStatusLine {
    $state = Get-InstallerCoreUpdateState
    return $state.StatusLine
}

function Read-InstallerCoreUpdateChoice {
    Write-Host "  $($script:Ui.White)Choices:$($script:Ui.Reset)"
    Write-UiShortcutSegments -Segments @(
        New-UiShortcutSegment -Text 'Enter' -Color $script:Ui.OK
        New-UiShortcutSegment -Text ' = use shown defaults' -Color $script:Ui.White
    )
    Write-UiTextLine -Text 'Continue with the Installer Mode + branch/source shown above' -Prefix '        ' -Color $script:Ui.Dim
    Write-UiShortcutSegments -Segments @(
        New-UiShortcutSegment -Text 'E' -Color $script:Ui.Warn
        New-UiShortcutSegment -Text ' = open full InstallerCore menu' -Color $script:Ui.White
    )
    Write-UiTextLine -Text 'Choose Local/GitHub and branch/source manually' -Prefix '        ' -Color $script:Ui.Dim
    Write-UiShortcutSegments -Segments @(
        New-UiShortcutSegment -Text 'Esc' -Color $script:Ui.Fail
        New-UiShortcutSegment -Text ' = cancel' -Color $script:Ui.White
    )
    Write-Host ''
    Write-Host '  Choice: ' -ForegroundColor White -NoNewline

    while ($true) {
        $key = $Host.UI.RawUI.ReadKey('NoEcho,IncludeKeyDown')
        if ($key.VirtualKeyCode -eq 13) {
            Write-Host 'Enter' -ForegroundColor DarkGray
            return 'DEFAULT'
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
        if ($char -match '^[Ee]$') {
            return 'EDIT'
        }

        Write-Host '  Invalid choice. Use Enter, E, or ESC.' -ForegroundColor Yellow
        Write-Host '  Choice: ' -ForegroundColor Gray -NoNewline
    }
}

function Read-EnterOrEscChoice {
    param(
        [string]$EnterLabel = 'Proceed',
        [string]$EnterDescription = '',
        [string]$EscLabel = 'Cancel'
    )

    Write-Host "  $($script:Ui.White)Choices:$($script:Ui.Reset)"
    Write-UiShortcutSegments -Segments @(
        New-UiShortcutSegment -Text 'Enter' -Color $script:Ui.OK
        New-UiShortcutSegment -Text (" = {0}" -f $EnterLabel) -Color $script:Ui.White
    )
    if (-not [string]::IsNullOrWhiteSpace($EnterDescription)) {
        Write-UiTextLine -Text $EnterDescription -Prefix '        ' -Color $script:Ui.Dim
    }
    Write-UiShortcutSegments -Segments @(
        New-UiShortcutSegment -Text 'Esc' -Color $script:Ui.Fail
        New-UiShortcutSegment -Text (" = {0}" -f $EscLabel) -Color $script:Ui.White
    )
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

function Get-RecentTextFileLines {
    param(
        [AllowEmptyString()][string]$Path,
        [int]$TailCount = 10
    )

    if ([string]::IsNullOrWhiteSpace($Path) -or -not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        return @()
    }

    try {
        return @(Get-Content -LiteralPath $Path -Tail $TailCount -ErrorAction Stop | ForEach-Object { [string]$_ })
    }
    catch {
        return @()
    }
}

function Show-ToolUpdateProgressPanel {
    param(
        [string]$Message,
        [ValidateSet('Info', 'Good', 'Warn', 'Error')]
        [string]$Level = 'Info',
        [string[]]$RecentLines = @(),
        [switch]$AutoRestart
    )

    $messageColor = switch ($Level) {
        'Good' { $script:Ui.OK }
        'Warn' { $script:Ui.Warn }
        'Error' { $script:Ui.Fail }
        default { $script:Ui.H1 }
    }

    Show-SystemCleanupHeader -SectionTitle 'Update App' -SectionSubtitle 'InstallerCore'
    Write-UiTextLine -Text $Message -Prefix '  ' -Color $messageColor

    if (@($RecentLines).Count -gt 0) {
        Write-Host ''
        $recentPrefix = " $([char]0x25C6) Recent Output "
        $recentRule = [string]::new([char]0x2500, [Math]::Max(1, (Get-UiWidth) - $recentPrefix.Length - 1))
        Write-Host "$($script:Ui.H1)$recentPrefix$($script:Ui.Dim)$recentRule$($script:Ui.Reset)"
        foreach ($line in @($RecentLines | Select-Object -Last 10)) {
            Write-UiTextLine -Text ([string]$line) -Prefix '  ' -Color $script:Ui.Dim
        }
    }

    Write-Host ''
    $commandsPrefix = " $([char]0x25C6) Commands "
    $commandsRule = [string]::new([char]0x2500, [Math]::Max(1, (Get-UiWidth) - $commandsPrefix.Length - 1))
    Write-Host "$($script:Ui.H1)$commandsPrefix$($script:Ui.Dim)$commandsRule$($script:Ui.Reset)"
    if ($AutoRestart) {
        Write-UiTextLine -Text 'Restarting SystemCleanup with updated files...' -Prefix '  ' -Color $script:Ui.OK
    }
    else {
        Write-UiShortcutSegments -Segments @(
            New-UiShortcutSegment -Text 'Esc' -Color $script:Ui.Fail
            New-UiShortcutSegment -Text ' = back' -Color $script:Ui.Dim
        )
    }
}

function Invoke-InstallerCoreUpdateProcess {
    param(
        [Parameter(Mandatory)][string]$PwshExe,
        [Parameter(Mandatory)][string[]]$ArgumentList,
        [Parameter(Mandatory)][string]$WorkingDirectory,
        [Parameter(Mandatory)][string]$ProgressMessage,
        [Parameter(Mandatory)][string]$InstallerLogPath
    )

    $stdoutPath = Join-Path $env:TEMP ("SystemCleanup_updater_out_{0}.log" -f [guid]::NewGuid().ToString('N'))
    $stderrPath = Join-Path $env:TEMP ("SystemCleanup_updater_err_{0}.log" -f [guid]::NewGuid().ToString('N'))

    try {
        $process = Start-Process -FilePath $PwshExe -ArgumentList $ArgumentList -WorkingDirectory $WorkingDirectory -RedirectStandardOutput $stdoutPath -RedirectStandardError $stderrPath -WindowStyle Hidden -PassThru -ErrorAction Stop
        while (-not $process.HasExited) {
            $recentLines = @((Get-RecentTextFileLines -Path $InstallerLogPath -TailCount 8) + (Get-RecentTextFileLines -Path $stderrPath -TailCount 3))
            Show-ToolUpdateProgressPanel -Message $ProgressMessage -Level 'Info' -RecentLines $recentLines
            Start-Sleep -Milliseconds 250
        }

        $process.Refresh()
        $exitCode = [int]$process.ExitCode
        $finalLines = @((Get-RecentTextFileLines -Path $InstallerLogPath -TailCount 8) + (Get-RecentTextFileLines -Path $stderrPath -TailCount 5))
        return [pscustomobject]@{
            ExitCode = $exitCode
            RecentLines = $finalLines
        }
    }
    catch {
        return [pscustomobject]@{
            ExitCode = 9999
            RecentLines = @("Could not start updater process: $($_.Exception.Message)")
        }
    }
    finally {
        foreach ($tempPath in @($stdoutPath, $stderrPath)) {
            try {
                if (Test-Path -LiteralPath $tempPath -PathType Leaf) {
                    Remove-Item -LiteralPath $tempPath -Force -ErrorAction SilentlyContinue
                }
            }
            catch {}
        }
    }
}

function Invoke-GitWorkingCopyUpdateProcess {
    param(
        [Parameter(Mandatory)][string]$WorkingDirectory,
        [AllowEmptyString()][string]$Branch
    )

    $recentLines = [System.Collections.Generic.List[string]]::new()
    function Add-RecentLine {
        param([AllowEmptyString()][string]$Line)
        if ([string]::IsNullOrWhiteSpace($Line)) {
            return
        }
        [void]$recentLines.Add($Line)
        while ($recentLines.Count -gt 12) {
            $recentLines.RemoveAt(0)
        }
    }

    $gitCommand = Get-Command git.exe -ErrorAction SilentlyContinue
    if ($null -eq $gitCommand) {
        Add-RecentLine 'git.exe was not found in PATH.'
        return [pscustomobject]@{ ExitCode = 9001; RecentLines = @($recentLines) }
    }

    try {
        $inside = (& git.exe -C $WorkingDirectory rev-parse --is-inside-work-tree 2>&1 | Out-String).Trim()
        if ($inside -ne 'true') {
            Add-RecentLine 'This folder is not a git working copy.'
            return [pscustomobject]@{ ExitCode = 9002; RecentLines = @($recentLines) }
        }

        $dirty = (& git.exe -C $WorkingDirectory status --porcelain 2>&1 | Out-String).Trim()
        if (-not [string]::IsNullOrWhiteSpace($dirty)) {
            Add-RecentLine 'Working copy has local changes. Fast-forward update refused.'
            Add-RecentLine 'Commit, stash, or discard local changes before updating this repo copy.'
            return [pscustomobject]@{ ExitCode = 3; RecentLines = @($recentLines) }
        }

        if ([string]::IsNullOrWhiteSpace($Branch)) {
            $Branch = (& git.exe -C $WorkingDirectory branch --show-current 2>&1 | Out-String).Trim()
        }
        if ([string]::IsNullOrWhiteSpace($Branch)) {
            Add-RecentLine 'Could not determine the current git branch.'
            return [pscustomobject]@{ ExitCode = 9003; RecentLines = @($recentLines) }
        }

        Add-RecentLine ("Fetching origin/{0}..." -f $Branch)
        $fetchText = (& git.exe -C $WorkingDirectory fetch --prune origin $Branch 2>&1 | Out-String).Trim()
        foreach ($line in ($fetchText -split "`r?`n")) {
            Add-RecentLine $line
        }
        if ($LASTEXITCODE -ne 0) {
            return [pscustomobject]@{ ExitCode = $LASTEXITCODE; RecentLines = @($recentLines) }
        }

        $localHead = (& git.exe -C $WorkingDirectory rev-parse HEAD 2>&1 | Out-String).Trim()
        $remoteHead = (& git.exe -C $WorkingDirectory rev-parse "origin/$Branch" 2>&1 | Out-String).Trim()
        if (-not [string]::IsNullOrWhiteSpace($localHead) -and $localHead -eq $remoteHead) {
            Add-RecentLine ("Already up to date with origin/{0}." -f $Branch)
            return [pscustomobject]@{ ExitCode = 0; RecentLines = @($recentLines) }
        }

        Add-RecentLine ("Fast-forwarding to origin/{0}..." -f $Branch)
        $mergeText = (& git.exe -C $WorkingDirectory merge --ff-only "origin/$Branch" 2>&1 | Out-String).Trim()
        foreach ($line in ($mergeText -split "`r?`n")) {
            Add-RecentLine $line
        }
        return [pscustomobject]@{ ExitCode = $LASTEXITCODE; RecentLines = @($recentLines) }
    }
    catch {
        Add-RecentLine ("Git update failed: {0}" -f $_.Exception.Message)
        return [pscustomobject]@{ ExitCode = 9999; RecentLines = @($recentLines) }
    }
}

if (-not ('SystemCleanup.NativeUser32' -as [type])) {
    Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;

namespace SystemCleanup {
    public static class NativeUser32 {
        [DllImport("user32.dll")]
        public static extern IntPtr GetForegroundWindow();

        [DllImport("user32.dll")]
        public static extern uint GetWindowThreadProcessId(IntPtr hWnd, out uint lpdwProcessId);

        [DllImport("user32.dll", SetLastError = true)]
        [return: MarshalAs(UnmanagedType.Bool)]
        public static extern bool PostMessage(IntPtr hWnd, uint Msg, IntPtr wParam, IntPtr lParam);

        [DllImport("user32.dll")]
        [return: MarshalAs(UnmanagedType.Bool)]
        public static extern bool IsWindow(IntPtr hWnd);
    }
}
'@
}

function Get-CurrentWindowsTerminalWindowHandle {
    try {
        if ([string]::IsNullOrWhiteSpace($env:WT_SESSION)) {
            return [IntPtr]::Zero
        }

        $foregroundWindow = [SystemCleanup.NativeUser32]::GetForegroundWindow()
        if ($foregroundWindow -eq [IntPtr]::Zero) {
            return [IntPtr]::Zero
        }

        $processId = 0
        [void][SystemCleanup.NativeUser32]::GetWindowThreadProcessId($foregroundWindow, [ref]$processId)
        if ($processId -le 0) {
            return [IntPtr]::Zero
        }

        $foregroundProcess = Get-Process -Id $processId -ErrorAction SilentlyContinue
        if ($null -eq $foregroundProcess) {
            return [IntPtr]::Zero
        }

        if ($foregroundProcess.ProcessName -notin @('WindowsTerminal', 'wt')) {
            return [IntPtr]::Zero
        }

        return $foregroundWindow
    }
    catch {
        return [IntPtr]::Zero
    }
}

function Start-SystemCleanupLauncherRelaunch {
    param(
        [string]$LauncherScriptPath
    )

    if ([string]::IsNullOrWhiteSpace($LauncherScriptPath) -or -not (Test-Path -LiteralPath $LauncherScriptPath)) {
        return $false
    }

    $pwshCmd = Get-Command pwsh.exe -ErrorAction SilentlyContinue
    $pwshExe = if ($null -ne $pwshCmd) { $pwshCmd.Source } else { Join-Path $PSHOME 'pwsh.exe' }
    $wtCmd = Get-Command wt.exe -ErrorAction SilentlyContinue
    $wtExe = if ($null -ne $wtCmd) { $wtCmd.Source } else { '' }
    $launcherDir = Split-Path -Path $LauncherScriptPath -Parent
    $windowHandleToClose = Get-CurrentWindowsTerminalWindowHandle
    $windowHandleValue = if ($windowHandleToClose -eq [IntPtr]::Zero) { 0 } else { $windowHandleToClose.ToInt64() }
    $helperPath = Join-Path $env:TEMP ("SystemCleanup_relaunch_{0}.cmd" -f [guid]::NewGuid().ToString('N'))
    $helperContent = [System.Collections.Generic.List[string]]::new()
    [void]$helperContent.Add('@echo off')
    [void]$helperContent.Add('setlocal')
    [void]$helperContent.Add('timeout /t 1 /nobreak >nul')
    [void]$helperContent.Add('set "WT_SESSION="')

    if (-not [string]::IsNullOrWhiteSpace($wtExe)) {
        [void]$helperContent.Add(
            ('start "" "{0}" -w -1 new-tab "{1}" -NoProfile -ExecutionPolicy Bypass -File "{2}" -WtHosted' -f $wtExe, $pwshExe, $LauncherScriptPath)
        )
    }
    else {
        [void]$helperContent.Add(
            ('start "" "{0}" -NoProfile -ExecutionPolicy Bypass -File "{1}"' -f $pwshExe, $LauncherScriptPath)
        )
    }

    if ($windowHandleValue -gt 0) {
        [void]$helperContent.Add('timeout /t 1 /nobreak >nul')
        [void]$helperContent.Add(
            ('"{0}" -NoProfile -ExecutionPolicy Bypass -Command "$hwnd=[IntPtr]::{1}; Add-Type -Namespace Win32 -Name Native -MemberDefinition ''[DllImport(\"user32.dll\", SetLastError=true)] public static extern bool PostMessage(IntPtr hWnd, uint Msg, IntPtr wParam, IntPtr lParam); [DllImport(\"user32.dll\")] public static extern bool IsWindow(IntPtr hWnd);''; if([Win32.Native]::IsWindow($hwnd)){{ [void][Win32.Native]::PostMessage($hwnd, 0x0010, [IntPtr]::Zero, [IntPtr]::Zero) }}"' -f $pwshExe, $windowHandleValue)
        )
    }

    [void]$helperContent.Add('del "%~f0"')

    try {
        Set-Content -LiteralPath $helperPath -Value $helperContent -Encoding ASCII -ErrorAction Stop
        Start-Process -FilePath $helperPath -WorkingDirectory $launcherDir -WindowStyle Hidden | Out-Null
        return $true
    }
    catch {
        try {
            if (Test-Path -LiteralPath $helperPath) {
                Remove-Item -LiteralPath $helperPath -Force -ErrorAction SilentlyContinue
            }
        }
        catch {}
        return $false
    }
}

function Read-PostUpdateRelaunchChoice {
    Write-Host ''
    Write-Host "  $($script:Ui.White)Relaunch choices:$($script:Ui.Reset)"
    Write-UiShortcutSegments -Segments @(
        New-UiShortcutSegment -Text 'Enter' -Color $script:Ui.OK
        New-UiShortcutSegment -Text ' = relaunch app only' -Color $script:Ui.White
    )
    Write-UiTextLine -Text 'Restart the updated SystemCleanup window without touching Explorer' -Prefix '        ' -Color $script:Ui.Dim
    Write-UiShortcutSegments -Segments @(
        New-UiShortcutSegment -Text 'Any other key' -Color $script:Ui.Warn
        New-UiShortcutSegment -Text ' = restart Explorer + relaunch app' -Color $script:Ui.White
    )
    Write-UiTextLine -Text 'Explorer shell will restart with no folder window reopened' -Prefix '        ' -Color $script:Ui.Dim
    Write-Host ''
    Write-Host '  Choice: ' -ForegroundColor White -NoNewline

    $key = $Host.UI.RawUI.ReadKey('NoEcho,IncludeKeyDown')
    if ($key.VirtualKeyCode -eq 13) {
        Write-Host 'Enter' -ForegroundColor DarkGray
        return 'APP_ONLY'
    }

    $keyLabel = if ($key.VirtualKeyCode -eq 27) {
        'ESC'
    }
    elseif (-not [string]::IsNullOrWhiteSpace([string]$key.Character)) {
        [string]$key.Character
    }
    else {
        "VK $($key.VirtualKeyCode)"
    }

    Write-Host $keyLabel -ForegroundColor DarkGray
    return 'APP_AND_EXPLORER'
}

function Restart-ExplorerShellNoReopen {
    $runningExplorer = @(Get-Process -Name explorer -ErrorAction SilentlyContinue)
    if ($runningExplorer.Count -eq 0) {
        Write-Host '  ℹ️ Explorer was not running, so no shell restart was needed.' -ForegroundColor DarkGray
        return $true
    }

    try {
        foreach ($explorerProcess in $runningExplorer) {
            try {
                Stop-Process -Id $explorerProcess.Id -Force -ErrorAction Stop
            }
            catch {}
        }

        try {
            Wait-Process -Name explorer -Timeout 5 -ErrorAction SilentlyContinue
        }
        catch {}

        # Do not force Start-Process explorer.exe here. Windows should auto-restore
        # the shell, and forcing a fresh explorer instance can leave ghost/zombie
        # processes behind on some systems.
        $shellAlive = $false
        $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
        do {
            Start-Sleep -Milliseconds 300
            if (Get-Process -Name explorer -ErrorAction SilentlyContinue) {
                $shellAlive = $true
            }
        } while (-not $shellAlive -and $stopwatch.Elapsed.TotalSeconds -lt 10)

        if (-not $shellAlive) {
            Write-Host '  ⚠️ Explorer shell did not auto-restart within the timeout.' -ForegroundColor Yellow
            Write-Host '     Please restart Explorer manually if the desktop/taskbar stay missing.' -ForegroundColor DarkGray
            return $false
        }

        Start-Sleep -Milliseconds 500
        Write-Host '  ✅ Explorer restarted (auto). No folder window was reopened.' -ForegroundColor Green
        return $true
    }
    catch {
        Write-Host '  ⚠️ Explorer restart failed. Please restart Explorer manually if needed.' -ForegroundColor Yellow
        return $false
    }
}

function Invoke-InstallerCoreToolUpdate {
    $state = Get-InstallerCoreUpdateState
    $updateDetails = Get-SystemCleanupUpdateDetails

    Show-SystemCleanupHeader -SectionTitle 'Update App' -SectionSubtitle 'InstallerCore'

    if (-not $state.IsAvailable) {
        Write-Host "  ❌ $($state.StatusLine)" -ForegroundColor Red
        if (-not [string]::IsNullOrWhiteSpace($state.Reason)) {
            Write-Host "     $($state.Reason)" -ForegroundColor DarkGray
        }
        return
    }

    Write-UiKeyValue -Label 'Detected mode:' -Value $state.Mode
    Write-UiKeyValue -Label 'Installer Mode:' -Value $state.InstallerMode
    if ($state.InstallerMode -eq 'GitHub' -or $state.InstallerMode -eq 'Git fast-forward') {
        if (-not [string]::IsNullOrWhiteSpace($state.GitHubBranch)) {
            $branchLabelName = if ($state.InstallerMode -eq 'Git fast-forward') { 'Git branch:' } else { 'GitHub branch:' }
            Write-UiKeyValue -Label $branchLabelName -Value $state.GitHubBranch
        }
        else {
            $branchLabelName = if ($state.InstallerMode -eq 'Git fast-forward') { 'Git branch:' } else { 'GitHub branch:' }
            Write-UiKeyValue -Label $branchLabelName -Value 'auto-detect'
        }
    }
    elseif (-not [string]::IsNullOrWhiteSpace($state.LocalSourcePath)) {
        Write-UiKeyValue -Label 'Local source:' -Value $state.LocalSourcePath
    }
    Write-UiKeyValue -Label 'Install.ps1 path:' -Value $state.InstallScriptPath -ValueColor $script:Ui.Dim
    Write-Host ''
    $statusColor = switch ([string]$updateDetails.Status) {
        'UpToDate' { $script:Ui.OK }
        'UpdateAvailable' { $script:Ui.Warn }
        'WorkspaceModified' { $script:Ui.Warn }
        'LocalAhead' { $script:Ui.H1 }
        'Error' { $script:Ui.Fail }
        default { $script:Ui.Dim }
    }
    Write-UiKeyValue -Label 'Update status:' -Value $updateDetails.Status -ValueColor $statusColor
    Write-UiKeyValue -Label 'Current version:' -Value $updateDetails.LocalVersion
    Write-UiKeyValue -Label 'Latest version:' -Value $updateDetails.LatestVersion
    Write-UiKeyValue -Label 'Current commit:' -Value $updateDetails.LocalCommit
    Write-UiKeyValue -Label 'Latest commit:' -Value $updateDetails.LatestCommit
    $sourceLabel = if ($updateDetails.HasLocalChanges) { "$($updateDetails.SourceKind) + local changes" } else { $updateDetails.SourceKind }
    Write-UiKeyValue -Label 'Current source:' -Value $sourceLabel
    Write-UiKeyValue -Label 'Last check:' -Value ($updateDetails.CheckedAt -replace 'T', ' ') -ValueColor $script:Ui.Dim
    if (-not [string]::IsNullOrWhiteSpace([string]$updateDetails.Message)) {
        Write-UiTextLine -Text $updateDetails.Message -Prefix '  ' -Color $script:Ui.Dim
    }
    Write-Host ""
    Write-UiTextLine -Text 'This will update the tool via the sibling InstallerCore-generated Install.ps1.' -Prefix '  ' -Color $script:Ui.Warn
    if ($state.DefaultAction -eq 'GitFastForward') {
        Write-UiTextLine -Text '- Current git working copy will use fetch + fast-forward only' -Prefix '      ' -Color $script:Ui.Dim
        Write-UiTextLine -Text '- Dirty workspaces are refused instead of overwritten' -Prefix '      ' -Color $script:Ui.Dim
        Write-UiTextLine -Text '- The launcher will relaunch the app after a successful update' -Prefix '      ' -Color $script:Ui.Dim
    }
    elseif ($state.DefaultAction -eq 'DownloadLatest') {
        Write-UiTextLine -Text '- Current folder will be refreshed in place from GitHub' -Prefix '      ' -Color $script:Ui.Dim
        Write-UiTextLine -Text '- The launcher will show update progress and relaunch the updated app' -Prefix '      ' -Color $script:Ui.Dim
        if ($state.Mode -eq 'Repo copy') {
            Write-UiTextLine -Text '- Repo-copy defaults follow the currently checked-out git branch' -Prefix '      ' -Color $script:Ui.Dim
        }
    }
    elseif ($state.InstallerMode -eq 'Local') {
        Write-UiTextLine -Text '- Installed copy under %LOCALAPPDATA% will be updated from the recorded local source' -Prefix '      ' -Color $script:Ui.Dim
        Write-UiTextLine -Text '- A successful update will save that Local/GitHub choice for next time' -Prefix '      ' -Color $script:Ui.Dim
        Write-UiTextLine -Text '- The launcher will show update progress and relaunch the updated app' -Prefix '      ' -Color $script:Ui.Dim
        Write-UiTextLine -Text '- Use E if you want the full InstallerCore menu for GitHub/source switching' -Prefix '      ' -Color $script:Ui.Dim
    }
    else {
        Write-UiTextLine -Text '- Installed copy under %LOCALAPPDATA% will be updated from GitHub' -Prefix '      ' -Color $script:Ui.Dim
        Write-UiTextLine -Text '- A successful update will save the chosen GitHub branch for next time' -Prefix '      ' -Color $script:Ui.Dim
        Write-UiTextLine -Text '- The launcher will show update progress and relaunch the updated app' -Prefix '      ' -Color $script:Ui.Dim
        Write-UiTextLine -Text '- Registry/verification paths stay under the normal InstallerCore update flow' -Prefix '      ' -Color $script:Ui.Dim
    }
    Write-Host ""

    $launchMode = Read-InstallerCoreUpdateChoice
    if ($launchMode -eq 'ESC') {
        Write-Host "  Cancelled." -ForegroundColor DarkGray
        return $script:SkipReturnToMenuToken
    }

    $pwshCmd = Get-Command pwsh.exe -ErrorAction SilentlyContinue
    $pwshExe = if ($null -ne $pwshCmd) { $pwshCmd.Source } else { Join-Path $PSHOME 'pwsh.exe' }
    if ($launchMode -eq 'EDIT') {
        Write-Host "`n  Opening the standard InstallerCore menu so you can choose Local/GitHub and branch options..." -ForegroundColor Yellow
        & $pwshExe -NoProfile -ExecutionPolicy Bypass -File $state.InstallScriptPath
        $exitCode = $LASTEXITCODE
    }
    elseif ($launchMode -eq 'DEFAULT' -and $state.DefaultAction -eq 'GitFastForward') {
        $progressMessage = 'Updating this git working copy with fetch + fast-forward...'
        Show-ToolUpdateProgressPanel -Message $progressMessage -Level 'Info' -RecentLines @("Branch: $($state.GitHubBranch)")
        $updateProcessResult = Invoke-GitWorkingCopyUpdateProcess -WorkingDirectory $PSScriptRoot -Branch $state.GitHubBranch
        $exitCode = [int]$updateProcessResult.ExitCode
        $recentLines = @($updateProcessResult.RecentLines)
    }
    else {
        $launcherArgs = @(
            '-NoProfile',
            '-ExecutionPolicy', 'Bypass',
            '-File', $state.InstallScriptPath,
            '-Action', $state.DefaultAction,
            '-Force'
        )

        if ($state.InstallerMode -eq 'Local' -and -not [string]::IsNullOrWhiteSpace($state.LocalSourcePath)) {
            $launcherArgs += @('-PackageSource', 'Local', '-SourcePath', $state.LocalSourcePath)
        }
        elseif ($state.InstallerMode -eq 'GitHub' -and -not [string]::IsNullOrWhiteSpace($state.GitHubBranch)) {
            $launcherArgs += @('-GitHubRef', $state.GitHubBranch)
        }

        if ($state.DefaultAction -eq 'DownloadLatest') {
            $launcherArgs += '-NoSelfRelaunch'
        }
        if ($state.Mode -eq 'Installed copy') {
            $launcherArgs += '-NoExplorerRestart'
        }

        $progressMessage = if ($state.DefaultAction -eq 'DownloadLatest') {
            'Updating this working copy inside the current app session...'
        }
        elseif ($state.InstallerMode -eq 'Local') {
            'Updating from the recorded local source inside the current app session...'
        }
        else {
            'Updating from GitHub inside the current app session...'
        }
        $installerLogPath = Join-Path $PSScriptRoot 'logs\installer.log'
        $updateProcessResult = Invoke-InstallerCoreUpdateProcess -PwshExe $pwshExe -ArgumentList $launcherArgs -WorkingDirectory $PSScriptRoot -ProgressMessage $progressMessage -InstallerLogPath $installerLogPath
        $exitCode = [int]$updateProcessResult.ExitCode
        $recentLines = @($updateProcessResult.RecentLines)
    }

    Write-Host ""
    $shouldRelaunchTool = ($launchMode -ne 'EDIT' -and ($exitCode -eq 0 -or $exitCode -eq 2))
    if ($shouldRelaunchTool) {
        if ($exitCode -eq 0) {
            Show-ToolUpdateProgressPanel -Message 'Update finished. Restarting the updated app host and closing this window...' -Level 'Good' -RecentLines $recentLines -AutoRestart
        }
        else {
            Show-ToolUpdateProgressPanel -Message 'Update finished with warnings. Restarting the updated app host and closing this window...' -Level 'Warn' -RecentLines $recentLines -AutoRestart
        }

        $launcherScriptPath = Join-Path (Split-Path -Path $state.InstallScriptPath -Parent) 'SystemCleanup.ps1'
        $restartExplorerToo = $false
        if ($state.Mode -eq 'Installed copy') {
            $postUpdateChoice = Read-PostUpdateRelaunchChoice
            $restartExplorerToo = ($postUpdateChoice -eq 'APP_AND_EXPLORER')
        }

        if ($restartExplorerToo) {
            Write-Host ''
            Write-Host '  Restarting Explorer shell before relaunching the updated app...' -ForegroundColor Yellow
            $null = Restart-ExplorerShellNoReopen
        }
        elseif ($state.Mode -eq 'Installed copy') {
            Write-Host ''
            Write-Host '  Relaunching the updated app without restarting Explorer...' -ForegroundColor Cyan
        }

        if (Start-SystemCleanupLauncherRelaunch -LauncherScriptPath $launcherScriptPath) {
            if ($restartExplorerToo) {
                Write-Host "  🔄 Restarting SystemCleanup with the updated files after the Explorer refresh..." -ForegroundColor Cyan
            }
            else {
                Write-Host "  🔄 Restarting SystemCleanup with the updated files..." -ForegroundColor Cyan
            }
            return $script:RelaunchAndExitToken
        }

        Write-Host "  ⚠️ Update finished, but the launcher restart could not be started automatically." -ForegroundColor Yellow
        Write-Host "     Start SystemCleanup again from the context menu to use the updated files." -ForegroundColor DarkGray
    }

    if ($exitCode -eq 0) {
        Write-Host "  ✅ Update flow completed successfully." -ForegroundColor Green
        return
    }
    if ($exitCode -eq 2) {
        Write-Host "  ⚠️ Update flow completed with warnings." -ForegroundColor Yellow
        return
    }

    if ($launchMode -ne 'EDIT') {
        Show-ToolUpdateProgressPanel -Message ("Update failed with exit code {0}." -f $exitCode) -Level 'Error' -RecentLines $recentLines
        return
    }

    Write-Host "  ❌ Update flow failed (exit code: $exitCode)." -ForegroundColor Red
}

function Set-DeliveryOptimizationDownloadModePolicy {
    param([int]$Mode = 0)

    $policyPath = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\DeliveryOptimization'
    if (-not (Test-Path -LiteralPath $policyPath)) {
        New-Item -Path $policyPath -Force -ErrorAction Stop | Out-Null
    }

    New-ItemProperty -Path $policyPath -Name 'DODownloadMode' -PropertyType DWord -Value $Mode -Force -ErrorAction Stop | Out-Null

    $readBack = Get-ItemProperty -Path $policyPath -Name 'DODownloadMode' -ErrorAction Stop
    if (-not $readBack.PSObject.Properties['DODownloadMode'] -or [int]$readBack.DODownloadMode -ne $Mode) {
        throw "Failed to verify DODownloadMode=$Mode."
    }
}

function Refresh-DeliveryOptimizationService {
    $serviceName = 'DoSvc'
    $svc = Get-Service -Name $serviceName -ErrorAction SilentlyContinue
    if ($null -eq $svc) {
        return $false
    }

    try {
        if ($svc.Status -eq 'Running') {
            Restart-Service -Name $serviceName -Force -ErrorAction Stop
        }
        else {
            Start-Service -Name $serviceName -ErrorAction Stop
        }
        return (Wait-ServiceState -Name $serviceName -DesiredStatus 'Running' -TimeoutSeconds 15)
    }
    catch {
        return $false
    }
}

function Invoke-DeliveryOptimizationCleanupAndDisable {
    $before = Get-DeliveryOptimizationState

    Show-SystemCleanupHeader -SectionTitle 'Delivery Optimization Cleanup + Disable' -SectionSubtitle 'Clear cache and force CDN-only mode'
    Write-UiTextLine -Text 'This will:' -Prefix '  ' -Color $script:Ui.Warn
    Write-UiTextLine -Text '- Clear Delivery Optimization cache with Delete-DeliveryOptimizationCache' -Prefix '      ' -Color $script:Ui.Dim
    Write-UiTextLine -Text '- Force DownloadMode = 0 (CdnOnly) to disable peer-to-peer sharing safely' -Prefix '      ' -Color $script:Ui.Dim
    Write-UiTextLine -Text '- Keep Windows Update / Store downloads working from Microsoft/CDN' -Prefix '      ' -Color $script:Ui.Dim
    Write-UiTextLine -Text '- Try to refresh the Delivery Optimization service' -Prefix '      ' -Color $script:Ui.Dim
    Write-Host ""

    if (-not $before.IsAvailable) {
        Write-Host "  ⚠️ Delivery Optimization cmdlets are unavailable on this machine." -ForegroundColor Red
        return
    }

    $statusLabel = if ($before.IsDisabled) {
        'DISABLED'
    }
    elseif ($before.StatusLabel -eq 'Enabled') {
        'ENABLED'
    }
    else {
        'UNKNOWN'
    }
    $statusColor = if ($before.IsDisabled) { $script:Ui.OK } else { $script:Ui.Warn }
    Write-UiKeyValue -Label 'Current status:' -Value $statusLabel -ValueColor $statusColor
    Write-UiKeyValue -Label 'Mode:' -Value $before.DownloadMode
    Write-UiKeyValue -Label 'Provider:' -Value $before.DownloadModeProvider
    Write-UiKeyValue -Label 'Cache size:' -Value $before.CacheSizeLabel
    Write-UiKeyValue -Label 'Cache files:' -Value ([string]$before.Files)
    if (-not [string]::IsNullOrWhiteSpace($before.WorkingDirectory)) {
        Write-UiKeyValue -Label 'Cache path:' -Value $before.WorkingDirectory
    }
    if ($null -ne $before.PolicyDownloadMode) {
        Write-UiKeyValue -Label 'Policy mode:' -Value ([string]$before.PolicyDownloadMode)
    }
    Write-Host ""

    $confirm = Read-EnterOrEscChoice -EnterLabel 'Run Delivery Optimization cleanup + disable' -EnterDescription 'Clear cache and apply the safe peer-disable policy' -EscLabel 'Back to main menu'
    if ($confirm -eq 'ESC') {
        Write-Host "  Cancelled." -ForegroundColor DarkGray
        return $script:SkipReturnToMenuToken
    }

    Write-Host "`n  Clearing Delivery Optimization cache..." -ForegroundColor Yellow
    try {
        Delete-DeliveryOptimizationCache -IncludePinnedFiles -Force -ErrorAction Stop | Out-Null
        Write-Host "  ✅ Delivery Optimization cache cleared." -ForegroundColor Green
    }
    catch {
        Write-Host "  ⚠️ Cache cleanup reported an error: $($_.Exception.Message)" -ForegroundColor Yellow
    }

    Write-Host "`n  Applying safe disable policy (DODownloadMode = 0)..." -ForegroundColor Yellow
    try {
        Set-DeliveryOptimizationDownloadModePolicy -Mode 0
        Write-Host "  ✅ Delivery Optimization policy set to CdnOnly." -ForegroundColor Green
    }
    catch {
        Write-Host "  ❌ Failed to set Delivery Optimization policy: $($_.Exception.Message)" -ForegroundColor Red
        return
    }

    Write-Host "`n  Refreshing Delivery Optimization service..." -ForegroundColor Yellow
    if (Refresh-DeliveryOptimizationService) {
        Write-Host "  ✅ Delivery Optimization service refreshed." -ForegroundColor Green
    }
    else {
        Write-Host "  ⚠️ Could not confirm a clean DoSvc refresh." -ForegroundColor Yellow
        Write-Host "     A sign-out/reboot may be needed before Settings reflects the new policy." -ForegroundColor DarkGray
    }

    $after = Get-DeliveryOptimizationState
    Write-Host ""
    Write-Host "  Final status: " -ForegroundColor White -NoNewline
    if ($after.IsDisabled) {
        Write-Host "DISABLED ✅" -ForegroundColor Green
    }
    elseif ($after.StatusLabel -eq 'Enabled') {
        Write-Host "ENABLED ⚠️" -ForegroundColor Yellow
    }
    else {
        Write-Host "UNKNOWN ⚠️" -ForegroundColor Yellow
    }
    Write-Host '      ⚙️  Mode:       ' -ForegroundColor DarkGray -NoNewline
    Write-Host $after.DownloadMode -ForegroundColor Green
    Write-Host '      🧩 Provider:   ' -ForegroundColor DarkGray -NoNewline
    Write-Host $after.DownloadModeProvider -ForegroundColor Green
    Write-Host '      💾 Cache size: ' -ForegroundColor DarkGray -NoNewline
    Write-Host $after.CacheSizeLabel -ForegroundColor Green
    if ($null -ne $after.PolicyDownloadMode) {
        Write-Host '      🛡️  Policy mode:' -ForegroundColor DarkGray -NoNewline
        Write-Host (" {0}" -f $after.PolicyDownloadMode) -ForegroundColor Green
    }
    Write-Host ""
    Write-Host "  💡 Safe disable here means peer-to-peer Delivery Optimization is off." -ForegroundColor Cyan
    Write-Host "     Windows can still download updates/apps directly from Microsoft/CDN." -ForegroundColor DarkGray
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
    
    Write-Host ''
    Write-UiTextLine -Text $Header -Prefix '  ' -Color $script:Ui.H1
    Write-UiRule
    
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
        $sizeLabel = if ($sizeMB -gt 0) { " - ${sizeMB} MB" } else { '' }
        Write-UiTextLine -Text ("[$idx] $title$kb$sizeLabel") -Prefix '    ' -Color $script:Ui.White
    }
    Write-UiRule
    return $true
}

# ─────────────────────────────────────────────
# 🔵 ACTION: Hide Update(s)
# ─────────────────────────────────────────────
function Hide-SelectedUpdates {
    # ⚠️ Workflow warning — hiding only works reliably on a fresh update list
    Write-Host "" 
    Write-UiTextLine -Text 'CORRECT WORKFLOW TO PERMANENTLY HIDE UPDATES:' -Prefix '  ' -Color $script:Ui.Warn
    Write-UiTextLine -Text '1. Reset Update Cache [5]' -Prefix '     ' -Color $script:Ui.Warn
    Write-UiTextLine -Text '2. REBOOT your PC' -Prefix '     ' -Color $script:Ui.Warn
    Write-UiTextLine -Text '3. Come back here and Hide Updates [2]' -Prefix '     ' -Color $script:Ui.Warn
    Write-UiTextLine -Text 'If you hide first and then reset, the hidden flag gets wiped and the update will reappear.' -Prefix '  ' -Color $script:Ui.Warn
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

    Write-UiTextLine -Text $Title -Prefix '  ' -Color $script:Ui.H1
    Write-UiRule

    if (-not $Info -or -not $Info.Succeeded) {
        $message = if ($Info -and -not [string]::IsNullOrWhiteSpace($Info.ErrorMessage)) {
            $Info.ErrorMessage
        }
        else {
            'Could not read DISM component store status.'
        }
        Write-UiTextLine -Text $message -Prefix '     ' -Color $script:Ui.Warn
        return
    }

    Write-UiKeyValue -Label 'Reclaimable packages:' -Value $Info.ReclaimablePackages -ValueColor $script:Ui.Dim
    Write-UiKeyValue -Label 'Backups/features:' -Value $Info.BackupsAndDisabledFeatures -ValueColor $script:Ui.Dim
    Write-UiKeyValue -Label 'Cleanup recommended:' -Value $Info.CleanupRecommended -ValueColor $script:Ui.Dim
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

    Show-SystemCleanupHeader -SectionTitle 'Live SoftwareDistribution Cleanup' -SectionSubtitle 'Clean the live Download cache safely'
    Write-UiTextLine -Text 'This will:' -Prefix '  ' -Color $script:Ui.Warn
    Write-UiTextLine -Text '- Stop update services temporarily' -Prefix '      ' -Color $script:Ui.Dim
    Write-UiTextLine -Text '- Clean the live SoftwareDistribution\Download cache' -Prefix '      ' -Color $script:Ui.Dim
    Write-UiTextLine -Text '- Keep DataStore / update history intact' -Prefix '      ' -Color $script:Ui.Dim
    Write-UiTextLine -Text '- Restart services' -Prefix '      ' -Color $script:Ui.Dim
    Write-Host ""
    Write-UiTextLine -Text 'Use this after updates to reclaim disk space.' -Prefix '  ' -Color $script:Ui.H1
    Write-UiTextLine -Text 'For hide/troubleshooting workflow, keep using [5] Reset Update Cache.' -Prefix '     ' -Color $script:Ui.Dim
    Write-Host ""

    if (-not (Test-Path -LiteralPath $downloadPath)) {
        Write-Host "  ℹ️ $downloadPath not found." -ForegroundColor DarkGray
        return
    }

    $beforeSizeMB = Get-DirectorySizeMB -Path $downloadPath
    Write-Host "  Current Download cache size: $beforeSizeMB MB" -ForegroundColor Gray
    Write-Host ""

    $confirm = Read-EnterOrEscChoice -EnterLabel 'Run Live SoftwareDistribution cleanup' -EnterDescription 'Clean the live Download cache and restart services safely' -EscLabel 'Back to main menu'
    if ($confirm -eq 'ESC') {
        Write-Host "  Cancelled." -ForegroundColor DarkGray
        return $script:SkipReturnToMenuToken
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
    Write-UiRule
    Write-UiTextLine -Text 'This will:' -Prefix '  ' -Color $script:Ui.Warn
    Write-UiTextLine -Text ("- Run Disk Cleanup Utility: cleanmgr /sagerun:{0}" -f $slot) -Prefix '      ' -Color $script:Ui.Dim
    Write-UiTextLine -Text '- Clean superseded WinSxS / component store update leftovers' -Prefix '      ' -Color $script:Ui.Dim
    Write-UiTextLine -Text '- May also scavenge WinSxS\Temp\PendingDeletes leftovers' -Prefix '      ' -Color $script:Ui.Dim
    Write-UiTextLine -Text '- Leave live SoftwareDistribution alone' -Prefix '      ' -Color $script:Ui.Dim
    Write-Host ""
    Write-UiTextLine -Text 'Best used after Windows Updates are installed and the PC has rebooted.' -Prefix '  ' -Color $script:Ui.H1
    Write-UiTextLine -Text 'Use this for extra post-update disk cleanup, not for hide/reset troubleshooting.' -Prefix '     ' -Color $script:Ui.Dim
    Write-Host ""

    $beforeInfo = Get-ComponentStoreCleanupInfo
    Show-ComponentStoreCleanupInfo -Info $beforeInfo -Title 'Current component store status'
    Write-Host ""
    if (-not [string]::IsNullOrWhiteSpace($debugLogPath)) {
        Write-UiTextLine -Text "Debug log: $debugLogPath" -Prefix '  ' -Color $script:Ui.Dim
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
    
    Write-UiTextLine -Text 'This will:' -Prefix '  ' -Color $script:Ui.Warn
    Write-UiTextLine -Text '- Stop core update services and try to quiet update orchestrators' -Prefix '      ' -Color $script:Ui.Dim
    Write-UiTextLine -Text '- Delete any existing .old backup folders first' -Prefix '      ' -Color $script:Ui.Dim
    Write-UiTextLine -Text '- Rename SoftwareDistribution and catroot2 folders' -Prefix '      ' -Color $script:Ui.Dim
    Write-UiTextLine -Text '- Restart services' -Prefix '      ' -Color $script:Ui.Dim
    Write-Host ""
    Write-UiTextLine -Text 'After reset, REBOOT, then use [2] Hide Updates on the fresh list.' -Prefix '  ' -Color $script:Ui.H1
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
    Write-UiTextLine -Text 'NEXT STEPS:' -Prefix '  ' -Color $script:Ui.H1
    Write-UiTextLine -Text '1. REBOOT your PC now' -Prefix '     ' -Color $script:Ui.H1
    Write-UiTextLine -Text '2. After reboot, open this tool again' -Prefix '     ' -Color $script:Ui.H1
    Write-UiTextLine -Text '3. Use [2] Hide Updates on the fresh update list' -Prefix '     ' -Color $script:Ui.H1
    Write-UiTextLine -Text 'The .old backup folders will be auto-cleaned on the next reset, or use [6] to clean them manually.' -Prefix '  ' -Color $script:Ui.Dim
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
        Write-UiKeyValue -Label 'Current status:' -Value 'POLICY ACTIVE' -ValueColor $script:Ui.OK
        Write-UiTextLine -Text 'Windows 11 feature upgrade is currently blocked via policy.' -Prefix '  ' -Color $script:Ui.Dim
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
        if ($state.StatusLabel -eq 'Policy mismatch') {
            Write-UiKeyValue -Label 'Current status:' -Value 'POLICY MISMATCH' -ValueColor $script:Ui.Warn
            Write-UiTextLine -Text 'The registry contains partial/invalid Win11 block values.' -Prefix '  ' -Color $script:Ui.Dim
            Write-UiKeyValue -Label 'TargetReleaseVersion:' -Value $state.TargetReleaseVersion -ValueColor $script:Ui.Dim
            Write-UiKeyValue -Label 'TargetReleaseInfo:' -Value $state.TargetReleaseVersionInfo -ValueColor $script:Ui.Dim
            Write-UiKeyValue -Label 'ProductVersion:' -Value $state.ProductVersion -ValueColor $script:Ui.Dim
            Write-UiKeyValue -Label 'Expected target:' -Value $state.ExpectedTargetReleaseVersionInfo -ValueColor $script:Ui.Dim
        }
        else {
            Write-UiKeyValue -Label 'Current status:' -Value 'NOT CONFIGURED' -ValueColor $script:Ui.Warn
            Write-UiTextLine -Text 'Windows Update may offer Windows 11 if your hardware is compatible.' -Prefix '  ' -Color $script:Ui.Dim
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
$skipReturnToMenu = $false
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
    'DeliveryOptimizationStatus' {
        Write-Output (Get-DeliveryOptimizationStatusLine)
        return
    }
    'ToolSelfUpdateStatus' {
        Write-Output (Get-InstallerCoreUpdateStatusLine)
        return
    }
    'DismFailureSummary' {
        Show-DismFailureSummary -Compact
        return
    }
    'DismFailureSummaryFull' {
        Show-DismFailureSummary
        return
    }
    'RepairSourceStatus' {
        $repairStatusExitCode = Invoke-RepairSourceStatus -RequestedPath $RepairIsoPath
        exit $repairStatusExitCode
    }
    'RepairRestoreHealth' {
        $repairExitCode = Invoke-RepairRestoreHealth -RequestedPath $RepairIsoPath
        exit $repairExitCode
    }
    'LiveCleanup' {
        $liveCleanupResult = Remove-LiveSoftwareDistributionDownload
        if ($liveCleanupResult -eq $script:SkipReturnToMenuToken) {
            $skipReturnToMenu = $true
            if ($SilentCaller) {
                Write-Output $script:SkipReturnToMenuToken
            }
        }
        $directActionCompleted = $true
    }
    'DeliveryOptimizationCleanup' {
        $deliveryOptimizationResult = Invoke-DeliveryOptimizationCleanupAndDisable
        if ($deliveryOptimizationResult -eq $script:SkipReturnToMenuToken) {
            $skipReturnToMenu = $true
            if ($SilentCaller) {
                Write-Output $script:SkipReturnToMenuToken
            }
        }
        $directActionCompleted = $true
    }
    'ToolSelfUpdate' {
        $toolSelfUpdateResult = Invoke-InstallerCoreToolUpdate
        if ($toolSelfUpdateResult -eq $script:SkipReturnToMenuToken) {
            $skipReturnToMenu = $true
            if ($SilentCaller) {
                Write-Output $script:SkipReturnToMenuToken
            }
        }
        elseif ($toolSelfUpdateResult -eq $script:RelaunchAndExitToken) {
            $skipReturnToMenu = $true
            if ($SilentCaller) {
                Write-Output $script:RelaunchAndExitToken
            }
        }
        $directActionCompleted = $true
    }
    'WindowsUpdateCleanup' {
        Invoke-WindowsUpdateCleanup
        $directActionCompleted = $true
    }
}

if ($directActionCompleted) {
    if (-not $SilentCaller -and -not $skipReturnToMenu) {
        Wait-ReturnToMenu
        Write-Host ""
    }
    return
}

$menuLoop = $true
while ($menuLoop) {
    Show-SystemCleanupHeader -SectionTitle 'Windows Update Manager' -SectionSubtitle 'Hide updates, reset cache, and block Windows 11'
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
    Write-UiRule
    Write-UiTextLine -Text 'WINDOWS UPDATE MANAGER' -Prefix '  ' -Color $script:Ui.White
    Write-UiRule
    Write-Host ""
    Write-UiTextLine -Text 'To permanently hide an update:' -Prefix '  ' -Color $script:Ui.Warn
    Write-UiTextLine -Text '[5] Reset Cache -> Reboot -> [2] Hide Updates' -Prefix '     ' -Color $script:Ui.Warn
    Write-Host ""
    Write-UiTextLine -Text '[1]  List Pending Updates' -Prefix '  ' -Color $script:Ui.White
    Write-UiTextLine -Text '[2]  Hide Update(s)' -Prefix '  ' -Color $script:Ui.Warn
    Write-UiTextLine -Text 'Block unwanted updates from appearing' -Prefix '       ' -Color $script:Ui.Dim
    Write-UiTextLine -Text '[3]  Show Hidden Updates' -Prefix '  ' -Color $script:Ui.White
    Write-UiTextLine -Text '[4]  Unhide Update(s)' -Prefix '  ' -Color $script:Ui.OK
    Write-UiTextLine -Text 'Restore previously hidden updates' -Prefix '       ' -Color $script:Ui.Dim
    Write-UiRule
    Write-UiTextLine -Text '[5]  Reset Update Cache' -Prefix '  ' -Color $script:Ui.Fail
    Write-UiTextLine -Text 'Reset SoftwareDistribution + catroot2' -Prefix '       ' -Color $script:Ui.Dim
    $oldFoldersStatus = Get-StaleOldFoldersStatusLine
    Write-UiTextLine -Text '[6]  Clean Stale Backup Folders' -Prefix '  ' -Color $script:Ui.H1
    Write-UiTextLine -Text $oldFoldersStatus -Prefix '       ' -Color $script:Ui.Dim
    Write-UiRule
    $win11AnsiColor = switch ($win11State.StatusLabel) {
        'Policy active' { $script:Ui.OK }
        'Policy mismatch' { $script:Ui.Warn }
        default { $script:Ui.Warn }
    }
    Write-UiTextLine -Text ("[7]  Block Windows 11 Upgrade [{0}]" -f $win11Status) -Prefix '  ' -Color $win11AnsiColor
    Write-UiTextLine -Text 'Pin this PC to Windows 10 via Group Policy' -Prefix '       ' -Color $script:Ui.Dim
    Write-UiRule
    Write-UiTextLine -Text '[ESC] Back to main menu' -Prefix '  ' -Color $script:Ui.Dim
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
