namespace WaterFields {
    namespace App {
        void Main() {
            Start();
        }

        void Start() {
            if (initialized) return;

            log::Start();
            if (!(S_CubeScale >= 0.25f && S_CubeScale <= Fields::maxHeight)) S_CubeScale = 8;
            initialized = true;
            log::Debug("Loaded " + pluginMeta.Name + " v" + pluginMeta.Version, "WaterFields::App::Start");
        }

        void Shutdown() {
            if (!initialized) return;

            Authoring::Input::Stop();
            Authoring::Input::placedFields.Resize(0);
            Authoring::Input::regions.Rebuild(Authoring::Input::placedFields);
            Authoring::Input::windowOpen = false;
            Authoring::Shutdown();
            Authoring::Linked::Reset();
            Export::Shutdown();
            Authoring::Assets::templatesVerified = false;
            @Authoring::lastResult = null;
            initialized = false;
            log::Debug("Stopped", "WaterFields::App::Shutdown");
            log::Shutdown();
        }

        void Update(float dt) {
            if (!initialized) return;
            Authoring::Update();
            Authoring::Linked::Update();
            Export::Update();
        }

        void RenderMenu() {
            if (!initialized) return;

            bool clicked = UI::MenuItem(MenuTitle(), "", Authoring::Input::windowOpen);
            if (clicked) {
                Authoring::Input::windowOpen = !Authoring::Input::windowOpen;
                if (!Authoring::Input::windowOpen) Authoring::Input::Stop();
            }
            if (UI::IsItemClicked(UI::MouseButton::Right)) {
                Meta::OpenSettings(pluginMeta);
            }
        }
    }
}
