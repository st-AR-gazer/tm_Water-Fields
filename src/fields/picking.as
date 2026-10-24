namespace WaterFields {
    namespace Fields {
        float CellMinimum(float value, float scale) {
            return Math::Floor(value / scale) * scale;
        }

        void DrawBounds(
            const vec3 &in start,
            const vec3 &in hit,
            float scale,
            int height,
            vec3 &out minimum,
            vec3 &out size
        ) {
            float extent = (Math::Floor(maxHorizontalSize / scale) - 1) * scale;
            float dx = Math::Clamp(hit.x - start.x, -extent, extent);
            float dz = Math::Clamp(hit.z - start.z, -extent, extent);
            int layers = Math::Clamp(height, 1, int(Math::Floor(maxHeight / scale)));
            minimum = start + vec3(Math::Min(0.0f, dx), 0, Math::Min(0.0f, dz));
            size = vec3(Math::Abs(dx) + scale, float(layers) * scale, Math::Abs(dz) + scale);
        }

        bool PlaneHit(const vec3 &in origin, const vec3 &in direction, float y, vec3 &out hit) {
            if (Math::Abs(direction.y) < 0.000001f) return false;
            float distance = (y - origin.y) / direction.y;
            if (!(distance >= 0 && distance < 100000)) return false;
            hit = origin + direction * distance;
            return true;
        }

        bool BoxHit(
            const vec3 &in origin,
            const vec3 &in direction,
            const vec3 &in minimum,
            const vec3 &in size,
            float &out near
        ) {
            if (direction.LengthSquared() < 0.000001f) return false;
            near = 0;
            float far = 100000;
            array<float> origins = {origin.x, origin.y, origin.z};
            array<float> directions = {direction.x, direction.y, direction.z};
            array<float> low = {minimum.x, minimum.y, minimum.z};
            array<float> high = {minimum.x + size.x, minimum.y + size.y, minimum.z + size.z};

            for (uint i = 0; i < 3; i++) {
                if (Math::Abs(directions[i]) < 0.000001f) {
                    if (origins[i] < low[i] || origins[i] > high[i]) return false;
                    continue;
                }

                float a = (low[i] - origins[i]) / directions[i];
                float b = (high[i] - origins[i]) / directions[i];
                near = Math::Max(near, Math::Min(a, b));
                far = Math::Min(far, Math::Max(a, b));
                if (far < near) return false;
            }

            return far >= 0;
        }
    }
}
