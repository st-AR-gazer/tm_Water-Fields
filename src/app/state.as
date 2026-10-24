namespace WaterFields {
    Meta::Plugin@ pluginMeta = Meta::ExecutingPlugin();

    namespace App {
        [Setting hidden name="Allow water outside map borders"]
        bool S_AllowOutsideMapBorders = false;
        [Setting hidden name="Cube size"]
        float S_CubeScale = 8;
        [Setting hidden name="Show fields outside water mode"]
        bool S_PreviewOutsideMode = false;
        bool initialized = false;

        string MenuTitle() {
            return Icons::Tint + " " + pluginMeta.Name;
        }
    }
}
