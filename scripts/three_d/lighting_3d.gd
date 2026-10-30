## Weather-reactive mood controller for the WorldEnvironment and sun.
## R2 grades every mood onto the visual revamp's cold palette. Underground is
## near-dark so amber lanterns own the warmth; storms flatten toward blue-white
## gloom; eruptions keep a cold key/ambient so meteors and lava are the warm
## heroes. The existing warning pulse briefly warms the key without accumulating.
## Post remains ACES everywhere, warm-source bloom on Standard+, depth fog on
## every tier, and SSAO/shadows on Fancy. Presentation only.
##
## WeatherManager signals are wired in setup() (the autoload always exists);
## PlayerController (view authority) and GridWorld (lava state) mount deferred
## with the sim, so they are connected lazily from _process until they appear.
## All node lookups are guarded so the class can be instanced bare in tests.
extends Node3D
class_name Lighting3D

## Exponential tween rate (1/s) toward the active mood target.
const TWEEN_RATE: float = 2.0

## 3D rework phase 5: warning-pulse period (seconds per beat) and the relative
## overdrive a beat adds above the volcano mood targets (applied to the tween
## TARGET, so the pulse stays bounded instead of accumulating per frame).
const WARNING_PULSE_PERIOD: float = 0.9
const WARNING_PULSE_ENERGY: float = 0.45
const WARNING_PULSE_TINT := Color(1.0, 0.28, 0.12)

const _MOODS: Dictionary = {
	"overcast": {
		"sun_color": Color("#C4D3E6"),
		"sun_energy": 1.0,
		"ambient_color": ArtStyle3D.PALETTE.night,
		"ambient_energy": 0.65,
		"background_color": ArtStyle3D.PALETTE.night,
		"fog_color": ArtStyle3D.PALETTE.night,
		"fog_density": 0.02,
	},
	"underground": {
		"sun_color": Color("#6C7684"),
		"sun_energy": 0.18,
		"ambient_color": ArtStyle3D.PALETTE.rock_dark,
		"ambient_energy": 0.28,
		"background_color": ArtStyle3D.PALETTE.rock_dark,
		"fog_color": ArtStyle3D.PALETTE.rock_dark,
		"fog_density": 0.035,
	},
	"storm": {
		"sun_color": ArtStyle3D.PALETTE.storm_gloom,
		"sun_energy": 0.55,
		"ambient_color": Color("#53677E"),
		"ambient_energy": 0.35,
		"background_color": Color("#53677E"),
		"fog_color": Color("#6E8095"),
		"fog_density": 0.055,
	},
	"volcano": {
		"sun_color": Color("#91A4BC"),
		"sun_energy": 0.85,
		"ambient_color": ArtStyle3D.PALETTE.night,
		"ambient_energy": 0.4,
		"background_color": ArtStyle3D.PALETTE.rock_dark,
		"fog_color": ArtStyle3D.PALETTE.rock,
		"fog_density": 0.06,
	},
}

var _camera: Camera3D
var _sun: DirectionalLight3D
var _env: Environment
var _grid: GridWorld

# Mood drivers. Weather state is polled every frame (cheap, and reconciles
# signals fired before this node existed); the signal handlers below nudge
# the flags immediately so a frame-zero transition doesn't wait for _process.
var _underground_view: bool = false
var _storm: bool = false
var _volcano: bool = false
var _lava_event: bool = false

## 3D rework phase 5: phase accumulator for the pre-eruption warning pulse.
var _warning_pulse_time: float = 0.0
var _storm_gust_time: float = 0.0

var _pc_connected: bool = false
## Reusable per-frame mood target — the storm-gust layer used to duplicate a
## mood Dictionary every frame for the whole storm; the resolution now fills
## this fixed-key dict in place. (_apply_warning_pulse keeps its test-facing
## pure form; it only allocates during the rare eruption-warning window.)
var _resolved: Dictionary = {}


func setup(camera: Camera3D) -> void:
	_camera = camera
	# Live under World3D: the light rig is a sibling branch ("Lights").
	var parent: Node = get_parent()
	if parent != null:
		_sun = parent.get_node_or_null("Lights/DirectionalLight3D") as DirectionalLight3D
		var env_node: WorldEnvironment = parent.get_node_or_null("Lights/WorldEnvironment") as WorldEnvironment
		if env_node != null:
			_env = env_node.environment
	if _sun != null or _env != null:
		apply_quality_settings()
	WeatherManager.snowstorm_started.connect(_on_snowstorm_started)
	WeatherManager.snowstorm_ended.connect(_on_snowstorm_ended)
	WeatherManager.volcano_warning_started.connect(_on_volcano_warning_started)
	WeatherManager.volcano_started.connect(_on_volcano_started)
	WeatherManager.volcano_ended.connect(_on_volcano_ended)
	_fetch_grid()


## Apply shared R2 post tokens and the preset gates after startup or a live
## quality change. Fog-of-war remains a separate, darker terrain treatment.
## Also applies the per-tier viewport render scale / MSAA / shadow-split
## configuration (the perf-side half of the quality presets).
func apply_quality_settings() -> void:
	if _sun != null:
		_sun.shadow_enabled = ArtStyle3D.shadows_enabled()
		_sun.directional_shadow_max_distance = ArtStyle3D.shadow_distance()
		# Two blended PSSM splits cover the 40-unit top-down board; the
		# engine default of four doubles the shadow pass for no visible
		# gain at this camera angle.
		_sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS
		_sun.directional_shadow_blend_splits = true
	if _env != null:
		_env.background_color = ArtStyle3D.PALETTE.night
		_env.fog_light_color = ArtStyle3D.PALETTE.night
		_env.glow_enabled = ArtStyle3D.glow_enabled()
		_env.glow_hdr_threshold = ArtStyle3D.BLOOM_HDR_THRESHOLD
		_env.glow_intensity = ArtStyle3D.BLOOM_INTENSITY
		_env.glow_strength = ArtStyle3D.BLOOM_STRENGTH
		_env.ssao_enabled = ArtStyle3D.ssao_enabled()
		_env.fog_enabled = ArtStyle3D.fog_enabled()
	var viewport := get_viewport()
	if viewport != null:
		# FSR 1.0 upscaling where the renderer supports it (gl_compatibility
		# falls back to bilinear); the scale itself is the perf lever.
		if RenderingServer.get_current_rendering_method() == "gl_compatibility":
			viewport.scaling_3d_mode = Viewport.SCALING_3D_MODE_BILINEAR
		else:
			viewport.scaling_3d_mode = Viewport.SCALING_3D_MODE_FSR
		viewport.scaling_3d_scale = ArtStyle3D.render_scale()
		viewport.msaa_3d = Viewport.MSAA_2X if ArtStyle3D.msaa_enabled() else Viewport.MSAA_DISABLED


## Underground-view mood hook. The shell's view switch and (lazily connected)
## PlayerController both route here.
func set_underground_view(underground: bool) -> void:
	_underground_view = underground


## Current resolved mood, one of "overcast" / "underground" / "storm" /
## "volcano". Volcano beats storm (it is the more dramatic read, and a storm
## during an eruption reads as ashen gloom — still tinted from above).
func get_mood_name() -> String:
	if _volcano:
		return "volcano"
	if _storm:
		return "storm"
	if _underground_view:
		return "underground"
	return "overcast"


func _process(delta: float) -> void:
	_connect_player_controller()
	if _grid == null or not is_instance_valid(_grid):
		_fetch_grid()
	_reconcile_weather()
	var lava_glow: bool = _lava_event
	if not lava_glow and _underground_view and _grid != null:
		lava_glow = _grid.is_lava_active() or _grid.is_lava_warning()
	_tween_toward(_resolve_mood(delta, lava_glow), delta)


## Fills the reusable _resolved mood target in place: base mood for the
## current state, plus the storm gust on fog, plus the eruption-warning beat
## on sun/ambient, plus the warm lava under-glow.
func _resolve_mood(delta: float, lava_glow: bool) -> Dictionary:
	var mood_name := get_mood_name()
	var base: Dictionary = _MOODS[mood_name]
	_resolved["sun_color"] = base["sun_color"]
	_resolved["sun_energy"] = base["sun_energy"]
	_resolved["ambient_color"] = base["ambient_color"]
	_resolved["ambient_energy"] = base["ambient_energy"]
	_resolved["background_color"] = base["background_color"]
	_resolved["fog_color"] = base["fog_color"]
	_resolved["fog_density"] = base["fog_density"]
	if mood_name == "storm":
		_storm_gust_time += delta
		var gust := clampf(0.5 + 0.5 * sin(_storm_gust_time * 1.9) + 0.25 * sin(_storm_gust_time * 0.63), 0.0, 1.0)
		_resolved["fog_density"] = float(base["fog_density"]) * lerpf(0.75, 1.25, gust)
		_resolved["fog_color"] = (base["fog_color"] as Color).lerp(ArtStyle3D.PALETTE.storm_gloom, 0.08 * gust)
	else:
		_storm_gust_time = 0.0
	if WeatherManager.is_volcano_warning():
		var pulsed: Dictionary = _apply_warning_pulse(_resolved, delta)
		_resolved["sun_energy"] = pulsed["sun_energy"]
		_resolved["sun_color"] = pulsed["sun_color"]
		_resolved["ambient_energy"] = pulsed["ambient_energy"]
	if lava_glow:
		# Warm red under-glow rising from the flood below.
		_resolved["ambient_color"] = (_resolved["ambient_color"] as Color).lerp(ArtStyle3D.PALETTE["lava"], 0.35)
		_resolved["ambient_energy"] = float(_resolved["ambient_energy"]) + 0.1
	return _resolved


## 3D rework phase 5: while the eruption warning counts down (meteors not yet
## falling), the mood target itself throbs hotter on a ~0.9s beat. Modulating
## the target keeps the pulse bounded — the light chases a moving target with
## the same exponential tween, so the beat can never accumulate.
func _apply_warning_pulse(target: Dictionary, delta: float) -> Dictionary:
	if not WeatherManager.is_volcano_warning():
		_warning_pulse_time = 0.0
		return target
	_warning_pulse_time += delta
	var beat: float = 0.5 + 0.5 * sin(_warning_pulse_time * TAU / WARNING_PULSE_PERIOD)
	var pulsed: Dictionary = target.duplicate()
	pulsed["sun_energy"] = float(target["sun_energy"]) * (1.0 + WARNING_PULSE_ENERGY * beat)
	pulsed["sun_color"] = (target["sun_color"] as Color).lerp(WARNING_PULSE_TINT, 0.35 * beat)
	pulsed["ambient_energy"] = float(target["ambient_energy"]) * (1.0 + 0.25 * beat)
	return pulsed


func _exit_tree() -> void:
	# Guarded: unit tests can instance this bare / free the shell mid-signal.
	if WeatherManager.snowstorm_started.is_connected(_on_snowstorm_started):
		WeatherManager.snowstorm_started.disconnect(_on_snowstorm_started)
	if WeatherManager.snowstorm_ended.is_connected(_on_snowstorm_ended):
		WeatherManager.snowstorm_ended.disconnect(_on_snowstorm_ended)
	if WeatherManager.volcano_warning_started.is_connected(_on_volcano_warning_started):
		WeatherManager.volcano_warning_started.disconnect(_on_volcano_warning_started)
	if WeatherManager.volcano_started.is_connected(_on_volcano_started):
		WeatherManager.volcano_started.disconnect(_on_volcano_started)
	if WeatherManager.volcano_ended.is_connected(_on_volcano_ended):
		WeatherManager.volcano_ended.disconnect(_on_volcano_ended)
	if _pc_connected:
		var pc: Node = get_node_or_null("/root/Main/PlayerController")
		if pc != null and pc.view_mode_changed.is_connected(_on_view_mode_changed):
			pc.view_mode_changed.disconnect(_on_view_mode_changed)
		_pc_connected = false


func _tween_toward(target: Dictionary, delta: float) -> void:
	if _sun == null and _env == null:
		return
	var f: float = 1.0 - exp(-TWEEN_RATE * delta)
	if _sun != null:
		_sun.light_color = _sun.light_color.lerp(target["sun_color"], f)
		_sun.light_energy = lerpf(_sun.light_energy, target["sun_energy"], f)
	if _env != null:
		_env.ambient_light_color = _env.ambient_light_color.lerp(target["ambient_color"], f)
		_env.ambient_light_energy = lerpf(_env.ambient_light_energy, target["ambient_energy"], f)
		_env.background_color = _env.background_color.lerp(target["background_color"], f)
		_env.fog_light_color = _env.fog_light_color.lerp(target["fog_color"], f)
		_env.fog_density = lerpf(_env.fog_density, target["fog_density"], f)


func _reconcile_weather() -> void:
	_storm = WeatherManager.is_snowstorm_active()
	_volcano = WeatherManager.is_volcano_active() or WeatherManager.is_volcano_warning()


func _connect_player_controller() -> void:
	if _pc_connected:
		return
	var pc: Node = get_node_or_null("/root/Main/PlayerController")
	if pc == null:
		return  # Sim mounts deferred; retry next frame.
	pc.view_mode_changed.connect(_on_view_mode_changed)
	_pc_connected = true
	_on_view_mode_changed(pc.get_current_view_mode())


func _fetch_grid() -> void:
	_grid = get_node_or_null("/root/Main/World/GridWorld") as GridWorld
	if _grid == null:
		return
	if not _grid.lava_warning_started.is_connected(_on_lava_warning_started):
		_grid.lava_warning_started.connect(_on_lava_warning_started)
	if not _grid.lava_risen.is_connected(_on_lava_risen):
		_grid.lava_risen.connect(_on_lava_risen)
	if not _grid.lava_receded.is_connected(_on_lava_receded):
		_grid.lava_receded.connect(_on_lava_receded)


func _on_view_mode_changed(mode: PlayerController.ViewMode) -> void:
	set_underground_view(mode == PlayerController.ViewMode.UNDERGROUND)


func _on_snowstorm_started() -> void:
	_storm = true


func _on_snowstorm_ended() -> void:
	_storm = WeatherManager.is_snowstorm_active()


func _on_volcano_warning_started(_seconds: float) -> void:
	# Pre-tension: the warning already eases the sun toward the eruption cast.
	_volcano = true


func _on_volcano_started() -> void:
	_volcano = true


func _on_volcano_ended() -> void:
	_volcano = WeatherManager.is_volcano_active() or WeatherManager.is_volcano_warning()


func _on_lava_warning_started(_seconds: float, _layers: int) -> void:
	_lava_event = true


func _on_lava_risen(_layers: int) -> void:
	_lava_event = true


func _on_lava_receded() -> void:
	_lava_event = false
