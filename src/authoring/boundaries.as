namespace WaterFields {
    namespace Authoring {
        namespace Boundaries {
            const string assetFolder = "Items/WaterFieldsBoundaries_v1/";

            string Stem(WaterFields::Fields::Field@ field) {
                return field.stem.SubStr(0, 7) + "_Water_Boundary";
            }

            string Id(WaterFields::Fields::Field@ field) {
                return "WaterFieldsBoundaries_v1\\" + Stem(field) + ".Item.Gbx";
            }

            string Build(WaterFields::Fields::Field@ field) {
                auto bytes = Templates::Read(Templates::templateFolder + "boundary.Item.Gbx");
                IO::FileSource file(Templates::templateFolder + "boundary_manifest.json");
                auto manifest = Json::Parse(file.ReadToEnd());
                Fields::Require(
                    bytes.GetSize() == 4681,
                    "Water boundary template size changed."
                );
                auto identities = manifest["identityOffsets"];
                for (uint i = 0; i < identities.Length; i++) {
                    bytes.Seek(uint(identities[i]) - 4);
                    Fields::Require(
                        bytes.ReadString(22) == "v31_000_Water_Boundary",
                        "Boundary identity changed."
                    );
                    bytes.Seek(uint(identities[i]) - 4);
                    bytes.Write(Stem(field));
                }

                array<float> origin = {139.25f, 234.5f, 361.75f};
                array<float> size = {field.size.x, field.size.y, field.size.z};
                auto coordinates = manifest["coordinates"];
                for (uint i = 0; i < coordinates.Length; i++) {
                    auto coordinate = coordinates[i];
                    uint axis = uint(coordinate["axis"]);
                    uint offset = uint(coordinate["offset"]);
                    float side = float(coordinate["side"]);
                    Fields::Require(
                        axis < 3 && (side == 0 || side == 1),
                        "Invalid boundary coordinate."
                    );
                    bytes.Seek(offset);
                    Fields::Require(
                        bytes.ReadFloat() == origin[axis] + 8 * side,
                        "Boundary vertex changed."
                    );
                    bytes.Seek(offset);
                    bytes.Write(size[axis] * side);
                }
                auto bounds = manifest["boundsOffsets"];
                for (uint i = 0; i < bounds.Length; i++) {
                    bytes.Seek(uint(bounds[i]));
                    for (uint pass = 0; pass < 2; pass++) {
                        for (uint axis = 0; axis < 3; axis++) bytes.Write(size[axis] / 2);
                    }
                }
                return Assets::Bytes(bytes);
            }

            void Generate(Result@ result) {
                result.boundaryBytes = Build(result.field);
                string folder = IO::FromUserGameFolder(assetFolder);
                Fields::Require(
                    folder != assetFolder,
                    "Trackmania's item folder is unavailable."
                );
                IO::CreateFolder(folder, true);
                _IO::File::WriteNewVerified(folder + Stem(result.field) + ".Item.Gbx", result.boundaryBytes);
            }

            bool Matches(CGameCtnAnchoredObject@ item, WaterFields::Fields::Field@ field) {
                return item !is null &&
                       item.ItemModel !is null &&
                       item.ItemModel.IdName.Replace("/", "\\") == Id(field) &&
                       (item.AbsolutePositionInMap - field.minimum).Length() < 0.01f &&
                       item.Scale == 1 &&
                       item.Yaw == 0 &&
                       item.Pitch == 0 &&
                       item.Roll == 0;
            }

            uint Count(WaterFields::Fields::Field@ field, bool exact) {
                auto map = ReadyEditor().Map;
                uint count = 0;
                for (uint i = 0; i < map.AnchoredObjects.Length; i++) {
                    auto item = map.AnchoredObjects[i];
                    if (item.ItemModel is null || item.ItemModel.IdName.Replace("/", "\\") != Id(field)) continue;
                    if (!exact || Matches(item, field)) count++;
                }
                return count;
            }

            CGameCtnAnchoredObject@ Find(WaterFields::Fields::Field@ field) {
                auto map = ReadyEditor().Map;
                for (uint i = 0; i < map.AnchoredObjects.Length; i++) {
                    if (Matches(map.AnchoredObjects[i], field)) return map.AnchoredObjects[i];
                }
                return null;
            }

            void VerifyModel(CGameItemModel@ model, WaterFields::Fields::Field@ field) {
                Fields::Require(
                    model !is null,
                    "The water boundary file did not load as an item model."
                );
                Fields::Require(
                    model.IdName.Replace("/", "\\") == Id(field),
                    "Wrong boundary model: expected '" + Id(field) + "', loaded '" + model.IdName + "'."
                );
                auto entity = cast<CGameCommonItemEntityModel>(model.EntityModel);
                auto object = entity is null ? null : cast<CPlugStaticObjectModel>(entity.StaticObject);
                Fields::Require(
                    entity !is null &&
                    entity.PhyModel is null &&
                    entity.TriggerShape is null &&
                    object !is null &&
                    object.Mesh !is null &&
                    object.Shape is null,
                    "The water boundary must have a mesh and no collision."
                );
            }

            CGameItemModel@ Load(WaterFields::Fields::Field@ field) {
                auto placed = Find(field);
                if (placed !is null) {
                    VerifyModel(placed.ItemModel, field);
                    return placed.ItemModel;
                }
                string path = "Items/" + Id(field).Replace("\\", "/");
                auto fid = Fids::GetFake("MemoryTemp/CurrentMap_EmbeddedFiles/ContentLoaded/" + path);
                CGameItemModel@ model;
                if (fid !is null) @model = cast<CGameItemModel>(Fids::Preload(fid));

                if (model is null) {
                    Fields::Require(
                        _IO::File::ReadBinary(IO::FromUserGameFolder(path)) == Build(field),
                        "The water boundary file is missing or changed."
                    );
                    auto folder = Fids::GetUserFolder(assetFolder);
                    if (folder is null) {
                        auto items = Fids::GetUserFolder("Items");
                        Fields::Require(
                            items !is null,
                            "The user Items folder is unavailable."
                        );
                        Fids::UpdateTree(items, false);
                        @folder = Fids::GetUserFolder(assetFolder);
                    }
                    Fields::Require(
                        folder !is null,
                        "The WaterFields item folder is unavailable."
                    );
                    Fids::UpdateTree(folder);
                    @fid = Fids::GetUser(path.Replace("/", "\\"));
                    Fields::Require(
                        fid !is null,
                        "The water boundary could not be found."
                    );
                    @model = cast<CGameItemModel>(Fids::Preload(fid));
                }
                VerifyModel(model, field);
                return model;
            }

            void Change(WaterFields::Fields::Field@ field, CGameItemModel@ model, bool add) {
                uint count = Count(field, true);
                Fields::Require(
                    count <= 1,
                    "Duplicate boundary items: remove the extra copy before editing water."
                );
                if ((count == 1) == add) return;
                if (add) {
                    auto item =::Editor::MakeItemSpec(model, field.minimum, vec3(0));
                    ::Editor::PlaceItems({item}, false);
                } else {
                    ::Editor::DeleteItems({Find(field)}, false);
                }
                Fields::Require(
                    (Count(field, true) == 1) == add,
                    "The water boundary did not change as expected."
                );
            }
        }
    }
}
