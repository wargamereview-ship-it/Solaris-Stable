shader_type canvas_item;
// Darkens the attract-mode battle behind the title screen: heavy on the left where the menu sits,
// light on the right, with a vignette, faint scanlines and a warm horizon glow.

uniform float left_dark = 0.9;
uniform float right_dark = 0.25;

void fragment() {
	vec2 uv = SCREEN_UV;
	float d = mix(left_dark, right_dark, smoothstep(0.15, 0.75, uv.x));
	float v = smoothstep(0.95, 0.3, length((uv - vec2(0.6, 0.5)) * vec2(1.1, 1.4)));
	d = mix(min(1.0, d + 0.25), d, v);
	float scan = 0.03 * step(0.5, fract(FRAGCOORD.y / 3.0));
	vec3 tint = vec3(0.02, 0.025, 0.035);
	tint += vec3(0.25, 0.14, 0.04) * 0.15 * smoothstep(0.6, 1.0, uv.y) * (1.0 - uv.x);
	COLOR = vec4(tint, clamp(d + scan, 0.0, 1.0));
}
