using System;
using System.Collections.Generic;
using System.Linq;
using System.Text;

namespace SeaPowerKeel;

internal static class Report
{
    public static bool IsProblem(PluginEntry p) => ReportFormat.IsProblem(p.State);

    public static int CountOrderWarnings(IEnumerable<PluginEntry> all) => all.Count(p => p.LoadOrderWarning != null);

    public static List<(string text, Tone tone)> SummaryParts(IReadOnlyCollection<PluginEntry> all) => ReportFormat.Summary(
        all.Count(p => ReportFormat.IsRunning(p.State)),
        all.Count(p => p.State == PluginState.RunningWithErrors),
        all.Count(p => p.State == PluginState.Failed),
        all.Count(p => p.State == PluginState.NotStarted),
        all.Count(p => p.State == PluginState.LeftToAnchorChain),
        CountOrderWarnings(all));

    public static string Summary(IReadOnlyCollection<PluginEntry> all) =>
        string.Join(ReportFormat.SummarySeparator, SummaryParts(all).Select(part => part.text));

    /// <summary>"STATE: Name 1.0 (folder) - reason", the line Keel logs for each mod's result.</summary>
    public static string ResultLine(PluginEntry p) =>
        $"{ReportFormat.Tag(p.State)}: {p.Display} {p.Version} ({p.Folder?.Label}){(p.Reason.Length > 0 ? " - " + p.Reason : "")}";

    public static string Text(IReadOnlyCollection<PluginEntry> all, string header, IEnumerable<string> notes, IReadOnlyCollection<SkippedDll> skipped = null)
    {
        var sb = new StringBuilder();
        sb.AppendLine(header);
        sb.AppendLine(Summary(all));
        foreach (string n in notes)
            sb.AppendLine("Note: " + n);
        sb.AppendLine();
        foreach (PluginEntry p in Sorted(all))
        {
            sb.AppendLine($"{ReportFormat.ModLine(p.State, p.Display, p.Version.ToString(), p.Guid)} – {p.Folder?.Label}, {System.IO.Path.GetFileName(p.Dll)}, {p.Kind}" +
                          (ReportFormat.IsRunning(p.State) ? $", started in {p.StartMs:0} ms" : ""));
            if (!string.IsNullOrEmpty(p.Reason))
                sb.AppendLine("    " + p.Reason);
            if (p.Sha256.Length > 0)
                sb.AppendLine("    SHA-256 " + p.Sha256);
            foreach (string w in p.Warnings)
                sb.AppendLine("    warning: " + w);
            if (p.OtherMapBuildOf != null)
                sb.AppendLine($"    note: the build for the other map kind; {p.OtherMapBuildOf} in the same folder is the one for this game build, so the {p.MissingUses.Count} part(s) it lacks here are expected (it stands down on its own)");
            if (p.LoadOrderWarning != null)
                sb.AppendLine("    warning: " + p.LoadOrderWarning);
            if (p.MissingUses.Count > 2)
                sb.AppendLine("    all missing in this build: " + string.Join("; ", p.MissingUses.Take(60)) + (p.MissingUses.Count > 60 ? $" (and {p.MissingUses.Count - 60} more)" : ""));
            if (p.LaterErrors > 0)
                sb.AppendLine($"    {p.LaterErrors} error(s) since it started, first: {p.FirstLaterError}");
        }
        if (skipped != null && skipped.Count > 0)
        {
            sb.AppendLine();
            sb.AppendLine($"DLLs left out on purpose ({skipped.Count}):");
            foreach (SkippedDll d in skipped)
                sb.AppendLine($"[SKIPPED DLL] {System.IO.Path.GetFileName(d.Path)} – {d.Folder?.Label}, {d.Path}{Environment.NewLine}    {d.Reason}");
        }
        sb.AppendLine();
        sb.AppendLine("R.A.T.S. Keel - Kanalratte");
        return sb.ToString();
    }

    /// <summary>Problems first, then running, then the rest; each group in start/mod-list order.</summary>
    public static IEnumerable<PluginEntry> Sorted(IEnumerable<PluginEntry> all) =>
        all.OrderBy(p => p.State switch
        {
            PluginState.Failed => 0,
            PluginState.NotStarted => 1,
            PluginState.RunningWithErrors => 2,
            PluginState.Running => 3,
            PluginState.LeftToAnchorChain => 4,
            _ => 5,
        }).ThenBy(p => p.Order);

    public static string Short(IList<string> items, int n = 2) =>
        string.Join("; ", items.Take(n)) + (items.Count > n ? $" (and {items.Count - n} more)" : "");
}
