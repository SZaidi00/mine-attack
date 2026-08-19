class_name UIThemeTokens
extends RefCounted

## Shared visual tokens and style factories for the MineAttack UI revamp.
## All revamp screens (main menu, HUD, build menu, research panel) should
## pull colors, spacing, and StyleBoxFlat factories from here so the
## "frosted steel console" language stays consistent.

# ─── Team / faction colors ───
const COLOR_PLAYER: Color = Color("#3B82F6")
const COLOR_ENEMY: Color = Color("#B91C1C")
const COLOR_ARCANE: Color = Color("#AF84FB")
const COLOR_BRUTE: Color = Color("#DF6B6B")
const COLOR_INDUSTRIAL: Color = Color("#FBBF24")

# ─── Core UI colors (source of truth: design_tokens.json) ───
const COLOR_PANEL_BG: Color = Color(12.0 / 255.0, 17.0 / 255.0, 27.0 / 255.0, 0.94)
const COLOR_PANEL_BORDER: Color = Color(1.0, 1.0, 1.0, 0.08)
const COLOR_BUTTON_NORMAL: Color = Color("#1A2434")
const COLOR_BUTTON_HOVER: Color = Color("#253650")
const COLOR_BUTTON_PRESSED: Color = Color("#111927")
const COLOR_BUTTON_DISABLED: Color = Color("#151C29")
const COLOR_BUTTON_BORDER: Color = Color(1.0, 1.0, 1.0, 0.07)
const COLOR_BUTTON_HOVER_BORDER: Color = Color("#4A86C8")
const COLOR_TAB_ACTIVE: Color = Color("#1F3A5C")
const COLOR_TAB_ACTIVE_BORDER: Color = Color("#4A86C8")
const COLOR_UPGRADE_BG: Color = Color("#272210")
const COLOR_UPGRADE_BORDER: Color = Color("#8A6D1F")
const COLOR_TEXT_GOLD: Color = Color("#FBBF24")
const COLOR_TEXT_PRIMARY: Color = Color("#E2E8F0")
const COLOR_TEXT_DIM: Color = Color("#94A3B8")

# ─── Warning / event colors ───
const COLOR_SNOWSTORM_WARNING: Color = Color("#FF4D3F")
const COLOR_LAVA_WARNING: Color = Color("#FF7F26")
const COLOR_VOLCANO_WARNING: Color = Color("#FF5926")

# ─── Derived UI colors ───
const COLOR_RECESSED_BG: Color = Color("#0b1018")
const COLOR_RECESSED_BORDER: Color = Color(1.0, 1.0, 1.0, 0.05)
const COLOR_DANGER_NORMAL: Color = Color("#3d1a1a")
const COLOR_DANGER_HOVER: Color = Color("#5c2626")
const COLOR_DANGER_PRESSED: Color = Color("#2a1212")
const COLOR_SUCCESS_BG: Color = Color("#14251a")
const COLOR_SUCCESS_BORDER: Color = Color("#3d7a4a")

# ─── Spacing / sizing ───
const RADIUS_PANEL: int = 10
const RADIUS_BUTTON: int = 8
const RADIUS_PROGRESS: int = 7
const PANEL_PADDING: int = 14
const DENSE_PADDING: int = 8
const BUTTON_H_PADDING: int = 12
const BUTTON_V_PADDING: int = 8
const FONT_SIZE_TITLE: int = 28
const FONT_SIZE_HEADER: int = 18
const FONT_SIZE_BODY: int = 13
const FONT_SIZE_SMALL: int = 11

enum ButtonVariant {
	SECONDARY,  # steel blue normal, blue hover border
	PRIMARY,    # gold accent
	UPGRADE,    # brown/gold upgrade look
	DANGER,     # muted red
}

enum ProgressVariant {
	GOLD,
	BLUE,
	GREEN,
	RED,
}

enum WarningVariant {
	SNOWSTORM,
	LAVA,
	VOLCANO,
}


# ─── Panel factories ───

static func make_panel_style(
	bg: Color = COLOR_PANEL_BG,
	border: Color = COLOR_PANEL_BORDER,
	radius: int = RADIUS_PANEL
) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = bg
	style.border_color = border
	style.set_border_width_all(1)
	style.set_corner_radius_all(radius)
	style.shadow_color = Color(0.0, 0.0, 0.0, 0.35)
	style.shadow_size = 6
	style.shadow_offset = Vector2(0.0, 2.0)
	return style


static func make_recessed_panel_style(
	bg: Color = COLOR_RECESSED_BG,
	border: Color = COLOR_RECESSED_BORDER,
	radius: int = RADIUS_BUTTON
) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = bg
	style.border_color = border
	style.set_border_width_all(1)
	style.set_corner_radius_all(radius)
	style.shadow_color = Color(0.0, 0.0, 0.0, 0.45)
	style.shadow_size = 3
	style.shadow_offset = Vector2(0.0, 1.0)
	return style


# ─── Button factories ───

static func make_button_state_style(
	variant: ButtonVariant,
	state: String
) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.set_border_width_all(1)
	style.set_corner_radius_all(RADIUS_BUTTON)
	style.content_margin_left = BUTTON_H_PADDING
	style.content_margin_top = BUTTON_V_PADDING
	style.content_margin_right = BUTTON_H_PADDING
	style.content_margin_bottom = BUTTON_V_PADDING

	match variant:
		ButtonVariant.PRIMARY:
			match state:
				"normal":
					style.bg_color = COLOR_UPGRADE_BG
					style.border_color = COLOR_UPGRADE_BORDER
				"hover":
					style.bg_color = COLOR_UPGRADE_BG.lightened(0.12)
					style.border_color = COLOR_TEXT_GOLD
				"pressed":
					style.bg_color = COLOR_UPGRADE_BG.darkened(0.4)
					style.border_color = COLOR_UPGRADE_BORDER
				"disabled":
					style.bg_color = COLOR_BUTTON_DISABLED
					style.border_color = COLOR_BUTTON_BORDER
		ButtonVariant.UPGRADE:
			match state:
				"normal":
					style.bg_color = COLOR_UPGRADE_BG
					style.border_color = COLOR_UPGRADE_BORDER
				"hover":
					style.bg_color = COLOR_UPGRADE_BG.lightened(0.12)
					style.border_color = COLOR_TEXT_GOLD
				"pressed":
					style.bg_color = COLOR_UPGRADE_BG.darkened(0.4)
					style.border_color = COLOR_UPGRADE_BORDER
				"disabled":
					style.bg_color = COLOR_BUTTON_DISABLED
					style.border_color = COLOR_BUTTON_BORDER
		ButtonVariant.DANGER:
			match state:
				"normal":
					style.bg_color = COLOR_DANGER_NORMAL
					style.border_color = Color(1.0, 1.0, 1.0, 0.07)
				"hover":
					style.bg_color = COLOR_DANGER_HOVER
					style.border_color = COLOR_SNOWSTORM_WARNING
				"pressed":
					style.bg_color = COLOR_DANGER_PRESSED
					style.border_color = Color(1.0, 1.0, 1.0, 0.07)
				"disabled":
					style.bg_color = COLOR_BUTTON_DISABLED
					style.border_color = COLOR_BUTTON_BORDER
		ButtonVariant.SECONDARY, _:
			match state:
				"normal":
					style.bg_color = COLOR_BUTTON_NORMAL
					style.border_color = COLOR_BUTTON_BORDER
				"hover":
					style.bg_color = COLOR_BUTTON_HOVER
					style.border_color = COLOR_BUTTON_HOVER_BORDER
				"pressed":
					style.bg_color = COLOR_BUTTON_PRESSED
					style.border_color = COLOR_BUTTON_BORDER
				"disabled":
					style.bg_color = COLOR_BUTTON_DISABLED
					style.border_color = COLOR_BUTTON_BORDER
	return style


static func apply_button_theme(btn: Button, variant: ButtonVariant) -> void:
	btn.add_theme_stylebox_override("normal", make_button_state_style(variant, "normal"))
	btn.add_theme_stylebox_override("hover", make_button_state_style(variant, "hover"))
	btn.add_theme_stylebox_override("pressed", make_button_state_style(variant, "pressed"))
	btn.add_theme_stylebox_override("disabled", make_button_state_style(variant, "disabled"))
	match variant:
		ButtonVariant.PRIMARY, ButtonVariant.UPGRADE:
			btn.add_theme_color_override("font_color", COLOR_TEXT_GOLD)
			btn.add_theme_color_override("font_hover_color", COLOR_TEXT_GOLD.lightened(0.2))
			btn.add_theme_color_override("font_pressed_color", COLOR_TEXT_GOLD)
			btn.add_theme_color_override("font_disabled_color", COLOR_TEXT_DIM)
		ButtonVariant.DANGER:
			btn.add_theme_color_override("font_color", COLOR_TEXT_PRIMARY)
			btn.add_theme_color_override("font_hover_color", Color.WHITE)
			btn.add_theme_color_override("font_pressed_color", COLOR_TEXT_PRIMARY)
			btn.add_theme_color_override("font_disabled_color", COLOR_TEXT_DIM)
		ButtonVariant.SECONDARY, _:
			btn.add_theme_color_override("font_color", COLOR_TEXT_PRIMARY)
			btn.add_theme_color_override("font_hover_color", Color.WHITE)
			btn.add_theme_color_override("font_pressed_color", COLOR_TEXT_PRIMARY)
			btn.add_theme_color_override("font_disabled_color", COLOR_TEXT_DIM)


# ─── Tab factories ───

static func make_tab_style(active: bool) -> StyleBoxFlat:
	if active:
		return make_button_state_style(ButtonVariant.SECONDARY, "pressed").duplicate()
	return make_button_state_style(ButtonVariant.SECONDARY, "normal").duplicate()


static func apply_tab_theme(btn: Button, active: bool) -> void:
	var style := StyleBoxFlat.new()
	style.set_border_width_all(1)
	style.set_corner_radius_all(RADIUS_BUTTON)
	style.content_margin_left = BUTTON_H_PADDING
	style.content_margin_top = BUTTON_V_PADDING
	style.content_margin_right = BUTTON_H_PADDING
	style.content_margin_bottom = BUTTON_V_PADDING
	if active:
		style.bg_color = COLOR_TAB_ACTIVE
		style.border_color = COLOR_TAB_ACTIVE_BORDER
	else:
		style.bg_color = COLOR_BUTTON_NORMAL
		style.border_color = COLOR_BUTTON_BORDER
	btn.add_theme_stylebox_override("normal", style)
	btn.add_theme_stylebox_override("hover", make_button_state_style(ButtonVariant.SECONDARY, "hover"))
	btn.add_theme_stylebox_override("pressed", make_button_state_style(ButtonVariant.SECONDARY, "pressed"))
	btn.add_theme_color_override("font_color", COLOR_TEXT_PRIMARY)
	btn.add_theme_color_override("font_hover_color", Color.WHITE)
	btn.add_theme_color_override("font_pressed_color", Color.WHITE)


# ─── Progress bar factories ───

static func apply_progress_bar_theme(bar: ProgressBar, variant: ProgressVariant) -> void:
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color("#121a28")
	bg.set_corner_radius_all(RADIUS_PROGRESS)
	bar.add_theme_stylebox_override("background", bg)

	var fill := StyleBoxFlat.new()
	match variant:
		ProgressVariant.GOLD:
			fill.bg_color = Color("#8a6d1f")
		ProgressVariant.BLUE:
			fill.bg_color = Color("#3b82c4")
		ProgressVariant.GREEN:
			fill.bg_color = Color("#3d7a4a")
		ProgressVariant.RED:
			fill.bg_color = Color("#b91c1c")
	fill.set_corner_radius_all(RADIUS_PROGRESS)
	bar.add_theme_stylebox_override("fill", fill)


# ─── Warning banner factories ───

static func make_warning_banner_style(variant: WarningVariant) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.set_corner_radius_all(RADIUS_BUTTON)
	style.set_border_width_all(1)
	match variant:
		WarningVariant.SNOWSTORM:
			style.bg_color = Color(COLOR_SNOWSTORM_WARNING.r, COLOR_SNOWSTORM_WARNING.g, COLOR_SNOWSTORM_WARNING.b, 0.18)
			style.border_color = Color(COLOR_SNOWSTORM_WARNING.r, COLOR_SNOWSTORM_WARNING.g, COLOR_SNOWSTORM_WARNING.b, 0.55)
		WarningVariant.LAVA:
			style.bg_color = Color(COLOR_LAVA_WARNING.r, COLOR_LAVA_WARNING.g, COLOR_LAVA_WARNING.b, 0.18)
			style.border_color = Color(COLOR_LAVA_WARNING.r, COLOR_LAVA_WARNING.g, COLOR_LAVA_WARNING.b, 0.55)
		WarningVariant.VOLCANO:
			style.bg_color = Color(COLOR_VOLCANO_WARNING.r, COLOR_VOLCANO_WARNING.g, COLOR_VOLCANO_WARNING.b, 0.18)
			style.border_color = Color(COLOR_VOLCANO_WARNING.r, COLOR_VOLCANO_WARNING.g, COLOR_VOLCANO_WARNING.b, 0.55)
	return style


static func warning_text_color(variant: WarningVariant) -> Color:
	match variant:
		WarningVariant.SNOWSTORM:
			return COLOR_SNOWSTORM_WARNING
		WarningVariant.LAVA:
			return COLOR_LAVA_WARNING
		WarningVariant.VOLCANO:
			return COLOR_VOLCANO_WARNING
	return COLOR_TEXT_PRIMARY


# ─── Card / faction card helpers ───

static func make_faction_card_style(faction_color: Color, selected: bool) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.set_corner_radius_all(RADIUS_PANEL)
	style.set_border_width_all(3 if selected else 1)
	style.bg_color = Color("#151c29") if not selected else Color("#1c2434")
	style.border_color = faction_color.darkened(0.5)
	if selected:
		style.border_color = COLOR_TEXT_GOLD
		style.shadow_color = Color(COLOR_TEXT_GOLD.r, COLOR_TEXT_GOLD.g, COLOR_TEXT_GOLD.b, 0.35)
		style.shadow_size = 18
	style.content_margin_left = DENSE_PADDING
	style.content_margin_top = DENSE_PADDING
	style.content_margin_right = DENSE_PADDING
	style.content_margin_bottom = DENSE_PADDING
	return style
