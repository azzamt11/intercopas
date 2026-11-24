#!/usr/bin/env pwsh
# Build and install Intercopas on Linux Mint (or another Debian-based desktop).
# Run from the project directory: pwsh ./install.ps1

$ErrorActionPreference = 'Stop'

if ($IsWindows -or $IsMacOS) {
    throw 'This installer is for Linux Mint and Debian-based Linux desktops.'
}

$ProjectDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$Package = Get-Content (Join-Path $ProjectDir 'package.json') -Raw | ConvertFrom-Json
$AppVersion = $Package.version
$HomeDir = [Environment]::GetFolderPath('UserProfile')
$InstallDir = Join-Path $HomeDir '.local/opt/intercopas'
$ApplicationsDir = Join-Path $HomeDir '.local/share/applications'
$DesktopDir = Join-Path $HomeDir 'Desktop'
$AppImagePath = Join-Path $InstallDir "Intercopas-$AppVersion.AppImage"

function Require-Command([string]$Name, [string]$InstallHint) {
    if (-not (Get-Command $Name -ErrorAction SilentlyContinue)) {
        throw "$Name is required. $InstallHint"
    }
}

Require-Command 'pwsh' 'Install PowerShell 7 (the pwsh package), then rerun this script.'

# Fresh Linux Mint installations can leave their installation medium enabled as an
# APT source. That CD-ROM source makes apt update fail, including in NodeSource's setup.
$AptSourceFiles = @('/etc/apt/sources.list') + @(
    Get-ChildItem '/etc/apt/sources.list.d' -File -ErrorAction SilentlyContinue |
        Where-Object { $_.Extension -in @('.list', '.sources') } |
        ForEach-Object { $_.FullName }
)
foreach ($SourceFile in $AptSourceFiles) {
    if (-not (Test-Path $SourceFile)) { continue }
    $SourceText = Get-Content $SourceFile -Raw
    if ($SourceText -match '(?im)^\s*(deb(?:-src)?\s+)?cdrom:') {
        Write-Host "Disabling the unused CD-ROM APT source in $SourceFile..."
        sudo sed -i -E '/^[[:space:]]*(deb(-src)?[[:space:]]+)?cdrom:/s/^/# disabled by Intercopas installer: /I' $SourceFile
        if ($LASTEXITCODE -ne 0) { throw "Could not disable the CD-ROM APT source in $SourceFile." }
    }
}

if (-not (Get-Command 'npm' -ErrorAction SilentlyContinue)) {
    Write-Host 'npm was not found. Installing Node.js 22 and npm from NodeSource...'
    sudo apt-get install -y ca-certificates curl gnupg
    if ($LASTEXITCODE -ne 0) { throw 'Could not install Node.js prerequisites.' }
    sudo install -d -m 0755 /etc/apt/keyrings
    if ($LASTEXITCODE -ne 0) { throw 'Could not create the APT keyring directory.' }
    curl -fsSL https://deb.nodesource.com/gpgkey/nodesource-repo.gpg.key | sudo gpg --dearmor --yes -o /etc/apt/keyrings/nodesource.gpg
    if ($LASTEXITCODE -ne 0) { throw 'Could not install the NodeSource signing key.' }
    sudo chmod 644 /etc/apt/keyrings/nodesource.gpg
    if ($LASTEXITCODE -ne 0) { throw 'Could not set permissions on the NodeSource signing key.' }
    $Architecture = (& dpkg --print-architecture).Trim()
    $NodeSourceEntry = "deb [arch=$Architecture signed-by=/etc/apt/keyrings/nodesource.gpg] https://deb.nodesource.com/node_22.x nodistro main"
    $NodeSourceEntry | sudo tee /etc/apt/sources.list.d/nodesource.list | Out-Null
    if ($LASTEXITCODE -ne 0) { throw 'Could not configure the NodeSource package repository.' }
    sudo apt-get update
    if ($LASTEXITCODE -ne 0) { throw 'APT update failed while configuring NodeSource.' }
    sudo apt-get install -y nodejs
    if ($LASTEXITCODE -ne 0) { throw 'Could not install Node.js from NodeSource.' }
}
Require-Command 'npm' 'Install Node.js 20 or later (with npm), then rerun this script.'

$NodeVersion = (& node --version).Trim().TrimStart('v')
if ([version]$NodeVersion -lt [version]'20.0') {
    throw "Node.js $NodeVersion is installed, but Intercopas needs Node.js 20 or later. Install Node.js 22 from NodeSource and rerun this script."
}

Write-Host 'Installing AppImage runtime dependency...'
sudo apt-get update
sudo apt-get install -y libfuse2

Write-Host 'Installing project dependencies and building the AppImage...'
Push-Location $ProjectDir
try {
    npm install
    npm run dist -- --linux AppImage
}
finally {
    Pop-Location
}

$BuiltAppImage = Get-ChildItem (Join-Path $ProjectDir 'dist') -Filter '*.AppImage' -File |
    Sort-Object LastWriteTime -Descending |
    Select-Object -First 1
if (-not $BuiltAppImage) {
    throw 'electron-builder did not produce an AppImage in the dist directory.'
}

New-Item -ItemType Directory -Force -Path $InstallDir, $ApplicationsDir | Out-Null
Copy-Item -Path $BuiltAppImage.FullName -Destination $AppImagePath -Force
& chmod +x $AppImagePath

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

if (Test-Path $DesktopDir) {
    $DesktopShortcut = Join-Path $DesktopDir 'Intercopas.desktop'
    Copy-Item -Path $DesktopFile -Destination $DesktopShortcut -Force
    & chmod +x $DesktopShortcut
    # Cinnamon displays a confirmation prompt for new desktop launchers.
    if (Get-Command gio -ErrorAction SilentlyContinue) {
        & gio set $DesktopShortcut metadata::trusted true 2>$null
    }
}

Write-Host "Intercopas $AppVersion is installed. Launch it from the desktop or your applications menu."
