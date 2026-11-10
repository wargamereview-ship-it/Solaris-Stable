shader_type canvas_item;
// The backdrop behind menus and hub screens: a dark steel gradient, a faint tactical grid with
// brighter major lines, a slow light sweep, film grain and a vignette.

uniform vec4 top_color : source_color = vec4(0.07, 0.09, 0.115, 1.0);
uniform vec4 bottom_color : source_color = vec4(0.025, 0.032, 0.042, 1.0);
uniform vec4 grid_color : source_color = vec4(0.45, 0.6, 0.75, 1.0);
uniform vec4 accent : source_color = vec4(0.96, 0.64, 0.2, 1.0);
uniform float grid = 44.0;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

void fragment() {
	vec2 px = FRAGCOORD.xy;
	vec2 uv = SCREEN_UV;
	vec3 c = mix(top_color.rgb, bottom_color.rgb, smoothstep(0.0, 1.0, uv.y));
	// grid: hairlines, every fourth one a little brighter
	vec2 g = abs(fract(px / grid - 0.5) - 0.5) * grid;
	float minor = 1.0 - smoothstep(0.0, 1.1, min(g.x, g.y));
	vec2 g4 = abs(fract(px / (grid * 4.0) - 0.5) - 0.5) * grid * 4.0;
	float major = 1.0 - smoothstep(0.0, 1.3, min(g4.x, g4.y));
	c += grid_color.rgb * (minor * 0.018 + major * 0.035);
	// tick marks at major intersections
	float cross = (1.0 - smoothstep(0.0, 1.2, g4.x)) * step(g4.y, 6.0) + (1.0 - smoothstep(0.0, 1.2, g4.y)) * step(g4.x, 6.0);
	c += grid_color.rgb * cross * 0.05;
	// slow diagonal light sweep
	float sweep = sin((uv.x * 0.8 + uv.y * 0.5) * 3.0 - TIME * 0.12) * 0.5 + 0.5;
	c += accent.rgb * pow(sweep, 8.0) * 0.012;
	// warm glow from the bottom left, cool from the top right
	c += accent.rgb * 0.035 * smoothstep(0.9, 0.0, distance(uv, vec2(0.0, 1.1)));
	c += grid_color.rgb * 0.03 * smoothstep(0.8, 0.0, distance(uv, vec2(1.0, -0.1)));
	// grain and vignette
	c += (hash(px + fract(TIME) * 17.0) - 0.5) * 0.012;
	float v = smoothstep(1.2, 0.35, length((uv - 0.5) * vec2(1.25, 1.0)));
	c *= mix(0.55, 1.0, v);
	COLOR = vec4(c, 1.0);
}
