namespace WaterFields {
    namespace Authoring {
        namespace Input {
            enum Tool {
                Off, Draw, Erase
            }
            Tool activeTool = Tool::Off;
            bool windowOpen = false;
            bool dragging = false;
            bool leftOwned = false;
            bool rightOwned = false;
            bool cameraNavigating = false;
            bool hasHit = false;
            bool cursorOwned = false;
            bool boxOwned = false;
            bool previousArrow;
            bool previousQuads;
            bool previousLines;
            bool previousPrisms;
            bool inputOwned = false;
            bool previousInputs;
            bool escapeDown = false;
            bool altDown = false;
            bool ctrlDown = false;
            bool shiftDown = false;
            VirtualKey historyKey = VirtualKey::None;
            uint64 inputReleaseAt;
            uint64 session;
            string mapUid;
            string statusMessage;
            string scanMessage;
            vec2 mousePosition;
            vec3 dragStart;
            float planeY;
            float cubeScale;
            int heightLayers = 1;
            WaterFields::Fields::Field@ preview = WaterFields::Fields::Field();
            WaterFields::Fields::Field@ hoveredField;
            WaterFields::Fields::Field@ eraseTarget;
            array<WaterFields::Fields::Field@> placedFields;
            WaterFields::Fields::Regions regions;
            array<WaterFields::Fields::Field@> eraseRegion;
            uint64 nextScanAt;
            CGameEditorPluginMap::EditMode previousEdit;
            CGameEditorPluginMap::EPlaceMode previousPlace;

            CGameCtnEditorFree@ Editor() {
                auto editor = cast<CGameCtnEditorFree>(GetApp().Editor);
                if (editor is null ||
                    editor.PluginMapType is null ||
                    editor.PluginMapType.Map is null
                ) return null;
                return editor;
            }

            bool SameMap(CGameCtnEditorFree@ editor) {
                return editor !is null &&
                       editor.PluginMapType.Map.MapInfo !is null &&
                       editor.PluginMapType.Map.MapInfo.MapUid == mapUid;
            }

            void Cancel() {
                dragging = false;
                @eraseTarget = null;
                eraseRegion.Resize(0);
                hasHit = false;
            }

            void RestoreCursor() {
                auto editor = Editor();
                if (cursorOwned && SameMap(editor)) {
                    auto pluginMap = editor.PluginMapType;
                    if (pluginMap.HideAlwaysCursorDirectionalArrow) {
                        pluginMap.HideAlwaysCursorDirectionalArrow = previousArrow;
                    }
                    if (boxOwned &&
                        editor.Cursor !is null &&
                        editor.Cursor.CursorBox !is null
                    ) {
                        auto box = editor.Cursor.CursorBox;
                        if (!box.IsShowQuads)  box.IsShowQuads  = previousQuads;
                        if (!box.IsShowLines)  box.IsShowLines  = previousLines;
                        if (!box.IsShowPrisms) box.IsShowPrisms = previousPrisms;
                    }
                }
                cursorOwned = false;
                boxOwned = false;
            }

            void ReleaseInputs() {
                auto editor = Editor();
                if (inputOwned &&
                    SameMap(editor) &&
                    editor.PluginMapType.EnableEditorInputsCustomProcessing
                ) {
                    editor.PluginMapType.EnableEditorInputsCustomProcessing = previousInputs;
                }
                inputOwned = false;
                escapeDown = false;
            }

            void GuardKey() {
                auto editor = Editor();
                if (SameMap(editor) && !inputOwned) {
                    previousInputs = editor.PluginMapType.EnableEditorInputsCustomProcessing;
                    editor.PluginMapType.EnableEditorInputsCustomProcessing = true;
                    inputOwned = true;
                }
                inputReleaseAt = Time::Now + 80;
            }

            void Stop() {
                Cancel();
                RestoreCursor();
                ReleaseInputs();
                auto editor = Editor();
                if (activeTool != Tool::Off &&
                    SameMap(editor) &&
                    editor.PluginMapType.PlaceMode == CGameEditorPluginMap::EPlaceMode::CustomSelection
                ) {
                    editor.PluginMapType.PlaceMode = previousPlace;
                    if (editor.PluginMapType.EditMode == CGameEditorPluginMap::EditMode::Place) {
                        editor.PluginMapType.EditMode = previousEdit;
                    }
                }
                activeTool = Tool::Off;
                leftOwned = false;
                rightOwned = false;
                cameraNavigating = false;
                altDown = false;
                ctrlDown = false;
                shiftDown = false;
                historyKey = VirtualKey::None;
                @hoveredField = null;
            }

            void Select(Tool tool) {
                if (tool == Tool::Off) {
                    Stop();
                    return;
                }
                try {
                    auto editor = ReadyEditor();
                    if (activeTool == Tool::Off) {
                        previousEdit = editor.EditMode;
                        previousPlace = editor.PlaceMode;
                        mapUid = Authoring::session.current.mapUid;
                    }
                    session = CaptureSession();
                    editor.EditMode = CGameEditorPluginMap::EditMode::Place;
                    editor.PlaceMode = CGameEditorPluginMap::EPlaceMode::CustomSelection;
                    activeTool = tool;
                    Cancel();
                    nextScanAt = 0;
                    statusMessage = "";
                } catch {
                    statusMessage = getExceptionInfo();
                    Stop();
                }
            }

            bool CameraInput(CGameCtnEditorFree@ editor) {
                return altDown ||
                       (editor !is null && editor.PluginMapType.EditMode == CGameEditorPluginMap::EditMode::FreeLook);
            }

            void Failed(const string &in message) {
                statusMessage = message;
                Stop();
            }

            bool NativeUiFocused(CControlBase@ control, uint depth = 0) {
                if (control is null ||
                    depth > 16 ||
                    !control.IsVisible ||
                    control.IsHiddenExternal ||
                    control.IsHiddenInternal
                ) {
                    return false;
                }
                if (cast<CControlButton>(control) !is null || cast<CControlEntry>(control) !is null) {
                    if (control.IsFocused) return true;
                }
                auto container = cast<CControlContainer>(control);
                if (container is null) return false;
                for (uint i = 0; i < container.Childs.Length; i++) {
                    if (NativeUiFocused(container.Childs[i], depth + 1)) return true;
                }
                return false;
            }

            bool WorldInput(CGameCtnEditorFree@ editor) {
                auto app = cast<CTrackMania>(GetApp());
                if (app !is null && app.ManiaPlanetScriptAPI !is null) {
                    auto api = app.ManiaPlanetScriptAPI;
                    if (api.ActiveContext_ClassicDialogDisplayed ||
                        api.ActiveContext_InGameMenuDisplayed ||
                        api.ActiveContext_ManialinkBrowserDisplayed
                    ) {
                        return false;
                    }
                }
                return editor !is null &&
                       editor.EditorInterface !is null &&
                       GetApp().InputPort.IsFocused &&
                       !UI::WantCaptureMouse() &&
                       !UI::WantCaptureKeyboard() &&
                       mousePosition.x >= 0 &&
                       mousePosition.y >= 0 &&
                       mousePosition.x < Display::GetWidth() &&
                       mousePosition.y < Display::GetHeight() &&
                       !NativeUiFocused(editor.EditorInterface.InterfaceRoot);
            }

            bool MouseRay(const vec2 &in mouse, vec3 &out origin, vec3 &out direction) {
                if (Camera::GetCurrent() is null ||
                    Display::GetWidth() < 2 ||
                    Display::GetHeight() < 2
                ) return false;
                vec2 uv = mouse / (vec2(Display::GetWidth(), Display::GetHeight()) - vec2(1)) * 2 - vec2(1);
                auto point = mat4::Inverse(Camera::GetProjectionMatrix()) * vec3(uv, 0.01f);
                if (Math::Abs(point.w) < 0.000001f) return false;
                origin = Camera::GetCurrentPosition();
                direction = (origin - point.xyz / point.w).Normalized();
                return direction.LengthSquared() > 0.5f;
            }

            void Scan() {
                array<WaterFields::Fields::Field@> fields;
                scanMessage = "";
                auto editor = ReadyEditor();
                uint skipped = 0;
                for (uint i = 0; i < editor.GhostBlocks.Length; i++) {
                    try {
                        auto field = ReadField(editor.GhostBlocks[i]);
                        if (field !is null) fields.InsertLast(field);
                    } catch {
                        skipped++;
                    }
                }
                if (skipped > 0) scanMessage = "Skipped " + skipped + " fields with unreadable bounds.";
                bool changed = !SameFields(fields, placedFields);
                if (changed || regions.membership.Length != fields.Length) {
                    placedFields = fields;
                    regions.Rebuild(fields);
                }
                nextScanAt = Time::Now + 500;
            }

            array<WaterFields::Fields::Field@> Region(WaterFields::Fields::Field@ field) {
                array<WaterFields::Fields::Field@> members;
                for (uint i = 0; i < placedFields.Length; i++) {
                    if (!SameField(field, placedFields[i])) continue;
                    for (uint j = 0; j < placedFields.Length; j++) {
                        if (regions.membership[j] == regions.membership[i]) members.InsertLast(placedFields[j]);
                    }
                    break;
                }
                return members;
            }

            void ApplyHistory(bool redo) {
                Cancel();
                try {
                    ReadyEditor();
                    auto result = History::edits.Apply(redo, NativeFieldMutator());
                    statusMessage = result.success ?
                        (redo ? "Water edit redone." : "Water edit undone.") :
                        result.error;
                    Scan();
                } catch {
                    statusMessage = getExceptionInfo();
                }
            }

            void Pick() {
                hasHit = false;
                @hoveredField = null;
                auto editor = Editor();
                if (activeTool == Tool::Off ||
                    !WorldInput(editor) ||
                    CameraInput(editor)
                ) return;
                vec3 origin, direction, hit;
                if (!MouseRay(mousePosition, origin, direction)) return;
                if (activeTool == Tool::Erase) {
                    float best = 100000;
                    for (uint i = 0; i < placedFields.Length; i++) {
                        float distance;
                        auto field = placedFields[i];
                        if (Fields::BoxHit(origin, direction, field.minimum, field.size, distance) && distance < best) {
                            best = distance;
                            @hoveredField = field;
                        }
                    }
                    return;
                }
                if (!dragging) {
                    planeY = editor.PluginMapType.CameraTargetPosition.y;
                    cubeScale = App::S_CubeScale;
                    heightLayers = 1;
                }
                if (!Fields::PlaneHit(origin, direction, planeY, hit)) return;
                hit = vec3(Fields::CellMinimum(hit.x, cubeScale), planeY, Fields::CellMinimum(hit.z, cubeScale));
                if (!dragging) dragStart = hit;
                Fields::DrawBounds(dragStart, hit, cubeScale, heightLayers, preview.minimum, preview.size);
                hasHit = true;
            }

            void Update() {
                if (inputOwned &&
                    Time::Now >= inputReleaseAt &&
                    !escapeDown &&
                    historyKey == VirtualKey::None
                ) {
                    ReleaseInputs();
                }
                auto snapshot = ReadSnapshot();
                if (snapshot.state != SessionState::Ready || !GetApp().InputPort.IsFocused) {
                    Stop();
                    placedFields.Resize(0);
                    regions.Rebuild(placedFields);
                    return;
                }
                if (snapshot.mapUid != mapUid) {
                    Stop();
                    placedFields.Resize(0);
                    regions.Rebuild(placedFields);
                    statusMessage = "";
                    nextScanAt = 0;
                    mapUid = snapshot.mapUid;
                }
                auto editor = Editor();
                if (activeTool != Tool::Off && !IsSessionCurrent(session)) Stop();
                if (activeTool == Tool::Off && !App::S_PreviewOutsideMode) return;
                if (Time::Now >= nextScanAt) Scan();
                if (activeTool == Tool::Off) return;
                bool navigating = CameraInput(editor);
                if (navigating) {
                    Cancel();
                    ReleaseInputs();
                    RestoreCursor();
                    leftOwned = false;
                    rightOwned = false;
                } else {
                    auto pluginMap = editor.PluginMapType;
                    if (cameraNavigating && pluginMap.EditMode == CGameEditorPluginMap::EditMode::Place) {
                        pluginMap.PlaceMode = CGameEditorPluginMap::EPlaceMode::CustomSelection;
                    }
                    if (pluginMap.EditMode != CGameEditorPluginMap::EditMode::Place ||
                        pluginMap.PlaceMode != CGameEditorPluginMap::EPlaceMode::CustomSelection) {
                        Stop();
                        return;
                    }
                    if (!cursorOwned) {
                        previousArrow = pluginMap.HideAlwaysCursorDirectionalArrow;
                        cursorOwned = true;
                        pluginMap.HideAlwaysCursorDirectionalArrow = true;
                        if (editor.Cursor !is null && editor.Cursor.CursorBox !is null) {
                            auto box = editor.Cursor.CursorBox;
                            previousQuads = box.IsShowQuads;
                            previousLines = box.IsShowLines;
                            previousPrisms = box.IsShowPrisms;
                            boxOwned = true;
                            box.IsShowQuads = false;
                            box.IsShowLines = false;
                            box.IsShowPrisms = false;
                        }
                    }
                }
                cameraNavigating = navigating;
                Pick();
            }

            UI::InputBlocking MouseButton(bool down, int button, int x, int y) {
                mousePosition = vec2(x, y);
                Update();
                if (activeTool == Tool::Off || CameraInput(Editor())) return UI::InputBlocking::DoNothing;
                if (button == 1 &&
                    !down &&
                    rightOwned
                ) {
                    rightOwned = false;
                    return UI::InputBlocking::Block;
                }
                if (button == 1 &&
                    down &&
                    leftOwned
                ) {
                    Cancel();
                    rightOwned = true;
                    return UI::InputBlocking::Block;
                }
                if (button != 0) return UI::InputBlocking::DoNothing;
                if (!down && leftOwned) {
                    leftOwned = false;
                    Pick();
                    bool draw = dragging && hasHit;
                    auto erased = eraseTarget;
                    array<WaterFields::Fields::Field@> members = eraseRegion;
                    Cancel();
                    try {
                        Fields::Require(
                            IsSessionCurrent(session),
                            "The editor session changed."
                        );
                        if (draw) {
                            auto anchor = FreeAnchor(ReadyEditor(), preview.minimum);
                            auto result = Create(preview.minimum, preview.size, anchor);
                            statusMessage = result.Summary();
                        } else if (SameField(erased, hoveredField)) {
                            Scan();
                            Fields::Require(
                                SameFields(members, Region(erased)),
                                "The region changed. Select it again."
                            );
                            auto result = ApplyBatch(members, false, NativeFieldMutator());
                            History::edits.Record(result.changed, false);
                            statusMessage = result.success ? "Removed water region. Undo restores it." : result.error;
                        }
                        Scan();
                    } catch {
                        statusMessage = getExceptionInfo();
                    }
                    return UI::InputBlocking::Block;
                }
                if (!down) return UI::InputBlocking::DoNothing;
                if (!WorldInput(Editor())) {
                    if (UI::WantCaptureMouse() || UI::WantCaptureKeyboard()) {
                        Cancel();
                    } else {
                        Stop();
                    }
                    return UI::InputBlocking::DoNothing;
                }
                leftOwned = true;
                Scan();
                Pick();
                if (activeTool == Tool::Draw && hasHit) dragging = true;
                if (activeTool == Tool::Erase) {
                    @eraseTarget = hoveredField;
                    eraseRegion = Region(hoveredField);
                }
                return UI::InputBlocking::Block;
            }

            UI::InputBlocking MouseWheel(int delta) {
                Update();
                if (!dragging ||
                    !leftOwned ||
                    activeTool != Tool::Draw ||
                    !WorldInput(Editor()) ||
                    CameraInput(Editor())
                ) {
                    return UI::InputBlocking::DoNothing;
                }
                int layers = Math::Abs(delta) >= 120 ? delta / 120 : delta;
                heightLayers = Math::Clamp(heightLayers + layers, 1, int(Math::Floor(Fields::maxHeight / cubeScale)));
                Pick();
                return UI::InputBlocking::Block;
            }

            UI::InputBlocking Key(bool down, VirtualKey key) {
                bool alt = key == VirtualKey::Menu || key == VirtualKey::LMenu || key == VirtualKey::RMenu;
                if (alt) altDown = down;
                if (key == VirtualKey::Control ||
                    key == VirtualKey::LControl ||
                    key == VirtualKey::RControl
                ) {
                    ctrlDown = down;
                }
                if (key == VirtualKey::Shift ||
                    key == VirtualKey::LShift ||
                    key == VirtualKey::RShift
                ) {
                    shiftDown = down;
                }
                if (key == historyKey && historyKey != VirtualKey::None) {
                    if (!down) {
                        historyKey = VirtualKey::None;
                        inputReleaseAt = Time::Now + 80;
                    }
                    return UI::InputBlocking::Block;
                }
                if (key == VirtualKey::Escape && inputOwned) {
                    escapeDown = down;
                    if (!down) inputReleaseAt = Time::Now + 80;
                    return UI::InputBlocking::Block;
                }
                if (activeTool == Tool::Off) return UI::InputBlocking::DoNothing;
                if (down && alt) {
                    Cancel();
                    ReleaseInputs();
                    return UI::InputBlocking::DoNothing;
                }
                if (UI::WantCaptureKeyboard() ||
                    (!leftOwned && !WorldInput(Editor()))) return UI::InputBlocking::DoNothing;
                if (down &&
                    ctrlDown &&
                    !altDown &&
                    (key == VirtualKey::Z || key == VirtualKey::Y)
                ) {
                    historyKey = key;
                    GuardKey();
                    ApplyHistory(key == VirtualKey::Y || shiftDown);
                    return UI::InputBlocking::Block;
                }
                if (key != VirtualKey::Escape) {
                    if (down && (key == VirtualKey::F5 || (key == VirtualKey::S && ctrlDown))) Stop();
                    return UI::InputBlocking::DoNothing;
                }
                if (down) {
                    if (dragging || eraseTarget !is null) {
                        Cancel();
                    } else {
                        Stop();
                    }
                    GuardKey();
                    escapeDown = true;
                    inputReleaseAt = Time::Now + 80;
                }
                return UI::InputBlocking::Block;
            }
        }
    }
}
