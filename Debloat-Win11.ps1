#------------------------------------------------------------------------
#------------------------------------------------------------------------
#------------------------------------------------------------------------

# A clean, safe “debloat” script you can run in an elevated/admin
# PowerShell window. It targets less-obvious bloat (services, tasks, 
# preloads, and UWP apps) while avoiding core security and update 
# components.

# How to run:

# Press Start → type “PowerShell” → right-click → Run as administrator

# (Optional but smart) Create a restore point first.

# Paste sections you want, or save the whole script as:
# Debloat-Win11.ps1
# and run it.

#------------------------------------------------------------------------
#------------------------------------------------------------------------
#------------------------------------------------------------------------

# Quick safety notes

# Don’t disable Windows Update, Defender, or Windows Installer.

# If you print, leave Print Spooler running (in $services).

# Some OEM utilities (HP) can be bloaty, but check if you rely on
# BIOS/firmware updater or cooling control before removing.

#------------------------------------------------------------------------
#------------------------------------------------------------------------
#------------------------------------------------------------------------

# Create a restore point (works if System Protection is enabled)
Enable-ComputerRestore -Drive "C:\" -ErrorAction SilentlyContinue
Checkpoint-Computer -Description "Pre-debloat" -RestorePointType "MODIFY_SETTINGS"

# Export current state for rollback/reference
$stamp = (Get-Date).ToString("yyyyMMdd-HHmmss")
Get-Service | Sort Name | Export-Csv "$env:USERPROFILE\Desktop\Services-$stamp.csv" -NoTypeInformation
Get-ScheduledTask | Sort TaskPath,TaskName | Export-Csv "$env:USERPROFILE\Desktop\ScheduledTasks-$stamp.csv" -NoTypeInformation
Get-AppxPackage -AllUsers | Select Name,PackageFullName | Export-Csv "$env:USERPROFILE\Desktop\Appx-$stamp.csv" -NoTypeInformation

#------------------------------------------------------------------------
#------------------------------------------------------------------------
#------------------------------------------------------------------------

$services = @(
  'SysMain',                         # App prefetcher; often high disk/CPU
  'DiagTrack',                       # Connected User Experiences/Telemetry
  'WerSvc',                          # Windows Error Reporting (uploads)
  'RemoteRegistry',                  # Remote registry editing (not needed)
  'Fax'                              # Fax service (legacy)
)

foreach ($s in $services) {
  if (Get-Service -Name $s -ErrorAction SilentlyContinue) {
    Stop-Service $s -ErrorAction SilentlyContinue
    Set-Service  $s -StartupType Disabled
    Write-Host "Disabled service: $s"
  }
}

#------------------------------------------------------------------------
#------------------------------------------------------------------------
#------------------------------------------------------------------------

<#
# OPTIONAL: Xbox background services (only if you don’t use Game Bar / Xbox features)
$xb = @('XblAuthManager','XblGameSave','XboxGipSvc','XboxNetApiSvc')
foreach ($s in $xb) {
  if (Get-Service -Name $s -ErrorAction SilentlyContinue) {
    Stop-Service $s -ErrorAction SilentlyContinue
    Set-Service  $s -StartupType Disabled
    Write-Host "Disabled Xbox service: $s"
  }
}
#>

#------------------------------------------------------------------------
#------------------------------------------------------------------------
#------------------------------------------------------------------------

$tasks = @(
  '\Microsoft\Windows\Application Experience\Microsoft Compatibility Appraiser',
  '\Microsoft\Windows\Application Experience\ProgramDataUpdater',
  '\Microsoft\Windows\Customer Experience Improvement Program\Consolidator',
  '\Microsoft\Windows\Customer Experience Improvement Program\KernelCeipTask',
  '\Microsoft\Windows\Customer Experience Improvement Program\UsbCeip',
  '\Microsoft\Windows\Maps\MapsUpdateTask',
  '\Microsoft\Windows\Feedback\Siuf\DmClient',
  '\Microsoft\Windows\Feedback\Siuf\DmClientOnScenarioDownload'
)

foreach ($t in $tasks) {
  if (Get-ScheduledTask -TaskPath ($t -replace '\\[^\\]+$','\') -TaskName ($t.Split('\')[-1]) -ErrorAction SilentlyContinue) {
    Disable-ScheduledTask -TaskName ($t.Split('\')[-1]) -TaskPath ($t -replace '\\[^\\]+$','\') | Out-Null
    Write-Host "Disabled task: $t"
  }
}

#------------------------------------------------------------------------
#------------------------------------------------------------------------
#------------------------------------------------------------------------

# Hide Widgets & Teams Chat buttons (per user)
New-Item -Path HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced -Force | Out-Null
Set-ItemProperty HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced -Name TaskbarDa -Type DWord -Value 0    # Widgets
Set-ItemProperty HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced -Name TaskbarMn -Type DWord -Value 0    # Chat/Teams (consumer)

# Turn off Windows “Tips” / content suggestions (per user)
$cdm = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager'
New-Item -Path $cdm -Force | Out-Null
@(
  'SoftLandingEnabled',
  'SubscribedContent-310093Enabled',
  'SubscribedContent-314563Enabled',
  'SubscribedContent-338387Enabled',
  'SubscribedContent-338388Enabled',
  'SubscribedContent-338389Enabled',
  'SubscribedContent-338393Enabled'
) | ForEach-Object { Set-ItemProperty $cdm -Name $_ -Type DWord -Value 0 -ErrorAction SilentlyContinue }

# Disable WebView-backed widgets process startup for current user session
Stop-Process -Name 'Widgets','widgetsbrowser','msedgewebview2' -ErrorAction SilentlyContinue

#------------------------------------------------------------------------
#------------------------------------------------------------------------
#------------------------------------------------------------------------

# Helper to remove for current users AND future users
function Remove-AppxSafe {
  param([Parameter(Mandatory=$true)][string[]]$Patterns)
  foreach ($p in $Patterns) {
    Get-AppxPackage -AllUsers -Name $p -ErrorAction SilentlyContinue | Remove-AppxPackage -AllUsers -ErrorAction SilentlyContinue
    Get-AppxProvisionedPackage -Online | Where-Object {$_.DisplayName -like $p} | Remove-AppxProvisionedPackage -Online -ErrorAction SilentlyContinue | Out-Null
    Write-Host "Removed (or provision removed): $p"
  }
}

# Pick-and-choose from this list
$toRemove = @(
  'Microsoft.549981C3F5F10',     # Cortana
  'Microsoft.Microsoft3DViewer', # 3D Viewer
  'Microsoft.MixedReality.Portal',# Mixed Reality Portal
  'Microsoft.WindowsAlarms',     # Alarms & Clock
  'Microsoft.BingWeather',       # Weather
  'Microsoft.WindowsMaps',       # Maps
  'Microsoft.GetHelp',           # Get Help
  'Microsoft.Getstarted',        # Tips
  'Microsoft.People',            # People
  'Microsoft.GamingApp',         # Xbox app
  'Microsoft.Xbox.TCUI',
  'Microsoft.XboxGameOverlay',
  'Microsoft.XboxGamingOverlay',
  'Microsoft.XboxIdentityProvider',
  'Microsoft.ZuneMusic',         # Legacy Groove Music (if present)
  'Microsoft.ZuneVideo',         # Movies & TV (if present)
  'Microsoft.YourPhone'          # Phone Link (if you never use it)
)
Remove-AppxSafe -Patterns $toRemove

#------------------------------------------------------------------------
#------------------------------------------------------------------------
#------------------------------------------------------------------------

<#

# Fully uninstall OneDrive (Win11 comes with Win32 client)
$oneDrivePath = "$env:SystemRoot\SysWOW64\OneDriveSetup.exe"
if (-not (Test-Path $oneDrivePath)) { $oneDrivePath = "$env:SystemRoot\System32\OneDriveSetup.exe" }
if (Test-Path $oneDrivePath) {
  Start-Process $oneDrivePath -ArgumentList "/uninstall" -Wait
  Write-Host "OneDrive uninstalled."
}

# For each installed app, set app background activity to Disabled (where supported)
Get-AppxPackage -User $env:USERNAME | ForEach-Object {
  $pkg = $_.PackageFamilyName
  try {
    $cap = Get-AppxPackage -PackageTypeFilter Main -AllUsers -ErrorAction SilentlyContinue | Where-Object PackageFamilyName -eq $pkg
    # This is best done in Settings UI, but as a blunt tool:
    reg add "HKCU\Software\Microsoft\Windows\CurrentVersion\BackgroundAccessApplications" /v "$pkg\Disabled" /t REG_DWORD /d 1 /f | Out-Null
  } catch {}
}
Write-Host "Background access disabled for most Store apps (where honored)."


#>

#------------------------------------------------------------------------
#------------------------------------------------------------------------
#------------------------------------------------------------------------

# Refresh taskbar/Explorer to apply UI toggles
Stop-Process -Name explorer -Force
Start-Process explorer.exe
Write-Host "Explorer restarted. Consider rebooting to apply all service/task changes."

#------------------------------------------------------------------------
#------------------------------------------------------------------------
#------------------------------------------------------------------------

# Rollback / Re-enable quick notes

<#

Set-Service SysMain -StartupType Manual
Start-Service SysMain

Enable-ScheduledTask -TaskPath "\Microsoft\Windows\Customer Experience Improvement Program\" -TaskName "Consolidator"

Set-ItemProperty HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced -Name TaskbarDa -Type DWord -Value 1
Set-ItemProperty HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced -Name TaskbarMn -Type DWord -Value 1
Stop-Process -Name explorer -Force; Start-Process explorer

#>

