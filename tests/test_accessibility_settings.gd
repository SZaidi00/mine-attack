extends GutTest

# Accessibility settings: UI scale keeps the HUD layout inside the window at
# both extremes, reduced motion gates the camera shake offset, and the
# colorblind palette swap updates UIThemeTokens.COLOR_ENEMY and restores it.

const UIThemeTokens = preload("res://scripts/ui/ui_theme_tokens.gd")

var _main: Node
var _hud: HUD


func before_all() -> void:
	seed(12345)
	GameManager.set_map_seed(12345)
	_main = load("res://scenes/main.tscn").instantiate()
	get_tree().root.add_child(_main)
	get_tree().current_scene = _main
	_hud = _main.get_node("UI/HUD")


func after_all() -> void:
	SettingsManager.set_ui_scale(1.0)
	SettingsManager.set_reduced_motion(false)
	SettingsManager.set_colorblind(false)
	GameManager.clear_map_seed()
	ResearchManager.reset()
	EconomyManager.reset()
	_main.free()


func before_each() -> void:
	GameManager.game_active = true


# ─── UI scale ───

func test_ui_scale_extremes_keep_bottom_bar_inside_window() -> void:
	for s in [0.75, 1.5]:
		SettingsManager.set_ui_scale(s)
		await get_tree().process_frame
		await get_tree().process_frame
		var hud_rect: Rect2 = _hud.get_global_rect()
		var bottom: Control = _hud.get_node("BottomBar")
		var bar_rect: Rect2 = bottom.get_global_rect()
		assert_almost_eq(_hud.scale.x, _hud.scale.y, 0.001, "uniform scale (%s)" % s)
		assert_true(_hud.scale.x <= s + 0.001, "effective scale never exceeds the setting (%s)" % s)
		assert_true(hud_rect.encloses(bar_rect),
			"BottomBar inside the window at scale %s (applied %s, window %s, bar %s)" % [s, _hud.scale.x, hud_rect, bar_rect])


func test_ui_scale_uses_virtual_rect() -> void:
	SettingsManager.set_ui_scale(1.5)
	await get_tree().process_frame
	var logical: Vector2 = _hud.get_viewport_rect().size
	assert_almost_eq(_hud.size.x * _hud.scale.x, logical.x, 1.0, "scaled root maps back to the full window width")
	assert_almost_eq(_hud.size.y * _hud.scale.y, logical.y, 1.0, "scaled root maps back to the full window height")


# ─── Reduced motion ───

func test_reduced_motion_gates_camera_shake_offset() -> void:
	var pc: PlayerController = _main.get_node("PlayerController")
	assert_not_null(pc.camera, "main scene has a player camera")
	SettingsManager.set_reduced_motion(true)
	pc.add_shake(20.0)
	pc._camera_helper._process_camera(0.016)
	assert_eq(pc.camera.offset, Vector2.ZERO, "shake offset not applied under reduced motion")
	SettingsManager.set_reduced_motion(false)
	pc.add_shake(20.0)
	pc._camera_helper._process_camera(0.016)
	assert_ne(pc.camera.offset, Vector2.ZERO, "shake offset applied when reduced motion is off")
	pc.camera.offset = Vector2.ZERO
	pc._shake_strength = 0.0


# ─── Colorblind palette ───

func test_colorblind_palette_swaps_and_restores() -> void:
	var original: Color = UIThemeTokens.COLOR_ENEMY
	UIThemeTokens.apply_colorblind_palette(true)
	assert_eq(UIThemeTokens.COLOR_ENEMY, Color("#D97A26"), "enemy red becomes orange")
	assert_eq(UIThemeTokens.COLOR_VICTORY, Color("#2AA8A0"), "semantic green becomes teal")
	UIThemeTokens.apply_colorblind_palette(false)
	assert_eq(UIThemeTokens.COLOR_ENEMY, original, "palette restores the default")


func test_hud_applies_palette_on_setting_change() -> void:
	SettingsManager.set_colorblind(true)
	assert_eq(UIThemeTokens.COLOR_ENEMY, Color("#D97A26"), "HUD reacted to the colorblind setting")
	SettingsManager.set_colorblind(false)
	assert_eq(UIThemeTokens.COLOR_ENEMY, Color("#B91C1C"), "HUD restored the default palette")
