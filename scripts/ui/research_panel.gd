class_name ResearchPanel
extends Control

# Doctrine Deck research overlay (UI revamp: research menu B+C hybrid).
# Full-screen dim with a centered frosted-steel console, toggled from the
# BottomBar Research button / R hotkey. The body pairs option B's spatial
# branch map (positioned tech cards on a tier grid, elbow connectors for
# prerequisites, dashed edges for OR requirements) with option C's persistent
# detail rail (icon, state badge, description, cost/time/prereq/exclusion
# readout, and the research action button). Every node carries a readable
# state badge — Available / Researching / Queued / Complete / Locked /
# Excluded — tinted by its discipline color so branch identity never relies
# on connector position alone. Completing a tier-3 capstone locks its
# alternative: the locked card stays visible but grayed out, the detail rail
# names the locking tech, and the action button carries a warning before the
# player commits to an exclusive choice. A one-time respec (BRANCH_RESPEC_COST)
# resets the team's branches. Research state itself stays in ResearchManager;
# this panel only renders it. Player side only — the AI researches through
# AIController. One active research per team; cancel refunds 100%.

const UIThemeTokens = preload("res://scripts/ui/ui_theme_tokens.gd")
const _Constants = preload("res://scripts/autoload/constants.gd")

const _TEAM: GameManager.Team = GameManager.Team.PLAYER

const _COL_TEXT: Color = UIThemeTokens.COLOR_TEXT_PRIMARY
const _COL_TEXT_DIM: Color = UIThemeTokens.COLOR_TEXT_DIM
const _COL_EDGE_LOCKED: Color = Color(1, 1, 1, 0.12)
const _COL_EDGE_OPEN: Color = Color(0.98, 0.75, 0.14, 0.75)

const _NODE_SIZE: Vector2 = Vector2(200, 88)
const _COL_PITCH: float = 250.0
const _ROW_PITCH: float = 96.0
const _TREE_ORIGIN: Vector2 = Vector2(10, 10)

# Discipline identity: the five tier-1 roots carry the branch hues (Industrial
# amber, Brute red, steel blue, Arcane violet, frost). Tier 2/3 techs inherit
# their root's color; tier-4 cross-path capstones get a pale steel accent.
const _DISCIPLINE_INFO: Dictionary = {
	"deep_delve": { "name": "Deep Delve", "color": Color("#FBBF24") },
	"surface_war": { "name": "Surface War", "color": Color("#DF6B6B") },
	"fortification": { "name": "Fortification", "color": Color("#4A86C8") },
	"dragon_mastery": { "name": "Dragon Mastery", "color": Color("#AF84FB") },
	"arctic_training": { "name": "Weather", "color": Color("#7FC4E8") },
}
const _CROSS_PATH_NAME: String = "Cross-path"
const _CROSS_PATH_COLOR: Color = Color("#C9D6E8")

enum _NodeState { AVAILABLE, ACTIVE, QUEUED, COMPLETE, LOCKED, EXCLUDED }

const _BADGE_TEXT: Dictionary = {
	_NodeState.AVAILABLE: "Available",
	_NodeState.QUEUED: "Queued",
	_NodeState.COMPLETE: "Complete",
	_NodeState.LOCKED: "Locked",
	_NodeState.EXCLUDED: "Excluded",
}
const _BADGE_COLOR: Dictionary = {
	_NodeState.AVAILABLE: Color("#4A86C8"),
	_NodeState.ACTIVE: Color("#FBBF24"),
	_NodeState.QUEUED: Color("#7FB2E5"),
	_NodeState.COMPLETE: Color("#6FBF82"),
	_NodeState.LOCKED: Color("#94A3B8"),
	_NodeState.EXCLUDED: Color("#B97A7A"),
}

const _TECH_ICONS: Dictionary = {
	"deep_delve": preload("res://improvements/mine_attack_sprites/tech_deep_delve.png"),
	"surface_war": preload("res://improvements/mine_attack_sprites/tech_surface_war.png"),
	"arctic_training": preload("res://frost_mines_assets/icons/icon_snowstorm.png"),
	"ore_sonar": preload("res://improvements/mine_attack_sprites/tech_ore_sonar.png"),
	"reinforced_pack": preload("res://improvements/mine_attack_sprites/tech_reinforced_pack.png"),
	"longbow": preload("res://frost_mines_assets/icons/icon_archer.png"),
	"rapid_fire": preload("res://frost_mines_assets/icons/icon_archer.png"),
	"crystal_forge": preload("res://improvements/mine_attack_sprites/tech_crystal_forge.png"),
	"earth_shield": preload("res://frost_mines_assets/icons/icon_hp.png"),
	"siege_master": preload("res://improvements/mine_attack_sprites/tech_siege_master.png"),
	"guerrilla": preload("res://frost_mines_assets/icons/icon_swordsman.png"),
	# New discipline roots.
	"fortification": preload("res://frost_mines_assets/icons/icon_building.png"),
	"dragon_mastery": preload("res://frost_mines_assets/icons/icon_dragon.png"),
	# New Fortification branch.
	"stone_masonry": preload("res://frost_mines_assets/icons/button_build_wall.png"),
	"sentry_network": preload("res://frost_mines_assets/icons/button_build_tower.png"),
	"citadel": preload("res://frost_mines_assets/icons/icon_building.png"),
	"artillery": preload("res://frost_mines_assets/icons/button_build_tower.png"),
	# New Dragon Mastery branch.
	"broodmother": preload("res://frost_mines_assets/icons/icon_dragon.png"),
	"sky_raiders": preload("res://frost_mines_assets/icons/icon_dragon.png"),
	"inferno": preload("res://frost_mines_assets/icons/icon_dragon.png"),
	"tempest_wings": preload("res://frost_mines_assets/icons/icon_dragon.png"),
	# New Weather branch.
	"weather_alert": preload("res://frost_mines_assets/icons/icon_weather_alert.png"),
	"storm_scout": preload("res://frost_mines_assets/icons/icon_snowstorm.png"),
	"stormcaller": preload("res://frost_mines_assets/icons/icon_snowstorm.png"),
	"pathfinder": preload("res://frost_mines_assets/icons/icon_snowstorm.png"),
	# Cross-path capstones.
	"deep_fortress": preload("res://frost_mines_assets/icons/icon_building.png"),
	"total_war": preload("res://frost_mines_assets/icons/icon_attack.png"),
	"storm_dragon": preload("res://frost_mines_assets/icons/icon_dragon.png"),
}


## The map canvas: draws the prerequisite edges behind the tech cards.
## The panel fills `edges` on every refresh and calls queue_redraw().
class TreeCanvas:
	extends Control
	# Each edge: { from: Vector2, to: Vector2, unlocked: bool, either: bool }.
	# "either" marks a requires_any (OR) edge and is drawn dashed.
	var edges: Array = []
	var col_open: Color = Color.GOLD
	var col_locked: Color = Color.GRAY

	func _draw() -> void:
		for e in edges:
			var col: Color = col_open if e.unlocked else col_locked
			var from: Vector2 = e["from"]
			var to: Vector2 = e["to"]
			# Elbow connector: horizontal out of the prereq, vertical, then
			# horizontal into the dependent node (reads as a tree, not a web).
			var mid_x: float = (from.x + to.x) * 0.5
			var segments: Array = [
				[from, Vector2(mid_x, from.y)],
				[Vector2(mid_x, from.y), Vector2(mid_x, to.y)],
				[Vector2(mid_x, to.y), to],
			]
			for seg in segments:
				if e.get("either", false):
					draw_dashed_line(seg[0], seg[1], col, 2.0, 6.0)
				else:
					draw_line(seg[0], seg[1], col, 2.0)


# tech_id -> { panel, icon, name_label, badge, level_label, desc, progress }.
var _tech_cards: Dictionary = {}
var _tech_rects: Dictionary = {}  # tech_id -> Rect2 (map canvas space)
var _canvas: TreeCanvas
var _selected_tech_id: String = ""
var _active_label: Label
var _progress_bar: ProgressBar
var _completed_label: Label
var _queue_label: Label
var _queue_chips: HBoxContainer
var _cancel_button: Button
var _respec_button: Button
var _scan_button: Button
# Detail rail widgets.
var _detail_icon: TextureRect
var _detail_branch: Label
var _detail_name: Label
var _detail_badge: Label
var _detail_desc: Label
var _detail_cost: Label
var _detail_time: Label
var _detail_requires: Label
var _detail_excludes: Label
var _detail_status: Label
var _detail_progress: ProgressBar
var _detail_warning: Label
var _detail_action: Button
# The research overlay automatically pauses the game while open so the player
# can read details and queue techs without time progressing. _paused_by_panel
# marks a pause this panel engaged, so it (and only it) gets released when the
# overlay closes — and so the HUD knows not to pop the pause menu on top.
var _pause_while_open: bool = true
var _paused_by_panel: bool = false


## True while the tree pause is owned by this overlay (HUD reads this to keep
## the pause menu hidden).
func owns_pause() -> bool:
	return _paused_by_panel


func _notification(what: int) -> void:
	if what == NOTIFICATION_VISIBILITY_CHANGED:
		_sync_pause()


func _sync_pause() -> void:
	var tree := get_tree()
	if tree == null:
		return
	if visible and _pause_while_open and not tree.paused:
		tree.paused = true
		_paused_by_panel = true
	elif (not visible or not _pause_while_open) and _paused_by_panel:
		tree.paused = false
		_paused_by_panel = false
	# Give the detail rail something useful on first open: the active research
	# if there is one, otherwise the first discipline root.
	if visible and _selected_tech_id == "" and not _tech_cards.is_empty():
		var active: Dictionary = ResearchManager.get_active(_TEAM)
		_selected_tech_id = active.tech_id if not active.is_empty() else "deep_delve"
		_refresh()


func _ready() -> void:
	_build_ui()
	ResearchManager.research_changed.connect(_on_research_changed)
	ResearchManager.research_queue_changed.connect(_on_research_queue_changed)
	ResearchManager.branch_locked.connect(_on_branch_locked)
	EconomyManager.coin_changed.connect(_on_economy_changed)
	_refresh()


func _process(_delta: float) -> void:
	if not visible:
		return
	_update_active_progress()
	_update_scan_button()
	_update_respec_button()
	# Researching percentage lives on the card itself — cheap to refresh.
	_update_researching_node()


func _build_ui() -> void:
	# Full-screen dim: clicking outside the card closes the overlay.
	var dim := ColorRect.new()
	dim.color = Color(0.02, 0.03, 0.06, 0.75)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.gui_input.connect(func(event: InputEvent) -> void:
		if event is InputEventMouseButton and event.pressed:
			visible = false
	)
	add_child(dim)

	var card := PanelContainer.new()
	card.set_anchors_preset(Control.PRESET_CENTER)
	# PRESET_CENTER leaves the grow directions at BEGIN, which would expand
	# the card right/down from the screen center and push the bottom rows
	# off-screen — grow both ways so it stays centered on its anchor.
	card.grow_horizontal = Control.GROW_DIRECTION_BOTH
	card.grow_vertical = Control.GROW_DIRECTION_BOTH
	card.custom_minimum_size = Vector2(1480, 920)
	var card_style := UIThemeTokens.make_panel_style()
	card_style.content_margin_left = UIThemeTokens.PANEL_PADDING
	card_style.content_margin_top = UIThemeTokens.DENSE_PADDING
	card_style.content_margin_right = UIThemeTokens.PANEL_PADDING
	card_style.content_margin_bottom = UIThemeTokens.DENSE_PADDING
	card.add_theme_stylebox_override("panel", card_style)
	# Grow-both keeps the card centered whatever size the content ends up.
	add_child(card)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", UIThemeTokens.PANEL_PADDING)
	margin.add_theme_constant_override("margin_top", UIThemeTokens.DENSE_PADDING)
	margin.add_theme_constant_override("margin_right", UIThemeTokens.PANEL_PADDING)
	margin.add_theme_constant_override("margin_bottom", UIThemeTokens.DENSE_PADDING)
	card.add_child(margin)
	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 8)
	margin.add_child(vbox)

	_build_header(vbox)

	var body := HBoxContainer.new()
	body.add_theme_constant_override("separation", 10)
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vbox.add_child(body)
	_build_map(body)
	_build_detail_rail(body)

	vbox.add_child(HSeparator.new())
	_build_footer(vbox)


func _build_header(vbox: VBoxContainer) -> void:
	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 16)
	vbox.add_child(header)

	var title_vbox := VBoxContainer.new()
	title_vbox.add_theme_constant_override("separation", 0)
	header.add_child(title_vbox)
	var eyebrow := Label.new()
	eyebrow.text = "RESEARCH"
	eyebrow.add_theme_font_size_override("font_size", UIThemeTokens.FONT_SIZE_SMALL)
	eyebrow.add_theme_color_override("font_color", _COL_TEXT_DIM)
	title_vbox.add_child(eyebrow)
	var title := Label.new()
	title.text = "Doctrine Deck"
	title.add_theme_font_size_override("font_size", UIThemeTokens.FONT_SIZE_TITLE)
	title.add_theme_color_override("font_color", _COL_TEXT)
	title_vbox.add_child(title)

	var status_vbox := VBoxContainer.new()
	status_vbox.add_theme_constant_override("separation", 4)
	status_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	status_vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	header.add_child(status_vbox)
	_active_label = Label.new()
	_active_label.add_theme_font_size_override("font_size", UIThemeTokens.FONT_SIZE_BODY)
	_active_label.add_theme_color_override("font_color", _COL_TEXT)
	status_vbox.add_child(_active_label)
	_progress_bar = ProgressBar.new()
	_progress_bar.custom_minimum_size = Vector2(0, 10)
	_progress_bar.max_value = 1.0
	_progress_bar.show_percentage = false
	UIThemeTokens.apply_progress_bar_theme(_progress_bar, UIThemeTokens.ProgressVariant.GOLD)
	status_vbox.add_child(_progress_bar)
	_completed_label = Label.new()
	_completed_label.add_theme_font_size_override("font_size", UIThemeTokens.FONT_SIZE_SMALL)
	_completed_label.add_theme_color_override("font_color", _COL_TEXT_DIM)
	status_vbox.add_child(_completed_label)

	var close_button := Button.new()
	close_button.text = "Close (R)"
	close_button.add_theme_font_size_override("font_size", UIThemeTokens.FONT_SIZE_SMALL)
	UIThemeTokens.apply_button_theme(close_button, UIThemeTokens.ButtonVariant.SECONDARY)
	close_button.pressed.connect(func() -> void: visible = false)
	header.add_child(close_button)


func _build_map(body: HBoxContainer) -> void:
	var map_panel := PanelContainer.new()
	map_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	map_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	map_panel.add_theme_stylebox_override("panel", UIThemeTokens.make_recessed_panel_style())
	body.add_child(map_panel)

	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	map_panel.add_child(scroll)

	_canvas = TreeCanvas.new()
	_canvas.col_open = _COL_EDGE_OPEN
	_canvas.col_locked = _COL_EDGE_LOCKED
	# Four tier columns (0-3) plus rows for five disciplines and cross-path
	# capstones. The canvas lives in a ScrollContainer so the tree can be
	# taller than the card without pushing the footer off-screen.
	var max_col: int = 0
	var max_row: int = 0
	for tech_id in _Constants.RESEARCH_TECHS:
		var pos: Vector2i = _Constants.RESEARCH_TECHS[tech_id].tree_pos
		max_col = maxi(max_col, pos.x)
		max_row = maxi(max_row, pos.y)
	_canvas.custom_minimum_size = Vector2(
		_TREE_ORIGIN.x * 2 + _COL_PITCH * max_col + _NODE_SIZE.x,
		_TREE_ORIGIN.y * 2 + _ROW_PITCH * max_row + _NODE_SIZE.y)
	scroll.add_child(_canvas)

	for tech_id in _Constants.RESEARCH_TECHS:
		var tech: Dictionary = _Constants.RESEARCH_TECHS[tech_id]
		var pos: Vector2i = tech.tree_pos
		var rect := Rect2(
			_TREE_ORIGIN + Vector2(pos.x * _COL_PITCH, pos.y * _ROW_PITCH),
			_NODE_SIZE)
		_tech_rects[tech_id] = rect
		_tech_cards[tech_id] = _build_tech_card(tech_id, tech, rect)


## A doctrine-map tech card: discipline-colored left accent, icon + name, a
## state badge, a compact effect summary, and a progress strip while active.
## Clicking selects the tech and loads it into the detail rail.
func _build_tech_card(tech_id: String, tech: Dictionary, rect: Rect2) -> Dictionary:
	var card := PanelContainer.new()
	card.position = rect.position
	card.size = rect.size
	card.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	card.gui_input.connect(_on_card_gui_input.bind(tech_id))
	card.mouse_entered.connect(func() -> void: AudioManager.play("click", Vector2.INF, -14.0))
	_canvas.add_child(card)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 2)
	vbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(vbox)

	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 6)
	top.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_child(top)
	var icon := TextureRect.new()
	icon.custom_minimum_size = Vector2(22, 22)
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.texture = _TECH_ICONS.get(tech_id)
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	top.add_child(icon)
	var name_label := Label.new()
	name_label.text = tech.name
	name_label.add_theme_font_size_override("font_size", 13)
	name_label.add_theme_color_override("font_color", _COL_TEXT)
	name_label.clip_text = true
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	top.add_child(name_label)

	var mid := HBoxContainer.new()
	mid.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_child(mid)
	var badge := Label.new()
	badge.add_theme_font_size_override("font_size", 10)
	badge.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	mid.add_child(badge)
	var level_label := Label.new()
	level_label.add_theme_font_size_override("font_size", 10)
	level_label.add_theme_color_override("font_color", _COL_TEXT_DIM)
	level_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	mid.add_child(level_label)

	var desc := Label.new()
	desc.add_theme_font_size_override("font_size", 10)
	desc.add_theme_color_override("font_color", _COL_TEXT_DIM)
	desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	desc.clip_text = true
	desc.custom_minimum_size = Vector2(0, 26)
	desc.size_flags_vertical = Control.SIZE_EXPAND_FILL
	desc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_child(desc)

	var progress := ProgressBar.new()
	progress.max_value = 1.0
	progress.show_percentage = false
	progress.custom_minimum_size = Vector2(0, 5)
	progress.visible = false
	progress.mouse_filter = Control.MOUSE_FILTER_IGNORE
	UIThemeTokens.apply_progress_bar_theme(progress, UIThemeTokens.ProgressVariant.GOLD)
	vbox.add_child(progress)

	return {
		"panel": card,
		"icon": icon,
		"name_label": name_label,
		"badge": badge,
		"level_label": level_label,
		"desc": desc,
		"progress": progress,
	}


func _build_detail_rail(body: HBoxContainer) -> void:
	var rail := PanelContainer.new()
	rail.custom_minimum_size = Vector2(300, 0)
	rail.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var rail_style := UIThemeTokens.make_recessed_panel_style()
	rail_style.content_margin_left = 12
	rail_style.content_margin_top = 12
	rail_style.content_margin_right = 12
	rail_style.content_margin_bottom = 12
	rail.add_theme_stylebox_override("panel", rail_style)
	body.add_child(rail)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 8)
	rail.add_child(vbox)

	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 10)
	vbox.add_child(head)
	_detail_icon = TextureRect.new()
	_detail_icon.custom_minimum_size = Vector2(40, 40)
	_detail_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_detail_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	head.add_child(_detail_icon)
	var title_vbox := VBoxContainer.new()
	title_vbox.add_theme_constant_override("separation", 0)
	title_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(title_vbox)
	_detail_branch = Label.new()
	_detail_branch.add_theme_font_size_override("font_size", UIThemeTokens.FONT_SIZE_SMALL)
	title_vbox.add_child(_detail_branch)
	_detail_name = Label.new()
	_detail_name.add_theme_font_size_override("font_size", UIThemeTokens.FONT_SIZE_HEADER)
	_detail_name.add_theme_color_override("font_color", _COL_TEXT)
	_detail_name.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	title_vbox.add_child(_detail_name)

	_detail_badge = Label.new()
	_detail_badge.add_theme_font_size_override("font_size", UIThemeTokens.FONT_SIZE_SMALL)
	vbox.add_child(_detail_badge)

	_detail_desc = Label.new()
	_detail_desc.add_theme_font_size_override("font_size", UIThemeTokens.FONT_SIZE_BODY)
	_detail_desc.add_theme_color_override("font_color", _COL_TEXT)
	_detail_desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vbox.add_child(_detail_desc)

	vbox.add_child(HSeparator.new())

	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 12)
	grid.add_theme_constant_override("v_separation", 4)
	vbox.add_child(grid)
	_detail_cost = _add_detail_row(grid, "Cost")
	_detail_time = _add_detail_row(grid, "Time")
	_detail_requires = _add_detail_row(grid, "Requires")
	_detail_excludes = _add_detail_row(grid, "Excludes")

	_detail_status = Label.new()
	_detail_status.add_theme_font_size_override("font_size", UIThemeTokens.FONT_SIZE_SMALL)
	_detail_status.add_theme_color_override("font_color", _COL_TEXT_DIM)
	_detail_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vbox.add_child(_detail_status)

	_detail_progress = ProgressBar.new()
	_detail_progress.max_value = 1.0
	_detail_progress.show_percentage = false
	_detail_progress.custom_minimum_size = Vector2(0, 8)
	_detail_progress.visible = false
	UIThemeTokens.apply_progress_bar_theme(_detail_progress, UIThemeTokens.ProgressVariant.GOLD)
	vbox.add_child(_detail_progress)

	_detail_warning = Label.new()
	_detail_warning.add_theme_font_size_override("font_size", UIThemeTokens.FONT_SIZE_SMALL)
	_detail_warning.add_theme_color_override("font_color", UIThemeTokens.COLOR_SNOWSTORM_WARNING)
	_detail_warning.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_detail_warning.visible = false
	vbox.add_child(_detail_warning)

	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vbox.add_child(spacer)

	_detail_action = Button.new()
	_detail_action.add_theme_font_size_override("font_size", UIThemeTokens.FONT_SIZE_BODY)
	UIThemeTokens.apply_button_theme(_detail_action, UIThemeTokens.ButtonVariant.PRIMARY)
	_detail_action.pressed.connect(_on_detail_action_pressed)
	vbox.add_child(_detail_action)


func _add_detail_row(grid: GridContainer, key: String) -> Label:
	var key_label := Label.new()
	key_label.text = key
	key_label.add_theme_font_size_override("font_size", UIThemeTokens.FONT_SIZE_SMALL)
	key_label.add_theme_color_override("font_color", _COL_TEXT_DIM)
	grid.add_child(key_label)
	var value_label := Label.new()
	value_label.add_theme_font_size_override("font_size", UIThemeTokens.FONT_SIZE_SMALL)
	value_label.add_theme_color_override("font_color", _COL_TEXT)
	value_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	value_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.add_child(value_label)
	return value_label


func _build_footer(vbox: VBoxContainer) -> void:
	var footer := HBoxContainer.new()
	footer.add_theme_constant_override("separation", 8)
	footer.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_child(footer)

	_queue_label = Label.new()
	_queue_label.add_theme_font_size_override("font_size", UIThemeTokens.FONT_SIZE_BODY)
	_queue_label.add_theme_color_override("font_color", _COL_TEXT_DIM)
	footer.add_child(_queue_label)

	_queue_chips = HBoxContainer.new()
	_queue_chips.add_theme_constant_override("separation", 4)
	footer.add_child(_queue_chips)

	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	footer.add_child(spacer)

	_cancel_button = Button.new()
	_cancel_button.text = "Cancel research (100% refund)"
	_cancel_button.add_theme_font_size_override("font_size", UIThemeTokens.FONT_SIZE_BODY)
	UIThemeTokens.apply_button_theme(_cancel_button, UIThemeTokens.ButtonVariant.DANGER)
	_cancel_button.pressed.connect(_cancel_research)
	footer.add_child(_cancel_button)

	_respec_button = Button.new()
	_respec_button.text = "Respec (%dg)" % _Constants.BRANCH_RESPEC_COST
	_respec_button.tooltip_text = "Reset all researched branches — one-time use per match"
	_respec_button.add_theme_font_size_override("font_size", UIThemeTokens.FONT_SIZE_BODY)
	UIThemeTokens.apply_button_theme(_respec_button, UIThemeTokens.ButtonVariant.PRIMARY)
	_respec_button.pressed.connect(_respec)
	footer.add_child(_respec_button)

	_scan_button = Button.new()
	_scan_button.add_theme_font_size_override("font_size", UIThemeTokens.FONT_SIZE_BODY)
	UIThemeTokens.apply_button_theme(_scan_button, UIThemeTokens.ButtonVariant.SECONDARY)
	_scan_button.pressed.connect(_scan)
	footer.add_child(_scan_button)


# ─── Selection ───

func _on_card_gui_input(event: InputEvent, tech_id: String) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		_select_tech(tech_id)


func _select_tech(tech_id: String) -> void:
	if not _Constants.RESEARCH_TECHS.has(tech_id):
		return
	_selected_tech_id = tech_id
	AudioManager.play("click")
	_refresh()


## The tier-1 discipline a tech belongs to, or "" for cross-path capstones.
func _discipline_of(tech_id: String) -> String:
	if _DISCIPLINE_INFO.has(tech_id):
		return tech_id
	var tech: Dictionary = _Constants.RESEARCH_TECHS.get(tech_id, {})
	var roots: Array[String] = []
	for prereq_id in tech.get("requires", {}):
		var root: String = _discipline_of(prereq_id)
		if root != "" and not roots.has(root):
			roots.append(root)
	for prereq_id in tech.get("requires_any", []):
		var root: String = _discipline_of(prereq_id)
		if root != "" and not roots.has(root):
			roots.append(root)
	if roots.size() == 1:
		return roots[0]
	return ""


func _branch_label(tech_id: String) -> String:
	var root: String = _discipline_of(tech_id)
	return _DISCIPLINE_INFO[root]["name"] if root != "" else _CROSS_PATH_NAME


func _branch_color(tech_id: String) -> Color:
	var root: String = _discipline_of(tech_id)
	return _DISCIPLINE_INFO[root]["color"] if root != "" else _CROSS_PATH_COLOR


func _node_state(tech_id: String) -> _NodeState:
	if ResearchManager.is_locked(_TEAM, tech_id):
		return _NodeState.EXCLUDED
	if ResearchManager.get_next_level_data(_TEAM, tech_id).is_empty():
		return _NodeState.COMPLETE
	var active: Dictionary = ResearchManager.get_active(_TEAM)
	if not active.is_empty() and active.tech_id == tech_id:
		return _NodeState.ACTIVE
	for entry in ResearchManager.get_queue(_TEAM):
		if entry.tech_id == tech_id:
			return _NodeState.QUEUED
	if not ResearchManager.are_prerequisites_met(_TEAM, tech_id):
		return _NodeState.LOCKED
	return _NodeState.AVAILABLE


# ─── Refresh ───

func _refresh() -> void:
	var busy: bool = ResearchManager.is_researching(_TEAM)
	for tech_id in _tech_cards:
		_refresh_card(tech_id)
	_cancel_button.visible = busy
	_update_respec_button()
	_refresh_queue()
	_rebuild_edges()
	_refresh_detail()
	var completed: int = 0
	for tech_id in _Constants.RESEARCH_TECHS:
		if ResearchManager.get_level(_TEAM, tech_id) > 0:
			completed += 1
	_completed_label.text = "%d / %d techs complete" % [completed, _Constants.RESEARCH_TECHS.size()]


func _refresh_card(tech_id: String) -> void:
	var card: Dictionary = _tech_cards[tech_id]
	var tech: Dictionary = _Constants.RESEARCH_TECHS[tech_id]
	var state: _NodeState = _node_state(tech_id)
	card.panel.tooltip_text = _build_tooltip(tech_id)
	_apply_card_style(card.panel, state, _branch_color(tech_id), tech_id == _selected_tech_id)
	var badge: Label = card.badge
	if state == _NodeState.ACTIVE:
		var active: Dictionary = ResearchManager.get_active(_TEAM)
		var pct: int = int(clampf(1.0 - active.remaining / active.total, 0.0, 1.0) * 100)
		badge.text = "Researching %d%%" % pct
	else:
		badge.text = _BADGE_TEXT[state]
	badge.add_theme_color_override("font_color", _BADGE_COLOR[state])
	card.level_label.text = "Lv %d/%d" % [ResearchManager.get_level(_TEAM, tech_id), ResearchManager.get_max_level(tech_id)]
	var muted: bool = state == _NodeState.LOCKED or state == _NodeState.EXCLUDED
	card.icon.modulate = Color(0.55, 0.58, 0.65, 0.8) if muted else Color.WHITE
	card.desc.text = _effect_summary(tech_id)
	card.progress.visible = state == _NodeState.ACTIVE


## Short effect line shown on the card: the next level's desc, or the final
## level's once the tech is maxed.
func _effect_summary(tech_id: String) -> String:
	var tech: Dictionary = _Constants.RESEARCH_TECHS[tech_id]
	var next: Dictionary = ResearchManager.get_next_level_data(_TEAM, tech_id)
	if not next.is_empty():
		return next.get("desc", "")
	var levels: Dictionary = tech.levels
	return levels[levels.keys().max()].get("desc", "")


func _build_tooltip(tech_id: String) -> String:
	var tech: Dictionary = _Constants.RESEARCH_TECHS[tech_id]
	var lines: Array[String] = [tech.name]
	for lvl in tech.levels:
		var data: Dictionary = tech.levels[lvl]
		lines.append("L%d: %s — %dg / %ds" % [lvl, data.get("desc", ""), data.cost, int(data.time)])
	for prereq_id in tech.get("requires", {}):
		var needed: int = tech.requires[prereq_id]
		var prereq_name: String = _Constants.RESEARCH_TECHS[prereq_id].name
		if ResearchManager.get_level(_TEAM, prereq_id) >= needed:
			lines.append("Requires: %s L%d ✓" % [prereq_name, needed])
		else:
			lines.append("Requires: %s L%d" % [prereq_name, needed])
	var any_of: Array = tech.get("requires_any", [])
	if not any_of.is_empty():
		var names: Array[String] = []
		var met: bool = false
		for prereq_id in any_of:
			names.append(_Constants.RESEARCH_TECHS[prereq_id].name)
			if ResearchManager.get_level(_TEAM, prereq_id) >= 1:
				met = true
		lines.append("Requires: %s%s" % [" or ".join(names), " ✓" if met else ""])
	if ResearchManager.is_locked(_TEAM, tech_id):
		# Name the completed branch that locked this alternative out.
		for other_id in _Constants.RESEARCH_TECHS:
			var other: Dictionary = _Constants.RESEARCH_TECHS[other_id]
			if other.get("locks", "") == tech_id and ResearchManager.has_branch(_TEAM, other_id):
				lines.append("Locked out by %s" % other.name)
				break
	return "\n".join(lines)


func _rebuild_edges() -> void:
	_canvas.edges.clear()
	for tech_id in _Constants.RESEARCH_TECHS:
		var tech: Dictionary = _Constants.RESEARCH_TECHS[tech_id]
		var to_rect: Rect2 = _tech_rects[tech_id]
		var unlocked: bool = ResearchManager.are_prerequisites_met(_TEAM, tech_id)
		for prereq_id in tech.get("requires", {}):
			_add_edge(prereq_id, to_rect, unlocked, false)
		for prereq_id in tech.get("requires_any", []):
			# OR prerequisite: dashed edge — any one of them unlocks the node.
			_add_edge(prereq_id, to_rect, unlocked, true)
	_canvas.queue_redraw()


func _add_edge(prereq_id: String, to_rect: Rect2, unlocked: bool, either: bool) -> void:
	var from_rect: Rect2 = _tech_rects[prereq_id]
	_canvas.edges.append({
		"from": Vector2(from_rect.end.x, from_rect.get_center().y),
		"to": Vector2(to_rect.position.x, to_rect.get_center().y),
		"unlocked": unlocked,
		"either": either,
	})


func _refresh_queue() -> void:
	# Rebuild the queue chips rather than trying to sync existing rows — the
	# queue is small (≤ RESEARCH_QUEUE_MAX) and this keeps the code simple.
	for child in _queue_chips.get_children():
		child.queue_free()
	var queue: Array = ResearchManager.get_queue(_TEAM)
	_queue_label.text = "Queue %d/%d" % [queue.size(), _Constants.RESEARCH_QUEUE_MAX]
	for i in range(queue.size()):
		var entry: Dictionary = queue[i]
		var tech_name: String = _Constants.RESEARCH_TECHS[entry.tech_id].name
		var chip := PanelContainer.new()
		chip.add_theme_stylebox_override("panel", UIThemeTokens.make_recessed_panel_style())
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 4)
		chip.add_child(row)
		var label := Label.new()
		label.text = "%d. %s — %ds" % [i + 1, tech_name, int(entry.time)]
		label.add_theme_font_size_override("font_size", UIThemeTokens.FONT_SIZE_SMALL)
		label.add_theme_color_override("font_color", _COL_TEXT_DIM)
		row.add_child(label)
		var remove_button := Button.new()
		remove_button.text = "×"
		remove_button.tooltip_text = "Cancel queued research (100% refund)"
		remove_button.add_theme_font_size_override("font_size", UIThemeTokens.FONT_SIZE_SMALL)
		UIThemeTokens.apply_button_theme(remove_button, UIThemeTokens.ButtonVariant.DANGER)
		remove_button.pressed.connect(_cancel_queue_entry.bind(i))
		row.add_child(remove_button)
		_queue_chips.add_child(chip)


func _update_researching_node() -> void:
	var active: Dictionary = ResearchManager.get_active(_TEAM)
	if active.is_empty():
		return
	var card: Dictionary = _tech_cards.get(active.tech_id, {})
	if card.is_empty():
		return
	var pct: float = clampf(1.0 - active.remaining / active.total, 0.0, 1.0)
	card.badge.text = "Researching %d%%" % int(pct * 100)
	card.progress.value = pct
	if _selected_tech_id == active.tech_id:
		_detail_progress.value = pct
		_detail_status.text = "Status: Researching L%d — %d%%" % [active.level, int(pct * 100)]


func _update_active_progress() -> void:
	var active: Dictionary = ResearchManager.get_active(_TEAM)
	if active.is_empty():
		_progress_bar.value = 0.0
		_active_label.text = "No active research"
		return
	var pct: float = clampf(1.0 - active.remaining / active.total, 0.0, 1.0)
	_progress_bar.value = pct
	var tech_name: String = _Constants.RESEARCH_TECHS[active.tech_id].name
	_active_label.text = "Researching · %s L%d — %d%%" % [tech_name, active.level, int(pct * 100)]


func _update_scan_button() -> void:
	var level: int = ResearchManager.get_sonar_level(_TEAM)
	if level <= 0:
		_scan_button.text = "Scan (needs Ore Sonar)"
		_scan_button.disabled = true
		return
	var cd: float = ResearchManager.get_scan_cooldown_remaining(_TEAM)
	if cd > 0.0:
		_scan_button.text = "Scan — %ds" % int(ceil(cd))
		_scan_button.disabled = true
	else:
		_scan_button.text = "Scan for Ore (L%d)" % level
		_scan_button.disabled = false


func _update_respec_button() -> void:
	_respec_button.disabled = not ResearchManager.can_respec(_TEAM)


# ─── Detail rail ───

func _refresh_detail() -> void:
	if _selected_tech_id == "" or not _Constants.RESEARCH_TECHS.has(_selected_tech_id):
		_detail_icon.texture = null
		_detail_branch.text = ""
		_detail_name.text = "Select a technology"
		_detail_badge.text = ""
		_detail_desc.text = "Click a node on the doctrine map to inspect its cost, timing, prerequisites, and exclusions."
		_detail_desc.add_theme_color_override("font_color", _COL_TEXT_DIM)
		_detail_cost.text = "—"
		_detail_time.text = "—"
		_detail_requires.text = "—"
		_detail_excludes.text = "—"
		_detail_status.text = ""
		_detail_progress.visible = false
		_detail_warning.visible = false
		_detail_action.visible = false
		return

	var tech_id: String = _selected_tech_id
	var tech: Dictionary = _Constants.RESEARCH_TECHS[tech_id]
	var state: _NodeState = _node_state(tech_id)
	var accent: Color = _branch_color(tech_id)

	_detail_icon.texture = _TECH_ICONS.get(tech_id)
	_detail_icon.modulate = Color(0.55, 0.58, 0.65, 0.8) if state == _NodeState.LOCKED or state == _NodeState.EXCLUDED else Color.WHITE
	_detail_branch.text = _branch_label(tech_id).to_upper()
	_detail_branch.add_theme_color_override("font_color", accent)
	_detail_name.text = tech.name
	_detail_badge.text = _BADGE_TEXT.get(state, "") if state != _NodeState.ACTIVE else "Researching"
	_detail_badge.add_theme_color_override("font_color", _BADGE_COLOR[state])
	_detail_desc.text = _effect_summary(tech_id)
	_detail_desc.add_theme_color_override("font_color", _COL_TEXT)

	var next: Dictionary = ResearchManager.get_next_level_data(_TEAM, tech_id)
	_detail_cost.text = "%dg" % next.cost if not next.is_empty() else "—"
	_detail_time.text = "%ds" % int(next.time) if not next.is_empty() else "—"
	_detail_requires.text = _prereq_text(tech)
	_detail_excludes.text = _excludes_text(tech)

	var level: int = ResearchManager.get_level(_TEAM, tech_id)
	var max_level: int = ResearchManager.get_max_level(tech_id)
	match state:
		_NodeState.ACTIVE:
			_detail_status.text = "Status: Researching L%d" % (level + 1)
		_NodeState.QUEUED:
			_detail_status.text = "Status: Queued for L%d" % (level + 1)
		_NodeState.COMPLETE:
			_detail_status.text = "Status: Complete — Lv %d/%d" % [level, max_level]
		_NodeState.LOCKED:
			_detail_status.text = "Status: Locked — prerequisites not met (Lv %d/%d)" % [level, max_level]
		_NodeState.EXCLUDED:
			_detail_status.text = "Status: Excluded by the chosen branch"
		_:
			_detail_status.text = "Status: Available — Lv %d/%d" % [level, max_level]

	_detail_progress.visible = state == _NodeState.ACTIVE
	_refresh_detail_warning(tech_id, tech, state)
	_refresh_detail_action(tech_id, state)


func _prereq_text(tech: Dictionary) -> String:
	var parts: Array[String] = []
	for prereq_id in tech.get("requires", {}):
		var needed: int = tech.requires[prereq_id]
		var prereq_name: String = _Constants.RESEARCH_TECHS[prereq_id].name
		var met: bool = ResearchManager.get_level(_TEAM, prereq_id) >= needed
		parts.append("%s L%d%s" % [prereq_name, needed, " ✓" if met else ""])
	var any_of: Array = tech.get("requires_any", [])
	if not any_of.is_empty():
		var names: Array[String] = []
		var met: bool = false
		for prereq_id in any_of:
			names.append(_Constants.RESEARCH_TECHS[prereq_id].name)
			if ResearchManager.get_level(_TEAM, prereq_id) >= 1:
				met = true
		parts.append("%s%s" % [" or ".join(names), " ✓" if met else ""])
	return ", ".join(parts) if not parts.is_empty() else "None"


func _excludes_text(tech: Dictionary) -> String:
	var locks: String = tech.get("locks", "")
	if locks == "":
		return "—"
	var alt_name: String = _Constants.RESEARCH_TECHS[locks].name
	if ResearchManager.is_locked(_TEAM, locks):
		return "%s (already locked out)" % alt_name
	return alt_name


## Mutual exclusivity is irreversible until the one-time respec — say so on
## the rail before the player commits.
func _refresh_detail_warning(tech_id: String, tech: Dictionary, state: _NodeState) -> void:
	var locks: String = tech.get("locks", "")
	if locks == "" or ResearchManager.is_locked(_TEAM, locks):
		_detail_warning.visible = false
		return
	if state == _NodeState.AVAILABLE or state == _NodeState.QUEUED or state == _NodeState.ACTIVE:
		var alt_name: String = _Constants.RESEARCH_TECHS[locks].name
		_detail_warning.text = "Completing %s permanently locks out %s. The one-time respec (%dg) is the only way back." % [tech.name, alt_name, _Constants.BRANCH_RESPEC_COST]
		_detail_warning.visible = true
	else:
		_detail_warning.visible = false


func _refresh_detail_action(tech_id: String, state: _NodeState) -> void:
	_detail_action.visible = true
	_detail_action.disabled = true
	match state:
		_NodeState.ACTIVE:
			_detail_action.text = "Researching…"
		_NodeState.QUEUED:
			_detail_action.text = "Queued — cancel from the queue below"
		_NodeState.COMPLETE:
			_detail_action.text = "Complete"
		_NodeState.EXCLUDED:
			_detail_action.text = "Excluded"
		_NodeState.LOCKED:
			_detail_action.text = "Locked — needs prerequisites"
		_NodeState.AVAILABLE:
			var next: Dictionary = ResearchManager.get_next_level_data(_TEAM, tech_id)
			var queue_size: int = ResearchManager.get_queue_size(_TEAM)
			if not EconomyManager.can_afford(_TEAM, next.cost):
				_detail_action.text = "Research — %dg (not enough gold)" % next.cost
			elif queue_size >= _Constants.RESEARCH_QUEUE_MAX:
				_detail_action.text = "Research queue full"
			elif ResearchManager.is_researching(_TEAM) or queue_size > 0:
				_detail_action.text = "Queue Research · %dg / %ds" % [next.cost, int(next.time)]
				_detail_action.disabled = false
			else:
				_detail_action.text = "Start Research · %dg / %ds" % [next.cost, int(next.time)]
				_detail_action.disabled = false


# ─── Actions ───

func _on_detail_action_pressed() -> void:
	if _selected_tech_id != "":
		_start_research(_selected_tech_id)


func _start_research(tech_id: String) -> void:
	if ResearchManager.start_research(_TEAM, tech_id):
		AudioManager.play("click")
	_refresh()


func _cancel_research() -> void:
	if ResearchManager.cancel_research(_TEAM):
		AudioManager.play("click")
	_refresh()


func _cancel_queue_entry(index: int) -> void:
	if ResearchManager.cancel_research_queue_entry(_TEAM, index):
		AudioManager.play("click")
	_refresh()


func _respec() -> void:
	if ResearchManager.respec(_TEAM):
		AudioManager.play("click")
	_refresh()


func _scan() -> void:
	if ResearchManager.scan(_TEAM) >= 0:
		AudioManager.play("click")


func _on_research_changed(_team: GameManager.Team) -> void:
	_refresh()


func _on_research_queue_changed(_team: GameManager.Team) -> void:
	_refresh()


func _on_branch_locked(_team: GameManager.Team, _tech_id: String) -> void:
	_refresh()


func _on_economy_changed(_team: GameManager.Team) -> void:
	_refresh()


# ─── Styling ───

## Card state style: discipline accent on the left edge, state-specific body
## tint, and a brightened border + soft glow while selected.
func _apply_card_style(card: PanelContainer, state: _NodeState, accent: Color, selected: bool) -> void:
	var style := StyleBoxFlat.new()
	style.set_corner_radius_all(UIThemeTokens.RADIUS_BUTTON)
	style.set_border_width_all(1)
	style.border_width_left = 3
	style.content_margin_left = 8
	style.content_margin_top = 6
	style.content_margin_right = 8
	style.content_margin_bottom = 6
	var border: Color
	match state:
		_NodeState.AVAILABLE:
			style.bg_color = UIThemeTokens.COLOR_BUTTON_NORMAL
			border = Color(accent, 0.55)
		_NodeState.ACTIVE:
			style.bg_color = UIThemeTokens.COLOR_UPGRADE_BG
			border = UIThemeTokens.COLOR_TEXT_GOLD
			style.shadow_color = Color(UIThemeTokens.COLOR_TEXT_GOLD, 0.3)
			style.shadow_size = 10
		_NodeState.QUEUED:
			style.bg_color = UIThemeTokens.COLOR_TAB_ACTIVE
			border = UIThemeTokens.COLOR_TAB_ACTIVE_BORDER
		_NodeState.COMPLETE:
			style.bg_color = UIThemeTokens.COLOR_SUCCESS_BG
			border = UIThemeTokens.COLOR_SUCCESS_BORDER
		_NodeState.EXCLUDED:
			style.bg_color = Color(0.12, 0.09, 0.09, 0.65)
			border = Color(1, 1, 1, 0.05)
		_NodeState.LOCKED, _:
			style.bg_color = Color(0.09, 0.1, 0.13, 0.65)
			border = Color(1, 1, 1, 0.06)
	if selected:
		style.border_color = border.lightened(0.35)
		if style.shadow_size == 0:
			style.shadow_color = Color(accent, 0.35)
			style.shadow_size = 8
	else:
		style.border_color = border
	card.add_theme_stylebox_override("panel", style)
