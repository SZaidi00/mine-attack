shader_type canvas_item;

// Surface band: weather and volcanic effects are clipped to this vertical region.
uniform float surface_top : hint_range(0.0, 1.0) = 0.095;
uniform float surface_bottom : hint_range(0.0, 1.0) = 0.382;

// Snowstorm
uniform bool snowstorm_active = false;
uniform float storm_time = 0.0;
// 0..1 fade factor: eases in on storm start, eases out on storm end, and is
// forced to 0 while the camera is in the underground view.
uniform float storm_strength : hint_range(0.0, 1.0) = 0.0;
uniform vec3 fog_color : source_color = vec3(0.886275, 0.941176, 0.968627);
uniform float fog_alpha : hint_range(0.0, 1.0) = 0.34;
uniform float storm_intensity : hint_range(0.0, 1.0) = 1.0;
uniform float visibility_loss : hint_range(0.0, 1.0) = 1.0;
uniform float wind : hint_range(-1.0, 1.0) = 0.16;

// Cloud banks: xy = normalized position, zw = normalized radii
uniform vec4 cloud_banks[12];
// x = speed, y = alpha, z = phase
uniform vec4 cloud_meta[12];

// Fog blobs
uniform vec4 fog_blobs[42];
uniform vec4 blob_meta[42];

// Lantern shelter cutouts (screen pixels)
uniform vec2 lantern_pos[16];
uniform float lantern_radius[16];
uniform int lantern_count = 0;

// Volcano / meteor
uniform bool volcano_active = false;
uniform float volcano_time = 0.0;
uniform float heat_grade : hint_range(0.0, 1.0) = 0.68;
uniform float plume_power : hint_range(0.0, 1.0) = 0.45;

const vec3 WARM_GLOW = vec3(0.984314, 0.749020, 0.141176);

void fragment() {
	vec2 uv = SCREEN_UV;
	float y = uv.y;

	vec3 out_color = vec3(0.0);
	float out_alpha = 0.0;

	// Surface-only clip: outside the band the overlay stays fully transparent.
	bool in_band = y >= surface_top && y <= surface_bottom;

	if (in_band) {
		float band_height = surface_bottom - surface_top;
		float band_t = (y - surface_top) / band_height;

	// ── Snowstorm ──
	if (snowstorm_active) {
		float intensity = storm_intensity;
		float visibility = visibility_loss;
		float t = storm_time;
		float fog_density = 0.0;

		// 1. Cold surface grade / base fog wash.
		float base_alpha = fog_alpha * (0.35 + visibility * 0.85);
		float grade = 0.18 + band_t * 0.58 + (1.0 - band_t) * 0.0;
		fog_density += base_alpha * grade;

		// 2. Cloud banks.
		for (int i = 0; i < 12; i++) {
			vec4 cb = cloud_banks[i];
			vec4 cm = cloud_meta[i];
			float dir = wind >= 0.0 ? 1.0 : -1.0;
			float x = cb.x + dir * cm.x * t * 0.1;
			x = fract(x + 100.0);
			float cy = cb.y + sin(t * 0.35 + cm.z) * 0.012;
			float dx = uv.x - x;
			if (dx > 0.5) dx -= 1.0;
			if (dx < -0.5) dx += 1.0;
			float dy = (y - cy) / band_height;
			float rx = cb.z * (0.9 + intensity * 0.35);
			float ry = cb.w * (0.8 + visibility * 0.55);
			float d2 = (dx * dx) / (rx * rx) + (dy * dy) / (ry * ry);
			if (d2 < 1.0) {
				float pulse = 0.82 + 0.18 * sin(t * 0.5 + cm.z);
				fog_density += (1.0 - d2) * (0.035 + cm.y * 0.18 * intensity * visibility) * pulse;
			}
		}

		// 3. Fog blobs.
		for (int i = 0; i < 42; i++) {
			vec4 fb = fog_blobs[i];
			vec4 fm = blob_meta[i];
			float dir = wind >= 0.0 ? 1.0 : -1.0;
			float x = fb.x + (wind * 0.7 + 0.2) * fm.x * t * 0.1;
			x = fract(x + 100.0);
			float cy = fb.y + sin(t * 0.45 + fm.z) * fm.w;
			float dx = uv.x - x;
			if (dx > 0.5) dx -= 1.0;
			if (dx < -0.5) dx += 1.0;
			float dy = (y - cy) / band_height;
			float rx = fb.z * (0.75 + intensity * 0.55);
			float ry = fb.w * (0.9 + visibility * 0.9);
			float d2 = (dx * dx) / (rx * rx) + (dy * dy) / (ry * ry);
			if (d2 < 1.0) {
				float pulse = 0.78 + 0.22 * sin(t * 0.7 + fm.z);
				fog_density += (1.0 - d2) * (0.05 + fm.y * fog_alpha * intensity * visibility) * pulse;
			}
		}

		// 4. Shelter cutouts.
		vec2 screen_px = uv / SCREEN_PIXEL_SIZE;
		float shelter_atten = 1.0;
		for (int i = 0; i < lantern_count; i++) {
			float d = distance(screen_px, lantern_pos[i]);
			float r = lantern_radius[i];
			float inner = r * 0.34;
			float a = 1.0 - smoothstep(inner, r, d);
			shelter_atten -= a * 0.74;
		}
		shelter_atten = clamp(shelter_atten, 0.0, 1.0);
		fog_density *= shelter_atten;

		// 5. Warm shelter glow.
		float glow = 0.0;
		for (int i = 0; i < lantern_count; i++) {
			float d = distance(screen_px, lantern_pos[i]);
			float r = lantern_radius[i] * 0.5;
			float g = 1.0 - smoothstep(0.0, r, d);
			glow += g * 0.28;
		}
		glow = clamp(glow, 0.0, 1.0);

		out_color = fog_color + WARM_GLOW * glow;
		out_alpha = clamp(fog_density, 0.0, 0.95) * storm_strength;
	}

	// ── Volcano / meteor heat ──
	if (volcano_active) {
		float t = volcano_time;
		float heat = heat_grade;

		// Surface heat grade.
		float heat_alpha = heat * (0.08 + band_t * 0.14) * 0.72;
		// Central hot spot near the volcano mouth.
		float dx = uv.x - 0.505;
		float dy = band_t - 0.3;
		float dist = sqrt(dx * dx + dy * dy * 4.0);
		heat_alpha += heat * 0.2 * smoothstep(0.3, 0.0, dist);
		heat_alpha = clamp(heat_alpha, 0.0, 0.6);

		vec3 heat_color = mix(vec3(0.33, 0.07, 0.04), vec3(1.0, 0.4, 0.12), band_t);
		out_color = mix(out_color, heat_color, heat_alpha * (1.0 - out_alpha * 0.5));
		out_alpha = max(out_alpha, heat_alpha * 0.5);

		// Crater plume.
		if (plume_power > 0.01) {
			for (int i = 0; i < 18; i++) {
				float pt = float(i) / 18.0;
				float pulse = 0.72 + 0.28 * sin(t * 2.0 + float(i) * 1.7);
				float px = 0.505 + sin(t + float(i)) * 0.012 * (1.0 + pt * 2.4);
				float py = 0.285 - pt * 0.2 * plume_power;
				float radius = (0.005 + pt * 0.022) * plume_power * pulse;
				float d = distance(uv, vec2(px, py));
				if (d < radius) {
					float a = (1.0 - d / radius) * 0.11 * plume_power;
					out_color += vec3(1.0, 0.74, 0.29) * a;
					out_alpha = max(out_alpha, a * 0.5);
				}
				}
			}
		}
	}

	COLOR = vec4(out_color, out_alpha);
}
