namespace WaterFields {
    namespace Ui {
        bool ClipEdge(array<vec3> @edge, const vec3 &in normal, float limit) {
            vec3 a = edge[0], b = edge[1];
            float da = Math::Dot(a, normal) - limit;
            float db = Math::Dot(b, normal) - limit;
            if (da < 0 && db < 0) return false;
            if ((da >= 0) != (db >= 0)) {
                vec3 hit = a + (b - a) * (da / (da - db));
                if (da < 0) {
                    a = hit;
                } else {
                    b = hit;
                }
            }
            edge[0] = a;
            edge[1] = b;
            return true;
        }

        bool Projected(const vec3 &in point) {
            return point.z < 0 && Math::Abs(point.x) < 1e9f && Math::Abs(point.y) < 1e9f;
        }

        void Box(WaterFields::Fields::Field@ field, const vec4 &in color) {
            vec3 camera, forward;
            if (!Authoring::Input::MouseRay(
                (vec2(Display::GetWidth(), Display::GetHeight()) - vec2(1)) / 2,
                camera,
                forward
            )) {
                return;
            }
            float near = Math::Dot(camera, forward) + 0.05f;
            array<vec3> points;
            for (uint i = 0; i < 8; i++) {
                vec3 corner(
                    (i & 1) > 0 ? field.size.x : 0,
                    (i & 2) > 0 ? field.size.y : 0,
                    (i & 4) > 0 ? field.size.z : 0
                );
                points.InsertLast(field.minimum + corner);
            }
            array<vec3> planes = {vec3(1, 0, 0), vec3(-1, 0, 0), vec3(0, 1, 0), vec3(0, -1, 0)};
            array<float> limits = {0, -float(Display::GetWidth()), 0, -float(Display::GetHeight())};
            nvg::BeginPath();
            for (uint i = 0; i < 8; i++) {
                for (uint bit = 1; bit <= 4; bit *= 2) {
                    uint j = i ^ bit;
                    if (j < i) continue;
                    array<vec3> edge = {points[i], points[j]};
                    if (!ClipEdge(edge, forward, near)) continue;
                    edge[0] = Camera::ToScreen(edge[0]);
                    edge[1] = Camera::ToScreen(edge[1]);
                    if (!Projected(edge[0]) || !Projected(edge[1])) continue;
                    bool visible = true;
                    for (uint k = 0; k < 4; k++) {
                        if (!ClipEdge(edge, planes[k], limits[k])) {
                            visible = false;
                            break;
                        }
                    }
                    if (visible) {
                        nvg::MoveTo(edge[0].xy);
                        nvg::LineTo(edge[1].xy);
                    }
                }
            }
            nvg::StrokeWidth(2);
            nvg::StrokeColor(color);
            nvg::Stroke();
        }

        void RenderPreview() {
            if (!App::initialized ||
                Authoring::ReadSnapshot().state != WaterFields::Authoring::SessionState::Ready) return;
            bool active = Authoring::Input::activeTool != Authoring::Input::Tool::Off;
            if (!active && !App::S_PreviewOutsideMode) return;
            nvg::Save();
            DrawRegions(active);
            if (active &&
                Authoring::Input::hasHit &&
                Authoring::Input::activeTool == Authoring::Input::Tool::Draw
            ) {
                bool valid = true;
                auto field = Authoring::Input::preview;
                try {
                    Fields::Validate(field);
                    Fields::ValidateMapBounds(field, GetApp().RootMap.Size);
                } catch {
                    valid = false;
                }
                Box(field, valid ? vec4(0.4, 1, 0.7, 1) : vec4(1, 0.3, 0.2, 1));
            }
            nvg::Restore();
        }

        void DrawRegions(bool active) {
            WaterFields::Fields::Regions@ regions = Authoring::Input::regions;
            int selected = -1;
            if (active) {
                for (uint i = 0; i < Authoring::Input::placedFields.Length; i++) {
                    if (Authoring::SameField(Authoring::Input::placedFields[i], Authoring::Input::hoveredField)) {
                        selected = regions.membership[i];
                        break;
                    }
                }
            }
            vec3 camera, forward;
            if (!Authoring::Input::MouseRay(
                (vec2(Display::GetWidth(), Display::GetHeight()) - vec2(1)) / 2,
                camera,
                forward
            )) {
                return;
            }
            float near = Math::Dot(camera, forward) + 0.05f;
            array<vec3> planes = {vec3(1, 0, 0), vec3(-1, 0, 0), vec3(0, 1, 0), vec3(0, -1, 0)};
            array<float> limits = {0, -float(Display::GetWidth()), 0, -float(Display::GetHeight())};
            for (uint i = 0; i < regions.edges.Length; i++) {
                auto line = regions.edges[i];
                array<vec3> edge = {line.start, line.end};
                if (!ClipEdge(edge, forward, near)) continue;
                edge[0] = Camera::ToScreen(edge[0]);
                edge[1] = Camera::ToScreen(edge[1]);
                if (!Projected(edge[0]) || !Projected(edge[1])) continue;
                bool visible = true;
                for (uint j = 0; j < planes.Length; j++) {
                    if (!ClipEdge(edge, planes[j], limits[j])) {
                        visible = false;
                        break;
                    }
                }
                if (!visible) continue;
                nvg::BeginPath();
                nvg::MoveTo(edge[0].xy);
                nvg::LineTo(edge[1].xy);
                nvg::StrokeWidth(2);
                nvg::StrokeColor(line.region == selected ? vec4(1, 0.3, 0.2, 1) : vec4(0.2, 0.7, 1, 0.65));
                nvg::Stroke();
            }
        }
    }
}
