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
$script:AppName = 'SystemCleanup'
$script:AppVersion = '1.0.0'
$script:AppGitHubRepo = 'joty79/SystemCleanup'
$script:AppMetadataPath = Join-Path $PSScriptRoot 'app-metadata.json'
$script:StatePath = Join-Path $PSScriptRoot 'state'
$script:AppUpdateStatusCachePath = Join-Path $script:StatePath 'app-update-status.json'
$script:AppUpdateStatusCacheTtlMinutes = 30
$script:CachedLiveDownloadCacheLine = $null
$script:CachedDeliveryOptimizationLine = $null
$script:SkipReturnToMenuToken = '__SYSTEMCLEANUP_SKIP_RETURN_TO_MENU__'
$script:RelaunchAndExitToken = '__SYSTEMCLEANUP_RELAUNCH_AND_EXIT__'
$script:MainMenuIndex = 0
$script:LastWindowWidth = 0
$script:LastWindowHeight = 0
$script:PwshExe = if (Get-Command pwsh.exe -ErrorAction SilentlyContinue) {
    (Get-Command pwsh.exe -ErrorAction SilentlyContinue).Source
}
else {
    Join-Path $PSHOME 'pwsh.exe'
}
$script:E = [char]27
$script:C = @{
    H1      = "$($script:E)[38;2;90;180;240m"
    H2      = "$($script:E)[38;2;140;160;180m"
    Accent  = "$($script:E)[38;2;180;120;255m"
    OK      = "$($script:E)[38;2;46;204;113m"
    Warn    = "$($script:E)[38;2;241;196;15m"
    Fail    = "$($script:E)[38;2;231;76;60m"
    Info    = "$($script:E)[38;2;52;152;219m"
    Gold    = "$($script:E)[38;2;243;156;18m"
    White   = "$($script:E)[38;2;220;225;230m"
    Dim     = "$($script:E)[38;2;100;110;120m"
    SelBg   = "$($script:E)[48;2;40;80;120m"
    SelFg   = "$($script:E)[38;2;255;255;255m"
    Bold    = "$($script:E)[1m"
    Reset   = "$($script:E)[0m"
    EraseLn = "$($script:E)[K"
}
$script:AppUpdateStatus = [pscustomobject]@{
    LocalVersion    = $script:AppVersion
    LatestVersion   = ''
    LocalCommit     = ''
    LatestCommit    = ''
    SourceKind      = 'Unknown'
    HasLocalChanges = $false
    Repo            = $script:AppGitHubRepo
    Branch          = ''
    Status          = 'Unknown'
    IsKnown         = $false
    IsUpToDate      = $false
    Message         = 'Update status has not been checked yet.'
    CheckedAt       = ''
    Error           = ''
}
function Ensure-Directory {
    param([string]$Path)
    if (-not (Test-Path -LiteralPath $Path)) {
        New-Item -Path $Path -ItemType Directory -Force -ErrorAction Stop | Out-Null
    }
}

function Read-JsonFile {
    param([Parameter(Mandatory)][string]$Path)

    Get-Content -LiteralPath $Path -Raw -ErrorAction Stop | ConvertFrom-Json -Depth 50
}

function Save-JsonFile {
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][object]$InputObject
    )

    $parentPath = Split-Path -Path $Path -Parent
    if (-not [string]::IsNullOrWhiteSpace($parentPath)) {
        Ensure-Directory -Path $parentPath
    }

    $json = $InputObject | ConvertTo-Json -Depth 50
    [System.IO.File]::WriteAllText($Path, $json + [Environment]::NewLine, [System.Text.UTF8Encoding]::new($false))
}

function ConvertTo-NormalizedAppVersion {
    param(
        [AllowEmptyString()]
        [string]$VersionText
    )

    if ([string]::IsNullOrWhiteSpace($VersionText)) {
        return $null
    }

    try {
        return [version]$VersionText.Trim()
    }
    catch {
        return $null
    }
}

function Get-OptionalObjectPropertyValue {
    param(
        [object]$InputObject,
        [string]$PropertyName,
        $DefaultValue = $null
    )

    if ($null -eq $InputObject -or [string]::IsNullOrWhiteSpace($PropertyName)) {
        return $DefaultValue
    }

    $property = $InputObject.PSObject.Properties[$PropertyName]
    if ($null -eq $property) {
        return $DefaultValue
    }

    return $property.Value
}

function Get-ShortGitCommitText {
    param(
        [AllowEmptyString()]
        [string]$Commit
    )

    if ([string]::IsNullOrWhiteSpace($Commit)) {
        return ''
    }

    $normalizedCommit = $Commit.Trim()
    if ($normalizedCommit.Length -le 7) {
        return $normalizedCommit
    }

    return $normalizedCommit.Substring(0, 7)
}

function Get-CurrentAppSourceInfo {
    $result = [ordered]@{
        Commit          = ''
        SourceKind      = 'Unknown'
        HasLocalChanges = $false
    }

    $installMetaPath = Join-Path $PSScriptRoot 'state\install-meta.json'
    if (Test-Path -LiteralPath $installMetaPath -PathType Leaf) {
        try {
            $installMeta = Read-JsonFile -Path $installMetaPath
            $commit = [string](Get-OptionalObjectPropertyValue -InputObject $installMeta -PropertyName 'github_commit' -DefaultValue '')
            if (-not [string]::IsNullOrWhiteSpace($commit)) {
                $result.Commit = $commit.Trim()
                $result.SourceKind = 'Installed'
                return [pscustomobject]$result
            }
        }
        catch {
        }
    }

    if (Get-Command git.exe -ErrorAction SilentlyContinue) {
        try {
            $inside = (& git.exe -C $PSScriptRoot rev-parse --is-inside-work-tree 2>$null | Out-String).Trim()
            if ($inside -eq 'true') {
                $commit = (& git.exe -C $PSScriptRoot rev-parse HEAD 2>$null | Out-String).Trim()
                if (-not [string]::IsNullOrWhiteSpace($commit)) {
                    $dirty = (& git.exe -C $PSScriptRoot status --porcelain 2>$null | Out-String).Trim()
                    $result.Commit = $commit
                    $result.SourceKind = 'Workspace'
                    $result.HasLocalChanges = (-not [string]::IsNullOrWhiteSpace($dirty))
                    return [pscustomobject]$result
                }
            }
        }
        catch {
        }
    }

    return [pscustomobject]$result
}

function Get-CurrentAppSourceCommit {
    $sourceInfo = Get-CurrentAppSourceInfo
    return [string]$sourceInfo.Commit
}

function Test-LocalGitCommitContainsRemoteCommit {
    param(
        [AllowEmptyString()]
        [string]$RemoteCommit,
        [AllowEmptyString()]
        [string]$LocalCommit
    )

    if (
        [string]::IsNullOrWhiteSpace($RemoteCommit) -or
        [string]::IsNullOrWhiteSpace($LocalCommit) -or
        -not (Get-Command git.exe -ErrorAction SilentlyContinue)
    ) {
        return $false
    }

    try {
        & git.exe -C $PSScriptRoot merge-base --is-ancestor $RemoteCommit $LocalCommit 2>$null
        return ($LASTEXITCODE -eq 0)
    }
    catch {
        return $false
    }
}

function New-AppUpdateStatusObject {
    param(
        [string]$LocalVersion = $script:AppVersion,
        [AllowEmptyString()]
        [string]$LatestVersion = '',
        [AllowEmptyString()]
        [string]$LocalCommit = '',
        [AllowEmptyString()]
        [string]$LatestCommit = '',
        [AllowEmptyString()]
        [string]$SourceKind = 'Unknown',
        [bool]$HasLocalChanges = $false,
        [AllowEmptyString()]
        [string]$Repo = $script:AppGitHubRepo,
        [AllowEmptyString()]
        [string]$Branch = '',
        [ValidateSet('Unknown', 'UpToDate', 'UpdateAvailable', 'LocalAhead', 'WorkspaceModified', 'Error')]
        [string]$Status = 'Unknown',
        [string]$Message = 'Update status has not been checked yet.',
        [AllowEmptyString()]
        [string]$CheckedAt = '',
        [AllowEmptyString()]
        [string]$Error = ''
    )

    $isKnown = $Status -in @('UpToDate', 'UpdateAvailable', 'LocalAhead', 'WorkspaceModified')
    [pscustomobject]@{
        LocalVersion  = $LocalVersion
        LatestVersion = $LatestVersion
        LocalCommit   = $LocalCommit
        LatestCommit  = $LatestCommit
        SourceKind    = $SourceKind
        HasLocalChanges = $HasLocalChanges
        Repo          = $Repo
        Branch        = $Branch
        Status        = $Status
        IsKnown       = $isKnown
        IsUpToDate    = ($Status -eq 'UpToDate')
        Message       = $Message
        CheckedAt     = $CheckedAt
        Error         = $Error
    }
}

function Initialize-AppMetadata {
    if (-not (Test-Path -LiteralPath $script:AppMetadataPath -PathType Leaf)) {
        return
    }

    try {
        $metadata = Read-JsonFile -Path $script:AppMetadataPath
    }
    catch {
        return
    }

    $appNameProperty = $metadata.PSObject.Properties['app_name']
    if ($null -ne $appNameProperty -and -not [string]::IsNullOrWhiteSpace([string]$appNameProperty.Value)) {
        $script:AppName = [string]$appNameProperty.Value
    }

    $versionProperty = $metadata.PSObject.Properties['version']
    if ($null -ne $versionProperty -and -not [string]::IsNullOrWhiteSpace([string]$versionProperty.Value)) {
        $script:AppVersion = [string]$versionProperty.Value
    }

    $repoProperty = $metadata.PSObject.Properties['github_repo']
    if ($null -ne $repoProperty -and -not [string]::IsNullOrWhiteSpace([string]$repoProperty.Value)) {
        $script:AppGitHubRepo = [string]$repoProperty.Value
    }

    $script:AppUpdateStatus = New-AppUpdateStatusObject -LocalVersion $script:AppVersion -Repo $script:AppGitHubRepo
}

function Get-AppUpdateStatusOverview {
    if ($null -eq $script:AppUpdateStatus) {
        $script:AppUpdateStatus = New-AppUpdateStatusObject
    }

    return $script:AppUpdateStatus
}

function Get-AppUpdateStatusPresentation {
    $status = Get-AppUpdateStatusOverview
    $label = 'Status unavailable'
    $color = $script:C.Dim
    $gitHubBranchLabel = if ([string]::IsNullOrWhiteSpace([string]$status.Branch)) { 'GitHub' } else { "GitHub $($status.Branch)" }

    switch ([string]$status.Status) {
        'UpToDate' {
            $label = "Up to date with $gitHubBranchLabel"
            $color = $script:C.OK
        }
        'UpdateAvailable' {
            if (
                -not [string]::IsNullOrWhiteSpace([string]$status.LatestVersion) -and
                [string]$status.LatestVersion -ne [string]$status.LocalVersion
            ) {
                $label = "Update available from $gitHubBranchLabel ($($status.LatestVersion))"
            }
            elseif (
                -not [string]::IsNullOrWhiteSpace([string]$status.LatestCommit) -and
                -not [string]::IsNullOrWhiteSpace([string]$status.LocalCommit) -and
                [string]$status.LatestCommit -ne [string]$status.LocalCommit
            ) {
                $label = "Update available from $gitHubBranchLabel (newer commit)"
            }
            else {
                $label = "Update available from $gitHubBranchLabel"
            }
            $color = $script:C.Warn
        }
        'LocalAhead' {
            $label = "Workspace ahead of $gitHubBranchLabel"
            $color = $script:C.Info
        }
        'WorkspaceModified' {
            $label = 'Workspace has unpublished local changes'
            $color = $script:C.Info
        }
        'Error' {
            $label = 'Update check failed'
            $color = $script:C.Fail
        }
    }

    [pscustomobject]@{
        Label         = $label
        Color         = $color
        LatestVersion = [string]$status.LatestVersion
        LocalVersion  = [string]$status.LocalVersion
        LatestCommit  = [string]$status.LatestCommit
        LocalCommit   = [string]$status.LocalCommit
        SourceKind    = [string]$status.SourceKind
        HasLocalChanges = [bool]$status.HasLocalChanges
        Repo          = [string]$status.Repo
        Branch        = [string]$status.Branch
        Message       = [string]$status.Message
        CheckedAt     = [string]$status.CheckedAt
        Status        = [string]$status.Status
    }
}

function Read-AppUpdateStatusCache {
    param(
        [switch]$AllowStale
    )

    if (-not (Test-Path -LiteralPath $script:AppUpdateStatusCachePath -PathType Leaf)) {
        return $null
    }

    try {
        $cache = Read-JsonFile -Path $script:AppUpdateStatusCachePath
    }
    catch {
        return $null
    }

    if (-not $AllowStale) {
        $checkedAtProperty = $cache.PSObject.Properties['CheckedAt']
        $checkedAtText = if ($null -ne $checkedAtProperty) { [string]$checkedAtProperty.Value } else { '' }
        $checkedAt = [datetime]::MinValue
        if ([string]::IsNullOrWhiteSpace($checkedAtText) -or -not [datetime]::TryParse($checkedAtText, [ref]$checkedAt)) {
            return $null
        }

        $age = (Get-Date) - $checkedAt
        if ($age.TotalMinutes -gt $script:AppUpdateStatusCacheTtlMinutes) {
            return $null
        }
    }

    $cachedStatus = [string](Get-OptionalObjectPropertyValue -InputObject $cache -PropertyName 'Status' -DefaultValue '')
    if (-not $AllowStale -and $cachedStatus -eq 'UpToDate') {
        return $null
    }

    $localCommitProperty = $cache.PSObject.Properties['LocalCommit']
    $latestCommitProperty = $cache.PSObject.Properties['LatestCommit']
    $sourceKindProperty = $cache.PSObject.Properties['SourceKind']
    $hasLocalChangesProperty = $cache.PSObject.Properties['HasLocalChanges']
    if ($null -eq $localCommitProperty -or $null -eq $latestCommitProperty -or $null -eq $sourceKindProperty) {
        return $null
    }

    $localCommit = if ($null -ne $localCommitProperty) { [string]$localCommitProperty.Value } else { '' }
    $latestCommit = if ($null -ne $latestCommitProperty) { [string]$latestCommitProperty.Value } else { '' }
    $sourceKind = if ($null -ne $sourceKindProperty) { [string]$sourceKindProperty.Value } else { 'Unknown' }
    $hasLocalChanges = if ($null -ne $hasLocalChangesProperty) { [bool]$hasLocalChangesProperty.Value } else { $false }
    $currentSourceInfo = Get-CurrentAppSourceInfo
    if ([string]$cache.LocalVersion -ne [string]$script:AppVersion) {
        return $null
    }
    if ([string]$currentSourceInfo.SourceKind -ne $sourceKind) {
        return $null
    }
    if ([bool]$currentSourceInfo.HasLocalChanges -ne $hasLocalChanges) {
        return $null
    }
    if (
        -not [string]::IsNullOrWhiteSpace([string]$currentSourceInfo.Commit) -and
        -not [string]::IsNullOrWhiteSpace($localCommit) -and
        [string]$currentSourceInfo.Commit -ne $localCommit
    ) {
        return $null
    }

    return (New-AppUpdateStatusObject `
        -LocalVersion ([string]$cache.LocalVersion) `
        -LatestVersion ([string]$cache.LatestVersion) `
        -LocalCommit $localCommit `
        -LatestCommit $latestCommit `
        -SourceKind $sourceKind `
        -HasLocalChanges $hasLocalChanges `
        -Repo ([string]$cache.Repo) `
        -Branch ([string]$cache.Branch) `
        -Status ([string]$cache.Status) `
        -Message ([string]$cache.Message) `
        -CheckedAt ([string]$cache.CheckedAt) `
        -Error ([string]$cache.Error))
}

function Write-AppUpdateStatusCache {
    param(
        [Parameter(Mandatory)]
        [object]$Status
    )

    try {
        Save-JsonFile -Path $script:AppUpdateStatusCachePath -InputObject $Status
    }
    catch {
    }
}

function Get-AppGitHubApiHeaders {
    $headers = @{
        'User-Agent' = "$($script:AppName)/$($script:AppVersion)"
    }

    if (-not [string]::IsNullOrWhiteSpace($env:GITHUB_TOKEN)) {
        $headers['Authorization'] = "Bearer $($env:GITHUB_TOKEN)"
    }

    return $headers
}

function ConvertTo-GitHubRepoSlugFromRemoteUrl {
    param(
        [AllowEmptyString()]
        [string]$RemoteUrl
    )

    if ([string]::IsNullOrWhiteSpace($RemoteUrl)) {
        return ''
    }

    $match = [regex]::Match($RemoteUrl.Trim(), 'github\.com[:/](?<owner>[^/]+)/(?<repo>[^/#?]+?)(?:\.git)?(?:[/#?].*)?$', [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)
    if (-not $match.Success) {
        return ''
    }

    return ('{0}/{1}' -f $match.Groups['owner'].Value, $match.Groups['repo'].Value).ToLowerInvariant()
}

function Get-AppGitRemoteTarget {
    param(
        [AllowEmptyString()]
        [string]$Repo = $script:AppGitHubRepo
    )

    if ([string]::IsNullOrWhiteSpace($Repo) -or -not (Get-Command git.exe -ErrorAction SilentlyContinue)) {
        return ''
    }

    $expectedRepo = $Repo.Trim().ToLowerInvariant()
    try {
        $inside = (& git.exe -C $PSScriptRoot rev-parse --is-inside-work-tree 2>$null | Out-String).Trim()
        if ($inside -eq 'true') {
            foreach ($remoteName in @(& git.exe -C $PSScriptRoot remote 2>$null)) {
                $name = [string]$remoteName
                if ([string]::IsNullOrWhiteSpace($name)) {
                    continue
                }

                $remoteUrl = (& git.exe -C $PSScriptRoot remote get-url $name 2>$null | Out-String).Trim()
                if ((ConvertTo-GitHubRepoSlugFromRemoteUrl -RemoteUrl $remoteUrl) -eq $expectedRepo) {
                    return $name.Trim()
                }
            }
        }
    }
    catch {
    }

    return ("https://github.com/{0}.git" -f $Repo.Trim())
}

function Resolve-RemoteAppCommit {
    param(
        [AllowEmptyString()]
        [string]$Repo = $script:AppGitHubRepo,
        [AllowEmptyString()]
        [string]$Ref = ''
    )

    if ([string]::IsNullOrWhiteSpace($Repo) -or [string]::IsNullOrWhiteSpace($Ref)) {
        return ''
    }

    if (Get-Command gh.exe -ErrorAction SilentlyContinue) {
        try {
            $commit = (& gh.exe api "repos/$Repo/commits/$Ref" --jq '.sha' 2>$null | Out-String).Trim()
            if (-not [string]::IsNullOrWhiteSpace($commit)) {
                return $commit
            }
        }
        catch {
        }
    }

    try {
        $headers = Get-AppGitHubApiHeaders
        $commitInfo = Invoke-RestMethod -Uri ("https://api.github.com/repos/{0}/commits/{1}" -f $Repo, $Ref) -Headers $headers -TimeoutSec 5 -ErrorAction Stop
        $commit = [string]$commitInfo.sha
        if (-not [string]::IsNullOrWhiteSpace($commit)) {
            return $commit
        }
    }
    catch {
    }

    $gitRemoteTarget = Get-AppGitRemoteTarget -Repo $Repo
    if (-not [string]::IsNullOrWhiteSpace($gitRemoteTarget) -and (Get-Command git.exe -ErrorAction SilentlyContinue)) {
        foreach ($candidateRef in @("refs/heads/$Ref", $Ref)) {
            try {
                $remoteLine = (& git.exe -C $PSScriptRoot ls-remote $gitRemoteTarget $candidateRef 2>$null | Select-Object -First 1 | Out-String).Trim()
                if (-not [string]::IsNullOrWhiteSpace($remoteLine)) {
                    $commit = ($remoteLine -split '\s+')[0]
                    if (-not [string]::IsNullOrWhiteSpace($commit)) {
                        return $commit
                    }
                }
            }
            catch {
            }
        }
    }

    return ''
}

function Get-RemoteAppMetadataFromGit {
    param(
        [AllowEmptyString()]
        [string]$Repo = $script:AppGitHubRepo,
        [Parameter(Mandatory)]
        [System.Collections.Generic.List[string]]$BranchCandidates,
        [Parameter(Mandatory)]
        [string]$MetadataRelativePath
    )

    if ([string]::IsNullOrWhiteSpace($Repo) -or -not (Get-Command git.exe -ErrorAction SilentlyContinue)) {
        return $null
    }

    $gitRemoteTarget = Get-AppGitRemoteTarget -Repo $Repo
    if ([string]::IsNullOrWhiteSpace($gitRemoteTarget)) {
        return $null
    }

    foreach ($branch in $BranchCandidates) {
        $latestCommit = ''
        try {
            $remoteLine = (& git.exe -C $PSScriptRoot ls-remote $gitRemoteTarget "refs/heads/$branch" 2>$null | Select-Object -First 1 | Out-String).Trim()
            if ([string]::IsNullOrWhiteSpace($remoteLine)) {
                continue
            }

            $latestCommit = ($remoteLine -split '\s+')[0]
        }
        catch {
            continue
        }

        $metadata = $null
        try {
            $inside = (& git.exe -C $PSScriptRoot rev-parse --is-inside-work-tree 2>$null | Out-String).Trim()
            if ($inside -eq 'true') {
                foreach ($treeRef in @($latestCommit, "refs/remotes/$gitRemoteTarget/$branch", "$gitRemoteTarget/$branch")) {
                    if ([string]::IsNullOrWhiteSpace($treeRef)) {
                        continue
                    }

                    try {
                        & git.exe -C $PSScriptRoot cat-file -e "$treeRef^{commit}" 2>$null
                        if ($LASTEXITCODE -ne 0) {
                            continue
                        }

                        $metadataJson = (& git.exe -C $PSScriptRoot show "$($treeRef):$MetadataRelativePath" 2>$null | Out-String).Trim()
                        if (-not [string]::IsNullOrWhiteSpace($metadataJson)) {
                            $metadata = $metadataJson | ConvertFrom-Json
                            break
                        }
                    }
                    catch {
                    }
                }
            }
        }
        catch {
        }

        if ($null -eq $metadata) {
            try {
                $sourceInfo = Get-CurrentAppSourceInfo
                if (
                    [string]$sourceInfo.SourceKind -eq 'Workspace' -and
                    -not [string]::IsNullOrWhiteSpace([string]$sourceInfo.Commit) -and
                    [string]$sourceInfo.Commit -eq $latestCommit -and
                    (Test-Path -LiteralPath $script:AppMetadataPath -PathType Leaf)
                ) {
                    $metadata = Read-JsonFile -Path $script:AppMetadataPath
                }
            }
            catch {
            }
        }

        if ($null -eq $metadata) {
            $tempRoot = Join-Path $env:TEMP ("SystemCleanup_update_metadata_{0}" -f [guid]::NewGuid().ToString('N'))
            try {
                & git.exe clone --quiet --depth 1 --branch $branch $gitRemoteTarget $tempRoot 2>$null
                if ($LASTEXITCODE -eq 0) {
                    $metadataPath = Join-Path $tempRoot ($MetadataRelativePath -replace '/', [System.IO.Path]::DirectorySeparatorChar)
                    if (Test-Path -LiteralPath $metadataPath -PathType Leaf) {
                        $metadata = Read-JsonFile -Path $metadataPath
                    }
                }
            }
            catch {
            }
            finally {
                if (Test-Path -LiteralPath $tempRoot) {
                    Remove-Item -LiteralPath $tempRoot -Recurse -Force -ErrorAction SilentlyContinue
                }
            }
        }

        if ($null -eq $metadata) {
            $metadata = [pscustomobject]@{
                version = ''
            }
        }

        return [pscustomobject]@{
            Repo          = $Repo
            Branch        = $branch
            DefaultBranch = ''
            Commit        = $latestCommit
            Metadata      = $metadata
        }
    }

    return $null
}

function Get-RemoteAppMetadata {
    param(
        [AllowEmptyString()]
        [string]$Repo = $script:AppGitHubRepo
    )

    if ([string]::IsNullOrWhiteSpace($Repo)) {
        return $null
    }

    $headers = Get-AppGitHubApiHeaders
    $defaultBranch = ''
    if (Get-Command gh.exe -ErrorAction SilentlyContinue) {
        try {
            $repoJson = (& gh.exe api "repos/$Repo" 2>$null | Out-String).Trim()
            if (-not [string]::IsNullOrWhiteSpace($repoJson)) {
                $repoInfo = $repoJson | ConvertFrom-Json
                $defaultBranch = [string]$repoInfo.default_branch
            }
        }
        catch {
        }
    }

    try {
        if ([string]::IsNullOrWhiteSpace($defaultBranch)) {
            $repoInfo = Invoke-RestMethod -Uri ("https://api.github.com/repos/{0}" -f $Repo) -Headers $headers -TimeoutSec 5 -ErrorAction Stop
            $defaultBranch = [string]$repoInfo.default_branch
        }
    }
    catch {
    }

    $metadataRelativePath = ($script:AppMetadataPath.Substring($PSScriptRoot.Length).TrimStart('\')).Replace('\', '/')
    $branchCandidates = [System.Collections.Generic.List[string]]::new()
    foreach ($candidate in @($defaultBranch, 'master', 'main', 'latest')) {
        if (-not [string]::IsNullOrWhiteSpace($candidate) -and -not $branchCandidates.Contains($candidate)) {
            $branchCandidates.Add($candidate)
        }
    }

    foreach ($branch in $branchCandidates) {
        if (Get-Command gh.exe -ErrorAction SilentlyContinue) {
            try {
                $contentJson = (& gh.exe api ("repos/{0}/contents/{1}?ref={2}" -f $Repo, $metadataRelativePath, $branch) 2>$null | Out-String).Trim()
                if (-not [string]::IsNullOrWhiteSpace($contentJson)) {
                    $contentInfo = $contentJson | ConvertFrom-Json
                    $encodedContent = [string]$contentInfo.content
                    if (-not [string]::IsNullOrWhiteSpace($encodedContent)) {
                        $normalizedBase64 = ($encodedContent -replace '\s', '')
                        $decodedJson = [System.Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($normalizedBase64))
                        $metadata = $decodedJson | ConvertFrom-Json
                        return [pscustomobject]@{
                            Repo          = $Repo
                            Branch        = $branch
                            DefaultBranch = $defaultBranch
                            Commit        = (Resolve-RemoteAppCommit -Repo $Repo -Ref $branch)
                            Metadata      = $metadata
                        }
                    }
                }
            }
            catch {
            }
        }

        $metadataUri = "https://raw.githubusercontent.com/{0}/{1}/{2}" -f $Repo, $branch, $metadataRelativePath
        try {
            $response = Invoke-WebRequest -Uri $metadataUri -Headers $headers -TimeoutSec 5 -ErrorAction Stop
            $metadata = $response.Content | ConvertFrom-Json
            return [pscustomobject]@{
                Repo          = $Repo
                Branch        = $branch
                DefaultBranch = $defaultBranch
                Commit        = (Resolve-RemoteAppCommit -Repo $Repo -Ref $branch)
                Metadata      = $metadata
            }
        }
        catch {
        }
    }

    $gitRemoteInfo = Get-RemoteAppMetadataFromGit -Repo $Repo -BranchCandidates $branchCandidates -MetadataRelativePath $metadataRelativePath
    if ($null -ne $gitRemoteInfo) {
        return $gitRemoteInfo
    }

    return $null
}

function Resolve-AppUpdateStatus {
    param(
        [switch]$ForceRefresh
    )

    if (-not $ForceRefresh) {
        $cachedStatus = Read-AppUpdateStatusCache
        if ($null -ne $cachedStatus) {
            $script:AppUpdateStatus = $cachedStatus
            return $script:AppUpdateStatus
        }
    }

    $staleCachedStatus = Read-AppUpdateStatusCache -AllowStale
    $remoteInfo = Get-RemoteAppMetadata
    if ($null -eq $remoteInfo) {
        if ($null -ne $staleCachedStatus -and [string]$staleCachedStatus.Status -ne 'UpToDate') {
            $staleCachedStatus.Message = 'Using cached update status because the latest version could not be reached.'
            $script:AppUpdateStatus = $staleCachedStatus
            return $script:AppUpdateStatus
        }

        $script:AppUpdateStatus = New-AppUpdateStatusObject -LocalVersion $script:AppVersion -Repo $script:AppGitHubRepo -Status 'Error' -Message 'Could not reach GitHub to check the latest version.' -CheckedAt ((Get-Date).ToString('s'))
        return $script:AppUpdateStatus
    }

    $metadata = $remoteInfo.Metadata
    $latestVersionProperty = $metadata.PSObject.Properties['version']
    $latestVersion = if ($null -ne $latestVersionProperty) { [string]$latestVersionProperty.Value } else { '' }
    $sourceInfo = Get-CurrentAppSourceInfo
    $localCommit = [string]$sourceInfo.Commit
    $latestCommit = [string]$remoteInfo.Commit
    $sourceKind = [string]$sourceInfo.SourceKind
    $hasLocalChanges = [bool]$sourceInfo.HasLocalChanges

    $statusName = 'Unknown'
    $statusMessage = 'Update status is unavailable.'
    $localVersionObject = ConvertTo-NormalizedAppVersion -VersionText $script:AppVersion
    $remoteVersionObject = ConvertTo-NormalizedAppVersion -VersionText $latestVersion

    if ($sourceKind -eq 'Workspace' -and $hasLocalChanges) {
        $statusName = 'WorkspaceModified'
        $statusMessage = "This workspace has unpublished local changes. Local metadata is v$($script:AppVersion) at HEAD $(Get-ShortGitCommitText -Commit $localCommit); latest published GitHub $($remoteInfo.Branch) is v$latestVersion at $(Get-ShortGitCommitText -Commit $latestCommit)."
    }
    elseif ($sourceKind -eq 'Workspace' -and $localCommit -ne $latestCommit -and (Test-LocalGitCommitContainsRemoteCommit -RemoteCommit $latestCommit -LocalCommit $localCommit)) {
        $statusName = 'LocalAhead'
        $statusMessage = "This workspace has local commits not yet published to GitHub $($remoteInfo.Branch). Latest published commit is $(Get-ShortGitCommitText -Commit $latestCommit); local HEAD is $(Get-ShortGitCommitText -Commit $localCommit)."
    }
    elseif ($null -ne $localVersionObject -and $null -ne $remoteVersionObject) {
        if ($localVersionObject -lt $remoteVersionObject) {
            $statusName = 'UpdateAvailable'
            $statusMessage = "Update available from GitHub $($remoteInfo.Branch): v$latestVersion."
        }
        elseif ($localVersionObject -gt $remoteVersionObject) {
            $statusName = 'LocalAhead'
            $statusMessage = "Local version v$($script:AppVersion) is newer than the latest published GitHub $($remoteInfo.Branch) version v$latestVersion."
        }
        elseif (
            -not [string]::IsNullOrWhiteSpace($localCommit) -and
            -not [string]::IsNullOrWhiteSpace($latestCommit) -and
            $localCommit -ne $latestCommit
        ) {
            $statusName = 'UpdateAvailable'
            $statusMessage = "Update available from GitHub $($remoteInfo.Branch): v$latestVersion has commit $(Get-ShortGitCommitText -Commit $latestCommit); local is $(Get-ShortGitCommitText -Commit $localCommit)."
        }
        else {
            $statusName = 'UpToDate'
            $commitLabel = Get-ShortGitCommitText -Commit $latestCommit
            $statusMessage = if ([string]::IsNullOrWhiteSpace($commitLabel)) { "App is up to date with GitHub $($remoteInfo.Branch) at v$latestVersion." } else { "App is up to date with GitHub $($remoteInfo.Branch) at v$latestVersion ($commitLabel)." }
        }
    }
    elseif (-not [string]::IsNullOrWhiteSpace($latestVersion) -and $latestVersion -eq $script:AppVersion) {
        if (
            -not [string]::IsNullOrWhiteSpace($localCommit) -and
            -not [string]::IsNullOrWhiteSpace($latestCommit) -and
            $localCommit -ne $latestCommit
        ) {
            $statusName = 'UpdateAvailable'
            $statusMessage = "Update available from GitHub $($remoteInfo.Branch): v$latestVersion has commit $(Get-ShortGitCommitText -Commit $latestCommit); local is $(Get-ShortGitCommitText -Commit $localCommit)."
        }
        else {
            $statusName = 'UpToDate'
            $commitLabel = Get-ShortGitCommitText -Commit $latestCommit
            $statusMessage = if ([string]::IsNullOrWhiteSpace($commitLabel)) { "App is up to date with GitHub $($remoteInfo.Branch) at v$latestVersion." } else { "App is up to date with GitHub $($remoteInfo.Branch) at v$latestVersion ($commitLabel)." }
        }
    }

    $script:AppUpdateStatus = New-AppUpdateStatusObject `
        -LocalVersion $script:AppVersion `
        -LatestVersion $latestVersion `
        -LocalCommit $localCommit `
        -LatestCommit $latestCommit `
        -SourceKind $sourceKind `
        -HasLocalChanges $hasLocalChanges `
        -Repo ([string]$remoteInfo.Repo) `
        -Branch ([string]$remoteInfo.Branch) `
        -Status $statusName `
        -Message $statusMessage `
        -CheckedAt ((Get-Date).ToString('s'))

    Write-AppUpdateStatusCache -Status $script:AppUpdateStatus
    return $script:AppUpdateStatus
}



function Begin-SyncRender {
    [Console]::Write("$($script:E)[?2026h")
}

function End-SyncRender {
    [Console]::Write("$($script:E)[?2026l")
}

function Set-CursorVisibleSafe {
    param([bool]$Visible)

    try {
        [Console]::CursorVisible = $Visible
    }
    catch {
    }
}

function Clear-ConsoleInputBuffer {
    try {
        while ([Console]::KeyAvailable) {
            [void][Console]::ReadKey($true)
        }
    }
    catch {
    }
}

function Get-UiWidth {
    try {
        return [Math]::Min(110, $Host.UI.RawUI.WindowSize.Width - 2)
    }
    catch {
        return 88
    }
}

function Lock-ViewportToWindow {
    try {
        $windowSize = $Host.UI.RawUI.WindowSize
        if ($Host.UI.RawUI.BufferSize.Height -ne $windowSize.Height) {
            $Host.UI.RawUI.BufferSize = $windowSize
        }
    }
    catch {
    }
}

function Test-WindowResized {
    try {
        $width = $Host.UI.RawUI.WindowSize.Width
        $height = $Host.UI.RawUI.WindowSize.Height
    }
    catch {
        return $false
    }

    if ($width -ne $script:LastWindowWidth -or $height -ne $script:LastWindowHeight) {
        $script:LastWindowWidth = $width
        $script:LastWindowHeight = $height
        return $true
    }

    return $false
}

function Write-Banner {
    $width = Get-UiWidth
    $border = [string]::new([char]0x2550, ($width - 2))
    $titleText = " $($script:AppName) v$($script:AppVersion)"
    $subtitleText = ' Repair + Update + Cache Cleanup'
    $updateStatus = Get-AppUpdateStatusPresentation
    $updateText = " Update: $($updateStatus.Label)"
    $titlePad = [Math]::Max(0, $width - 2 - $titleText.Length)
    $subtitlePad = [Math]::Max(0, $width - 2 - $subtitleText.Length)
    $updatePad = [Math]::Max(0, $width - 2 - $updateText.Length)

    Write-Host ''
    Write-Host "$($script:C.H1)$([char]0x2554)$border$([char]0x2557)$($script:C.Reset)"
    Write-Host "$($script:C.H1)$([char]0x2551)$($script:C.Bold)$($script:C.White)$titleText$($script:C.Reset)$(' ' * $titlePad)$($script:C.H1)$([char]0x2551)$($script:C.Reset)"
    Write-Host "$($script:C.H1)$([char]0x2551)$($script:C.Dim)$subtitleText$($script:C.Reset)$(' ' * $subtitlePad)$($script:C.H1)$([char]0x2551)$($script:C.Reset)"
    Write-Host "$($script:C.H1)$([char]0x2551)$($updateStatus.Color)$updateText$($script:C.Reset)$(' ' * $updatePad)$($script:C.H1)$([char]0x2551)$($script:C.Reset)"
    Write-Host "$($script:C.H1)$([char]0x255A)$border$([char]0x255D)$($script:C.Reset)"
    Write-Host ''
}

function Write-Section {
    param([string]$Title)

    $width = Get-UiWidth
    $prefix = " $([char]0x25C6) $Title "
    $remaining = [Math]::Max(0, $width - $prefix.Length - 1)
    $line = [string]::new([char]0x2500, $remaining)
    Write-Host "$($script:C.H1)$prefix$($script:C.Dim)$line$($script:C.Reset)"
}

function Show-SubmenuHeader {
    param(
        [Parameter(Mandatory)][string]$Title,
        [AllowEmptyString()][string]$Subtitle = ''
    )

    try {
        Clear-Host
    }
    catch {
    }

    Write-Banner
    Write-Section $Title
    if (-not [string]::IsNullOrWhiteSpace($Subtitle)) {
        Write-Host "  $($script:C.Dim)$Subtitle$($script:C.Reset)"
    }
    Write-Host ''
}

function Request-LauncherExit {
    try {
        $Host.SetShouldExit(0)
    }
    catch {
    }
}

function Get-NormalizedConsoleKeyName {
    param(
        [AllowEmptyString()]
        [string]$KeyName,
        [int]$VirtualKeyCode = 0,
        [char]$KeyChar = [char]0
    )

    if ($VirtualKeyCode -eq 27) { return 'Escape' }
    if ($VirtualKeyCode -eq 13) { return 'Enter' }
    if ($VirtualKeyCode -eq 38) { return 'UpArrow' }
    if ($VirtualKeyCode -eq 40) { return 'DownArrow' }
    if ([int][char]$KeyChar -eq 27) { return 'Escape' }
    if ([int][char]$KeyChar -eq 13) { return 'Enter' }

    switch ($KeyName) {
        'Esc' { return 'Escape' }
        'Return' { return 'Enter' }
        default { return $KeyName }
    }
}

function Read-ConsoleKey {
    Set-CursorVisibleSafe -Visible $false

    try {
        while (-not [Console]::KeyAvailable) {
            if (Test-WindowResized) {
                return [pscustomobject]@{
                    Key            = 'ResizeEvent'
                    KeyChar        = [char]0
                    VirtualKeyCode = 0
                }
            }

            Start-Sleep -Milliseconds 40
        }
    }
    catch {
    }

    try {
        $keyInfo = $Host.UI.RawUI.ReadKey('NoEcho,IncludeKeyDown')
    }
    catch {
        $keyInfo = [Console]::ReadKey($true)
    }

    $keyName = $null
    $keyChar = [char]0
    $virtualKeyCode = $null

    if ($keyInfo.PSObject.Properties['Key']) {
        $keyName = [string]$keyInfo.Key
    }
    elseif ($keyInfo.PSObject.Properties['VirtualKeyCode']) {
        $virtualKeyCode = [int]$keyInfo.VirtualKeyCode
        try {
            $keyName = [string][System.Enum]::ToObject([System.ConsoleKey], $virtualKeyCode)
        }
        catch {
            $keyName = [string]$virtualKeyCode
        }
    }

    if ($keyInfo.PSObject.Properties['KeyChar']) {
        $keyChar = [char]$keyInfo.KeyChar
    }
    elseif ($keyInfo.PSObject.Properties['Character']) {
        $keyChar = [char]$keyInfo.Character
    }

    if ($null -eq $virtualKeyCode -and $keyInfo.PSObject.Properties['VirtualKeyCode']) {
        $virtualKeyCode = [int]$keyInfo.VirtualKeyCode
    }

    $keyName = Get-NormalizedConsoleKeyName -KeyName $keyName -VirtualKeyCode $virtualKeyCode -KeyChar $keyChar

    [pscustomobject]@{
        Key            = $keyName
        KeyChar        = $keyChar
        VirtualKeyCode = $virtualKeyCode
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

function Get-MainMenuOptions {
    param(
        [string]$LiveDownloadCacheLine,
        [string]$DeliveryOptimizationLine,
        [string]$ToolSelfUpdateLine
    )

    @(
        [pscustomobject]@{
            Key         = '1'
            Label       = 'Full Cleanup'
            Description = 'Run SFC, DISM, and WinSxS Temp cleanup'
            Detail      = 'SFC + DISM + InFlight'
            Color       = $script:C.OK
        }
        [pscustomobject]@{
            Key         = '2'
            Label       = 'InFlight Cleanup Only'
            Description = 'Quick cleanup that schedules locked files for reboot-time removal'
            Detail      = 'MoveFileEx + PendingFileRenameOperations'
            Color       = $script:C.Warn
        }
        [pscustomobject]@{
            Key         = '3'
            Label       = 'Live SoftwareDistribution Cleanup'
            Description = $LiveDownloadCacheLine
            Detail      = 'Post-update download cache cleanup'
            Color       = $script:C.Info
        }
        [pscustomobject]@{
            Key         = '4'
            Label       = 'Delivery Optimization Cleanup + Disable'
            Description = $DeliveryOptimizationLine
            Detail      = 'Clear DO cache and force CDN-only mode'
            Color       = $script:C.White
        }
        [pscustomobject]@{
            Key         = '5'
            Label       = 'Windows Update Manager'
            Description = 'Hide/unhide/list updates, reset cache, block Win11'
            Detail      = 'Interactive submenu'
            Color       = $script:C.Info
        }
        [pscustomobject]@{
            Key         = '6'
            Label       = 'Last DISM/CBS Failure Details'
            Description = 'Full-width recent servicing log view'
            Detail      = 'Diagnostics'
            Color       = $script:C.Accent
        }
        [pscustomobject]@{
            Key         = '7'
            Label       = 'Update App'
            Description = $ToolSelfUpdateLine
            Detail      = 'InstallerCore'
            Color       = $script:C.Info
        }
        [pscustomobject]@{
            Key         = 'ESC'
            Label       = 'Close / Cancel'
            Description = 'Exit the launcher'
            Detail      = ''
            Color       = $script:C.Fail
        }
    )
}

function Invoke-MainMenu {
    if ($null -eq $script:CachedLiveDownloadCacheLine) {
        $script:CachedLiveDownloadCacheLine = Get-LiveDownloadCacheStatusLine
    }
    if ($null -eq $script:CachedDeliveryOptimizationLine) {
        $script:CachedDeliveryOptimizationLine = Get-DeliveryOptimizationStatusLine
    }

    $toolSelfUpdateLine = Get-ToolSelfUpdateStatusLine
    $options = @(Get-MainMenuOptions -LiveDownloadCacheLine $script:CachedLiveDownloadCacheLine -DeliveryOptimizationLine $script:CachedDeliveryOptimizationLine -ToolSelfUpdateLine $toolSelfUpdateLine)
    $script:MainMenuIndex = [Math]::Max(0, [Math]::Min($script:MainMenuIndex, $options.Count - 1))

    while ($true) {
        Lock-ViewportToWindow

        Begin-SyncRender
        try {
            try {
                Clear-Host
            }
            catch {
            }

            Write-Banner
            Write-Section 'Runtime'
            $hostLabel = if (-not [string]::IsNullOrWhiteSpace($env:WT_SESSION)) { 'Windows Terminal' } else { 'PowerShell host' }
            $logLabel = if ([string]::IsNullOrWhiteSpace($script:LogFile)) { 'Unavailable' } else { $script:LogFile }
            Write-Host "  $($script:C.H2)Host:$($script:C.Reset) $($script:C.White)$hostLabel$($script:C.Reset)"
            Write-Host "  $($script:C.H2)Logs:$($script:C.Reset) $($script:C.Dim)$logLabel$($script:C.Reset)"

            Write-Host ''
            Write-Section 'Main Menu'
            Write-Host ''

            for ($index = 0; $index -lt $options.Count; $index++) {
                $item = $options[$index]
                $labelPrefix = if ($item.Key -eq 'ESC') { '[ESC]' } else { "[{0}]" -f $item.Key }
                $line = "  $labelPrefix $($item.Label)"
                if (-not [string]::IsNullOrWhiteSpace($item.Detail)) {
                    $line += " ($($item.Detail))"
                }

                if ($index -eq $script:MainMenuIndex) {
                    Write-Host "$($script:C.SelBg)$($script:C.SelFg)$($script:C.Bold)  $([char]0x276F) $line $($script:C.Reset)$($script:C.EraseLn)"
                    Write-Host "      $($script:C.White)$($item.Description)$($script:C.Reset)$($script:C.EraseLn)"
                }
                else {
                    Write-Host "    $($item.Color)$line$($script:C.Reset)$($script:C.EraseLn)"
                    Write-Host "      $($script:C.Dim)$($item.Description)$($script:C.Reset)$($script:C.EraseLn)"
                }

                Write-Host ''
            }

            Write-Host "  $($script:C.Dim)$([char]0x2191)$([char]0x2193) navigate   Enter = select   1..7 shortcuts   Esc = exit$($script:C.Reset)$($script:C.EraseLn)"
            Write-Host "$($script:E)[J" -NoNewline
        }
        finally {
            End-SyncRender
        }

        $key = Read-ConsoleKey
        switch ($key.Key) {
            'UpArrow' {
                $script:MainMenuIndex = [Math]::Max(0, $script:MainMenuIndex - 1)
                continue
            }
            'DownArrow' {
                $script:MainMenuIndex = [Math]::Min($options.Count - 1, $script:MainMenuIndex + 1)
                continue
            }
            'Enter' {
                return $options[$script:MainMenuIndex].Key
            }
            'Escape' {
                return 'ESC'
            }
            'ResizeEvent' {
                continue
            }
        }

        $keyText = [string]$key.KeyChar
        if ($key.VirtualKeyCode -ge 49 -and $key.VirtualKeyCode -le 55) {
            return $keyText
        }
    }
}

function Wait-ReturnToMenu {
    Clear-ConsoleInputBuffer
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
            $summaryLines = @(& (Join-Path $PSScriptRoot 'ManageUpdates.ps1') -Action DismFailureSummary -SilentCaller)
            if ($summaryLines.Count -gt 0) {
                foreach ($summaryLine in $summaryLines) {
                    Write-Host $summaryLine
                }
            }
            else {
                Write-Host '  Recent servicing log lines: no summary output returned.' -ForegroundColor DarkGray
            }
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
    Show-SubmenuHeader -Title 'Full Cleanup' -Subtitle 'SFC + DISM + InFlight'
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

    Show-SubmenuHeader -Title 'Full Cleanup' -Subtitle 'Running servicing and cleanup flow'
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
    Show-SubmenuHeader -Title 'InFlight Cleanup Only' -Subtitle 'MoveFileEx + reboot-time deletion fallback'
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
    Show-SubmenuHeader -Title 'DISM / CBS Failure Details' -Subtitle 'Recent servicing diagnostics'
    Write-Host '  DISM log: C:\Windows\Logs\DISM\dism.log' -ForegroundColor DarkGray
    Write-Host '  CBS log:  C:\Windows\Logs\CBS\CBS.log' -ForegroundColor DarkGray
    Write-Host ''

    try {
        $summaryLines = @(& (Join-Path $PSScriptRoot 'ManageUpdates.ps1') -Action DismFailureSummaryFull -SilentCaller)
        if ($summaryLines.Count -gt 0) {
            foreach ($summaryLine in $summaryLines) {
                Write-Host $summaryLine
            }
        }
        else {
            Write-Host '  No recent servicing summary lines were returned.' -ForegroundColor DarkGray
        }
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

if (Start-PreferredHost) {
    return
}

Initialize-Logging
Initialize-AppMetadata
[void](Resolve-AppUpdateStatus)

while ($true) {
    $choice = Invoke-MainMenu
    Clear-ConsoleInputBuffer

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
            if ($deliveryOptimizationResult -ne $script:SkipReturnToMenuToken) {
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
            if ($toolSelfUpdateResult -eq $script:RelaunchAndExitToken) {
                Request-LauncherExit
                return
            }
            if ($toolSelfUpdateResult -ne $script:SkipReturnToMenuToken) {
                [void](Resolve-AppUpdateStatus -ForceRefresh)
                Wait-ReturnToMenu
            }
            continue
        }
        '^ESC$' {
            Request-LauncherExit
            return
        }
        default {
            Write-Host '  Invalid choice.' -ForegroundColor Red
            Start-Sleep -Milliseconds 700
        }
    }
}
