namespace WaterFields {
    namespace Authoring {
        class NativeFieldMutator : FieldMutator {
            uint64 session = CaptureSession();
            array<CGameCtnBlockInfo@> models;

            CGameEditorPluginMapMapType@ Editor() {
                Fields::Require(
                    IsSessionCurrent(session),
                    "The editor session changed."
                );
                return ReadyEditor();
            }

            CGameCtnBlockInfo@ Model(WaterFields::Fields::Field@ field) {
                auto editor = Editor();
                for (uint i = 0; i < models.Length; i++) {
                    if (models[i].IdName == field.ModelId()) return models[i];
                }
                auto placed = FindPlaced(editor, field);
                CGameCtnBlockInfo@ model;
                if (placed !is null) @model = placed.BlockInfo;
                if (model is null)   @model = editor.GetBlockModelFromName(field.ModelId());
                if (model is null) {
                    auto fid = Fids::GetUser((Assets::assetFolder + field.stem + ".Block.Gbx").Replace("/", "\\"));
                    auto item = fid is null ? null : cast<CGameItemModel>(Fids::Preload(fid));
                    if (item !is null) @model = cast<CGameCtnBlockInfo>(item.EntityModel);
                }
                Fields::Require(
                    model !is null,
                    "The water model is unavailable. History was kept; no changes were made."
                );
                VerifyBlockModel(model, field);
                Fields::Require(
                    model.Description == Assets::Metadata(field),
                    "The water model's bounds changed."
                );
                models.InsertLast(model);
                return model;
            }

            bool Exists(WaterFields::Fields::Field@ field) {
                auto block = FindPlaced(Editor(), field);
                if (block is null) return false;
                Fields::Require(
                    SameField(ReadField(block), field),
                    "The water field no longer matches its history."
                );
                return true;
            }

            void Preflight(WaterFields::Fields::Field@ field, bool add) {
                Fields::Validate(field);
                auto editor = Editor();
                auto model = Model(field);
                Fields::ValidateMapBounds(field, editor.Map.Size);
                if (add) {
                    ValidateAnchor(editor, field);
                    Fields::Require(
                        editor.CanPlaceGhostBlock(
                            model,
                            field.anchor,
                            CGameEditorPluginMap::ECardinalDirections::North
                        ),
                        "A water field cannot be restored at its original anchor."
                    );
                } else {
                    Fields::Require(
                        SameField(ReadField(FindPlaced(editor, field)), field),
                        "A water field changed outside this edit. History was kept; no changes were made."
                    );
                }
            }

            void Change(WaterFields::Fields::Field@ field, bool add) {
                auto editor = Editor();
                auto model = Model(field);
                auto direction = CGameEditorPluginMap::ECardinalDirections::North;
                if (!add) {
                    editor.RemoveGhostBlock(model, field.anchor, direction);
                    Fields::Require(
                        !Exists(field),
                        "A water field could not be removed."
                    );
                    return;
                }
                ValidateAnchor(editor, field);
                auto nativeEditor = cast<CGameCtnEditorFree>(GetApp().Editor);
                bool ground = nativeEditor.GhostBlockForcedGroundElseAir;
                uint variant = nativeEditor.GhostBlockForcedVariantIndex;
                string error;
                try {
                    nativeEditor.GhostBlockForcedGroundElseAir = field.isGround;
                    nativeEditor.GhostBlockForcedVariantIndex = field.variant;
                    Fields::Require(
                        editor.PlaceGhostBlock(model, field.anchor, direction),
                        "Water restoration failed."
                    );
                    Fields::Require(
                        SameField(ReadField(FindPlaced(editor, field)), field),
                        "The restored water field differs from the original."
                    );
                } catch {
                    error = getExceptionInfo();
                }
                nativeEditor.GhostBlockForcedGroundElseAir = ground;
                nativeEditor.GhostBlockForcedVariantIndex = variant;
                if (error.Length > 0) {
                    auto placed = FindPlaced(editor, field);
                    if (placed !is null && !SameField(ReadField(placed), field)) {
                        editor.RemoveGhostBlock(model, field.anchor, direction);
                        error += FindPlaced(editor, field) is null ?
                            " The unexpected placement was removed." :
                            " An unexpected placement remains; keep this map open for recovery.";
                    }
                }
                Fields::Require(
                    error.Length == 0,
                    error
                );
            }
        }
    }
}
