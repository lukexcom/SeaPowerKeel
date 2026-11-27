<#
.SYNOPSIS
    Builds KeelWatcher.exe and KeelSetup.exe from the public source only: no game files, no files from a developer's PC.

.DESCRIPTION
    What the release builds need from outside this repository, all public: the official BepInEx release (compiled against; KeelSetup.exe
    downloads it on the player's PC, pinned to its hash) and the Unity reference assemblies from BepInEx's NuGet feed (only compiled against, never shipped). The results land in
    dist-ci\. This is what .github\workflows\build.yml runs, so a signature can be traced back to this source.
#>
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
. (Join-Path $PSScriptRoot 'refs.ps1')
$public = Get-PublicRefs $root      # the official BepInEx release and Unity's reference assemblies, both pinned by hash
$refs = "-p:ManagedDir=$($public.ManagedDir)", "-p:BepInExCore=$($public.BepInExCore)"
dotnet build (Join-Path $root 'src\SeaPowerKeel.Stub\SeaPowerKeel.Stub.csproj') -c Release -p:Deploy=false @refs
if ($LASTEXITCODE -ne 0) { throw 'Build failed: stub' }
dotnet build (Join-Path $root 'src\SeaPowerKeel.Patcher\SeaPowerKeel.Patcher.csproj') -c Release @refs
if ($LASTEXITCODE -ne 0) { throw 'Build failed: patcher' }
dotnet build (Join-Path $root 'src\SeaPowerKeel.Watcher\SeaPowerKeel.Watcher.csproj') -c Release @refs
if ($LASTEXITCODE -ne 0) { throw 'Build failed: KeelWatcher' }

dotnet build (Join-Path $root 'src\SeaPowerKeel.Setup\SeaPowerKeel.Setup.csproj') -c Release "-p:BepInExVersion=$BepInExVersion" "-p:BepInExSha256=$BepInExSha256" @refs
if ($LASTEXITCODE -ne 0) { throw 'Build failed: KeelSetup' }

$out = Join-Path $root 'dist-ci'
New-Item -ItemType Directory -Force $out | Out-Null
Copy-Item (Join-Path $root 'src\SeaPowerKeel.Watcher\bin\Release\net48\KeelWatcher.exe') $out
Copy-Item (Join-Path $root 'src\SeaPowerKeel.Setup\bin\Release\net48\KeelSetup.exe') $out
Get-ChildItem $out | ForEach-Object { '{0}  {1}  {2}' -f $_.Name, $_.VersionInfo.ProductName, $_.VersionInfo.ProductVersion }
