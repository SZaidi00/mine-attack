class_name PlayerController
extends Node

const _Constants = preload("res://scripts/autoload/constants.gd")
const _REJECT_POPUP: PackedScene = preload("res://scenes/effects/reject_popup.tscn")
const _LANTERN_SCENE: PackedScene = preload("res://scenes/lantern.tscn")
const _GHOST_RING: Texture2D = preload("res://frost_mines_assets/effects/selection_ring.png")

enum ViewMode { SURFACE, UNDERGROUND }
signal view_mode_changed(mode: ViewMode)

@export var camera: Camera2D
@export var selection_box: ColorRect

var _selected_units: Array = []
var _drag_start: Vector2 = Vector2.ZERO
var _is_dragging: bool = false
var _camera_speed: float = 600.0
var _zoom_min: float = 0.65
var _zoom_max: float = 2.0
# User wheel-zoom factor around the resolution-adaptive base zoom (1.0 default).
var _zoom_factor: float = 1.0

@onready var _grid: GridWorld = get_node("/root/Main/World/GridWorld")

var _view_mode: ViewMode = ViewMode.SURFACE
var _last_surface_cam_pos: Vector2 = Vector2(0, -150)
var _last_underground_cam_pos: Vector2 = Vector2(0, 400)
# Camera slide target after a view toggle (INF = not sliding).
var _view_slide_target: Vector2 = Vector2.INF
# Screen shake strength, decaying to 0; driven by building damage/destruction.
var _shake_strength: float = 0.0
# Rally stance armed: the next left-click sets the rally point for all fighters.
var _rally_armed: bool = false
# Persistent army mode set by the Attack/Defend/Garrison buttons: newly
# trained fighters automatically receive this order when they spawn.
var _current_stance: String = "defend"
# Lantern placement mode (Revamp Phase 1): "" when inactive, otherwise
# "lantern" (surface) or "underground_lantern". A ghost sprite follows the
# cursor — green where placement is valid, red where it is not.
var _build_mode: String = ""
var _build_ghost: Node2D = null


func _ready() -> void:
	# The camera export is assigned in main.tscn, but scene exports resolved
	# from NodePaths can be null in some contexts (e.g. headless harnesses) —
	# fall back to the well-known path instead of dying silently.
	if camera == null:
		camera = get_node_or_null("/root/Main/Camera2D")
	if selection_box:
		selection_box.visible = false
		# The box is purely visual: it must never consume mouse events, or a
		# drag-release landing inside it would be swallowed by the GUI and
		# _unhandled_input would never finish the selection.
		selection_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_init_view_positions()
	_connect_building_shake()
	_connect_building_spawns()
	_apply_zoom()
	get_window().size_changed.connect(_apply_zoom)
	call_deferred("_validate_setup")


## Newly trained player fighters automatically receive the current stance mode
## (Attack/Defend/Garrison) as soon as they leave the building.
func _connect_building_spawns() -> void:
	for b in get_tree().get_nodes_in_group("buildings"):
		if b.get("team") == GameManager.Team.PLAYER and b.has_signal("unit_spawned"):
			b.unit_spawned.connect(_on_fighter_spawned)


func _on_fighter_spawned(unit: Node2D) -> void:
	var data = unit.get("data")
	if data == null or data.is_miner:
		return  # Miners always auto-enter the mine, regardless of stance.
	match _current_stance:
		"attack":
			var enemy_building: Node2D = _enemy_building()
			if enemy_building:
				unit.attack_building(enemy_building)
		"garrison":
			unit.garrison_home()
		# "defend" needs no order: a fresh fighter already holds its spawn post.


## Screen shake (Phase 8): small rumble on every building hit, a big one when
## either building falls.
func _connect_building_shake() -> void:
	for b in get_tree().get_nodes_in_group("buildings"):
		if b.has_signal("hp_changed"):
			b.hp_changed.connect(_on_building_shake_hit)
		if b.has_signal("destroyed"):
			b.destroyed.connect(_on_building_shake_destroyed)


func _on_building_shake_hit(_current: int, _maximum: int) -> void:
	_shake_strength = maxf(_shake_strength, 3.0)


func _on_building_shake_destroyed(_team: GameManager.Team) -> void:
	_shake_strength = maxf(_shake_strength, 20.0)


func _init_view_positions() -> void:
	if camera == null:
		return
	# The scene author can set a starting camera position; if it looks like a
	# surface position, treat it as the saved surface view, otherwise default.
	if camera.position.y < 100:
		_last_surface_cam_pos = camera.position
	else:
		_last_surface_cam_pos = Vector2(camera.position.x, -150)
	var entry: Node2D = _player_mine_entry()
	if entry:
		_last_underground_cam_pos = entry.call("get_underground_position")
	else:
		_last_underground_cam_pos = Vector2(_last_surface_cam_pos.x, 400)
	# Apply the initial view mode so the camera is consistent on first frame.
	if _view_mode == ViewMode.SURFACE:
		camera.position = _last_surface_cam_pos
	else:
		camera.position = _last_underground_cam_pos


## Resolution-adaptive base zoom: the stretch setup (canvas_items/expand +
## stretch/scale) keeps the UI at a fixed logical 1920x1080, but the world
## should use every pixel the window offers — a 2560x1440 window shows a
## 2560x1440 world area (nearly the whole map), a 1280x720 window a
## 1280x720 area. Note `content_scale_factor` does NOT track window size in
## canvas_items mode (it only carries the stretch scale), so the ratio is
## computed from the visible rect vs. the actual window size instead.
## The wheel zoom multiplies on top of this base.
func _base_zoom() -> float:
	var win_size: Vector2i = get_window().size
	if win_size.x <= 0:
		return 1.0
	var logical: Vector2 = get_viewport().get_visible_rect().size
	return logical.x / win_size.x


func _apply_zoom() -> void:
	if camera == null:
		return
	camera.zoom = Vector2.ONE * (_base_zoom() * _zoom_factor)


func _player_mine_entry() -> Node2D:
	for entry in get_tree().get_nodes_in_group("mine_entries"):
		if entry.get("team") == GameManager.Team.PLAYER:
			return entry
	return null


## Phase 1 startup validation: fail loudly when the scene or groups the
## command pipeline depends on are missing, instead of at the first click.
func _validate_setup() -> void:
	var problems: Array[String] = []
	var buildings: Array = get_tree().get_nodes_in_group("buildings")
	if buildings.size() < 2:
		problems.append("expected 2 nodes in 'buildings' group, found %d" % buildings.size())
	var entries: Array = get_tree().get_nodes_in_group("mine_entries")
	if entries.size() < 2:
		problems.append("expected 2 nodes in 'mine_entries' group, found %d" % entries.size())
	for path in ["/root/Main/World/GridWorld", "/root/Main/Units", "/root/Main/Projectiles", "/root/Main/Camera2D"]:
		if get_node_or_null(path) == null:
			problems.append("missing node " + path)
	for b in buildings:
		if not b.has_method("get_bounds_rect"):
			problems.append("building %d lacks get_bounds_rect()" % b.get_instance_id())
	for b in buildings:
		if not b.is_in_group("buildings"):
			problems.append("building %d missing 'buildings' group" % b.get_instance_id())
	if problems.is_empty():
		DebugLog.log_command("PlayerController", "startup validation", "OK")
	for p in problems:
		push_error("PlayerController startup validation: " + p)
		DebugLog.log_reject("PlayerController", "startup validation", p)


func _process(delta: float) -> void:
	# Lantern placement ghost: snap to the cell under the cursor and tint it
	# by placement validity (green = valid, red = invalid).
	if _build_mode != "" and _build_ghost != null:
		var world: Vector2 = _screen_to_world(get_viewport().get_mouse_position())
		var cell: Vector2i = _grid.world_to_grid(world)
		_build_ghost.global_position = _grid.grid_to_world(cell)
		var err: String = _lantern_placement_error(_build_mode, cell)
		_build_ghost.modulate = Color(0.4, 1.0, 0.4, 0.55) if err == "" else Color(1.0, 0.35, 0.35, 0.55)
	if camera == null:
		return
	var move: Vector2 = Vector2.ZERO
	if Input.is_action_pressed(_Constants.INPUT_CAMERA_RIGHT):
		move.x += 1
	if Input.is_action_pressed(_Constants.INPUT_CAMERA_LEFT):
		move.x -= 1
	if Input.is_action_pressed(_Constants.INPUT_CAMERA_DOWN):
		move.y += 1
	if Input.is_action_pressed(_Constants.INPUT_CAMERA_UP):
		move.y -= 1
	camera.position += move.normalized() * _camera_speed * delta / camera.zoom
	# Camera slide after a view toggle; any manual pan cancels it.
	if _view_slide_target != Vector2.INF:
		if move != Vector2.ZERO:
			_view_slide_target = Vector2.INF
		else:
			camera.position = camera.position.lerp(_view_slide_target, minf(1.0, delta * 6.0))
			if camera.position.distance_to(_view_slide_target) < 4.0:
				camera.position = _view_slide_target
				_view_slide_target = Vector2.INF
	# Screen shake decays back to a clean zero offset.
	if _shake_strength > 0.2:
		camera.offset = Vector2(randf_range(-_shake_strength, _shake_strength), randf_range(-_shake_strength, _shake_strength))
		_shake_strength = move_toward(_shake_strength, 0.0, delta * 30.0)
	elif camera.offset != Vector2.ZERO:
		camera.offset = Vector2.ZERO
	# Clamp camera within world bounds. When the view is larger than the
	# bounds on an axis (e.g. a 1440p+ window where the whole world fits),
	# pin the camera to the bounds center on that axis instead of leaving it
	# free to drift past the world into empty space.
	var half_size: Vector2 = get_viewport().get_visible_rect().size / (2.0 * camera.zoom)
	var min_pos: Vector2 = Vector2((GridWorld.X_MIN - 2) * GridWorld.CELL_SIZE, -300)
	var max_pos: Vector2 = Vector2((GridWorld.X_MAX + 3) * GridWorld.CELL_SIZE, (GridWorld.Y_MAX + 4) * GridWorld.CELL_SIZE)
	var lo: Vector2 = min_pos + half_size
	var hi: Vector2 = max_pos - half_size
	if lo.x <= hi.x:
		camera.position.x = clampf(camera.position.x, lo.x, hi.x)
	else:
		camera.position.x = (min_pos.x + max_pos.x) / 2.0
	if lo.y <= hi.y:
		camera.position.y = clampf(camera.position.y, lo.y, hi.y)
	else:
		camera.position.y = (min_pos.y + max_pos.y) / 2.0


func _unhandled_input(event: InputEvent) -> void:
	if not GameManager.game_active:
		return

	# Lantern placement mode: left-click confirms (stays active on an invalid
	# spot so the player can adjust), right-click or Esc cancels. Swallowed
	# either way so no selection/command leaks through.
	if _build_mode != "":
		if event.is_action_pressed(_Constants.INPUT_SELECT):
			var world: Vector2 = _screen_to_world(get_viewport().get_mouse_position())
			if try_place_lantern(_build_mode, world):
				_cancel_build_mode()
		elif event.is_action_pressed(_Constants.INPUT_COMMAND) or event.is_action_pressed(_Constants.INPUT_PAUSE):
			_cancel_build_mode()
			DebugLog.log_command("PlayerController", "build", "placement cancelled")
		return

	# Rally placement mode: left-click places the point (standard command-card
	# UX), right-click cancels. Swallow the input either way.
	if _rally_armed:
		if event.is_action_pressed(_Constants.INPUT_SELECT):
			_set_rally_point(get_viewport().get_mouse_position())
		elif event.is_action_pressed(_Constants.INPUT_COMMAND):
			_rally_armed = false
			DebugLog.log_command("PlayerController", "rally", "placement cancelled")
		return

	if event.is_action_pressed(_Constants.INPUT_SELECT):
		_drag_start = get_viewport().get_mouse_position()
		_is_dragging = true
		if selection_box:
			selection_box.position = _drag_start
			selection_box.size = Vector2.ZERO
			selection_box.visible = true
	elif event.is_action_released(_Constants.INPUT_SELECT):
		if _is_dragging:
			var end: Vector2 = get_viewport().get_mouse_position()
			if end.distance_to(_drag_start) < 8:
				_single_select(_drag_start)
			else:
				_box_select(_drag_start, end)
			_is_dragging = false
			if selection_box:
				selection_box.visible = false
	elif event.is_action_pressed(_Constants.INPUT_COMMAND):
		_issue_command(get_viewport().get_mouse_position())
	elif event.is_action_pressed(_Constants.INPUT_SELECT_ALL):
		_select_units(get_tree().get_nodes_in_group("player"))
	elif event.is_action_pressed(_Constants.INPUT_SELECT_MINERS):
		_select_units(_filter_miners(get_tree().get_nodes_in_group("player")))
	elif event.is_action_pressed(_Constants.INPUT_SELECT_FIGHTERS):
		_select_units(_filter_fighters(get_tree().get_nodes_in_group("player")))
	elif event.is_action_pressed(_Constants.INPUT_SELECT_DRAGONS):
		_select_units(_filter_dragons(get_tree().get_nodes_in_group("player")))
	elif event.is_action_pressed(_Constants.INPUT_CAMERA_ZOOM_IN):
		_zoom_factor = clampf(_zoom_factor * 1.1, _zoom_min, _zoom_max)
		_apply_zoom()
	elif event.is_action_pressed(_Constants.INPUT_CAMERA_ZOOM_OUT):
		_zoom_factor = clampf(_zoom_factor / 1.1, _zoom_min, _zoom_max)
		_apply_zoom()
	elif event.is_action_pressed(_Constants.INPUT_TRAIN_MINER):
		train_unit("miner")
	elif event.is_action_pressed(_Constants.INPUT_TRAIN_SWORDSMAN):
		train_unit("swordsman")
	elif event.is_action_pressed(_Constants.INPUT_TRAIN_ARCHER):
		train_unit("archer")
	elif event.is_action_pressed(_Constants.INPUT_TRAIN_WIZARD):
		train_unit("wizard")
	elif event.is_action_pressed(_Constants.INPUT_TRAIN_DRAGON):
		train_unit("dragon")
	elif event.is_action_pressed(_Constants.INPUT_TOGGLE_VIEW):
		_toggle_view()
	elif event.is_action_pressed(_Constants.INPUT_TOGGLE_RESEARCH):
		var hud: CanvasLayer = get_node_or_null("/root/Main/UI/HUD")
		if hud:
			hud.toggle_research_panel()
	elif event.is_action_pressed(_Constants.INPUT_KILL_UNITS):
		kill_selected()
	elif event.is_action_pressed(_Constants.INPUT_PAUSE):
		get_tree().paused = not get_tree().paused

	if _is_dragging and event is InputEventMouseMotion:
		_update_selection_box(get_viewport().get_mouse_position())


func _update_selection_box(current: Vector2) -> void:
	if selection_box == null:
		return
	selection_box.position = Vector2(min(_drag_start.x, current.x), min(_drag_start.y, current.y))
	selection_box.size = (_drag_start - current).abs()


func _single_select(screen_pos: Vector2) -> void:
	var world_pos: Vector2 = _screen_to_world(screen_pos)
	var shift: bool = Input.is_key_pressed(KEY_SHIFT)
	# Check units first.
	var clicked_unit: Unit = _unit_at(world_pos)
	if clicked_unit != null and clicked_unit.team == GameManager.Team.PLAYER:
		if shift:
			if not _selected_units.has(clicked_unit):
				_selected_units.append(clicked_unit)
			_select_units(_selected_units)
		else:
			_select_units([clicked_unit])
		return
	# Then buildings.
	var clicked_building: Node2D = _building_at(world_pos)
	if clicked_building != null and clicked_building.get("team") == GameManager.Team.PLAYER:
		if not shift:
			_select_units([])
		# TODO: building selection UI.
		return
	if shift:
		return
	_select_units([])


func _box_select(start: Vector2, end: Vector2) -> void:
	var units: Array = []
	var min_p: Vector2 = Vector2(min(start.x, end.x), min(start.y, end.y))
	var max_p: Vector2 = Vector2(max(start.x, end.x), max(start.y, end.y))
	var canvas: Transform2D = get_viewport().get_canvas_transform()
	for unit in get_tree().get_nodes_in_group("player"):
		# Feet or combat body (flying dragons) — either inside the box counts.
		var feet_sp: Vector2 = canvas * unit.global_position
		var combat_sp: Vector2 = canvas * unit.get_combat_position()
		var feet_in: bool = feet_sp.x >= min_p.x and feet_sp.x <= max_p.x and feet_sp.y >= min_p.y and feet_sp.y <= max_p.y
		var combat_in: bool = combat_sp.x >= min_p.x and combat_sp.x <= max_p.x and combat_sp.y >= min_p.y and combat_sp.y <= max_p.y
		if feet_in or combat_in:
			units.append(unit)
	if Input.is_key_pressed(KEY_SHIFT):
		for u in units:
			if not _selected_units.has(u):
				_selected_units.append(u)
		_select_units(_selected_units)
	else:
		_select_units(units)


func _select_units(units: Array) -> void:
	for u in _selected_units:
		if is_instance_valid(u):
			u.selected = false
			u.queue_redraw()
	_selected_units = units
	for u in _selected_units:
		if is_instance_valid(u):
			u.selected = true
			u.queue_redraw()


func _issue_command(screen_pos: Vector2) -> void:
	# Belt and braces: a right-click while rally placement is armed cancels it
	# (normally swallowed earlier in _unhandled_input).
	if _rally_armed:
		_rally_armed = false
		return

	# Drop dead units from the selection before issuing anything.
	_selected_units = _selected_units.filter(func(u): return is_instance_valid(u))
	if _selected_units.is_empty():
		DebugLog.log_reject("PlayerController", "RMB command", "no selected units")
		return
	var world_pos: Vector2 = _screen_to_world(screen_pos)
	var grid_pos: Vector2i = _grid.world_to_grid(world_pos)

	# Resolution order is deterministic and exclusive: exactly one command (or
	# one rejection) is produced per right-click.
	# 1. Enemy unit clicked -> attack with fighters.
	var enemy_unit: Unit = _enemy_unit_at(world_pos)
	if enemy_unit != null:
		var fighters: Array = _filter_fighters(_selected_units)
		if fighters.is_empty():
			_reject_command("attack_unit", "no fighters selected", world_pos)
			return
		# Only order units that can actually hurt the target (e.g. dragons are
		# immune to swordsmen — mixed selections should still send archers).
		var capable: Array = []
		for u in fighters:
			if u.can_damage_unit(enemy_unit):
				capable.append(u)
		if capable.is_empty():
			_reject_command("attack_unit", "target immune to selected units", world_pos)
			return
		DebugLog.log_command("PlayerController", "attack_unit", "target=%d fighters=%d" % [enemy_unit.get_instance_id(), capable.size()])
		for u in capable:
			u.attack_unit(enemy_unit)
		return

	# 2. Enemy building clicked -> attack with fighters.
	var enemy_building: Node2D = _enemy_building_at(world_pos)
	if enemy_building != null:
		var fighters: Array = _filter_fighters(_selected_units)
		if fighters.is_empty():
			_reject_command("attack_building", "no fighters selected", world_pos)
			return
		DebugLog.log_command("PlayerController", "attack_building", "target=%d fighters=%d" % [enemy_building.get_instance_id(), fighters.size()])
		for u in fighters:
			u.attack_building(enemy_building)
		return

	# 2b. Enemy lantern clicked -> attack with fighters (kills its vision).
	var enemy_lantern: Node2D = _enemy_lantern_at(world_pos)
	if enemy_lantern != null:
		var fighters: Array = _filter_fighters(_selected_units)
		if fighters.is_empty():
			_reject_command("attack_lantern", "no fighters selected", world_pos)
			return
		DebugLog.log_command("PlayerController", "attack_lantern", "target=%d fighters=%d" % [enemy_lantern.get_instance_id(), fighters.size()])
		for u in fighters:
			u.attack_building(enemy_lantern)
		return

	# 3. Central wall clicked with miners selected -> breach.
	var miners: Array = _filter_miners(_selected_units)
	if _grid.is_central_wall(grid_pos) and not miners.is_empty():
		DebugLog.log_command("PlayerController", "breach_wall", "cell=%s miners=%d" % [str(grid_pos), miners.size()])
		for u in miners:
			u.mine_cell(grid_pos)
		return

	# 4. Diggable cell clicked with miners selected -> mine it.
	var cell: GridWorld.Cell = _grid.get_cell(grid_pos)
	var diggable: bool = cell != null and (cell.type == GridWorld.CellType.DIRT or cell.type == GridWorld.CellType.ORE)
	if diggable and not miners.is_empty():
		DebugLog.log_command("PlayerController", "mine_cell", "cell=%s miners=%d" % [str(grid_pos), miners.size()])
		for u in miners:
			u.mine_cell(grid_pos)
		return

	# 5. Own mine entry clicked -> deposit (miners with coin), enter, or exit.
	var entry: Node2D = _mine_entry_at(world_pos)
	if entry != null and entry.get("team") == GameManager.Team.PLAYER:
		DebugLog.log_command("PlayerController", "mine_entry", "entry=%d units=%d" % [entry.get_instance_id(), _selected_units.size()])
		for u in _selected_units:
			if u.data.is_miner and u.carried_coin > 0:
				u.deposit_coin()
			elif u.is_underground:
				u.exit_mine()
			else:
				u.enter_mine()
		return

	# 6. Enemy mine entry clicked -> reject: units can never enter the enemy mine.
	if entry != null and entry.get("team") != GameManager.Team.PLAYER:
		_reject_command("mine_entry", "cannot enter the enemy mine", world_pos)
		return

	# 7. Default: move.
	DebugLog.log_command("PlayerController", "move_to", "pos=%s units=%d" % [str(world_pos), _selected_units.size()])
	for u in _selected_units:
		u.move_to(world_pos)


func _reject_command(action: String, reason: String, at: Vector2) -> void:
	DebugLog.log_reject("PlayerController", action, reason)
	var popup: Node2D = _REJECT_POPUP.instantiate()
	popup.global_position = at
	get_tree().current_scene.add_child(popup)


func _screen_to_world(screen_pos: Vector2) -> Vector2:
	# Camera2D has no project_position() (that is a Camera3D API); convert via
	# the viewport's canvas transform, which also handles zoom and stretch.
	return get_viewport().get_canvas_transform().affine_inverse() * screen_pos


func _unit_at(world_pos: Vector2) -> Unit:
	var best: Unit = null
	var best_dist: float = 999999.0
	for unit in get_tree().get_nodes_in_group("units"):
		var d: float = unit.get_combat_position().distance_to(world_pos)
		if d < GridWorld.CELL_SIZE / 1.5 and d < best_dist:
			best_dist = d
			best = unit
	return best


func _enemy_unit_at(world_pos: Vector2) -> Unit:
	var unit: Unit = _unit_at(world_pos)
	# Fog of War: hidden enemy units cannot be clicked (their ghost is a
	# memory, not a target).
	if unit != null and unit.team != GameManager.Team.PLAYER \
			and _grid.is_visible_to(GameManager.Team.PLAYER, unit.global_position):
		return unit
	return null


## Enemy lantern near the click point (Fog of War: only while visible).
func _enemy_lantern_at(world_pos: Vector2) -> Node2D:
	for lantern in get_tree().get_nodes_in_group("lanterns"):
		if lantern.team == GameManager.Team.PLAYER:
			continue
		if not _grid.is_visible_to(GameManager.Team.PLAYER, lantern.global_position):
			continue
		if lantern.global_position.distance_to(world_pos) < GridWorld.CELL_SIZE:
			return lantern
	return null


func _building_at(world_pos: Vector2) -> Node2D:
	# Pick against the building's full body rect (base plus sprite height)
	# instead of a radius around its base point, so clicks anywhere on the
	# building register as building clicks.
	var best: Node2D = null
	var best_dist: float = 999999.0
	for building in get_tree().get_nodes_in_group("buildings"):
		var rect: Rect2 = building.call("get_bounds_rect")
		if not rect.has_point(world_pos):
			continue
		var d: float = building.global_position.distance_squared_to(world_pos)
		if d < best_dist:
			best_dist = d
			best = building
	return best


func _enemy_building_at(world_pos: Vector2) -> Node2D:
	var building: Node2D = _building_at(world_pos)
	if building != null and building.get("team") != GameManager.Team.PLAYER:
		return building
	return null


func _mine_entry_at(world_pos: Vector2) -> Node2D:
	var best: Node2D = null
	var best_dist: float = 999999.0
	for entry in get_tree().get_nodes_in_group("mine_entries"):
		var d: float = entry.global_position.distance_to(world_pos)
		if d < GridWorld.CELL_SIZE * 2.0 and d < best_dist:
			best_dist = d
			best = entry
	return best


func _filter_miners(units: Array) -> Array:
	return units.filter(func(u): return u.data.is_miner)


func _filter_fighters(units: Array) -> Array:
	return units.filter(func(u): return u.data.is_fighter)


func _filter_dragons(units: Array) -> Array:
	return units.filter(func(u): return u.data != null and u.data.unit_name.to_lower() == "dragon")


# ---------- UI callbacks ----------

func train_unit(unit_id: String) -> bool:
	for building in get_tree().get_nodes_in_group("buildings"):
		if building.get("team") == GameManager.Team.PLAYER:
			return building.call("queue_unit", unit_id)
	return false


func upgrade_miner() -> void:
	EconomyManager.upgrade_miner(GameManager.Team.PLAYER)


func upgrade_fighter(unit_id: String) -> void:
	EconomyManager.upgrade_fighter(GameManager.Team.PLAYER, unit_id)


func _toggle_view() -> void:
	set_view(_view_mode == ViewMode.SURFACE)


## Both layers are always rendered, so the view toggle is a camera bookmark:
## it saves the camera position of the view being left and jumps to the last
## position of the requested view (surface base / own mine underground).
func set_view(underground: bool) -> void:
	var new_mode: ViewMode = ViewMode.UNDERGROUND if underground else ViewMode.SURFACE
	if new_mode == _view_mode or camera == null:
		return
	if _view_mode == ViewMode.SURFACE:
		_last_surface_cam_pos = camera.position
	else:
		_last_underground_cam_pos = camera.position
	_view_mode = new_mode
	# Slide to the bookmark instead of snapping (Phase 8 game feel).
	_view_slide_target = _last_underground_cam_pos if underground else _last_surface_cam_pos
	DebugLog.log_command("PlayerController", "set_view", "UNDERGROUND" if underground else "SURFACE")
	view_mode_changed.emit(_view_mode)


func is_underground_view() -> bool:
	return _view_mode == ViewMode.UNDERGROUND


func get_current_view_mode() -> ViewMode:
	return _view_mode


## Rally placement: army-wide order, so it does not need a selection. Called
## with the screen position of the confirming left-click.
func _set_rally_point(screen_pos: Vector2) -> void:
	_rally_armed = false
	var world_pos: Vector2 = _screen_to_world(screen_pos)
	var fighters: Array = _filter_fighters(get_tree().get_nodes_in_group("player"))
	if fighters.is_empty():
		_reject_command("rally", "no fighters", world_pos)
		return
	DebugLog.log_command("PlayerController", "rally", "point=%s fighters=%d" % [str(world_pos), fighters.size()])
	for u in fighters:
		u.rally_to(world_pos)


func set_stance(stance: String) -> void:
	# [DECISION] Stances are army-wide orders to every living player fighter;
	# right-click issues orders to the current selection only. Attack/Defend/
	# Garrison are also persistent modes: the choice is remembered and applied
	# to every fighter trained afterwards (see _on_fighter_spawned), so setting
	# a mode with zero fighters is valid.
	if stance in ["attack", "defend", "garrison"]:
		# Choosing any stance cancels a pending rally-point placement.
		_rally_armed = false
		_cancel_build_mode()
		_current_stance = stance
	var fighters: Array = _filter_fighters(get_tree().get_nodes_in_group("player"))
	match stance:
		"rally":
			if fighters.is_empty():
				DebugLog.log_reject("PlayerController", "set_stance rally", "no fighters")
				return
			# No immediate order: the next left-click places the rally point
			# (see _set_rally_point; right-click cancels). Fighters then hunt
			# everything on the surface — enemy miners included.
			_rally_armed = true
			DebugLog.log_command("PlayerController", "stance rally", "armed; awaiting rally point left-click")
		"attack":
			var enemy_building: Node2D = _enemy_building()
			if enemy_building == null:
				DebugLog.log_reject("PlayerController", "set_stance attack", "no enemy building")
				return
			DebugLog.log_command("PlayerController", "stance attack", "fighters=%d" % fighters.size())
			for u in fighters:
				u.attack_building(enemy_building)
		"defend":
			DebugLog.log_command("PlayerController", "stance defend", "fighters=%d" % fighters.size())
			for u in fighters:
				u.stop()
		"garrison":
			# Fall back and defend the base: underground fighters climb out,
			# everyone gathers at the home building and holds there.
			DebugLog.log_command("PlayerController", "stance garrison", "fighters=%d" % fighters.size())
			for u in fighters:
				u.garrison_home()
		_:
			DebugLog.log_reject("PlayerController", "set_stance", "unknown stance " + stance)


func get_stance() -> String:
	return _current_stance


func _enemy_building() -> Node2D:
	for b in get_tree().get_nodes_in_group("buildings"):
		if b.get("team") != GameManager.Team.PLAYER:
			return b
	return null


func get_selected_units() -> Array:
	return _selected_units


## Disband every selected unit (no coin refund — frees population slots).
func kill_selected() -> void:
	_selected_units = _selected_units.filter(func(u): return is_instance_valid(u))
	if _selected_units.is_empty():
		DebugLog.log_reject("PlayerController", "kill_selected", "no selected units")
		return
	DebugLog.log_command("PlayerController", "kill_selected", "units=%d" % _selected_units.size())
	var victims: Array = _selected_units.duplicate()
	_select_units([])  # dying units must not linger in the selection
	for u in victims:
		u.kill()


func is_rally_armed() -> bool:
	return _rally_armed


# ---------- Lantern placement (Revamp Phase 1) ----------

## Enters lantern placement mode: a ghost follows the cursor until left-click
## confirms or right-click/Esc cancels. kind is "lantern" (surface) or
## "underground_lantern".
func start_build_placement(kind: String) -> void:
	_cancel_build_mode()
	_rally_armed = false
	_build_mode = kind
	_build_ghost = Node2D.new()
	_build_ghost.name = "BuildGhost"
	var texture: Texture2D
	var vision: int
	if kind == "underground_lantern":
		texture = preload("res://frost_mines_assets/props/lantern_underground.png")
		vision = _Constants.UNDERGROUND_LANTERN_VISION
	else:
		texture = preload("res://frost_mines_assets/props/lantern_t1.png")
		vision = _Constants.LANTERN_T1_VISION
	var sprite: Sprite2D = Sprite2D.new()
	sprite.texture = texture
	if kind != "underground_lantern":
		# Surface lanterns stand on the ground line at the bottom of the row.
		sprite.position = Vector2(0, 16.0 - texture.get_height() / 2.0)
	_build_ghost.add_child(sprite)
	# Faint ring showing the vision radius the lantern would provide.
	var ring: Sprite2D = Sprite2D.new()
	ring.texture = _GHOST_RING
	var diameter: float = vision * GridWorld.CELL_SIZE * 2.0
	ring.scale = Vector2.ONE * (diameter / _GHOST_RING.get_width())
	ring.modulate = Color(1.0, 0.85, 0.4, 0.3)
	_build_ghost.add_child(ring)
	add_child(_build_ghost)
	DebugLog.log_command("PlayerController", "build", "placement mode: " + kind)


func _cancel_build_mode() -> void:
	if _build_mode == "":
		return
	_build_mode = ""
	if _build_ghost != null:
		_build_ghost.queue_free()
		_build_ghost = null


func is_build_mode_active() -> bool:
	return _build_mode != ""


## Validates a lantern placement cell. Returns "" when valid, otherwise a
## human-readable reason (also used to tint the placement ghost).
func _lantern_placement_error(kind: String, cell: Vector2i) -> String:
	var underground: bool = kind == "underground_lantern"
	var team: GameManager.Team = GameManager.Team.PLAYER
	var same_kind: Array = []
	for lantern in get_tree().get_nodes_in_group("lanterns"):
		if lantern.team == team and lantern.is_underground_lantern == underground:
			same_kind.append(lantern)
	if underground:
		if cell.y < 1:
			return "must be placed underground"
		if cell.x > -2:
			return "own half of the mine only"
		# Carved tunnel cells are erased from the grid; anything still present
		# (dirt/ore/wall) is solid and cannot hold a lantern.
		if _grid.get_cell(cell) != null:
			return "needs a dug-out tunnel cell"
		if same_kind.size() >= _Constants.UNDERGROUND_LANTERN_MAX_COUNT:
			return "max underground lanterns reached"
		for lantern in same_kind:
			if Vector2(_grid.world_to_grid(lantern.global_position) - cell).length() < _Constants.UNDERGROUND_LANTERN_MIN_DISTANCE:
				return "too close to another lantern"
	else:
		if cell.y != 0:
			return "must be placed on the surface"
		if cell.x > -2:
			return "own half of the map only"
		for lantern in same_kind:
			if _grid.world_to_grid(lantern.global_position) == cell:
				return "" if lantern.can_upgrade() else "lantern fully upgraded"
		if same_kind.size() >= _Constants.LANTERN_MAX_COUNT:
			return "max lanterns reached"
		for lantern in same_kind:
			if Vector2(_grid.world_to_grid(lantern.global_position) - cell).length() < _Constants.LANTERN_MIN_DISTANCE:
				return "too close to another lantern"
	return ""


## Own surface lantern standing on the given cell (upgrade target), if any.
func _surface_lantern_at_cell(cell: Vector2i) -> Node2D:
	for lantern in get_tree().get_nodes_in_group("lanterns"):
		if lantern.team == GameManager.Team.PLAYER and not lantern.is_underground_lantern \
				and _grid.world_to_grid(lantern.global_position) == cell:
			return lantern
	return null


## Validates and executes a lantern placement (or in-place tier upgrade when
## the cell already holds an own surface lantern). Spends the coin and spawns
## the structure on success. Public so the HUD, tests, and (later) the AI can
## share one code path.
func try_place_lantern(kind: String, world_pos: Vector2) -> bool:
	var cell: Vector2i = _grid.world_to_grid(world_pos)
	var err: String = _lantern_placement_error(kind, cell)
	if err != "":
		_reject_command("build", err, world_pos)
		return false
	var team: GameManager.Team = GameManager.Team.PLAYER
	# In-place upgrade: T1 → T2 → T3 at the same location.
	if kind == "lantern":
		var existing: Node2D = _surface_lantern_at_cell(cell)
		if existing != null:
			var upgrade_cost: int = Lantern.cost_for(false, existing.tier + 1)
			if not EconomyManager.spend_coin(team, upgrade_cost):
				_reject_command("build", "not enough coin (%d needed)" % upgrade_cost, world_pos)
				return false
			existing.total_cost += upgrade_cost
			existing.upgrade()
			DebugLog.log_command("PlayerController", "build", "lantern upgraded to T%d at %s" % [existing.tier, str(cell)])
			return true
	var underground: bool = kind == "underground_lantern"
	var cost: int = Lantern.cost_for(underground, 1)
	if not EconomyManager.spend_coin(team, cost):
		_reject_command("build", "not enough coin (%d needed)" % cost, world_pos)
		return false
	var lantern: Lantern = _LANTERN_SCENE.instantiate()
	lantern.team = team
	lantern.is_underground_lantern = underground
	lantern.total_cost = cost
	lantern.global_position = _grid.grid_to_world(cell)
	get_node("/root/Main/Structures").add_child(lantern)
	DebugLog.log_command("PlayerController", "build", "%s at %s" % [kind, str(cell)])
	return true
