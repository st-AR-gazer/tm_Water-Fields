namespace WaterFields {
    namespace App {
        void Main() {
            Start();
        }

        void Start() {
            if (g_initialized) return;

            log::Start();
            g_initialized = true;
            log::Debug("Loaded " + PluginMeta.Name + " v" + PluginMeta.Version, "WaterFields::App::Start");
        }

        void Shutdown() {
            if (!g_initialized) return;

            Authoring::Shutdown();
            Authoring::Assets::g_templatesVerified = false;
            @Authoring::g_lastResult = null;
            g_initialized = false;
            log::Debug("Stopped", "WaterFields::App::Shutdown");
            log::Shutdown();
        }

        void Update(float dt) {
            if (!g_initialized) return;
            Authoring::Update();
        }

        void RenderMenu() {
            if (!g_initialized) return;

            bool clicked = UI::MenuItem(MenuTitle());
            if (clicked || UI::IsItemClicked(UI::MouseButton::Right)) {
                Meta::OpenSettings(PluginMeta);
            }
        }
    }
}
