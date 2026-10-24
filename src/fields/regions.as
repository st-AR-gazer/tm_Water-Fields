namespace WaterFields {
    namespace Fields {
        float Axis(const vec3 &in point, uint axis) {
            if (axis == 0) return point.x;
            if (axis == 1) return point.y;
            return point.z;
        }

        vec3 Point(uint axis, float plane, float u, float v) {
            if (axis == 0) return vec3(plane, u, v);
            if (axis == 1) return vec3(v, plane, u);
            return vec3(u, v, plane);
        }

        bool Joined(Field@ a, Field@ b) {
            uint positive = 0;
            for (uint axis = 0; axis < 3; axis++) {
                float overlap = Math::Min(Axis(a.minimum + a.size, axis), Axis(b.minimum + b.size, axis)) -
                                Math::Max(Axis(a.minimum, axis), Axis(b.minimum, axis));
                if (overlap < 0) return false;
                if (overlap > 0) positive++;
            }
            return positive >= 2;
        }

        array<uint> Connected(const array<Field@> &in fields, uint seed) {
            array<uint> members;
            if (seed >= fields.Length) return members;
            array<bool> seen(fields.Length, false);
            members.InsertLast(seed);
            seen[seed] = true;
            for (uint head = 0; head < members.Length; head++) {
                for (uint i = 0; i < fields.Length; i++) {
                    if (!seen[i] && Joined(fields[members[head]], fields[i])) {
                        seen[i] = true;
                        members.InsertLast(i);
                    }
                }
            }
            return members;
        }

        array<vec4> SubtractRect(const vec4 &in rect, const vec4 &in cut) {
            array<vec4> pieces;
            float x0 = Math::Max(rect.x, cut.x), y0 = Math::Max(rect.y, cut.y);
            float x1 = Math::Min(rect.z, cut.z), y1 = Math::Min(rect.w, cut.w);
            if (x0 >= x1 || y0 >= y1) {
                pieces.InsertLast(rect);
                return pieces;
            }
            if (rect.x < x0) pieces.InsertLast(vec4(rect.x, rect.y, x0, rect.w));
            if (x1 < rect.z) pieces.InsertLast(vec4(x1, rect.y, rect.z, rect.w));
            if (rect.y < y0) pieces.InsertLast(vec4(x0, rect.y, x1, y0));
            if (y1 < rect.w) pieces.InsertLast(vec4(x0, y1, x1, rect.w));
            return pieces;
        }

        class Face {
            uint axis;
            int region;
            float plane;
            vec4 rect;

            array<vec3> Vertices() const {
                return {
                    Point(axis, plane, rect.x, rect.y),
                    Point(axis, plane, rect.z, rect.y),
                    Point(axis, plane, rect.z, rect.w),
                    Point(axis, plane, rect.x, rect.w)
                };
            }
        }

        class Edge {
            vec3 start;
            vec3 end;
            uint axis;
            uint faceAxis;
            int region;
            float plane;

            Edge() { }

            Edge(const vec3 &in a, const vec3 &in b, Face@ face) {
                if (a.x != b.x) {
                    axis = 0;
                } else if (a.y != b.y) {
                    axis = 1;
                } else {
                    axis = 2;
                }
                bool ordered = Axis(a, axis) < Axis(b, axis);
                start = ordered ? a : b;
                end = ordered ? b : a;
                faceAxis = face.axis;
                plane = face.plane;
                region = face.region;
            }

            bool Collinear(Edge@ other) const {
                return region == other.region &&
                       axis == other.axis &&
                       Axis(start, (axis + 1) % 3) == Axis(other.start, (axis + 1) % 3) &&
                       Axis(start, (axis + 2) % 3) == Axis(other.start, (axis + 2) % 3);
            }

            int opCmp(const Edge &in other) const {
                if (region != other.region) return region < other.region ? -1 : 1;
                if (axis != other.axis) return axis < other.axis ? -1 : 1;
                for (uint i = 1; i <= 2; i++) {
                    float a = Axis(start, (axis + i) % 3), b = Axis(other.start, (axis + i) % 3);
                    if (a != b) return a < b ? -1 : 1;
                }
                return 0;
            }
        }

        array<vec2> SubtractIntervals(const array<vec2> &in parts, float low, float high) {
            array<vec2> next;
            for (uint i = 0; i < parts.Length; i++) {
                auto part = parts[i];
                float start = Math::Max(part.x, low), end = Math::Min(part.y, high);
                if (start >= end) {
                    next.InsertLast(part);
                } else {
                    if (part.x < start) next.InsertLast(vec2(part.x, start));
                    if (end < part.y) next.InsertLast(vec2(end, part.y));
                }
            }
            return next;
        }

        class Regions {
            array<int> membership;
            array<Face@> faces;
            array<Edge@> edges;
            uint count = 0;

            void Rebuild(const array<Field@> &in fields) {
                membership = array<int>(fields.Length, -1);
                faces.Resize(0);
                edges.Resize(0);
                count = 0;
                for (uint i = 0; i < fields.Length; i++) {
                    if (membership[i] != -1) continue;
                    auto members = Connected(fields, i);
                    for (uint j = 0; j < members.Length; j++) membership[members[j]] = int(count);
                    count++;
                }
                for (uint i = 0; i < fields.Length; i++) {
                    for (uint axis = 0; axis < 3; axis++) {
                        for (uint side = 0; side < 2; side++) BuildFace(fields, i, axis, side);
                    }
                }
                BuildEdges();
            }

            void BuildEdges() {
                array<Edge@> raw;
                for (uint i = 0; i < faces.Length; i++) {
                    auto points = faces[i].Vertices();
                    for (uint j = 0; j < 4; j++) raw.InsertLast(Edge(points[j], points[(j + 1) % 4], faces[i]));
                }
                raw.SortAsc();
                uint first = 0, last = 0, emitted = 0;
                for (uint i = 0; i < raw.Length; i++) {
                    auto edge = raw[i];
                    if (i == last) {
                        first = i;
                        emitted = edges.Length;
                        last = i + 1;
                        while (last < raw.Length && edge.Collinear(raw[last])) last++;
                    }
                    array<vec2> parts = {vec2(Axis(edge.start, edge.axis), Axis(edge.end, edge.axis))};
                    for (uint j = first; j < last && parts.Length > 0; j++) {
                        auto other = raw[j];
                        if (i != j &&
                            edge.faceAxis == other.faceAxis &&
                            edge.plane == other.plane &&
                            edge.Collinear(other)
                        ) {
                            parts = SubtractIntervals(
                                parts,
                                Axis(other.start, edge.axis),
                                Axis(other.end, edge.axis)
                            );
                        }
                    }
                    for (uint j = emitted; j < edges.Length && parts.Length > 0; j++) {
                        if (edge.Collinear(edges[j])) {
                            parts = SubtractIntervals(
                                parts,
                                Axis(edges[j].start, edge.axis),
                                Axis(edges[j].end, edge.axis)
                            );
                        }
                    }
                    for (uint j = 0; j < parts.Length; j++) {
                        auto piece = Edge();
                        piece = edge;
                        vec3 direction = (edge.end - edge.start) /
                                         (Axis(edge.end, edge.axis) - Axis(edge.start, edge.axis));
                        piece.start = edge.start + direction * (parts[j].x - Axis(edge.start, edge.axis));
                        piece.end = edge.start + direction * (parts[j].y - Axis(edge.start, edge.axis));
                        edges.InsertLast(piece);
                    }
                }
            }

            void BuildFace(const array<Field@> &in fields, uint index, uint axis, uint side) {
                auto field = fields[index];
                vec3 high = field.minimum + field.size;
                uint u = (axis + 1) % 3, v = (axis + 2) % 3;
                float plane = Axis(side == 0 ? field.minimum : high, axis);
                array<vec4> patches = {
                    vec4(Axis(field.minimum, u), Axis(field.minimum, v), Axis(high, u), Axis(high, v))
                };
                for (uint i = 0; i < fields.Length && patches.Length > 0; i++) {
                    if (i == index || membership[i] != membership[index]) continue;
                    auto other = fields[i];
                    vec3 otherHigh = other.minimum + other.size;
                    float low = Axis(other.minimum, axis), top = Axis(otherHigh, axis);
                    bool hidden = side == 0 ? low < plane && top >= plane : top > plane && low <= plane;
                    bool duplicate = i < index && (side == 0 ? low == plane : top == plane);
                    if (!hidden && !duplicate) continue;
                    vec4 cut(Axis(other.minimum, u), Axis(other.minimum, v), Axis(otherHigh, u), Axis(otherHigh, v));
                    array<vec4> next;
                    for (uint j = 0; j < patches.Length; j++) {
                        auto pieces = SubtractRect(patches[j], cut);
                        for (uint k = 0; k < pieces.Length; k++) next.InsertLast(pieces[k]);
                    }
                    patches = next;
                }
                for (uint i = 0; i < patches.Length; i++) {
                    auto face = Face();
                    face.axis = axis;
                    face.region = membership[index];
                    face.plane = plane;
                    face.rect = patches[i];
                    faces.InsertLast(face);
                }
            }
        }
    }
}
