extends Node
## Capture pilot: survives the menu→game scene swap (parented to the root
## window by capture_driver.gd) and steers the match to a deterministic set
## of screenshots. See capture_driver.gd for the argument contract.
##
## Drives a throwaway match through deterministic camera and event poses.
## Forced weather uses WeatherManager's own start/end routines and is ended
## again after the shot. Underground/breach poses finish real lantern
## placements for readable light pools; breach uses GridWorld's public damage
## API and restores its temporary reveal-all override after capture.

const WEATHER_LEAD_SEC := 3.0
const SURFACE_CAM_POS := Vector2(0.0, -150.0)
const ZOOMOUT_FACTOR := 0.5

var _config: Dictionary = {}
var _elapsed := 0.0
var _shot_idx := 0
var _pending_captures := 0
var _pc: Node = null
var _shell: Node = null
var _weather_active := ""
var _breach_revealed := false


func setup(config: Dictionary) -> void:
	_config = config


func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(_config.out)


func _process(delta: float) -> void:
	if _pc == null:
		_pc = get_node_or_null("/root/Main/PlayerController")
		if _pc == null or _pc.camera == null:
			return
		# 3D branch: the camera rig lives on the main_3d shell. PlayerController
		# set_view() still drives it (view_mode_changed), but dolly/focus are
		# rig state — reach the shell node once it exists.
		_shell = get_node_or_null("/root/Main3D")
	_elapsed += delta
	var shots: Array = _config.shots
	if _shot_idx >= shots.size():
		# The last shot's capture coroutine may still be awaiting its frames —
		# only wrap up once every save has landed.
		if _pending_captures == 0:
			_end_forced_weather()
			print("Capture: done (%d shots in %s)" % [shots.size(), _config.out])
			get_tree().quit()
		return
	var shot: Dictionary = shots[_shot_idx]
	# Weather shots need a head start so particles/overlay are visible.
	if (shot.pose == "storm" or shot.pose == "volcano") \
			and _weather_active != shot.pose \
			and _elapsed >= shot.t - WEATHER_LEAD_SEC:
		_begin_forced_weather(shot.pose)
	if _elapsed < shot.t:
		return
	_apply_pose(shot)
	_shot_idx += 1


func _apply_pose(shot: Dictionary) -> void:
	match shot.pose:
		"start":
			pass  # camera untouched since match start
		"surface", "storm", "volcano":
			# Weather shots read best from the surface bookmark. The rig
			# follows PlayerController's view_mode_changed signal.
			_pc.set_view(false)
			if shot.pose == "surface" and _shell != null:
				_shell.pose_camera(Vector3(0.0, 0.0, -1.5), 12.0, _shell.SURFACE_PITCH_DEGREES)
		"zoomout":
			_pc.set_view(false)
			if _shell != null:
				_shell.pose_camera(Vector3.ZERO, 16.0, _shell.SURFACE_PITCH_DEGREES)
		"underground":
			_pc.set_view(true)
			var lantern_cell := Vector2i(-15, 3)
			_ensure_underground_lantern(lantern_cell)
			if _shell != null:
				var grid := get_node_or_null("/root/Main/World/GridWorld") as GridWorld
				if grid != null:
					_shell.pose_camera(Presentation3D.to_3d(grid.grid_to_world(lantern_cell)),
						6.0, _shell.UNDERGROUND_PITCH_DEGREES)
		"breach":
			_pc.set_view(true)
			var grid := get_node_or_null("/root/Main/World/GridWorld") as GridWorld
			if grid != null:
				var wall_cells: Array = grid.get_wall_cells()
				if not wall_cells.is_empty():
					var center: Vector2i = wall_cells[int(wall_cells.size() / 2)]
					grid.set_reveal_all(GameManager.Team.PLAYER, true)
					_breach_revealed = true
					grid.damage_cell(center, 100000, 3)
					_ensure_underground_lantern(center)
					if _shell != null:
						_shell.pose_camera(Presentation3D.to_3d(grid.grid_to_world(center)),
							4.5, _shell.UNDERGROUND_PITCH_DEGREES)
		"custom":
			# 3D branch: custom:X:Y:Z = focus (X, Y world units) + dolly Z.
			if _shell != null:
				var pitch: float = _shell.UNDERGROUND_PITCH_DEGREES \
					if _pc.get_current_view_mode() == PlayerController.ViewMode.UNDERGROUND \
					else _shell.SURFACE_PITCH_DEGREES
				_shell.pose_camera(Vector3(shot.pos.x * 0.01, 0.0, shot.pos.y * 0.01), shot.zoom, pitch)
	_capture(shot)


func _ensure_underground_lantern(cell: Vector2i) -> void:
	var grid := get_node_or_null("/root/Main/World/GridWorld") as GridWorld
	if grid == null:
		return
	var world_pos := grid.grid_to_world(cell)
	for lantern in get_tree().get_nodes_in_group("lanterns"):
		if lantern.team == GameManager.Team.PLAYER and lantern.is_underground_lantern \
				and grid.world_to_grid(lantern.global_position) == cell:
			return
	if not _pc.try_place_lantern("underground_lantern", world_pos):
		return
	for lantern in get_tree().get_nodes_in_group("lanterns"):
		if lantern.team == GameManager.Team.PLAYER and lantern.is_underground_lantern \
				and grid.world_to_grid(lantern.global_position) == cell:
			lantern._build_progress = 999.0
			lantern._process(0.1)
			return


## Wheel-style zoom relative to the resolution-adaptive base zoom the
## PlayerCamera helper would apply (PlayerCamera._base_zoom()).
func _set_zoom(factor: float) -> void:
	var win_size: Vector2i = get_window().size
	if win_size.x <= 0:
		return
	var logical: Vector2 = get_viewport().get_visible_rect().size
	_pc.camera.zoom = Vector2.ONE * (logical.x / win_size.x) * factor


func _begin_forced_weather(pose: String) -> void:
	_weather_active = pose
	_pc.set_view(false)
	if pose == "storm" and WeatherManager.has_method("_start_snowstorm"):
		WeatherManager.call("_start_snowstorm")
	elif pose == "volcano" and WeatherManager.has_method("_start_volcano"):
		WeatherManager.call("_start_volcano")


func _end_forced_weather() -> void:
	if _weather_active == "storm" and WeatherManager.has_method("_end_snowstorm"):
		WeatherManager.call("_end_snowstorm")
	elif _weather_active == "volcano" and WeatherManager.has_method("_end_volcano"):
		WeatherManager.call("_end_volcano")
	_weather_active = ""


func _capture(shot: Dictionary) -> void:
	# Filename before the awaits: _shot_idx advances as soon as this coroutine
	# yields, which would otherwise offset every name by one.
	_pending_captures += 1
	var name: String = "%03d_%s.png" % [_shot_idx + 1, shot.pose]
	if _shell != null and ["underground", "breach", "storm", "volcano"].has(shot.pose):
		await get_tree().create_timer(_shell.VIEW_TWEEN_DURATION).timeout
	if shot.pose == "underground" or shot.pose == "breach":
		await get_tree().create_timer(Fog3D.REFRESH_INTERVAL).timeout
	# Two frames: one for the pose/weather to take effect, one to draw.
	await get_tree().process_frame
	await get_tree().process_frame
	var err := get_viewport().get_texture().get_image().save_png(
		_config.out.path_join(name))
	if err != OK:
		push_error("Capture: save_png failed (%d) for %s" % [err, name])
	else:
		print("Capture: %s at t=%.2fs" % [name, _elapsed])
	if shot.pose == "storm" or shot.pose == "volcano":
		_end_forced_weather()
	elif shot.pose == "breach" and _breach_revealed:
		var grid := get_node_or_null("/root/Main/World/GridWorld") as GridWorld
		if grid != null:
			grid.set_reveal_all(GameManager.Team.PLAYER, false)
		_breach_revealed = false
	_pending_captures -= 1
