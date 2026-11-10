shader_type canvas_item;
// Colors MegaMek's grayscale unit sprites with a stable color or a camo pattern,
// the same idea MegaMek uses for its camo.

uniform vec4 tint : source_color = vec4(0.6, 0.6, 0.6, 1.0);
uniform sampler2D camo : source_color, filter_linear, repeat_enable;
uniform float use_camo = 0.0;
uniform float camo_scale = 1.0;
uniform float flash = 0.0;
uniform float darken = 0.0;

void fragment() {
	vec4 t = texture(TEXTURE, UV);
	float g = t.r;
	vec3 base = tint.rgb;
	if (use_camo > 0.5) {
		base = texture(camo, UV * camo_scale).rgb;
	}
	vec3 c = base * g * 1.75;
	c = mix(c, vec3(g), smoothstep(0.78, 1.0, g) * 0.55);
	c = mix(c, vec3(1.0, 0.95, 0.85), flash);
	c *= (1.0 - darken);
	COLOR = vec4(c, t.a * COLOR.a);
}
