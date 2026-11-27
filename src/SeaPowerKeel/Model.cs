using System;
using System.Collections.Generic;

namespace SeaPowerKeel;

internal enum PluginKind
{
    BepInEx,        // a plain BepInEx plugin ([BepInPlugin] on a BaseUnityPlugin) in a mod folder
    AnchorChain,    // an Anchor Chain mod ([ACPlugin] on an IAnchorChainMod)
}

internal sealed class Dependency
{
    public string Guid;
    public Version Min;
    public Version Max;     // inclusive upper bound (Anchor Chain's ranges); null = any
    public bool Hard = true;

    public bool Accepts(Version v) => (Min == null || v >= Min) && (Max == null || v <= Max);

    public string Range => Min == null && Max == null ? "" : Max == null ? $" {Min} or newer" : Min == null ? $" up to {Max}" : $" {Min} to {Max}";
}

internal sealed class PluginEntry
{
    public string Guid;
    public string Name;
    public Version Version = new(1, 0);
    public PluginKind Kind;
    public string TypeName;
    public string Dll;
    public string AssemblyName;
    public ModFolder Folder;
    public int Order;                       // folder position, then file, then type: the tie-breaker everywhere

    public readonly List<Dependency> Dependencies = new();
    public readonly List<string> LoadBefore = new();   // plugins that must start after this one (Anchor Chain "before")
    public readonly List<string> Incompatible = new();
    public readonly List<string> Processes = new();    // [BepInProcess]: empty = any
    public bool UsesAcConfig;
    public bool AcConfigRequired = true;               // [ACConfig(required)]: a config file that cannot be made keeps the mod from starting
    public bool Exported = true;                        // Anchor Chain only sees public (exported) plugin classes
    public bool StartEarly;                             // asked to start before the load screen ends (EarlyStart)
    public bool BlockingStart;                          // asked to start before the game's first frame, holding the game up (EarlyStart)
    /// <summary>The Workshop items the mod's folder names as required in its _info.ini (RequiredItems).</summary>
    public readonly List<RequiredItem> RequiredItems = new();
    /// <summary>Set when the mod is kept out because a plugin it needs is missing or too old and that plugin comes from a required item: the card offers it.</summary>
    public RequiredItem MissingItem;
    /// <summary>GUIDs of the same DLL's backup entries (a BepInEx entry next to the Anchor Chain one): a dependency on one of them
    /// counts as met by this entry. The backup entry itself is not listed (rgreat 2026-11-12: a second entry is by design).</summary>
    public readonly List<string> AlsoKnownAs = new();

    public PluginState State = PluginState.Pending;
    public string Reason = "";
    public readonly List<string> Warnings = new();
    public string LoadOrderWarning;
    /// <summary>Every game method/field/type the DLL uses that this build lacks, as <c>Namespace.Type::Member(args)</c> (the preflight check).</summary>
    public readonly List<string> MissingUses = new();
    /// <summary>Set when this DLL is the other map kind's build of a mod whose matching build sits in the same folder (XFlat.dll beside X.dll): its missing parts are expected.</summary>
    public string OtherMapBuildOf;
    public int LaterErrors;
    public string FirstStartupError;
    public string FirstLaterError;
    public float StartMs;
    public object Instance;

    public string Display => string.IsNullOrEmpty(Name) ? Guid : Name;

    private string sha256;
    /// <summary>The DLL's SHA-256 as lowercase hex, read once when first asked: players compare it with the release's checksum list
    /// to see that the file is the one that was published and scanned (roadmap 2026-11-26). Empty when the file cannot be read.</summary>
    public string Sha256 => sha256 ??= FileHash.Sha256(Dll);

    public void Stop(PluginState state, string reason)
    {
        State = state;
        Reason = reason;
    }
}

/// <summary>A DLL the scanner did not read as a plugin source, and why (shown in the report).</summary>
internal sealed class SkippedDll
{
    public string Path;
    public ModFolder Folder;
    public string Reason;
}
