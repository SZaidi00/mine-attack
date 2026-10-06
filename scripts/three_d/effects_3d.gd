## Phase 2 effects (roadmap/3d-conversion/phase-2-art-pass.md §2.5).
##
## Art-directed cheap particles for the 3D presentation, all driven by sim
## state (signals + WeatherManager polls, never writes the sim):
##   - DustMotes     — slow drifting specks while the underground (Tab) view
##                     is active; off entirely on the Potato preset.
##   - StormSnow     — wind-swept snow streaks around the camera while a
##                     snowstorm rages (surface view); weather-significant, so
##                     it shows on every preset at particle_mult() counts.
##   - VolcanoEmbers — embers drifting up around the camera during eruptions
##                     (surface view); particles only — the red glow is the
##                     lighting pass.
##   - CaveInBurst0… — one-shot grey-brown dust puffs on grid.cave_in_occurred,
##                     a small reusable pool (freed/restarted, never re-alloc'd).
##
## All counts scale with ArtStyle3D.particle_mult(); continuous emitters are
## positioned on the camera's x/z focus each frame. Materials are unshaded
## billboards with a soft radial dot — few draw calls, no textures on disk.
##
## View mode arrives two ways: lazy-connected from
## /root/Main/PlayerController.view_mode_changed (the shell mounts the sim
## deferred, so the connect is retried in _process), or directly via
## set_underground_view() (shell/tests).
extends Node3D
class_name Effects3D

## 3D units per 2D pixel — mirrors main_3d.gd/terrain_3d.gd.
const WORLD_SCALE: float = 0.01

const STORM_SNOW_BASE_AMOUNT: int = 240
const EMBERS_BASE_AMOUNT: int = 110
const MOTES_BASE_AMOUNT: int = 130
const BURST_POOL_SIZE: int = 4
const BURST_BASE_AMOUNT: int = 26

const MOTES_NAME: StringName = &"DustMotes"
const STORM_NAME: StringName = &"StormSnow"
const EMBERS_NAME: StringName = &"VolcanoEmbers"

var _grid: GridWorld
var _camera: Camera3D
var _built := false
var _pc_connected := false
var _underground_view := false

var _motes: GPUParticles3D
var _storm: GPUParticles3D
var _embers: GPUParticles3D
var _bursts: Array[GPUParticles3D] = []
var _burst_index := 0

var _dot: Texture2D
var _particle_materials: Dictionary = {}


func setup(grid: GridWorld, camera: Camera3D) -> void:
	# The shell attaches this script at runtime (set_script on the in-tree
	# Effects3D container); a runtime-attached script's _process callback is
	# not wired automatically, so re-register it explicitly.
	set_process(true)
	_grid = grid
	_camera = camera
	if not _built:
		_build_emitters()
	if not _grid.cave_in_occurred.is_connected(_on_cave_in):
		_grid.cave_in_occurred.connect(_on_cave_in)
	_refresh_emitters()


## Layer (Tab) view switch. Called by the shell/tests directly, or via the
## PlayerController signal once the lazy connect lands.
func set_underground_view(underground: bool) -> void:
	_underground_view = underground
	_refresh_emitters()


func _process(_delta: float) -> void:
	if _grid == null or _camera == null or not is_instance_valid(_camera):
		_try_lazy_setup()
		return
	_ensure_pc_connected()
	_apply_quality_amounts()
	_refresh_emitters()
	# Continuous emitters track the camera's ground focus (x/z only; the
	# emitters' own heights are baked into their process materials).
	var focus: Vector3 = _camera.global_position
	_motes.position = Vector3(focus.x, 0.15, focus.z)
	_storm.position = Vector3(focus.x, 2.2, focus.z)
	_embers.position = Vector3(focus.x, 0.25, focus.z)


## The shell mounts the sim deferred; until /root/Main exists we retry the
## hookup every frame instead of requiring main_3d.gd ordering guarantees.
func _try_lazy_setup() -> void:
	var grid: GridWorld = get_node_or_null("/root/Main/World/GridWorld") as GridWorld
	var cam: Camera3D = get_viewport().get_camera_3d()
	if grid != null and cam != null:
		setup(grid, cam)


func _ensure_pc_connected() -> void:
	if _pc_connected:
		return
	var pc: Node = get_node_or_null("/root/Main/PlayerController")
	if pc == null:
		return
	if not pc.view_mode_changed.is_connected(_on_view_mode_changed):
		pc.view_mode_changed.connect(_on_view_mode_changed)
	_pc_connected = true
	set_underground_view(pc.get_current_view_mode() == PlayerController.ViewMode.UNDERGROUND)


func _on_view_mode_changed(mode: PlayerController.ViewMode) -> void:
	set_underground_view(mode == PlayerController.ViewMode.UNDERGROUND)


func _on_cave_in(center: Vector2i) -> void:
	if _bursts.is_empty() or _grid == null:
		return
	var burst: GPUParticles3D = _bursts[_burst_index]
	_burst_index = (_burst_index + 1) % _bursts.size()
	var ground: Vector2 = _grid.grid_to_world(center) * WORLD_SCALE
	burst.position = Vector3(ground.x, 0.05, ground.y)
	burst.restart()


## Emission state per emitter. Weather state is polled (not just signal-
## driven) because WeatherManager.reset() on scene reload emits nothing and
## the autoload outlives this node.
func _refresh_emitters() -> void:
	if not _built:
		return
	_motes.emitting = _underground_view and ArtStyle3D.detail_enabled()
	var surface_view := not _underground_view
	_storm.emitting = surface_view and WeatherManager.is_snowstorm_active()
	_embers.emitting = surface_view and WeatherManager.is_volcano_active()


## particle_mult() can change at runtime (quality presets) — adjust amounts
## on the fly (setting .amount restarts that emitter, so only on change).
func _apply_quality_amounts() -> void:
	var mult := ArtStyle3D.particle_mult()
	_set_amount(_motes, int(MOTES_BASE_AMOUNT * mult))
	_set_amount(_storm, int(STORM_SNOW_BASE_AMOUNT * mult))
	_set_amount(_embers, int(EMBERS_BASE_AMOUNT * mult))
	for b in _bursts:
		_set_amount(b, int(BURST_BASE_AMOUNT * mult))


func _set_amount(p: GPUParticles3D, n: int) -> void:
	if p.amount != n:
		p.amount = n


# ─── Emitter construction ───

func _build_emitters() -> void:
	_built = true
	_dot = _make_dot_texture()

	_motes = _make_continuous(
		MOTES_NAME, MOTES_BASE_AMOUNT,
		_motes_material(), _fade_ramp(Color(0.85, 0.78, 0.6, 0.28)),
		_motes_process())
	add_child(_motes)

	_storm = _make_continuous(
		STORM_NAME, STORM_SNOW_BASE_AMOUNT,
		_particle_material(Color(1, 1, 1), 0.6), _fade_ramp(Color(0.93, 0.96, 0.98, 0.8)),
		_storm_process())
	add_child(_storm)

	_embers = _make_continuous(
		EMBERS_NAME, EMBERS_BASE_AMOUNT,
		_particle_material(Color(1, 1, 1), 0.85), _fade_ramp(Color(0.98, 0.42, 0.1, 0.9)),
		_embers_process())
	add_child(_embers)

	for i in range(BURST_POOL_SIZE):
		var burst := _make_burst(i)
		_bursts.append(burst)
		add_child(burst)


func _make_continuous(name_: StringName, amount: int, mesh_mat: StandardMaterial3D, ramp: GradientTexture1D, pm: ParticleProcessMaterial) -> GPUParticles3D:
	var p := GPUParticles3D.new()
	p.name = name_
	p.amount = amount
	p.lifetime = 4.0
	p.emitting = false
	var quad := QuadMesh.new()
	quad.size = Vector2(0.06, 0.06)
	quad.material = mesh_mat
	p.draw_pass_1 = quad
	pm.color_ramp = ramp
	p.process_material = pm
	return p


func _make_burst(i: int) -> GPUParticles3D:
	var p := GPUParticles3D.new()
	p.name = "CaveInBurst%d" % i
	p.amount = BURST_BASE_AMOUNT
	p.lifetime = 1.6
	p.one_shot = true
	p.explosiveness = 0.85
	p.emitting = false
	var quad := QuadMesh.new()
	quad.size = Vector2(0.12, 0.12)
	quad.material = _particle_material(Color(1, 1, 1), 0.55)
	p.draw_pass_1 = quad
	# Grey-brown dust: pop upward then settle.
	var ramp := Gradient.new()
	ramp.set_color(0, Color(0.48, 0.42, 0.36, 0.0))
	ramp.set_color(1, Color(0.48, 0.42, 0.36, 0.55))
	ramp.add_point(0.25, Color(0.48, 0.42, 0.36, 0.5))
	ramp.add_point(0.75, Color(0.42, 0.37, 0.32, 0.35))
	var ramp_tex := GradientTexture1D.new()
	ramp_tex.gradient = ramp
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	pm.emission_sphere_radius = 0.35
	pm.direction = Vector3(0.0, 1.0, 0.0)
	pm.spread = 55.0
	pm.gravity = Vector3(0.0, -0.7, 0.0)
	pm.initial_velocity_min = 0.4
	pm.initial_velocity_max = 1.1
	pm.scale_min = 0.4
	pm.scale_max = 1.0
	pm.color_ramp = ramp_tex
	p.process_material = pm
	return p


func _motes_process() -> ParticleProcessMaterial:
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pm.emission_box_extents = Vector3(7.0, 2.2, 5.0)
	pm.direction = Vector3(1.0, 0.12, 0.3)
	pm.spread = 180.0
	pm.gravity = Vector3.ZERO
	pm.initial_velocity_min = 0.06
	pm.initial_velocity_max = 0.22
	pm.scale_min = 0.3
	pm.scale_max = 0.8
	return pm


func _storm_process() -> ParticleProcessMaterial:
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pm.emission_box_extents = Vector3(10.0, 4.0, 8.0)
	pm.direction = Vector3(0.3, -1.0, 0.08)
	pm.spread = 14.0
	# Sideways gravity is the wind gust; falling snow stays the dominant drift.
	pm.gravity = Vector3(2.2, -3.2, 0.5)
	pm.initial_velocity_min = 2.4
	pm.initial_velocity_max = 4.8
	pm.scale_min = 0.25
	pm.scale_max = 0.6
	return pm


func _embers_process() -> ParticleProcessMaterial:
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pm.emission_box_extents = Vector3(8.0, 1.4, 6.0)
	pm.direction = Vector3(0.12, 1.0, 0.05)
	pm.spread = 28.0
	# Net upward drift: embers ride the heat column with a lazy sideways lean.
	pm.gravity = Vector3(0.12, 0.5, 0.0)
	pm.initial_velocity_min = 0.35
	pm.initial_velocity_max = 0.9
	pm.scale_min = 0.2
	pm.scale_max = 0.5
	return pm


## Unshaded billboard material cache. ArtStyle3D.get_material can't be used
## directly: its cache is shared with lit world geometry, and particles need
## SHADING_MODE_UNSHADED + BILLBOARD_PARTICLES + vertex-color albedo.
func _particle_material(color: Color, alpha: float) -> StandardMaterial3D:
	var key := "%s|%f" % [color.to_html(), alpha]
	if _particle_materials.has(key):
		return _particle_materials[key]
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.vertex_color_use_as_albedo = true
	mat.albedo_texture = _dot
	mat.albedo_color = Color(color.r, color.g, color.b, alpha)
	mat.roughness = 1.0
	mat.metallic = 0.0
	_particle_materials[key] = mat
	return mat


## Warm ore-tinted motes get a whisper of self-illumination underground.
func _motes_material() -> StandardMaterial3D:
	var mat := _particle_material(Color(0.85, 0.78, 0.6), 1.0).duplicate()
	mat.emission_enabled = true
	mat.emission = Color(0.85, 0.72, 0.45)
	mat.emission_energy_multiplier = 0.4
	return mat


## Fade-in/hold/fade-out ramp: particles dissolve instead of popping.
func _fade_ramp(tint: Color) -> GradientTexture1D:
	var ramp := Gradient.new()
	ramp.set_color(0, Color(tint.r, tint.g, tint.b, 0.0))
	ramp.set_color(1, Color(tint.r, tint.g, tint.b, 0.0))
	ramp.add_point(0.15, tint)
	ramp.add_point(0.8, tint)
	var tex := GradientTexture1D.new()
	tex.gradient = ramp
	return tex


## Small soft radial dot (mirrors GridAmbience's 2D dot; no art dependency).
func _make_dot_texture() -> Texture2D:
	var img := Image.create(16, 16, false, Image.FORMAT_RGBA8)
	for x in range(16):
		for y in range(16):
			var d: float = Vector2(x - 7.5, y - 7.5).length()
			img.set_pixel(x, y, Color(1, 1, 1, clampf(1.0 - d / 8.0, 0.0, 1.0)))
	return ImageTexture.create_from_image(img)
