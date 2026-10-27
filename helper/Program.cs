using System.Buffers.Binary;
using System.IO.Compression;
using System.Reflection;
using System.Text;
using System.Text.Json;
using System.Text.Json.Nodes;
using System.Text.RegularExpressions;
using GBX.NET;
using GBX.NET.Components;
using GBX.NET.Engines.Game;
using GBX.NET.Engines.GameData;
using GBX.NET.LZO;
using GBX.NET.Serialization;
using GBX.NET.Serialization.Chunking;

namespace WaterFields.Export;

internal static class Program
{
    private const int mapLimit = 512 * 1024 * 1024;
    private const int assetLimit = 1024 * 1024;
    private const string modelSuffix = ".Block.Gbx_CustomBlock";
    private const float maxHorizontalSize = 2048;
    private const float maxHeight = 256;

    private const int nativeDescriptionOffset = 2571;
    private const int wrapperDescriptionOffset = 424;

    internal static JsonObject Run(string requestPath, CancellationToken deadline)
    {
        Gbx.LZO = new Lzo();

        var requestBytes = Read(requestPath, 65536);
        string requestText = Encoding.UTF8.GetString(requestBytes).TrimStart('\uFEFF');
        using var request = JsonDocument.Parse(requestText);
        var root = request.RootElement;

        Require(root.GetProperty("schema").GetString() == "waterfields-export-v1", "Unsupported request version.");

        string input = Path.GetFullPath(root.GetProperty("input").GetString()!);
        string output = Path.GetFullPath(root.GetProperty("output").GetString()!);
        string assets = Path.GetFullPath(root.GetProperty("assetRoot").GetString()!);

        Require(
            input.EndsWith(".Map.Gbx", StringComparison.OrdinalIgnoreCase)
            && output.EndsWith(".Map.Gbx", StringComparison.OrdinalIgnoreCase),
            "Choose .Map.Gbx files."
        );
        Require(
            !File.Exists(output) && !Directory.Exists(output) && !File.Exists(output + ".json"),
            "Output must be new."
        );

        string mapUid = root.GetProperty("mapUid").GetString()!;

        return Export(input, output, assets, mapUid, deadline);
    }

    private static void Require(bool valid, string message)
    {
        if (!valid)
        {
            throw new InvalidDataException(message);
        }
    }

    private static byte[] Read(string path, int limit)
    {
        using var file = new FileStream(path, FileMode.Open, FileAccess.Read, FileShare.Read);
        Require(file.Length > 0 && file.Length <= limit, "Input size is outside the supported range: " + path);

        var bytes = new byte[(int)file.Length];
        file.ReadExactly(bytes);

        return bytes;
    }

    private static Gbx<CGameCtnChallenge> ParseMap(byte[] bytes)
    {
        using var stream = new MemoryStream(bytes, false);
        var gbx = Gbx.Parse<CGameCtnChallenge>(stream, Limits(mapLimit));

        if (gbx.Body.Exception is not null)
        {
            throw gbx.Body.Exception;
        }

        return gbx;
    }

    private static GbxReadSettings Limits(int size) => new()
    {
        MaxDataSize = size,
        MaxUncompressedBodySize = size,
        MaxCompressedBodySize = size
    };

    private static byte[] Save(Gbx gbx)
    {
        using var stream = new MemoryStream();
        gbx.Save(stream);

        Require(stream.Length <= mapLimit, "Export is too large.");

        return stream.ToArray();
    }

    private static byte[] Content(byte[] bytes)
    {
        var gbx = ParseMap(bytes);
        gbx.Node.EmbeddedZipData = [];

        return Save(gbx);
    }

    private static byte[] Template(string name)
    {
        string resourceName = "WaterFields.Templates." + name;
        using var stream = Assembly.GetExecutingAssembly().GetManifestResourceStream(resourceName) ??
                           throw new InvalidDataException("Missing helper template: " + name);
        using var copy = new MemoryStream();
        stream.CopyTo(copy);

        return copy.ToArray();
    }

    private static byte[] WithDescription(byte[] bytes, int offset, string description)
    {
        int length = BinaryPrimitives.ReadInt32LittleEndian(bytes.AsSpan(offset));
        var text = Encoding.UTF8.GetBytes(description);
        var prefix = bytes[..offset];
        var suffix = bytes[(offset + 4 + length)..];

        return prefix
            .Concat(BitConverter.GetBytes(text.Length))
            .Concat(text)
            .Concat(suffix)
            .ToArray();
    }

    private static float[] ValidateAssets(string stem, Dictionary<string, byte[]> files)
    {
        var wrapper = ReadWrapper(files[stem + ".Block.Gbx"]).Node;
        string metadata = wrapper.Description ?? "";
        string version = metadata.StartsWith("WaterFields:2:", StringComparison.Ordinal) ? "2" : "1";
        string prefix = "WaterFields:" + version + ":" + stem + ":";

        Require(
            metadata.StartsWith(prefix, StringComparison.Ordinal)
            && Regex.IsMatch(metadata[prefix.Length..], "^[0-9a-f]{48}$"),
            "Invalid water metadata."
        );

        var values = new float[6];

        for (int i = 0; i < values.Length; i++)
        {
            string hex = metadata.Substring(prefix.Length + i * 8, 8);
            uint bits = Convert.ToUInt32(hex, 16);
            values[i] = BitConverter.UInt32BitsToSingle(bits);
        }

        Require(
            values.All(float.IsFinite)
            && values.Take(3).All(v => Math.Abs(v) < 16384)
            && values.Skip(3).All(v => v >= .25f)
            && values[3] <= maxHorizontalSize
            && values[4] <= maxHeight
            && values[5] <= maxHorizontalSize,
            "Unsupported water bounds."
        );

        using var manifest = JsonDocument.Parse(Template("manifest.json"));
        var native = Template("v28_000_Water_Area.EDClassic.Gbx");
        var expectedWrapper = Template("v28_000_Water_Area.Block.Gbx");
        var stemBytes = Encoding.ASCII.GetBytes(stem);

        foreach (var (bytes, key) in new[] {
            (native, "nativeIdentityOffsets"),
            (expectedWrapper, "wrapperIdentityOffsets")
        })
        {
            foreach (var offset in manifest.RootElement.GetProperty(key).EnumerateArray())
            {
                stemBytes.CopyTo(bytes, offset.GetInt32() - 4);
            }
        }

        float[] transformValues = [
            values[0],
            values[1],
            values[2],
            0f,
            values[3],
            values[4],
            values[5]
        ];
        var transformBytes = transformValues.SelectMany(BitConverter.GetBytes).ToArray();

        foreach (var offset in manifest.RootElement.GetProperty("waterOffsets").EnumerateArray())
        {
            transformBytes.CopyTo(native, offset.GetInt32());
        }

        var expectedNative = WithDescription(native, nativeDescriptionOffset, metadata);
        expectedWrapper = WithDescription(expectedWrapper, wrapperDescriptionOffset, metadata);
        var expectedPrefab = Template("v28_000_Water_Area.Prefab.Gbx");

        Require(
            files["Native/" + stem + ".EDClassic.Gbx"].SequenceEqual(expectedNative),
            "Generated native asset differs from the water recipe: " + stem
        );
        Require(
            files[stem + ".Block.Gbx"].SequenceEqual(expectedWrapper),
            "Generated wrapper asset differs from the water recipe: " + stem
        );
        Require(
            files["Native/" + stem + ".Prefab.Gbx"].SequenceEqual(expectedPrefab),
            "Generated prefab asset differs from the water recipe: " + stem
        );

        foreach (var (path, bytes) in files)
        {
            using var stream = new MemoryStream(bytes, false);
            var gbx = Gbx.ParseHeader(stream);
            var refs = gbx.RefTable;

            if (refs is null)
            {
                continue;
            }

            Require(refs.AncestorLevel == 0 && refs.Resources.Count == 0, "Unsupported asset reference table: " + path);

            string directory = Path.GetDirectoryName(path) ?? "";

            foreach (var reference in refs.Files)
            {
                string dependency = Path.Combine(directory, reference.FilePath).Replace('\\', '/');

                Require(files.ContainsKey(dependency), "Missing asset dependency: " + path + " -> " + dependency);
            }
        }

        return values;
    }

    private static byte[] BuildBoundary(string stem, float[] values)
    {
        var bytes = Template("boundary.Item.Gbx");
        using var manifest = JsonDocument.Parse(Template("boundary_manifest.json"));
        var root = manifest.RootElement;
        var identity = Encoding.ASCII.GetBytes(stem[..7] + "_Water_Boundary");

        foreach (var offset in root.GetProperty("identityOffsets").EnumerateArray())
        {
            identity.CopyTo(bytes, offset.GetInt32() - 4);
        }

        foreach (var coordinate in root.GetProperty("coordinates").EnumerateArray())
        {
            int axis = coordinate.GetProperty("axis").GetInt32();
            int offset = coordinate.GetProperty("offset").GetInt32();
            float side = coordinate.GetProperty("side").GetSingle();
            BitConverter.GetBytes(values[axis + 3] * side).CopyTo(bytes, offset);
        }

        foreach (var offset in root.GetProperty("boundsOffsets").EnumerateArray())
        {
            for (int i = 0; i < 6; i++)
            {
                BitConverter.GetBytes(values[3 + i % 3] / 2).CopyTo(bytes, offset.GetInt32() + i * 4);
            }
        }

        return bytes;
    }

    private static Gbx<CGameItemModel> ReadWrapper(byte[] bytes)
    {
        var copy = bytes.ToArray();

        BinaryPrimitives.WriteInt32LittleEndian(
            copy.AsSpan(HeaderTypeOffset(copy)),
            (int)CGameItemModel.EItemType.Ornament
        );

        using var stream = new MemoryStream(copy, false);
        var gbx = Gbx.Parse<CGameItemModel>(stream, Limits(assetLimit));

        if (gbx.Body.Exception is not null)
        {
            throw gbx.Body.Exception;
        }

        return gbx;
    }

    private static Dictionary<string, byte[]> ReadZip(CGameCtnChallenge map, Dictionary<string, string> aliases)
    {
        var entries = new Dictionary<string, byte[]>(StringComparer.OrdinalIgnoreCase);

        if (map.EmbeddedZipData is not { Length: > 0 })
        {
            return entries;
        }

        using var zip = map.OpenReadEmbeddedZipData();
        Require(zip.Entries.Count <= 16384, "Too many embedded files.");
        long total = 0;

        foreach (var entry in zip.Entries)
        {
            string path = entry.FullName.Replace('\\', '/');
            string key = aliases.GetValueOrDefault(path, path);

            Require(
                !key.StartsWith('/') && key.Split('/').All(p => p != "." && p != ".." && !p.Contains(':')),
                "Unsafe embedded path: " + path
            );

            total += entry.Length;
            Require(entry.Length <= 64 * 1024 * 1024 && total <= 128 * 1024 * 1024, "Embedded files are too large.");

            using var stream = entry.Open();
            var bytes = new byte[(int)entry.Length];
            stream.ReadExactly(bytes);

            Require(
                stream.ReadByte() == -1 && entries.TryAdd(key, bytes),
                "Invalid or duplicate embedded file: " + key
            );
        }

        return entries;
    }

    private static byte[] WriteZip(Dictionary<string, byte[]> entries)
    {
        using var buffer = new MemoryStream();

        using (var zip = new ZipArchive(buffer, ZipArchiveMode.Create, true))
        {
            foreach (var (path, bytes) in entries)
            {
                var entry = zip.CreateEntry(path, CompressionLevel.Optimal);
                entry.LastWriteTime = new DateTimeOffset(2000, 1, 1, 0, 0, 0, TimeSpan.Zero);

                using var stream = entry.Open();
                stream.Write(bytes);
            }
        }

        return buffer.ToArray();
    }

    private static JsonObject Export(
        string input,
        string output,
        string assetRoot,
        string mapUid,
        CancellationToken deadline
    )
    {
        deadline.ThrowIfCancellationRequested();

        var original = Read(input, mapLimit);
        var gbx = ParseMap(original);
        var map = gbx.Node;

        Require(map.MapUid == mapUid && !string.IsNullOrWhiteSpace(mapUid), "Map UID differs from the request.");
        Require(map.MapInfo.Collection == new Id(26), "Only Stadium maps are supported.");

        var placements = (map.Blocks ?? []).Concat(map.BakedBlocks ?? []).ToArray();
        var fields = placements
            .Where(b => Regex.IsMatch(b.Name ?? "", @"^wf1_[A-Z0-9]{3}_Water_Area\.Block\.Gbx_CustomBlock$"))
            .GroupBy(b => b.Name![..^modelSuffix.Length])
            .ToArray();

        Require(fields.Length is > 0 and <= 4096, "No supported water fields, or too many fields.");

        var files = new Dictionary<string, byte[]>(StringComparer.OrdinalIgnoreCase);
        var evidence = new Dictionary<string, byte[]>(StringComparer.OrdinalIgnoreCase);
        var aliases = new Dictionary<string, string>(StringComparer.OrdinalIgnoreCase);
        var identities = new List<Ident>();

        foreach (var field in fields)
        {
            deadline.ThrowIfCancellationRequested();

            string stem = field.Key;
            Require(
                field.All(b => b.Direction == Direction.North && b.IsGhost),
                "Only north-facing ghost water is supported."
            );

            var built = new Dictionary<string, byte[]>();

            foreach (var path in new[] {
                stem + ".Block.Gbx",
                "Native/" + stem + ".EDClassic.Gbx",
                "Native/" + stem + ".Prefab.Gbx"
            })
            {
                string source = Path.Combine(assetRoot, path);
                var bytes = Read(source, assetLimit);

                built.Add(path, bytes);
                evidence.Add(source, bytes);
                files.Add("Blocks/" + path, bytes);

                if (path.EndsWith(".Block.Gbx", StringComparison.Ordinal))
                {
                    aliases.Add(source.Replace('\\', '/'), "Blocks/" + path);
                }
            }

            var values = ValidateAssets(stem, built);

            string metadata = ReadWrapper(built[stem + ".Block.Gbx"]).Node.Description ?? "";
            if (metadata.StartsWith("WaterFields:2:", StringComparison.Ordinal))
            {
                string boundaryId = "WaterFieldsBoundaries_v1/" + stem[..7] + "_Water_Boundary.Item.Gbx";
                var items = (map.AnchoredObjects ?? [])
                    .Where(item => item.ItemModel.Id.Replace('\\', '/') == boundaryId)
                    .ToArray();

                Require(items.Length == field.Count(), "Missing or copied water boundary: " + stem);
                foreach (var block in field)
                {
                    var minimum = new Vec3(
                        block.Coord.X * 32 + values[0],
                        (block.Coord.Y - 8) * 8 + values[1],
                        block.Coord.Z * 32 + values[2]
                    );
                    Require(
                        items.Count(item => item.AbsolutePositionInMap == minimum
                            && item.YawPitchRoll == new Vec3() && item.Scale == 1) == 1,
                        "A water boundary was moved, rotated, scaled or duplicated: " + stem
                    );
                }

                var expected = BuildBoundary(stem, values);
                using var boundaryStream = new MemoryStream(expected, false);
                var boundaryIdentity = Gbx.Parse<CGameItemModel>(boundaryStream, Limits(assetLimit)).Node.Ident;
                Require(
                    items.All(item => item.ItemModel.Author == boundaryIdentity.Author
                        && item.ItemModel.Collection == boundaryIdentity.Collection),
                    "Saved boundary binding differs from its package: " + stem
                );
                identities.Add(boundaryIdentity);
                string source = Path.GetFullPath(Path.Combine(assetRoot, "../../Items", boundaryId));
                var bytes = Read(source, assetLimit);
                Require(bytes.SequenceEqual(expected), "Water boundary differs from its recipe: " + stem);
                evidence.Add(source, bytes);
                files.Add("Items/" + boundaryId, bytes);
                aliases.Add(source.Replace('\\', '/'), "Items/" + boundaryId);
            }

            var ident = ReadWrapper(built[stem + ".Block.Gbx"]).Node.Ident;
            Require(
                ident.Id == stem + ".Block.Gbx" && !string.IsNullOrWhiteSpace(ident.Author),
                "Invalid wrapper identity."
            );
            Require(
                field.All(b => b.Author == ident.Author && (b.Flags & 0x8000) != 0),
                "Saved water binding differs from its package."
            );

            identities.Add(ident);
        }

        if (!map.Chunks.OfType<CGameCtnChallenge.Chunk03043054>().Any())
        {
            map.Chunks.Create<CGameCtnChallenge.Chunk03043054>();
        }

        var comparison = Content(Save(gbx));
        var entries = ReadZip(map, aliases);

        foreach (var (path, bytes) in files)
        {
            if (entries.TryGetValue(path, out var old) && !old.SequenceEqual(bytes))
            {
                Require(
                    path.EndsWith(".Block.Gbx", StringComparison.Ordinal),
                    "Conflicting embedded dependency: " + path
                );
                ValidateStrippedWrapper(old, bytes);
            }

            entries[path] = bytes;
        }

        map.EmbeddedZipData = WriteZip(entries);
        var result = Save(gbx);

        deadline.ThrowIfCancellationRequested();
        Require(Content(result).SequenceEqual(comparison), "Export changed non-embedding map content.");

        var saved = ParseMap(result).Node;
        var savedEntries = ReadZip(saved, new(StringComparer.OrdinalIgnoreCase));

        Require(savedEntries.Count == entries.Count, "Export changed the embedded file count.");

        foreach (var (path, bytes) in entries)
        {
            Require(
                savedEntries.TryGetValue(path, out var savedBytes) && savedBytes.SequenceEqual(bytes),
                "Export is missing or changed an embedded dependency: " + path
            );
        }

        foreach (var identity in identities)
        {
            Require(
                saved.ExpectedEmbeddedItemModels?.Contains(identity) == true,
                "Export is missing a water model identity: " + identity.Id
            );
        }

        Require(Read(input, mapLimit).SequenceEqual(original), "Input map changed during export.");

        foreach (var (path, bytes) in evidence)
        {
            Require(Read(path, assetLimit).SequenceEqual(bytes), "Source asset changed during export: " + path);
        }

        Directory.CreateDirectory(Path.GetDirectoryName(output)!);
        string temporary = output + "." + Guid.NewGuid().ToString("N") + ".tmp";

        try
        {
            using (var file = new FileStream(temporary, FileMode.CreateNew, FileAccess.Write, FileShare.None))
            {
                file.Write(result);
                file.Flush(true);
            }

            Require(Read(temporary, mapLimit).SequenceEqual(result), "Written export differs from verified bytes.");
            deadline.ThrowIfCancellationRequested();

            File.Move(temporary, output, false);
        }
        finally
        {
            if (File.Exists(temporary))
            {
                File.Delete(temporary);
            }
        }

        var receipt = new JsonObject
        {
            ["schema"] = "waterfields-export-result-v1",
            ["status"] = "verified",
            ["input"] = input,
            ["output"] = output,
            ["mapUid"] = mapUid,
            ["fields"] = new JsonArray(fields.Select(f => (JsonNode?)JsonValue.Create(f.Key)).ToArray()),
            ["inputBytes"] = original.Length,
            ["outputBytes"] = result.Length,
            ["placementWrites"] = 0,
            ["sourceUnchanged"] = true,
            ["contentPreserved"] = true,
            ["embeddedFiles"] = entries.Count
        };

        try
        {
            using var file = new FileStream(output + ".json", FileMode.CreateNew, FileAccess.Write, FileShare.None);
            var receiptBytes = Encoding.UTF8.GetBytes(
                receipt.ToJsonString(new JsonSerializerOptions { WriteIndented = true })
            );

            file.Write(receiptBytes);
            file.Flush(true);
        }
        catch (Exception e)
        {
            throw new IOException("Map written and verified, but its receipt failed: " + output, e);
        }

        return receipt;
    }

    private static byte[] SaveUncompressed(Gbx gbx)
    {
        gbx.Header.Basic = gbx.Header.Basic with { CompressionOfBody = GbxCompression.Uncompressed };

        return Save(gbx);
    }

    private static int HeaderTypeOffset(byte[] bytes)
    {
        if (bytes.Length < 25
            || Encoding.ASCII.GetString(bytes, 0, 3) != "GBX"
            || BinaryPrimitives.ReadUInt16LittleEndian(bytes.AsSpan(3)) != 6
            || bytes[5] != (byte)'B'
            || BinaryPrimitives.ReadUInt32LittleEndian(bytes.AsSpan(9)) != 0x2E002000)
        {
            throw new InvalidDataException("Expected binary GBX v6 CGameItemModel.");
        }

        var size = BinaryPrimitives.ReadInt32LittleEndian(bytes.AsSpan(13));
        var count = BinaryPrimitives.ReadInt32LittleEndian(bytes.AsSpan(17));

        if (count is < 1 or > 64 || size < 4 + count * 8 || size > bytes.Length - 17)
        {
            throw new InvalidDataException("Invalid header bounds.");
        }

        var cursor = 21 + count * 8;
        var result = -1;

        for (var i = 0; i < count; i++)
        {
            var id = BinaryPrimitives.ReadUInt32LittleEndian(bytes.AsSpan(21 + i * 8));
            var length = BinaryPrimitives.ReadInt32LittleEndian(bytes.AsSpan(25 + i * 8)) & int.MaxValue;

            if (length > 17 + size - cursor)
            {
                throw new InvalidDataException("Header payload exceeds bounds.");
            }

            if (id == 0x2E002000)
            {
                if (length != 4 || result >= 0)
                {
                    throw new InvalidDataException("Unexpected item-type header.");
                }

                result = cursor;
            }

            cursor += length;
        }

        if (result < 0 || cursor != 17 + size)
        {
            throw new InvalidDataException("Missing or malformed item-type header.");
        }

        return result;
    }

    private static void ValidateStrippedWrapper(byte[] embedded, byte[] generated)
    {
        Require(embedded.Length <= assetLimit, "Embedded water wrapper is too large.");

        using var stream = new MemoryStream(embedded, false);
        var old = Gbx.Parse<CGameItemModel>(stream, Limits(assetLimit));

        if (old.Body.Exception is not null)
        {
            throw old.Body.Exception;
        }

        var full = ReadWrapper(generated);

        Require(old.Node.Ident == full.Node.Ident, "Embedded water wrapper identity differs from its package.");
        Require(
            old.Node.Description == full.Node.Description,
            "Embedded water wrapper metadata differs from its package."
        );
        Require(old.Node.ItemTypeE == CGameItemModel.EItemType.Block, "Embedded water wrapper is not a block.");
        Require(
            old.Node.EntityModel is null && old.Node.EntityModelEditionFile is null,
            "Embedded water wrapper contains a compiled model or an external editor recipe."
        );
        Require(
            old.RefTable is null || old.RefTable.Files.Count + old.RefTable.Resources.Count == 0,
            "Embedded water wrapper has external dependencies."
        );
        Require(
            old.Node.EntityModelEdition is CGameBlockItem && full.Node.EntityModelEdition is CGameBlockItem,
            "Missing water block recipe."
        );

        var oldRecipe = (CGameBlockItem)old.Node.EntityModelEdition!;
        var newRecipe = (CGameBlockItem)full.Node.EntityModelEdition!;

        Require(
            oldRecipe.CustomizedVariants.Count == 0 && newRecipe.CustomizedVariants.Count == 0,
            "Water recipe has customized variants."
        );

        foreach (var recipe in new[] { oldRecipe, newRecipe })
        {
            Require(
                recipe.Chunks.SingleOrDefault(c => c.Id == 0x2E025003) is ISkippableChunk,
                "Missing empty variant-record metadata."
            );

            var chunk = (ISkippableChunk)recipe.Chunks.Single(c => c.Id == 0x2E025003);

            Require(
                chunk.Data is { Length: 4 or 5 } && chunk.Data.All(x => x == 0),
                "Unsupported empty variant-record metadata."
            );

            chunk.Data = new byte[4];
        }

        var oldRecipeBytes = SaveUncompressed(oldRecipe.ToGbx());
        var newRecipeBytes = SaveUncompressed(newRecipe.ToGbx());

        Require(
            oldRecipeBytes.SequenceEqual(newRecipeBytes),
            "Editor wrapper recipe differs from the verified generated package."
        );
    }
}
