namespace WaterFields {
    namespace Authoring {
        namespace Templates {
            const string Root = "src/assets/templates/";
            const string Native = Root + "Native/v28_000_Water_Area.EDClassic.Gbx";
            const string Wrapper = Root + "v28_000_Water_Area.Block.Gbx";
            const string Prefab = Root + "Native/v28_000_Water_Area.Prefab.Gbx";

            MemoryBuffer@ Read(const string &in path) {
                IO::FileSource file(path);
                return file.Read(file.Size());
            }

            Json::Value@ Manifest() {
                IO::FileSource file(Root + "manifest.json");
                return Json::Parse(file.ReadToEnd());
            }
        }
    }
}
