shader_type canvas_item;
// GPU Voronoi / metaball faction territories evaluated per screen pixel from a spatial grid texture.
// Produces smooth, non-overlapping borders between neighboring realms, organic outer rims,
// subtle frontier hatching, and pulsing contested borders along active war fronts.

uniform sampler2D cell_tex : filter_nearest;
uniform sampler2D war_tex : filter_nearest;
uniform vec2 view_size = vec2(1000.0, 800.0);
uniform vec2 center = vec2(0.0, 0.0);
uniform float zoom = 1.25;
uniform float time = 0.0;

const vec2 SPACE_MIN = vec2(-1920.0, -2048.0);
const float GRID_STEP = 32.0;
const int GRID_W = 128;
const int GRID_H = 128;
const int MAX_SLOTS = 64;
const int CELL_ROWS = 32;
const int MAX_FACS = 12;
const vec2 CELL_TEX_SIZE = vec2(512.0, 4096.0);
const float DISC_R = 25.0;
const float OUTER_THRESH = 0.17;

vec4 fetch_cell(int x, int y) {
	return texture(cell_tex, (vec2(float(x), float(y)) + 0.5) / CELL_TEX_SIZE);
}

void fragment() {
	vec2 px = UV * view_size;
	vec2 d_screen = (px - view_size * 0.5) / max(zoom, 0.05);
	vec2 ly = vec2(center.x + d_screen.x, center.y - d_screen.y);

	ivec2 cell = ivec2(floor((ly - SPACE_MIN) / GRID_STEP));
	if (cell.x < 0 || cell.x >= GRID_W || cell.y < 0 || cell.y >= GRID_H) {
		COLOR = vec4(0.0);
	} else {
		int f_id[MAX_FACS];
		vec3 f_col[MAX_FACS];
		float f_sum[MAX_FACS];
		int n_fac = 0;
		for (int i = 0; i < MAX_FACS; i++) {
			f_id[i] = 0;
			f_col[i] = vec3(0.0);
			f_sum[i] = 0.0;
		}

		int base_row = cell.y * CELL_ROWS;
		int base_col = cell.x * 4;

		for (int k = 0; k < MAX_SLOTS; k++) {
			int row = base_row + (k >> 1);
			int col_x0 = base_col + (k & 1) * 2;
			int col_x1 = col_x0 + 1;
			vec4 t1 = fetch_cell(col_x1, row);
			if (t1.a <= 0.001) {
				break;
			}
			vec4 t0 = fetch_cell(col_x0, row);
			float ux = (t0.r * 65280.0 + t0.g * 255.0) / 65535.0;
			float uy = (t0.b * 65280.0 + t0.a * 255.0) / 65535.0;
			vec2 spos = SPACE_MIN + vec2(ux, uy) * 4096.0;
			float dist = length(ly - spos);
			if (dist >= DISC_R) {
				continue;
			}
			float t = 1.0 - dist / DISC_R;
			float w = t * t * (3.0 - 2.0 * t);
			float w3 = w * w * w;
			int fid = int(t1.a * 255.0 + 0.5);

			int slot = -1;
			for (int s = 0; s < n_fac; s++) {
				if (f_id[s] == fid) {
					slot = s;
					break;
				}
			}
			if (slot < 0 && n_fac < MAX_FACS) {
				slot = n_fac;
				n_fac++;
				f_id[slot] = fid;
				f_col[slot] = t1.rgb;
			}
			if (slot >= 0) {
				f_sum[slot] += w3;
			}
		}

		int top_s = -1;
		int sec_s = -1;
		float top_v = 0.0;
		float sec_v = 0.0;
		for (int s = 0; s < n_fac; s++) {
			float v = pow(f_sum[s], 0.3333333);
			if (v > top_v) {
				sec_v = top_v;
				sec_s = top_s;
				top_v = v;
				top_s = s;
			} else if (v > sec_v) {
				sec_v = v;
				sec_s = s;
			}
		}

		if (top_s < 0 || top_v <= OUTER_THRESH) {
			COLOR = vec4(0.0);
		} else {
			vec3 col = f_col[top_s];
			float outer_ly = (top_v - OUTER_THRESH) * DISC_R;
			float nb_weight = (sec_s >= 0) ? smoothstep(OUTER_THRESH * 0.55, OUTER_THRESH * 0.95, sec_v) : 0.0;
			float meet_ly = (sec_s >= 0) ? (top_v - sec_v) * DISC_R * 0.52 : 999.0;

			float outer_px = outer_ly * zoom;
			float meet_px = meet_ly * zoom;

			// Anti-aliased territory coverage mask
			float mask = smoothstep(-0.75, 0.75, outer_px);

			// Frontier inner glow and subtle diagonal tactical hatching near borders (smoothly weighted)
			float inner_band = max(exp(-outer_ly / 6.5), exp(-meet_ly / 6.5) * nb_weight);
			float hatch = 0.5 + 0.5 * sin((px.x - px.y) * 0.85);
			float hatch_boost = inner_band * (0.035 * hatch);

			// Crisp border lines (screen-space pixel width so they stay sharp at every zoom)
			float meet_line = smoothstep(2.0, 0.35, meet_px) * nb_weight;
			float rim_line = smoothstep(1.8, 0.25, abs(outer_px - 0.6)) * (1.0 - meet_line);

			// Check if the two bordering factions are actively at war
			float war = 0.0;
			if (sec_s >= 0 && nb_weight > 0.001) {
				vec2 wuv = (vec2(float(f_id[top_s]), float(f_id[sec_s])) + 0.5) / 256.0;
				war = texture(war_tex, wuv).r;
			}
			float pulse = 0.55 + 0.45 * sin(time * 3.2);
			float war_band = war * exp(-meet_ly / 4.2) * nb_weight;

			vec3 fill_col = col * (0.92 + 0.25 * inner_band);
			vec3 border_col = mix(col * 1.38 + vec3(0.14), vec3(1.0, 0.48, 0.28), war * 0.55 * pulse);
			vec3 final_col = mix(fill_col, border_col, clamp(meet_line + rim_line * 0.7 + war_band * 0.35, 0.0, 1.0));

			float base_a = 0.105 + inner_band * 0.11 + hatch_boost + war_band * 0.08 * pulse;
			float line_a = meet_line * (0.72 + war * 0.18) + rim_line * 0.36;
			float a = clamp(base_a + line_a, 0.0, 0.92) * mask;

			COLOR = vec4(final_col, a);
		}
	}
}
