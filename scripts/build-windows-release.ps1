#!/usr/bin/env pwsh
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$Version,
    [string]$OutputDirectory
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

if ($Version.StartsWith("v")) {
    $Version = $Version.Substring(1)
}

if ($Version -notmatch '^\d+\.\d+\.\d+([\-+][0-9A-Za-z.-]+)?$') {
    throw "Version must be a semantic version, for example 1.2.1 or 1.2.1-beta.1: $Version"
}

if ([Environment]::OSVersion.Platform -ne [PlatformID]::Win32NT) {
    throw "The Windows packaging script must run on a Windows runner."
}

$RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
$WindowsRoot = Join-Path $RepoRoot "windows"
$AppRoot = Join-Path $WindowsRoot "apps\codexu-tauri"
$WebRoot = Join-Path $AppRoot "web"
$ManifestPath = Join-Path $AppRoot "src-tauri\Cargo.toml"

foreach ($RequiredPath in @($WindowsRoot, $WebRoot, $ManifestPath)) {
    if (-not (Test-Path -LiteralPath $RequiredPath)) {
        throw "Required Windows project path is missing: $RequiredPath"
    }
}

if (-not $OutputDirectory) {
    $OutputDirectory = Join-Path $RepoRoot "dist\windows"
}
$OutputDirectory = [System.IO.Path]::GetFullPath($OutputDirectory)
New-Item -ItemType Directory -Force -Path $OutputDirectory | Out-Null

function Invoke-Checked {
    param(
        [Parameter(Mandatory = $true)]
        [string]$FilePath,
        [Parameter(Mandatory = $false)]
        [string[]]$ArgumentList = @()
    )

    Write-Host "> $FilePath $($ArgumentList -join ' ')"
    & $FilePath @ArgumentList
    if ($LASTEXITCODE -ne 0) {
        throw "$FilePath failed with exit code $LASTEXITCODE"
    }
}

if (-not (Get-Command rustup -ErrorAction SilentlyContinue)) {
    throw "rustup is required to build the Windows release."
}
if (-not (Get-Command cargo -ErrorAction SilentlyContinue)) {
    throw "cargo is required to build the Windows release."
}
if (-not (Get-Command npm -ErrorAction SilentlyContinue)) {
    throw "npm is required to build the Windows release."
}

$Toolchain = "stable-x86_64-pc-windows-msvc"
Invoke-Checked "rustup" @("update", "--no-self-update", $Toolchain)

Push-Location $WindowsRoot
try {
    Invoke-Checked "cargo" @("+$Toolchain", "fmt", "--all", "--", "--check")
    Invoke-Checked "cargo" @("+$Toolchain", "test", "--workspace")
}
finally {
    Pop-Location
}

Push-Location $WebRoot
try {
    if (Test-Path -LiteralPath (Join-Path $WebRoot "package-lock.json")) {
        Invoke-Checked "npm" @("ci", "--no-audit", "--no-fund")
    }
    else {
        Write-Warning "package-lock.json is not committed; using npm install for this Windows build."
        Invoke-Checked "npm" @("install", "--no-audit", "--no-fund")
    }
    Invoke-Checked "npm" @("run", "build")
}
finally {
    Pop-Location
}

$TauriConfigPath = Join-Path ([System.IO.Path]::GetTempPath()) ("codexu-tauri-config-" + [Guid]::NewGuid().ToString("N") + ".json")
$TauriConfig = @{ version = $Version } | ConvertTo-Json -Compress
try {
    [System.IO.File]::WriteAllText(
        $TauriConfigPath,
        $TauriConfig,
        [System.Text.UTF8Encoding]::new($false)
    )

    Push-Location $AppRoot
    try {
        $TauriCliVersion = "2.6.2"
        $TauriVersionOutput = ""
        $TauriInstalled = $false
        try {
            $TauriVersionOutput = (& cargo "+$Toolchain" "tauri" "--version" 2>&1 | Out-String).Trim()
            $TauriInstalled = (
                $LASTEXITCODE -eq 0 -and
                $TauriVersionOutput -match ("tauri-cli\s+" + [regex]::Escape($TauriCliVersion) + "(?:\s|$)")
            )
        }
        catch {
            $TauriInstalled = $false
        }
        if (-not $TauriInstalled) {
            Invoke-Checked "cargo" @("+$Toolchain", "install", "tauri-cli", "--version", $TauriCliVersion, "--locked", "--force")
        }

        Invoke-Checked "cargo" @(
            "+$Toolchain", "tauri", "build",
            "--config", $TauriConfigPath,
            "--bundles", "msi,nsis"
        )
    }
    finally {
        Pop-Location
    }
}
finally {
    if (Test-Path -LiteralPath $TauriConfigPath) {
        Remove-Item -LiteralPath $TauriConfigPath -Force
    }
}

$BundleRoots = @(
    (Join-Path $WindowsRoot "target\release\bundle"),
    (Join-Path $AppRoot "target\release\bundle")
) | Where-Object { Test-Path -LiteralPath $_ }

if (-not $BundleRoots) {
    throw "Tauri did not produce a release bundle directory."
}

$Msi = $BundleRoots |
    ForEach-Object { Get-ChildItem -LiteralPath (Join-Path $_ "msi") -Filter "*.msi" -File -ErrorAction SilentlyContinue } |
    Sort-Object LastWriteTime -Descending |
    Select-Object -First 1
$Nsis = $BundleRoots |
    ForEach-Object { Get-ChildItem -LiteralPath (Join-Path $_ "nsis") -Filter "*-setup.exe" -File -ErrorAction SilentlyContinue } |
    Sort-Object LastWriteTime -Descending |
    Select-Object -First 1

if (-not $Msi) {
    throw "No MSI installer was found under the Tauri release bundle."
}
if (-not $Nsis) {
    throw "No NSIS setup executable was found under the Tauri release bundle."
}

$Artifacts = @(
    @{ Source = $Msi.FullName; Name = "codexU-$Version-windows-x86_64.msi" },
    @{ Source = $Nsis.FullName; Name = "codexU-$Version-windows-x86_64-setup.exe" }
)
$Utf8NoBom = [System.Text.UTF8Encoding]::new($false)

foreach ($Artifact in $Artifacts) {
    $Destination = Join-Path $OutputDirectory $Artifact.Name
    Copy-Item -LiteralPath $Artifact.Source -Destination $Destination -Force
    $Hash = (Get-FileHash -LiteralPath $Destination -Algorithm SHA256).Hash.ToLowerInvariant()
    $ChecksumPath = "$Destination.sha256"
    [System.IO.File]::WriteAllText($ChecksumPath, "$Hash  $($Artifact.Name)$([Environment]::NewLine)", $Utf8NoBom)
    Write-Host "Wrote $Destination"
    Write-Host "Wrote $ChecksumPath"
}

$Manifest = [ordered]@{
    product = "codexU"
    version = $Version
    target = "windows-x86_64"
    installers = @($Artifacts.Name)
    generated_utc = [DateTime]::UtcNow.ToString("o")
}
[System.IO.File]::WriteAllText(
    (Join-Path $OutputDirectory "manifest.json"),
    ($Manifest | ConvertTo-Json -Depth 4),
    $Utf8NoBom
)

Write-Host "Windows release artifacts verified for codexU $Version"
