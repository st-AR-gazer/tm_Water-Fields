namespace WaterFields {
    namespace App {
        void RenderGeneralSettingsUI() {
            bool open = UI::BeginChild("##water-fields-settings-general", vec2(0, 0), false);
            if (open) {
                S_AllowOutsideMapBorders = UI::Checkbox("Allow water outside map borders", S_AllowOutsideMapBorders);
                UI::Text(Authoring::StateText());
                if (Authoring::g_lastError.Length > 0) UI::TextWrapped(Authoring::g_lastError);
            }
            UI::EndChild();
        }

        void RenderLoggingSettingsUI() {
            bool open = UI::BeginChild("##water-fields-settings-logging", vec2(0, 0), false);
            if (open) {
                log::RenderSettingsUI("water-fields-logging");
            }
            UI::EndChild();
        }
    }
}
