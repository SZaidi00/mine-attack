extends Node
## Capture pilot: survives the menu→game scene swap (parented to the root
## window by capture_driver.gd) and steers the match to a deterministic set
## of screenshots. See capture_driver.gd for the argument contract.
##
## Drives a throwaway match through deterministic camera and event poses.
## Forced weather uses WeatherManager's own start/end routines and is ended
## again after the shot. Underground/breach poses finish real lantern
## placements for readable light pools; breach uses GridWorld's public damage
## API and restores its temporary reveal-all override after capture. R7 unit
## galleries freeze real Unit scenes after _ready and carve a lantern-lit tunnel
## through the same public APIs, so every sim-wide unit scan sees a real Unit.

const WEATHER_LEAD_SEC := 3.0
const SURFACE_CAM_POS := Vector2(0.0, -150.0)
const ZOOMOUT_FACTOR := 0.5
const UNIT_IDS: Array[String] = [
	"miner", "pigeon", "archer", "wizard", "engineer", "dragon", "swordsman", "crawler",
]

var _config: Dictionary = {}
var _elapsed := 0.0
var _shot_idx := 0
var _pending_captures := 0
var _pc: Node = null
var _shell: Node = null
var _weather_active := ""
var _breach_revealed := false
var _dunes_revealed := false
var _fortress_revealed := false
var _ui_prepared := false
var _lineup_units: Array[Node2D] = []
var _lineup_revealed := false
var _stress_spawned := false


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
	if not _ui_prepared:
		var hints := get_node_or_null("/root/Main/UI/HUD/TutorialHints")
		if hints != null:
			hints.visible = false
			hints.set_process(false)
			_ui_prepared = true
	for unit in _lineup_units:
		if is_instance_valid(unit):
			unit.position = unit.get_meta("lineup_position")
			unit.is_underground = bool(unit.get_meta("lineup_underground"))
			unit.set("_state", Unit.State.IDLE)
	if int(_config.get("stress_units", 0)) > 0 and not _stress_spawned:
		_spawn_stress_units()
	_elapsed += delta
	var shots: Array = _config.shots
	if _shot_idx >= shots.size():
		# The last shot's capture coroutine may still be awaiting its frames —
		# only wrap up once every save has landed. A bench window keeps the
		# match running past the shots so Probe3D accumulates real load.
		if _pending_captures == 0:
			var bench: float = float(_config.get("bench", 0.0))
			if bench > 0.0 and _elapsed < bench:
				return
			_end_forced_weather()
			if Probe3D.enabled:
				print("BENCH script-time report (avg ms per sample):")
				print(Probe3D.report())
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
			if _shell != null:
				if shot.pose == "surface":
					_shell.pose_camera(Vector3(0.0, 0.0, -1.5), 12.0, _shell.SURFACE_PITCH_DEGREES)
				else:
					_shell.pose_camera(Vector3(-10.0, 0.0, -1.5), 10.5, _shell.SURFACE_PITCH_DEGREES)
		"zoomout":
			_pc.set_view(false)
			if _shell != null:
				_shell.pose_camera(Vector3.ZERO, 16.0, _shell.SURFACE_PITCH_DEGREES)
		"underground":
			_pc.set_view(true)
			var lantern_cell := Vector2i(-15, 3)
			_ensure_underground_lantern(lantern_cell)
			var grid := get_node_or_null("/root/Main/World/GridWorld") as GridWorld
			if grid != null and _shell != null:
				_shell.pose_camera(Presentation3D.to_3d(grid.grid_to_world(lantern_cell)),
					4.0, _shell.UNDERGROUND_PITCH_DEGREES)
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
		"base":
			_pc.set_view(false)
			var building := _find_building(GameManager.Team.PLAYER)
			if building != null:
				building.call("queue_unit", "dragon")
				if _shell != null:
					_shell.pose_camera(Presentation3D.to_3d(building.global_position) + Vector3(2.0, 0.0, 0.0),
						8.0, _shell.SURFACE_PITCH_DEGREES)
		"dunes":
			_pc.set_view(false)
			var grid := get_node_or_null("/root/Main/World/GridWorld") as GridWorld
			if grid != null:
				grid.set_reveal_all(GameManager.Team.PLAYER, true)
				_dunes_revealed = true
			if _shell != null:
				_shell.pose_camera(Vector3(0.0, 0.0, -1.5), 10.5, _shell.SURFACE_PITCH_DEGREES)
		"fortress":
			_pc.set_view(false)
			var building := _find_building(GameManager.Team.ENEMY)
			var grid := get_node_or_null("/root/Main/World/GridWorld") as GridWorld
			if grid != null:
				grid.set_reveal_all(GameManager.Team.PLAYER, true)
				_fortress_revealed = true
			FactionManager.identify_faction(GameManager.Team.ENEMY)
			var hud := get_node_or_null("/root/Main/UI/HUD")
			if hud != null and hud.get("_faction_popup") != null:
				hud.get("_faction_popup").visible = false
			if building != null and _shell != null:
				_shell.pose_camera(Presentation3D.to_3d(building.global_position), 7.0, _shell.SURFACE_PITCH_DEGREES)
		"units", "units_underground":
			var underground: bool = shot.pose == "units_underground"
			_pc.set_view(underground)
			var focus := _spawn_unit_lineup(underground)
			if _shell != null:
				var pitch: float = _shell.UNDERGROUND_PITCH_DEGREES if underground else _shell.SURFACE_PITCH_DEGREES
				_shell.pose_camera(Presentation3D.to_3d(focus), 3.5 if underground else 6.0, pitch)
		"custom":
			# 3D branch: custom:X:Y:Z = focus (X, Y world units) + dolly Z.
			if _shell != null:
				var pitch: float = _shell.UNDERGROUND_PITCH_DEGREES \
					if _pc.get_current_view_mode() == PlayerController.ViewMode.UNDERGROUND \
					else _shell.SURFACE_PITCH_DEGREES
				_shell.pose_camera(Vector3(shot.pos.x * 0.01, 0.0, shot.pos.y * 0.01), shot.zoom, pitch)
	_capture(shot)


func _find_building(team: GameManager.Team) -> Node2D:
	for building in get_tree().get_nodes_in_group("buildings"):
		if building is Node2D and building.get("team") == team:
			return building
	return null


func _spawn_unit_lineup(underground: bool) -> Vector2:
	_clear_unit_lineup()
	var grid := get_node_or_null("/root/Main/World/GridWorld") as GridWorld
	var container := get_node_or_null("/root/Main/Units")
	if grid == null or container == null:
		return Vector2.ZERO
	grid.set_reveal_all(GameManager.Team.PLAYER, true)
	_lineup_revealed = true
	var row := 3 if underground else -2
	for i in range(UNIT_IDS.size()):
		var cell := Vector2i(-9 + (i % 4) * 2, row + floori(i / 4.0) * 2) if underground \
			else Vector2i(-7 + i * 2, row)
		if underground:
			grid.damage_cell(cell, 100000, 3)
		var unit: Unit = load("res://scenes/unit.tscn").instantiate()
		unit.data = load("res://scripts/resources/units/%s.tres" % UNIT_IDS[i]).duplicate(true)
		unit.is_underground = underground
		unit.position = grid.grid_to_world(cell)
		container.add_child(unit)
		unit.set_process(false)
		unit.set("_state", Unit.State.IDLE)
		unit.set_meta("lineup_position", unit.position)
		unit.set_meta("lineup_underground", underground)
		_lineup_units.append(unit)
	if underground:
		grid.damage_cell(Vector2i(-6, row + 1), 100000, 3)
		_ensure_underground_lantern(Vector2i(-6, row + 1))
		return grid.grid_to_world(Vector2i(-6, row + 1))
	return grid.grid_to_world(Vector2i(0, row))


## BENCH stress load: spawn n units per team across the surface band — real,
## live units (process on) so the sim, proxies, fog, and combat feedback all
## see genuine load. Reveal-all keeps every proxy on the expensive visible
## path; half the player army stays selected so HP bars render too.
func _spawn_stress_units() -> void:
	var grid := get_node_or_null("/root/Main/World/GridWorld") as GridWorld
	var container := get_node_or_null("/root/Main/Units")
	if grid == null or container == null:
		return  # Scene still mounting; retry next frame.
	_stress_spawned = true
	grid.set_reveal_all(GameManager.Team.PLAYER, true)
	var n: int = int(_config.get("stress_units", 0))
	var scene: PackedScene = load("res://scenes/unit.tscn")
	var per_row := 20
	var spawned := 0
	var type_idx := 0
	while spawned < n * 2:
		var team: GameManager.Team = GameManager.Team.PLAYER if spawned < n else GameManager.Team.ENEMY
		var i := spawned if team == GameManager.Team.PLAYER else spawned - n
		var row := GridWorld.SURFACE_TOP + 1 + (i / per_row) % 4
		# Each team spawns on its own half so the bench load persists for the
		# whole window instead of brawling to death at the midfield line.
		var col := (-19 + (i % per_row)) if team == GameManager.Team.PLAYER else (1 + (i % per_row))
		var unit: Unit = scene.instantiate()
		unit.data = load("res://scripts/resources/units/%s.tres" % UNIT_IDS[type_idx % UNIT_IDS.size()]).duplicate(true)
		type_idx += 1
		unit.team = team
		unit.is_underground = false
		unit.position = grid.grid_to_world(Vector2i(col, row))
		container.add_child(unit)
		if team == GameManager.Team.PLAYER and i % 2 == 0:
			unit.selected = true
		spawned += 1


func _clear_unit_lineup() -> void:
	for unit in _lineup_units:
		if is_instance_valid(unit):
			unit.free()
	_lineup_units.clear()
	if _lineup_revealed:
		var grid := get_node_or_null("/root/Main/World/GridWorld") as GridWorld
		if grid != null:
			grid.set_reveal_all(GameManager.Team.PLAYER, false)
		_lineup_revealed = false


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
	if _shell != null and ["underground", "breach", "storm", "volcano", "units_underground"].has(shot.pose):
		await get_tree().create_timer(_shell.VIEW_TWEEN_DURATION).timeout
	if ["underground", "breach", "units_underground", "dunes", "fortress"].has(shot.pose):
		await get_tree().create_timer(Fog3D.REFRESH_INTERVAL).timeout
	if shot.pose == "units":
		await get_tree().create_timer(0.3).timeout
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
	elif (shot.pose == "breach" and _breach_revealed) or (shot.pose == "dunes" and _dunes_revealed) or (shot.pose == "fortress" and _fortress_revealed):
		var grid := get_node_or_null("/root/Main/World/GridWorld") as GridWorld
		if grid != null:
			grid.set_reveal_all(GameManager.Team.PLAYER, false)
		_breach_revealed = false
		_dunes_revealed = false
		_fortress_revealed = false
	elif shot.pose == "units" or shot.pose == "units_underground":
		_clear_unit_lineup()
	_pending_captures -= 1
