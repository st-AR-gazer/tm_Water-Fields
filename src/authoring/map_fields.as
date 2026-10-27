namespace WaterFields {
    namespace Authoring {
        WaterFields::Fields::Field@ ReadField(CGameCtnBlock@ block) {
            if (block is null ||
                block.BlockInfo is null ||
                block.Dir != CGameCtnBlock::ECardinalDirections::North
            ) {
                return null;
            }
            string id = block.BlockInfo.IdName;
            if (id.Length != 40 ||
                !id.StartsWith("wf1_") ||
                !id.EndsWith("_Water_Area.Block.Gbx_CustomBlock")
            ) {
                return null;
            }

            auto field = WaterFields::Fields::Field();
            field.stem = id.SubStr(0, 18);
            field.anchor = int3(block.Coord.x, block.Coord.y, block.Coord.z);
            field.variant = block.BlockInfoVariantIndex;
            field.isGround = block.IsGround;
            string description = block.BlockInfo.Description;
            field.boundary = description.StartsWith("WaterFields:2:");
            string prefix = "WaterFields:" + (field.boundary ? "2:" : "1:") + field.stem + ":";
            Fields::Require(
                description.StartsWith(prefix) && description.Length == prefix.Length + 48,
                "Water field metadata is missing or unsupported."
            );
            auto bytes = MemoryBuffer();

            for (uint i = 0; i < 6; i++) {
                string hex = description.SubStr(prefix.Length + i * 8, 8);
                uint bits = Text::ParseUInt(hex, 16);
                Fields::Require(
                    Text::Format("%08x", bits) == hex,
                    "Invalid water field metadata."
                );
                bytes.Write(bits);
            }
            bytes.Seek(0);
            array<float> values;
            for (uint i = 0; i < 6; i++) values.InsertLast(bytes.ReadFloat());
            vec3 local(values[0], values[1], values[2]);
            field.size = vec3(values[3], values[4], values[5]);
            field.minimum = vec3(
                float(field.anchor.x) * 32,
                (float(field.anchor.y) - 8) * 8,
                float(field.anchor.z) * 32
            ) +
                            local;
            Fields::Validate(field);
            return field;
        }

        bool SameField(WaterFields::Fields::Field@ a, WaterFields::Fields::Field@ b) {
            return a !is null &&
                   b !is null &&
                   a.stem == b.stem &&
                   a.anchor == b.anchor &&
                   a.minimum == b.minimum &&
                   a.size == b.size &&
                   a.variant == b.variant &&
                   a.isGround == b.isGround &&
                   a.boundary == b.boundary;
        }

        bool SameFields(
            const array<WaterFields::Fields::Field@> &in a,
            const array<WaterFields::Fields::Field@> &in b
        ) {
            if (a.Length != b.Length) return false;
            array<bool> used(b.Length, false);
            for (uint i = 0; i < a.Length; i++) {
                bool found = false;
                for (uint j = 0; j < b.Length; j++) {
                    if (!used[j] && SameField(a[i], b[j])) {
                        used[j] = true;
                        found = true;
                        break;
                    }
                }
                if (!found) return false;
            }
            return true;
        }

        uint64 AnchorIndex(const nat3 &in coord, const nat3 &in size) {
            return(uint64(coord.y - 1) * (size.z - 2) + coord.z - 1) * (size.x - 2) + coord.x - 1;
        }

        bool UsableAnchor(const nat3 &in coord, const nat3 &in size) {
            return coord.x > 0 &&
                   coord.x < size.x - 1 &&
                   coord.y > 0 &&
                   coord.y < size.y &&
                   coord.z > 0 &&
                   coord.z < size.z - 1;
        }

        array<nat3> GetTerrainCells(CGameEditorPluginMapMapType@ editor) {
            array<nat3> cells;
            for (uint i = 0; i < editor.TerrainBlocks.Length; i++) {
                auto block = editor.TerrainBlocks[i];
                cells.InsertLast(block.Coord);
                for (uint j = 0; j < block.BlockUnits.Length; j++) {
                    auto offset = block.BlockUnits[j].AbsoluteOffset;
                    cells.InsertLast(nat3(
                        block.Coord.x + offset.x,
                        block.Coord.y + offset.y,
                        block.Coord.z + offset.z
                    ));
                }
            }
            return cells;
        }

        int3 FreeAnchor(CGameEditorPluginMapMapType@ editor, const vec3 &in minimum) {
            auto size = editor.Map.Size;
            Fields::Require(
                size.x > 2 && size.y > 1 && size.z > 2,
                "The map grid has no room for a carrier."
            );
            nat3 preferred(
                uint(Math::Clamp(Math::Floor(minimum.x / 32), 1.0f, float(size.x - 2))),
                uint(Math::Clamp(Math::Floor(minimum.y / 8) + 8, 1.0f, float(size.y - 1))),
                uint(Math::Clamp(Math::Floor(minimum.z / 32), 1.0f, float(size.z - 2)))
            );
            array<uint64> occupied;
            auto terrain = GetTerrainCells(editor);
            for (uint i = 0; i < terrain.Length; i++) {
                if (UsableAnchor(terrain[i], size)) occupied.InsertLast(AnchorIndex(terrain[i], size));
            }
            for (uint i = 0; i < editor.ClassicBlocks.Length; i++) {
                auto coord = editor.ClassicBlocks[i].Coord;
                if (UsableAnchor(coord, size)) occupied.InsertLast(AnchorIndex(coord, size));
            }
            for (uint i = 0; i < editor.GhostBlocks.Length; i++) {
                auto coord = editor.GhostBlocks[i].Coord;
                if (UsableAnchor(coord, size)) occupied.InsertLast(AnchorIndex(coord, size));
            }

            uint64 index = AnchorIndex(preferred, size);
            if (occupied.Find(index) < 0) return int3(preferred.x, preferred.y, preferred.z);

            occupied.SortAsc();
            uint64 end = uint64(size.x - 2) * (size.y - 1) * (size.z - 2);
            for (uint pass = 0; pass < 2; pass++) {
                for (uint i = 0; i < occupied.Length; i++) {
                    if (occupied[i] > index) break;
                    if (occupied[i] == index) index++;
                }
                if (index < end) {
                    return int3(
                        1 + index % (size.x - 2),
                        1 + index / (uint64(size.x - 2) * (size.z - 2)),
                        1 + (index / (size.x - 2)) % (size.z - 2)
                    );
                }
                index = 0;
            }
            throw("No free carrier anchor remains in this map.");
            return int3();
        }
    }
}
