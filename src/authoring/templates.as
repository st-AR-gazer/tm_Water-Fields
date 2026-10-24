namespace WaterFields {
    namespace Authoring {
        namespace Templates {
            const string templateFolder = "src/assets/templates/";
            const string nativePath = templateFolder + "Native/v28_000_Water_Area.EDClassic.Gbx";
            const string wrapperPath = templateFolder + "v28_000_Water_Area.Block.Gbx";
            const string prefabPath = templateFolder + "Native/v28_000_Water_Area.Prefab.Gbx";

            MemoryBuffer@ Read(const string &in path) {
                IO::FileSource file(path);
                return file.Read(file.Size());
            }

            Json::Value@ Manifest() {
                IO::FileSource file(templateFolder + "manifest.json");
                return Json::Parse(file.ReadToEnd());
            }
        }
    }
}
