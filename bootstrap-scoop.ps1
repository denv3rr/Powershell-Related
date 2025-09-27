<# =====================================================================
    bootstrap-scoop.ps1  —  Fresh Windows 11 setup via Scoop
    -----------------------------------------------------------------------
    • What this does:
        - Installs Scoop (per-user, no admin) if missing
        - Adds buckets: main, extras, nerd-fonts, versions
        - Installs: CHECK APPS ARRAY BELOW
        - Configures Scoop to use aria2 for faster downloads (if aria2 is installed)
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

# --- Begin script ---

# Stop on errors
$ErrorActionPreference = 'Stop'

# Helper: test command availability
function Test-Command { param([Parameter(Mandatory)] [string]$Name)
    return [bool](Get-Command $Name -ErrorAction SilentlyContinue)
}

# Check for Scoop:
# If you ever install Scoop to a non-default root or system-wide later, you’re already covered
# with this $env:SCOOP fallback.
Write-Host "`n=== Checking Scoop ===" -ForegroundColor Cyan
if (-not (Test-Command 'scoop')) {
    Write-Host "Scoop not found. Installing per-user (no admin)..." -ForegroundColor Yellow

    # Make sure execution policy allows install in current session
    try {
        $curr = Get-ExecutionPolicy -Scope CurrentUser -ErrorAction SilentlyContinue
        if ($null -eq $curr -or $curr -eq 'Undefined') {
            Set-ExecutionPolicy -Scope CurrentUser RemoteSigned -Force
        }
    } catch { }

    # Prefer TLS 1.2
    try { [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12 } catch { }

    # Install Scoop
    Invoke-RestMethod -Uri https://get.scoop.sh | Invoke-Expression

    # Ensure shims are available in *this* session even before a new shell
    $scoopRoot  = if ($env:SCOOP) { $env:SCOOP } else { Join-Path $env:USERPROFILE 'scoop' }
    $shimsPath  = Join-Path $scoopRoot 'shims'
    $pathParts  = ($env:PATH -split ';') | Where-Object { $_ }       # remove empties
    $hasShims   = $pathParts | Where-Object { $_.TrimEnd('\') -ieq $shimsPath.TrimEnd('\') }

    if (-not $hasShims) {
        Write-Host "Adding Scoop shims to PATH for this session..."
        $env:PATH = "$shimsPath;$env:PATH"
    }

    if (-not (Test-Command 'scoop')) {
        throw "Scoop installation appears to have failed. Open a new terminal and try again."
    }
    Write-Host "✔ Scoop installed." -ForegroundColor Green
}
else {
    Write-Host "✔ Scoop already installed." -ForegroundColor Green
    # Ensure shims exist in this session (covers shells started before install or PATH glitches)
    $scoopRoot  = if ($env:SCOOP) { $env:SCOOP } else { Join-Path $env:USERPROFILE 'scoop' }
    $shimsPath  = Join-Path $scoopRoot 'shims'
    $pathParts  = ($env:PATH -split ';') | Where-Object { $_ }
    $hasShims   = $pathParts | Where-Object { $_.TrimEnd('\') -ieq $shimsPath.TrimEnd('\') }
    if (-not $hasShims) {
        Write-Host "Adding Scoop shims to PATH for this session..."
        $env:PATH = "$shimsPath;$env:PATH"
    }
    else {
        Write-Host "Scoop shims already in PATH."
    }
}

# Add/update buckets
Write-Host "`n=== Adding/Updating Scoop buckets ===" -ForegroundColor Cyan
# Buckets you’ll want for dev + fonts + desktop apps
$buckets = @('main','extras','nerd-fonts','versions')
foreach ($b in $buckets) {
    if (-not (scoop bucket list | Select-String -SimpleMatch $b)) {
        scoop bucket add $b | Out-Null
        Write-Host "Added bucket: $b"
    } else {
        Write-Host "Bucket present: $b"
    }
}

# Update Scoop and all buckets
scoop update

# Install apps
Write-Host "`n=== Installing apps via Scoop ===" -ForegroundColor Cyan
$apps = @(
    'pwsh',                 # PowerShell 7
    'windows-terminal',     # Windows Terminal (extras)
    'oh-my-posh',           # Oh My Posh
    'JetBrainsMono-NF',     # JetBrains Mono Nerd Font (nerd-fonts)
    'git',                  # Git
    'glazewm',              # GlazeWM tiling window manager
    'vscode',               # Visual Studio Code
    'nodejs-lts',           # Node.js LTS
    'gcc',                  # MinGW-w64 GCC (g++)
    'python',               # Python
    'googlechrome',         # Google Chrome
    'discord',              # Discord
    'aria2'                 # aria2 (accelerated downloads)
    # 'neovim',
    # '7zip',
    # 'ripgrep',
    # 'fd',
    # 'bat',
    # 'curl',
    # 'wget',
    # 'jq',
    # 'yarn',
    # 'vlc',
    # 'spotify',
    # 'notepadplusplus',
    # 'firefox',
    # 'zoom',
    # 'postman',
)

foreach ($app in $apps) {
    $installed = $false
    try {
        scoop prefix $app | Out-Null
        $installed = $true
    } catch { $installed = $false }

    if ($installed) {
        Write-Host "Already installed: $app"
    } else {
        Write-Host "Installing: $app"
        scoop install $app
    }
}

# Configures Scoop to use aria2 (if it is installed above)
# Faster downloads, especially for large files
try {
    scoop config aria2-enabled true    | Out-Null
    scoop config aria2-retry-wait 2    | Out-Null
    scoop config aria2-split 16        | Out-Null
    scoop config aria2-max-connection-per-server 16 | Out-Null
} catch {}

# Re-check installs in case of partial failures above
Write-Host "`n=== Re-checking installs ===" -ForegroundColor Cyan
foreach ($app in $apps) {
    $installed = $false
    try { scoop prefix $app | Out-Null; $installed = $true } catch { $installed = $false }
    if ($installed) {
        Write-Host "Already installed: $app"
    } else {
        Write-Host "Installing: $app"
        scoop install $app
    }
}

# Optional: ensure PSReadLine (usually present on Win11/PS7)
if (-not (Get-Module -ListAvailable PSReadLine)) {
    try { Install-Module PSReadLine -Scope CurrentUser -Force -AllowClobber } catch { }
}

# Quick verify of installs + versions
Write-Host "`n=== Quick verify versions installed ===" -ForegroundColor Cyan
try { scoop --version | ForEach-Object { "scoop: $_" } } catch {}
try { (Get-Command scoop).Source | ForEach-Object { "scoop path: $_" } } catch {}
try { aria2c --version | Select-Object -First 1 | ForEach-Object { "aria2: $_" } } catch {}
try { (Get-Command aria2c).Source | ForEach-Object { "aria2 path: $_" } } catch {}
Write-Host "`n"
try { wt --version | ForEach-Object { "windows-terminal: $_" } } catch {}
try { (Get-Command wt).Source | ForEach-Object { "windows-terminal path: $_" } } catch {}
Write-Host "`n"
try { pwsh -NoLogo -NoProfile -Command '$PSVersionTable.PSVersion.ToString()' | ForEach-Object { "pwsh: $_" } } catch {}
try { (Get-Command pwsh).Source | ForEach-Object { "pwsh path: $_" } } catch {}
Write-Host "`n"
try { g++ --version | Select-Object -First 1 | ForEach-Object { "g++ version: $_" } } catch {}
try { (Get-Command g++).Source | ForEach-Object { "g++ path: $_" } } catch {}
Write-Host "`n"
try { node --version | ForEach-Object { "node: $_" } } catch {}
try { (Get-Command node).Source | ForEach-Object { "node path: $_" } } catch {}
Write-Host "`n"
try { python --version | ForEach-Object { "python: $_" } } catch {}
try { (Get-Command python).Source | ForEach-Object { "python path: $_" } } catch {}
Write-Host "`n"
try { oh-my-posh --version | ForEach-Object { "oh-my-posh: $_" } } catch {}
try { (Get-Command oh-my-posh).Source | ForEach-Object { "oh-my-posh path: $_" } } catch {}
Write-Host "`n"
try { code --version | Select-Object -First 1 | ForEach-Object { "vscode: $_" } } catch {}
try { (Get-Command code).Source | ForEach-Object { "vscode path: $_" } } catch {}
Write-Host "`n"
try { git --version | ForEach-Object { "git: $_" } } catch {}
try { (Get-Command git).Source | ForEach-Object { "git path: $_" } } catch {}
Write-Host "`n"
try { glazewm --version | ForEach-Object { "glazewm: $_" } } catch {}
try { (Get-Command glazewm).Source | ForEach-Object { "glazewm path: $_" } } catch {}
Write-Host "`n=== Other useful paths/info ===" -ForegroundColor Cyan
try { Get-InstalledModule PSReadLine | ForEach-Object { "PSReadLine: $($_.Version)" } } catch {}
Write-Host "`n"
try { Get-Item "$env:USERPROFILE\Documents\WindowsPowerShell\Microsoft.PowerShell_profile.ps1" | ForEach-Object { "PowerShell profile: $($_.FullName)" } } catch {}
try { Get-Item "$env:USERPROFILE\Documents\PowerShell\Microsoft.PowerShell_profile.ps1" | ForEach-Object { "PowerShell 7 profile: $($_.FullName)" } } catch {}
try { Get-Item "$env:USERPROFILE\scoop\shims" | ForEach-Object { "Scoop shims dir: $($_.FullName)" } } catch {}
try { Get-Item "$env:USERPROFILE\scoop\apps\oh-my-posh\current\themes" | ForEach-Object { "Oh My Posh themes dir: $($_.FullName)" } } catch {}
try { Get-Item "$env:USERPROFILE\scoop\apps\JetBrainsMono-NF\current" | ForEach-Object { "JetBrains Mono NF dir: $($_.FullName)" } } catch {}
try { Get-Item "$env:USERPROFILE\scoop\apps\windows-terminal\current" | ForEach-Object { "Windows Terminal dir: $($_.FullName)" } } catch {}
Write-Host "`n"

# Run scoop checkup (may show warnings/fixes)
Write-Host "`n=== Scoop checkup ===" -ForegroundColor Cyan
try { scoop checkup } catch {}
Write-Host "`n"

# Final notes
Write-Host "`n=== Done ===" -ForegroundColor Green
Write-Host "If Windows Terminal was open, restart it."
Write-Host "`nTo double check g++ version, run:`ng++ --version`n(Get-Command g++).Source`n***NOTE*** -- should be '...\scoop\shims\g++.exe'"
Write-Host "`nIf fonts don’t show, sign out/in (rare) or reopen the terminal."
Write-Host "`nRun 'oh-my-posh init pwsh --config <theme>' to set up your prompt."
Write-Host "You can change your theme later with 'Set-PoshPrompt -Theme <theme>'."
Write-Host "See https://ohmyposh.dev/docs/ for themes and docs."
Write-Host "`nYou can export your installed apps with 'scoop export > scoopfile.json'."
Write-Host "You can import them later with 'scoop import scoopfile.json'."
Write-Host "`nPeace!`n"