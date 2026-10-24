namespace WaterFields {
    namespace Export {
        Import::Library@ exportLibrary;
        Import::Function@ startExport;
        Import::Function@ exportState;
        string pendingRequest;
        string statusMessage;
        Json::Value@ exportResult;

        bool Busy() {
            return pendingRequest.Length > 0;
        }

        void Load() {
            if (exportLibrary !is null) return;
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
            @exportLibrary = library;
            @startExport = start;
            @exportState = state;
        }

        void Start(const string &in requestPath) {
            Fields::Require(
                !Busy(),
                "A water export is already running."
            );
            Load();
            int code = startExport.CallInt32(requestPath);
            Fields::Require(
                code == 0,
                code == 1 ?
                    "A water export is already running." :
                    "Could not start water export. Use a new request filename and check the DLL installation."
            );
            @exportResult = null;
            pendingRequest = requestPath;
            statusMessage = "Exporting water...";
        }

        void Update() {
            if (!Busy() || exportState.CallInt32() == 1) return;
            try {
                auto result = Json::FromFile(pendingRequest + ".result.json");
                Fields::Require(
                    string(result["schema"]) == "waterfields-export-result-v1",
                    "Invalid water export result."
                );
                @exportResult = result;
                statusMessage = string(result["status"]) == "verified" ?
                    "Water exported: " + string(result["output"]) :
                    string(result["error"]);
            } catch {
                statusMessage = "Could not read the water export result: " + getExceptionInfo();
            }
            pendingRequest = "";
        }

        void Shutdown() {
            pendingRequest = "";
            @exportResult = null;
            statusMessage = "";
        }
    }
}
