class_name HUDStyling
extends RefCounted

var hud: HUD

func _init(h: HUD) -> void:
	hud = h

# Flat UI palette: solid dark panels and buttons with a faint border — no
# gradient textures, so the bars stay readable over any background.
const _COL_PANEL_BG: Color = Color(0.047, 0.066, 0.106, 0.94)
const _COL_PANEL_BORDER: Color = Color(1, 1, 1, 0.08)
const _COL_BTN_NORMAL: Color = Color("#1a2434")
const _COL_BTN_HOVER: Color = Color("#253650")
const _COL_BTN_PRESSED: Color = Color("#111927")
const _COL_BTN_DISABLED: Color = Color("#151c29")
const _COL_BTN_BORDER: Color = Color(1, 1, 1, 0.07)
const _COL_BTN_HOVER_BORDER: Color = Color("#4a86c8")
const _COL_TAB_ACTIVE: Color = Color("#1f3a5c")
const _COL_TAB_ACTIVE_BORDER: Color = Color("#4a86c8")
const _COL_UPGRADE_BG: Color = Color("#272210")
const _COL_UPGRADE_BORDER: Color = Color("#8a6d1f")


func _ignore_mouse_recursive(node: Node) -> void:
	if node is Control:
		# Keep buttons interactive; ignore everything else.
		if not (node is Button):
			node.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for child in node.get_children():
		_ignore_mouse_recursive(child)


func _style_panel(panel: PanelContainer) -> void:
	var style: StyleBoxFlat = StyleBoxFlat.new()
	style.bg_color = _COL_PANEL_BG
	style.border_color = _COL_PANEL_BORDER
	style.set_border_width_all(1)
	style.set_corner_radius_all(10)
	style.shadow_color = Color(0, 0, 0, 0.35)
	style.shadow_size = 6
	style.shadow_offset = Vector2(0, 2)
	panel.add_theme_stylebox_override("panel", style)


func _style_tab_buttons() -> void:
	for btn in [hud._surface_button, hud._underground_button]:
		btn.custom_minimum_size = Vector2(90, 28)
		btn.add_theme_font_size_override("font_size", 11)
		btn.add_theme_color_override("font_color", Color("#e2e8f0"))
		btn.add_theme_color_override("font_pressed_color", Color("#ffffff"))
		btn.add_theme_color_override("font_hover_color", Color("#ffffff"))
		btn.add_theme_stylebox_override("normal", _make_flat_style(_COL_BTN_NORMAL))
		btn.add_theme_stylebox_override("pressed", _make_flat_style(_COL_TAB_ACTIVE, _COL_TAB_ACTIVE_BORDER))
		btn.add_theme_stylebox_override("hover", _make_flat_style(_COL_BTN_HOVER, _COL_BTN_HOVER_BORDER))


func _style_speed_buttons() -> void:
	var buttons: Array[Button] = [hud._pause_button]
	buttons.append_array(hud._speed_buttons.values())
	for btn: Button in buttons:
		btn.custom_minimum_size = Vector2(40, 28)
		btn.add_theme_font_size_override("font_size", 11)
		btn.add_theme_color_override("font_color", Color("#e2e8f0"))
		btn.add_theme_color_override("font_pressed_color", Color("#ffffff"))
		btn.add_theme_color_override("font_hover_color", Color("#ffffff"))
		btn.add_theme_stylebox_override("normal", _make_flat_style(_COL_BTN_NORMAL))
		btn.add_theme_stylebox_override("pressed", _make_flat_style(_COL_TAB_ACTIVE, _COL_TAB_ACTIVE_BORDER))
		btn.add_theme_stylebox_override("hover", _make_flat_style(_COL_BTN_HOVER, _COL_BTN_HOVER_BORDER))


func _style_upgrade_button() -> void:
	hud._upgrade_button.custom_minimum_size = Vector2(120, 70)
	hud._upgrade_button.add_theme_font_size_override("font_size", 12)
	hud._upgrade_button.add_theme_color_override("font_color", Color("#fbbf24"))
	hud._upgrade_button.add_theme_color_override("font_disabled_color", Color("#94a3b8"))
	hud._upgrade_button.add_theme_stylebox_override("normal", _make_flat_style(_COL_UPGRADE_BG, _COL_UPGRADE_BORDER))
	hud._upgrade_button.add_theme_stylebox_override("hover", _make_flat_style(_COL_UPGRADE_BG.lightened(0.12), Color("#fbbf24")))
	hud._upgrade_button.add_theme_stylebox_override("pressed", _make_flat_style(_COL_UPGRADE_BG.darkened(0.4), _COL_UPGRADE_BORDER))
	hud._upgrade_button.add_theme_stylebox_override("disabled", _make_flat_style(_COL_BTN_DISABLED))


func _style_stance_buttons() -> void:
	for btn in [hud._attack_button, hud._defend_button, hud._garrison_button, hud._rally_button, hud._kill_button, hud._build_button]:
		btn.custom_minimum_size = Vector2(100, 70)
		btn.add_theme_font_size_override("font_size", 12)
		btn.add_theme_color_override("font_color", Color("#e2e8f0"))
		btn.add_theme_color_override("font_pressed_color", Color("#ffffff"))
		btn.add_theme_stylebox_override("normal", _make_flat_style(_COL_BTN_NORMAL, _COL_BTN_BORDER))
		btn.add_theme_stylebox_override("hover", _make_flat_style(_COL_BTN_HOVER, _COL_BTN_HOVER_BORDER))
		btn.add_theme_stylebox_override("pressed", _make_flat_style(_COL_TAB_ACTIVE, _COL_TAB_ACTIVE_BORDER))


func _make_flat_style(bg: Color, border: Color = Color(0, 0, 0, 0), radius: int = 8, content_margin: int = 6) -> StyleBoxFlat:
	var style: StyleBoxFlat = StyleBoxFlat.new()
	style.bg_color = bg
	if border.a > 0.0:
		style.border_color = border
		style.set_border_width_all(1)
	style.set_corner_radius_all(radius)
	style.content_margin_left = content_margin
	style.content_margin_top = content_margin
	style.content_margin_right = content_margin
	style.content_margin_bottom = content_margin
	return style


func _style_fighter_upgrade_buttons() -> void:
	for unit_id: String in hud._fighter_upgrade_buttons:
		var btn: Button = hud._fighter_upgrade_buttons[unit_id]
		btn.custom_minimum_size = Vector2(110, 70)
		btn.add_theme_font_size_override("font_size", 11)
		btn.add_theme_color_override("font_color", Color("#fbbf24"))
		btn.add_theme_color_override("font_disabled_color", Color("#94a3b8"))
		btn.add_theme_stylebox_override("normal", _make_flat_style(_COL_UPGRADE_BG, _COL_UPGRADE_BORDER))
		btn.add_theme_stylebox_override("hover", _make_flat_style(_COL_UPGRADE_BG.lightened(0.12), Color("#fbbf24")))
		btn.add_theme_stylebox_override("pressed", _make_flat_style(_COL_UPGRADE_BG.darkened(0.4), _COL_UPGRADE_BORDER))
		btn.add_theme_stylebox_override("disabled", _make_flat_style(_COL_BTN_DISABLED))
