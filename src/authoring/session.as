namespace WaterFields {
    namespace Authoring {
        enum SessionState {
            Inactive,
            Waiting,
            Ready,
            Testing,
            Unsupported
        }

        class EditorSnapshot {
            string mapUid;
            string mapName;
            string mapFileName;
            SessionState state = SessionState::Inactive;
        }

        class EditorSession {
            EditorSnapshot@ current = EditorSnapshot();
            uint64 revision = 0;

            bool Observe(EditorSnapshot@ next) {
                bool changed = current.state != next.state ||
                               current.mapUid != next.mapUid ||
                               current.mapFileName != next.mapFileName;
                if (changed) revision++;
                @current = next;
                return changed;
            }

            uint64 Capture() const {
                return IsCurrent(revision) ? revision : 0;
            }

            bool IsCurrent(uint64 token) const {
                return token != 0 && current.state == SessionState::Ready && token == revision;
            }

            void Reset() {
                Observe(EditorSnapshot());
            }
        }

        EditorSession g_session;
        string g_lastError;

        EditorSnapshot@ ReadSnapshot() {
            auto snapshot = EditorSnapshot();
            auto app = GetApp();
            auto editor = cast<CGameCtnEditorFree>(app.Editor);
            if (editor is null || editor.PluginMapType is null) return snapshot;
            auto pluginMap = editor.PluginMapType;
            auto map = pluginMap.Map;
            if (map is null) return snapshot;
            if (map.MapInfo !is null) snapshot.mapUid = map.MapInfo.MapUid;
            snapshot.mapName = string(pluginMap.MapName);
            snapshot.mapFileName = string(pluginMap.MapFileName);
            if (map.CollectionName != "Stadium") {
                snapshot.state = SessionState::Unsupported;
            } else if (pluginMap.IsTesting || pluginMap.IsSwitchedToPlayground) {
                snapshot.state = SessionState::Testing;
            } else {
                snapshot.state = pluginMap.IsEditorReadyForRequest ? SessionState::Ready : SessionState::Waiting;
            }
            return snapshot;
        }

        void Update() {
            try {
                if (g_session.Observe(ReadSnapshot())) {
                    log::Debug(StateText(), "WaterFields::Authoring::Update");
                }
                g_lastError = "";
            } catch {
                g_session.Reset();
                string error = getExceptionInfo();
                if (error != g_lastError) log::Warning(error, "WaterFields::Authoring::Update");
                g_lastError = error;
            }
        }

        uint64 CaptureSession() {
            if (!App::g_initialized) return 0;
            Update();
            return g_session.Capture();
        }

        bool IsSessionCurrent(uint64 token) {
            if (!App::g_initialized) return false;
            Update();
            return g_session.IsCurrent(token);
        }

        void Shutdown() {
            g_session.Reset();
            g_lastError = "";
        }

        string StateText() {
            auto state = g_session.current.state;
            if (state == SessionState::Ready) return "Editor ready";
            if (state == SessionState::Waiting) return "Waiting for the editor";
            if (state == SessionState::Testing) return "Test drive active";
            if (state == SessionState::Unsupported) return "Open a Stadium map";
            return "Open a map in the advanced editor";
        }
    }
}
