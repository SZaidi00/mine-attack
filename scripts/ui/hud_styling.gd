class_name HUDStyling
extends RefCounted

const UIThemeTokens = preload("res://scripts/ui/ui_theme_tokens.gd")

var hud: HUD

func _init(h: HUD) -> void:
	hud = h

# Backwards-compatible color aliases. New code should prefer UIThemeTokens.
const _COL_PANEL_BG: Color = UIThemeTokens.COLOR_PANEL_BG
const _COL_PANEL_BORDER: Color = UIThemeTokens.COLOR_PANEL_BORDER
const _COL_BTN_NORMAL: Color = UIThemeTokens.COLOR_BUTTON_NORMAL
const _COL_BTN_HOVER: Color = UIThemeTokens.COLOR_BUTTON_HOVER
const _COL_BTN_PRESSED: Color = UIThemeTokens.COLOR_BUTTON_PRESSED
const _COL_BTN_DISABLED: Color = UIThemeTokens.COLOR_BUTTON_DISABLED
const _COL_BTN_BORDER: Color = UIThemeTokens.COLOR_BUTTON_BORDER
const _COL_BTN_HOVER_BORDER: Color = UIThemeTokens.COLOR_BUTTON_HOVER_BORDER
const _COL_TAB_ACTIVE: Color = UIThemeTokens.COLOR_TAB_ACTIVE
const _COL_TAB_ACTIVE_BORDER: Color = UIThemeTokens.COLOR_TAB_ACTIVE_BORDER
const _COL_UPGRADE_BG: Color = UIThemeTokens.COLOR_UPGRADE_BG
const _COL_UPGRADE_BORDER: Color = UIThemeTokens.COLOR_UPGRADE_BORDER


func _ignore_mouse_recursive(node: Node) -> void:
	if node is Control:
		# Keep buttons interactive; ignore everything else.
		if not (node is Button):
			node.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for child in node.get_children():
		_ignore_mouse_recursive(child)


func _style_panel(panel: PanelContainer) -> void:
	panel.add_theme_stylebox_override("panel", UIThemeTokens.make_panel_style())


func _style_tab_buttons() -> void:
	for btn in [hud._surface_button, hud._underground_button]:
		btn.custom_minimum_size = Vector2(90, 28)
		btn.add_theme_font_size_override("font_size", UIThemeTokens.FONT_SIZE_SMALL)
		UIThemeTokens.apply_tab_theme(btn, false)


func _style_speed_buttons() -> void:
	var buttons: Array[Button] = [hud._pause_button]
	buttons.append_array(hud._speed_buttons.values())
	for btn: Button in buttons:
		btn.custom_minimum_size = Vector2(40, 28)
		btn.add_theme_font_size_override("font_size", UIThemeTokens.FONT_SIZE_SMALL)
		UIThemeTokens.apply_tab_theme(btn, false)


func _style_upgrade_button() -> void:
	hud._upgrade_button.custom_minimum_size = Vector2(120, 70)
	hud._upgrade_button.add_theme_font_size_override("font_size", 12)
	UIThemeTokens.apply_button_theme(hud._upgrade_button, UIThemeTokens.ButtonVariant.UPGRADE)


func _style_stance_buttons() -> void:
	for btn in [hud._attack_button, hud._defend_button, hud._garrison_button, hud._rally_button, hud._kill_button, hud._build_button]:
		btn.custom_minimum_size = Vector2(100, 70)
		btn.add_theme_font_size_override("font_size", 12)
		var variant := UIThemeTokens.ButtonVariant.SECONDARY
		if btn == hud._kill_button:
			variant = UIThemeTokens.ButtonVariant.DANGER
		UIThemeTokens.apply_button_theme(btn, variant)


func _style_fighter_upgrade_buttons() -> void:
	for unit_id: String in hud._fighter_upgrade_buttons:
		var btn: Button = hud._fighter_upgrade_buttons[unit_id]
		btn.custom_minimum_size = Vector2(110, 70)
		btn.add_theme_font_size_override("font_size", 11)
		UIThemeTokens.apply_button_theme(btn, UIThemeTokens.ButtonVariant.UPGRADE)


## Backwards-compatible flat style factory. Prefer UIThemeTokens factories for
## new code; this wrapper is kept for callers that already use it.
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
