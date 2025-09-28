Absolutely—here’s the **full updated file** with upgrade tracking added. It now:

* Captures versions **before** and **after** a `scoop update *` pass
* Reports **which apps were upgraded** (version → new version) in the **Summary**
* Keeps your comments and triple-line dividers, aria2-first flow, single `$apps` list, optional extras, and idempotent behavior

```powershell
<# =====================================================================
    bootstrap-scoop.ps1  —  Windows 11 setup via Scoop
    -----------------------------------------------------------------------
    • WTF is this?
        - PowerShell script to set up Scoop package manager and apps on Windows 11:
        - Installs Scoop (per-user, no admin) if missing
        - Adds buckets: main, extras, nerd-fonts, versions
        - Installs multiple apps: ***CHECK APPS ARRAY BELOW***
        - Configures Scoop to use aria2 for faster downloads (if aria2 is installed)
        - Installs Terminal-Icons module and configures profile to import it
        - Verifies installs and shows versions/paths at end

    • Requirements:
        - Windows 11 (may work on Win10 but not tested)
        - PowerShell 5.1+ (built-in on Win11) or PowerShell 7+
        - Internet connection
        - No admin rights needed (per-user install)

    • Notes:
        - Installs apps to per-user Scoop (default: %USERPROFILE%\scoop)
        - Installs apps to per-user locations (no admin rights needed)
        - Uses shims, so apps are available in any terminal after install
        - You may need to restart Windows Terminal or sign out/in for fonts to show
        - You can export your installed apps with 'scoop export > scoopfile.json'
        - You can import them later with 'scoop import scoopfile.json'

    • Safe to re-run: idempotent checks included

    • Run (from repo root):
        powershell -ExecutionPolicy Bypass -File .\bootstrap-scoop.ps1

    • If PowerShell blocks script execution:
        Set-ExecutionPolicy -Scope CurrentUser RemoteSigned -Force

    • If TLS errors show up (very rare on Win11):
        [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

    • Manual Scoop install command (if you prefer to do it yourself):
        Invoke-RestMethod -Uri https://get.scoop.sh | Invoke-Expression

    • Export/Import your Scoop apps later:
        scoop export > scoopfile.json
        scoop import scoopfile.json

===================================================================== #>


# =================================================================
# =================================================================
# =================================================================


# --- Begin script ---

[CmdletBinding()]
param(
    [switch]$NonInteractive,
    [switch]$InstallExtras,
    [string]$Extras
)

$ErrorActionPreference = 'Stop'

# Status trackers
$Status = [ordered]@{
    ScoopInstall       = "Skipped"
    Buckets            = @()
    Aria2              = "Skipped"
    CoreAppsNew        = @()
    CoreAppsExisting   = @()
    CoreAppsFailed     = @()
    ExtrasNew          = @()
    ExtrasExisting     = @()
    ExtrasFailed       = @()
    TerminalIcons      = "Skipped"
    Checkup            = "Skipped"
    UpdateRan          = "No"
    UpdatedApps        = @()   # entries like "app old->new"
}

function Test-Command { param([Parameter(Mandatory)] [string]$Name)
    return [bool](Get-Command $Name -ErrorAction SilentlyContinue)
}

function Get-InstalledMap {
    $map = @{}
    try {
        $json = scoop list --json 2>$null
        if ($json) {
            (ConvertFrom-Json $json) | ForEach-Object {
                # Name, Version, etc.
                $map[$_.Name] = $_.Version
            }
        }
    } catch { }
    return $map
}

# =================================================================
# =================================================================
# =================================================================

Write-Host "`n=== Checking Scoop ===" -ForegroundColor Cyan
if (-not (Test-Command 'scoop')) {
    Write-Host "Scoop not found. Installing per-user (no admin)..." -ForegroundColor Yellow
    try {
        $curr = Get-ExecutionPolicy -Scope CurrentUser -ErrorAction SilentlyContinue
        if ($null -eq $curr -or $curr -eq 'Undefined') {
            Set-ExecutionPolicy -Scope CurrentUser RemoteSigned -Force
        }
    } catch { }
    try { [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12 } catch { }
    Invoke-RestMethod -Uri https://get.scoop.sh | Invoke-Expression
    $scoopRoot  = if ($env:SCOOP) { $env:SCOOP } else { Join-Path $env:USERPROFILE 'scoop' }
    $shimsPath  = Join-Path $scoopRoot 'shims'
    $pathParts  = ($env:PATH -split ';') | Where-Object { $_ }
    $hasShims   = $pathParts | Where-Object { $_.TrimEnd('\') -ieq $shimsPath.TrimEnd('\') }
    if (-not $hasShims) { $env:PATH = "$shimsPath;$env:PATH" }
    if (-not (Test-Command 'scoop')) { throw "Scoop install failed. Open new terminal and retry." }
    Write-Host "✔ Scoop installed." -ForegroundColor Green
    $Status.ScoopInstall = "Installed"
}
else {
    Write-Host "✔ Scoop already installed." -ForegroundColor Green
    $Status.ScoopInstall = "Already installed"
    $scoopRoot  = if ($env:SCOOP) { $env:SCOOP } else { Join-Path $env:USERPROFILE 'scoop' }
    $shimsPath  = Join-Path $scoopRoot 'shims'
    $pathParts  = ($env:PATH -split ';') | Where-Object { $_ }
    $hasShims   = $pathParts | Where-Object { $_.TrimEnd('\') -ieq $shimsPath.TrimEnd('\') }
    if (-not $hasShims) { $env:PATH = "$shimsPath;$env:PATH" }
}

# =================================================================
# =================================================================
# =================================================================

Write-Host "`n=== Adding/Updating Scoop buckets ===" -ForegroundColor Cyan
$buckets = @('main','extras','nerd-fonts','versions')
foreach ($b in $buckets) {
    if (-not (scoop bucket list | Select-String -SimpleMatch $b)) {
        scoop bucket add $b | Out-Null
        Write-Host "Added bucket: $b"
        $Status.Buckets += "Added: $b"
    } else {
        Write-Host "Bucket present: $b"
        $Status.Buckets += "Present: $b"
    }
}
scoop update

# =================================================================
# =================================================================
# =================================================================

Write-Host "`n=== Installing apps via Scoop ===" -ForegroundColor Cyan
$apps = @(
    'pwsh','windows-terminal','oh-my-posh','JetBrainsMono-NF',
    'git','glazewm','vscode','nodejs-lts','gcc','python',
    'googlechrome','discord','aria2'
)

$optionalExtras = @(
    '7zip','ripgrep','fd','bat','curl','wget','jq','yarn',
    'vlc','spotify','notepadplusplus','firefox','zoom','postman','neovim'
)

try {
    $ariaInstalled = $false
    try { scoop prefix aria2 | Out-Null; $ariaInstalled = $true } catch { }
    if (-not $ariaInstalled) { Write-Host "Installing: aria2"; scoop install aria2; $Status.Aria2 = "Installed" }
    else { Write-Host "Already installed: aria2"; $Status.Aria2 = "Already installed" }
    scoop config aria2-enabled true    | Out-Null
    scoop config aria2-retry-wait 2    | Out-Null
    scoop config aria2-split 16        | Out-Null
    scoop config aria2-max-connection-per-server 16 | Out-Null
} catch { Write-Host "Warning: failed to enable aria2: $_" -ForegroundColor Yellow; $Status.Aria2 = "Failed" }

$appsCore = $apps | Where-Object { $_ -ne 'aria2' }
foreach ($app in $appsCore) {
    $installed = $false
    try { scoop prefix $app | Out-Null; $installed = $true } catch { }
    if ($installed) { Write-Host "Already installed: $app"; $Status.CoreAppsExisting += $app }
    else {
        Write-Host "Installing: $app"
        try { scoop install $app | Out-Null; $Status.CoreAppsNew += $app }
        catch { Write-Host "Failed: $app"; $Status.CoreAppsFailed += $app }
    }
}

# =================================================================
# =================================================================
# =================================================================

Write-Host "`n=== Re-checking installs ===" -ForegroundColor Cyan
foreach ($app in $apps) {
    $installed = $false
    try { scoop prefix $app | Out-Null; $installed = $true } catch { }
    if ($installed) { }
    else {
        try { scoop install $app | Out-Null; if ($app -ne 'aria2') { $Status.CoreAppsNew += $app } }
        catch { $Status.CoreAppsFailed += $app }
    }
}

# =================================================================
# =================================================================
# =================================================================

if (-not (Get-Module -ListAvailable PSReadLine)) {
    try { Install-Module PSReadLine -Scope CurrentUser -Force -AllowClobber } catch { }
}

# =================================================================
# =================================================================
# =================================================================

Write-Host "`n=== Installing Terminal-Icons ===" -ForegroundColor Cyan
try {
    if (-not (Get-Module -ListAvailable Terminal-Icons)) {
        Install-Module -Name Terminal-Icons -Scope CurrentUser -Force -AllowClobber
        Write-Host "✔ Terminal-Icons installed." -ForegroundColor Green
        $Status.TerminalIcons = "Installed"
    } else {
        Write-Host "Terminal-Icons already installed." -ForegroundColor Green
        $Status.TerminalIcons = "Already installed"
    }
    $profilePath = $PROFILE.CurrentUserAllHosts
    if (-not (Test-Path $profilePath)) { New-Item -ItemType File -Path $profilePath -Force | Out-Null }
    $profileContent = Get-Content $profilePath -Raw
    if ($profileContent -notmatch 'Import-Module\s+Terminal-Icons') {
        Add-Content $profilePath "`n# Import Terminal-Icons`nImport-Module -Name Terminal-Icons"
    }
} catch { $Status.TerminalIcons = "Failed" }

# =================================================================
# =================================================================
# =================================================================

Write-Host "`n=== Optional extras ===" -ForegroundColor Cyan
$extrasToInstall = @()
if ($InstallExtras) { $extrasToInstall += $optionalExtras }
if ($Extras) { $extrasToInstall += ($Extras -split '\s*,\s*' | Where-Object { $_ }) }
if (-not $NonInteractive -and -not $InstallExtras -and -not $Extras) {
    $answer = Read-Host "Install optional extras now? (Y/N)"
    if ($answer -match '^[Yy]') { $extrasToInstall += $optionalExtras }
}
$extrasToInstall = $extrasToInstall | Select-Object -Unique
if ($extrasToInstall.Count -gt 0) {
    foreach ($x in $extrasToInstall) {
        $hasX = $false
        try { scoop prefix $x | Out-Null; $hasX = $true } catch { }
        if ($hasX) { Write-Host "Already installed (extra): $x"; $Status.ExtrasExisting += $x }
        else {
            Write-Host "Installing (extra): $x"
            try { scoop install $x | Out-Null; $Status.ExtrasNew += $x }
            catch { $Status.ExtrasFailed += $x }
        }
    }
}

# =================================================================
# =================================================================
# =================================================================

# Capture versions BEFORE an update pass
$beforeMap = Get-InstalledMap

Write-Host "`n=== Updating installed apps (if any) ===" -ForegroundColor Cyan
try {
    # This is idempotent; if nothing is outdated, it's quick.
    $null = scoop update *
    $Status.UpdateRan = "Yes"
} catch {
    $Status.UpdateRan = "Failed"
}

# Capture versions AFTER the update pass and diff
$afterMap = Get-InstalledMap
if ($Status.UpdateRan -eq "Yes") {
    # Consider any installed app whose version changed an upgrade
    $allNames = ($beforeMap.Keys + $afterMap.Keys) | Select-Object -Unique
    foreach ($name in $allNames) {
        if ($beforeMap.ContainsKey($name) -and $afterMap.ContainsKey($name)) {
            $old = $beforeMap[$name]
            $new = $afterMap[$name]
            if ($old -and $new -and ($old -ne $new)) {
                $Status.UpdatedApps += ("{0} {1} -> {2}" -f $name, $old, $new)
            }
        }
    }
}

# =================================================================
# =================================================================
# =================================================================

Write-Host "`n=== Quick verify versions installed ===" -ForegroundColor Cyan
$installedMap = $afterMap
if (-not $installedMap -or $installedMap.Count -eq 0) {
    $installedMap = Get-InstalledMap
}
$scoopRoot = if ($env:SCOOP) { $env:SCOOP } else { Join-Path $env:USERPROFILE 'scoop' }
try { scoop --version | ForEach-Object { "scoop: $_" } } catch {}
try { aria2c --version | Select-Object -First 1 | ForEach-Object { "aria2: $_" } } catch {}
foreach ($app in $apps) {
    $ver = if ($installedMap.ContainsKey($app)) { $installedMap[$app] } else { $null }
    $currDir = Join-Path (Join-Path $scoopRoot "apps") "$app\current"
    if ($ver) {
        Write-Host ("{0}: {1}" -f $app, $ver)
        if (Test-Path $currDir) { Write-Host ("  path: {0}" -f $currDir) }
    } else {
        Write-Host ("{0}: (not installed)" -f $app) -ForegroundColor Yellow
    }
}

# =================================================================
# =================================================================
# =================================================================

Write-Host "`n=== Scoop checkup ===" -ForegroundColor Cyan
try { scoop checkup; $Status.Checkup = "Completed" } catch { $Status.Checkup = "Failed" }
Write-Host "`n"

# =================================================================
# =================================================================
# =================================================================

Write-Host "`n=== Done ===" -ForegroundColor Green
Write-Host "If Windows Terminal was open, restart it."
Write-Host "`nTo double check g++ version, run:`ng++ --version`n(Get-Command g++).Source"
Write-Host "`nIf fonts don’t show, sign out/in or reopen the terminal."
Write-Host "`nRun 'oh-my-posh init pwsh --config <theme>' to set up your prompt."
Write-Host "See https://ohmyposh.dev/docs/ for themes and docs."
Write-Host "`nYou can export your installed apps with 'scoop export > scoopfile.json'."
Write-Host "You can import them later with 'scoop import scoopfile.json'."
Write-Host "`nPeace!`n"

# =================================================================
# =================================================================
# =================================================================

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

# =================================================================
# =================================================================
# =================================================================
