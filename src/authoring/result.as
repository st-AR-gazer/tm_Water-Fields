namespace WaterFields {
    namespace Authoring {
        class Result {
            Fields::Field@ field = Fields::Field();
            string generation = "not-started";
            string placement = "not-attempted";
            string error;
            string receiptError;
            string assetRoot;
            string recordPath;
            string nativeBytes;
            string wrapperBytes;
            string prefabBytes;
            string mapUid;
            string mapFileName;

            Json::Value@ Record() const {
                auto record = Json::Object();
                record["schema"] = "waterfields-generation-v1";
                record["authoringVersion"] = PluginMeta.Version;
                record["stem"] = field.stem;
                record["minimum"] = Fields::Vector(field.minimum);
                record["size"] = Fields::Vector(field.size);
                record["anchor"] = Fields::Vector(vec3(field.anchor.x, field.anchor.y, field.anchor.z));
                record["localOrigin"] = Fields::Vector(field.LocalOrigin());
                record["generation"] = generation;
                record["placement"] = placement;
                record["placedVariant"] = field.variant;
                record["placedGround"] = field.isGround;
                record["mapUid"] = mapUid;
                record["mapFileName"] = mapFileName;
                record["templateSchema"] = "water-area-generator-assets-v28";
                record["nativeByteCount"] = nativeBytes.Length;
                record["wrapperByteCount"] = wrapperBytes.Length;
                record["prefabByteCount"] = prefabBytes.Length;
                record["error"] = error;
                record["mapSaves"] = 0;
                return record;
            }

            void Save() {
                if (recordPath.Length == 0) return;
                string bytes = Json::Write(Record());
                IO::File file(recordPath, IO::FileMode::Write);
                file.Write(bytes);
                file.Close();
                Fields::Require(_IO::File::ReadBinary(recordPath) == bytes, "Generation record verification failed.");
            }

            string Summary() const {
                string summary = "Assets: " + generation + ". Placement: " + placement + ".";
                if (field.stem.Length > 0) summary += " " + field.stem + ".";
                if (error.Length > 0) summary += " " + error;
                if (receiptError.Length > 0) summary += " Record could not be updated: " + receiptError;
                return summary;
            }
        }

        Result@ g_lastResult;
    }
}
