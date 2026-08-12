# GearScout Installer / lib/Detect.ps1
#
# Finds World of Warcraft installations on any fixed drive and reports what
# is already in each one's Interface\AddOns folder. Read only: nothing in
# this file writes, deletes, or creates anything on disk. Installing is a
# separate step in InstallLogic.ps1.
#
# Meant to be dot sourced:  . "$PSScriptRoot\lib\Detect.ps1"
# Then call Find-WowCandidates to get the list.

Set-StrictMode -Version Latest

# ---------------------------------------------------------------------------
# Known flavour folder names. Blizzard adds new ones occasionally, so a
# generic pattern is also tried as a fallback (see Get-FlavourDirs).
# ---------------------------------------------------------------------------
$Script:KnownFlavours = @('_anniversary_', '_classic_', '_classic_era_', '_retail_')

$Script:FlavourLabels = @{
    '_anniversary_' = 'Anniversary'
    '_classic_'      = 'Classic'
    '_classic_era_'  = 'Classic Era'
    '_retail_'       = 'Retail'
}

function global:Get-FlavourLabel {
    param([string]$FlavourName)
    if ($Script:FlavourLabels.ContainsKey($FlavourName)) {
        return $Script:FlavourLabels[$FlavourName]
    }
    # Unrecognised flavour folder, e.g. a future _ptr_ or _beta_. Turn
    # "_something_else_" into "Something Else" rather than showing it raw.
    $bare = $FlavourName.Trim('_') -replace '_', ' '
    if (-not $bare) { return $FlavourName }
    $textInfo = (Get-Culture).TextInfo
    return $textInfo.ToTitleCase($bare)
}

# ---------------------------------------------------------------------------
# Reparse point safety helpers. GearScout is developed by editing files that
# live outside of Interface\AddOns and linking them in with a directory
# junction, so an AddOns\GearScout folder is sometimes not a real directory
# at all but a link to someone's working copy. Every place in this app that
# might delete or overwrite a folder must check this first.
# ---------------------------------------------------------------------------
function global:Test-IsReparsePoint {
    param([Parameter(Mandatory)][string]$Path)
    if (-not (Test-Path -LiteralPath $Path)) { return $false }
    $item = Get-Item -LiteralPath $Path -Force -ErrorAction SilentlyContinue
    if (-not $item) { return $false }
    return [bool]($item.Attributes -band [System.IO.FileAttributes]::ReparsePoint)
}

function global:Get-ReparseTarget {
    param([Parameter(Mandatory)][string]$Path)
    $item = Get-Item -LiteralPath $Path -Force -ErrorAction SilentlyContinue
    if ($item -and $item.PSObject.Properties['Target'] -and $item.Target) {
        return ($item.Target | Select-Object -First 1)
    }
    return $null
}

# ---------------------------------------------------------------------------
# Fixed, ready local drives only. Network and removable drives are skipped,
# scanning them is slow and WoW does not install there in practice.
# ---------------------------------------------------------------------------
function global:Get-FixedDriveRoots {
    [System.IO.DriveInfo]::GetDrives() |
        Where-Object { $_.DriveType -eq 'Fixed' -and $_.IsReady } |
        ForEach-Object { $_.RootDirectory.FullName }
}

# ---------------------------------------------------------------------------
# Obvious install roots to probe per drive, plus a shallow, targeted look for
# any folder literally named "World of Warcraft". This is deliberately not a
# full recursive scan of the drive, that would be slow and would wander into
# folders the app has no business reading.
# ---------------------------------------------------------------------------
function global:Get-CandidateWowRoots {
    $found = New-Object System.Collections.Generic.List[string]
    $seen  = New-Object 'System.Collections.Generic.HashSet[string]' ([System.StringComparer]::OrdinalIgnoreCase)

    foreach ($drive in Get-FixedDriveRoots) {
        $bases = @(
            $drive
            (Join-Path $drive 'Program Files (x86)')
            (Join-Path $drive 'Program Files')
            (Join-Path $drive 'Games')
            (Join-Path $drive 'Battle.net')
            (Join-Path $drive 'Blizzard')
            (Join-Path $drive 'Blizzard Games')
        )

        foreach ($base in $bases) {
            if (-not (Test-Path -LiteralPath $base)) { continue }

            # Direct hit: "<base>\World of Warcraft"
            $direct = Join-Path $base 'World of Warcraft'
            if (Test-Path -LiteralPath $direct -PathType Container) {
                if ($seen.Add($direct)) { $found.Add($direct) }
            }

            # One level of children whose name contains "World of Warcraft",
            # catches custom install names like "World of Warcraft (Retail)".
            try {
                Get-ChildItem -LiteralPath $base -Directory -ErrorAction SilentlyContinue |
                    Where-Object { $_.Name -like '*World of Warcraft*' } |
                    ForEach-Object {
                        if ($seen.Add($_.FullName)) { $found.Add($_.FullName) }
                    }
            } catch {
                # Permission errors on odd system folders are expected, skip quietly.
            }
        }
    }

    return $found
}

# ---------------------------------------------------------------------------
# Flavour subfolders inside one WoW root: the known names first, then a
# generic "_word_" pattern so a flavour Blizzard adds later still shows up.
# ---------------------------------------------------------------------------
function global:Get-FlavourDirs {
    param([Parameter(Mandatory)][string]$WowRoot)

    $names = New-Object 'System.Collections.Generic.HashSet[string]' ([System.StringComparer]::OrdinalIgnoreCase)
    foreach ($n in $Script:KnownFlavours) {
        if (Test-Path -LiteralPath (Join-Path $WowRoot $n) -PathType Container) {
            [void]$names.Add($n)
        }
    }

    try {
        Get-ChildItem -LiteralPath $WowRoot -Directory -ErrorAction SilentlyContinue |
            Where-Object { $_.Name -match '^_[A-Za-z0-9]+_$' } |
            ForEach-Object { [void]$names.Add($_.Name) }
    } catch {}

    return $names
}

# ---------------------------------------------------------------------------
# Reads "## Version: 0.10.0" (or similar) out of a .toc file. Returns $null
# if the file is missing or has no version line, never throws.
# ---------------------------------------------------------------------------
function global:Get-TocVersion {
    param([Parameter(Mandatory)][string]$TocPath)
    if (-not (Test-Path -LiteralPath $TocPath)) { return $null }
    try {
        $lines = Get-Content -LiteralPath $TocPath -ErrorAction Stop
    } catch {
        return $null
    }
    foreach ($line in $lines) {
        if ($line -match '^\s*##\s*Version:\s*(.+?)\s*$') {
            return $Matches[1]
        }
    }
    return $null
}

# ---------------------------------------------------------------------------
# State of one addon folder (GearScout or GearScout_Lead) under an AddOns
# path: missing, a normal installed copy, or a link to a development folder.
# Read only, safe to call any time.
# ---------------------------------------------------------------------------
function global:Get-AddonState {
    param(
        [Parameter(Mandatory)][string]$AddonsPath,
        [Parameter(Mandatory)][string]$FolderName
    )

    $folderPath = Join-Path $AddonsPath $FolderName
    $state = [ordered]@{
        FolderName = $FolderName
        Path       = $folderPath
        Exists     = $false
        IsLinked   = $false
        LinkTarget = $null
        Version    = $null
    }

    if (-not (Test-Path -LiteralPath $folderPath -PathType Container)) {
        return [pscustomobject]$state
    }
    $state.Exists = $true

    if (Test-IsReparsePoint -Path $folderPath) {
        $state.IsLinked   = $true
        $state.LinkTarget = Get-ReparseTarget -Path $folderPath
    }

    # Reading the version is safe even through a link, this never writes.
    $tocPath = Join-Path $folderPath "$FolderName.toc"
    $state.Version = Get-TocVersion -TocPath $tocPath

    return [pscustomobject]$state
}

# One line summary for the UI list, e.g. "Installed 0.10.0", "Not installed",
# or "Linked to a dev folder".
function global:Get-AddonStateLabel {
    param($AddonState)
    if (-not $AddonState.Exists) { return 'Not installed' }
    if ($AddonState.IsLinked) { return 'Linked to a dev folder' }
    if ($AddonState.Version) { return "Installed $($AddonState.Version)" }
    return 'Installed (version unknown)'
}

# ---------------------------------------------------------------------------
# Everything about one flavour folder found on disk: where it is, how many
# addons are already there, and the state of GearScout / GearScout_Lead.
# ---------------------------------------------------------------------------
function global:Get-FlavourCandidate {
    param(
        [Parameter(Mandatory)][string]$WowRoot,
        [Parameter(Mandatory)][string]$FlavourName
    )

    $flavourPath = Join-Path $WowRoot $FlavourName
    $addonsPath  = Join-Path $flavourPath 'Interface\AddOns'
    $addonsExists = Test-Path -LiteralPath $addonsPath -PathType Container

    $addonCount = 0
    if ($addonsExists) {
        try {
            $addonCount = (Get-ChildItem -LiteralPath $addonsPath -Directory -ErrorAction SilentlyContinue |
                Measure-Object).Count
        } catch { $addonCount = 0 }
    }

    $gearScout = Get-AddonState -AddonsPath $addonsPath -FolderName 'GearScout'
    $lead      = Get-AddonState -AddonsPath $addonsPath -FolderName 'GearScout_Lead'

    [pscustomobject]@{
        WowRoot       = $WowRoot
        Flavour       = $FlavourName
        FlavourLabel  = Get-FlavourLabel $FlavourName
        FlavourPath   = $flavourPath
        AddOnsPath    = $addonsPath
        AddOnsExists  = $addonsExists
        AddonCount    = $addonCount
        IsAnniversary = ($FlavourName -eq '_anniversary_')
        GearScout     = $gearScout
        Lead          = $lead
        DisplayLabel  = "$(Get-FlavourLabel $FlavourName) - $flavourPath ($addonCount addons already installed)"
    }
}

# ---------------------------------------------------------------------------
# Top level entry point. Returns every flavour candidate found across every
# WoW root on every fixed drive, sorted with the most likely "real" install
# first: Anniversary (the flavour GearScout targets) before other flavours,
# then whichever has the most existing addons, since a well used AddOns
# folder is a strong signal this is the account someone actually plays on.
# ---------------------------------------------------------------------------
function global:Find-WowCandidates {
    $results = New-Object System.Collections.Generic.List[object]

    foreach ($root in Get-CandidateWowRoots) {
        foreach ($flavour in (Get-FlavourDirs -WowRoot $root)) {
            $results.Add((Get-FlavourCandidate -WowRoot $root -FlavourName $flavour))
        }
    }

    return $results | Sort-Object -Property `
        @{ Expression = { [int]$_.IsAnniversary }; Descending = $true }, `
        @{ Expression = 'AddonCount'; Descending = $true }, `
        @{ Expression = 'WowRoot'; Descending = $false }
}
