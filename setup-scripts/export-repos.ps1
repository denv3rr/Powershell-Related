# Script to export GitHub repositories to a text file and optionally clone them.
# Requires PowerShell 5.1+ (Windows) or PowerShell 7+ (cross-platform).

# Usage example (replace my username with your GitHub username):
<#
# Public repos (SSH), write repos.txt only
.\Export-GitHubRepos.ps1 -User denv3rr -UrlType ssh

# Include forks and clone everything into ~/Programming
.\Export-GitHubRepos.ps1 -User denv3rr -IncludeForks -CloneAll

# Include private repos too (requires token)
$env:GITHUB_TOKEN = 'ghp_XXXXXXXXXXXXXXXXXXXX'
.\Export-GitHubRepos.ps1 -User denv3rr -CloneAll
#>

param(
    # GitHub username (default: denv3rr)
  [string]$User = "USERNAME",
    # Include forked repos (default: no)
  [switch]$IncludeForks,
    # URL type: ssh or https (default: ssh)
  [ValidateSet("ssh","https")] [string]$UrlType = "ssh",
    # Output file (default: repos.txt)
  [string]$OutFile = "repos.txt",
    # Clone all repos to $CloneDir (default: no)
  [switch]$CloneAll,
    # Directory to clone to (default: $env:USERPROFILE\Programming)
  [string]$CloneDir = "$env:USERPROFILE\Programming"
)

# If you set $env:GITHUB_TOKEN, this will include private repos you own.
#   $env:GITHUB_TOKEN = 'ghp_...'

# Prepare headers
$Headers = @{
  "User-Agent" = "ps-export-repos"
}
if ($env:GITHUB_TOKEN) { $Headers.Authorization = "Bearer $env:GITHUB_TOKEN" }

# Strategy:
# - If token provided: use /user/repos (visibility=all, affiliation=owner)
# - Else: public only via /users/:user/repos
$BaseUrl = if ($env:GITHUB_TOKEN) {
  "https://api.github.com/user/repos?per_page=100&visibility=all&affiliation=owner&sort=full_name&direction=asc"
} else {
  "https://api.github.com/users/$User/repos?per_page=100&type=owner&sort=full_name&direction=asc"
}

# Fetch all pages of results
$all = @()
$page = 1
while ($true) {
  $url = "$BaseUrl&page=$page"
  $resp = Invoke-RestMethod -Method GET -Uri $url -Headers $Headers -ErrorAction Stop
  if (-not $resp -or $resp.Count -eq 0) { break }
  $all += $resp
  $page++
}

# Filter out forks if needed
if (-not $IncludeForks) {
  $all = $all | Where-Object { -not $_.fork }
}

# Choose clone URL flavor
$urls = if ($UrlType -eq 'ssh') { $all | ForEach-Object { $_.ssh_url } }
        else                     { $all | ForEach-Object { $_.clone_url } }

# Output to file
$urls | Sort-Object -Unique | Set-Content -Path $OutFile -Encoding UTF8
Write-Host "Wrote $($urls.Count) repos to $OutFile" -ForegroundColor Green

# Optionally clone all repos
if ($CloneAll) {
  New-Item -ItemType Directory -Force -Path $CloneDir | Out-Null
  Push-Location $CloneDir
  try {
    Get-Content (Resolve-Path $OutFile) | ForEach-Object {
      Write-Host "Cloning $_ ..." -ForegroundColor Cyan
      git clone $_
    }
  } finally {
    Pop-Location
  }
}
