# GearScout Installer / lib/InstallLogic.ps1
#
# Everything that touches disk beyond reading: finding a source zip (local
# file or GitHub release), unpacking it, and copying the two addon folders
# into an Interface\AddOns folder.
#
# Safety rule that overrides everything else in this file: GearScout is
# developed by linking Interface\AddOns\GearScout to a working copy with a
# directory junction. If a destination folder turns out to be a link, this
# file must never delete it or write into it, only report that it is linked
# and leave it alone. Requires Detect.ps1 to already be dot sourced (for
# Test-IsReparsePoint, Get-ReparseTarget, Get-TocVersion).
#
# Meant to be dot sourced:  . "$PSScriptRoot\lib\InstallLogic.ps1"

Set-StrictMode -Version Latest

$Script:AddonFolderNames = @('GearScout', 'GearScout_Lead')

# ---------------------------------------------------------------------------
# Local zip discovery. Looks next to the app first (how it will actually be
# handed out), then in ..\dist next to the app (this repo's layout, useful
# while developing the installer itself).
# ---------------------------------------------------------------------------
function global:Find-LocalZip {
    param([Parameter(Mandatory)][string]$AppDir)

    $searchDirs = @(
        $AppDir
        (Join-Path $AppDir '..\dist')
    )

    $best = $null
    foreach ($dir in $searchDirs) {
        if (-not (Test-Path -LiteralPath $dir -PathType Container)) { continue }
        $zips = Get-ChildItem -LiteralPath $dir -Filter 'GearScout*.zip' -File -ErrorAction SilentlyContinue
        foreach ($z in $zips) {
            if (-not $best -or $z.LastWriteTimeUtc -gt $best.LastWriteTimeUtc) {
                $best = $z
            }
        }
    }

    if ($best) { return $best.FullName }
    return $null
}

# ---------------------------------------------------------------------------
# GitHub release download. Owner/repo are passed in from the caller (see the
# constant at the top of GearScoutInstaller.ps1). Never throws, returns $null
# on any failure so the caller can fall back to the local zip.
# ---------------------------------------------------------------------------
function global:Get-LatestGitHubZip {
    param(
        [string]$Owner,
        [string]$Repo,
        [Parameter(Mandatory)][string]$DownloadDir
    )

    if ([string]::IsNullOrWhiteSpace($Owner) -or [string]::IsNullOrWhiteSpace($Repo)) {
        return [pscustomobject]@{ Path = $null; Version = $null; Error = 'No GitHub repo configured yet.' }
    }

    try {
        $api = "https://api.github.com/repos/$Owner/$Repo/releases/latest"
        $headers = @{ 'User-Agent' = 'GearScoutInstaller' }
        $release = Invoke-RestMethod -Uri $api -Headers $headers -TimeoutSec 10 -ErrorAction Stop

        $asset = $release.assets | Where-Object { $_.name -like 'GearScout*.zip' } | Select-Object -First 1
        if (-not $asset) {
            return [pscustomobject]@{ Path = $null; Version = $null; Error = 'Latest release has no GearScout zip attached.' }
        }

        if (-not (Test-Path -LiteralPath $DownloadDir)) {
            New-Item -ItemType Directory -Force -Path $DownloadDir | Out-Null
        }
        $outPath = Join-Path $DownloadDir $asset.name
        Invoke-WebRequest -Uri $asset.browser_download_url -Headers $headers -OutFile $outPath -TimeoutSec 60 -ErrorAction Stop

        $version = $release.tag_name
        return [pscustomobject]@{ Path = $outPath; Version = $version; Error = $null }
    } catch {
        return [pscustomobject]@{ Path = $null; Version = $null; Error = $_.Exception.Message }
    }
}

# ---------------------------------------------------------------------------
# Peeks inside a zip's central directory to see if it has a GearScout_Lead
# folder, without extracting anything. Read only, safe to call at any time.
# ---------------------------------------------------------------------------
function global:Test-ZipContainsLead {
    param([Parameter(Mandatory)][string]$ZipPath)
    try {
        Add-Type -AssemblyName System.IO.Compression.FileSystem -ErrorAction SilentlyContinue
        $zip = [System.IO.Compression.ZipFile]::OpenRead($ZipPath)
        try {
            $hit = $zip.Entries | Where-Object { $_.FullName -match '(^|[\\/])GearScout_Lead[\\/]GearScout_Lead\.toc$' } | Select-Object -First 1
            return [bool]$hit
        } finally {
            $zip.Dispose()
        }
    } catch {
        return $false
    }
}

# ---------------------------------------------------------------------------
# Decides where the install package comes from. GitHub is preferred when a
# repo is configured and reachable; anything else (no repo configured yet,
# no network, no release, no matching asset) falls back to the local zip.
#
# Only GearScout is published publicly, GearScout_Lead is the officer only
# half and is handed out privately, never through GitHub. So LeadAvailable
# is hard coded false for a GitHub sourced package regardless of what that
# zip happens to contain, and is only ever true for the local zip, and only
# when that zip actually has a GearScout_Lead folder in it.
# ---------------------------------------------------------------------------
function global:Resolve-InstallSource {
    param(
        [Parameter(Mandatory)][string]$AppDir,
        [string]$GitHubOwner,
        [string]$GitHubRepo
    )

    $tempDir = Join-Path $env:TEMP 'GearScoutInstaller'

    $gh = Get-LatestGitHubZip -Owner $GitHubOwner -Repo $GitHubRepo -DownloadDir $tempDir
    if ($gh.Path) {
        return [pscustomobject]@{
            ZipPath      = $gh.Path
            Kind         = 'github'
            Version      = $gh.Version
            Message      = "Using the latest release from GitHub ($($gh.Version))."
            LeadAvailable = $false
        }
    }

    $local = Find-LocalZip -AppDir $AppDir
    if ($local) {
        $reason = if ($gh.Error) { " ($($gh.Error))" } else { '' }
        return [pscustomobject]@{
            ZipPath      = $local
            Kind         = 'local'
            Version      = $null
            Message      = "Using the local file $(Split-Path -Leaf $local)$reason."
            LeadAvailable = (Test-ZipContainsLead -ZipPath $local)
        }
    }

    return [pscustomobject]@{
        ZipPath      = $null
        Kind         = 'none'
        Version      = $null
        Message      = 'No install package found. Put a GearScout zip next to this app, or set up the GitHub repo constant.'
        LeadAvailable = $false
    }
}

# ---------------------------------------------------------------------------
# Unpacks a zip into a fresh temp folder under %TEMP% and checks it has the
# shape this installer expects: a GearScout folder with a .toc in it.
# GearScout_Lead is optional in the package (older builds might not ship it).
# ---------------------------------------------------------------------------
function global:Expand-GearScoutPackage {
    param([Parameter(Mandatory)][string]$ZipPath)

    $stagingRoot = Join-Path $env:TEMP ('GearScoutInstaller_stage_' + [guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Force -Path $stagingRoot | Out-Null

    Expand-Archive -LiteralPath $ZipPath -DestinationPath $stagingRoot -Force

    # Some zip tools nest everything one folder deeper (a single top level
    # folder wrapping GearScout\ and GearScout_Lead\). If the addon folders
    # are not at the root, look one level down for them.
    $root = $stagingRoot
    if (-not (Test-Path -LiteralPath (Join-Path $root 'GearScout\GearScout.toc'))) {
        $sub = Get-ChildItem -LiteralPath $stagingRoot -Directory -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($sub -and (Test-Path -LiteralPath (Join-Path $sub.FullName 'GearScout\GearScout.toc'))) {
            $root = $sub.FullName
        }
    }

    $hasGearScout = Test-Path -LiteralPath (Join-Path $root 'GearScout\GearScout.toc')
    $hasLead      = Test-Path -LiteralPath (Join-Path $root 'GearScout_Lead\GearScout_Lead.toc')
    $version      = $null
    if ($hasGearScout) {
        $version = Get-TocVersion -TocPath (Join-Path $root 'GearScout\GearScout.toc')
    }

    [pscustomobject]@{
        StagingRoot  = $stagingRoot
        PackageRoot  = $root
        HasGearScout = $hasGearScout
        HasLead      = $hasLead
        Version      = $version
    }
}

function global:Remove-StagingFolder {
    param([Parameter(Mandatory)][string]$StagingRoot)
    # Only ever remove folders this installer created itself, under %TEMP%
    # with its own prefix. Never called with anything else.
    if ($StagingRoot -like (Join-Path $env:TEMP 'GearScoutInstaller_stage_*')) {
        Remove-Item -LiteralPath $StagingRoot -Recurse -Force -ErrorAction SilentlyContinue
    }
}

# ---------------------------------------------------------------------------
# Deletes exactly one addon folder this installer owns. Guarded three ways
# before anything is removed: the path must end in \GearScout or
# \GearScout_Lead, it must not be a reparse point (a link to a dev folder),
# and it must actually be a directory. Throws "REPARSE:" prefixed messages
# so callers can tell a link apart from a real error.
# ---------------------------------------------------------------------------
function global:Remove-OwnedAddonFolder {
    param([Parameter(Mandatory)][string]$Path)

    if ($Path -notmatch '\\(GearScout|GearScout_Lead)$') {
        throw "Refused to remove '$Path': it does not look like a folder this installer owns."
    }
    if (-not (Test-Path -LiteralPath $Path)) { return }

    if (Test-IsReparsePoint -Path $Path) {
        $target = Get-ReparseTarget -Path $Path
        throw "REPARSE:$Path|$target"
    }

    $item = Get-Item -LiteralPath $Path -Force
    if (-not $item.PSIsContainer) {
        throw "Refused to remove '$Path': it is not a directory."
    }

    Remove-Item -LiteralPath $Path -Recurse -Force
}

# ---------------------------------------------------------------------------
# Installs (or updates) one addon folder, e.g. "GearScout", from the unpacked
# package into an Interface\AddOns folder. Creates Interface\AddOns if it is
# missing. Returns a result object describing what happened, it never throws
# for the expected cases (missing package folder, destination is a link).
# ---------------------------------------------------------------------------
function global:Install-AddonFolder {
    param(
        [Parameter(Mandatory)][string]$PackageRoot,
        [Parameter(Mandatory)][string]$FolderName,
        [Parameter(Mandatory)][string]$AddOnsPath
    )

    $sourcePath = Join-Path $PackageRoot $FolderName
    $destPath   = Join-Path $AddOnsPath $FolderName

    if (-not (Test-Path -LiteralPath $sourcePath -PathType Container)) {
        return [pscustomobject]@{
            FolderName = $FolderName
            Status     = 'error'
            Message    = "The package does not contain a $FolderName folder, nothing to install."
            LinkTarget = $null
        }
    }

    if ((Test-Path -LiteralPath $destPath) -and (Test-IsReparsePoint -Path $destPath)) {
        $target = Get-ReparseTarget -Path $destPath
        return [pscustomobject]@{
            FolderName = $FolderName
            Status     = 'skipped_linked'
            Message    = "$FolderName here is linked to a development folder ($target). It is already live, so it was left untouched."
            LinkTarget = $target
        }
    }

    try {
        if (-not (Test-Path -LiteralPath $AddOnsPath)) {
            New-Item -ItemType Directory -Force -Path $AddOnsPath | Out-Null
        }

        Remove-OwnedAddonFolder -Path $destPath
        Copy-Item -LiteralPath $sourcePath -Destination $destPath -Recurse -Force

        return [pscustomobject]@{
            FolderName = $FolderName
            Status     = 'installed'
            Message    = "$FolderName installed."
            LinkTarget = $null
        }
    } catch {
        $msg = $_.Exception.Message
        if ($msg -like 'REPARSE:*') {
            $parts = $msg.Substring(8).Split('|')
            return [pscustomobject]@{
                FolderName = $FolderName
                Status     = 'skipped_linked'
                Message    = "$FolderName here is linked to a development folder ($($parts[1])). It is already live, so it was left untouched."
                LinkTarget = $parts[1]
            }
        }
        return [pscustomobject]@{
            FolderName = $FolderName
            Status     = 'error'
            Message    = "Could not install $FolderName`: $msg"
            LinkTarget = $null
        }
    }
}

# ---------------------------------------------------------------------------
# Installs GearScout, and GearScout_Lead if requested, into one AddOns
# folder. Returns the per folder results plus the staging folder used so the
# caller can clean it up (or leave it, cleanup failure is not fatal).
# ---------------------------------------------------------------------------
function global:Install-GearScoutPackage {
    param(
        [Parameter(Mandatory)][string]$ZipPath,
        [Parameter(Mandatory)][string]$AddOnsPath,
        [switch]$IncludeLead
    )

    $package = Expand-GearScoutPackage -ZipPath $ZipPath
    $results = New-Object System.Collections.Generic.List[object]

    if (-not $package.HasGearScout) {
        $results.Add([pscustomobject]@{
            FolderName = 'GearScout'
            Status     = 'error'
            Message    = 'The install package is missing GearScout\GearScout.toc, this does not look like a valid GearScout release.'
            LinkTarget = $null
        })
        Remove-StagingFolder -StagingRoot $package.StagingRoot
        return $results
    }

    $results.Add((Install-AddonFolder -PackageRoot $package.PackageRoot -FolderName 'GearScout' -AddOnsPath $AddOnsPath))

    if ($IncludeLead) {
        if ($package.HasLead) {
            $results.Add((Install-AddonFolder -PackageRoot $package.PackageRoot -FolderName 'GearScout_Lead' -AddOnsPath $AddOnsPath))
        } else {
            $results.Add([pscustomobject]@{
                FolderName = 'GearScout_Lead'
                Status     = 'error'
                Message    = 'GearScout_Lead was requested but the install package does not include it.'
                LinkTarget = $null
            })
        }
    }

    Remove-StagingFolder -StagingRoot $package.StagingRoot
    return $results
}
