using System.Text;
using System.Text.Json;
using System.Text.Json.Nodes;
using System.Text.RegularExpressions;
using GBX.NET;
using GBX.NET.Engines.Game;

namespace WaterFields.Export;

internal static class SaveGuard
{
    private const int mapLimit = 512 * 1024 * 1024;
    private const int leaseMs = 15000;
    private static readonly object gate = new();
    private static volatile Request? current;
    private static long renewedAt;
    private static Task? worker;

    internal sealed record Field(string stem, Int3 anchor, int variant, bool ground);
    internal sealed record Request(
        string session, int revision, string input, string assetRoot, string mapUid,
        string statusPath, Field[] fields, string json
    );

    internal static Request Parse(string json)
    {
        Program.Require(Encoding.UTF8.GetByteCount(json) <= 2 * 1024 * 1024, "Save request is too large.");
        using var document = JsonDocument.Parse(json);
        var root = document.RootElement;
        Program.Require(root.GetProperty("schema").GetString() == "waterfields-save-v1", "Unsupported save request.");
        string session = root.GetProperty("session").GetString()!;
        int revision = root.GetProperty("revision").GetInt32();
        string mapUid = root.GetProperty("mapUid").GetString()!;
        Program.Require(!string.IsNullOrWhiteSpace(session) && session.Length <= 128 && revision > 0,
            "Invalid save session.");
        Program.Require(!string.IsNullOrWhiteSpace(mapUid) && mapUid.Length <= 128, "Invalid map UID.");
        string input = root.GetProperty("input").GetString()!;
        if (input.Length > 0)
        {
            Program.Require(Path.IsPathFullyQualified(input)
                && input.EndsWith(".Map.Gbx", StringComparison.OrdinalIgnoreCase), "Invalid saved map path.");
            input = Path.GetFullPath(input);
        }
        string assets = Path.GetFullPath(root.GetProperty("assetRoot").GetString()!);
        string statusPath = Path.GetFullPath(root.GetProperty("statusPath").GetString()!);
        Program.Require(statusPath.EndsWith(".json", StringComparison.OrdinalIgnoreCase), "Invalid save status path.");
        var list = root.GetProperty("fields");
        Program.Require(list.ValueKind == JsonValueKind.Array && list.GetArrayLength() <= 4096,
            "Invalid field list.");
        var fields = new List<Field>();
        foreach (var field in list.EnumerateArray())
        {
            string stem = field.GetProperty("stem").GetString()!;
            Program.Require(Regex.IsMatch(stem, "^wf1_[A-Z0-9]{3}_Water_Area$"), "Invalid water identity.");
            var coord = field.GetProperty("anchor").EnumerateArray().Select(v => v.GetInt32()).ToArray();
            int variant = field.GetProperty("variant").GetInt32();
            Program.Require(coord.Length == 3 && coord.All(v => v >= 0 && v < 4096)
                && variant >= 0 && variant < 64, "Invalid water placement.");
            fields.Add(new(stem, new(coord[0], coord[1], coord[2]), variant, field.GetProperty("ground").GetBoolean()));
        }
        return new(session, revision, input, assets, mapUid, statusPath, fields.ToArray(), json);
    }

    internal static void Pulse(string json)
    {
        lock (gate)
        {
            if (current?.json == json && worker is { IsCompleted: false })
            {
                renewedAt = Environment.TickCount64;
                return;
            }
        }
        var request = Parse(json);
        lock (gate)
        {
            if (current?.json != json)
            {
                current = request;
            }
            renewedAt = Environment.TickCount64;
            if (worker is null || worker.IsCompleted)
            {
                worker = Task.Run(Watch);
            }
        }
    }

    internal static void Stop()
    {
        lock (gate)
        {
            current = null;
        }
    }

    private static bool IsCurrent(Request request)
    {
        return ReferenceEquals(current, request) && Environment.TickCount64 - Volatile.Read(ref renewedAt) < leaseMs;
    }

    private static async Task Watch()
    {
        Gbx.LZO = new GBX.NET.LZO.Lzo();
        Request? previous = null;
        byte[]? observed = null;
        byte[]? verified = null;
        string backup = "";

        while (true)
        {
            Request request;
            lock (gate)
            {
                if (current is null || !IsCurrent(current))
                {
                    current = null;
                    worker = null;
                    return;
                }
                request = current;
            }
            try
            {
                if (!ReferenceEquals(previous, request))
                {
                    if (previous?.input != request.input) backup = "";
                    observed = null;
                    verified = null;
                    previous = request;
                }
                if (request.input.Length == 0 || !File.Exists(request.input))
                {
                    Publish(request, "placed", "Save the map to verify its water.", backup);
                }
                else
                {
                    if (verified is not null && FileEquals(request.input, verified))
                    {
                        Publish(request, "verified", "Saved water verified.", backup);
                        await Task.Delay(1000);
                        continue;
                    }
                    var bytes = Program.Read(request.input, mapLimit);
                    if (observed is null || !bytes.SequenceEqual(observed))
                    {
                        verified = null;
                        observed = bytes;
                        Publish(request, "awaiting", "Waiting for the saved file to settle.", backup);
                    }
                    else
                    {
                        using var deadline = new CancellationTokenSource(TimeSpan.FromSeconds(30));
                        var map = Program.ParseMap(bytes).Node;
                        if (!Matches(map, request))
                        {
                            Publish(request, "placed", "The saved file does not contain this water layout. Save again.", backup);
                        }
                        else
                        {
                            Publish(request, "awaiting", "Verifying saved water...", backup);
                            var output = request.fields.Length == 0 ? bytes :
                                Program.Prepare(bytes, request.assetRoot, request.mapUid, deadline.Token).bytes;
                            deadline.Token.ThrowIfCancellationRequested();
                            if (!IsCurrent(request)) continue;
                            if (!bytes.SequenceEqual(output))
                            {
                                Replace(request, bytes, output, deadline.Token, ref backup);
                            }
                            verified = output;
                            observed = output;
                            Program.Require(Program.Read(request.input, mapLimit).SequenceEqual(output),
                                "Another save changed the map after verification; retrying.");
                            Publish(request, "verified", "Saved water verified.", backup);
                        }
                    }
                }
            }
            catch (Exception e)
            {
                verified = null;
                try
                {
                    Publish(request, "attention", e is OperationCanceledException ?
                        "Save verification timed out. Retry when the editor is idle." : e.Message, backup);
                }
                catch { }
            }
            await Task.Delay(1000);
        }
    }

    internal static bool Matches(CGameCtnChallenge map, Request request)
    {
        if (map.MapUid != request.mapUid || map.MapInfo.Collection != new Id(26)) return false;
        var blocks = (map.Blocks ?? []).Concat(map.BakedBlocks ?? [])
            .Where(b => (b.Name ?? "").StartsWith("wf1_", StringComparison.Ordinal)).ToList();
        if (blocks.Count != request.fields.Length) return false;
        foreach (var field in request.fields)
        {
            int index = blocks.FindIndex(b => b.Name == field.stem + ".Block.Gbx_CustomBlock"
                && b.Coord == field.anchor && b.Direction == Direction.North && b.IsGhost
                && b.Variant == field.variant && b.IsGround == field.ground);
            if (index < 0) return false;
            blocks.RemoveAt(index);
        }
        return true;
    }

    private static bool FileEquals(string path, byte[] expected)
    {
        using var file = new FileStream(path, FileMode.Open, FileAccess.Read, FileShare.Read);
        if (file.Length != expected.Length) return false;
        var buffer = new byte[65536];
        for (int offset = 0; offset < expected.Length; offset += buffer.Length)
        {
            int count = Math.Min(buffer.Length, expected.Length - offset);
            file.ReadExactly(buffer.AsSpan(0, count));
            if (!buffer.AsSpan(0, count).SequenceEqual(expected.AsSpan(offset, count))) return false;
        }
        return true;
    }

    internal static void Replace(
        Request request, byte[] original, byte[] output, CancellationToken deadline, ref string backup
    )
    {
        string suffix = ".waterfields-" + Guid.NewGuid().ToString("N");
        string staged = request.input + suffix + ".tmp";
        string backups = Path.Combine(Path.GetDirectoryName(request.input)!, ".waterfields-backups");
        Directory.CreateDirectory(backups);
        backup = Path.Combine(backups, Path.GetFileNameWithoutExtension(request.input) + suffix + ".Map.Gbx");
        try
        {
            using (var file = new FileStream(staged, FileMode.CreateNew, FileAccess.Write, FileShare.None))
            {
                file.Write(output);
                file.Flush(true);
            }
            Program.Require(Program.Read(staged, mapLimit).SequenceEqual(output), "Staged water map differs.");
            using var source = new FileStream(request.input, FileMode.Open, FileAccess.Read, FileShare.Read | FileShare.Delete);
            Program.Require(source.Length == original.Length, "A competing save changed the map.");
            var latest = new byte[original.Length];
            source.ReadExactly(latest);
            Program.Require(latest.SequenceEqual(original), "A competing save changed the map.");
            deadline.ThrowIfCancellationRequested();
            Publish(request, "awaiting", "Replacing the verified save; the original is retained as a backup.", backup);
            lock (gate)
            {
                Program.Require(IsCurrent(request), "The save session ended before replacement.");
                File.Move(request.input, backup, false);
            }
            try
            {
                Program.Require(Program.Read(backup, mapLimit).SequenceEqual(original),
                    "A competing save changed the file before replacement.");
                deadline.ThrowIfCancellationRequested();
                lock (gate)
                {
                    Program.Require(IsCurrent(request), "The save session ended before replacement.");
                    File.Move(staged, request.input, false);
                }
            }
            catch
            {
                if (!File.Exists(request.input)) File.Move(backup, request.input, false);
                throw;
            }
        }
        finally
        {
            if (File.Exists(staged)) File.Delete(staged);
        }
    }

    private static void Publish(Request request, string status, string message, string backup)
    {
        if (!IsCurrent(request)) return;
        WriteJson(request.statusPath, new JsonObject
        {
            ["schema"] = "waterfields-save-status-v1",
            ["session"] = request.session,
            ["revision"] = request.revision,
            ["mapUid"] = request.mapUid,
            ["input"] = request.input,
            ["status"] = status,
            ["message"] = message,
            ["backup"] = backup,
            ["checkedAt"] = DateTimeOffset.UtcNow.ToUnixTimeSeconds()
        });
    }

    private static void WriteJson(string path, JsonObject value)
    {
        Directory.CreateDirectory(Path.GetDirectoryName(path)!);
        string temporary = path + ".tmp";
        using (var file = new FileStream(temporary, FileMode.Create, FileAccess.Write, FileShare.None))
        {
            file.Write(Encoding.UTF8.GetBytes(value.ToJsonString()));
            file.Flush(true);
        }
        File.Move(temporary, path, true);
    }
}
