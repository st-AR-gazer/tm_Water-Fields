namespace WaterFields {
    namespace Export {
        Import::Library@ g_library;
        Import::Function@ g_start;
        Import::Function@ g_state;
        string g_request;
        string g_message;
        Json::Value@ g_result;

        bool Busy() {
            return g_request.Length > 0;
        }

        void Load() {
            if (g_library !is null) return;
            string directory = IO::FromStorageFolder("helper/" + Time::Stamp + "-" + Time::Now + "/");
            IO::CreateFolder(directory);
            for (uint i = 0; i < 2; i++) {
                string name = i == 0 ? "WaterFields.Export.dll" : "liblzo2.dll";
                IO::FileSource source("src/assets/" + name);
                Fields::Require(
                    source.Size() > 0,
                    "Missing export library: " + name
                );
                IO::File file(directory + name, IO::FileMode::Write);
                file.Write(source.Read(source.Size()));
                file.Close();
            }
            auto library = Import::GetLibrary(directory + "WaterFields.Export.dll");
            Fields::Require(
                library !is null,
                "Could not load the water export library."
            );
            auto start = library.GetFunction("WaterFields_StartExportV1");
            auto state = library.GetFunction("WaterFields_ExportStateV1");
            Fields::Require(
                start !is null && state !is null,
                "Unsupported water export library."
            );
            @g_library = library;
            @g_start = start;
            @g_state = state;
        }

        void Start(const string &in requestPath) {
            Fields::Require(
                !Busy(),
                "A water export is already running."
            );
            Load();
            int code = g_start.CallInt32(requestPath);
            Fields::Require(
                code == 0,
                code == 1 ?
                    "A water export is already running." :
                    "Could not start water export. Use a new request filename and check the DLL installation."
            );
            @g_result = null;
            g_request = requestPath;
            g_message = "Exporting water...";
        }

        void Update() {
            if (!Busy() || g_state.CallInt32() == 1) return;
            try {
                auto result = Json::FromFile(g_request + ".result.json");
                Fields::Require(
                    string(result["schema"]) == "waterfields-export-result-v1",
                    "Invalid water export result."
                );
                @g_result = result;
                g_message = string(result["status"]) == "verified" ?
                    "Water exported: " + string(result["output"]) :
                    string(result["error"]);
            } catch {
                g_message = "Could not read the water export result: " + getExceptionInfo();
            }
            g_request = "";
        }

        void Shutdown() {
            g_request = "";
            @g_result = null;
            g_message = "";
        }
    }
}
