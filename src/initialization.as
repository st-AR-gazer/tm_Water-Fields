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
