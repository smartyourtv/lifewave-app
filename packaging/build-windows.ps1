<#
.SYNOPSIS
  Build the Lifewave AI Windows app + its easy-install Setup.exe.

.DESCRIPTION
  Adapted from the windows-health packaging template for a FLUTTER
  WINDOWS app (folder payload, not a single-file PyInstaller exe).
  All per-app values come from packaging\app-config.json.

  Steps:
    1. flutter build windows --release (in the Flutter project dir).
    2. Verify the Release folder (exe + flutter_windows.dll + data\).
    3. Inno Setup (ISCC): per-user installer dist\<App>-Setup.exe,
       with /D defines read from app-config.json.

  Run from anywhere; paths resolve relative to this script.
  Requires (Windows only): Flutter 3.24.5 on PATH, Inno Setup 6.
  Nothing here signs the binaries - SmartScreen's
  "More info -> Run anyway" step applies (documented in the README).

.PARAMETER SkipInno
  Build only the Flutter Windows app folder, not the installer.
#>
[CmdletBinding()]
param(
    [switch]$SkipInno
)

$ErrorActionPreference = "Stop"
$PackagingDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$RepoRoot = Split-Path -Parent $PackagingDir
$Config = Get-Content (Join-Path $PackagingDir "app-config.json") -Raw | ConvertFrom-Json

$FlutterDir = Join-Path $RepoRoot $Config.flutter_project_dir
$ReleaseDir = Join-Path $RepoRoot $Config.windows_release_dir
$ExePath = Join-Path $ReleaseDir $Config.exe_name
$SetupPath = Join-Path $RepoRoot ("dist\" + $Config.setup_name)

Write-Host "== Flutter: build windows --release =="
Push-Location $FlutterDir
try {
    flutter build windows --release
    if ($LASTEXITCODE -ne 0) { throw "flutter build windows failed" }
}
finally {
    Pop-Location
}

Write-Host "== Verify Flutter Release folder =="
if (-not (Test-Path $ExePath)) { throw "exe not produced: $ExePath" }
if (-not (Test-Path (Join-Path $ReleaseDir "flutter_windows.dll"))) {
    throw "flutter_windows.dll missing in $ReleaseDir"
}
if (-not (Test-Path (Join-Path $ReleaseDir "data"))) {
    throw "data folder missing in $ReleaseDir"
}

if ($SkipInno) {
    Write-Host "Built: $ReleaseDir"
    return
}

Write-Host "== Inno Setup: $($Config.setup_name) =="
$Iscc = Get-Command "ISCC.exe" -ErrorAction SilentlyContinue |
    Select-Object -ExpandProperty Source -First 1
if (-not $Iscc) {
    foreach ($cand in @(
        "${env:ProgramFiles(x86)}\Inno Setup 6\ISCC.exe",
        "$env:ProgramFiles\Inno Setup 6\ISCC.exe",
        "$env:LOCALAPPDATA\Programs\Inno Setup 6\ISCC.exe")) {
        if (Test-Path $cand) { $Iscc = $cand; break }
    }
}
if (-not $Iscc) {
    throw "ISCC.exe not found. Install Inno Setup 6 from https://jrsoftware.org/isdl.php (or: choco install innosetup)"
}
New-Item -ItemType Directory -Force (Join-Path $RepoRoot "dist") | Out-Null
& $Iscc `
    "/DMyAppId=$($Config.app_id)" `
    "/DMyAppName=$($Config.display_name)" `
    "/DMyAppVersion=$($Config.version)" `
    "/DMyAppPublisher=$($Config.publisher)" `
    "/DMyExeName=$($Config.exe_name)" `
    "/DMyInstallFolder=$($Config.install_folder)" `
    "/DMySetupBaseName=$([IO.Path]::GetFileNameWithoutExtension($Config.setup_name))" `
    "/DMySourceDir=$ReleaseDir" `
    "/DMyOutputDir=$(Join-Path $RepoRoot 'dist')" `
    (Join-Path $PackagingDir "setup.iss")
if ($LASTEXITCODE -ne 0) { throw "Inno Setup compile failed" }
if (-not (Test-Path $SetupPath)) { throw "installer not produced: $SetupPath" }

Write-Host ""
Write-Host "Built:"
Write-Host "  $ReleaseDir"
Write-Host "  $SetupPath"
Write-Host "Unsigned: first run shows SmartScreen - 'More info' -> 'Run anyway'."
