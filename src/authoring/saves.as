namespace WaterFields {
    namespace Saves {
        CGameCtnChallenge@ currentMap;
        Json::Value@ request;
        Json::Value@ recovery;
        string sessionId;
        string layout;
        string status = "placed";
        string message = "Save the map to verify its water.";
        string exitWarning;
        array<string> unresolved;
        uint revision = 0;
        uint64 nextUpdateAt = 0;
        uint64 leftEditorAt = 0;
        uint64 startedAt = 0;
        bool initialized = false;
        bool halted = false;

        string Folder() {
            return IO::FromStorageFolder("recovery/");
        }

        void Start() {
            exitWarning = "";
            unresolved.Resize(0);
            halted = false;
            try {
                Export::Load();
                IO::CreateFolder(Folder(), true);
                auto paths = IO::IndexFolder(Folder(), false);
                for (uint i = 0; i < paths.Length; i++) {
                    if (!paths[i].EndsWith(".layout.json")) continue;
                    auto saved = Json::FromFile(paths[i]);
                    Fields::Require(
                        string(saved["schema"]) == "waterfields-save-v1",
                        "Invalid saved layout."
                    );
                    string dismissed = paths[i] + ".dismissed.json";
                    if (IO::FileExists(dismissed) &&
                        uint(Json::FromFile(dismissed)) == uint(saved["revision"])) continue;
                    bool finished = false;
                    string previousPath = string(saved["statusPath"]);
                    if (IO::FileExists(previousPath)) {
                        auto previous = Json::FromFile(previousPath);
                        finished = string(previous["schema"]) == "waterfields-save-status-v1" &&
                                   string(previous["status"]) == "verified" &&
                                   uint(previous["revision"]) == uint(saved["revision"]) &&
                                   string(previous["session"]) == string(saved["session"]);
                    }
                    if (!finished) {
                        unresolved.InsertLast(paths[i]);
                        @recovery = saved;
                    }
                }
                if (unresolved.Length > 0) {
                    exitWarning = unresolved.Length + " previous water session(s) did not finish verification. "
                    "Their captured positions are available below.";
                } else if (IO::FileExists(Folder() + "latest.json")) {
                    @recovery = Json::FromFile(Folder() + "latest.json");
                    Fields::Require(
                        string(recovery["schema"]) == "waterfields-save-v1",
                        "Invalid saved layout."
                    );
                }
            } catch {
                halted = true;
                status = "attention";
                message = "Save verification is unavailable: " + getExceptionInfo();
            }
            initialized = true;
        }

        string MapPath(const string &in fileName) {
            if (fileName.Length == 0) return "";
            string path = fileName.Replace("\\", "/");
            if (path.Contains(":")) return path.Replace("/", "\\");
            if (!path.StartsWith("Maps/")) path = "Maps/" + path;
            return IO::FromUserGameFolder(path).Replace("/", "\\");
        }

        Json::Value@ Capture(CGameEditorPluginMapMapType@ editor) {
            auto fields = Json::Array();
            for (uint i = 0; i < editor.GhostBlocks.Length; i++) {
                auto field = Authoring::ReadField(editor.GhostBlocks[i]);
                if (field is null) continue;
                auto value = Json::Object();
                value["stem"] = field.stem;
                auto anchor = Json::Array();
                anchor.Add(field.anchor.x);
                anchor.Add(field.anchor.y);
                anchor.Add(field.anchor.z);
                value["anchor"] = anchor;
                value["variant"] = field.variant;
                value["ground"] = field.isGround;
                value["minimum"] = Fields::Vector(field.minimum);
                value["size"] = Fields::Vector(field.size);
                fields.Add(value);
            }
            return fields;
        }

        void Update() {
            if (!initialized || Time::Now<nextUpdateAt) return;
            nextUpdateAt = Time::Now + 500;
            try {
                auto editor = cast<CGameCtnEditorFree>(GetApp().Editor);
                auto snapshot = Authoring::session.current;
                if (editor is null ||
                    editor.PluginMapType is null ||
                    snapshot.state == Authoring::SessionState::Unsupported
                ) {
                    if (request is null) return;
                    if (leftEditorAt == 0) leftEditorAt = Time::Now;
                    if (Time::Now - leftEditorAt> 45000) {
                        Stop();
                        return;
                    }
                } else {
                    leftEditorAt = 0;
                    auto map = editor.PluginMapType.Map;
                    if (map is null) return;
                    if (currentMap !is map) {
                        Stop();
                        @currentMap = map;
                        sessionId = Time::Stamp + "-" + Time::Now;
                        layout = "";
                        revision = 0;
                    }
                    auto fields = request is null ? Json::Array() : request["fields"];
                    if (snapshot.state == Authoring::SessionState::Ready) @fields = Capture(editor.PluginMapType);
                    if (fields.Length == 0 && request is null) return;
                    auto next = Json::Object();
                    next["schema"] = "waterfields-save-v1";
                    next["session"] = sessionId;
                    next["mapUid"] = snapshot.mapUid;
                    next["input"] = MapPath(snapshot.mapFileName);
                    next["assetRoot"] = IO::FromUserGameFolder(Authoring::Assets::assetFolder);
                    next["statusPath"] = Folder() + sessionId + ".status.json";
                    next["fields"] = fields;
                    string nextLayout = Json::Write(next);
                    if (nextLayout != layout) {
                        layout = nextLayout;
                        next["revision"] = ++revision;
                        @request = next;
                        @recovery = next;
                        startedAt = Time::Now;
                        if (!halted) {
                            status = "placed";
                            message = "Water layout changed. Save the map to verify it.";
                        }
                        Json::ToFile(Folder() + "latest.json", request);
                        Json::ToFile(Folder() + sessionId + ".layout.json", request);
                    }
                }
                if (request is null || halted) return;
                if (string(request["mapUid"]).Length == 0) {
                    if (Export::saveStop !is null) Export::saveStop.CallInt32();
                    status = "placed";
                    message = "Save the new map before verifying its water.";
                    return;
                }
                Export::Load();
                Fields::Require(
                    Export::savePulse.CallInt32(Json::Write(request)) == 0,
                    "Could not start save verification. Check the DLL installation, then Retry."
                );
                ReadStatus();
            } catch {
                halted = true;
                status = "attention";
                message = getExceptionInfo();
                if (Export::saveStop !is null) Export::saveStop.CallInt32();
            }
        }

        void ReadStatus() {
            string path = string(request["statusPath"]);
            if (!IO::FileExists(path)) {
                Fields::Require(
                    Time::Now - startedAt < 5000,
                    "The save worker did not respond. Retry verification."
                );
                return;
            }
            auto value = Json::FromFile(path);
            Fields::Require(
                value.GetType() == Json::Type::Object,
                "Save status must be an object."
            );
            array<string> strings = {"schema", "session", "mapUid", "input", "status", "message"};
            for (uint i = 0; i < strings.Length; i++) {
                Fields::Require(
                    value[strings[i]].GetType() == Json::Type::String,
                    "Malformed save status field."
                );
            }
            Fields::Require(
                value["revision"].GetType() == Json::Type::Number && value["checkedAt"].GetType() == Json::Type::Number,
                "Malformed save status numbers."
            );
            Fields::Require(
                string(value["schema"]) == "waterfields-save-status-v1",
                "Malformed save status."
            );
            if (string(value["session"]) != sessionId || uint(value["revision"]) != revision) {
                Fields::Require(
                    Time::Now - startedAt < 35000,
                    "The save worker did not finish this layout."
                );
                return;
            }
            Fields::Require(
                string(value["mapUid"]) == string(request["mapUid"]) &&
                string(value["input"]) == string(request["input"]),
                "Save status belongs to a different map."
            );
            string next = string(value["status"]);
            Fields::Require(
                next == "placed" || next == "awaiting" || next == "verified" || next == "attention",
                "Unknown save status."
            );
            int64 checkedAt = int64(double(value["checkedAt"]));
            int timeout = next == "awaiting" ? 35 : 5;
            Fields::Require(
                checkedAt <= Time::Stamp + 1 && Time::Stamp - checkedAt <= timeout,
                "Save verification stopped responding. Retry before sharing the map."
            );
            status = next;
            message = string(value["message"]);
        }

        void Retry() {
            if (request is null) return;
            request["revision"] = ++revision;
            Json::ToFile(Folder() + "latest.json", request);
            Json::ToFile(Folder() + sessionId + ".layout.json", request);
            startedAt = Time::Now;
            nextUpdateAt = 0;
            halted = false;
            status = "awaiting";
            message = "Retrying save verification...";
        }

        void RecoverCopy() {
            try {
                Fields::Require(
                    recovery !is null,
                    "No saved water layout is available."
                );
                string input = string(recovery["input"]);
                if (!IO::FileExists(input) && IO::FileExists(string(recovery["statusPath"]))) {
                    auto previous = Json::FromFile(string(recovery["statusPath"]));
                    Fields::Require(
                        string(previous["session"]) == string(recovery["session"]),
                        "The backup belongs to a different session."
                    );
                    input = string(previous["backup"]);
                }
                Fields::Require(
                    IO::FileExists(input),
                    "Save the map first. Positions alone cannot recover unsaved edits."
                );
                string name = "water-recovery-" + Time::Stamp + "-" + Time::Now;
                auto job = Json::Object();
                job["schema"] = "waterfields-export-v1";
                job["input"] = input;
                job["output"] = IO::FromUserGameFolder("Maps/WaterFields Recovery/" + name + ".Map.Gbx");
                job["assetRoot"] = recovery["assetRoot"];
                job["mapUid"] = recovery["mapUid"];
                job["recoverMissing"] = true;
                string path = Folder() + name + ".json";
                Json::ToFile(path, job);
                Export::Start(path);
            } catch {
                Export::statusMessage = getExceptionInfo();
            }
        }

        void Stop() {
            if (request !is null && status != "verified") {
                exitWarning = "Water was not verified before leaving the editor. Retry on reopening, or recover a saved copy.";
                string path = Folder() + sessionId + ".layout.json";
                if (unresolved.Find(path) < 0) unresolved.InsertLast(path);
                UI::ShowNotification("Water Fields", exitWarning, 10000);
            }
            if (Export::saveStop !is null) Export::saveStop.CallInt32();
            @request = null;
            @currentMap = null;
            leftEditorAt = 0;
            if (!halted) {
                status = "placed";
                message = "Open a map with water fields to verify its next save.";
            }
        }

        void Render() {
            string label = "Placed";
            if (status == "awaiting")  label = "Awaiting save verification";
            if (status == "verified")  label = "Verified";
            if (status == "attention") label = "Needs attention";
            UI::Separator();
            UI::Text("Water save: " + label);
            UI::TextWrapped(message);
            if (status == "awaiting") UI::TextWrapped("Keep Trackmania open until verification finishes.");
            UI::BeginDisabled(request is null);
            if (UI::Button("Retry verification")) Retry();
            UI::EndDisabled();
            UI::BeginDisabled(recovery is null || Export::Busy());
            if (UI::Button("Recover saved copy")) RecoverCopy();
            UI::EndDisabled();
            UI::SameLine();
            if (UI::Button("Captured positions")) _IO::OpenFolder(Folder());
            UI::TextWrapped("Recovery keeps the saved map intact and creates a separate copy. " "It cannot recover unsaved map edits. Open the copy to load repaired water models; save again after editing.");
            if (exitWarning.Length > 0) {
                UI::TextWrapped(exitWarning);
                if (UI::Button("Dismiss previous warnings")) {
                    try {
                        for (uint i = 0; i < unresolved.Length; i++) {
                            auto saved = Json::FromFile(unresolved[i]);
                            Json::ToFile(unresolved[i] + ".dismissed.json", saved["revision"]);
                        }
                        unresolved.Resize(0);
                        exitWarning = "";
                    } catch {
                        exitWarning = "Could not dismiss the warning: " + getExceptionInfo();
                    }
                }
            }
            if (Export::statusMessage.Length > 0) UI::TextWrapped(Export::statusMessage);
        }
    }
}
