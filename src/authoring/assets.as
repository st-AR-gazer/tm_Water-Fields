namespace WaterFields {
    namespace Authoring {
        namespace Assets {
            const string Root = "Blocks/WaterFields/";
            bool g_templatesVerified = false;

            string Bytes(MemoryBuffer@ buffer) {
                buffer.Seek(0);
                return buffer.ReadString(buffer.GetSize());
            }

            void ValidateIdentityOffsets(MemoryBuffer@ buffer, Json::Value@ offsets) {
                Fields::Require(
                    offsets.Length == 5,
                    "Identity manifest changed."
                );
                for (uint i = 0; i < offsets.Length; i++) {
                    uint64 offset = uint64(offsets[i]);
                    Fields::Require(
                        offset >= 4 && offset <= buffer.GetSize() - 14,
                        "Identity offset is out of range."
                    );
                    for (uint j = 0; j < i; j++) {
                        Fields::Require(
                            offset != uint64(offsets[j]),
                            "Duplicate identity offset."
                        );
                    }
                    buffer.Seek(offset - 4);
                    Fields::Require(
                        buffer.ReadString(18) == "v28_000_Water_Area",
                        "Identity template changed."
                    );
                }
            }

            void ValidateDescription(MemoryBuffer@ buffer, uint offset, const string &in expected) {
                Fields::Require(
                    offset >= 4 && uint64(offset) + 4 + uint(expected.Length) <= buffer.GetSize(),
                    "Description offset is out of range."
                );
                buffer.Seek(offset - 4);
                Fields::Require(
                    buffer.ReadUInt32() == 0x2e00100d &&
                    buffer.ReadUInt32() == uint(expected.Length) &&
                    buffer.ReadString(expected.Length) == expected,
                    "Description template changed."
                );
            }

            void ValidateTemplates(
                MemoryBuffer@ native,
                MemoryBuffer@ wrapper,
                MemoryBuffer@ prefab,
                Json::Value@ manifest
            ) {
                Fields::Require(
                    string(manifest["schema"]) == "water-area-generator-assets-v28" &&
                    string(manifest["stem"]) == "v28_000_Water_Area" &&
                    string(manifest["archetype"]) == "TrackWallWithHoleWater" &&
                    uint(manifest["variantCount"]) == 10 &&
                    uint(manifest["mobilCount"]) == 1 &&
                    uint(manifest["runtimePointers"]) == 0 &&
                    uint(manifest["resourceIndices"]) == 0,
                    "Unsupported water template manifest."
                );
                Fields::Require(
                    native.GetSize() == 9066 && wrapper.GetSize() == 1095 && prefab.GetSize() == 53,
                    "Water template sizes changed."
                );
                ValidateIdentityOffsets(native, manifest["nativeIdentityOffsets"]);
                ValidateIdentityOffsets(wrapper, manifest["wrapperIdentityOffsets"]);
                auto offsets = manifest["waterOffsets"];
                Fields::Require(
                    offsets.Length == 10,
                    "Water transform manifest changed."
                );
                array<float> expected = {139.25f, 234.5f, 361.75f, 0, 8, 8, 8};
                for (uint i = 0; i < offsets.Length; i++) {
                    uint64 offset = uint64(offsets[i]);
                    Fields::Require(
                        offset <= native.GetSize() - 28,
                        "Water transform offset is out of range."
                    );
                    for (uint j = 0; j < i; j++) {
                        Fields::Require(
                            offset != uint64(offsets[j]),
                            "Duplicate water transform offset."
                        );
                    }
                    native.Seek(offset);
                    for (uint j = 0; j < expected.Length; j++) {
                        Fields::Require(
                            native.ReadFloat() == expected[j],
                            "Water transform template changed."
                        );
                    }
                }
                ValidateDescription(native, 2571, "TrackWallWithHoleWater");
                ValidateDescription(wrapper, 424, "No Description");
            }

            void PatchIdentity(MemoryBuffer@ buffer, Json::Value@ offsets, const string &in stem) {
                Fields::Require(
                    stem.Length == 18,
                    "Wrong generated stem length."
                );
                for (uint i = 0; i < offsets.Length; i++) {
                    buffer.Seek(uint64(offsets[i]) - 4);
                    buffer.Write(stem);
                }
            }

            string Metadata(Fields::Field@ field) {
                auto buffer = MemoryBuffer();
                auto origin = field.LocalOrigin();
                buffer.Write(origin.x);
                buffer.Write(origin.y);
                buffer.Write(origin.z);
                buffer.Write(field.size.x);
                buffer.Write(field.size.y);
                buffer.Write(field.size.z);
                buffer.Seek(0);
                string metadata = "WaterFields:1:" + field.stem + ":";
                for (uint i = 0; i < 6; i++) metadata += Text::Format("%08x", buffer.ReadUInt32());
                return metadata;
            }

            string WithDescription(MemoryBuffer@ buffer, uint offset, const string &in metadata) {
                buffer.Seek(offset);
                uint length = buffer.ReadUInt32();
                buffer.Seek(0);
                string prefix = buffer.ReadString(offset);
                buffer.Seek(offset + 4 + length);
                string suffix = buffer.ReadString(buffer.GetSize() - offset - 4 - length);
                auto result = MemoryBuffer();
                result.Write(prefix);
                result.Write(uint(metadata.Length));
                result.Write(metadata);
                result.Write(suffix);
                return Bytes(result);
            }

            string Stem(uint index) {
                const string characters = "0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ";
                Fields::Require(
                    index < 46656,
                    "Water field IDs are exhausted; existing identities cannot be reused."
                );
                return "wf1_" +
                       characters.SubStr(index / 1296, 1) +
                       characters.SubStr((index / 36) % 36, 1) +
                       characters.SubStr(index % 36, 1) +
                       "_Water_Area";
            }

            bool Exists(const string &in path) {
                return IO::FileExists(path) || IO::FolderExists(path);
            }

            bool Taken(const string &in root, const string &in records, const string &in stem) {
                string id = stem.SubStr(4, 3);
                return id == "DRY" ||
                       id == "W08" ||
                       id == "W01" ||
                       id == "REC" ||
                       id == "W80" ||
                       Exists(root + "reservations/" + stem + ".json") ||
                       Exists(records + stem + ".json") ||
                       Exists(root + stem + ".Block.Gbx") ||
                       Exists(root + "Native/" + stem + ".EDClassic.Gbx") ||
                       Exists(root + "Native/" + stem + ".Prefab.Gbx");
            }

            void Reserve(Result@ result, const string &in root, const string &in records) {
                IO::CreateFolder(root + "reservations", true);
                IO::CreateFolder(records, true);
                for (uint i = 0; i < 46656; i++) {
                    string stem = Stem(i);
                    if (Taken(root, records, stem)) continue;
                    _IO::File::WriteNewVerified(root + "reservations/" + stem + ".json", "{\"stem\":\"" + stem + "\"}");
                    result.field.stem = stem;
                    result.assetRoot = root;
                    result.generation = "reserved";
                    result.recordPath = records + stem + ".json";
                    _IO::File::WriteNewVerified(result.recordPath, Json::Write(result.Record()));
                    return;
                }
                throw("Water field IDs are exhausted; existing identities cannot be reused.");
            }

            void Generate(Result@ result, const string &in root, const string &in records) {
                try {
                    Fields::Validate(result.field);
                    auto manifest = Templates::Manifest();
                    auto native = Templates::Read(Templates::Native);
                    auto wrapper = Templates::Read(Templates::Wrapper);
                    auto prefab = Templates::Read(Templates::Prefab);
                    if (!g_templatesVerified) {
                        ValidateTemplates(native, wrapper, prefab, manifest);
                        g_templatesVerified = true;
                    }
                    Reserve(result, root, records);
                    auto field = result.field;
                    PatchIdentity(native, manifest["nativeIdentityOffsets"], field.stem);
                    PatchIdentity(wrapper, manifest["wrapperIdentityOffsets"], field.stem);
                    auto origin = field.LocalOrigin();
                    auto offsets = manifest["waterOffsets"];
                    for (uint i = 0; i < offsets.Length; i++) {
                        native.Seek(uint64(offsets[i]));
                        native.Write(origin.x);
                        native.Write(origin.y);
                        native.Write(origin.z);
                        native.Write(float(0));
                        native.Write(field.size.x);
                        native.Write(field.size.y);
                        native.Write(field.size.z);
                    }
                    string metadata = Metadata(field);
                    string nativeBytes = WithDescription(native, 2571, metadata);
                    string wrapperBytes = WithDescription(wrapper, 424, metadata);
                    string prefabBytes = Bytes(prefab);
                    result.nativeBytes = nativeBytes;
                    result.wrapperBytes = wrapperBytes;
                    result.prefabBytes = prefabBytes;
                    result.Save();
                    IO::CreateFolder(root + "Native", true);
                    _IO::File::WriteNewVerified(root + "Native/" + field.stem + ".Prefab.Gbx", prefabBytes);
                    _IO::File::WriteNewVerified(root + "Native/" + field.stem + ".EDClassic.Gbx", nativeBytes);
                    _IO::File::WriteNewVerified(root + field.stem + ".Block.Gbx", wrapperBytes);
                    result.generation = "verified";
                } catch {
                    result.generation = "failed";
                    result.error = getExceptionInfo();
                }
                try {
                    result.Save();
                } catch {
                    result.receiptError = getExceptionInfo();
                }
            }
        }
    }
}
