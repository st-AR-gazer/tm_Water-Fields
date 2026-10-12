namespace WaterFields {
    Meta::Plugin@ PluginMeta = Meta::ExecutingPlugin();

    namespace App {
        bool g_initialized = false;

        string MenuTitle() {
            return Icons::Tint + " " + PluginMeta.Name;
        }
    }
}
