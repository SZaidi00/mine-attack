extends Node

## Display settings: user-selectable window resolution (desktop only).
## The stretch setup (canvas_items/expand + stretch/scale 1.333333) keeps the
## logical layout at 1920x1080 for any 16:9 window size, so switching
## resolution only changes render sharpness, never the UI layout.

const CONFIG_PATH := "user://settings.cfg"

## 16:9 options, smallest to largest. 2560x1440 is the project default.
const RESOLUTIONS: Array[Vector2i] = [
	Vector2i(1280, 720),
	Vector2i(1600, 900),
	Vector2i(1920, 1080),
	Vector2i(2560, 1440),
	Vector2i(3840, 2160),
]


func _ready() -> void:
	if not is_supported():
		return
	var available := get_available_resolutions()
	var saved := _load_saved()
	if saved in available:
		_apply(saved)
	elif not available.is_empty() and get_window().size > available[-1]:
		# First boot (or a smaller screen than last time): shrink the project
		# default to the biggest resolution the current screen can hold.
		_apply(available[-1])


## Window resolution switching only works on desktop; the web canvas is
## full-bleed and follows the browser window.
func is_supported() -> bool:
	return not OS.has_feature("web")


## Resolutions that fit the current screen's usable rect (so the dock /
## taskbar stay clear). Headless reports a zero screen — return everything.
func get_available_resolutions() -> Array[Vector2i]:
	var screen: Vector2i = DisplayServer.screen_get_usable_rect().size
	if screen == Vector2i.ZERO:
		return RESOLUTIONS.duplicate()
	var result: Array[Vector2i] = []
	for res in RESOLUTIONS:
		if res.x <= screen.x and res.y <= screen.y:
			result.append(res)
	if result.is_empty():
		result.append(RESOLUTIONS[0])
	return result


func get_resolution() -> Vector2i:
	return get_window().size


func set_resolution(size: Vector2i) -> void:
	if not is_supported():
		return
	_apply(size)
	_save(size)


func _apply(size: Vector2i) -> void:
	var win := get_window()
	win.size = size
	win.move_to_center()


func _load_saved() -> Vector2i:
	var cfg := ConfigFile.new()
	if cfg.load(CONFIG_PATH) != OK:
		return Vector2i.ZERO
	return cfg.get_value("display", "resolution", Vector2i.ZERO)


func _save(size: Vector2i) -> void:
	var cfg := ConfigFile.new()
	cfg.load(CONFIG_PATH)  # Preserve any other stored settings.
	cfg.set_value("display", "resolution", size)
	cfg.save(CONFIG_PATH)
