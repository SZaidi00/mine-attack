extends GutTest

# 3D rework phase 4 (palette & team identity): the ArtStyle3D team-color
# accessor and its live colorblind mirror, entity rim materials, Brute's
# ember accent separation from the enemy team colors, and the snow-cover
# visibility buff. Settings writes are restored like test_settings_volume.gd.

var _prior_colorblind: bool


func before_all() -> void:
	_prior_colorblind = SettingsManager.get_colorblind()


func after_all() -> void:
	SettingsManager.set_colorblind(_prior_colorblind)  # Restore settings.cfg.


func test_team_colors_are_value_lifted_3d_variants() -> void:
	SettingsManager.set_colorblind(false)
	assert_eq(ArtStyle3D.team_color(GameManager.Team.PLAYER), ArtStyle3D.TEAM_PLAYER)
	assert_eq(ArtStyle3D.team_color(GameManager.Team.ENEMY), ArtStyle3D.TEAM_ENEMY)
	assert_gt(ArtStyle3D.TEAM_ENEMY.get_luminance(), GameManager.COLOR_ENEMY.get_luminance(),
		"3D enemy scarlet is lifted above the 2D deep red")
	assert_gt(ArtStyle3D.TEAM_PLAYER.get_luminance(), GameManager.COLOR_PLAYER.get_luminance(),
		"3D player blue is lifted above the 2D blue")


func test_team_color_mirrors_colorblind_swap() -> void:
	SettingsManager.set_colorblind(true)
	assert_eq(ArtStyle3D.team_color(GameManager.Team.ENEMY), ArtStyle3D.TEAM_ENEMY_COLORBLIND,
		"enemy reads as ember orange under the colorblind palette")
	assert_eq(ArtStyle3D.team_color(GameManager.Team.PLAYER), ArtStyle3D.TEAM_PLAYER,
		"player blue is stable across palettes")
	SettingsManager.set_colorblind(false)
	assert_eq(ArtStyle3D.team_color(GameManager.Team.ENEMY), ArtStyle3D.TEAM_ENEMY,
		"toggling back off restores the scarlet")


func test_enemy_separates_from_underground_rock_in_value() -> void:
	SettingsManager.set_colorblind(false)
	for team_color in [ArtStyle3D.TEAM_ENEMY, ArtStyle3D.TEAM_ENEMY_COLORBLIND, ArtStyle3D.TEAM_PLAYER]:
		assert_gt(team_color.get_luminance(), ArtStyle3D.PALETTE.rock.get_luminance() + 0.08,
			"team color lifts clearly above the underground rock")
		assert_gt(team_color.get_luminance(), ArtStyle3D.PALETTE.rock_dark.get_luminance() + 0.15,
			"team color lifts clearly above the darkest rock")


func test_brute_accent_no_longer_reads_as_enemy() -> void:
	var brute: Color = ArtStyle3D.FACTION_ACCENTS["brute"]
	assert_gt(absf(brute.h - ArtStyle3D.TEAM_ENEMY.h), 0.04,
		"ember hue is clearly off the enemy scarlet")
	assert_ne(brute, ArtStyle3D.TEAM_ENEMY)
	assert_ne(brute, ArtStyle3D.TEAM_ENEMY_COLORBLIND)


func test_undead_tint_stays_distinct_in_both_palettes() -> void:
	assert_gt(absf(ArtStyle3D.UNDEAD_TINT.h - ArtStyle3D.FACTION_ACCENTS["arcane"].h), 0.15,
		"sickly green never reads as Arcane violet")
	assert_gt(absf(ArtStyle3D.UNDEAD_TINT.h - ArtStyle3D.TEAM_ENEMY.h), 0.15)
	assert_gt(absf(ArtStyle3D.UNDEAD_TINT.h - ArtStyle3D.TEAM_ENEMY_COLORBLIND.h), 0.15)


func test_entity_materials_get_rim_others_do_not() -> void:
	var rimmed := ArtStyle3D.get_material(Color.RED, Color(0, 0, 0), 0.0, 1.0, true)
	assert_true(rimmed.rim_enabled, "entity material carries the sky-side rim")
	assert_almost_eq(rimmed.rim, ArtStyle3D.RIM_STRENGTH, 0.001)
	assert_almost_eq(rimmed.rim_tint, ArtStyle3D.RIM_TINT, 0.001)
	var plain := ArtStyle3D.get_material(Color.RED)
	assert_false(plain.rim_enabled, "plain materials (terrain glow, effects) stay rimless")
	assert_not_same(rimmed, plain, "rim is part of the material cache key")
	var boxed := ArtStyle3D.make_box(Vector3.ONE, Color.RED)
	assert_true((boxed.get_material_override() as StandardMaterial3D).rim_enabled,
		"entity primitive builders route through the rim material")
	boxed.free()


func test_r2_palette_matches_art_direction_tokens() -> void:
	var expected := {
		"night": Color("#232C3A"),
		"snow": Color("#DDE8F2"),
		"snow_shadow": Color("#8FA3B8"),
		"rock": Color("#3A3F4A"),
		"rock_dark": Color("#1C2029"),
		"wood": Color("#5C4632"),
		"steel": Color("#4E5A66"),
		"brass": Color("#C9A227"),
		"lamp_warm": Color("#FFB85C"),
		"rust": Color("#C45C26"),
		"ore_bright": Color("#F0B23C"),
		"lava": Color("#E8380D"),
		"necro": Color("#9EDF9E"),
		"witch_light": Color("#A8E6C8"),
		"storm_gloom": Color("#B9C6D4"),
	}
	for role in expected:
		assert_eq(ArtStyle3D.PALETTE[role], expected[role], "R2 token: %s" % role)
	assert_eq(ArtStyle3D.FACTION_ACCENTS.arcane, Color("#8C5CF6"))
	assert_eq(ArtStyle3D.FACTION_ACCENTS.brute, Color("#EE6B1C"))
	assert_eq(ArtStyle3D.FACTION_ACCENTS.industrial, Color("#C9A227"))


func test_bloom_clamps_cool_emissives_but_preserves_warm_sources() -> void:
	var warm := ArtStyle3D.get_material(ArtStyle3D.PALETTE.lamp_warm, ArtStyle3D.PALETTE.lamp_warm, 1.8)
	assert_almost_eq(warm.emission_energy_multiplier, 1.8, 0.001,
		"amber practical lights keep their emission energy")
	var cool := ArtStyle3D.get_material(ArtStyle3D.FACTION_ACCENTS.arcane, ArtStyle3D.FACTION_ACCENTS.arcane, 2.2)
	assert_true(cool.emission_enabled, "cool magic remains emissive for readability")
	assert_almost_eq(cool.emission_energy_multiplier, ArtStyle3D.COOL_EMISSION_CAP, 0.001,
		"cool magic is clamped out of the warm-source bloom range")
	assert_lt(ArtStyle3D.COOL_EMISSION_CAP, ArtStyle3D.BLOOM_HDR_THRESHOLD)


func test_snow_cover_is_a_visible_value_lift() -> void:
	assert_gt(ArtStyle3D.PALETTE.snow.get_luminance(), ArtStyle3D.PALETTE.snow_shadow.get_luminance() + 0.05,
		"storm snow cover visibly whitens the shadow-snow surface")
