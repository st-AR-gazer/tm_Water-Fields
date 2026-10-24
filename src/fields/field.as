namespace WaterFields {
    namespace Fields {
        const float maxHorizontalSize = 2048;
        const float maxHeight = 256;

        class Field {
            vec3 minimum;
            vec3 size;
            int3 anchor;
            string stem;
            uint variant = 0;
            bool isGround = false;

            vec3 LocalOrigin() const {
                return minimum - vec3(float(anchor.x) * 32, (float(anchor.y) - 8) * 8, float(anchor.z) * 32);
            }

            string ModelId() const {
                return stem + ".Block.Gbx_CustomBlock";
            }
        }

        void Require(bool valid, const string &in message) {
            if (!valid) throw(message);
        }

        bool InRange(const vec3 &in point, const nat3 &in mapSize) {
            return point.x >= 0 && point.x <= float(mapSize.x) * 32 && point.z >= 0 && point.z <= float(mapSize.z) * 32;
        }

        void ValidateMapBounds(Field@ field, const nat3 &in mapSize) {
            Require(
                App::S_AllowOutsideMapBorders ||
                (InRange(field.minimum, mapSize) && InRange(field.minimum + field.size, mapSize)),
                "Water must stay inside the map borders. Enable 'Allow water outside map borders' in General settings to extend it outside."
            );
        }

        void Validate(Field@ field) {
            Require(
                field !is null,
                "Missing water bounds."
            );
            Require(
                field.size.x >= 0.25f &&
                field.size.x <= maxHorizontalSize &&
                field.size.y >= 0.25f &&
                field.size.y <= maxHeight &&
                field.size.z >= 0.25f &&
                field.size.z <= maxHorizontalSize,
                "Water dimensions must be at least 0.25 m, with width/depth up to 2048 m and height up to 256 m."
            );
            auto origin = field.LocalOrigin();
            Require(
                origin.x > -16384 &&
                origin.x < 16384 &&
                origin.y > -16384 &&
                origin.y < 16384 &&
                origin.z > -16384 &&
                origin.z < 16384,
                "The carrier anchor is too far from the water bounds."
            );
            Require(
                field.variant < uint(field.isGround ? 4 : 6),
                "Unsupported water variant."
            );
        }

        Json::Value@ Vector(const vec3 &in value) {
            auto result = Json::Array();
            result.Add(value.x);
            result.Add(value.y);
            result.Add(value.z);
            return result;
        }
    }
}
