# GearScout Installer
#
# A portable, no-install WPF app. Finds World of Warcraft on this machine,
# shows what is already there, and installs or updates GearScout in one
# click. Styled to match the addon's own Obsidian skin (see GearScout/Skin.lua).
#
# Run it through GearScoutInstaller.cmd, not this file directly, so a double
# click from Explorer works without a PowerShell console popping up bare.

# ===========================================================================
# FILL ME IN
# The GitHub repo that publishes GearScout releases. Once this points at a
# real repo, the installer prefers downloading the newest release from there
# and only falls back to the zip sitting next to this app when that fails
# (no repo configured yet, no network, no release, whatever). Leave both
# blank to always use the local zip.
# ===========================================================================
$GitHubOwner = 'Ryzz3nn'
$GitHubRepo  = 'GearScout'

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$Script:AppDir = $PSScriptRoot

# ---------------------------------------------------------------------------
# Where the launcher the player actually double clicked lives, for the
# desktop shortcut (see New-DesktopUpdaterShortcut in lib\InstallLogic.ps1).
# This script only ever knows where it itself is running from, and in the
# bundled case (dist\GearScoutInstaller.bat) that is a fresh %TEMP% folder
# about to be deleted, not the .bat the player actually launched. So the
# batch header passes its own path through as the GSI_SELF environment
# variable (see tools/build-installer.mjs). When that is not set, this is
# the unbundled, folder based build, and the launcher is just
# GearScoutInstaller.cmd sitting next to this script.
# ---------------------------------------------------------------------------
$Script:LauncherSelf =
    if ($env:GSI_SELF) { $env:GSI_SELF }
    else { Join-Path $PSScriptRoot 'GearScoutInstaller.cmd' }

Add-Type -AssemblyName PresentationFramework, PresentationCore, WindowsBase, System.Xaml, System.Windows.Forms

# ---------------------------------------------------------------------------
# Last resort error surface. Used before the WPF window exists, or if the
# window itself fails to build. The user should never see a raw stack trace.
# ---------------------------------------------------------------------------
function global:Show-FatalError {
    param([string]$Message)
    try {
        [System.Windows.Forms.MessageBox]::Show(
            "GearScout Installer ran into a problem and has to close.`n`n$Message",
            'GearScout Installer',
            [System.Windows.Forms.MessageBoxButtons]::OK,
            [System.Windows.Forms.MessageBoxIcon]::Error) | Out-Null
    } catch {
        # If even Windows Forms is unavailable, there is nothing left to show with.
    }
}

# ---------------------------------------------------------------------------
# Shared state. Kept at script scope so both the top level and event handler
# script blocks (which close over the scope they were defined in) see the
# same values.
# ---------------------------------------------------------------------------
$Script:Candidates        = @()
$Script:SelectedCandidate = $null
$Script:SourceInfo        = $null
$Script:ManualCandidateSeq = 0

# ---------------------------------------------------------------------------
# Accessors for the shared state above. Event handler script blocks are
# built with .GetNewClosure() so they keep working after Initialize-MainWindow
# returns (PowerShell would otherwise lose access to that function's local
# variables, like $window and $statusText, once it exits). GetNewClosure
# also freezes a snapshot of any $script: scoped variable read directly
# inside the handler body, so a handler that reads $Script:SelectedCandidate
# by itself would always see whatever it was at the moment the window was
# built, never a later change. Routing every read and write through a plain
# function like the ones below avoids that: a normal function call always
# resolves $script: variables live, closure or no closure.
# ---------------------------------------------------------------------------
function global:Get-SelectedCandidate { return $Script:SelectedCandidate }
function global:Get-SourceInfo { return $Script:SourceInfo }
function global:Select-CandidateByIndex {
    param([int]$Index)
    if ($Index -ge 0 -and $Index -lt $Script:Candidates.Count) {
        $Script:SelectedCandidate = $Script:Candidates[$Index]
    } else {
        $Script:SelectedCandidate = $null
    }
    return $Script:SelectedCandidate
}

# ---------------------------------------------------------------------------
# Builds one small coloured status line for a folder (GearScout or
# GearScout_Lead): not installed, installed vX, or linked to a dev folder.
# ---------------------------------------------------------------------------
function global:New-StatusBadge {
    param($Window, [string]$Label, $State)

    $panel = New-Object System.Windows.Controls.StackPanel
    $panel.Orientation = 'Vertical'

    $lbl = New-Object System.Windows.Controls.TextBlock
    $lbl.Text = $Label
    $lbl.FontSize = 10
    $lbl.Foreground = $Window.Resources['DimBrush']
    [void]$panel.Children.Add($lbl)

    $val = New-Object System.Windows.Controls.TextBlock
    $val.Text = Get-AddonStateLabel $State
    $val.FontSize = 11
    $val.FontWeight = 'SemiBold'
    if ($State.IsLinked) {
        $val.Foreground = $Window.Resources['AccentBrush']
        $val.ToolTip = "This folder is a link to a development folder:`n$($State.LinkTarget)`n`nIt is already live and will not be touched."
    } elseif ($State.Exists) {
        $val.Foreground = $Window.Resources['GoodBrush']
    } else {
        $val.Foreground = $Window.Resources['DimBrush']
    }
    [void]$panel.Children.Add($val)
    return $panel
}

# ---------------------------------------------------------------------------
# One selectable row in the install list: flavour, path, addon count, and
# the GearScout / GearScout_Lead status badges. Selection colouring is
# applied afterwards by Update-ListSelectionVisuals, not baked in here.
# ---------------------------------------------------------------------------
function global:New-CandidateItemVisual {
    param($Window, $Candidate)

    $outer = New-Object System.Windows.Controls.Border
    $outer.CornerRadius = 8
    $outer.BorderThickness = 1
    $outer.Padding = 12
    $outer.Background = $Window.Resources['PanelBrush']
    $outer.BorderBrush = $Window.Resources['LineHardBrush']

    $stack = New-Object System.Windows.Controls.StackPanel

    $titleRow = New-Object System.Windows.Controls.TextBlock
    $titleRow.Text = $Candidate.FlavourLabel
    $titleRow.FontWeight = 'SemiBold'
    $titleRow.FontSize = 13
    $titleRow.Foreground = $Window.Resources['TextBrush']
    [void]$stack.Children.Add($titleRow)

    $pathRow = New-Object System.Windows.Controls.TextBlock
    $pathRow.Text = $Candidate.FlavourPath
    $pathRow.FontSize = 11
    $pathRow.Foreground = $Window.Resources['DimBrush']
    $pathRow.Margin = '0,2,0,0'
    $pathRow.TextWrapping = 'Wrap'
    [void]$stack.Children.Add($pathRow)

    $countRow = New-Object System.Windows.Controls.TextBlock
    $countRow.Text = "$($Candidate.AddonCount) addons already in this AddOns folder"
    $countRow.FontSize = 11
    $countRow.Foreground = $Window.Resources['DimBrush']
    $countRow.Margin = '0,2,0,8'
    [void]$stack.Children.Add($countRow)

    $statusPanel = New-Object System.Windows.Controls.StackPanel
    $statusPanel.Orientation = 'Horizontal'
    $gsBadge = New-StatusBadge -Window $Window -Label 'GearScout' -State $Candidate.GearScout
    $leadBadge = New-StatusBadge -Window $Window -Label 'GearScout_Lead' -State $Candidate.Lead
    $leadBadge.Margin = '20,0,0,0'
    [void]$statusPanel.Children.Add($gsBadge)
    [void]$statusPanel.Children.Add($leadBadge)
    [void]$stack.Children.Add($statusPanel)

    $outer.Child = $stack
    return $outer
}

# Repaints selection colouring across all list items without rebuilding them.
function global:Update-ListSelectionVisuals {
    param($Window, $ListBox)
    for ($i = 0; $i -lt $ListBox.Items.Count; $i++) {
        $item = $ListBox.Items[$i]
        if ($item -isnot [System.Windows.Controls.ListBoxItem]) { continue }
        $border = $item.Content
        if ($border -isnot [System.Windows.Controls.Border]) { continue }
        if ($item.IsSelected) {
            $border.BorderBrush = $Window.Resources['AccentBrush']
            $border.Background = $Window.Resources['HoverBrush']
        } else {
            $border.BorderBrush = $Window.Resources['LineHardBrush']
            $border.Background = $Window.Resources['PanelBrush']
        }
    }
}

# ---------------------------------------------------------------------------
# Re-runs detection and refills the list. Keeps the previously selected
# AddOns path selected if it is still present, otherwise selects the top
# (most likely) candidate.
# ---------------------------------------------------------------------------
function global:Update-CandidateList {
    param($Window, $ListBox)

    $previousPath = $null
    if ($Script:SelectedCandidate) { $previousPath = $Script:SelectedCandidate.AddOnsPath }

    $ListBox.Items.Clear()
    $Script:Candidates = @(Find-WowCandidates)

    if ($Script:Candidates.Count -eq 0) {
        $placeholder = New-Object System.Windows.Controls.Border
        $placeholder.CornerRadius = 8
        $placeholder.BorderThickness = 1
        $placeholder.Padding = 12
        $placeholder.Background = $Window.Resources['PanelBrush']
        $placeholder.BorderBrush = $Window.Resources['LineHardBrush']
        $msg = New-Object System.Windows.Controls.TextBlock
        $msg.Text = 'No World of Warcraft installation was found automatically. Use "Browse for a different folder" below and point at your Interface\AddOns folder (or the folder that should contain it).'
        $msg.TextWrapping = 'Wrap'
        $msg.Foreground = $Window.Resources['WarnBrush']
        $msg.FontSize = 12
        $placeholder.Child = $msg
        $li = New-Object System.Windows.Controls.ListBoxItem
        $li.Content = $placeholder
        $li.IsHitTestVisible = $false
        [void]$ListBox.Items.Add($li)
        $Script:SelectedCandidate = $null
        return
    }

    $selectIndex = 0
    for ($i = 0; $i -lt $Script:Candidates.Count; $i++) {
        $c = $Script:Candidates[$i]
        $visual = New-CandidateItemVisual -Window $Window -Candidate $c
        $li = New-Object System.Windows.Controls.ListBoxItem
        $li.Content = $visual
        [void]$ListBox.Items.Add($li)
        if ($previousPath -and $c.AddOnsPath -eq $previousPath) { $selectIndex = $i }
    }

    $ListBox.SelectedIndex = $selectIndex
    $Script:SelectedCandidate = $Script:Candidates[$selectIndex]
    Update-ListSelectionVisuals -Window $Window -ListBox $ListBox
}

# ---------------------------------------------------------------------------
# Adds a manually browsed folder to the top of the list as its own
# candidate, the same shape Find-WowCandidates produces.
# ---------------------------------------------------------------------------
function global:Add-ManualCandidate {
    param($Window, $ListBox, [string]$AddOnsPath)

    if (-not (Test-Path -LiteralPath $AddOnsPath)) {
        try { New-Item -ItemType Directory -Force -Path $AddOnsPath | Out-Null } catch {
            throw "Could not use '$AddOnsPath': $($_.Exception.Message)"
        }
    }

    $Script:ManualCandidateSeq++
    $addonCount = 0
    try {
        $addonCount = (Get-ChildItem -LiteralPath $AddOnsPath -Directory -ErrorAction SilentlyContinue | Measure-Object).Count
    } catch {}

    $candidate = [pscustomobject]@{
        WowRoot       = $AddOnsPath
        Flavour       = 'custom'
        FlavourLabel  = 'Folder you chose'
        FlavourPath   = $AddOnsPath
        AddOnsPath    = $AddOnsPath
        AddOnsExists  = $true
        AddonCount    = $addonCount
        IsAnniversary = $false
        GearScout     = (Get-AddonState -AddonsPath $AddOnsPath -FolderName 'GearScout')
        Lead          = (Get-AddonState -AddonsPath $AddOnsPath -FolderName 'GearScout_Lead')
        DisplayLabel  = "Folder you chose - $AddOnsPath"
    }

    $Script:Candidates = @($candidate) + @($Script:Candidates)
    $ListBox.Items.Clear()
    for ($i = 0; $i -lt $Script:Candidates.Count; $i++) {
        $visual = New-CandidateItemVisual -Window $Window -Candidate $Script:Candidates[$i]
        $li = New-Object System.Windows.Controls.ListBoxItem
        $li.Content = $visual
        [void]$ListBox.Items.Add($li)
    }
    $ListBox.SelectedIndex = 0
    $Script:SelectedCandidate = $candidate
    Update-ListSelectionVisuals -Window $Window -ListBox $ListBox
}

# ---------------------------------------------------------------------------
# Refreshes the "where the files come from" line, and shows or hides the
# GearScout_Lead checkbox to match. Only GearScout is published publicly:
# GearScout_Lead is the officer only half, handed out privately, and is
# never downloaded from GitHub. The checkbox only appears when the resolved
# package (always the local zip in that case) actually contains it, so
# there is never a dead control sitting on screen doing nothing.
# ---------------------------------------------------------------------------
function global:Update-SourceInfo {
    param($Window, $SourceText, $LeadCheckBox, $LeadExplainText)
    $Script:SourceInfo = Resolve-InstallSource -AppDir $Script:AppDir -GitHubOwner $GitHubOwner -GitHubRepo $GitHubRepo
    $SourceText.Text = $Script:SourceInfo.Message
    $SourceText.Foreground = switch ($Script:SourceInfo.Kind) {
        'github' { $Window.Resources['GoodBrush'] }
        'local'  { $Window.Resources['DimBrush'] }
        default  { $Window.Resources['BadBrush'] }
    }

    if ($Script:SourceInfo.LeadAvailable) {
        $LeadCheckBox.Visibility = [System.Windows.Visibility]::Visible
        $LeadExplainText.Visibility = [System.Windows.Visibility]::Visible
    } else {
        $LeadCheckBox.IsChecked = $false
        $LeadCheckBox.Visibility = [System.Windows.Visibility]::Collapsed
        $LeadExplainText.Visibility = [System.Windows.Visibility]::Collapsed
    }
}

# ---------------------------------------------------------------------------
# Keeps the "here is what will happen" text in sync with the current
# selection and the GearScout_Lead checkbox, before anything is installed.
# ---------------------------------------------------------------------------
function global:Update-Summary {
    param($Window, $SummaryText, $InstallButton, $IncludeLead)

    if (-not $Script:SelectedCandidate) {
        $SummaryText.Text = 'Select an installation above, or use Browse, before installing.'
        $SummaryText.Foreground = $Window.Resources['DimBrush']
        $InstallButton.IsEnabled = $false
        return
    }

    $c = $Script:SelectedCandidate
    $lines = New-Object System.Collections.Generic.List[string]

    if ($c.GearScout.IsLinked) {
        $lines.Add("GearScout here is linked to a development folder and will be left alone.")
    } else {
        $lines.Add("GearScout will be installed into: $($c.AddOnsPath)")
    }

    if ($IncludeLead) {
        if ($c.Lead.IsLinked) {
            $lines.Add("GearScout_Lead here is linked to a development folder and will be left alone.")
        } else {
            $lines.Add("GearScout_Lead will also be installed.")
        }
    }

    if ($Script:SourceInfo -and -not $Script:SourceInfo.ZipPath) {
        $lines.Add("No install package is available right now, Install is disabled until one is found.")
        $InstallButton.IsEnabled = $false
    } else {
        $InstallButton.IsEnabled = $true
    }

    $SummaryText.Text = [string]::Join("`n", $lines.ToArray())
    $SummaryText.Foreground = $Window.Resources['TextBrush']
}

# ---------------------------------------------------------------------------
# Builds the window, wires every control up, and returns it. Does not show
# it, the caller decides when (or whether) to call ShowDialog, which is what
# makes this testable without blocking on a real GUI.
# ---------------------------------------------------------------------------
function global:Initialize-MainWindow {
    $xamlPath = Join-Path $Script:AppDir 'GearScoutInstaller.xaml'
    if (-not (Test-Path -LiteralPath $xamlPath)) {
        throw "Missing $xamlPath, the installer window cannot be built."
    }
    [xml]$xamlXml = Get-Content -LiteralPath $xamlPath -Raw
    $reader = New-Object System.Xml.XmlNodeReader $xamlXml
    $window = [System.Windows.Markup.XamlReader]::Load($reader)

    $titleBar      = $window.FindName('TitleBar')
    $closeButton   = $window.FindName('CloseButton')
    $installList   = $window.FindName('InstallList')
    $browseButton  = $window.FindName('BrowseButton')
    $leadCheckBox  = $window.FindName('LeadCheckBox')
    $leadExplainText = $window.FindName('LeadExplainText')
    $shortcutCheckBox = $window.FindName('ShortcutCheckBox')
    $sourceText    = $window.FindName('SourceText')
    $summaryText   = $window.FindName('SummaryText')
    $installButton = $window.FindName('InstallButton')
    $rescanButton  = $window.FindName('RescanButton')
    $statusText    = $window.FindName('StatusText')

    foreach ($needed in 'titleBar','closeButton','installList','browseButton','leadCheckBox','leadExplainText',
                         'shortcutCheckBox','sourceText','summaryText','installButton','rescanButton','statusText') {
        if (-not (Get-Variable -Name $needed -ValueOnly)) {
            throw "The installer window is missing an expected control: $needed"
        }
    }

    # Also built with GetNewClosure, otherwise it would lose access to
    # $window, $summaryText, $installButton and $leadCheckBox the moment
    # this function returns, see the note above Get-SelectedCandidate.
    $refreshSummary = {
        Update-Summary -Window $window -SummaryText $summaryText -InstallButton $installButton -IncludeLead $leadCheckBox.IsChecked
    }.GetNewClosure()

    # --- window chrome -----------------------------------------------------
    $titleBar.Add_MouseLeftButtonDown({
        param($s, $e)
        try { if ($e.ChangedButton -eq [System.Windows.Input.MouseButton]::Left) { $window.DragMove() } } catch {}
    }.GetNewClosure())
    $closeButton.Add_Click({ $window.Close() }.GetNewClosure())

    # --- install list --------------------------------------------------------
    $installList.Add_SelectionChanged({
        try {
            Select-CandidateByIndex -Index $installList.SelectedIndex | Out-Null
            Update-ListSelectionVisuals -Window $window -ListBox $installList
            & $refreshSummary
        } catch {
            $statusText.Text = "Error: $($_.Exception.Message)"
            $statusText.Foreground = $window.Resources['BadBrush']
        }
    }.GetNewClosure())

    # --- browse for a folder -------------------------------------------------
    $browseButton.Add_Click({
        try {
            $dlg = New-Object System.Windows.Forms.FolderBrowserDialog
            $dlg.Description = 'Select your WoW flavour folder (for example "_retail_"), or the Interface\AddOns folder inside it.'
            $dlg.ShowNewFolderButton = $false
            $result = $dlg.ShowDialog()
            if ($result -ne [System.Windows.Forms.DialogResult]::OK) { return }

            $chosen = $dlg.SelectedPath
            $addonsPath =
                if ((Split-Path -Leaf $chosen) -ieq 'AddOns' -and (Split-Path -Leaf (Split-Path -Parent $chosen)) -ieq 'Interface') {
                    $chosen
                } elseif (Test-Path -LiteralPath (Join-Path $chosen 'Interface\AddOns')) {
                    Join-Path $chosen 'Interface\AddOns'
                } else {
                    Join-Path $chosen 'Interface\AddOns'
                }

            Add-ManualCandidate -Window $window -ListBox $installList -AddOnsPath $addonsPath
            & $refreshSummary
            $statusText.Text = "Using $addonsPath"
            $statusText.Foreground = $window.Resources['DimBrush']
        } catch {
            $statusText.Text = "Error: $($_.Exception.Message)"
            $statusText.Foreground = $window.Resources['BadBrush']
        }
    }.GetNewClosure())

    # --- options ---------------------------------------------------------
    $leadCheckBox.Add_Checked({ & $refreshSummary }.GetNewClosure())
    $leadCheckBox.Add_Unchecked({ & $refreshSummary }.GetNewClosure())

    # --- rescan ------------------------------------------------------------
    $rescanButton.Add_Click({
        try {
            $statusText.Text = ''
            Update-CandidateList -Window $window -ListBox $installList
            Update-SourceInfo -Window $window -SourceText $sourceText -LeadCheckBox $leadCheckBox -LeadExplainText $leadExplainText
            & $refreshSummary
        } catch {
            $statusText.Text = "Error while scanning: $($_.Exception.Message)"
            $statusText.Foreground = $window.Resources['BadBrush']
        }
    }.GetNewClosure())

    # --- install -------------------------------------------------------------
    $installButton.Add_Click({
        try {
            $candidate = Get-SelectedCandidate
            $source = Get-SourceInfo
            if (-not $candidate) { return }
            if (-not $source -or -not $source.ZipPath) {
                $statusText.Text = 'No install package is available. Put a GearScout zip next to this app and click Scan again.'
                $statusText.Foreground = $window.Resources['BadBrush']
                return
            }

            $installButton.IsEnabled = $false
            $statusText.Text = 'Installing...'
            $statusText.Foreground = $window.Resources['DimBrush']

            # GearScout_Lead is only ever installed from a package that both
            # offers it (never true for a GitHub sourced package, see
            # Resolve-InstallSource) and that the user asked for.
            $includeLead = [bool]($source.LeadAvailable -and $leadCheckBox.IsChecked)

            $results = Install-GearScoutPackage -ZipPath $source.ZipPath `
                -AddOnsPath $candidate.AddOnsPath -IncludeLead:$includeLead

            $hasError   = $false
            $hasLinked  = $false
            $lines = New-Object System.Collections.Generic.List[string]
            foreach ($r in $results) {
                $lines.Add($r.Message)
                if ($r.Status -eq 'error') { $hasError = $true }
                if ($r.Status -eq 'skipped_linked') { $hasLinked = $true }
            }

            # Only ever after a successful install, never on launch, and
            # only if the player actually asked for it. A shortcut problem
            # is reported here but never turns this red: the addon being
            # installed is what matters, see New-DesktopUpdaterShortcut.
            if (-not $hasError -and $shortcutCheckBox.IsChecked) {
                $shortcutResult = New-DesktopUpdaterShortcut -LauncherPath $Script:LauncherSelf -InstallerSourceDir $Script:AppDir
                $lines.Add($shortcutResult.Message)
            }

            $statusText.Text = [string]::Join("`n", $lines.ToArray())
            $statusText.Foreground =
                if ($hasError) { $window.Resources['BadBrush'] }
                elseif ($hasLinked) { $window.Resources['AccentBrush'] }
                else { $window.Resources['GoodBrush'] }

            Update-CandidateList -Window $window -ListBox $installList
            & $refreshSummary
        } catch {
            $statusText.Text = "Install failed: $($_.Exception.Message)"
            $statusText.Foreground = $window.Resources['BadBrush']
        } finally {
            $installButton.IsEnabled = $true
        }
    }.GetNewClosure())

    # --- first load ----------------------------------------------------------
    $window.Add_Loaded({
        try {
            $statusText.Text = ''
            Update-CandidateList -Window $window -ListBox $installList
            Update-SourceInfo -Window $window -SourceText $sourceText -LeadCheckBox $leadCheckBox -LeadExplainText $leadExplainText
            & $refreshSummary
        } catch {
            $statusText.Text = "Error while scanning: $($_.Exception.Message)"
            $statusText.Foreground = $window.Resources['BadBrush']
        }
    }.GetNewClosure())

    return $window
}

# ===========================================================================
# Entry point. Dot sourcing this file (as the test harness does) skips
# ShowDialog so the window can be built and inspected without blocking.
# ===========================================================================
try {
    . (Join-Path $PSScriptRoot 'lib\Detect.ps1')
    . (Join-Path $PSScriptRoot 'lib\InstallLogic.ps1')

    if ($MyInvocation.InvocationName -ne '.') {
        $Script:MainWindow = Initialize-MainWindow
        [void]$Script:MainWindow.ShowDialog()
    }
} catch {
    Show-FatalError -Message $_.Exception.Message
    if ($MyInvocation.InvocationName -ne '.') { exit 1 }
}
