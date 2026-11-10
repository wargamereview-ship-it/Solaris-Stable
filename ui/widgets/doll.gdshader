shader_type canvas_item;
// A targeting-computer readout of a unit. TEXTURE is the unit's grey art (assets/dolls/*_shade.png,
// from tools/dolls/build_doll_maps.py); id_tex says which armor location each pixel belongs to
// (red = id * 20). The art is reduced to glowing line work: its detail edges and the outline of
// every location in that location's status color, a thin inner trace in the color of its internal
// structure, a faint phosphor fill, scanlines and a slow scan sweep. Stripped armor blinks,
// destroyed locations drop to a dim red flicker, fresh hits flash white. Art that is line work
// already (the 'Mech: white lines on black) sets line_art and has its own lines lit instead.

uniform sampler2D id_tex : filter_nearest;
uniform vec4 armor_col[12];
uniform vec4 struct_col[12];
uniform float state[12];     // 0 fine, 1 armor stripped, 2 destroyed, 3 not a location (plain hull)
uniform float flash[12];
uniform float dim[12];       // pushed back (the rear view's arms and legs)
uniform int hi = -1;
uniform vec4 hi_col : source_color = vec4(0.96, 0.64, 0.2, 1.0);
uniform float tpp = 1.0;     // art texels per screen pixel
uniform float band = 2.6;    // how far inside a location its structure trace runs, in screen pixels
uniform float phase = 0.0;   // offsets the sweep so dolls side by side don't pulse together
uniform bool line_art = false;  // the art is already line work: glow its lines ("line_art" in dolls.json)

int id_at(vec2 uv) {
	vec4 c = texture(id_tex, uv);
	return c.a < 0.5 ? 0 : clamp(int(round(c.r * 12.75)), 0, 11);
}

float lum(sampler2D tex, vec2 uv, float lod) {
	vec4 c = textureLod(tex, uv, lod);
	return dot(c.rgb, vec3(0.3, 0.55, 0.15)) * c.a;
}

vec3 loc_col(int j) {
	float st = state[j];
	if (st > 2.5) {
		return vec3(0.3, 0.55, 0.62) * 0.75;
	}
	if (st > 1.5) {
		return vec3(0.8, 0.14, 0.09);
	}
	return armor_col[j].rgb;
}

void fragment() {
	vec2 ts = vec2(textureSize(id_tex, 0));
	vec2 px = tpp / ts;
	float lod = max(0.0, log2(max(1.0, tpp)) - (line_art ? 0.3 : 0.4));
	int id = id_at(UV);
	float scan = 0.84 + 0.16 * step(0.5, fract(FRAGCOORD.y * 0.5));
	float sweep = exp(-pow((fract(TIME * 0.16 + phase) * 1.5 - 0.25 - UV.y) * 10.0, 2.0));
	if (id == 0) {
		// a phosphor glow around the silhouette, in the color of the location it surrounds
		vec3 g = vec3(0.0);
		float n = 0.0;
		for (int k = 0; k < 8; k++) {
			float a = float(k) * 0.785398;
			int j = id_at(UV + vec2(cos(a), sin(a)) * px * 2.4);
			if (j != 0) {
				g += loc_col(j);
				n += 1.0;
			}
		}
		COLOR = n > 0.0 ? vec4(g / n, n / 8.0 * 0.32 * scan) : vec4(0.0);
	} else {
		bool edge = false;
		bool near_b = false;
		bool past_b = false;
		for (int k = 0; k < 12; k++) {
			float a = float(k) * 0.523599;
			vec2 d = vec2(cos(a), sin(a)) * px;
			if (id_at(UV + d * 1.0) != id) {
				edge = true;
			}
			if (id_at(UV + d * band) != id || id_at(UV + d * band * 0.55) != id) {
				near_b = true;
			}
			if (id_at(UV + d * (band + 1.1)) != id) {
				past_b = true;
			}
		}
		bool trace = past_b && !near_b;
		float l0 = lum(TEXTURE, UV, lod);
		float gx = lum(TEXTURE, UV + vec2(px.x, 0.0), lod) - lum(TEXTURE, UV - vec2(px.x, 0.0), lod);
		float gy = lum(TEXTURE, UV + vec2(0.0, px.y), lod) - lum(TEXTURE, UV - vec2(0.0, px.y), lod);
		float detail = line_art ? smoothstep(0.08, 0.42, l0) : smoothstep(0.04, 0.2, length(vec2(gx, gy)));
		float st = state[id];
		vec3 c = loc_col(id);
		float glow = line_art ? 0.07 + detail * 0.9 : 0.08 + 0.12 * l0 + detail * 0.62;
		vec3 col = c * glow;
		if (trace && st < 1.5) {
			col = mix(col, struct_col[id].rgb, 0.85);
		}
		if (edge) {
			col = c * 1.15;
		}
		col += c * sweep * 0.22;
		if (st > 1.5 && st < 2.5) {
			col *= (0.5 + 0.5 * step(0.32, fract(TIME * 2.3 + float(id) * 0.37))) * (edge ? 1.0 : 0.55);
		} else if (st > 0.5 && st < 1.5) {
			col *= 0.65 + 0.35 * step(0.5, fract(TIME * 1.7));
		}
		col *= 1.0 - 0.6 * dim[id];
		col = mix(col, vec3(1.0, 0.98, 0.92), flash[id] * 0.8);
		if (id == hi) {
			col = edge ? hi_col.rgb : col + hi_col.rgb * 0.16;
		}
		COLOR = vec4(col * scan, max(0.35, textureLod(TEXTURE, UV, lod).a));
	}
}
