#!/usr/bin/env pwsh
[CmdletBinding()]
param([Parameter(Mandatory = $true)][string]$Version)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"
if ($Version -notmatch '^\d+\.\d+\.\d+$') {
    throw "A Windows stable release needs a major.minor.patch version."
}
$RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
$Tag = "windows-v$Version"
$NotesPath = Join-Path $RepoRoot "docs\release-notes-windows-v$Version.md"
$Notes = Get-Content -Raw -Encoding UTF8 -LiteralPath $NotesPath
if ($Notes.Contains("SHA256_PLACEHOLDER")) { throw "Release notes still contain checksum placeholders." }
$Config = Get-Content -Raw -Encoding UTF8 -LiteralPath (Join-Path $RepoRoot "windows\apps\codexu-tauri\src-tauri\tauri.conf.json") | ConvertFrom-Json
if ($Config.version -ne $Version) { throw "Windows Tauri version mismatch." }
$Changelog = Get-Content -Raw -Encoding UTF8 -LiteralPath (Join-Path $RepoRoot "CHANGELOG.md")
if (-not $Changelog.Contains("## $Version -")) { throw "Changelog is missing the Windows release." }
foreach ($Readme in @("README.md", "README.en.md", "windows\README.md")) {
    $Text = Get-Content -Raw -Encoding UTF8 -LiteralPath (Join-Path $RepoRoot $Readme)
    if (-not $Text.Contains("releases/tag/$Tag")) { throw "$Readme is missing the Windows release link." }
}
$Directory = Join-Path $RepoRoot "dist\windows"
$Manifest = Get-Content -Raw -Encoding UTF8 -LiteralPath (Join-Path $Directory "manifest.json") | ConvertFrom-Json
if ($Manifest.version -ne $Version -or $Manifest.target -ne "windows-x86_64") {
    throw "Artifact manifest version/target mismatch."
}
$Names = @("codexU-$Version-windows-x86_64.msi", "codexU-$Version-windows-x86_64-setup.exe")
foreach ($Name in $Names) {
    if ($Manifest.installers -notcontains $Name) { throw "Manifest is missing $Name." }
    $Path = Join-Path $Directory $Name
    if ((Get-Item -LiteralPath $Path).Length -eq 0) { throw "Empty installer: $Name" }
    $Hash = (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()
    $ExpectedLine = "$Hash  $Name"
    if ((Get-Content -Raw -Encoding UTF8 -LiteralPath "$Path.sha256").Trim() -ne $ExpectedLine) {
        throw "Checksum mismatch: $Name"
    }
    if (-not $Notes.Contains($ExpectedLine)) { throw "Release notes are missing the verified checksum: $Name" }
    $Signature = Get-AuthenticodeSignature -LiteralPath $Path
    if ($Signature.Status -notin @("Valid", "NotSigned")) { throw "Invalid installer signature: $Name ($($Signature.Status))" }
    Write-Output "$Name SHA256=$Hash signature=$($Signature.Status)"
}
$Installer = New-Object -ComObject WindowsInstaller.Installer
$Database = $Installer.OpenDatabase((Join-Path $Directory $Names[0]), 0)
$View = $Database.OpenView('SELECT `Value` FROM `Property` WHERE `Property` = ''ProductVersion''')
$View.Execute()
$Record = $View.Fetch()
$ProductVersion = $Record.StringData(1)
if ($ProductVersion -ne $Version) { throw "MSI ProductVersion mismatch: $ProductVersion" }
$Summary = $Database.SummaryInformation(0)
$Template = $Summary.Property(7)
if ($Template -notlike 'x64;*') { throw "MSI architecture mismatch: $Template" }
$View.Close()
foreach ($Object in @($Record, $View, $Summary, $Database, $Installer)) {
    [void][System.Runtime.InteropServices.Marshal]::ReleaseComObject($Object)
}
$ExeVersion = (Get-Item -LiteralPath (Join-Path $Directory $Names[1])).VersionInfo.ProductVersion
if ($ExeVersion -ne $Version -and -not $ExeVersion.StartsWith("$Version.")) {
    throw "NSIS ProductVersion mismatch: $ExeVersion"
}
Push-Location $RepoRoot
try {
    & git diff --check
    if ($LASTEXITCODE -ne 0) { throw "git diff --check failed." }
    & git ls-remote --exit-code --tags "https://github.com/shanggqm/codexU.git" "refs/tags/$Tag"
    if ($LASTEXITCODE -eq 0) { throw "Upstream tag already exists: $Tag" }
    if ($LASTEXITCODE -ne 2) { throw "Cannot verify upstream tag absence." }
    & gh release view $Tag --repo shanggqm/codexU --json tagName 2>$null
    if ($LASTEXITCODE -eq 0) { throw "Release already exists: $Tag" }
    & gh repo view shanggqm/codexU --json nameWithOwner | Out-Null
    if ($LASTEXITCODE -ne 0) { throw "Cannot verify release repository access." }
}
finally { Pop-Location }
Write-Output "Windows release metadata, MSI x64/version, NSIS version and checksums verified for $Tag"
