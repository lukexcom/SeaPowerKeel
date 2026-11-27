<#
.SYNOPSIS
    Builds a release of R.A.T.S. Keel and stages the folder that goes to the Steam Workshop.

.DESCRIPTION
    Release builds of the loader and the stub, then dist\SeaPowerKeel\ with exactly what players get:
    SeaPowerKeel.dll, SeaPowerKeel.Patcher.dll, _info.ini, LICENSE.txt, CHANGELOG.md, preview.jpg (workshop\preview.jpg) and copy-to-BepInEx-plugins\SeaPowerKeel.Stub.dll,
    the one file players copy into Sea Power\BepInEx\plugins once (Keel never loads it from the mod folder).
    With -Install the staged folder also replaces <GameDir>\Sea Power_Data\StreamingAssets\SeaPowerKeel\. Sea Power must be closed.

.EXAMPLE
    powershell -ExecutionPolicy Bypass -File tools\package.ps1
#>
param(
    [string]$GameDir = $(if ($env:GameDir) { $env:GameDir } else { 'E:\Games\steamapps\common\Sea Power' }),
    [switch]$Install
)

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$dist = Join-Path $root 'dist\SeaPowerKeel'

# The public, hash-pinned references (tools\refs.ps1), never the game folder: GitHub Actions builds from the same files and
# release-check.yml compares its build with this one byte for byte.
. (Join-Path $PSScriptRoot 'refs.ps1')
$refs = Get-PublicRefs $root
$refArgs = "-p:ManagedDir=$($refs.ManagedDir)", "-p:BepInExCore=$($refs.BepInExCore)"

foreach ($p in 'src\SeaPowerKeel\SeaPowerKeel.csproj', 'src\SeaPowerKeel.Stub\SeaPowerKeel.Stub.csproj', 'src\SeaPowerKeel.Patcher\SeaPowerKeel.Patcher.csproj', 'src\SeaPowerKeel.Watcher\SeaPowerKeel.Watcher.csproj') {
    dotnet build (Join-Path $root $p) -c Release -p:Deploy=false @refArgs
    if ($LASTEXITCODE -ne 0) { throw "Build failed: $p" }
}

if (Test-Path $dist) { Remove-Item -Recurse -Force $dist }
New-Item -ItemType Directory -Force (Join-Path $dist 'copy-to-BepInEx-plugins') | Out-Null
Copy-Item (Join-Path $root 'src\SeaPowerKeel\bin\Release\netstandard2.1\SeaPowerKeel.dll') $dist
Copy-Item (Join-Path $root 'src\SeaPowerKeel.Stub\bin\Release\netstandard2.1\SeaPowerKeel.Stub.dll') (Join-Path $dist 'copy-to-BepInEx-plugins')
Copy-Item (Join-Path $root 'src\SeaPowerKeel.Watcher\bin\Release\net48\KeelWatcher.exe') $dist
# The takeover patcher: Keel copies it into BepInEx\patchers itself and keeps it current (players never handle it).
Copy-Item (Join-Path $root 'src\SeaPowerKeel.Patcher\bin\Release\netstandard2.1\SeaPowerKeel.Patcher.dll') $dist

# KeelSetup.exe carries no other program inside: it copies the starter DLL and the patcher that lie next to it. BepInEx is not
# shipped: the setup downloads the release pinned in tools\bepinex.ps1 and refuses any file with another hash.
Get-OfficialBepInExZip $root | Out-Null      # checks now that the pinned release is still downloadable and unchanged
dotnet build (Join-Path $root 'src\SeaPowerKeel.Setup\SeaPowerKeel.Setup.csproj') -c Release -p:BepInExVersion="$BepInExVersion" -p:BepInExSha256="$BepInExSha256" @refArgs
if ($LASTEXITCODE -ne 0) { throw 'Build failed: KeelSetup' }
Copy-Item (Join-Path $root 'src\SeaPowerKeel.Setup\bin\Release\net48\KeelSetup.exe') $dist
Copy-Item (Join-Path $root 'src\SeaPowerKeel\mod\_info.ini') $dist
Copy-Item (Join-Path $root 'LICENSE') (Join-Path $dist 'LICENSE.txt')
Copy-Item (Join-Path $root 'CHANGELOG.md') $dist      # What's new shows its top sections to players of a local or offline copy
New-Item -ItemType Directory -Force (Join-Path $dist 'lib') | Out-Null
Copy-Item (Join-Path $root 'lib\AnchorChain.keel.bin'), (Join-Path $root 'lib\THIRD-PARTY.txt') (Join-Path $dist 'lib')
$preview = Join-Path $root 'workshop\preview.jpg'
if (Test-Path $preview) { Copy-Item $preview $dist } else { Write-Warning 'workshop\preview.jpg missing.' }

$version = ([xml](Get-Content (Join-Path $root 'src\SeaPowerKeel\SeaPowerKeel.csproj'))).Project.PropertyGroup.Version | Where-Object { $_ } | Select-Object -First 1
Write-Host "Staged R.A.T.S. Keel $version in $dist"

if ($Install) {
    if (Get-Process -Name 'Sea Power' -ErrorAction SilentlyContinue) { throw 'Sea Power is running - close it first.' }
    $target = Join-Path $GameDir 'Sea Power_Data\StreamingAssets\SeaPowerKeel'
    if (Test-Path $target) { Remove-Item -Recurse -Force $target }
    Copy-Item -Recurse $dist $target
    Write-Host "Installed to $target"
}
