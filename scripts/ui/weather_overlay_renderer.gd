class_name WeatherOverlayRenderer
extends Control

# Surface-only weather overlay renderer (Phase 01 revamp).
# Draws snowstorm and volcano effects clipped to the above-ground band.

const SURFACE_TOP: float = 0.095
const SURFACE_BOTTOM: float = 0.382

const _FOG_COLOR: Color = Color(0.886275, 0.941176, 0.968627)
const _FOG_ALPHA: float = 0.34
const _WIND: float = 0.16
const _STORM_INTENSITY: float = 1.0
const _VISIBILITY_LOSS: float = 1.0

const _CLOUD_BANK_COUNT: int = 12
const _FOG_BLOB_COUNT: int = 42
const _SNOW_COUNT: int = 360
const _METEOR_COUNT: int = 82
const _EMBER_COUNT: int = 220
const _MAX_LANTERNS: int = 16
const _PLUME_PUFFS: int = 18

const _SHADER: Shader = preload("res://scripts/ui/weather_overlay.gdshader")

## Storm fade speed (strength per second): 0.5 gives a ~2s fade in/out.
const _FADE_SPEED: float = 0.5

var _fog_rect: ColorRect = null
var _particle_layer: ParticleLayer = null

var _snowstorm_active: bool = false
var _volcano_active: bool = false
var _storm_time: float = 0.0
var _volcano_time: float = 0.0
## 0..1 render strength of the snowstorm overlay. Eases toward 1 while the
## storm rages on the surface view and toward 0 when it ends or the camera
## goes underground, so the fog never pops in/out or covers the mine view.
var _storm_strength: float = 0.0
## Normalized screen Y of the terrain line under the current camera. The
## fixed SURFACE_BOTTOM constant is only a fallback: panning/zooming moves
## the ground line on screen, so the clip band is recomputed every frame to
## keep weather strictly above ground.
var _band_bottom_norm: float = SURFACE_BOTTOM

# Particle pools
var _cloud_banks: Array[Dictionary] = []
var _fog_blobs: Array[Dictionary] = []
var _snowflakes: Array[Dictionary] = []
var _meteors: Array[Dictionary] = []
var _embers: Array[Dictionary] = []

# Shader data
var _cloud_bank_array: Array[Vector4] = []
var _cloud_meta_array: Array[Vector4] = []
var _fog_blob_array: Array[Vector4] = []
var _fog_blob_meta_array: Array[Vector4] = []
var _lantern_pos_array: Array[Vector2] = []
var _lantern_radius_array: Array[float] = []


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	process_mode = Node.PROCESS_MODE_ALWAYS

	_fog_rect = ColorRect.new()
	_fog_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	_fog_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var material := ShaderMaterial.new()
	material.shader = _SHADER
	_fog_rect.material = material
	add_child(_fog_rect)

	_particle_layer = ParticleLayer.new()
	_particle_layer.renderer = self
	_particle_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_particle_layer)

	_seed_clouds()
	_seed_blobs()
	_seed_snow()
	_seed_meteors()
	_seed_embers()
	_setup_shader_constants()
	_update_shader_state(true)


func _process(delta: float) -> void:
	if get_tree().paused:
		return

	# Fade the storm in/out; it also fades out while the camera is in the
	# underground view so surface weather never renders over the mine.
	var storm_target: float = 0.0
	if _snowstorm_active and not _is_underground_view():
		storm_target = 1.0
	_storm_strength = move_toward(_storm_strength, storm_target, _FADE_SPEED * delta)
	var storm_visible: bool = _storm_strength > 0.001

	if not storm_visible and not _volcano_active:
		return

	_update_surface_band()
	var viewport_size: Vector2 = get_viewport_rect().size
	if storm_visible:
		_storm_time += delta
		_update_snow(delta, viewport_size)
	if _volcano_active:
		_volcano_time += delta
		_update_meteors(delta, viewport_size)
		_update_embers(delta, viewport_size)

	_update_lanterns()
	_update_shader_state(false)
	_particle_layer.queue_redraw()


func set_snowstorm_active(active: bool) -> void:
	_snowstorm_active = active
	# No state reset on end: _process keeps simulating while _storm_strength
	# eases down, producing a slow fade-out instead of an instant cut.
	if active:
		_update_lanterns()
	_update_shader_state(false)
	_particle_layer.queue_redraw()


func set_volcano_active(active: bool) -> void:
	_volcano_active = active
	if not active:
		_volcano_time = 0.0
	_update_shader_state(false)
	_particle_layer.queue_redraw()


func _setup_shader_constants() -> void:
	var material: ShaderMaterial = _fog_rect.material
	material.set_shader_parameter("surface_top", SURFACE_TOP)
	material.set_shader_parameter("surface_bottom", SURFACE_BOTTOM)
	material.set_shader_parameter("fog_color", _FOG_COLOR)
	material.set_shader_parameter("fog_alpha", _FOG_ALPHA)
	material.set_shader_parameter("storm_intensity", _STORM_INTENSITY)
	material.set_shader_parameter("visibility_loss", _VISIBILITY_LOSS)
	material.set_shader_parameter("wind", _WIND)
	material.set_shader_parameter("heat_grade", 0.68)
	material.set_shader_parameter("plume_power", 0.45)
	material.set_shader_parameter("cloud_banks", _cloud_bank_array)
	material.set_shader_parameter("cloud_meta", _cloud_meta_array)
	material.set_shader_parameter("fog_blobs", _fog_blob_array)
	material.set_shader_parameter("blob_meta", _fog_blob_meta_array)


func _update_shader_state(_initial: bool) -> void:
	var material: ShaderMaterial = _fog_rect.material
	material.set_shader_parameter("surface_bottom", _band_bottom_norm)
	material.set_shader_parameter("snowstorm_active", _storm_strength > 0.001)
	material.set_shader_parameter("storm_strength", _storm_strength)
	material.set_shader_parameter("storm_time", _storm_time)
	material.set_shader_parameter("volcano_active", _volcano_active)
	material.set_shader_parameter("volcano_time", _volcano_time)
	material.set_shader_parameter("lantern_pos", _lantern_pos_array)
	material.set_shader_parameter("lantern_radius", _lantern_radius_array)
	material.set_shader_parameter("lantern_count", _lantern_pos_array.size())


## True while the player camera is bookmarked on the underground mine view.
func _is_underground_view() -> bool:
	var pc: PlayerController = get_node_or_null("/root/Main/PlayerController") as PlayerController
	return pc != null and pc.is_underground_view()


## Recomputes the normalized screen Y of the terrain line (grid row Y_MIN's
## top edge) so fog, snow, meteors, and embers all stop exactly at the ground
## instead of a fixed screen band. When the ground line is off-screen above
## (deep underground view), the band collapses to a sliver and nothing draws.
func _update_surface_band() -> void:
	var viewport_height: float = get_viewport_rect().size.y
	if viewport_height <= 0.0:
		return
	var ground_world_y: float = float(GridWorld.Y_MIN * GridWorld.CELL_SIZE)
	var screen_y: float = (get_viewport().canvas_transform * Vector2(0.0, ground_world_y)).y
	_band_bottom_norm = clampf(screen_y / viewport_height, SURFACE_TOP + 0.001, 1.0)


func _update_lanterns() -> void:
	_lantern_pos_array.clear()
	_lantern_radius_array.clear()
	var canvas_transform: Transform2D = get_viewport().canvas_transform
	for lantern in get_tree().get_nodes_in_group("lanterns"):
		if _lantern_pos_array.size() >= _MAX_LANTERNS:
			break
		if lantern.get("team") != GameManager.Team.PLAYER:
			continue
		if not lantern.call("is_built"):
			continue
		if lantern.get("is_underground_lantern"):
			continue
		var world_pos: Vector2 = lantern.global_position
		var screen_pos: Vector2 = canvas_transform * world_pos
		_lantern_pos_array.append(screen_pos)
		var radius_cells: int = lantern.get("vision_radius")
		var radius_px: float = radius_cells * GridWorld.CELL_SIZE * canvas_transform.get_scale().x
		# Scale by approved 23% pocket size -> approximate shelter radius.
		_lantern_radius_array.append(radius_px * 0.55)


func _seed_clouds() -> void:
	_cloud_banks.clear()
	_cloud_bank_array.clear()
	_cloud_meta_array.clear()
	var band_height: float = SURFACE_BOTTOM - SURFACE_TOP
	for i in range(_CLOUD_BANK_COUNT):
		var bank: Dictionary = {
			"x": randf(),
			"y": SURFACE_TOP + 0.015 + randf() * (band_height - 0.03),
			"rx": 0.16 + randf() * 0.22,
			"ry": 0.028 + randf() * 0.052,
			"speed": 0.018 + randf() * 0.045,
			"alpha": 0.35 + randf() * 0.65,
			"phase": randf() * TAU,
		}
		_cloud_banks.append(bank)
		_cloud_bank_array.append(Vector4(bank.x, bank.y, bank.rx, bank.ry))
		_cloud_meta_array.append(Vector4(bank.speed, bank.alpha, bank.phase, 0.0))


func _seed_blobs() -> void:
	_fog_blobs.clear()
	_fog_blob_array.clear()
	_fog_blob_meta_array.clear()
	var band_height: float = SURFACE_BOTTOM - SURFACE_TOP
	for i in range(_FOG_BLOB_COUNT):
		var blob: Dictionary = {
			"x": randf(),
			"y": SURFACE_TOP + randf() * band_height,
			"rx": 0.05 + randf() * 0.15,
			"ry": 0.025 + randf() * 0.085,
			"speed": 0.006 + randf() * 0.026,
			"alpha": 0.25 + randf() * 0.75,
			"phase": randf() * TAU,
			"lift": randf() * 0.02,
		}
		_fog_blobs.append(blob)
		_fog_blob_array.append(Vector4(blob.x, blob.y, blob.rx, blob.ry))
		_fog_blob_meta_array.append(Vector4(blob.speed, blob.alpha, blob.phase, blob.lift))


func _seed_snow() -> void:
	_snowflakes.clear()
	var band_height: float = SURFACE_BOTTOM - SURFACE_TOP
	for i in range(_SNOW_COUNT):
		_snowflakes.append({
			"x": randf(),
			"y": SURFACE_TOP + randf() * band_height,
			"length": 0.008 + randf() * 0.032,
			"width": 0.7 + randf() * 1.9,
			"speed": 0.07 + randf() * 0.24,
			"drift": 0.35 + randf() * 0.9,
			"alpha": 0.2 + randf() * 0.72,
			"phase": randf() * TAU,
		})


func _update_snow(delta: float, viewport_size: Vector2) -> void:
	var wind_x: float = _WIND * 1.8
	var active_count: int = int(_snowflakes.size() * maxf(0.12, _STORM_INTENSITY))
	var height: float = viewport_size.y
	for i in range(active_count):
		var flake: Dictionary = _snowflakes[i]
		flake.y += flake.speed * delta * (0.7 + _STORM_INTENSITY * 0.8) / (SURFACE_BOTTOM - SURFACE_TOP)
		flake.x += _WIND * flake.drift * delta * 0.13 / (SURFACE_BOTTOM - SURFACE_TOP)
		if flake.y > _band_bottom_norm:
			flake.y = SURFACE_TOP - randf() * 0.025
			flake.x = randf()
		if flake.x > 1.08:
			flake.x = -0.08
		if flake.x < -0.08:
			flake.x = 1.08


func _seed_meteors() -> void:
	_meteors.clear()
	for i in range(_METEOR_COUNT):
		_meteors.append({
			"x": 0.08 + randf() * 1.05,
			"y": -0.12 + randf() * 0.5,
			"speed": 0.17 + randf() * 0.34,
			"length": 0.045 + randf() * 0.09,
			"width": 1.2 + randf() * 2.2,
			"phase": randf() * TAU,
			"delay": float(i % 9) * 0.17,
		})


func _update_meteors(delta: float, viewport_size: Vector2) -> void:
	var active_count: int = int(_meteors.size() * maxf(0.08, 1.0))
	for i in range(active_count):
		var meteor: Dictionary = _meteors[i]
		if _volcano_time < meteor.delay:
			continue
		meteor.y += meteor.speed * delta * (0.45 + 1.0 * 0.8)
		meteor.x -= meteor.speed * delta * 0.31
		if meteor.y > _band_bottom_norm or meteor.x < -0.18:
			meteor.x = 0.42 + randf() * 0.78
			meteor.y = -0.12 - randf() * 0.18


func _seed_embers() -> void:
	_embers.clear()
	for i in range(_EMBER_COUNT):
		_embers.append({
			"x": randf(),
			"y": 0.11 + randf() * 0.36,
			"radius": 0.7 + randf() * 2.6,
			"speed": 0.012 + randf() * 0.036,
			"sway": 0.3 + randf() * 0.9,
			"alpha": 0.24 + randf() * 0.66,
			"phase": randf() * TAU,
		})


func _update_embers(delta: float, viewport_size: Vector2) -> void:
	var active_count: int = int(_embers.size() * maxf(0.06, 1.0))
	for i in range(active_count):
		var ember: Dictionary = _embers[i]
		ember.y -= ember.speed * delta * (0.55 + 1.0)
		ember.x += sin(_volcano_time + ember.phase) * ember.sway * delta * 0.012
		if ember.y < 0.08:
			ember.y = _band_bottom_norm - 0.02 + randf() * 0.02
			ember.x = randf()


class ParticleLayer:
	extends Control

	var renderer: WeatherOverlayRenderer = null

	func _ready() -> void:
		set_anchors_preset(Control.PRESET_FULL_RECT)
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		if renderer == null:
			return
		var viewport_size: Vector2 = get_viewport_rect().size
		var top: float = viewport_size.y * WeatherOverlayRenderer.SURFACE_TOP
		var bottom: float = viewport_size.y * renderer._band_bottom_norm
		if renderer._storm_strength > 0.001:
			_draw_snow(viewport_size, top, bottom)
		if renderer._volcano_active:
			_draw_meteors(viewport_size, top, bottom)
			_draw_embers(viewport_size, top, bottom)

	func _draw_snow(viewport_size: Vector2, top: float, bottom: float) -> void:
		var wind_x: float = WeatherOverlayRenderer._WIND * 1.8
		var active_count: int = int(renderer._snowflakes.size() * maxf(0.12, WeatherOverlayRenderer._STORM_INTENSITY))
		var width: float = viewport_size.x
		var height: float = viewport_size.y
		for i in range(active_count):
			var flake: Dictionary = renderer._snowflakes[i]
			var x: float = flake.x * width
			var y: float = flake.y * height
			if y < top - 10.0 or y > bottom + 10.0:
				continue
			if _in_lantern_shelter(Vector2(x, y)):
				continue
			var gust: float = 1.0 + sin(Time.get_ticks_msec() / 1000.0 * 1.2 + flake.phase) * 0.34
			var length: float = flake.length * height * 1.25 * gust
			var alpha: float = flake.alpha * (0.28 + WeatherOverlayRenderer._STORM_INTENSITY * 0.72) * renderer._storm_strength
			var head: Vector2 = Vector2(x, y)
			var tail: Vector2 = Vector2(x - wind_x * length, y - length)
			var col: Color = Color(0.945, 0.973, 1.0, alpha)
			draw_line(tail, head, Color(col.r, col.g, col.b, alpha * 0.35), flake.width * 3.2)
			draw_line(tail, head, col, flake.width)

	func _draw_meteors(viewport_size: Vector2, top: float, bottom: float) -> void:
		var active_count: int = int(renderer._meteors.size() * maxf(0.08, 1.0))
		var width: float = viewport_size.x
		var height: float = viewport_size.y
		for i in range(active_count):
			var meteor: Dictionary = renderer._meteors[i]
			if renderer._volcano_time < meteor.delay:
				continue
			var x: float = meteor.x * width
			var y: float = meteor.y * height
			if y < top - 30.0 or y > bottom + 40.0:
				continue
			var length: float = meteor.length * height * 1.4
			var tail_x: float = x + length * 0.5
			var tail_y: float = y - length
			var glow: float = 0.35 + 0.65 * pow(sin(Time.get_ticks_msec() / 1000.0 * 6.0 + meteor.phase), 2.0)
			var head: Vector2 = Vector2(x, y)
			var tail: Vector2 = Vector2(tail_x, tail_y)
			draw_line(tail, head, Color(1.0, 0.345, 0.11, 0.24 * glow), meteor.width * 3.2)
			draw_line(tail, head, Color(1.0, 0.894, 0.573, 0.82), meteor.width)
			draw_circle(head, meteor.width * 1.7, Color(1.0, 0.965, 0.8, 0.9))
			# Subtle impact flash near ground line.
			var ground: float = renderer._band_bottom_norm
			if meteor.y > ground - 0.02 and meteor.y < ground:
				var flash: float = 1.0 - absf(meteor.y - (ground - 0.01)) / 0.01
				if flash > 0.0:
					draw_circle(head, meteor.width * 4.0 * flash, Color(1.0, 0.76, 0.35, 0.35 * flash))

	func _draw_embers(viewport_size: Vector2, top: float, bottom: float) -> void:
		var active_count: int = int(renderer._embers.size() * maxf(0.06, 1.0))
		var width: float = viewport_size.x
		var height: float = viewport_size.y
		for i in range(active_count):
			var ember: Dictionary = renderer._embers[i]
			var x: float = ember.x * width
			var y: float = ember.y * height
			if y < top or y > bottom + height * 0.03:
				continue
			var flicker: float = 0.55 + 0.45 * sin(Time.get_ticks_msec() / 1000.0 * 8.0 + ember.phase)
			var alpha: float = ember.alpha * flicker
			draw_circle(Vector2(x, y), ember.radius, Color(1.0, 0.494, 0.149, alpha))

	func _in_lantern_shelter(screen_pos: Vector2) -> bool:
		for i in range(renderer._lantern_pos_array.size()):
			var d: float = screen_pos.distance_to(renderer._lantern_pos_array[i])
			if d < renderer._lantern_radius_array[i] * 0.7:
				return true
		return false
