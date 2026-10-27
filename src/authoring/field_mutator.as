namespace WaterFields {
    namespace Authoring {
        class NativeFieldMutator : FieldMutator {
            uint64 session = CaptureSession();
            array<CGameCtnBlockInfo@> models;
            array<CGameItemModel@> boundaryModels;

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

            CGameItemModel@ BoundaryModel(WaterFields::Fields::Field@ field) {
                for (uint i = 0; i < boundaryModels.Length; i++) {
                    if (boundaryModels[i].IdName.Replace("/", "\\") == Boundaries::Id(field)) return boundaryModels[i];
                }
                auto model = Boundaries::Load(field);
                boundaryModels.InsertLast(model);
                return model;
            }

            bool CarrierExists(WaterFields::Fields::Field@ field) {
                auto block = FindPlaced(Editor(), field);
                if (block is null) return false;
                Fields::Require(
                    SameField(ReadField(block), field),
                    "The water field no longer matches its history."
                );
                return true;
            }

            bool Exists(WaterFields::Fields::Field@ field) {
                bool water = CarrierExists(field);
                if (!field.boundary) return water;
                uint count = Boundaries::Count(field, true);
                Fields::Require(
                    count <= 1 && water == (count == 1),
                    "Water pair is incomplete; keep it in history for repair."
                );
                return water;
            }

            void Preflight(WaterFields::Fields::Field@ field, bool add) {
                Fields::Validate(field);
                auto editor = Editor();
                auto model = Model(field);
                Fields::ValidateMapBounds(field, editor.Map.Size);
                if (field.boundary) {
                    BoundaryModel(field);
                    uint exact = Boundaries::Count(field, true);
                    Fields::Require(
                        exact <= 1,
                        "Duplicate boundary items: remove the extra copy before editing water."
                    );
                    Fields::Require(
                        Boundaries::Count(field, false) == exact,
                        "A boundary was moved, rotated or copied. Undo that native edit before editing its water."
                    );
                    if (CarrierExists(field)) {
                        Fields::Require(
                            !add || exact == 0,
                            "This water pair was already restored outside water history."
                        );
                        return;
                    }
                    if (!add && exact == 1) return;
                }
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
                if (!field.boundary) {
                    ChangeCarrier(field, add);
                    return;
                }
                auto boundary = BoundaryModel(field);
                bool hadWater = CarrierExists(field);
                bool hadBoundary = Boundaries::Count(field, true) == 1;
                try {
                    if (hadWater != add) ChangeCarrier(field, add);
                    Boundaries::Change(field, boundary, add);
                    Fields::Require(
                        Exists(field) == add,
                        "Water pair verification failed."
                    );
                } catch {
                    string error = getExceptionInfo();
                    try {
                        Boundaries::Change(field, boundary, hadBoundary);
                    } catch {
                        error += " Boundary rollback: " + getExceptionInfo();
                    }
                    try {
                        if (CarrierExists(field) != hadWater) ChangeCarrier(field, hadWater);
                    } catch {
                        error += " Water rollback: " + getExceptionInfo();
                    }
                    throw(error);
                }
            }

            void ChangeCarrier(WaterFields::Fields::Field@ field, bool add) {
                auto editor = Editor();
                auto model = Model(field);
                auto direction = CGameEditorPluginMap::ECardinalDirections::North;
                if (!add) {
                    editor.RemoveGhostBlock(model, field.anchor, direction);
                    Fields::Require(
                        !CarrierExists(field),
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
