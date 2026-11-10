shader_type canvas_item;
// Faction territories from the disc texture: a soft wash of the owner's color, a bright border
// where two realms meet, and a faint rim where a realm ends in unclaimed space.

uniform vec2 texel = vec2(0.0005);

void fragment() {
	vec4 c = texture(TEXTURE, UV);
	float meet = 0.0;
	float rim = 0.0;
	for (int k = 0; k < 8; k++) {
		float a = float(k) * 0.785398;
		vec4 n = texture(TEXTURE, UV + vec2(cos(a), sin(a)) * texel * 1.6);
		if (n.a > 0.5 && c.a > 0.5) {
			meet = max(meet, length(n.rgb - c.rgb));
		}
		rim = max(rim, abs(n.a - c.a));
	}
	meet = smoothstep(0.06, 0.3, meet);
	rim = smoothstep(0.1, 0.9, rim) * (1.0 - meet);
	// a wide, dim inner glow towards the edge reads like a lit frontier
	float inner = 0.0;
	for (int k = 0; k < 8; k++) {
		float a = float(k) * 0.785398 + 0.39;
		vec4 n = texture(TEXTURE, UV + vec2(cos(a), sin(a)) * texel * 6.0);
		inner = max(inner, (n.a < 0.5 || length(n.rgb - c.rgb) > 0.1) ? 1.0 : 0.0);
	}
	vec3 col = c.rgb;
	float a = c.a * (0.1 + inner * 0.08) + meet * 0.75 + rim * 0.2;
	COLOR = vec4(mix(col, col * 1.3 + 0.12, meet), a);
}
