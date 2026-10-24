void Main() {
    WaterFields::App::Main();
}

void Update(float dt) {
    WaterFields::App::Update(dt);
}

void RenderMenu() {
    WaterFields::App::RenderMenu();
}

void OnDisabled() {
    WaterFields::App::Shutdown();
}

void OnDestroyed() {
    WaterFields::App::Shutdown();
}

void RenderEarly() {
    if (!WaterFields::App::initialized) return;
    try {
        WaterFields::Authoring::Input::Update();
    } catch {
        WaterFields::Authoring::Input::Failed(getExceptionInfo());
    }
}

void Render() {
    WaterFields::Ui::RenderPreview();
    WaterFields::Ui::RenderTools();
}

void OnMouseMove(int x, int y) {
    WaterFields::Authoring::Input::mousePosition = vec2(x, y);
}

UI::InputBlocking OnMouseButton(bool down, int button, int x, int y) {
    try {
        return WaterFields::Authoring::Input::MouseButton(down, button, x, y);
    } catch {
        WaterFields::Authoring::Input::Failed(getExceptionInfo());
    }
    return UI::InputBlocking::Block;
}

UI::InputBlocking OnMouseWheel(int x, int y) {
    try {
        return WaterFields::Authoring::Input::MouseWheel(y);
    } catch {
        WaterFields::Authoring::Input::Failed(getExceptionInfo());
    }
    return UI::InputBlocking::Block;
}

UI::InputBlocking OnKeyPress(bool down, VirtualKey key) {
    try {
        return WaterFields::Authoring::Input::Key(down, key);
    } catch {
        WaterFields::Authoring::Input::Failed(getExceptionInfo());
    }
    return UI::InputBlocking::Block;
}
