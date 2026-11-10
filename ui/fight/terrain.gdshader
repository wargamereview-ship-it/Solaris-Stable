shader_type canvas_item;
// The battlefield ground, drawn on the GPU from per-cell data textures (one texel per 10 m cell).
// Terrain types blend along noise-warped edges so the 10 m grid never shows; hillshading and contour
// lines come from the height channel; water ripples and foams at the shore; buildings cast shadows;
// ash, rubble and fire glow come from a live texture the viewer updates as the fight goes on.

uniform sampler2D data_a : filter_linear, repeat_disable;   // light woods, heavy woods, rough, rubble
uniform sampler2D data_b : filter_linear, repeat_disable;   // water depth, pavement, height, building height
uniform sampler2D data_c : filter_linear, repeat_disable;   // ash, fire, collapsed rubble, scorch
uniform sampler2D noise : filter_linear_mipmap, repeat_enable;
uniform sampler2D grain : filter_linear_mipmap, repeat_enable;
uniform vec2 cells = vec2(50.0, 40.0);
uniform float max_level = 8.0;
uniform vec4 ground_a : source_color = vec4(0.45, 0.5, 0.3, 1.0);
uniform vec4 ground_b : source_color = vec4(0.38, 0.44, 0.26, 1.0);
uniform vec4 dirt : source_color = vec4(0.48, 0.42, 0.32, 1.0);
uniform vec4 rock : source_color = vec4(0.5, 0.48, 0.44, 1.0);
uniform vec4 forest_floor : source_color = vec4(0.2, 0.27, 0.15, 1.0);
uniform vec4 water_shallow : source_color = vec4(0.2, 0.38, 0.46, 1.0);
uniform vec4 water_deep : source_color = vec4(0.07, 0.17, 0.28, 1.0);
uniform vec4 asphalt : source_color = vec4(0.27, 0.28, 0.3, 1.0);
uniform vec4 rubble_col : source_color = vec4(0.42, 0.4, 0.37, 1.0);
uniform vec4 ash_col : source_color = vec4(0.13, 0.12, 0.11, 1.0);
uniform float snow = 0.0;
uniform float sand = 0.0;
uniform float paved_floor = 0.0;   // arena floors (factory, urban): concrete slabs
uniform float night = 0.0;

float luma(vec3 c) { return dot(c, vec3(0.299, 0.587, 0.114)); }

void fragment() {
	vec2 cell = UV * cells;
	vec2 px = 1.0 / cells;
	float n1 = texture(noise, cell * 0.021).r;
	float n2 = texture(noise, cell * 0.083 + 0.37).r;
	float n3 = texture(grain, cell * 0.55).r;
	float n4 = texture(grain, cell * 2.3 + 0.11).r;
	vec2 warp = (vec2(texture(noise, cell * 0.06).r, texture(noise, cell * 0.06 + vec2(0.5, 0.21)).r) - 0.5) * 1.3;
	vec2 suv = (cell + warp) / cells;
	vec4 A = texture(data_a, suv);
	vec4 B = texture(data_b, suv);
	vec4 C = texture(data_c, (cell + warp * 0.6) / cells);
	vec4 Bs = texture(data_b, (cell + warp * 0.12) / cells);   // roads stay straight

	// --- ground
	vec3 g = mix(ground_a.rgb, ground_b.rgb, smoothstep(0.3, 0.7, n1));
	g = mix(g, dirt.rgb, smoothstep(0.6, 0.82, n2) * 0.5);
	if (paved_floor > 0.5) {
		g = mix(ground_a.rgb, ground_b.rgb, n1 * 0.6);
		vec2 slab = abs(fract(cell / 3.0) - 0.5);
		float seam = smoothstep(0.485, 0.5, max(slab.x, slab.y));
		g *= 1.0 - seam * 0.18;
		g = mix(g, g * 0.72, smoothstep(0.74, 0.88, n2) * 0.45);   // oil stains
		g *= 0.95 + n3 * 0.08;
	} else {
		g *= 0.9 + n3 * 0.16 + (n4 - 0.5) * 0.08;
	}
	// woods floor, rough ground, rubble, roads
	float lw = smoothstep(0.32, 0.62, A.r + (n2 - 0.5) * 0.35);
	float hw = smoothstep(0.32, 0.62, A.g + (n2 - 0.5) * 0.35);
	g = mix(g, forest_floor.rgb * (0.85 + n3 * 0.3), max(lw * 0.55, hw * 0.85));
	float rough = smoothstep(0.3, 0.66, A.b + (n4 - 0.5) * 0.5);
	vec3 rk = rock.rgb * (0.7 + n4 * 0.6);
	g = mix(g, rk, rough * 0.8);
	float rub = smoothstep(0.3, 0.6, max(A.a, C.b) + (n4 - 0.5) * 0.4);
	vec3 rb = rubble_col.rgb * (0.55 + n4 * 0.9);
	g = mix(g, rb, rub * 0.92);
	float pave = smoothstep(0.42, 0.58, Bs.g);
	vec3 asp = asphalt.rgb * (0.92 + n4 * 0.14);
	float crack = smoothstep(0.78, 0.82, texture(grain, cell * 0.9).r) * 0.25;
	asp *= 1.0 - crack;
	g = mix(g, asp, pave);
	g *= 1.0 - (pave * (1.0 - pave)) * 1.2;   // kerbs
	// snow and sand cover
	if (snow > 0.0) {
		float cover = snow * smoothstep(0.12, 0.42, n1 + 0.32 - rough * 0.18);
		vec3 sn = vec3(0.86, 0.9, 0.95) * (0.93 + n3 * 0.08);
		g = mix(g, sn, cover * (1.0 - pave * 0.7) * (1.0 - hw * 0.5));
	}
	if (sand > 0.0) {
		float dune = sin(cell.x * 0.35 + n1 * 9.0 + cell.y * 0.12) * 0.5 + 0.5;
		g *= mix(1.0, 0.92 + dune * 0.12, sand);
	}
	// ash and scorch
	float ash = smoothstep(0.25, 0.6, C.r + (n2 - 0.5) * 0.3);
	g = mix(g, ash_col.rgb * (0.7 + n4 * 0.6), ash * 0.92);
	g = mix(g, ash_col.rgb, smoothstep(0.2, 0.7, C.a) * 0.75);

	// --- relief
	float hc = B.b * max_level;
	float hxp = texture(data_b, suv + vec2(px.x, 0.0)).b;
	float hxm = texture(data_b, suv - vec2(px.x, 0.0)).b;
	float hyp = texture(data_b, suv + vec2(0.0, px.y)).b;
	float hym = texture(data_b, suv - vec2(0.0, px.y)).b;
	vec3 nrm = normalize(vec3((hxm - hxp) * max_level * 0.9, (hym - hyp) * max_level * 0.9, 1.0));
	vec3 light = normalize(vec3(-0.55, -0.7, 0.75));
	float shade = clamp(dot(nrm, light), 0.0, 1.0);
	g *= 0.68 + shade * 0.48;
	g *= 0.94 + clamp(hc / max_level, 0.0, 1.0) * 0.16;
	// contour lines between levels
	float lv = hc;
	float fw = max(fwidth(lv), 0.0001);
	float contour = 1.0 - smoothstep(0.0, fw * 1.4, abs(fract(lv - 0.5) - 0.5));
	contour *= smoothstep(0.02, 0.2, fw * 40.0);
	g *= 1.0 - contour * 0.22 * (1.0 - pave);

	// --- water
	float wv = B.r + (n2 - 0.5) * 0.14;
	float water = smoothstep(0.2, 0.36, wv);
	float deep = smoothstep(0.55, 0.85, B.r);
	vec2 flow = vec2(TIME * 0.02, TIME * 0.012);
	float r1 = texture(noise, cell * 0.09 + flow).r;
	float r2 = texture(noise, cell * 0.13 - flow * 1.3 + 0.5).r;
	vec3 wc = mix(water_shallow.rgb, water_deep.rgb, deep);
	wc *= 0.93 + (r1 - r2) * 0.16;
	float glint = smoothstep(0.035, 0.0, abs(r1 - r2)) * (1.0 - night * 0.7) * 0.6;
	wc += vec3(0.55, 0.65, 0.7) * glint * 0.12;
	float shore = smoothstep(0.2, 0.3, wv) * (1.0 - smoothstep(0.3, 0.5, wv));
	float foam = shore * (0.55 + 0.45 * sin(TIME * 1.7 + n2 * 25.0 + cell.x * 0.3));
	vec3 bank = mix(g, dirt.rgb * 0.85, 0.5);
	g = mix(g, bank, smoothstep(0.1, 0.25, wv) * (1.0 - water));
	g = mix(g, wc, water);
	g += vec3(0.8, 0.85, 0.9) * foam * 0.22 * water;

	// --- buildings: contact darkening and cast shadows (toward the bottom right)
	float bld = texture(data_b, (cell) / cells).a;
	float ao = smoothstep(0.0, 0.6, texture(data_b, (cell + vec2(0.35, 0.35)) / cells).a);
	g *= 1.0 - ao * 0.22;
	float sh = 0.0;
	for (int s = 1; s <= 5; s++) {
		float d = float(s) * 0.45;
		float bh = texture(data_b, (cell - vec2(0.62, 0.78) * d) / cells).a * 5.0;
		sh = max(sh, step(d * 0.9, bh * 1.05) * (1.0 - float(s) * 0.08));
	}
	g *= 1.0 - sh * 0.38;

	// --- fire glow on the ground
	g += vec3(1.0, 0.42, 0.08) * C.g * (0.28 + 0.12 * sin(TIME * 9.0 + n2 * 30.0)) * (0.5 + night);

	// --- light
	if (night > 0.0) {
		vec3 nightc = vec3(luma(g)) * vec3(0.55, 0.65, 0.95);
		g = mix(g, nightc * 0.55, night * 0.75);
	}
	// soft fade at the map edges
	vec2 e = min(UV, 1.0 - UV) * cells;
	float edge = smoothstep(0.0, 2.5, min(e.x, e.y));
	g *= mix(0.55, 1.0, edge);
	COLOR = vec4(g, 1.0);
}
