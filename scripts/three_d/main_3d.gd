## Phase 1 shell (roadmap/3d-conversion/phase-1-25d-port.md).
##
## Launched as the main scene; hosts the untouched 2D simulation — mounted
## at "/root/Main" so every hard-coded path resolves exactly as shipped — and
## the 3D presentation (World3D: terrain, entity proxies, effects container)
## on top of it. The sim's CanvasItem layers are hidden; the simulation runs
## untouched (presentation reads sim state, never writes it).
##
## The camera rig replaces player_camera.gd's visible role: PlayerController
## stays the single input authority (its Tab handling emits view_mode_changed,
## which this rig follows), while pan/zoom are applied to the 3D camera. The
## 2D Camera2D keeps receiving the same input invisibly — harmless, and it
## keeps player_camera.gd's bookmarks/logic exercised for the GUT suite.
extends Node3D

const SIM_SCENE: PackedScene = preload("res://scenes/main.tscn")

## 3D units per 2D pixel. The map is ~2560x800 px, i.e. ~26x8 units.
const WORLD_SCALE: float = 0.01
const PITCH_DEGREES: float = 55.0
const DOLLY_MIN: float = 3.0
const DOLLY_MAX: float = 25.0
const DOLLY_WHEEL_STEP: float = 1.1
const DOLLY_START: float = 12.0
const PAN_SPEED: float = 10.0
const EDGE_PAN_MARGIN: float = 24.0

var _sim: Node2D
var _pc: Node
var _camera: Camera3D
var _terrain: Node3D
var _proxies: Node3D
var _focus: Vector3 = Vector3.ZERO
var _surface_focus: Vector3
var _underground_focus: Vector3
var _dolly: float = DOLLY_START


func _ready() -> void:
	_camera = $CameraRig/Camera3D
	_terrain = $World3D/Terrain3D
	_proxies = $World3D/EntityProxies

	# Mount the untouched 2D game at "/root/Main" (deferred so the whole
	# scene enters the tree normally), then hide its CanvasItem layers: the
	# sim keeps running, only its 2D drawing is suppressed. The HUD
	# (CanvasLayer) intentionally stays visible — Controls overlay a 3D
	# viewport unchanged.
	_sim = SIM_SCENE.instantiate()
	get_tree().root.add_child.call_deferred(_sim)
	await _sim.ready
	get_tree().current_scene = _sim
	_sim.get_node("World").visible = false
	_sim.get_node("Units").visible = false
	_sim.get_node("Projectiles").visible = false
	_sim.get_node("Structures").visible = false

	# View bookmarks mirror the 2D camera defaults: surface start position
	# and the own mine entry's underground position.
	var cam2d: Camera2D = _sim.get_node("Camera2D")
	_surface_focus = _to_ground(cam2d.position)
	var entry: Node2D = _sim.get_node("World/PlayerMineEntry")
	_underground_focus = _to_ground(entry.call("get_underground_position"))
	_focus = _surface_focus

	var grid: GridWorld = _sim.get_node("World/GridWorld") as GridWorld
	_terrain.setup(grid)
	_proxies.setup($World3D/Units3D, $World3D/Structures3D, grid, $World3D/Effects3D, _camera)

	# PlayerController is the single input authority for view switching.
	_pc = _sim.get_node("PlayerController")
	_pc.view_mode_changed.connect(_on_view_mode_changed)
	_apply_view(_pc.get_current_view_mode() == PlayerController.ViewMode.UNDERGROUND, true)


func _to_ground(pos2d: Vector2) -> Vector3:
	return Vector3(pos2d.x * WORLD_SCALE, 0.0, pos2d.y * WORLD_SCALE)


func _process(delta: float) -> void:
	_pan(delta)
	# Glue the Camera3D to the rig focus at the fixed pitch; dolly changes
	# only the horizontal distance (and derived height), never the pitch.
	var height: float = _dolly * tan(deg_to_rad(PITCH_DEGREES))
	$CameraRig.position = _focus
	_camera.position = Vector3(0.0, height, _dolly)
	_camera.rotation_degrees = Vector3(-PITCH_DEGREES, 0.0, 0.0)


func _pan(delta: float) -> void:
	var dir := Vector2.ZERO
	if Input.is_action_pressed(Constants.INPUT_CAMERA_RIGHT):
		dir.x += 1.0
	if Input.is_action_pressed(Constants.INPUT_CAMERA_LEFT):
		dir.x -= 1.0
	if Input.is_action_pressed(Constants.INPUT_CAMERA_DOWN):
		dir.y += 1.0
	if Input.is_action_pressed(Constants.INPUT_CAMERA_UP):
		dir.y -= 1.0
	if dir == Vector2.ZERO:
		dir = _edge_pan_dir()
	if dir == Vector2.ZERO:
		return
	# Pan speed scales with dolly so zoomed-out traversal isn't tedious.
	var speed: float = PAN_SPEED * (_dolly / DOLLY_START)
	_focus.x += dir.x * speed * delta
	_focus.z += dir.y * speed * delta
	# Same clamp rect player_camera.gd uses for the 2D camera, in 3D units.
	var x_range := Vector2(
		(GridWorld.X_MIN - 2) * GridWorld.CELL_SIZE,
		(GridWorld.X_MAX + 3) * GridWorld.CELL_SIZE) * WORLD_SCALE
	var z_range := Vector2(-300.0, (GridWorld.Y_MAX + 4) * GridWorld.CELL_SIZE) * WORLD_SCALE
	_focus.x = clampf(_focus.x, x_range.x, x_range.y)
	_focus.z = clampf(_focus.z, z_range.x, z_range.y)


func _edge_pan_dir() -> Vector2:
	var window_size: Vector2i = get_window().size
	if window_size.x <= 0:
		return Vector2.ZERO
	var mouse: Vector2 = get_viewport().get_mouse_position()
	if mouse.x < 0.0 or mouse.y < 0.0 or mouse.x > window_size.x or mouse.y > window_size.y:
		return Vector2.ZERO
	var dir := Vector2.ZERO
	if mouse.x < EDGE_PAN_MARGIN:
		dir.x -= 1.0
	elif mouse.x > window_size.x - EDGE_PAN_MARGIN:
		dir.x += 1.0
	if mouse.y < EDGE_PAN_MARGIN:
		dir.y -= 1.0
	elif mouse.y > window_size.y - EDGE_PAN_MARGIN:
		dir.y += 1.0
	return dir


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		# Wheel events double as the camera_zoom_in/out actions in the input
		# map; handling the raw button covers both bindings in one branch.
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			_dolly = clampf(_dolly / DOLLY_WHEEL_STEP, DOLLY_MIN, DOLLY_MAX)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_dolly = clampf(_dolly * DOLLY_WHEEL_STEP, DOLLY_MIN, DOLLY_MAX)
	elif event.is_action_pressed(Constants.INPUT_CAMERA_ZOOM_IN):
		_dolly = clampf(_dolly / DOLLY_WHEEL_STEP, DOLLY_MIN, DOLLY_MAX)
	elif event.is_action_pressed(Constants.INPUT_CAMERA_ZOOM_OUT):
		_dolly = clampf(_dolly * DOLLY_WHEEL_STEP, DOLLY_MIN, DOLLY_MAX)


## PlayerController (input authority) says the Tab view changed; the rig
## teleports to the bookmark of the requested layer, remembering where the
## view being left was parked (mirrors player_camera.set_view, minus slide).
func _on_view_mode_changed(mode: PlayerController.ViewMode) -> void:
	_apply_view(mode == PlayerController.ViewMode.UNDERGROUND, false)


func _apply_view(underground: bool, initial: bool) -> void:
	if not initial:
		if underground:
			_surface_focus = _focus
			_focus = _underground_focus
		else:
			_underground_focus = _focus
			_focus = _surface_focus
	_terrain.set_underground_view(underground)
	_proxies.set_underground_view(underground)
