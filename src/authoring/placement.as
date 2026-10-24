namespace WaterFields {
    namespace Authoring {
        void VerifyBlockModel(CGameCtnBlockInfo@ model, WaterFields::Fields::Field@ field) {
            Fields::Require(
                model !is null && model.IdName == field.ModelId(),
                "Wrong generated model identity."
            );
            Fields::Require(
                model.AdditionalVariantsGround.Length == 3 && model.AdditionalVariantsAir.Length == 5,
                "Water variant distribution changed."
            );
            array<CGameCtnBlockInfoVariant@> variants = {model.VariantBaseGround, model.VariantBaseAir};
            for (uint i = 0; i < model.AdditionalVariantsGround.Length; i++) {
                variants.InsertLast(model.AdditionalVariantsGround[i]);
            }
            for (uint i = 0; i < model.AdditionalVariantsAir.Length; i++) {
                variants.InsertLast(model.AdditionalVariantsAir[i]);
            }
            for (uint i = 0; i < variants.Length; i++) {
                auto variant = variants[i];
                Fields::Require(
                    variant !is null && variant.BlockUnitInfos.Length == 1 && variant.Mobils00.Length == 1,
                    "Water block graph changed."
                );
                auto mobil = cast<CGameCtnBlockInfoMobil>(variant.Mobils00[0]);
                Fields::Require(
                    mobil !is null &&
                    mobil.SolidFid is null &&
                    mobil.OldSolidAggreg is null &&
                    mobil.Solid2FromBlockItem is null,
                    "Donor solid geometry is still present."
                );
                auto prefabFid = cast<CSystemFidFile>(mobil.PrefabFid);
                Fields::Require(
                    prefabFid !is null,
                    "Empty prefab reference is missing."
                );
                auto prefab = cast<CPlugPrefab>(Fids::Preload(prefabFid));
                Fields::Require(
                    prefab !is null && prefab.Ents.Length == 0,
                    "Water prefab contains donor entities."
                );
            }
        }

        CGameEditorPluginMapMapType@ ReadyEditor() {
            Fields::Require(
                CaptureSession() != 0,
                "Open an advanced editor session before creating water. (Only stadium supported for now)"
            );
            auto editor = cast<CGameCtnEditorFree>(GetApp().Editor);
            Fields::Require(
                editor !is null && editor.PluginMapType !is null,
                "The editor is unavailable."
            );
            return editor.PluginMapType;
        }

        bool AtAnchor(CGameCtnBlock@ block, const int3 &in anchor) {
            return block !is null &&
                   int(block.Coord.x) == anchor.x &&
                   int(block.Coord.y) == anchor.y &&
                   int(block.Coord.z) == anchor.z;
        }

        void ValidateAnchor(CGameEditorPluginMapMapType@ editor, WaterFields::Fields::Field@ field) {
            auto anchor = field.anchor;
            auto size = editor.Map.Size;
            Fields::Require(
                anchor.x >= 0 &&
                anchor.y >= 0 &&
                anchor.z >= 0 &&
                uint(anchor.x) < size.x &&
                uint(anchor.y) < size.y &&
                uint(anchor.z) < size.z,
                "The carrier anchor must be inside this map's grid."
            );
            Fields::ValidateMapBounds(field, size);
            for (uint i = 0; i < editor.ClassicBlocks.Length; i++) {
                Fields::Require(
                    !AtAnchor(editor.ClassicBlocks[i], anchor),
                    "The carrier anchor already contains a classic block."
                );
            }
            for (uint i = 0; i < editor.GhostBlocks.Length; i++) {
                Fields::Require(
                    !AtAnchor(editor.GhostBlocks[i], anchor),
                    "The carrier anchor already contains a ghost block."
                );
            }
        }

        CGameCtnBlock@ FindPlaced(CGameEditorPluginMapMapType@ editor, WaterFields::Fields::Field@ field) {
            for (uint i = 0; i < editor.GhostBlocks.Length; i++) {
                auto block = editor.GhostBlocks[i];
                if (AtAnchor(block, field.anchor) &&
                    block.BlockInfo !is null &&
                    block.BlockInfo.IdName == field.ModelId()
                ) {
                    return block;
                }
            }
            return null;
        }

        void RollBack(Result@ result) {
            try {
                auto editor = ReadyEditor();
                auto block = FindPlaced(editor, result.field);
                if (block !is null) {
                    editor.RemoveGhostBlock(
                        block.BlockInfo,
                        result.field.anchor,
                        CGameEditorPluginMap::ECardinalDirections::North
                    );
                }
                result.placement = FindPlaced(editor, result.field) is null ? "rolled-back" : "residual";
            } catch {
                result.placement = "residual";
                result.error += " Rollback could not be verified: " + getExceptionInfo();
            }
        }

        void Place(Result@ result) {
            bool mutationAttempted = false;
            try {
                Fields::Require(
                    result.generation == "verified",
                    "Generate and verify the assets before placement."
                );
                Fields::Validate(result.field);
                auto editor = ReadyEditor();
                ValidateAnchor(editor, result.field);
                Fields::Require(
                    result.assetRoot == IO::FromUserGameFolder(Assets::assetFolder),
                    "Only installed WaterFields assets can be placed."
                );
                auto field = result.field;
                string nativeBase = result.assetRoot + "Native/" + field.stem;
                Fields::Require(
                    _IO::File::ReadBinary(result.assetRoot + field.stem + ".Block.Gbx") == result.wrapperBytes &&
                    _IO::File::ReadBinary(nativeBase + ".EDClassic.Gbx") == result.nativeBytes &&
                    _IO::File::ReadBinary(nativeBase + ".Prefab.Gbx") == result.prefabBytes,
                    "Generated assets changed before preload."
                );
                auto waterFolder = Fids::GetUserFolder(Assets::assetFolder);
                if (waterFolder is null) {
                    auto blocksFolder = Fids::GetUserFolder("Blocks");
                    Fields::Require(
                        blocksFolder !is null,
                        "The user Blocks folder is unavailable."
                    );
                    Fids::UpdateTree(blocksFolder, false);
                    @waterFolder = Fids::GetUserFolder(Assets::assetFolder);
                }
                Fields::Require(
                    waterFolder !is null,
                    "The WaterFields asset folder is unavailable."
                );
                Fids::UpdateTree(waterFolder);
                string path = Assets::assetFolder + field.stem + ".Block.Gbx";
                auto fid = Fids::GetUser(path.Replace("/", "\\"));
                Fields::Require(
                    fid !is null && fid.ParentFolder !is null,
                    "Generated wrapper lookup failed."
                );
                auto item = cast<CGameItemModel>(Fids::Preload(fid));
                Fields::Require(
                    item !is null,
                    "Generated wrapper did not load."
                );
                auto model = cast<CGameCtnBlockInfo>(item.EntityModel);
                VerifyBlockModel(model, field);
                auto direction = CGameEditorPluginMap::ECardinalDirections::North;
                Fields::Require(
                    editor.CanPlaceGhostBlock(model, field.anchor, direction),
                    "Water cannot be placed at this carrier anchor."
                );
                result.placement = "attempting";
                result.Save();
                mutationAttempted = true;
                bool placed = editor.PlaceGhostBlock(model, field.anchor, direction);
                auto block = FindPlaced(editor, field);
                Fields::Require(
                    placed && block !is null,
                    "Water placement did not complete."
                );
                Fields::Require(
                    block.Dir == CGameCtnBlock::ECardinalDirections::North &&
                    block.BlockInfoVariantIndex < uint(block.IsGround ? 4 : 6),
                    "Placed water has an unsupported direction or variant."
                );
                VerifyBlockModel(block.BlockInfo, field);
                field.variant = block.BlockInfoVariantIndex;
                field.isGround = block.IsGround;
                result.placement = "placed";
            } catch {
                result.error = getExceptionInfo();
                result.placement = "failed";
                if (mutationAttempted) {
                    RollBack(result);
                }
            }
            try {
                result.Save();
            } catch {
                result.receiptError = getExceptionInfo();
            }
        }

        Result@ Create(const vec3 &in minimum, const vec3 &in size, const int3 &in anchor) {
            auto result = Result();
            result.field.minimum = minimum;
            result.field.size = size;
            result.field.anchor = anchor;
            try {
                Fields::Validate(result.field);
                auto editor = ReadyEditor();
                ValidateAnchor(editor, result.field);
                result.mapUid = session.current.mapUid;
                result.mapFileName = session.current.mapFileName;
                string root = IO::FromUserGameFolder(Assets::assetFolder);
                Fields::Require(
                    root != Assets::assetFolder,
                    "Trackmania's user folder is unavailable."
                );
                Assets::Generate(result, root, IO::FromStorageFolder("records/"));
                if (result.generation == "verified") Place(result);
            } catch {
                result.error = getExceptionInfo();
            }
            if (result.placement == "placed" || result.placement == "residual") {
                History::edits.Record({result.field}, true);
            }
            @lastResult = result;
            log::Info(result.Summary(), "WaterFields::Authoring::Create");
            return result;
        }
    }
}
