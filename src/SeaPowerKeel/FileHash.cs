using System;
using System.IO;
using System.Security.Cryptography;
using System.Text;

namespace SeaPowerKeel;

/// <summary>SHA-256 of a file, the same text as Get-FileHash and the release's SHA256SUMS.txt (lowercase hex).</summary>
internal static class FileHash
{
    public static string Sha256(string path)
    {
        try
        {
            using var stream = File.OpenRead(path);
            using var sha = SHA256.Create();
            byte[] digest = sha.ComputeHash(stream);
            var sb = new StringBuilder(digest.Length * 2);
            foreach (byte b in digest)
                sb.Append(b.ToString("x2"));
            return sb.ToString();
        }
        catch (Exception)
        {
            // A missing or locked file only costs the checksum line, never the report.
            return "";
        }
    }

    /// <summary>The first characters, enough to compare by eye in the report window.</summary>
    public static string Short(string hex) => hex.Length > 12 ? hex.Substring(0, 12) + "..." : hex;
}
