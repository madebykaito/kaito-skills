# Windows launcher: checks the tools setup needs, then runs ./setup in Git Bash.
# Usage (PowerShell, from the repo folder): .\setup.ps1 [--yes] [--no-gstack] [--no-codegraph] [--uninstall] [--purge]
$ErrorActionPreference = 'Stop'
$missing = @()

$bash = $null
$git = Get-Command git -ErrorAction SilentlyContinue
if ($git) {
  # git.exe lives in <Git>\cmd or <Git>\bin; Git Bash is <Git>\bin\bash.exe.
  $root = Split-Path (Split-Path $git.Source)
  $candidate = Join-Path $root 'bin\bash.exe'
  if (Test-Path $candidate) { $bash = $candidate }
}
if (-not $bash) { $missing += 'winget install --id Git.Git -e' }
if (-not (Get-Command node -ErrorAction SilentlyContinue)) { $missing += 'winget install --id OpenJS.NodeJS.LTS -e' }
if (-not (Get-Command npm -ErrorAction SilentlyContinue) -and -not ($missing -match 'NodeJS')) { $missing += 'winget install --id OpenJS.NodeJS.LTS -e' }
if (($args -notcontains '--no-gstack') -and ($args -notcontains '--uninstall') -and ($args -notcontains '--purge') -and
    -not (Get-Command bun -ErrorAction SilentlyContinue)) {
  $missing += 'winget install --id Oven-sh.Bun -e   (or run with --no-gstack)'
}

if ($missing.Count -gt 0) {
  Write-Host 'setup needs these first. Install them, open a new terminal, and run .\setup.ps1 again:'
  $missing | Select-Object -Unique | ForEach-Object { Write-Host "  $_" }
  exit 1
}

Push-Location $PSScriptRoot
try {
  & $bash ./setup @args
  exit $LASTEXITCODE
} finally {
  Pop-Location
}
