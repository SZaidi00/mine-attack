extends Node
## Capture pilot: survives the menu→game scene swap (parented to the root
## window by capture_driver.gd) and steers the match to a deterministic set
## of screenshots. See capture_driver.gd for the argument contract.
##
## Presentation-only: it reads sim state and drives the camera/weather the
## same way a player could (camera bookmarks, view toggle, weather events).
## Forced weather uses WeatherManager's own start/end routines and is ended
## again after the shot so later shots are unaffected.

const WEATHER_LEAD_SEC := 3.0
const SURFACE_CAM_POS := Vector2(0.0, -150.0)
const ZOOMOUT_FACTOR := 0.5

var _config: Dictionary = {}
var _elapsed := 0.0
var _shot_idx := 0
var _pending_captures := 0
var _pc: Node = null
var _weather_active := ""


func setup(config: Dictionary) -> void:
	_config = config


func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(_config.out)


func _process(delta: float) -> void:
	if _pc == null:
		_pc = get_node_or_null("/root/Main/PlayerController")
		if _pc == null or _pc.camera == null:
			return
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
			# Weather shots read best from the surface bookmark.
			_pc.set_view(false)
			if shot.pose == "surface":
				_pc.camera.position = SURFACE_CAM_POS
				_set_zoom(1.0)
		"zoomout":
			_pc.set_view(false)
			_pc.camera.position = SURFACE_CAM_POS
			_set_zoom(ZOOMOUT_FACTOR)
		"underground":
			_pc.set_view(true)
		"custom":
			_pc.camera.position = shot.pos
			_set_zoom(shot.zoom)
	_capture(shot)


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
	_pending_captures -= 1
