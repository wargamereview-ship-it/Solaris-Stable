shader_type canvas_item;
// Deep space behind the star map: three layers of stars with parallax and a faint nebula.

uniform vec2 offset = vec2(0.0);
uniform float zoom = 1.0;

float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1, 0)), f.x), mix(hash(i + vec2(0, 1)), hash(i + vec2(1, 1)), f.x), f.y);
}
float fbm(vec2 p) {
	float v = 0.0;
	float a = 0.5;
	for (int k = 0; k < 5; k++) { v += a * noise(p); p *= 2.03; a *= 0.5; }
	return v;
}
float stars(vec2 p, float density, float size) {
	vec2 cell = floor(p);
	vec2 f = fract(p) - 0.5;
	float h = hash(cell);
	if (h > density) return 0.0;
	vec2 o = vec2(hash(cell + 3.1), hash(cell + 7.7)) - 0.5;
	float d = length(f - o * 0.7);
	return smoothstep(size, 0.0, d) * (0.5 + 0.5 * hash(cell + 11.0));
}

void fragment() {
	vec2 px = FRAGCOORD.xy;
	vec3 c = vec3(0.012, 0.016, 0.03);
	vec2 q = px / 520.0 + offset * 0.4;
	float n = fbm(q * 1.4);
	float n2 = fbm(q * 2.7 + 5.0);
	c += vec3(0.1, 0.05, 0.16) * smoothstep(0.45, 0.9, n) * 0.55;
	c += vec3(0.03, 0.08, 0.14) * smoothstep(0.5, 0.95, n2) * 0.6;
	c += vec3(1.0, 0.95, 0.9) * stars(px / 3.0 + offset * 12.0, 0.04, 0.22) * 0.55;
	c += vec3(0.8, 0.88, 1.0) * stars(px / 6.0 + offset * 24.0, 0.035, 0.18) * 0.7;
	c += vec3(1.0, 0.9, 0.8) * stars(px / 11.0 + offset * 40.0, 0.03, 0.12) * 0.9;
	vec2 uv = SCREEN_UV;
	c *= smoothstep(1.3, 0.3, length(uv - 0.5) * 1.4);
	COLOR = vec4(c, 1.0);
}
