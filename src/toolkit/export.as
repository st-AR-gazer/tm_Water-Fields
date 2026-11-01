namespace WaterFields {
    namespace Export {
        Import::Library@ exportLibrary;
        Import::Function@ startExport;
        Import::Function@ exportState;
        Import::Function@ savePulse;
        Import::Function@ saveStop;
        string pendingRequest;
        string statusMessage;
        Json::Value@ exportResult;
        Json::Value@ request;
        uint64 startedAt = 0;

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
            auto pulse = library.GetFunction("WaterFields_SavePulseV1");
            auto stop = library.GetFunction("WaterFields_SaveStopV1");
            Fields::Require(
                start !is null && state !is null && pulse !is null && stop !is null,
                "Unsupported water export library."
            );
            @exportLibrary = library;
            @startExport = start;
            @exportState = state;
            @savePulse = pulse;
            @saveStop = stop;
        }

        void Start(const string &in requestPath) {
            Fields::Require(
                !Busy(),
                "A water export is already running."
            );
            Load();
            @request = Json::FromFile(requestPath);
            Fields::Require(
                string(request["schema"]) == "waterfields-export-v1",
                "Invalid export request."
            );
            int code = startExport.CallInt32(requestPath);
            Fields::Require(
                code == 0,
                code == 1 ?
                    "A water export is already running." :
                    "Could not start water export. Use a new request filename and check the DLL installation."
            );
            @exportResult = null;
            pendingRequest = requestPath;
            startedAt = Time::Now;
            statusMessage = "Exporting water...";
        }

        void Update() {
            if (!Busy()) return;
            if (exportState.CallInt32() == 1 && Time::Now - startedAt < 35000) return;
            try {
                auto result = Json::FromFile(pendingRequest + ".result.json");
                Fields::Require(
                    string(result["schema"]) == "waterfields-export-result-v1",
                    "Invalid water export result."
                );
                string state = string(result["status"]);
                if (state == "verified") {
                    Fields::Require(
                        string(result["mapUid"]) == string(request["mapUid"]) &&
                        string(result["input"]).Replace("\\", "/") == string(request["input"]).Replace("\\", "/") &&
                        string(result["output"]).Replace("\\", "/") == string(request["output"]).Replace("\\", "/") &&
                        result["contentPreserved"].GetType() == Json::Type::Boolean &&
                        bool(result["contentPreserved"]),
                        "Export result does not match this request."
                    );
                    statusMessage = "Saved copy verified: " + string(result["output"]);
                } else {
                    Fields::Require(
                        (state == "failed" || state == "timed-out") && result["error"].GetType() == Json::Type::String,
                        "Malformed export failure."
                    );
                    statusMessage = string(result["error"]);
                }
                @exportResult = result;
            } catch {
                statusMessage = "Could not read the water export result: " + getExceptionInfo();
            }
            pendingRequest = "";
            @request = null;
        }

        void Shutdown() {
            if (saveStop !is null) saveStop.CallInt32();
            pendingRequest = "";
            @exportResult = null;
            @request = null;
            statusMessage = "";
        }
    }
}
