class_name ResearchPanel
extends Control

# Research tree overlay: full-screen dim with a centered card, toggled from
# the BottomBar Research button / R hotkey. Techs from Constants.RESEARCH_TECHS
# are laid out as a tree — tree_pos gives (tier column, branch row) and the
# "requires"/"requires_any" tables draw the connecting edges — so the player
# can see what each line progresses toward. Completing a branch locks its
# alternative ("locks"); locked nodes stay visible but grayed out, and their
# tooltip still shows what the branch would have done. A one-time respec
# (BRANCH_RESPEC_COST) resets the team's branches. Hovering a node shows its
# effects (native tooltip). Player side only — the AI researches through
# AIController. One active research per team; cancel refunds 100%.

const _Constants = preload("res://scripts/autoload/constants.gd")

const _TEAM: GameManager.Team = GameManager.Team.PLAYER

const _COL_BTN_NORMAL: Color = Color("#1a2434")
const _COL_BTN_HOVER: Color = Color("#253650")
const _COL_BTN_PRESSED: Color = Color("#111927")
const _COL_BTN_DISABLED: Color = Color("#151c29")
const _COL_BTN_BORDER: Color = Color(1, 1, 1, 0.07)
const _COL_BTN_HOVER_BORDER: Color = Color("#4a86c8")
const _COL_MAXED_BG: Color = Color("#14251a")
const _COL_MAXED_BORDER: Color = Color("#3d7a4a")
const _COL_LOCKED_BG: Color = Color(0.09, 0.1, 0.13, 0.65)
const _COL_LOCKED_BORDER: Color = Color(1, 1, 1, 0.04)
const _COL_TEXT: Color = Color("#e2e8f0")
const _COL_TEXT_DIM: Color = Color("#94a3b8")
const _COL_EDGE_LOCKED: Color = Color(1, 1, 1, 0.15)
const _COL_EDGE_OPEN: Color = Color("#8a6d1f")

const _NODE_SIZE: Vector2 = Vector2(200, 64)
const _COL_PITCH: float = 260.0
const _ROW_PITCH: float = 76.0
const _TREE_ORIGIN: Vector2 = Vector2(10, 10)

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


## The tree canvas: draws the prerequisite edges behind the node buttons.
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


var _tech_buttons: Dictionary = {}  # tech_id -> Button
var _tech_rects: Dictionary = {}    # tech_id -> Rect2 (tree canvas space)
var _canvas: TreeCanvas
var _active_label: Label
var _progress_bar: ProgressBar
var _queue_container: VBoxContainer
var _cancel_button: Button
var _respec_button: Button
var _scan_button: Button
# Optional "Pause game" toggle: the overlay never pauses by itself, but the
# player can opt in. _paused_by_panel marks a pause this panel engaged, so it
# (and only it) gets released when the overlay closes — and so the HUD knows
# not to pop the pause menu on top of the overlay.
var _pause_while_open: bool = false
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
	# Researching percentage lives on the node itself — cheap to refresh.
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
	card.custom_minimum_size = Vector2(1040, 900)
	var card_style := StyleBoxFlat.new()
	card_style.bg_color = Color(0.047, 0.066, 0.106, 0.97)
	card_style.border_color = Color(1, 1, 1, 0.08)
	card_style.set_border_width_all(1)
	card_style.set_corner_radius_all(10)
	card_style.shadow_color = Color(0, 0, 0, 0.35)
	card_style.shadow_size = 6
	card.add_theme_stylebox_override("panel", card_style)
	# Grow-both keeps the card centered whatever size the content ends up.
	add_child(card)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 14)
	margin.add_theme_constant_override("margin_top", 10)
	margin.add_theme_constant_override("margin_right", 14)
	margin.add_theme_constant_override("margin_bottom", 10)
	card.add_child(margin)
	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 8)
	margin.add_child(vbox)

	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 12)
	vbox.add_child(header)
	var title := Label.new()
	title.text = "Research Tree"
	title.add_theme_font_size_override("font_size", 16)
	title.add_theme_color_override("font_color", _COL_TEXT)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title)
	# Opt-in pause: the overlay itself never pauses the game, but the player
	# can choose to freeze the action while browsing the tree.
	var pause_toggle := CheckBox.new()
	pause_toggle.text = "Pause game"
	pause_toggle.tooltip_text = "Pause the game while the research tree is open (closing the tree resumes)"
	pause_toggle.add_theme_font_size_override("font_size", 12)
	pause_toggle.add_theme_color_override("font_color", _COL_TEXT_DIM)
	pause_toggle.toggled.connect(func(on: bool) -> void:
		_pause_while_open = on
		_sync_pause()
	)
	header.add_child(pause_toggle)
	var close_button := Button.new()
	close_button.text = "Close (R)"
	close_button.add_theme_font_size_override("font_size", 12)
	_style_button(close_button)
	close_button.pressed.connect(func() -> void: visible = false)
	header.add_child(close_button)

	_canvas = TreeCanvas.new()
	_canvas.col_open = _COL_EDGE_OPEN
	_canvas.col_locked = _COL_EDGE_LOCKED
	# Four tier columns (0-3) plus rows for five disciplines and cross-path
	# capstones. The canvas is placed inside a ScrollContainer so the tree can
	# be taller than the card without pushing the footer off-screen.
	var max_col: int = 0
	var max_row: int = 0
	for tech_id in _Constants.RESEARCH_TECHS:
		var pos: Vector2i = _Constants.RESEARCH_TECHS[tech_id].tree_pos
		max_col = maxi(max_col, pos.x)
		max_row = maxi(max_row, pos.y)
	_canvas.custom_minimum_size = Vector2(
		_TREE_ORIGIN.x * 2 + _COL_PITCH * max_col + _NODE_SIZE.x,
		_TREE_ORIGIN.y * 2 + _ROW_PITCH * max_row + _NODE_SIZE.y)

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.custom_minimum_size = Vector2(0, 520)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	vbox.add_child(scroll)
	scroll.add_child(_canvas)

	for tech_id in _Constants.RESEARCH_TECHS:
		var tech: Dictionary = _Constants.RESEARCH_TECHS[tech_id]
		var pos: Vector2i = tech.tree_pos
		var rect := Rect2(
			_TREE_ORIGIN + Vector2(pos.x * _COL_PITCH, pos.y * _ROW_PITCH),
			_NODE_SIZE)
		_tech_rects[tech_id] = rect
		var btn := Button.new()
		btn.icon = _TECH_ICONS.get(tech_id)
		btn.position = rect.position
		btn.size = rect.size
		btn.add_theme_font_size_override("font_size", 12)
		_style_button(btn)
		btn.pressed.connect(_start_research.bind(tech_id))
		btn.mouse_entered.connect(func() -> void: AudioManager.play("click", Vector2.INF, -14.0))
		_canvas.add_child(btn)
		_tech_buttons[tech_id] = btn

	vbox.add_child(HSeparator.new())

	_active_label = Label.new()
	_active_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_active_label.add_theme_font_size_override("font_size", 12)
	_active_label.add_theme_color_override("font_color", _COL_TEXT)
	vbox.add_child(_active_label)

	_progress_bar = ProgressBar.new()
	_progress_bar.custom_minimum_size = Vector2(0, 14)
	_progress_bar.max_value = 1.0
	_style_progress_bar()
	vbox.add_child(_progress_bar)

	_queue_container = VBoxContainer.new()
	_queue_container.add_theme_constant_override("separation", 4)
	vbox.add_child(_queue_container)

	var footer := HBoxContainer.new()
	footer.add_theme_constant_override("separation", 8)
	footer.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_child(footer)

	_cancel_button = Button.new()
	_cancel_button.text = "Cancel research (100% refund)"
	_cancel_button.add_theme_font_size_override("font_size", 12)
	_style_button(_cancel_button)
	_cancel_button.pressed.connect(_cancel_research)
	footer.add_child(_cancel_button)

	_respec_button = Button.new()
	_respec_button.text = "Respec (%dg)" % _Constants.BRANCH_RESPEC_COST
	_respec_button.tooltip_text = "Reset all researched branches — one-time use per match"
	_respec_button.add_theme_font_size_override("font_size", 12)
	_style_button(_respec_button)
	_respec_button.pressed.connect(_respec)
	footer.add_child(_respec_button)

	_scan_button = Button.new()
	_scan_button.add_theme_font_size_override("font_size", 12)
	_style_button(_scan_button)
	_scan_button.pressed.connect(_scan)
	footer.add_child(_scan_button)


# ─── Refresh ───

func _refresh() -> void:
	var busy: bool = ResearchManager.is_researching(_TEAM)
	for tech_id in _tech_buttons:
		_refresh_node(tech_id, busy)
	_cancel_button.visible = busy
	_update_respec_button()
	_refresh_queue()
	_rebuild_edges()


func _refresh_node(tech_id: String, _busy: bool) -> void:
	var btn: Button = _tech_buttons[tech_id]
	var tech: Dictionary = _Constants.RESEARCH_TECHS[tech_id]
	var level: int = ResearchManager.get_level(_TEAM, tech_id)
	var max_level: int = ResearchManager.get_max_level(tech_id)
	var next: Dictionary = ResearchManager.get_next_level_data(_TEAM, tech_id)
	btn.tooltip_text = _build_tooltip(tech_id)
	if ResearchManager.is_locked(_TEAM, tech_id):
		# Locked-out alternative: stays visible but grayed out; the tooltip
		# still shows what the branch would have done.
		btn.text = "%s\nLOCKED" % tech.name
		btn.disabled = true
		_style_node_locked(btn)
	elif next.is_empty():
		btn.text = "%s\nLv %d/%d — MAX" % [tech.name, max_level, max_level]
		btn.disabled = true
		_style_node_maxed(btn)
	else:
		# Re-apply the base style: a respec can un-max/unlock a node.
		_style_button(btn)
		var is_pending: bool = _is_tech_pending(tech_id)
		var line: String
		if is_pending:
			line = "Queued"
		else:
			line = "Lv %d/%d — %dg / %ds" % [level, max_level, next.cost, int(next.time)]
			if not ResearchManager.are_prerequisites_met(_TEAM, tech_id):
				line = "Lv %d/%d — needs prereq" % [level, max_level]
		btn.text = "%s\n%s" % [tech.name, line]
		var queue_full: bool = ResearchManager.get_queue_size(_TEAM) >= _Constants.RESEARCH_QUEUE_MAX
		btn.disabled = queue_full or is_pending or not EconomyManager.can_afford(_TEAM, next.cost)


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


func _is_tech_pending(tech_id: String) -> bool:
	var active: Dictionary = ResearchManager.get_active(_TEAM)
	if not active.is_empty() and active.tech_id == tech_id:
		return true
	for entry in ResearchManager.get_queue(_TEAM):
		if entry.tech_id == tech_id:
			return true
	return false


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
	# Rebuild the queue list rather than trying to sync existing rows — the
	# queue is small (≤ RESEARCH_QUEUE_MAX) and this keeps the code simple.
	for child in _queue_container.get_children():
		child.queue_free()
	var queue: Array = ResearchManager.get_queue(_TEAM)
	for i in range(queue.size()):
		var entry: Dictionary = queue[i]
		var tech_name: String = _Constants.RESEARCH_TECHS[entry.tech_id].name
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 6)
		var label := Label.new()
		label.text = "%d. %s — %ds" % [i + 1, tech_name, int(entry.time)]
		label.add_theme_font_size_override("font_size", 12)
		label.add_theme_color_override("font_color", _COL_TEXT_DIM)
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(label)
		var remove_button := Button.new()
		remove_button.text = "×"
		remove_button.tooltip_text = "Cancel queued research (100% refund)"
		remove_button.add_theme_font_size_override("font_size", 12)
		_style_button(remove_button)
		remove_button.pressed.connect(_cancel_queue_entry.bind(i))
		row.add_child(remove_button)
		_queue_container.add_child(row)


func _update_researching_node() -> void:
	var active: Dictionary = ResearchManager.get_active(_TEAM)
	if active.is_empty():
		return
	var btn: Button = _tech_buttons.get(active.tech_id)
	if btn == null:
		return
	var tech: Dictionary = _Constants.RESEARCH_TECHS[active.tech_id]
	var pct: int = int(clampf(1.0 - active.remaining / active.total, 0.0, 1.0) * 100)
	btn.text = "%s\nResearching %d%%" % [tech.name, pct]


func _update_active_progress() -> void:
	var active: Dictionary = ResearchManager.get_active(_TEAM)
	if active.is_empty():
		_progress_bar.value = 0.0
		_active_label.text = "No active research"
		return
	var pct: float = clampf(1.0 - active.remaining / active.total, 0.0, 1.0)
	_progress_bar.value = pct
	var tech_name: String = _Constants.RESEARCH_TECHS[active.tech_id].name
	_active_label.text = "%s L%d — %d%%" % [tech_name, active.level, int(pct * 100)]


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


# ─── Actions ───

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

func _style_button(btn: Button) -> void:
	for state in ["normal", "hover", "pressed", "disabled"]:
		var style := StyleBoxFlat.new()
		match state:
			"normal":
				style.bg_color = _COL_BTN_NORMAL
				style.border_color = _COL_BTN_BORDER
			"hover":
				style.bg_color = _COL_BTN_HOVER
				style.border_color = _COL_BTN_HOVER_BORDER
			"pressed":
				style.bg_color = _COL_BTN_PRESSED
				style.border_color = _COL_BTN_BORDER
			"disabled":
				style.bg_color = _COL_BTN_DISABLED
				style.border_color = _COL_BTN_BORDER
		style.set_border_width_all(1)
		style.set_corner_radius_all(8)
		btn.add_theme_stylebox_override(state, style)


func _style_node_maxed(btn: Button) -> void:
	for state in ["normal", "disabled"]:
		var style := StyleBoxFlat.new()
		style.bg_color = _COL_MAXED_BG
		style.border_color = _COL_MAXED_BORDER
		style.set_border_width_all(1)
		style.set_corner_radius_all(8)
		btn.add_theme_stylebox_override(state, style)


func _style_node_locked(btn: Button) -> void:
	for state in ["normal", "disabled"]:
		var style := StyleBoxFlat.new()
		style.bg_color = _COL_LOCKED_BG
		style.border_color = _COL_LOCKED_BORDER
		style.set_border_width_all(1)
		style.set_corner_radius_all(8)
		btn.add_theme_stylebox_override(state, style)


func _style_progress_bar() -> void:
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color("#121a28")
	bg.set_corner_radius_all(7)
	_progress_bar.add_theme_stylebox_override("background", bg)
	var fill := StyleBoxFlat.new()
	fill.bg_color = Color("#8a6d1f")
	fill.set_corner_radius_all(7)
	_progress_bar.add_theme_stylebox_override("fill", fill)
