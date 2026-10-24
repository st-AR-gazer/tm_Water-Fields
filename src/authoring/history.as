namespace WaterFields {
    namespace Authoring {
        interface FieldMutator {
            void Preflight(WaterFields::Fields::Field@ field, bool add);
            void Change(WaterFields::Fields::Field@ field, bool add);
            bool Exists(WaterFields::Fields::Field@ field);
        }

        class BatchResult {
            bool success = false;
            string error;
            array<WaterFields::Fields::Field@> changed;
        }

        BatchResult@ ApplyBatch(const array<WaterFields::Fields::Field@> &in fields, bool add, FieldMutator@ mutator) {
            auto result = BatchResult();
            uint attempted = 0;
            try {
                Fields::Require(fields.Length > 0, "No fields in this edit.");
                for (uint i = 0; i < fields.Length; i++) {
                    for (uint j = 0; j < i; j++) {
                        Fields::Require(fields[i].anchor != fields[j].anchor, "Two fields share a carrier anchor.");
                    }
                    mutator.Preflight(fields[i], add);
                }
                for (uint i = 0; i < fields.Length; i++) {
                    attempted = i + 1;
                    mutator.Change(fields[i], add);
                    Fields::Require(mutator.Exists(fields[i]) == add, "A water field did not change as expected.");
                }
                result.success = true;
                result.changed = fields;
                return result;
            } catch {
                result.error = getExceptionInfo();
            }

            for (int i = int(attempted) - 1; i >= 0; i--) {
                try {
                    if (mutator.Exists(fields[i]) == add) mutator.Change(fields[i], !add);
                } catch {
                    result.error += " Rollback: " + getExceptionInfo();
                }
            }
            for (uint i = 0; i < attempted; i++) {
                try {
                    if (mutator.Exists(fields[i]) == add) result.changed.InsertLast(fields[i]);
                } catch {
                    result.changed.InsertLast(fields[i]);
                    result.error += " Could not verify " + fields[i].stem + "; retained in history.";
                }
            }
            if (result.changed.Length > 0) result.error += " Remaining changes are kept in water history.";
            return result;
        }

        namespace History {
            class Edit {
                array<WaterFields::Fields::Field@> fields;
                bool added;

                Edit(const array<WaterFields::Fields::Field@> &in fields, bool added) {
                    for (uint i = 0; i < fields.Length; i++) {
                        auto copy = WaterFields::Fields::Field();
                        copy = fields[i];
                        this.fields.InsertLast(copy);
                    }
                    this.added = added;
                }
            }

            class Stack {
                array<Edit@> undo;
                array<Edit@> redo;
                string mapUid;
                uint64 revision = 0;

                void Reset() {
                    revision++;
                    undo.Resize(0);
                    redo.Resize(0);
                    mapUid = "";
                }

                void Observe(const string &in uid, bool open) {
                    if (!open || uid != mapUid) Reset();
                    if (open) mapUid = uid;
                }

                void Record(const array<WaterFields::Fields::Field@> &in fields, bool added) {
                    if (fields.Length == 0) return;
                    undo.InsertLast(Edit(fields, added));
                    redo.Resize(0);
                }

                BatchResult@ Apply(bool forward, FieldMutator@ mutator) {
                    uint64 captured = revision;
                    auto source = forward ? redo : undo;
                    Fields::Require(source.Length > 0, forward ? "Nothing to redo." : "Nothing to undo.");
                    auto edit = source[source.Length - 1];
                    auto result = ApplyBatch(edit.fields, forward ? edit.added :!edit.added, mutator);
                    if (revision != captured) {
                        result.success = false;
                        result.error += " The map session changed; water history was cleared.";
                        return result;
                    }
                    if (result.changed.Length == 0) return result;
                    array<WaterFields::Fields::Field@> remaining;
                    for (uint i = 0; i < edit.fields.Length; i++) {
                        if (result.changed.FindByRef(edit.fields[i]) < 0) remaining.InsertLast(edit.fields[i]);
                    }
                    auto moved = Edit(result.changed, edit.added);
                    if (forward) {
                        redo.RemoveLast();
                        if (remaining.Length > 0) redo.InsertLast(Edit(remaining, edit.added));
                        undo.InsertLast(moved);
                    } else {
                        undo.RemoveLast();
                        if (remaining.Length > 0) undo.InsertLast(Edit(remaining, edit.added));
                        redo.InsertLast(moved);
                    }
                    return result;
                }
            }

            Stack edits;
        }
    }
}
