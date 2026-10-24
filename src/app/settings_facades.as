namespace WaterFields {
    namespace App {
        void RenderGeneralSettingsUi() {
            bool open = UI::BeginChild("##water-fields-settings-general", vec2(0, 0), false);
            if (open) {
                Ui::Preferences();
                S_AllowOutsideMapBorders = UI::Checkbox("Allow water outside map borders", S_AllowOutsideMapBorders);
                UI::Text(Authoring::StateText());
                if (Authoring::lastError.Length > 0) UI::TextWrapped(Authoring::lastError);
            }
            UI::EndChild();
        }

        void RenderLoggingSettingsUi() {
            bool open = UI::BeginChild("##water-fields-settings-logging", vec2(0, 0), false);
            if (open) {
                log::RenderSettingsUI("water-fields-logging");
            }
            UI::EndChild();
        }
    }
}
