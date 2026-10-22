## Phase 2 lighting & mood (roadmap/3d-conversion/phase-2-art-pass.md §2.4).
##
## Weather-reactive mood controller: owns the WorldEnvironment + sun found
## under its parent's "Lights" node and tweens them toward per-mood targets
## (rate ~2/s) in _process. Also applies the 3D rework phase 3 post stack:
## ACES tonemapping, emissive bloom (Standard+), depth fog (all presets) and
## SSAO (Fancy), all gated by ArtStyle3D.apply_quality_settings(). Base overcast; the underground view drops to a
## dark, faintly warm mine; snowstorms flatten to white gloom; volcano events
## cast a menacing red-orange from above (with the warning acting as a subtle
## pre-tension); an underground lava flood tints the ambient toward the lava
## palette. 3D rework phase 5: during the volcano warning the sun pulses on a
## ~0.9s beat toward the eruption cast — the pre-eruption "light sweep" the
## 2D HUD banner can't show in 3D. Presentation only — never touches the sim.
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

## Per-mood light targets: sun color/energy + ambient color/energy.
## 3D rework phase 3 retune: the terrain albedo pass is lit now, and ACES
## tonemapping compresses brights — the underground mood needed a lift so the
## mine reads dark-warm rather than black.
const _MOODS: Dictionary = {
	"overcast": {
		"sun_color": Color(0.82, 0.87, 0.96),
		"sun_energy": 1.1,
		"ambient_color": Color(0.32, 0.38, 0.46),
		"ambient_energy": 0.5,
	},
	"underground": {
		"sun_color": Color(0.9, 0.78, 0.6),
		"sun_energy": 0.5,
		"ambient_color": Color(0.16, 0.19, 0.24),
		"ambient_energy": 0.32,
	},
	"storm": {
		"sun_color": Color(0.75, 0.8, 0.88),
		"sun_energy": 0.7,
		"ambient_color": Color(0.3, 0.35, 0.42),
		"ambient_energy": 0.3,
	},
	"volcano": {
		"sun_color": Color(1.0, 0.45, 0.25),
		"sun_energy": 1.4,
		"ambient_color": Color(0.42, 0.3, 0.26),
		"ambient_energy": 0.55,
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

var _pc_connected: bool = false


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


## 3D rework phase 3: the post-processing preset gates live on ArtStyle3D
## (glow Standard+, SSAO Fancy, fog everywhere, Fancy-only shadows) and land
## here on the owned rig — call again after a runtime quality flip.
func apply_quality_settings() -> void:
	if _sun != null:
		_sun.shadow_enabled = ArtStyle3D.shadows_enabled()
		_sun.directional_shadow_max_distance = ArtStyle3D.shadow_distance()
	if _env != null:
		_env.glow_enabled = ArtStyle3D.glow_enabled()
		_env.ssao_enabled = ArtStyle3D.ssao_enabled()
		# Atmospheric depth cueing at every tier; the fog color/density are
		# scene defaults. Fog-of-war stays the much darker vertex-color read.
		_env.fog_enabled = ArtStyle3D.fog_enabled()


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
	_tween_toward(_apply_warning_pulse(_MOODS[get_mood_name()], delta), lava_glow, delta)


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


func _tween_toward(target: Dictionary, lava_glow: bool, delta: float) -> void:
	if _sun == null and _env == null:
		return
	var f: float = 1.0 - exp(-TWEEN_RATE * delta)
	var ambient_color: Color = target["ambient_color"]
	var ambient_energy: float = target["ambient_energy"]
	if lava_glow:
		# Warm red under-glow rising from the flood below.
		ambient_color = ambient_color.lerp(ArtStyle3D.PALETTE["lava"], 0.35)
		ambient_energy += 0.1
	if _sun != null:
		_sun.light_color = _sun.light_color.lerp(target["sun_color"], f)
		_sun.light_energy = lerpf(_sun.light_energy, target["sun_energy"], f)
	if _env != null:
		_env.ambient_light_color = _env.ambient_light_color.lerp(ambient_color, f)
		_env.ambient_light_energy = lerpf(_env.ambient_light_energy, ambient_energy, f)


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
