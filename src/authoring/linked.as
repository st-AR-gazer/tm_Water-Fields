namespace WaterFields {
    namespace Authoring {
        namespace Linked {
            enum Action {
                None, RemoveWater, RestoreWater, RemoveBoundary, RestoreBoundary, Unsupported
            }

            class Pair {
                WaterFields::Fields::Field@ field;
                bool water = false;
                uint exact = 0;
                uint total = 0;
                bool removedWater = false;
                bool removedBoundary = false;
                bool failed = false;
            }

            array<Pair@> pairs;
            string mapUid;
            string message;
            uint64 nextScanAt = 0;

            Action Decide(Pair@ pair, bool water, uint exact, uint total) {
                if (exact > 1) return Action::Unsupported;
                if (water &&
                    exact == 0 &&
                    pair.exact == 1 &&
                    total < pair.total
                ) return Action::RemoveWater;
                if (!water &&
                    exact == 1 &&
                    pair.removedWater
                ) return Action::RestoreWater;
                if (!water &&
                    exact == 1 &&
                    pair.water
                ) return Action::RemoveBoundary;
                if (water &&
                    exact == 0 &&
                    pair.removedBoundary
                ) return Action::RestoreBoundary;
                if (total != exact || water != (exact == 1)) return Action::Unsupported;
                return Action::None;
            }

            void Reset() {
                pairs.Resize(0);
                mapUid = "";
                message = "";
                nextScanAt = 0;
            }

            void Remember(WaterFields::Fields::Field@ field) {
                if (!field.boundary) return;
                for (uint i = 0; i < pairs.Length; i++) {
                    auto old = pairs[i].field;
                    if (old.stem == field.stem && old.anchor == field.anchor) {
                        pairs[i].field = field;
                        return;
                    }
                }
                auto pair = Pair();
                @pair.field = WaterFields::Fields::Field();
                pair.field = field;
                pair.water = FindPlaced(ReadyEditor(), field) !is null;
                pair.exact = Boundaries::Count(field, true);
                pair.total = Boundaries::Count(field, false);
                pairs.InsertLast(pair);
            }

            void Update() {
                auto snapshot = session.current;
                if (snapshot.state == SessionState::Inactive ||
                    snapshot.state == SessionState::Unsupported ||
                    snapshot.mapUid != mapUid
                ) {
                    Reset();
                    mapUid = snapshot.mapUid;
                }
                if (snapshot.state != SessionState::Ready || Time::Now<nextScanAt) return;
                nextScanAt = Time::Now + 500;
                string previousMessage = message;
                message = "";
                try {
                    auto editor = ReadyEditor();
                    for (uint i = 0; i<editor.GhostBlocks.Length; i++) {
                        auto field = ReadField(editor.GhostBlocks[i]);
                        if (field !is null) Remember(field);
                    }
                    for (uint i = 0; i<pairs.Length; i++) {
                        auto pair = pairs[i];
                        if (pair.failed) {
                            message = "Linked water editing stopped after a failed change. Undo the native edit, then Retry linked edits.";
                            continue;
                        }
                        auto field = pair.field;
                        auto mutator = NativeFieldMutator();
                        bool water = mutator.CarrierExists(field);
                        uint exact = Boundaries::Count(field, true);
                        uint total = Boundaries::Count(field, false);
                        auto action = Decide(pair, water, exact, total);
                        try {
                            if (action == Action::RemoveWater || action == Action::RestoreWater) {
                                bool add = action == Action::RestoreWater;
                                mutator.ChangeCarrier(field, add);
                                pair.removedWater = !add;
                            } else if (action == Action::RemoveBoundary || action == Action::RestoreBoundary) {
                                bool add = action == Action::RestoreBoundary;
                                Boundaries::Change(field, mutator.BoundaryModel(field), add);
                                pair.removedBoundary = !add;
                            } else if (action == Action::Unsupported) {
                                message = "A water boundary is missing, moved, rotated or copied. Water stays at its original bounds. Undo the native edit before continuing.";
                            }
                            pair.water = mutator.CarrierExists(field);
                            pair.exact = Boundaries::Count(field, true);
                            pair.total = Boundaries::Count(field, false);
                            if (pair.water && pair.exact == 1) {
                                pair.removedWater = false;
                                pair.removedBoundary = false;
                            }
                        } catch {
                            pair.failed = true;
                            message = "Linked water edit failed: " + getExceptionInfo();
                            log::Warning(message, "WaterFields::Authoring::Linked::Update");
                        }
                    }
                } catch {
                    message = "Could not inspect linked water: " + getExceptionInfo();
                }
                if (message.Length> 0 && message != previousMessage) {
                    Input::windowOpen = true;
                    log::Warning(message, "WaterFields::Authoring::Linked::Update");
                }
            }

            void Retry() {
                for (uint i = 0; i<pairs.Length; i++) pairs[i].failed = false;
                nextScanAt = 0;
            }
        }
    }
}
