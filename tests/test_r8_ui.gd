extends GutTest

const UIThemeTokens = preload("res://scripts/ui/ui_theme_tokens.gd")
const UIProgressDial = preload("res://scripts/ui/ui_progress_dial.gd")


func test_progress_dial_clamps_value_and_ignores_mouse() -> void:
	var dial := UIProgressDial.new()
	add_child(dial)
	dial.value = 0.65
	assert_almost_eq(dial.value, 0.65, 0.001)
	dial.value = 2.0
	assert_eq(dial.value, 1.0)
	dial.value = -1.0
	assert_eq(dial.value, 0.0)
	assert_eq(dial.mouse_filter, Control.MOUSE_FILTER_IGNORE)
	assert_eq(dial.custom_minimum_size, Vector2(48, 48))
	dial.free()


func test_r8_panel_and_display_font_contract() -> void:
	assert_not_null(UIThemeTokens.DISPLAY_FONT)
	var style := UIThemeTokens.make_panel_style()
	assert_eq(style.border_width_top, 2)
	assert_eq(style.border_color, UIThemeTokens.COLOR_PANEL_BORDER)
	var label := Label.new()
	UIThemeTokens.apply_display_font(label)
	assert_eq(label.get_theme_font("font"), UIThemeTokens.DISPLAY_FONT)
	label.free()
