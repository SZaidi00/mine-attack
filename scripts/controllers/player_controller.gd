class_name PlayerController
extends Node

const _Constants = preload("res://scripts/autoload/constants.gd")
const _REJECT_POPUP: PackedScene = preload("res://scenes/effects/reject_popup.tscn")
const _LANTERN_SCENE: PackedScene = preload("res://scenes/lantern.tscn")
const _GHOST_RING: Texture2D = preload("res://frost_mines_assets/effects/selection_ring.png")

const PlayerSelection := preload("res://scripts/controllers/player_selection.gd")
const PlayerCommands := preload("res://scripts/controllers/player_commands.gd")
const PlayerCamera := preload("res://scripts/controllers/player_camera.gd")
const PlayerBuildPlacement := preload("res://scripts/controllers/player_build_placement.gd")

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

var _selection: PlayerSelection
var _commands: PlayerCommands
var _camera_helper: PlayerCamera
var _build_placement: PlayerBuildPlacement


func _init() -> void:
	_selection = PlayerSelection.new(self)
	_commands = PlayerCommands.new(self)
	_camera_helper = PlayerCamera.new(self)
	_build_placement = PlayerBuildPlacement.new(self)


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
	_camera_helper._init_view_positions()
	_connect_building_shake()
	_connect_building_spawns()
	_camera_helper._apply_zoom()
	get_window().size_changed.connect(_camera_helper._apply_zoom)
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


func _player_mine_entry() -> Node2D:
	for entry in get_tree().get_nodes_in_group("mine_entries"):
		if entry.get("team") == GameManager.Team.PLAYER:
			return entry
	return null


func _enemy_building() -> Node2D:
	for b in get_tree().get_nodes_in_group("buildings"):
		if b.get("team") != GameManager.Team.PLAYER:
			return b
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


func _process(_delta: float) -> void:
	_build_placement._update_ghost()
	_camera_helper._process_camera(_delta)


func _unhandled_input(event: InputEvent) -> void:
	if not GameManager.game_active:
		return

	# Lantern placement mode: left-click confirms (stays active on an invalid
	# spot so the player can adjust), right-click or Esc cancels. Swallowed
	# either way so no selection/command leaks through.
	if _build_mode != "":
		_build_placement._handle_input(event)
		return

	# Rally placement mode: left-click places the point (standard command-card
	# UX), right-click cancels. Swallow the input either way.
	if _rally_armed:
		_commands._handle_rally_input(event)
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
				_selection._single_select(_drag_start)
			else:
				_selection._box_select(_drag_start, end)
			_is_dragging = false
			if selection_box:
				selection_box.visible = false
	elif event.is_action_pressed(_Constants.INPUT_COMMAND):
		_commands._issue_command(get_viewport().get_mouse_position())
	elif event.is_action_pressed(_Constants.INPUT_SELECT_ALL):
		_selection._select_units(get_tree().get_nodes_in_group("player"))
	elif event.is_action_pressed(_Constants.INPUT_SELECT_MINERS):
		_selection._select_units(_selection._filter_miners(get_tree().get_nodes_in_group("player")))
	elif event.is_action_pressed(_Constants.INPUT_SELECT_FIGHTERS):
		_selection._select_units(_selection._filter_fighters(get_tree().get_nodes_in_group("player")))
	elif event.is_action_pressed(_Constants.INPUT_SELECT_DRAGONS):
		_selection._select_units(_selection._filter_dragons(get_tree().get_nodes_in_group("player")))
	elif event.is_action_pressed(_Constants.INPUT_CAMERA_ZOOM_IN):
		_camera_helper._zoom_in()
	elif event.is_action_pressed(_Constants.INPUT_CAMERA_ZOOM_OUT):
		_camera_helper._zoom_out()
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
		_camera_helper._toggle_view()
	elif event.is_action_pressed(_Constants.INPUT_TOGGLE_RESEARCH):
		var hud: CanvasLayer = get_node_or_null("/root/Main/UI/HUD")
		if hud:
			hud.toggle_research_panel()
	elif event.is_action_pressed(_Constants.INPUT_KILL_UNITS):
		kill_selected()
	elif event.is_action_pressed(_Constants.INPUT_PAUSE):
		get_tree().paused = not get_tree().paused

	if _is_dragging and event is InputEventMouseMotion:
		_selection._update_selection_box(get_viewport().get_mouse_position())


# ---------- Public API wrappers ----------

func train_unit(unit_id: String) -> bool:
	return _commands.train_unit(unit_id)


func upgrade_miner() -> void:
	_commands.upgrade_miner()


func upgrade_fighter(unit_id: String) -> void:
	_commands.upgrade_fighter(unit_id)


func set_stance(stance: String) -> void:
	_commands.set_stance(stance)


func get_stance() -> String:
	return _current_stance


func set_view(underground: bool) -> void:
	_camera_helper.set_view(underground)


func is_underground_view() -> bool:
	return _camera_helper.is_underground_view()


func get_current_view_mode() -> ViewMode:
	return _camera_helper.get_current_view_mode()


func get_selected_units() -> Array:
	return _selected_units


func kill_selected() -> void:
	_commands.kill_selected()


func is_rally_armed() -> bool:
	return _rally_armed


func start_build_placement(kind: String) -> void:
	_build_placement.start_build_placement(kind)


func is_build_mode_active() -> bool:
	return _build_placement.is_build_mode_active()


func try_place_structure(kind: String, world_pos: Vector2) -> bool:
	return _build_placement.try_place_structure(kind, world_pos)


func try_place_lantern(kind: String, world_pos: Vector2) -> bool:
	return _build_placement.try_place_lantern(kind, world_pos)


## Backwards-compatibility wrappers: the old direct helpers now live in
## PlayerSelection, but the test suite calls them on the controller.
func _filter_dragons(units: Array) -> Array:
	return _selection._filter_dragons(units)


func _select_units(units: Array) -> void:
	_selection._select_units(units)
