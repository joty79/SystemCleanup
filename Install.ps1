#requires -version 7.0
[CmdletBinding()]
param(
    [ValidateSet('Install', 'Update', 'Uninstall', 'InstallGitHub', 'UpdateGitHub', 'OpenInstallDirectory', 'OpenInstallLogs')]
    [string]$Action = 'Install',
    [string]$InstallPath = '',
    [string]$SourcePath = $PSScriptRoot,
    [ValidateSet('Local', 'GitHub')]
    [string]$PackageSource = 'Local',
    [string]$GitHubRepo = '',
    [string]$GitHubRef = '',
    [string]$GitHubZipUrl = '',
    [switch]$Force,
    [switch]$NoExplorerRestart
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$script:ProfileJson = @'
{
  "tool_name": "SystemCleanup",
  "installer_title": "SystemCleanup Installer",
  "install_folder_name": "SystemCleanupContext",
  "github_repo": "joty79/SystemCleanup",
  "github_ref": "",
  "legacy_root": "D:\\Users\\joty79\\scripts\\dism",
  "publisher": "joty79",
  "uninstall_key_name": "SystemCleanupContext",
  "uninstall_display_name": "SystemCleanup Context Menu",
  "menu_option_5_label": "Open install logs",
  "required_commands": [
    "cmd.exe",
    "pwsh.exe",
    "sfc.exe",
    "dism.exe",
    "takeown.exe",
    "icacls.exe",
    "reg.exe"
  ],
  "required_package_entries": [
    "Install.ps1",
    "SystemCleanup.cmd",
    "CleanInFlight.ps1",
    "SystemCleanup.reg"
  ],
  "deploy_entries": [
    "Install.ps1",
    "SystemCleanup.cmd",
    "CleanInFlight.ps1",
    "SystemCleanup.reg"
  ],
  "preserve_existing_entries": [],
  "verify_core_files": [
    "Install.ps1",
    "SystemCleanup.cmd",
    "CleanInFlight.ps1"
  ],
  "migration_copy_entries": [
    "logs",
    "state"
  ],
  "uninstall_preserve_files": [
    "Install.ps1"
  ],
  "registry_cleanup_keys": [
    "HKCU\\Software\\Classes\\DesktopBackground\\Shell\\SystemCleanup",
    "HKCR\\DesktopBackground\\Shell\\SystemCleanup",
    "HKCU\\Software\\Classes\\DesktopBackground\\Shell\\SystemTools\\shell\\SystemCleanup",
    "HKCR\\DesktopBackground\\Shell\\SystemTools\\shell\\SystemCleanup"
  ],
  "registry_values": [
    {
      "key": "HKCU\\Software\\Classes\\DesktopBackground\\Shell\\SystemTools\\shell\\SystemCleanup",
      "name": "MUIVerb",
      "type": "REG_SZ",
      "value": "Windows Update CleanUp"
    },
    {
      "key": "HKCU\\Software\\Classes\\DesktopBackground\\Shell\\SystemTools\\shell\\SystemCleanup",
      "name": "Icon",
      "type": "REG_SZ",
      "value": "imageres.dll,-5323"
    },
    {
      "key": "HKCU\\Software\\Classes\\DesktopBackground\\Shell\\SystemTools\\shell\\SystemCleanup\\Command",
      "name": "(default)",
      "type": "REG_SZ",
      "value": "cmd.exe /c \"{InstallRoot}\\SystemCleanup.cmd\""
    }
  ],
  "registry_verify": [
    {
      "key": "HKCU\\Software\\Classes\\DesktopBackground\\Shell\\SystemTools\\shell\\SystemCleanup",
      "name": "MUIVerb",
      "expected": "Windows Update CleanUp"
    },
    {
      "key": "HKCU\\Software\\Classes\\DesktopBackground\\Shell\\SystemTools\\shell\\SystemCleanup\\Command",
      "name": "(default)",
      "expected": "cmd.exe /c \"{InstallRoot}\\SystemCleanup.cmd\""
    }
  ],
  "wrapper_patches": []
}
'@
$script:Profile = $script:ProfileJson | ConvertFrom-Json -Depth 50
$script:GitHubRefSpecified = $PSBoundParameters.ContainsKey('GitHubRef')

function Get-P([string]$Name, [object]$Default = $null) {
    $prop = $script:Profile.PSObject.Properties[$Name]
    if ($null -eq $prop) { return $Default }
    return $prop.Value
}
function Arr([string]$Name) { @((Get-P $Name @()) | ForEach-Object { [string]$_ } | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }) }
function Norm([string]$Path) { [System.IO.Path]::GetFullPath($Path.Trim()) }
function X([string]$Value, [string]$InstallRoot) {
    if ($null -eq $Value) { return '' }
    return $Value.Replace('{InstallRoot}', $InstallRoot).Replace('{InstallPath}', $InstallPath).Replace('{SourcePath}', $SourcePath)
}
function EnsureDir([string]$Path) { if (-not (Test-Path -LiteralPath $Path)) { New-Item -Path $Path -ItemType Directory -Force | Out-Null } }
function NormalizeGitHubRef([string]$Ref) {
    if ($null -eq $Ref) { return '' }
    $candidate = $Ref.Trim()
    if ($candidate.StartsWith('refs/heads/', [System.StringComparison]::OrdinalIgnoreCase)) {
        $candidate = $candidate.Substring('refs/heads/'.Length)
    }
    return $candidate
}

$script:ToolName = [string](Get-P 'tool_name' 'Tool')
$script:InstallerVersion = '1.0.0'
$script:DisplayName = [string](Get-P 'uninstall_display_name' "$($script:ToolName) Context Menu")
$script:InstallerTitle = [string](Get-P 'installer_title' "$($script:ToolName) Installer")
$script:LegacyRoot = [string](Get-P 'legacy_root' '')
$uninstallKeyName = [string](Get-P 'uninstall_key_name' "$($script:ToolName)Context")
$script:UninstallKeyPath = "Registry::HKEY_CURRENT_USER\Software\Microsoft\Windows\CurrentVersion\Uninstall\$uninstallKeyName"
$script:Warnings = [System.Collections.Generic.List[string]]::new()
$script:ResolvedPackageSource = $PackageSource
$script:ResolvedGitHubCommit = ''
$script:TempPackageRoots = [System.Collections.Generic.List[string]]::new()
$script:HasCliArgs = $MyInvocation.BoundParameters.Count -gt 0

if ([string]::IsNullOrWhiteSpace($InstallPath)) { $InstallPath = Join-Path $env:LOCALAPPDATA ([string](Get-P 'install_folder_name' "$($script:ToolName)Context")) }
if ([string]::IsNullOrWhiteSpace($GitHubRepo)) { $GitHubRepo = [string](Get-P 'github_repo' '') }
$GitHubRef = NormalizeGitHubRef $GitHubRef
if (-not $script:GitHubRefSpecified) { $GitHubRef = NormalizeGitHubRef ([string](Get-P 'github_ref' '')) }
$InstallPath = Norm $InstallPath
$SourcePath = Norm $SourcePath
$script:InstallerLogPath = Join-Path $InstallPath 'logs\installer.log'

function Log([string]$Message, [ValidateSet('INFO', 'WARN', 'ERROR')] [string]$Level = 'INFO') {
    $line = ('{0} | {1} | {2}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss.fff'), $Level, $Message)
    try { EnsureDir (Split-Path -Path $script:InstallerLogPath -Parent); Add-Content -Path $script:InstallerLogPath -Value $line -Encoding UTF8 } catch {}
    if ($Level -eq 'WARN') { $script:Warnings.Add($Message) | Out-Null; Write-Host "[!] $Message" -ForegroundColor Yellow; return }
    if ($Level -eq 'ERROR') { Write-Host "[x] $Message" -ForegroundColor Red; return }
    Write-Host "[>] $Message" -ForegroundColor DarkGray
}

function RequiredEntries {
    $r = Arr 'required_package_entries'
    if ($r.Count -gt 0) { return $r }
    return (Arr 'deploy_entries')
}
function DeployEntries {
    $r = Arr 'deploy_entries'
    if ($r.Count -gt 0) { return $r }
    return (RequiredEntries)
}

function Confirm([string]$Prompt) {
    if ($Force) { return $true }
    return ((Read-Host "$Prompt [y/N]").Trim().ToLowerInvariant() -eq 'y')
}

function RegCmd([AllowEmptyString()][string[]]$RegArgs, [switch]$IgnoreNotFound) {
    $out = & reg.exe @RegArgs 2>&1
    if ($LASTEXITCODE -eq 0) { return $out }
    $text = ($out | Out-String).Trim()
    if ($IgnoreNotFound -and $text -match 'unable to find the specified registry key or value') { return $null }
    throw "reg.exe failed: reg $($RegArgs -join ' ')`n$text"
}
function RegDel([string]$Key) { RegCmd -RegArgs @('delete', $Key, '/f') -IgnoreNotFound | Out-Null }
function RegAdd([string]$Key, [string]$Name, [string]$Type, [AllowEmptyString()][string]$Value) {
    $safe = if ($Type -eq 'REG_DWORD') { if ([string]::IsNullOrWhiteSpace($Value)) { '0' } else { $Value } } else { $Value }
    $regArgs = @('add', $Key)
    if ($Name -eq '(default)') { $regArgs += '/ve' } else { $regArgs += @('/v', $Name) }
    $regArgs += @('/t', $Type, '/d', $safe, '/f')
    RegCmd -RegArgs $regArgs | Out-Null
    if ($Type -in @('REG_SZ', 'REG_EXPAND_SZ') -and $Value -eq '') {
        $actual = RegGet -Key $Key -Name $Name
        if ($null -eq $actual -or $actual -ne '') {
            throw "Empty-string registry write verification failed for $Key [$Name]"
        }
    }
}
function RegGet([string]$Key, [string]$Name) {
    $q = if ($Name -eq '(default)') { RegCmd -RegArgs @('query', $Key, '/ve') -IgnoreNotFound } else { RegCmd -RegArgs @('query', $Key, '/v', $Name) -IgnoreNotFound }
    if (-not $q) { return $null }
    $line = $q | Where-Object { $_ -match 'REG_' -and $_ -match '^\s*(\(Default\)|\S+)\s+REG_' } | Select-Object -First 1
    if (-not $line) { return $null }
    $parts = ($line -split '\s{2,}') | Where-Object { $_ -ne '' }
    if ($parts.Count -ge 3) { return [string]$parts[2] }
    return ''
}

function CleanupRegistry {
    foreach ($k in (Arr 'registry_cleanup_keys')) {
        try {
            RegDel $k
        }
        catch {
            $errText = [string]$_.Exception.Message
            if ($k -like 'HKCR\*' -and $errText -match 'Access is denied') { continue }
            Log "Failed to remove key: $k" 'WARN'
        }
    }
}
function WriteRegistry([string]$InstallRoot) {
    CleanupRegistry
    foreach ($row in @((Get-P 'registry_values' @()))) {
        $k = [string]$row.key; if ([string]::IsNullOrWhiteSpace($k)) { continue }
        $n = [string]$row.name; if ([string]::IsNullOrWhiteSpace($n)) { $n = '(default)' }
        $t = [string]$row.type; if ([string]::IsNullOrWhiteSpace($t)) { $t = 'REG_SZ' }
        $v = X ([string]$row.value) $InstallRoot
        RegAdd -Key $k -Name $n -Type $t -Value $v
    }
}
function VerifyRegistry([string]$InstallRoot) {
    $ok = $true
    foreach ($row in @((Get-P 'registry_verify' @()))) {
        $k = [string]$row.key; $n = [string]$row.name; if ([string]::IsNullOrWhiteSpace($n)) { $n = '(default)' }
        $e = X ([string]$row.expected) $InstallRoot
        $a = RegGet -Key $k -Name $n
        if ($a -ne $e) { $ok = $false; Log "Registry mismatch: $k [$n] expected='$e' actual='$a'" 'WARN' }
    }
    return $ok
}

function SetUninstall([string]$InstallRoot) {
    $installScript = Join-Path $InstallRoot 'Install.ps1'
    $uninstallCmd = "pwsh -NoProfile -ExecutionPolicy Bypass -File `"$installScript`" -Action Uninstall -Force"
    $publisher = [string](Get-P 'publisher' 'joty79')
    New-Item -Path $script:UninstallKeyPath -Force | Out-Null
    New-ItemProperty -Path $script:UninstallKeyPath -Name 'DisplayName' -PropertyType String -Value $script:DisplayName -Force | Out-Null
    New-ItemProperty -Path $script:UninstallKeyPath -Name 'DisplayVersion' -PropertyType String -Value $script:InstallerVersion -Force | Out-Null
    New-ItemProperty -Path $script:UninstallKeyPath -Name 'Publisher' -PropertyType String -Value $publisher -Force | Out-Null
    New-ItemProperty -Path $script:UninstallKeyPath -Name 'InstallLocation' -PropertyType String -Value $InstallRoot -Force | Out-Null
    New-ItemProperty -Path $script:UninstallKeyPath -Name 'UninstallString' -PropertyType String -Value $uninstallCmd -Force | Out-Null
    New-ItemProperty -Path $script:UninstallKeyPath -Name 'NoModify' -PropertyType DWord -Value 1 -Force | Out-Null
    New-ItemProperty -Path $script:UninstallKeyPath -Name 'NoRepair' -PropertyType DWord -Value 1 -Force | Out-Null
}
function RemoveUninstall {
    try { if (Test-Path -LiteralPath $script:UninstallKeyPath) { Remove-Item -LiteralPath $script:UninstallKeyPath -Recurse -Force } } catch { Log 'Could not remove uninstall registry entry.' 'WARN' }
}

function TestPkgRoot([string]$Root) { foreach ($e in (RequiredEntries)) { if (-not (Test-Path -LiteralPath (Join-Path $Root $e))) { return $false } }; return $true }
function Get-GitHubApiHeaders {
    $headers = @{ 'User-Agent' = "$($script:ToolName)Installer/$($script:InstallerVersion)" }
    if (-not [string]::IsNullOrWhiteSpace($env:GITHUB_TOKEN)) {
        $headers['Authorization'] = "Bearer $($env:GITHUB_TOKEN)"
    }
    return $headers
}
function Get-GitHubRemoteInfo([string]$Repo) {
    $result = [ordered]@{
        DefaultBranch = ''
        Branches = [System.Collections.Generic.List[string]]::new()
    }
    if ([string]::IsNullOrWhiteSpace($Repo)) { return [pscustomobject]$result }

    if (Get-Command gh.exe -ErrorAction SilentlyContinue) {
        try {
            $repoJson = (& gh.exe api "repos/$Repo" 2>$null | Out-String).Trim()
            if (-not [string]::IsNullOrWhiteSpace($repoJson)) {
                $repoInfo = $repoJson | ConvertFrom-Json
                $result.DefaultBranch = [string]$repoInfo.default_branch
            }
            $branchesJson = (& gh.exe api --paginate "repos/$Repo/branches?per_page=100" 2>$null | Out-String).Trim()
            if (-not [string]::IsNullOrWhiteSpace($branchesJson)) {
                foreach ($row in @($branchesJson | ConvertFrom-Json)) {
                    $name = NormalizeGitHubRef ([string]$row.name)
                    if (-not [string]::IsNullOrWhiteSpace($name) -and -not $result.Branches.Contains($name)) {
                        $result.Branches.Add($name)
                    }
                }
            }
            if ($result.DefaultBranch -or $result.Branches.Count -gt 0) { return [pscustomobject]$result }
        }
        catch {}
    }

    try {
        $headers = Get-GitHubApiHeaders
        $repoResp = Invoke-WebRequest -Uri ("https://api.github.com/repos/{0}" -f $Repo) -UseBasicParsing -Headers $headers
        $repoInfo = $repoResp.Content | ConvertFrom-Json
        $result.DefaultBranch = [string]$repoInfo.default_branch

        $branchesResp = Invoke-WebRequest -Uri ("https://api.github.com/repos/{0}/branches?per_page=100" -f $Repo) -UseBasicParsing -Headers $headers
        foreach ($row in @($branchesResp.Content | ConvertFrom-Json)) {
            $name = NormalizeGitHubRef ([string]$row.name)
            if (-not [string]::IsNullOrWhiteSpace($name) -and -not $result.Branches.Contains($name)) {
                $result.Branches.Add($name)
            }
        }
    }
    catch {}

    return [pscustomobject]$result
}
function ResolveGitHubRefAuto {
    if ($script:GitHubRefSpecified -and -not [string]::IsNullOrWhiteSpace($GitHubRef)) {
        $script:ResolvedGitHubCommit = ''
        return $GitHubRef
    }

    $info = Get-GitHubRemoteInfo -Repo $GitHubRepo
    $preferred = [System.Collections.Generic.List[string]]::new()
    foreach ($candidate in @($info.DefaultBranch, 'master', [string](Get-P 'github_ref' ''), 'latest')) {
        $name = NormalizeGitHubRef $candidate
        if (-not [string]::IsNullOrWhiteSpace($name) -and -not $preferred.Contains($name)) {
            $preferred.Add($name)
        }
    }

    foreach ($candidate in $preferred) {
        if ($info.Branches.Contains($candidate)) {
            Log "Auto-detected GitHub ref: $candidate"
            return $candidate
        }
    }

    if (-not [string]::IsNullOrWhiteSpace($info.DefaultBranch)) {
        $defaultRef = NormalizeGitHubRef $info.DefaultBranch
        if (-not [string]::IsNullOrWhiteSpace($defaultRef)) {
            Log "Falling back to remote default branch: $defaultRef" 'WARN'
            return $defaultRef
        }
    }

    foreach ($candidate in @('master', 'latest')) {
        if (-not [string]::IsNullOrWhiteSpace($candidate)) {
            Log "GitHub ref auto-detect failed; using fallback ref: $candidate" 'WARN'
            return $candidate
        }
    }

    throw 'Could not resolve a GitHub ref.'
}
function EnsureGitHubRefResolved {
    $resolved = ResolveGitHubRefAuto
    $script:GitHubRefSpecified = $true
    $script:ResolvedGitHubCommit = ''
    Set-Variable -Name GitHubRef -Scope Script -Value $resolved
}
function ResolveSourceRoot {
    $script:ResolvedPackageSource = $PackageSource
    if ($PackageSource -eq 'Local' -and (TestPkgRoot $SourcePath)) { return $SourcePath }
    if ([string]::IsNullOrWhiteSpace($GitHubRepo)) { throw 'GitHubRepo is required for GitHub package source.' }
    if ([string]::IsNullOrWhiteSpace($GitHubRef)) { EnsureGitHubRefResolved }
    if ([string]::IsNullOrWhiteSpace($GitHubRef)) { throw 'GitHubRef could not be resolved for GitHub package source.' }
    $script:ResolvedPackageSource = 'GitHub'
    $fallbackRoots = @()
    if (TestPkgRoot $SourcePath) { $fallbackRoots += $SourcePath }
    if ((Test-Path -LiteralPath $InstallPath) -and (TestPkgRoot $InstallPath)) { $fallbackRoots += $InstallPath }
    $url = if ([string]::IsNullOrWhiteSpace($GitHubZipUrl)) { "https://codeload.github.com/$GitHubRepo/zip/refs/heads/$GitHubRef" } else { $GitHubZipUrl.Trim() }
    $tmp = Join-Path $env:TEMP ("$($script:ToolName)_pkg_" + [guid]::NewGuid().ToString('N'))
    $zip = Join-Path $tmp 'pkg.zip'
    $ext = Join-Path $tmp 'extract'
    EnsureDir $tmp; EnsureDir $ext
    $script:TempPackageRoots.Add($tmp) | Out-Null
    Log "Downloading package: $url"
    $downloaded = $false
    try {
        $headers = @{ 'User-Agent' = "$($script:ToolName)Installer/$($script:InstallerVersion)" }
        if (-not [string]::IsNullOrWhiteSpace($env:GITHUB_TOKEN)) {
            $headers['Authorization'] = "Bearer $($env:GITHUB_TOKEN)"
        }
        Invoke-WebRequest -Uri $url -OutFile $zip -UseBasicParsing -Headers $headers
        $downloaded = $true
    }
    catch {
        if (Get-Command gh.exe -ErrorAction SilentlyContinue) {
            try {
                Log 'Invoke-WebRequest failed; trying authenticated GitHub API fallback via gh auth token...'
                $ghToken = (& gh.exe auth token 2>$null | Out-String).Trim()
                if (-not [string]::IsNullOrWhiteSpace($ghToken)) {
                    $apiHeaders = @{
                        'User-Agent' = "$($script:ToolName)Installer/$($script:InstallerVersion)"
                        'Authorization' = "Bearer $ghToken"
                        'Accept' = 'application/vnd.github+json'
                    }
                    $apiUrl = "https://api.github.com/repos/$GitHubRepo/zipball/$GitHubRef"
                    Invoke-WebRequest -Uri $apiUrl -OutFile $zip -UseBasicParsing -Headers $apiHeaders
                }
                if (Test-Path -LiteralPath $zip) {
                    $downloaded = $true
                }
            }
            catch {}
        }
        if (-not $downloaded) {
            if ($fallbackRoots.Count -gt 0) {
                Log "GitHub fetch failed. Falling back to local package source: $($fallbackRoots[0])" 'WARN'
                $script:ResolvedPackageSource = 'Local'
                return $fallbackRoots[0]
            }
            throw
        }
    }
    try {
        Expand-Archive -Path $zip -DestinationPath $ext -Force
    }
    catch {
        if ($fallbackRoots.Count -gt 0) {
            Log "GitHub extract failed. Falling back to local package source: $($fallbackRoots[0])" 'WARN'
            $script:ResolvedPackageSource = 'Local'
            return $fallbackRoots[0]
        }
        throw
    }
    $roots = @(Get-ChildItem -LiteralPath $ext -Directory -Recurse -ErrorAction SilentlyContinue | ForEach-Object { $_.FullName })
    foreach ($r in $roots) { if (TestPkgRoot $r) { return $r } }
    if ($fallbackRoots.Count -gt 0) {
        Log "Downloaded package missing required files. Falling back to local package source: $($fallbackRoots[0])" 'WARN'
        $script:ResolvedPackageSource = 'Local'
        return $fallbackRoots[0]
    }
    throw 'Downloaded package does not contain required files.'
}

function Deploy([string]$SourceRoot, [string]$InstallRoot) {
    $keep = @{}; foreach ($e in (Arr 'preserve_existing_entries')) { $keep[$e.ToLowerInvariant()] = $true }
    foreach ($rel in (DeployEntries)) {
        $src = Join-Path $SourceRoot $rel
        $dst = Join-Path $InstallRoot $rel
        if (-not (Test-Path -LiteralPath $src)) { throw "Missing deploy entry: $rel" }
        $preserve = $keep.ContainsKey($rel.ToLowerInvariant())
        $srcItem = Get-Item -LiteralPath $src
        if ($srcItem.PSIsContainer) {
            if ($preserve -and (Test-Path -LiteralPath $dst)) { continue }
            EnsureDir (Split-Path -Path $dst -Parent)
            Copy-Item -LiteralPath $src -Destination $dst -Recurse -Force
            continue
        }
        EnsureDir (Split-Path -Path $dst -Parent)
        if ($preserve -and (Test-Path -LiteralPath $dst)) { continue }
        if ((Norm $src) -ieq (Norm $dst)) { continue }
        Copy-Item -LiteralPath $src -Destination $dst -Force
    }
}

function PatchWrappers([string]$InstallRoot) {
    foreach ($p in @((Get-P 'wrapper_patches' @()))) {
        $fileRel = [string]$p.file; $regex = [string]$p.regex; $repRaw = [string]$p.replacement
        if ([string]::IsNullOrWhiteSpace($fileRel) -or [string]::IsNullOrWhiteSpace($regex)) { continue }
        $target = Join-Path $InstallRoot $fileRel
        if (-not (Test-Path -LiteralPath $target)) { Log "Wrapper patch target missing: $target" 'WARN'; continue }
        $raw = Get-Content -LiteralPath $target -Raw
        $patched = [regex]::Replace($raw, $regex, (X $repRaw $InstallRoot))
        Set-Content -LiteralPath $target -Value $patched -Encoding UTF8
    }
}

function VerifyCore([string]$InstallRoot) {
    $required = Arr 'verify_core_files'; if ($required.Count -eq 0) { $required = RequiredEntries }
    $ok = $true
    foreach ($rel in $required) {
        if (-not (Test-Path -LiteralPath (Join-Path $InstallRoot $rel))) { $ok = $false; Log "Missing core file: $rel" 'WARN' }
    }
    return $ok
}

function SaveMeta([string]$InstallRoot, [string]$Mode) {
    $metaPath = Join-Path $InstallRoot 'state\install-meta.json'
    EnsureDir (Split-Path -Path $metaPath -Parent)
    $meta = [ordered]@{
        schema_version = 1
        installer_version = $script:InstallerVersion
        tool_name = $script:ToolName
        install_path = $InstallPath
        source_path = if ($script:ResolvedPackageSource -eq 'GitHub') { "github://$GitHubRepo@$GitHubRef" } else { $SourcePath }
        package_source = $script:ResolvedPackageSource
        github_repo = $GitHubRepo
        github_ref = $GitHubRef
        github_zip_url = $GitHubZipUrl
        github_commit = $script:ResolvedGitHubCommit
        last_action = $Mode
        installed_utc = (Get-Date).ToUniversalTime().ToString('o')
    }
    $meta | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $metaPath -Encoding UTF8
}

function Resolve-ExplorerPathArgument([string]$PathToUse) {
    if ([string]::IsNullOrWhiteSpace($PathToUse)) { return '' }

    try {
        $fullPath = [System.IO.Path]::GetFullPath($PathToUse)
    }
    catch {
        return ''
    }

    if (-not (Test-Path -LiteralPath $fullPath -PathType Container)) { return '' }

    $desktopPath = [Environment]::GetFolderPath('Desktop')
    if ($fullPath.TrimEnd('\') -ieq $desktopPath.TrimEnd('\')) { return '' }

    return $fullPath
}

function Get-ExplorerRestartPath {
    foreach ($candidate in @($SourcePath, $InstallPath)) {
        $resolved = Resolve-ExplorerPathArgument -PathToUse $candidate
        if (-not [string]::IsNullOrWhiteSpace($resolved)) { return $resolved }
    }
    return ''
}

function RestartExplorer {
    if ($NoExplorerRestart) { Log 'Explorer restart skipped by -NoExplorerRestart.' 'WARN'; return }
    if (-not $Force) {
        $a = (Read-Host 'Restart Explorer now to refresh context menus? [Y/n]').Trim().ToLowerInvariant()
        if ($a -in @('n', 'no')) { Log 'Explorer restart skipped by user.' 'WARN'; return }
    }

    $reopenPath = Get-ExplorerRestartPath
    $runningExplorer = @(Get-Process -Name explorer -ErrorAction SilentlyContinue)

    try {
        foreach ($process in $runningExplorer) {
            try {
                Stop-Process -Id $process.Id -Force -ErrorAction Stop
            }
            catch {}
        }
        try {
            Wait-Process -Name explorer -Timeout 5 -ErrorAction SilentlyContinue
        }
        catch {}

        # Do not Start-Process explorer.exe here. Windows auto-restores the shell,
        # and forcing a new explorer process can create a secondary zombie instance.
        $shellAlive = $false
        $sw = [System.Diagnostics.Stopwatch]::StartNew()
        do {
            Start-Sleep -Milliseconds 300
            if (Get-Process -Name explorer -ErrorAction SilentlyContinue) { $shellAlive = $true }
        } while (-not $shellAlive -and $sw.Elapsed.TotalSeconds -lt 10)

        if (-not $shellAlive) {
            Log 'Explorer shell did not auto-restart within timeout. Please restart manually.' 'WARN'
            return
        }

        if ([string]::IsNullOrWhiteSpace($reopenPath)) {
            Start-Sleep -Milliseconds 500
            Log 'Explorer restarted (auto). No folder window was reopened.'
            return
        }

        Start-Sleep -Seconds 2
        try {
            $shell = New-Object -ComObject Shell.Application
            $shell.Open($reopenPath)
            Log "Explorer restarted and reopened folder: $reopenPath"
        }
        catch {
            Log "Explorer restarted, but folder reopen failed: $reopenPath" 'WARN'
        }
    }
    catch {
        Log 'Explorer restart failed. Please restart manually.' 'WARN'
    }
}

function RunInstallOrUpdate([ValidateSet('Install', 'Update')] [string]$Mode) {
    Log "Starting $Mode to $InstallPath"
    foreach ($cmd in @('pwsh.exe', 'wscript.exe') + (Arr 'required_commands')) { if (-not (Get-Command $cmd -ErrorAction SilentlyContinue)) { Log "Missing required command: $cmd" 'ERROR'; return 1 } }
    EnsureDir $InstallPath; EnsureDir (Join-Path $InstallPath 'logs'); EnsureDir (Join-Path $InstallPath 'state'); EnsureDir (Join-Path $InstallPath 'assets')
    try { $src = ResolveSourceRoot; Deploy -SourceRoot $src -InstallRoot $InstallPath } finally { foreach ($t in $script:TempPackageRoots) { try { if (Test-Path -LiteralPath $t) { Remove-Item -LiteralPath $t -Recurse -Force -ErrorAction SilentlyContinue } } catch {} } $script:TempPackageRoots.Clear() }
    PatchWrappers -InstallRoot $InstallPath
    $coreOk = VerifyCore -InstallRoot $InstallPath
    WriteRegistry -InstallRoot $InstallPath
    $regOk = VerifyRegistry -InstallRoot $InstallPath
    SetUninstall -InstallRoot $InstallPath
    SaveMeta -InstallRoot $InstallPath -Mode $Mode
    RestartExplorer
    if ($script:Warnings.Count -gt 0 -or -not $coreOk -or -not $regOk) { Write-Host "$Mode completed with warnings." -ForegroundColor Yellow; return 2 }
    Write-Host "$Mode completed successfully." -ForegroundColor Green
    return 0
}

function RunUninstall {
    Log "Starting uninstall from $InstallPath"
    CleanupRegistry
    RemoveUninstall
    if (Test-Path -LiteralPath $InstallPath) {
        $preserve = @('Install.ps1') + (Arr 'uninstall_preserve_files')
        foreach ($item in @(Get-ChildItem -LiteralPath $InstallPath -Force -ErrorAction SilentlyContinue)) {
            if ($preserve -contains $item.Name) { continue }
            try { Remove-Item -LiteralPath $item.FullName -Recurse -Force -ErrorAction Stop } catch { Log "Could not remove during uninstall: $($item.FullName)" 'WARN' }
        }
    }
    RestartExplorer
    Write-Host 'Uninstall completed successfully.' -ForegroundColor Green
    return 0
}

function ShowMenu {
    while ($true) {
        try { Clear-Host } catch {}
        Write-Host '============================================================' -ForegroundColor Cyan
        Write-Host ('  {0}  v{1}' -f $script:InstallerTitle, $script:InstallerVersion) -ForegroundColor Cyan
        Write-Host '============================================================' -ForegroundColor Cyan
        Write-Host ('Source:  {0}' -f $SourcePath) -ForegroundColor DarkGray
        Write-Host ('Install: {0}' -f $InstallPath) -ForegroundColor DarkGray
        Write-Host ''
        Write-Host '[1] Install' -ForegroundColor Green
        Write-Host '[2] Update' -ForegroundColor Yellow
        Write-Host '[3] Uninstall' -ForegroundColor Red
        Write-Host '[4] Open install directory' -ForegroundColor Cyan
        Write-Host ('[5] {0}' -f ([string](Get-P 'menu_option_5_label' 'Open install logs'))) -ForegroundColor Cyan
        Write-Host '[0] Exit' -ForegroundColor Gray
        $c = (Read-Host 'Select option').Trim()
        switch ($c) { '1' { return 'Install' }; '2' { return 'Update' }; '3' { return 'Uninstall' }; '4' { return 'OpenInstallDirectory' }; '5' { return 'OpenInstallLogs' }; '0' { return 'Exit' } }
    }
}

function Get-GitHubBranchNames([string]$Repo) {
    if ([string]::IsNullOrWhiteSpace($Repo)) { return @() }

    $headers = @{ 'User-Agent' = "$($script:ToolName)Installer/$($script:InstallerVersion)" }
    if (-not [string]::IsNullOrWhiteSpace($env:GITHUB_TOKEN)) {
        $headers['Authorization'] = "Bearer $($env:GITHUB_TOKEN)"
    }

    try {
        $resp = Invoke-RestMethod -Uri ("https://api.github.com/repos/{0}/branches?per_page=100" -f $Repo) -Headers $headers -Method Get
        if (-not $resp) { return @() }
        $names = @($resp | ForEach-Object { [string]$_.name } | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
        return @($names | Select-Object -Unique)
    }
    catch {
        if (Get-Command gh.exe -ErrorAction SilentlyContinue) {
            try {
                $ghToken = (& gh.exe auth token 2>$null | Out-String).Trim()
                if (-not [string]::IsNullOrWhiteSpace($ghToken)) {
                    $authHeaders = @{
                        'User-Agent' = "$($script:ToolName)Installer/$($script:InstallerVersion)"
                        'Authorization' = "Bearer $ghToken"
                        'Accept' = 'application/vnd.github+json'
                    }
                    $resp = Invoke-RestMethod -Uri ("https://api.github.com/repos/{0}/branches?per_page=100" -f $Repo) -Headers $authHeaders -Method Get
                    if ($resp) {
                        $names = @($resp | ForEach-Object { [string]$_.name } | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
                        return @($names | Select-Object -Unique)
                    }
                }
            }
            catch {}
        }
        Write-Host ("[!] Could not fetch branch list from GitHub: {0}" -f $_.Exception.Message) -ForegroundColor Yellow
        return @()
    }
}

function ReadRefInteractive([string]$DefaultRef) {
    $normalizedDefault = if ([string]::IsNullOrWhiteSpace($DefaultRef)) { 'master' } else { $DefaultRef.Trim() }
    $branches = @(Get-GitHubBranchNames -Repo $GitHubRepo)

    if ($branches.Count -gt 0) {
        if ($branches -notcontains $normalizedDefault) {
            $branches = @($normalizedDefault) + @($branches)
        }
        else {
            $branches = @($normalizedDefault) + @($branches | Where-Object { $_ -ne $normalizedDefault })
        }
        $branches = @($branches | Select-Object -Unique)

        Write-Host ''
        Write-Host ("Available branches for {0}:" -f $GitHubRepo) -ForegroundColor Cyan
        for ($i = 0; $i -lt $branches.Count; $i++) {
            $n = $i + 1
            $name = $branches[$i]
            $suffix = if ($name -eq $normalizedDefault) { ' (default)' } else { '' }
            Write-Host ("[{0}] {1}{2}" -f $n, $name, $suffix) -ForegroundColor Gray
        }
        Write-Host '[M] Manual branch/ref input' -ForegroundColor Gray
        Write-Host '[Enter] Use default' -ForegroundColor Gray

        while ($true) {
            $choice = (Read-Host ("Select branch number (blank = {0})" -f $normalizedDefault)).Trim()
            if ([string]::IsNullOrWhiteSpace($choice)) { return $normalizedDefault }
            if ($choice.Equals('m', [System.StringComparison]::OrdinalIgnoreCase)) { break }
            if ($choice -match '^\d+$') {
                $index = [int]$choice
                if ($index -ge 1 -and $index -le $branches.Count) {
                    return $branches[$index - 1]
                }
            }
            Write-Host 'Invalid selection. Choose a number, M, or Enter.' -ForegroundColor Yellow
        }
    }

    while ($true) {
        $raw = Read-Host ("GitHub branch/ref (blank = {0})" -f $normalizedDefault)
        $candidate = if ($null -eq $raw) { '' } else { $raw.Trim() }
        if ([string]::IsNullOrWhiteSpace($candidate)) { return $normalizedDefault }
        if ($candidate.StartsWith('refs/heads/', [System.StringComparison]::OrdinalIgnoreCase)) {
            $candidate = $candidate.Substring('refs/heads/'.Length)
        }
        if ([string]::IsNullOrWhiteSpace($candidate)) {
            Write-Host 'Invalid branch/ref. Try again.' -ForegroundColor Yellow
            continue
        }
        return $candidate
    }
}

if (-not $script:HasCliArgs) { $menuAction = ShowMenu; if ($menuAction -eq 'Exit') { exit 0 }; $Action = $menuAction }
switch ($Action) {
    'Install' { $PackageSource = 'GitHub'; EnsureGitHubRefResolved; if (-not $script:HasCliArgs) { $GitHubRef = ReadRefInteractive -DefaultRef $GitHubRef }; Write-Host ("Using GitHub ref: {0}" -f $GitHubRef) -ForegroundColor DarkCyan; if (-not (Confirm "Install $($script:DisplayName) to '$InstallPath'?")) { Write-Host 'Cancelled.' -ForegroundColor Yellow; exit 0 }; exit (RunInstallOrUpdate -Mode 'Install') }
    'InstallGitHub' { $PackageSource = 'GitHub'; EnsureGitHubRefResolved; Write-Host ("Using GitHub ref: {0}" -f $GitHubRef) -ForegroundColor DarkCyan; if (-not (Confirm "Install $($script:DisplayName) to '$InstallPath'?")) { Write-Host 'Cancelled.' -ForegroundColor Yellow; exit 0 }; exit (RunInstallOrUpdate -Mode 'Install') }
    'Update' { $PackageSource = 'GitHub'; EnsureGitHubRefResolved; if (-not $script:HasCliArgs) { $GitHubRef = ReadRefInteractive -DefaultRef $GitHubRef }; Write-Host ("Using GitHub ref: {0}" -f $GitHubRef) -ForegroundColor DarkCyan; if (-not (Confirm "Update existing $($script:DisplayName) at '$InstallPath'?")) { Write-Host 'Cancelled.' -ForegroundColor Yellow; exit 0 }; exit (RunInstallOrUpdate -Mode 'Update') }
    'UpdateGitHub' { $PackageSource = 'GitHub'; EnsureGitHubRefResolved; Write-Host ("Using GitHub ref: {0}" -f $GitHubRef) -ForegroundColor DarkCyan; if (-not (Confirm "Update existing $($script:DisplayName) at '$InstallPath'?")) { Write-Host 'Cancelled.' -ForegroundColor Yellow; exit 0 }; exit (RunInstallOrUpdate -Mode 'Update') }
    'Uninstall' { if (-not (Confirm "Uninstall $($script:DisplayName) from '$InstallPath'?")) { Write-Host 'Cancelled.' -ForegroundColor Yellow; exit 0 }; exit (RunUninstall) }
    'OpenInstallDirectory' { if (-not (Test-Path -LiteralPath $InstallPath)) { Write-Host ("Install directory not found: {0}" -f $InstallPath) -ForegroundColor Yellow; exit 1 }; Start-Process explorer.exe -ArgumentList $InstallPath; exit 0 }
    'OpenInstallLogs' { $logFile = Join-Path $InstallPath 'logs\\installer.log'; $logDir = Split-Path -Path $logFile -Parent; EnsureDir $logDir; if (Test-Path -LiteralPath $logFile) { Start-Process notepad.exe -ArgumentList $logFile } else { Start-Process explorer.exe -ArgumentList $logDir }; exit 0 }
    default { Write-Host "Unknown action: $Action" -ForegroundColor Red; exit 1 }
}

