class_name PlayerController
extends Node

const _Constants = preload("res://scripts/autoload/constants.gd")

@export var camera: Camera2D
@export var selection_box: ColorRect

var _selected_units: Array = []
var _drag_start: Vector2 = Vector2.ZERO
var _is_dragging: bool = false
var _camera_speed: float = 600.0
var _zoom_min: float = 0.4
var _zoom_max: float = 2.0

@onready var _grid: GridWorld = get_node("/root/Main/World/GridWorld")

var _underground_view: bool = true


func _ready() -> void:
	if selection_box:
		selection_box.visible = false


func _process(delta: float) -> void:
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
	# Clamp camera within world bounds. Only clamp when the viewport is smaller
	# than the playable area; otherwise the whole world is visible and the player
	# should be free to pan (e.g. to follow surface/underground views).
	var half_size: Vector2 = get_viewport().get_visible_rect().size / (2.0 * camera.zoom)
	var min_pos: Vector2 = Vector2((GridWorld.X_MIN - 2) * GridWorld.CELL_SIZE, -300)
	var max_pos: Vector2 = Vector2((GridWorld.X_MAX + 3) * GridWorld.CELL_SIZE, (GridWorld.Y_MAX + 4) * GridWorld.CELL_SIZE)
	var lo: Vector2 = min_pos + half_size
	var hi: Vector2 = max_pos - half_size
	if lo.x <= hi.x:
		camera.position.x = clampf(camera.position.x, lo.x, hi.x)
	if lo.y <= hi.y:
		camera.position.y = clampf(camera.position.y, lo.y, hi.y)


func _unhandled_input(event: InputEvent) -> void:
	if not GameManager.game_active:
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
	elif event.is_action_pressed(_Constants.INPUT_CAMERA_ZOOM_IN):
		camera.zoom = (camera.zoom * 1.1).clamp(Vector2(_zoom_min, _zoom_min), Vector2(_zoom_max, _zoom_max))
	elif event.is_action_pressed(_Constants.INPUT_CAMERA_ZOOM_OUT):
		camera.zoom = (camera.zoom / 1.1).clamp(Vector2(_zoom_min, _zoom_min), Vector2(_zoom_max, _zoom_max))
	elif event.is_action_pressed(_Constants.INPUT_TRAIN_MINER):
		train_unit("miner")
	elif event.is_action_pressed(_Constants.INPUT_TRAIN_SWORDSMAN):
		train_unit("swordsman")
	elif event.is_action_pressed(_Constants.INPUT_TRAIN_ARCHER):
		train_unit("archer")
	elif event.is_action_pressed(_Constants.INPUT_TRAIN_WIZARD):
		train_unit("wizard")
	elif event.is_action_pressed(_Constants.INPUT_TOGGLE_VIEW):
		_toggle_view()
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
	for unit in get_tree().get_nodes_in_group("player"):
		var sp: Vector2 = camera.unproject_position(unit.global_position)
		if sp.x >= min_p.x and sp.x <= max_p.x and sp.y >= min_p.y and sp.y <= max_p.y:
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
	if _selected_units.is_empty():
		return
	var world_pos: Vector2 = _screen_to_world(screen_pos)

	# Enemy unit/building clicked -> attack with fighters.
	var enemy_unit: Unit = _enemy_unit_at(world_pos)
	if enemy_unit != null:
		for u in _selected_units:
			if u.data.is_fighter:
				u.attack_unit(enemy_unit)
		return
	var enemy_building: Node2D = _enemy_building_at(world_pos)
	if enemy_building != null:
		for u in _selected_units:
			if u.data.is_fighter:
				u.attack_building(enemy_building)
		return

	# Central wall clicked -> breach with miners.
	var grid_pos: Vector2i = _grid.world_to_grid(world_pos)
	if _grid.is_central_wall(grid_pos):
		var any_miner: bool = false
		for u in _selected_units:
			if u.data.is_miner:
				u.mine_cell(grid_pos)
				any_miner = true
		if any_miner:
			return

	# Diggable cell clicked -> mine with miners.
	if _grid.has_cell(grid_pos) and _grid.get_cell(grid_pos).type != GridWorld.CellType.SURFACE_GROUND:
		var any_miner: bool = false
		for u in _selected_units:
			if u.data.is_miner:
				u.mine_cell(grid_pos)
				any_miner = true
		if any_miner:
			return

	# Mine entry clicked -> deposit (miners with coin), enter, or exit mine.
	var entry: Node2D = _mine_entry_at(world_pos)
	if entry != null and entry.get("team") == GameManager.Team.PLAYER:
		for u in _selected_units:
			if u.data.is_miner and u.carried_coin > 0:
				u.deposit_coin()
			elif u.is_underground:
				u.exit_mine()
			else:
				u.enter_mine()
		return

	# Default move.
	for u in _selected_units:
		u.move_to(world_pos)


func _screen_to_world(screen_pos: Vector2) -> Vector2:
	if camera == null:
		return screen_pos
	return camera.project_position(screen_pos, 0)


func _unit_at(world_pos: Vector2) -> Unit:
	var best: Unit = null
	var best_dist: float = 999999.0
	for unit in get_tree().get_nodes_in_group("units"):
		var d: float = unit.global_position.distance_to(world_pos)
		if d < GridWorld.CELL_SIZE / 1.5 and d < best_dist:
			best_dist = d
			best = unit
	return best


func _enemy_unit_at(world_pos: Vector2) -> Unit:
	var unit: Unit = _unit_at(world_pos)
	if unit != null and unit.team != GameManager.Team.PLAYER:
		return unit
	return null


func _building_at(world_pos: Vector2) -> Node2D:
	var best: Node2D = null
	var best_dist: float = 999999.0
	for building in get_tree().get_nodes_in_group("buildings"):
		var d: float = building.global_position.distance_to(world_pos)
		if d < building.get("width_cells") * GridWorld.CELL_SIZE / 2.0 and d < best_dist:
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


# ---------- UI callbacks ----------

func train_unit(unit_id: String) -> bool:
	for building in get_tree().get_nodes_in_group("buildings"):
		if building.get("team") == GameManager.Team.PLAYER:
			return building.call("queue_unit", unit_id)
	return false


func upgrade_miner() -> void:
	EconomyManager.upgrade_miner(GameManager.Team.PLAYER)


func _toggle_view() -> void:
	set_view(not _underground_view)


func set_view(underground: bool) -> void:
	if camera == null:
		return
	_underground_view = underground
	camera.position.y = 400.0 if _underground_view else -150.0


func is_underground_view() -> bool:
	return _underground_view


func set_stance(stance: String) -> void:
	if stance == "attack":
		# Move all selected fighters toward enemy building.
		var enemy_building: Node2D = null
		for b in get_tree().get_nodes_in_group("buildings"):
			if b.get("team") != GameManager.Team.PLAYER:
				enemy_building = b
				break
		if enemy_building != null:
			for u in _selected_units:
				if u.data.is_fighter:
					u.attack_building(enemy_building)
	elif stance == "defend":
		for u in _selected_units:
			u.stop()
	elif stance == "garrison":
		for u in _selected_units:
			if u.is_underground:
				u.exit_mine()
			else:
				u.enter_mine()


func get_selected_units() -> Array:
	return _selected_units
