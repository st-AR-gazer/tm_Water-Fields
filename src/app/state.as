namespace WaterFields {
    Meta::Plugin@ PluginMeta = Meta::ExecutingPlugin();

    namespace App {
        [Setting hidden name="Allow water outside map borders"]
        bool S_AllowOutsideMapBorders = false;

        bool g_initialized = false;

        string MenuTitle() {
            return Icons::Tint + " " + PluginMeta.Name;
        }
    }
}
