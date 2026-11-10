shader_type canvas_item;
// Deep space behind the star map: multi-layered nebula dust lanes, subtle galactic band,
// and four parallax star layers with spectral color variation and gentle twinkle.

uniform vec2 offset = vec2(0.0);
uniform float zoom = 1.0;
uniform float time = 0.0;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453123);
}

float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(
		mix(hash(i), hash(i + vec2(1.0, 0.0)), f.x),
		mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), f.x),
		f.y
	);
}

float fbm(vec2 p) {
	float v = 0.0;
	float a = 0.5;
	mat2 rot = mat2(vec2(0.8, 0.6), vec2(-0.6, 0.8));
	for (int k = 0; k < 5; k++) {
		v += a * noise(p);
		p = rot * p * 2.03 + vec2(13.7, 7.3);
		a *= 0.5;
	}
	return v;
}

vec3 star_layer(vec2 p, float density, float size, float t) {
	vec2 cell = floor(p);
	vec2 f = fract(p) - 0.5;
	float h = hash(cell);
	if (h > density) return vec3(0.0);
	vec2 o = vec2(hash(cell + 3.1), hash(cell + 7.7)) - 0.5;
	float d = length(f - o * 0.72);
	float core = smoothstep(size, 0.0, d);
	float halo = smoothstep(size * 2.6, 0.0, d) * 0.25;
	float bri = 0.55 + 0.45 * hash(cell + 11.0);
	float tw = 0.88 + 0.12 * sin(t * (1.2 + hash(cell + 5.3) * 2.0) + h * 60.0);
	float temp = hash(cell + 19.3);
	vec3 tint = mix(vec3(1.0, 0.78, 0.62), vec3(0.74, 0.86, 1.0), smoothstep(0.2, 0.85, temp));
	tint = mix(tint, vec3(1.0, 0.97, 0.92), smoothstep(0.35, 0.65, 1.0 - abs(temp - 0.5) * 2.0));
	return tint * (core + halo) * bri * tw;
}

void fragment() {
	vec2 px = FRAGCOORD.xy;
	vec3 c = vec3(0.009, 0.014, 0.024);

	// Slow parallax nebula coordinates
	vec2 q = px / 560.0 + offset * 0.35;
	float n1 = fbm(q * 1.25);
	float n2 = fbm(q * 2.3 + vec2(5.2, -3.1));
	float dust = fbm(q * 3.4 - vec2(2.4, 6.8));

	// Subtle cosmic nebula washes + dark dust lanes
	c += vec3(0.035, 0.075, 0.145) * smoothstep(0.42, 0.88, n1) * 0.55;
	c += vec3(0.09, 0.04, 0.13) * smoothstep(0.48, 0.92, n2) * 0.42;
	c += vec3(0.02, 0.09, 0.11) * smoothstep(0.55, 0.95, n1 * n2 * 1.8) * 0.45;
	c *= 1.0 - 0.32 * smoothstep(0.52, 0.82, dust);

	// Four depth layers of background stars
	c += star_layer(px / 2.8 + offset * 10.0, 0.032, 0.20, time) * 0.38;
	c += star_layer(px / 5.2 + offset * 18.0, 0.030, 0.17, time) * 0.58;
	c += star_layer(px / 9.5 + offset * 30.0, 0.024, 0.14, time) * 0.82;
	c += star_layer(px / 16.0 + offset * 44.0, 0.015, 0.12, time) * 1.05;

	// Soft edge vignette so the map center commands focus
	vec2 uv = SCREEN_UV;
	c *= smoothstep(1.38, 0.28, length(uv - 0.5) * 1.35);
	COLOR = vec4(c, 1.0);
}
