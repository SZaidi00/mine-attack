shader_type spatial;
render_mode cull_back;

uniform sampler2D palette_texture : source_color, filter_nearest, repeat_disable;
uniform vec4 team_color : source_color = vec4(1.0);
uniform vec4 accent_color : source_color = vec4(1.0);
uniform vec4 team_region_a = vec4(0.0);
uniform vec4 team_region_b = vec4(0.0);
uniform vec4 accent_region = vec4(0.0);
uniform vec4 tint_color : source_color = vec4(1.0);
uniform float tint_weight = 0.0;

bool in_region(vec2 uv, vec4 region) {
	return region.z > region.x && region.w > region.y
		&& uv.x >= region.x && uv.x <= region.z
		&& uv.y >= region.y && uv.y <= region.w;
}

void fragment() {
	vec3 painted = texture(palette_texture, UV).rgb;
	float shade = clamp(max(painted.r, max(painted.g, painted.b)), 0.25, 1.0);
	vec3 color = painted;
	if (in_region(UV, team_region_a) || in_region(UV, team_region_b)) {
		color = team_color.rgb * shade;
	} else if (in_region(UV, accent_region)) {
		color = accent_color.rgb * shade;
	}
	ALBEDO = mix(color, tint_color.rgb, tint_weight);
	METALLIC = 0.0;
	ROUGHNESS = 0.92;
	RIM = 0.35;
	RIM_TINT = 0.5;
}
