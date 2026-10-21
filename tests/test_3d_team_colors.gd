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


func test_snow_cover_is_a_visible_value_lift() -> void:
	assert_gt(ArtStyle3D.PALETTE.snow.get_luminance(), GameManager.COLOR_ICE.get_luminance() + 0.05,
		"storm snow cover visibly whitens the ice surface")
