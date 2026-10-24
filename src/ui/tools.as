namespace WaterFields {
    namespace Ui {
        void Preferences() {
            UI::BeginDisabled(Authoring::Input::leftOwned);
            float scale = UI::InputFloat("Cube size (m)", App::S_CubeScale, 0.25f, 1.0f);
            if (scale >= 0.25f && scale <= Fields::maxHeight) App::S_CubeScale = scale;
            App::S_PreviewOutsideMode = UI::Checkbox("Show fields outside water mode", App::S_PreviewOutsideMode);
            UI::EndDisabled();
        }

        void RenderTools() {
            if (!App::initialized || !Authoring::Input::windowOpen) return;
            UI::SetNextWindowSize(390, 0, UI::Cond::Always);
            if (UI::Begin(
                App::MenuTitle() + "###WaterFieldsTools",
                Authoring::Input::windowOpen,
                UI::WindowFlags::AlwaysAutoResize
            )) {
                bool ready = Authoring::ReadSnapshot().state == WaterFields::Authoring::SessionState::Ready;
                UI::BeginDisabled(!ready);
                if (UI::RadioButton("Off", Authoring::Input::activeTool == Authoring::Input::Tool::Off)) {
                    Authoring::Input::Select(Authoring::Input::Tool::Off);
                }
                UI::SameLine();
                if (UI::RadioButton("Draw", Authoring::Input::activeTool == Authoring::Input::Tool::Draw)) {
                    Authoring::Input::Select(Authoring::Input::Tool::Draw);
                }
                UI::SameLine();
                if (UI::RadioButton("Erase", Authoring::Input::activeTool == Authoring::Input::Tool::Erase)) {
                    Authoring::Input::Select(Authoring::Input::Tool::Erase);
                }
                UI::EndDisabled();
                UI::BeginDisabled(!ready || Authoring::Input::leftOwned || Authoring::History::edits.undo.Length == 0);
                if (UI::Button("Undo water")) Authoring::Input::ApplyHistory(false);
                UI::EndDisabled();
                UI::SameLine();
                UI::BeginDisabled(!ready || Authoring::Input::leftOwned || Authoring::History::edits.redo.Length == 0);
                if (UI::Button("Redo water")) Authoring::Input::ApplyHistory(true);
                UI::EndDisabled();
                Preferences();
                UI::TextWrapped("Drag to draw. Scroll while holding to change height. " "Right-click or Escape cancels. Hold Alt to move the camera.");
                UI::TextWrapped("Erase: click and release on the same field to remove its connected region.");
                UI::TextWrapped("In water mode: Ctrl+Z undoes a water edit; Ctrl+Y or Ctrl+Shift+Z redoes it.");
                if (!ready) UI::Text(Authoring::StateText());
                if (Authoring::Input::hasHit) {
                    auto size = Authoring::Input::preview.size;
                    string dimensions = Text::Format("%.2f", size.x) +
                                        " x " +
                                        Text::Format("%.2f", size.y) +
                                        " x " +
                                        Text::Format("%.2f", size.z) +
                                        " m";
                    UI::Text(dimensions);
                }
                if (Authoring::Input::statusMessage.Length > 0) UI::TextWrapped(Authoring::Input::statusMessage);
                if (Authoring::Input::scanMessage.Length > 0) UI::TextWrapped(Authoring::Input::scanMessage);
                UI::TextWrapped("Native saves strip the water model. Use the export step to preserve water in a shared map.");
            }
            UI::End();
            if (!Authoring::Input::windowOpen) Authoring::Input::Stop();
        }
    }
}
