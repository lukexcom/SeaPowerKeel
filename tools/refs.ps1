# The files Keel compiles against, all public and pinned by hash: the official BepInEx release and Unity's reference assemblies
# from BepInEx's NuGet feed. Dot-sourced by package.ps1 (the release build on the developer's PC) and ci-build.ps1 (GitHub
# Actions), so both compile against the very same bytes and give the same DLLs: release-check.yml rebuilds every release this
# way and compares it with the published zip. (Until 0.8.1 package.ps1 took the developer's game folder, whose BepInEx core
# can be another build, e.g. Alpine's.)
. (Join-Path $PSScriptRoot 'bepinex.ps1')

$UnityVersion = '6000.0.84'
$UnitySha256 = '25c5a5009b775e727729acc28e0d9d910735ec4f4a2312d49a1c9235ccb152c6'
$UnityRefs = 'UnityEngine.dll', 'UnityEngine.CoreModule.dll', 'UnityEngine.IMGUIModule.dll', 'UnityEngine.TextRenderingModule.dll'

# Returns @{ ManagedDir = <Unity references>; BepInExCore = <official BepInEx\core> }, cached in obj\.
function Get-PublicRefs([string]$root) {
    $bepInEx = Get-OfficialBepInEx $root
    $cache = Join-Path $root 'obj\unity'
    New-Item -ItemType Directory -Force $cache | Out-Null
    $nupkg = Join-Path $cache "unityengine.modules.$UnityVersion.nupkg"
    if (-not (Test-Path $nupkg)) {
        $ProgressPreference = 'SilentlyContinue'
        Invoke-WebRequest "https://nuget.bepinex.dev/v3/package/unityengine.modules/$UnityVersion/unityengine.modules.$UnityVersion.nupkg" -OutFile $nupkg
    }
    $hash = (Get-FileHash $nupkg -Algorithm SHA256).Hash.ToLowerInvariant()
    if ($hash -ne $UnitySha256) { throw "UnityEngine.Modules $UnityVersion is not the pinned package (SHA-256 $hash). Delete $nupkg and build again." }
    $unpacked = Join-Path $cache 'unpacked'
    if (Test-Path $unpacked) { Remove-Item -Recurse -Force $unpacked }
    # Expand-Archive of Windows PowerShell 5.1 refuses any extension but .zip
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    [System.IO.Compression.ZipFile]::ExtractToDirectory($nupkg, $unpacked)
    $managed = Join-Path $cache 'managed'
    New-Item -ItemType Directory -Force $managed | Out-Null
    foreach ($name in $UnityRefs) {
        # one fixed flavour of the package: a different folder would change the references written into the DLL
        Copy-Item (Join-Path $unpacked "lib\netstandard2.0\$name") $managed -Force
    }
    return @{ ManagedDir = $managed; BepInExCore = Join-Path $bepInEx 'BepInEx\core' }
}
