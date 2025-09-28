<# =====================================================================
  bootstrap-scoop.ps1 — Windows 11 setup via Scoop (one-page GUI picker)
  ----------------------------------------------------------------------
  • Runs interactively by default (no flags needed)
  • One-page GUI picker (Core + Extras side-by-side) when WinForms is available
    - Fallback: Out-GridView (if available), else text-based picker
  • Per-user Scoop install/check + buckets
  • Prereqs: 7zip, innounp, dark
  • aria2 enabled + tuned
  • VS Code system-install detect (default unchecked in Core)
  • Quiet installs with verbose-retry logs on failure (.\logs\*.log)
  • Version summary via 'scoop export'
  • Closing notes appear AFTER the Summary
===================================================================== #>

[CmdletBinding()]
param(
    [switch]$NonInteractive,
    [ValidateSet('auto','winforms','ogv','text')]
    [string]$Picker = 'auto'
)

$ErrorActionPreference = 'Stop'

# =========================
# Status (for Summary)
# =========================
$Status = [ordered]@{
    ScoopInstall       = "Pending"
    Buckets            = @()
    Aria2              = "Pending"
    PrereqsNew         = @()
    PrereqsExisting    = @()
    PrereqsFailed      = @()
    CoreAppsChosen     = @()
    CoreAppsNew        = @()
    CoreAppsExisting   = @()
    CoreAppsFailed     = @()
    ExtrasCatalog      = @()
    ExtrasChosen       = @()
    ExtrasNew          = @()
    ExtrasExisting     = @()
    ExtrasFailed       = @()
    TerminalIcons      = "Pending"
    Checkup            = "Pending"
    UpdateRan          = "No"
    UpdatedApps        = @()
}

# =========================
# Helpers
# =========================
function Resolve-PickerPreference {
    param(
        [switch]$NonInteractive,
        [ValidateSet('auto','winforms','ogv','text')]
        [string]$PickerDefault = 'auto'
    )

    if ($NonInteractive) { return $PickerDefault }

    # What’s actually available?
    $canWinForms = Test-CanUseWinForms
    $hasOGV      = Test-HasOutGridView

    # Build the prompt text based on availability
    $opts = @()
    if ($canWinForms) { $opts += "type 'g' for GUI" }
    if ($hasOGV)      { $opts += "type 'o' for Out-GridView" }
    $hint = if ($opts) { " or " + ($opts -join ", ") } else { "" }

    Write-Host ""
    Write-Host "How do you want to do this?" -ForegroundColor Cyan
    Write-Host "Press Enter for DEFAULT/TEXT selector (numbers/all/none)$hint." -ForegroundColor Yellow
    $resp = Read-Host "Selection"

    if ([string]::IsNullOrWhiteSpace($resp)) { return 'text' }
    switch ($resp.ToLowerInvariant()) {
        'g'   { if ($canWinForms) { return 'winforms' } else { Write-Host "GUI not available; falling back to text."; return 'text' } }
        'o'   { if ($hasOGV)      { return 'ogv' }      else { Write-Host "Out-GridView not available; falling back to text."; return 'text' } }
        't'   { return 'text' }
        'auto'{ return 'auto' }
        default { return 'text' }
    }
}
function Get-ScoopRoot {
    if ($env:SCOOP -and (Test-Path $env:SCOOP)) { return $env:SCOOP }
    return (Join-Path $env:USERPROFILE 'scoop')
}
function Test-Command {
    param([Parameter(Mandatory)][string]$Name)
    return [bool](Get-Command $Name -ErrorAction SilentlyContinue)
}
function Test-AppInstalled {
    param([Parameter(Mandatory)][string]$Name)
    $root = Get-ScoopRoot
    return (Test-Path (Join-Path $root "apps\$Name\current"))
}
function Get-InstalledMap {
    $map = @{}
    try {
        $json = scoop export 2>$null
        if ($json) {
            $obj = $json | ConvertFrom-Json
            foreach ($a in ($obj.apps | Where-Object { $_.Name })) {
                $map[$a.Name] = $a.Version
            }
        }
    } catch { }
    return $map
}
function Resolve-Selection {
    param([string]$InputText,[int]$MaxIndex)
    $collected = @()
    foreach ($chunk in ($InputText -split '\s*,\s*' | Where-Object { $_ })) {
        if ($chunk -match '^\d+\-\d+$') {
            $b = $chunk -split '-'; $lo=[int]$b[0]; $hi=[int]$b[1]
            if ($hi -lt $lo) { $t=$lo; $lo=$hi; $hi=$t }
            for ($i=$lo; $i -le $hi; $i++) { if ($i -ge 1 -and $i -le $MaxIndex) { $collected += $i } }
        } elseif ($chunk -match '^\d+$') {
            $i=[int]$chunk; if ($i -ge 1 -and $i -le $MaxIndex) { $collected += $i }
        }
    }
    return @($collected | Sort-Object -Unique)
}
function Test-SystemVSCodeInstalled {
    try {
        $paths = @(
            "$Env:ProgramFiles\Microsoft VS Code\Code.exe",
            "$Env:ProgramFiles(x86)\Microsoft VS Code\Code.exe",
            "$Env:LOCALAPPDATA\Programs\Microsoft VS Code\Code.exe",
            (Join-Path "$Env:LOCALAPPDATA\Microsoft\WindowsApps" "Code.exe")
        )
        foreach ($p in $paths) { if (Test-Path $p) { return $true } }
    } catch { }
    return $false
}

# Picker capability checks
function Test-CanUseWinForms {
    try {
        Add-Type -AssemblyName System.Windows.Forms -ErrorAction Stop | Out-Null
        Add-Type -AssemblyName System.Drawing       -ErrorAction Stop | Out-Null
        return $true
    } catch { return $false }
}
function Test-HasOutGridView {
    return [bool](Get-Command Out-GridView -ErrorAction SilentlyContinue)
}

# Text picker (fallback)
function Choose-FromChecklist {
    param(
        [string]$Title,
        [string[]]$Items,
        [hashtable]$Prechecked = $null,
        [hashtable]$Notes      = $null,
        [switch]$NonInteractive
    )
    if ($NonInteractive) {
        $selected = @()
        foreach ($n in $Items) {
            $isChecked = if ($Prechecked.ContainsKey($n)) { [bool]$Prechecked[$n] } else { $true }
            if ($isChecked) { $selected += $n }
        }
        return ,$selected
    }
    Write-Host ""
    Write-Host ("=== {0} ===" -f $Title) -ForegroundColor Cyan
    for ($i=0; $i -lt $Items.Count; $i++) {
        $name = $Items[$i]
        $note    = if ($Notes -and $Notes.ContainsKey($name)) { "  (" + $Notes[$name] + ")" } else { "" }
	$already = if (Test-AppInstalled $name) { "  {installed}" } else { "" }
	Write-Host ("  {0,2}. {1}{2}{3}" -f ($i+1), $name, $already, $note)

    }
    Write-Host ""
    Write-Host "Select items to install:" -ForegroundColor Yellow
    Write-Host " - Enter numbers (e.g., 1,3,5-7)"
    Write-Host " - Type 'all' for all, 'none' to skip all, or Enter for defaults"
    $resp = Read-Host "Your choice"
    if ($resp -match '^\s*$') {
        $selected = @(); foreach ($n in $Items) {
            $isChecked = if ($Prechecked.ContainsKey($n)) { [bool]$Prechecked[$n] } else { $true }
            if ($isChecked) { $selected += $n }
        }
        return ,$selected
    } elseif ($resp -match '^(all)$') { return ,$Items }
    elseif ($resp -match '^(none)$') { return @() }
    else {
        $idxs = Resolve-Selection -InputText $resp -MaxIndex $Items.Count
        if ($idxs.Count -gt 0) { return ($idxs | ForEach-Object { $Items[$_-1] }) }
        return @()
    }
}

# One-page WinForms picker (Core + Extras)
function Show-CombinedPickerWinForms {
    param(
        [string[]]$CoreItems,
        [hashtable]$CorePrechecked,
        [hashtable]$CoreNotes,
        [string[]]$ExtrasItems,
        [hashtable]$ExtrasPrechecked,
        [hashtable]$ExtrasNotes
    )

    Add-Type -AssemblyName System.Windows.Forms | Out-Null
    Add-Type -AssemblyName System.Drawing       | Out-Null

    # Build row models
    $coreRows = foreach ($n in $CoreItems) {
        $checked   = if ($CorePrechecked.ContainsKey($n)) { [bool]$CorePrechecked[$n] } else { $false }
        $installed = if (Test-AppInstalled $n) { '{installed}' } else { '' }
        $note      = if ($CoreNotes -and $CoreNotes.ContainsKey($n)) { $CoreNotes[$n] } else { '' }
        [PSCustomObject]@{ Name=$n; Checked=$checked; Installed=$installed; Note=$note }
    }
    $extraRows = foreach ($n in $ExtrasItems) {
        $checked   = if ($ExtrasPrechecked.ContainsKey($n)) { [bool]$ExtrasPrechecked[$n] } else { $false }
        $installed = if (Test-AppInstalled $n) { '{installed}' } else { '' }
        $note      = if ($ExtrasNotes -and $ExtrasNotes.ContainsKey($n)) { $ExtrasNotes[$n] } else { '' }
        [PSCustomObject]@{ Name=$n; Checked=$checked; Installed=$installed; Note=$note }
    }

    # ---------- FORM ----------
    $form               = New-Object System.Windows.Forms.Form
    $form.Text          = "Choose apps to install"
    $form.StartPosition = 'CenterScreen'
    $form.Size          = New-Object System.Drawing.Size(980, 700)
    $form.MinimumSize   = New-Object System.Drawing.Size(700, 560)
    $form.MaximizeBox   = $true

    # Decide side-by-side vs stacked based on available width
    $workW = [System.Windows.Forms.Screen]::PrimaryScreen.WorkingArea.Width
    $stackVertically = $workW -lt 1000  # if narrow, stack vertically

    # Split container holds Core (Panel1) and Extras (Panel2)
    $split = New-Object System.Windows.Forms.SplitContainer
    $split.Dock = 'Fill'
    $split.Orientation = if ($stackVertically) { [System.Windows.Forms.Orientation]::Horizontal } else { [System.Windows.Forms.Orientation]::Vertical }
    $split.SplitterWidth = 6
    $split.IsSplitterFixed = $false
    $form.Controls.Add($split)

    # Helper: create one side (group with search + list + buttons)
    function New-ListGroup {
        param([string]$Title)

        $panel = New-Object System.Windows.Forms.Panel
        $panel.Dock = 'Fill'

        $grp = New-Object System.Windows.Forms.GroupBox
        $grp.Text = $Title
        $grp.Dock = 'Fill'
        $panel.Controls.Add($grp)

        $layout = New-Object System.Windows.Forms.TableLayoutPanel
        $layout.Dock = 'Fill'
        $layout.RowCount = 3
        $layout.ColumnCount = 1
        $layout.RowStyles.Add( (New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::Absolute, 32)) )  # search
        $layout.RowStyles.Add( (New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::Percent, 100)) )  # list
        $layout.RowStyles.Add( (New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::Absolute, 40)) )  # buttons
        $grp.Controls.Add($layout)

        $txt = New-Object System.Windows.Forms.TextBox
        $txt.PlaceholderText = "Filter…"
        $txt.Dock = 'Fill'
        $layout.Controls.Add($txt, 0, 0)

        $clb = New-Object System.Windows.Forms.CheckedListBox
        $clb.CheckOnClick = $true
        $clb.Dock = 'Fill'
        $clb.IntegralHeight = $false
        $clb.HorizontalScrollbar = $true   # enable horizontal scrollbar
        $layout.Controls.Add($clb, 0, 1)

        $btnPanel = New-Object System.Windows.Forms.FlowLayoutPanel
        $btnPanel.FlowDirection = 'LeftToRight'
        $btnPanel.Dock = 'Fill'
        $layout.Controls.Add($btnPanel, 0, 2)

        $btnAll  = New-Object System.Windows.Forms.Button
        $btnAll.Text = "Select All"
        $btnAll.Width = 100
        $btnPanel.Controls.Add($btnAll)

        $btnNone = New-Object System.Windows.Forms.Button
        $btnNone.Text = "Select None"
        $btnNone.Width = 110
        $btnPanel.Controls.Add($btnNone)

        return @{ Panel=$panel; Search=$txt; List=$clb; BtnAll=$btnAll; BtnNone=$btnNone }
    }

    $coreUI   = New-ListGroup -Title "Core apps"
    $extrasUI = New-ListGroup -Title "Extras"

    $split.Panel1.Controls.Add($coreUI.Panel)
    $split.Panel2.Controls.Add($extrasUI.Panel)

    # OK/Cancel strip
    $bottom = New-Object System.Windows.Forms.Panel
    $bottom.Dock = 'Bottom'
    $bottom.Height = 46
    $form.Controls.Add($bottom)

    $btnOK = New-Object System.Windows.Forms.Button
    $btnOK.Text = "OK"
    $btnOK.Anchor = 'Top,Right'
    $btnOK.Width = 100
    $btnOK.Location = New-Object System.Drawing.Point(($form.ClientSize.Width - 220), 8)
    $btnOK.DialogResult = [System.Windows.Forms.DialogResult]::OK
    $form.AcceptButton = $btnOK
    $bottom.Controls.Add($btnOK)

    $btnCancel = New-Object System.Windows.Forms.Button
    $btnCancel.Text = "Cancel"
    $btnCancel.Anchor = 'Top,Right'
    $btnCancel.Width = 100
    $btnCancel.Location = New-Object System.Drawing.Point(($form.ClientSize.Width - 110), 8)
    $btnCancel.Add_Click({ $form.Close() })
    $form.CancelButton = $btnCancel
    $bottom.Controls.Add($btnCancel)

    # keep buttons aligned on resize
    $form.Add_Resize({
        $btnOK.Location     = New-Object System.Drawing.Point(($form.ClientSize.Width - 220), 8)
        $btnCancel.Location = New-Object System.Drawing.Point(($form.ClientSize.Width - 110), 8)
    })

    # Populate helpers with filter + list building
    $populateCore = {
        param($filter)
        $ui = $coreUI
        $ui.List.Items.Clear()
        $view = if ([string]::IsNullOrWhiteSpace($filter)) { $coreRows } else {
            $f = [regex]::Escape($filter)
            $coreRows | Where-Object { $_.Name -match $f -or $_.Note -match $f }
        }
        foreach ($r in $view) {
            $label = $r.Name
            if ($r.Installed) { $label += "  $($r.Installed)" }
            if ($r.Note)      { $label += "  ($($r.Note))" }
            [void]$ui.List.Items.Add($label, $r.Checked)
        }
        $ui.List.Tag = $view
    }
    $populateExtras = {
        param($filter)
        $ui = $extrasUI
        $ui.List.Items.Clear()
        $view = if ([string]::IsNullOrWhiteSpace($filter)) { $extraRows } else {
            $f = [regex]::Escape($filter)
            $extraRows | Where-Object { $_.Name -match $f -or $_.Note -match $f }
        }
        foreach ($r in $view) {
            $label = $r.Name
            if ($r.Installed) { $label += "  $($r.Installed)" }
            if ($r.Note)      { $label += "  ($($r.Note))" }
            [void]$ui.List.Items.Add($label, $r.Checked)
        }
        $ui.List.Tag = $view
    }

    # Wire up the controls
    $coreUI.BtnAll.Add_Click({ for ($i=0; $i -lt $coreUI.List.Items.Count; $i++) { $coreUI.List.SetItemChecked($i,$true) } })
    $coreUI.BtnNone.Add_Click({ for ($i=0; $i -lt $coreUI.List.Items.Count; $i++) { $coreUI.List.SetItemChecked($i,$false) } })
    $coreUI.Search.Add_TextChanged({ & $populateCore $coreUI.Search.Text })

    $extrasUI.BtnAll.Add_Click({ for ($i=0; $i -lt $extrasUI.List.Items.Count; $i++) { $extrasUI.List.SetItemChecked($i,$true) } })
    $extrasUI.BtnNone.Add_Click({ for ($i=0; $i -lt $extrasUI.List.Items.Count; $i++) { $extrasUI.List.SetItemChecked($i,$false) } })
    $extrasUI.Search.Add_TextChanged({ & $populateExtras $extrasUI.Search.Text })

    & $populateCore  $null
    & $populateExtras $null

    if ($form.ShowDialog() -ne [System.Windows.Forms.DialogResult]::OK) {
        return [PSCustomObject]@{ Core=@(); Extras=@() }
    }

    # Collect selections
    $coreView   = [System.Collections.Generic.List[object]]$coreUI.List.Tag
    $extrasView = [System.Collections.Generic.List[object]]$extrasUI.List.Tag

    $coreSelected = @()
    for ($i=0; $i -lt $coreUI.List.Items.Count; $i++) {
        if ($coreUI.List.GetItemChecked($i)) { $coreSelected += $coreView[$i].Name }
    }
    $extrasSelected = @()
    for ($i=0; $i -lt $extrasUI.List.Items.Count; $i++) {
        if ($extrasUI.List.GetItemChecked($i)) { $extrasSelected += $extrasView[$i].Name }
    }

    return [PSCustomObject]@{ Core=$coreSelected; Extras=$extrasSelected }
}

# Out-GridView fallback (two-step in one call)
function Choose-CoreAndExtras-OGV {
    param(
        [string[]]$CoreItems,[hashtable]$CorePrechecked,[hashtable]$CoreNotes,
        [string[]]$ExtrasItems,[hashtable]$ExtrasPrechecked,[hashtable]$ExtrasNotes
    )
    $rowsCore = foreach ($n in $CoreItems) {
        $checked  = if ($CorePrechecked.ContainsKey($n)) { [bool]$CorePrechecked[$n] } else { $true }
        $installed= if (Test-AppInstalled $n) { 'yes' } else { '' }
        $note     = if ($CoreNotes -and $CoreNotes.ContainsKey($n)) { $CoreNotes[$n] } else { '' }
        [PSCustomObject]@{ Name=$n; Default=$checked; Installed=$installed; Note=$note }
    }
    $selCore = $rowsCore | Out-GridView -Title "Core apps" -PassThru
    $rowsExtras = foreach ($n in $ExtrasItems) {
        $checked  = if ($ExtrasPrechecked.ContainsKey($n)) { [bool]$ExtrasPrechecked[$n] } else { $false }
        $installed= if (Test-AppInstalled $n) { 'yes' } else { '' }
        $note     = if ($ExtrasNotes -and $ExtrasNotes.ContainsKey($n)) { $ExtrasNotes[$n] } else { '' }
        [PSCustomObject]@{ Name=$n; Default=$checked; Installed=$installed; Note=$note }
    }
    $selExtras = $rowsExtras | Out-GridView -Title "Extras (optional)" -PassThru
    return [PSCustomObject]@{ Core=($selCore.Name); Extras=($selExtras.Name) }
}

# Unified "choose both" wrapper
function Choose-CoreAndExtras {
    param(
        [string[]]$CoreItems,[hashtable]$CorePrechecked,[hashtable]$CoreNotes,
        [string[]]$ExtrasItems,[hashtable]$ExtrasPrechecked,[hashtable]$ExtrasNotes,
        [switch]$NonInteractive,[ValidateSet('auto','winforms','ogv','text')][string]$Picker = 'auto'
    )
    if ($NonInteractive) {
        $coreSel   = @(); foreach ($n in $CoreItems)   { if ($CorePrechecked[$n])   { $coreSel   += $n } }
        $extrasSel = @(); foreach ($n in $ExtrasItems) { if ($ExtrasPrechecked[$n]) { $extrasSel += $n } }
        return ,([PSCustomObject]@{ Core=$coreSel; Extras=$extrasSel })
    }
    if ($Picker -eq 'auto') {
        if (Test-CanUseWinForms) { $Picker = 'winforms' }
        elseif (Test-HasOutGridView) { $Picker = 'ogv' }
        else { $Picker = 'text' }
    }
    switch ($Picker) {
        'winforms' { return ,(Show-CombinedPickerWinForms -CoreItems $CoreItems -CorePrechecked $CorePrechecked -CoreNotes $CoreNotes -ExtrasItems $ExtrasItems -ExtrasPrechecked $ExtrasPrechecked -ExtrasNotes $ExtrasNotes) }
        'ogv'      { return ,(Choose-CoreAndExtras-OGV -CoreItems $CoreItems -CorePrechecked $CorePrechecked -CoreNotes $CoreNotes -ExtrasItems $ExtrasItems -ExtrasPrechecked $ExtrasPrechecked -ExtrasNotes $ExtrasNotes) }
        default    {
            $coreChosen   = Choose-FromChecklist -Title "Core apps" -Items $CoreItems -Prechecked $CorePrechecked
            $extrasChosen = Choose-FromChecklist -Title "Extras (optional)" -Items $ExtrasItems -Prechecked $ExtrasPrechecked
            return ,([PSCustomObject]@{ Core=$coreChosen; Extras=$extrasChosen })
        }
    }
}

# Installer with verbose retry + log file
function Install-AppVerboseRetry {
    param([Parameter(Mandatory)][string]$Name)
    if (Test-AppInstalled $Name) { return @{ result='existing' } }
    try { scoop install $Name *> $null; return @{ result='installed' } } catch { }
    $ts   = Get-Date -Format "yyyyMMdd-HHmmss"
    $logd = Join-Path -Path $PSScriptRoot -ChildPath "logs"
    if (-not (Test-Path $logd)) { New-Item -Path $logd -ItemType Directory | Out-Null }
    $logp = Join-Path $logd "scoop-install-$($Name)-$ts.log"
    Write-Host "Retrying $Name with verbose logging → $logp" -ForegroundColor Yellow
    & powershell -NoLogo -NoProfile -Command "scoop install $Name -v" *>&1 | Tee-Object -FilePath $logp | Out-Null
    if (Test-AppInstalled $Name) { return @{ result='installed'; log=$logp } }
    return @{ result='failed'; log=$logp }
}

# =========================
# App sets
# =========================
$apps = @(
    'pwsh','windows-terminal','oh-my-posh','JetBrainsMono-NF',
    'git','glazewm','vscode','nodejs-lts','gcc','python',
    'googlechrome','discord','aria2'
)
$prereqs = @('7zip','innounp','dark')
$optionalExtras = @(
    '7zip','ripgrep','fd','bat','curl','wget','jq','yarn',
    'vlc','spotify','notepadplusplus','firefox','zoom','postman','neovim'
)
$Status.ExtrasCatalog = $optionalExtras

# =========================
# Scoop presence
# =========================
Write-Host "`n=== Checking Scoop ===" -ForegroundColor Cyan
if (-not (Test-Command 'scoop')) {
    Write-Host "Scoop not found. Installing per-user..." -ForegroundColor Yellow
    try {
        $curr = Get-ExecutionPolicy -Scope CurrentUser -ErrorAction SilentlyContinue
        if ($null -eq $curr -or $curr -eq 'Undefined') { Set-ExecutionPolicy -Scope CurrentUser RemoteSigned -Force }
    } catch { }
    try { [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12 } catch { }
    Invoke-RestMethod -Uri https://get.scoop.sh | Invoke-Expression
    $scoopRoot  = Get-ScoopRoot
    $shimsPath  = Join-Path $scoopRoot 'shims'
    if (-not (($env:PATH -split ';') | Where-Object { $_.TrimEnd('\') -ieq $shimsPath.TrimEnd('\') })) { $env:PATH = "$shimsPath;$env:PATH" }
    if (-not (Test-Command 'scoop')) { throw "Scoop install failed. Open a new terminal and retry." }
    Write-Host "✔ Scoop installed." -ForegroundColor Green
    $Status.ScoopInstall = "Installed"
} else {
    Write-Host "✔ Scoop already installed." -ForegroundColor Green
    $Status.ScoopInstall = "Already installed"
    $scoopRoot  = Get-ScoopRoot
    $shimsPath  = Join-Path $scoopRoot 'shims'
    if (-not (($env:PATH -split ';') | Where-Object { $_.TrimEnd('\') -ieq $shimsPath.TrimEnd('\') })) { $env:PATH = "$shimsPath;$env:PATH" }
}

# =========================
# Buckets
# =========================
Write-Host "`n=== Adding/Updating Scoop buckets ===" -ForegroundColor Cyan
$buckets = @('main','extras','nerd-fonts','versions')
foreach ($b in $buckets) {
    if (-not (scoop bucket list 2>$null | Select-String -SimpleMatch $b)) {
        scoop bucket add $b *> $null
        Write-Host "Added bucket: $b"
        $Status.Buckets += "Added: $b"
    } else {
        Write-Host "Bucket present: $b"
        $Status.Buckets += "Present: $b"
    }
}
scoop update *> $null

# =========================
# Prereqs
# =========================
Write-Host "`n=== Installing prerequisites ===" -ForegroundColor Cyan
foreach ($p in $prereqs) {
    if (Test-AppInstalled $p) {
        Write-Host "Prereq already installed: $p"
        $Status.PrereqsExisting += $p
    } else {
        Write-Host "Installing prereq: $p"
        try { scoop install $p *> $null; $Status.PrereqsNew += $p }
        catch { Write-Host "Failed prereq: $p" -ForegroundColor Yellow; $Status.PrereqsFailed += $p }
    }
}

# =========================
# aria2 + config
# =========================
Write-Host "`n=== Ensuring aria2 and enabling accelerated downloads ===" -ForegroundColor Cyan
try {
    if (-not (Test-AppInstalled 'aria2')) {
        Write-Host "Installing: aria2"
        scoop install aria2 *> $null
        $Status.Aria2 = "Installed"
    } else { Write-Host "Already installed: aria2"; $Status.Aria2 = "Already installed" }
    scoop config aria2-enabled true                              *> $null
    scoop config aria2-retry-wait 2                              *> $null
    scoop config aria2-split 16                                  *> $null
    scoop config aria2-max-connection-per-server 16              *> $null
} catch { Write-Host "Warning: failed to enable aria2: $_" -ForegroundColor Yellow; $Status.Aria2 = "Failed" }

# =========================
# Build interactive choices (one-page)
# =========================
$appsCore = $apps | Where-Object { $_ -ne 'aria2' }  # aria2 handled already

# Default = nothing preselected
$preCore   = @{}; foreach ($n in $appsCore)       { $preCore[$n] = $false }
$preExtras = @{}; foreach ($n in $optionalExtras) { $preExtras[$n] = $false }

$notesCore = @{}
if (Test-SystemVSCodeInstalled) {
    $preCore['vscode'] = $false
    $notesCore['vscode'] = 'system install detected; default unchecked'
}

# Let user decide: Enter = text; 'g' = GUI; 'o' = Out-GridView (if available)
$Picker = Resolve-PickerPreference -NonInteractive:$NonInteractive -PickerDefault $Picker

$selection = Choose-CoreAndExtras `
    -CoreItems $appsCore -CorePrechecked $preCore -CoreNotes $notesCore `
    -ExtrasItems $optionalExtras -ExtrasPrechecked $preExtras -ExtrasNotes @{} `
    -NonInteractive:$NonInteractive -Picker $Picker

$chosenCore   = $selection.Core
$chosenExtras = $selection.Extras
$Status.CoreAppsChosen = $chosenCore
$Status.ExtrasChosen   = $chosenExtras

# =========================
# Install selections
# =========================
Write-Host "`n=== Installing selected core apps ===" -ForegroundColor Cyan
foreach ($app in $chosenCore) {
    if (Test-AppInstalled $app) { Write-Host "Already installed: $app"; $Status.CoreAppsExisting += $app; continue }
    Write-Host "Installing: $app"
    $res = Install-AppVerboseRetry -Name $app
    switch ($res.result) {
        'installed' { $Status.CoreAppsNew += $app; if ($res.log) { Write-Host "  (log: $($res.log))" -ForegroundColor DarkGray } }
        'existing'  { $Status.CoreAppsExisting += $app }
        default     { $Status.CoreAppsFailed  += $app; if ($res.log) { Write-Host "  See $($res.log)" -ForegroundColor Yellow } }
    }
}

if ($chosenExtras.Count -gt 0) {
    Write-Host "`n=== Installing selected extras ===" -ForegroundColor Cyan
    foreach ($x in $chosenExtras) {
        if (Test-AppInstalled $x) { Write-Host "Already installed (extra): $x"; $Status.ExtrasExisting += $x; continue }
        Write-Host "Installing (extra): $x"
        $res = Install-AppVerboseRetry -Name $x
        switch ($res.result) {
            'installed' { $Status.ExtrasNew += $x; if ($res.log) { Write-Host "  (log: $($res.log))" -ForegroundColor DarkGray } }
            'existing'  { $Status.ExtrasExisting += $x }
            default     { $Status.ExtrasFailed += $x; if ($res.log) { Write-Host "  See $($res.log)" -ForegroundColor Yellow } }
        }
    }
} else {
    Write-Host "`n=== Extras ===" -ForegroundColor Cyan
    Write-Host "No extras selected."
}

# =========================
# PSReadLine + Terminal-Icons
# =========================
if (-not (Get-Module -ListAvailable PSReadLine)) { try { Install-Module PSReadLine -Scope CurrentUser -Force -AllowClobber } catch { } }

Write-Host "`n=== Installing Terminal-Icons ===" -ForegroundColor Cyan
try {
    if (-not (Get-Module -ListAvailable Terminal-Icons)) {
        Install-Module -Name Terminal-Icons -Scope CurrentUser -Force -AllowClobber
        Write-Host "✔ Terminal-Icons installed." -ForegroundColor Green
        $Status.TerminalIcons = "Installed"
    } else { Write-Host "Terminal-Icons already installed." -ForegroundColor Green; $Status.TerminalIcons = "Already installed" }

    $profilesToTouch = @(
        "$env:USERPROFILE\Documents\WindowsPowerShell\Microsoft.PowerShell_profile.ps1",
        "$env:USERPROFILE\Documents\PowerShell\Microsoft.PowerShell_profile.ps1"
    )
    foreach ($pp in $profilesToTouch) {
        if (-not (Test-Path $pp)) { New-Item -ItemType File -Path $pp -Force | Out-Null }
        $pc = Get-Content $pp -Raw
        if ($pc -notmatch 'Import-Module\s+Terminal-Icons') { Add-Content $pp "`n# Import Terminal-Icons`nImport-Module -Name Terminal-Icons" }
    }
    try { Import-Module -Name Terminal-Icons -ErrorAction SilentlyContinue } catch { }
} catch { $Status.TerminalIcons = "Failed" }

# =========================
# Update + version diff
# =========================
$beforeMap = Get-InstalledMap
Write-Host "`n=== Updating installed apps (if any) ===" -ForegroundColor Cyan
try { $null = scoop update * *> $null; $Status.UpdateRan = "Yes" } catch { $Status.UpdateRan = "Failed" }

$afterMap = Get-InstalledMap
if ($Status.UpdateRan -eq "Yes") {
    $allNames = ($beforeMap.Keys + $afterMap.Keys) | Select-Object -Unique
    foreach ($name in $allNames) {
        if ($beforeMap.ContainsKey($name) -and $afterMap.ContainsKey($name)) {
            $old = $beforeMap[$name]; $new = $afterMap[$name]
            if ($old -and $new -and ($old -ne $new)) { $Status.UpdatedApps += ("{0} {1} -> {2}" -f $name, $old, $new) }
        }
    }
}

# =========================
# Quick verify
# =========================
Write-Host "`n=== Quick verify versions installed ===" -ForegroundColor Cyan
$installedMap = if ($afterMap -and $afterMap.Count -gt 0) { $afterMap } else { Get-InstalledMap }
$scoopRoot = Get-ScoopRoot
try { scoop --version | ForEach-Object { "scoop: $_" } } catch {}
try { aria2c --version | Select-Object -First 1 | ForEach-Object { "aria2: $_" } } catch {}

$verifyTargets = ($apps + $optionalExtras) | Select-Object -Unique
foreach ($app in $verifyTargets) {
    $ver = if ($installedMap.ContainsKey($app)) { $installedMap[$app] } else { $null }
    $currDir = Join-Path (Join-Path $scoopRoot "apps") "$app\current"
    if ($ver) {
        Write-Host ("{0}: {1}" -f $app, $ver)
        if (Test-Path $currDir) { Write-Host ("  path: {0}" -f $currDir) }
    }
}

# =========================
# Checkup
# =========================
Write-Host "`n=== Scoop checkup ===" -ForegroundColor Cyan
try { scoop checkup; $Status.Checkup = "Completed" } catch { $Status.Checkup = "Failed" }
Write-Host ""

# =========================
# Summary
# =========================
Write-Host "`n=== Summary ===" -ForegroundColor Cyan
$Status.GetEnumerator() | ForEach-Object {
    if ($_.Value -is [System.Collections.IEnumerable] -and -not ($_.Value -is [string])) {
        if ($_.Key -eq 'UpdatedApps' -and ($_.Value).Count -eq 0) {
            Write-Host ("{0}: None" -f $_.Key)
        } else {
            Write-Host ("{0}: {1}" -f $_.Key, (($_.Value) -join ', '))
        }
    } else {
        Write-Host ("{0}: {1}" -f $_.Key, $_.Value)
    }
}

# =========================
# Closing notes (after Summary)
# =========================
Write-Host "`n=== Done ===" -ForegroundColor Green
Write-Host "If Windows Terminal was open, restart it."
Write-Host "`nTo double check g++ version, run:`ng++ --version`n(Get-Command g++).Source"
Write-Host "`nIf fonts don’t show, sign out/in or reopen the terminal."
Write-Host "`nRun 'oh-my-posh init pwsh --config <theme>' to set up your prompt."
Write-Host "See https://ohmyposh.dev/docs/ for themes and docs."
Write-Host "`nYou can export your installed apps with 'scoop export > scoopfile.json'."
Write-Host "You can import them later with 'scoop import scoopfile.json'."
Write-Host "`nPeace!`n"
Write-Host "https://seperet.com`n"
