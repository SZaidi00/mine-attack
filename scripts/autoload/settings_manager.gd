extends Node

## Display settings: user-selectable window resolution (desktop only).
## The stretch setup (canvas_items/expand + stretch/scale 1.333333) keeps the
## logical layout at 1920x1080 for any 16:9 window size, so switching
## resolution only changes render sharpness, never the UI layout.
## Also persists the SFX bus volume (all platforms) in the same config file.
## Accessibility/gameplay preferences (UI scale, colorblind mode, reduced
## motion/flash, tutorial hints) live in the [access] and [tutorial] sections.

## Emitted after any preference changes, with the setting's key, so live
## UI (HUD scale, camera shake, palettes) can react without polling.
signal setting_changed(what: StringName)

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
	# Saved hotkey bindings apply before anything else reads the InputMap.
	apply_saved_bindings()
	# Audio applies everywhere (web included); AudioManager loads first, so the
	# SFX bus already exists by the time we run.
	_apply_sfx_volume(_load_sfx_volume())
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


# ---------- Audio ----------

## Linear SFX volume, 0.0 (muted) to 1.0 (full).
func get_sfx_volume() -> float:
	return _load_sfx_volume()


func set_sfx_volume(volume: float) -> void:
	volume = clampf(volume, 0.0, 1.0)
	_apply_sfx_volume(volume)
	var cfg := ConfigFile.new()
	cfg.load(CONFIG_PATH)  # Preserve any other stored settings.
	cfg.set_value("audio", "sfx_volume", volume)
	cfg.save(CONFIG_PATH)


func _apply_sfx_volume(volume: float) -> void:
	var bus := AudioServer.get_bus_index("SFX")
	if bus == -1:
		return
	AudioServer.set_bus_mute(bus, volume <= 0.0)
	AudioServer.set_bus_volume_db(bus, linear_to_db(maxf(volume, 0.0001)))


func _load_sfx_volume() -> float:
	var cfg := ConfigFile.new()
	if cfg.load(CONFIG_PATH) != OK:
		return 1.0
	return clampf(cfg.get_value("audio", "sfx_volume", 1.0), 0.0, 1.0)


# ---------- Accessibility / gameplay preferences ----------

## HUD scale, 0.75 (smallest) to 1.5 (largest). 1.0 leaves the 1920x1080
## logical layout untouched.
func get_ui_scale() -> float:
	return _load_value("access", "ui_scale", 1.0)


func set_ui_scale(scale: float) -> void:
	scale = clampf(scale, 0.75, 1.5)
	_save_value("access", "ui_scale", scale)
	setting_changed.emit(&"ui_scale")


## Colorblind mode: swaps hue-only semantic colors (enemy red, lava/ore) for
## a redundant palette + shape cues.
func get_colorblind() -> bool:
	return _load_value("access", "colorblind", false)


func set_colorblind(enabled: bool) -> void:
	_save_value("access", "colorblind", enabled)
	setting_changed.emit(&"colorblind")


## Reduced motion: disables camera shake from combat and terrain events.
func get_reduced_motion() -> bool:
	return _load_value("access", "reduced_motion", false)


func set_reduced_motion(enabled: bool) -> void:
	_save_value("access", "reduced_motion", enabled)
	setting_changed.emit(&"reduced_motion")


## Reduced flash: keeps warning banners static instead of pulsing.
func get_reduced_flash() -> bool:
	return _load_value("access", "reduced_flash", false)


func set_reduced_flash(enabled: bool) -> void:
	_save_value("access", "reduced_flash", enabled)
	setting_changed.emit(&"reduced_flash")


## Whether first-match tutorial hints may show at all.
func get_show_tutorial() -> bool:
	return _load_value("tutorial", "show", true)


func set_show_tutorial(enabled: bool) -> void:
	_save_value("tutorial", "show", enabled)
	setting_changed.emit(&"show_tutorial")


## Hint ids the player has already dismissed (never shown again).
func get_tutorial_seen() -> Array[String]:
	var raw: Array = _load_value("tutorial", "seen", [])
	var seen: Array[String] = []
	for id in raw:
		seen.append(str(id))
	return seen


func mark_tutorial_seen(id: String) -> void:
	var seen := get_tutorial_seen()
	if id in seen:
		return
	seen.append(id)
	_save_value("tutorial", "seen", seen)
	setting_changed.emit(&"tutorial_seen")


func reset_tutorial_seen() -> void:
	_save_value("tutorial", "seen", [])
	setting_changed.emit(&"tutorial_seen")


# ---------- Key bindings ----------

## Current binding for a remappable action: {keycode, ctrl, alt, shift}.
## Falls back to the first key event registered in the InputMap when nothing
## is stored. Mouse-button actions (lmb/rmb) are not remappable and return {}.
func get_key_binding(action: String) -> Dictionary:
	var stored: Variant = _load_value("input", action, {})
	if stored is Dictionary and not (stored as Dictionary).is_empty():
		return stored
	for event in InputMap.action_get_events(action):
		if event is InputEventKey:
			var key := event as InputEventKey
			return {
				"keycode": key.keycode,
				"ctrl": key.ctrl_pressed,
				"alt": key.alt_pressed,
				"shift": key.shift_pressed,
			}
	return {}


## Persist a binding and apply it to the InputMap immediately.
func set_key_binding(action: String, keycode: int, ctrl: bool, alt: bool, shift: bool) -> void:
	var binding := {"keycode": keycode, "ctrl": ctrl, "alt": alt, "shift": shift}
	_save_value("input", action, binding)
	_apply_key_binding(action, binding)
	setting_changed.emit(StringName(action))


## Re-apply every stored binding (called in _ready, before gameplay systems
## read the InputMap; InputMap edits also work on the web export).
func apply_saved_bindings() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(CONFIG_PATH) != OK:
		return
	if not cfg.has_section("input"):
		return
	for action in cfg.get_section_keys("input"):
		var binding: Dictionary = cfg.get_value("input", action, {})
		if binding.is_empty():
			continue
		_apply_key_binding(action, binding)


## Replace only the KEY events of an action; mouse buttons are untouched.
func _apply_key_binding(action: String, binding: Dictionary) -> void:
	if not InputMap.has_action(action):
		return
	for event in InputMap.action_get_events(action):
		if event is InputEventKey:
			InputMap.action_erase_event(action, event)
	var key := InputEventKey.new()
	key.keycode = int(binding.get("keycode", 0))
	key.ctrl_pressed = bool(binding.get("ctrl", false))
	key.alt_pressed = bool(binding.get("alt", false))
	key.shift_pressed = bool(binding.get("shift", false))
	InputMap.action_add_event(action, key)


func _load_value(section: String, key: String, default: Variant) -> Variant:
	var cfg := ConfigFile.new()
	if cfg.load(CONFIG_PATH) != OK:
		return default
	return cfg.get_value(section, key, default)


func _save_value(section: String, key: String, value: Variant) -> void:
	var cfg := ConfigFile.new()
	cfg.load(CONFIG_PATH)  # Preserve any other stored settings.
	cfg.set_value(section, key, value)
	cfg.save(CONFIG_PATH)
