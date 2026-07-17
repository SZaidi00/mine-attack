extends CanvasLayer

## Phase 0 debug overlay. Toggle with F3.
## Renders unit states, target lines, paths, cargo, and a global stats/log panel.

const PANEL_WIDTH: float = 320.0
const PANEL_HEIGHT: float = 420.0

var _overlay_visible: bool = true
var _reveal_underground: bool = false
var _draw_control: Control

@onready var _grid: GridWorld = get_node("/root/Main/World/GridWorld")
@onready var _panel: PanelContainer
@onready var _stats_label: RichTextLabel


func _ready() -> void:
	# Debug tooling only: remove the overlay entirely from release builds.
	if not Constants.DEBUG:
		set_process(false)
		set_process_input(false)
		queue_free()
		return
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build_draw_control()
	_build_panel()
	visible = _overlay_visible
	_draw_control.queue_redraw()


func _input(event: InputEvent) -> void:
	if event.is_action_pressed("toggle_debug"):
		_overlay_visible = not _overlay_visible
		visible = _overlay_visible
		_panel.visible = _overlay_visible
		_draw_control.queue_redraw()


func _process(_delta: float) -> void:
	if _overlay_visible:
		_update_stats()
		_draw_control.queue_redraw()


# CanvasLayer is not a CanvasItem, so it cannot _draw() by itself. A full-rect,
# input-transparent Control child performs the drawing and forwards it here
# through the CanvasItem.draw signal.
func _build_draw_control() -> void:
	_draw_control = Control.new()
	_draw_control.set_anchors_preset(Control.PRESET_FULL_RECT)
	_draw_control.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_draw_control.draw.connect(_on_draw_control_draw)
	add_child(_draw_control)


func _on_draw_control_draw() -> void:
	if not _overlay_visible:
		return

	var font: Font = ThemeDB.fallback_font
	var font_size: int = 12

	for unit in get_tree().get_nodes_in_group("units"):
		if not is_instance_valid(unit):
			continue
		if unit._state == Unit.State.DEAD:
			continue

		var screen_pos: Vector2 = _world_to_screen(unit.global_position)
		if not _is_on_screen(screen_pos):
			continue

		# State label above unit.
		var state_name: String = Unit.State.keys()[unit._state]
		var label_pos: Vector2 = screen_pos + Vector2(0, -36)
		_draw_control.draw_string(font, label_pos, state_name, HORIZONTAL_ALIGNMENT_CENTER, -1, font_size, _team_color(unit.team))

		# Cargo label for miners.
		if unit.data.is_miner:
			var cargo_text: String = "%d/%d" % [unit.carried_coin, unit.data.carry_capacity]
			_draw_control.draw_string(font, screen_pos + Vector2(0, 48), cargo_text, HORIZONTAL_ALIGNMENT_CENTER, -1, font_size, Color.GOLD)

		# Target line.
		var target_world: Vector2 = _get_unit_target_world(unit)
		if target_world != Vector2.INF:
			var target_screen: Vector2 = _world_to_screen(target_world)
			_draw_control.draw_line(screen_pos, target_screen, Color.YELLOW, 1.5)
			# Small target marker.
			_draw_control.draw_circle(target_screen, 4.0, Color.YELLOW)

		# Active path polyline.
		if unit._path.size() > 0:
			var path_screen: PackedVector2Array = PackedVector2Array()
			path_screen.append(screen_pos)
			for i in range(unit._path_index, unit._path.size()):
				path_screen.append(_world_to_screen(unit._path[i]))
			_draw_control.draw_polyline(path_screen, Color.CYAN, 1.0)


func _build_panel() -> void:
	_panel = PanelContainer.new()
	_panel.position = Vector2(10, 100)
	_panel.size = Vector2(PANEL_WIDTH, PANEL_HEIGHT)
	_panel.mouse_filter = Control.MOUSE_FILTER_PASS
	add_child(_panel)

	var margin: MarginContainer = MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 8)
	margin.add_theme_constant_override("margin_top", 8)
	margin.add_theme_constant_override("margin_right", 8)
	margin.add_theme_constant_override("margin_bottom", 8)
	_panel.add_child(margin)

	var vbox: VBoxContainer = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 6)
	margin.add_child(vbox)

	_stats_label = RichTextLabel.new()
	_stats_label.bbcode_enabled = true
	_stats_label.fit_content = true
	_stats_label.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_stats_label.scroll_active = true
	_stats_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_child(_stats_label)

	var button_grid: GridContainer = GridContainer.new()
	button_grid.columns = 2
	vbox.add_child(button_grid)

	_add_button(button_grid, "+500 Coin", _on_add_coin)
	_add_button(button_grid, "Spawn Swordsman", _on_spawn_swordsman)
	_add_button(button_grid, "Spawn Miner", _on_spawn_miner)
	_add_button(button_grid, "Teleport to Cursor", _on_teleport_selected)
	_add_button(button_grid, "Reveal Underground", _on_reveal_underground)
	_add_button(button_grid, "Clear Log", _on_clear_log)

	var style: StyleBoxFlat = StyleBoxFlat.new()
	style.bg_color = Color(0.05, 0.05, 0.08, 0.85)
	style.border_width_left = 1
	style.border_width_top = 1
	style.border_width_right = 1
	style.border_width_bottom = 1
	style.border_color = Color(0.3, 0.3, 0.4, 1.0)
	_panel.add_theme_stylebox_override("panel", style)


func _add_button(parent: GridContainer, text: String, callback: Callable) -> void:
	var btn: Button = Button.new()
	btn.text = text
	btn.pressed.connect(callback)
	parent.add_child(btn)


func _update_stats() -> void:
	var player_count: int = get_tree().get_nodes_in_group("player").size()
	var enemy_count: int = get_tree().get_nodes_in_group("enemy").size()
	var ai: AIController = get_node_or_null("/root/Main/AIController")

	var text: String = ""
	text += "FPS: %d\n" % Engine.get_frames_per_second()
	text += "Time: %.1f\n" % GameManager.match_time
	text += "Units: P=%d E=%d\n" % [player_count, enemy_count]
	text += "Coin: P=%d E=%d\n" % [EconomyManager.get_coin(GameManager.Team.PLAYER), EconomyManager.get_coin(GameManager.Team.ENEMY)]
	text += "Miner Lv: P=%d E=%d\n" % [EconomyManager.get_miner_level(GameManager.Team.PLAYER), EconomyManager.get_miner_level(GameManager.Team.ENEMY)]
	text += "Game active: %s\n" % str(GameManager.game_active)
	if ai:
		text += "AI aggression: %s\n" % ai._aggression_level

	# Show last queued commands from the debug log.
	text += "\n--- Recent log ---\n"
	text += DebugLog.get_recent(18)
	_stats_label.text = text


func _get_unit_target_world(unit: Unit) -> Vector2:
	if unit._target_unit != null and is_instance_valid(unit._target_unit):
		return unit._target_unit.global_position
	if unit._target_building != null and is_instance_valid(unit._target_building):
		return unit._target_building.global_position
	if unit._target_cell != Vector2i(-9999, -9999):
		return _grid.grid_to_world(unit._target_cell)
	if unit._target_position != Vector2.ZERO:
		return unit._target_position
	return Vector2.INF


func _team_color(team: GameManager.Team) -> Color:
	return GameManager.COLOR_PLAYER if team == GameManager.Team.PLAYER else GameManager.COLOR_ENEMY


func _is_on_screen(screen_pos: Vector2) -> bool:
	var viewport: Rect2 = get_viewport().get_visible_rect()
	return viewport.has_point(screen_pos)


# Camera2D has no project_position()/unproject_position() (those are Camera3D
# APIs); convert via the viewport's canvas transform instead.
func _world_to_screen(world_pos: Vector2) -> Vector2:
	return get_viewport().get_canvas_transform() * world_pos


func _screen_to_world(screen_pos: Vector2) -> Vector2:
	return get_viewport().get_canvas_transform().affine_inverse() * screen_pos


# ---------- Debug buttons ----------

func _on_add_coin() -> void:
	EconomyManager.add_coin(GameManager.Team.PLAYER, 500)
	DebugLog.log_command("DebugOverlay", "+500 coin player")


func _on_spawn_swordsman() -> void:
	var building: Node2D = _get_player_building()
	if building:
		building.call("queue_unit", "swordsman")
		DebugLog.log_command("DebugOverlay", "spawn swordsman queued")


func _on_spawn_miner() -> void:
	var building: Node2D = _get_player_building()
	if building:
		building.call("queue_unit", "miner")
		DebugLog.log_command("DebugOverlay", "spawn miner queued")


func _on_teleport_selected() -> void:
	var pc: PlayerController = get_node_or_null("/root/Main/PlayerController")
	if pc == null:
		return
	var mouse: Vector2 = get_viewport().get_mouse_position()
	var world: Vector2 = _screen_to_world(mouse)
	for unit in pc.get_selected_units():
		if is_instance_valid(unit):
			unit.global_position = world
	DebugLog.log_command("DebugOverlay", "teleport selected to " + str(world))


func _on_reveal_underground() -> void:
	_reveal_underground = not _reveal_underground
	var pc: PlayerController = get_node_or_null("/root/Main/PlayerController")
	if pc:
		pc.set_view(_reveal_underground)
	DebugLog.log_command("DebugOverlay", "reveal underground " + str(_reveal_underground))


func _on_clear_log() -> void:
	DebugLog.clear()


func _get_player_building() -> Node2D:
	for b in get_tree().get_nodes_in_group("buildings"):
		if b.get("team") == GameManager.Team.PLAYER:
			return b
	return null
