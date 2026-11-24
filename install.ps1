#!/usr/bin/env pwsh
# Clean-build, install, and launch Intercopas on Debian-based Linux desktops.
$ErrorActionPreference = 'Stop'

if ($IsWindows -or $IsMacOS) {
    throw 'This installer is for Linux Mint and Debian-based Linux desktops.'
}

$ProjectDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$DistDir = Join-Path $ProjectDir 'dist'
$Package = Get-Content (Join-Path $ProjectDir 'package.json') -Raw | ConvertFrom-Json
$AppVersion = $Package.version
$HomeDir = [Environment]::GetFolderPath('UserProfile')
$InstallDir = Join-Path $HomeDir '.local/opt/intercopas'
$ApplicationsDir = Join-Path $HomeDir '.local/share/applications'
$DesktopDir = Join-Path $HomeDir 'Desktop'
$AppImageName = "Intercopas-$AppVersion.AppImage"
$AppImagePath = Join-Path $InstallDir $AppImageName

foreach ($Command in @('npm', 'node', 'dpkg-query', 'sudo')) {
    if (-not (Get-Command $Command -ErrorAction SilentlyContinue)) {
        throw "$Command is required to build and install Intercopas."
    }
}

$NodeVersionText = (& node --version).Trim().TrimStart('v')
if ([version]$NodeVersionText -lt [version]'20.0') {
    throw "Node.js $NodeVersionText is installed. Intercopas requires Node.js 20 or later."
}

$FuseStatus = (& dpkg-query -W -f='${Status}' libfuse2t64 2>$null)
if ($LASTEXITCODE -ne 0 -or $FuseStatus -notmatch 'install ok installed') {
    $FuseStatus = (& dpkg-query -W -f='${Status}' libfuse2 2>$null)
}
if ($LASTEXITCODE -ne 0 -or $FuseStatus -notmatch 'install ok installed') {
    Write-Host 'Installing the AppImage FUSE runtime dependency...'
    sudo apt-get update
    if ($LASTEXITCODE -ne 0) { throw 'APT update failed.' }
    sudo apt-get install -y libfuse2
    if ($LASTEXITCODE -ne 0) { throw 'Could not install libfuse2.' }
}

# Stop an older installed instance so it cannot keep showing stale behavior.
$OldProcesses = Get-Process -Name 'intercopas' -ErrorAction SilentlyContinue
if ($OldProcesses) {
    $OldProcesses | Stop-Process -Force
    Start-Sleep -Milliseconds 800
}

if (Test-Path -LiteralPath $DistDir) {
    Write-Host 'Removing the old dist directory before rebuilding...'
    Remove-Item -LiteralPath $DistDir -Recurse -Force
}

Write-Host 'Installing locked dependencies and building a fresh AppImage...'
Push-Location $ProjectDir
try {
    npm ci
    if ($LASTEXITCODE -ne 0) { throw 'npm ci failed.' }
    npm run dist -- --linux AppImage
    if ($LASTEXITCODE -ne 0) { throw 'The AppImage build failed.' }
}
finally {
    Pop-Location
}

$BuiltAppImage = Join-Path $DistDir $AppImageName
if (-not (Test-Path -LiteralPath $BuiltAppImage -PathType Leaf)) {
    throw "The expected AppImage was not created: $BuiltAppImage"
}

New-Item -ItemType Directory -Force -Path $InstallDir, $ApplicationsDir | Out-Null
Copy-Item -LiteralPath $BuiltAppImage -Destination $AppImagePath -Force
& chmod +x $AppImagePath
if ($LASTEXITCODE -ne 0) { throw 'Could not mark the installed AppImage executable.' }

$DesktopEntry = @"
[Desktop Entry]
Type=Application
Name=Intercopas
Comment=Sync clipboard text between desktops
Exec="$AppImagePath" %U
Terminal=false
Categories=Utility;
StartupNotify=true
"@
$DesktopFile = Join-Path $ApplicationsDir 'intercopas.desktop'
Set-Content -Path $DesktopFile -Value $DesktopEntry -Encoding utf8
& chmod +x $DesktopFile
if ($LASTEXITCODE -ne 0) { throw 'Could not install the Intercopas application launcher.' }

if (Test-Path $DesktopDir) {
    $DesktopShortcut = Join-Path $DesktopDir 'Intercopas.desktop'
    Copy-Item -LiteralPath $DesktopFile -Destination $DesktopShortcut -Force
    & chmod +x $DesktopShortcut
    if (Get-Command gio -ErrorAction SilentlyContinue) {
        & gio set $DesktopShortcut metadata::trusted true 2>$null
    }
}

Write-Host "Installed fresh Intercopas $AppVersion. Launching $AppImagePath..."
Start-Process -FilePath $AppImagePath
