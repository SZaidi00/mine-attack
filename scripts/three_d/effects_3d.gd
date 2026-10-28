## Sim-driven 3D atmosphere and event particles. Overlapping camera-local
## volumes begin behind the camera and carry snow, meteors, cinders, and ash
## continuously into the distance without a clipped screen-space weather band.
## Underground motes and cave-in bursts remain world-space effects. All counts
## scale with ArtStyle3D.particle_mult(); weather never writes sim state.
extends Node3D
class_name Effects3D

const WORLD_SCALE: float = 0.01

const STORM_SNOW_BASE_AMOUNT: int = 960
const STORM_NEAR_BASE_AMOUNT: int = 1600
const EMBERS_BASE_AMOUNT: int = 500
const ASH_BASE_AMOUNT: int = 600
const ASH_NEAR_BASE_AMOUNT: int = 900
const METEOR_SHOWER_BASE_AMOUNT: int = 400
const MOTES_BASE_AMOUNT: int = 130
const BURST_POOL_SIZE: int = 4
const BURST_BASE_AMOUNT: int = 26

const MOTES_NAME: StringName = &"DustMotes"
const STORM_NAME: StringName = &"StormSnow"
const STORM_NEAR_NAME: StringName = &"StormSnowNear"
const EMBERS_NAME: StringName = &"VolcanoEmbers"
const ASH_NAME: StringName = &"VolcanoAsh"
const ASH_NEAR_NAME: StringName = &"VolcanoAshNear"
const METEOR_SHOWER_NAME: StringName = &"VolcanoMeteorShower"

const STORM_VOLUME_CENTER := Vector3(0.0, 0.0, -14.0)
const STORM_VOLUME_EXTENTS := Vector3(20.0, 12.0, 20.0)
const ERUPTION_VOLUME_CENTER := Vector3(0.0, 0.0, -14.0)
const ERUPTION_VOLUME_EXTENTS := Vector3(20.0, 12.0, 20.0)
const NEAR_VOLUME_CENTER := Vector3(0.0, 0.0, -3.0)
const NEAR_VOLUME_EXTENTS := Vector3(4.5, 3.5, 4.5)

var _grid: GridWorld
var _camera: Camera3D
var _built := false
var _pc_connected := false
var _underground_view := false

var _motes: GPUParticles3D
var _storm: GPUParticles3D
var _storm_near: GPUParticles3D
var _embers: GPUParticles3D
var _ash: GPUParticles3D
var _ash_near: GPUParticles3D
var _meteor_shower: GPUParticles3D
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
	var focus: Vector3 = _camera.global_position
	_motes.position = Vector3(focus.x, 0.15, focus.z)
	_track_camera_volume(_storm, STORM_VOLUME_CENTER)
	_track_camera_volume(_storm_near, NEAR_VOLUME_CENTER)
	_track_camera_volume(_embers, ERUPTION_VOLUME_CENTER)
	_track_camera_volume(_ash, ERUPTION_VOLUME_CENTER)
	_track_camera_volume(_ash_near, NEAR_VOLUME_CENTER)
	_track_camera_volume(_meteor_shower, ERUPTION_VOLUME_CENTER)


func _track_camera_volume(p: GPUParticles3D, center: Vector3) -> void:
	p.global_transform = _camera.global_transform * Transform3D(Basis.IDENTITY, center)


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
	_storm_near.emitting = _storm.emitting
	_embers.emitting = surface_view and (WeatherManager.is_volcano_active() or WeatherManager.is_volcano_warning())
	_ash.emitting = surface_view and WeatherManager.is_volcano_active()
	_ash_near.emitting = _ash.emitting
	_meteor_shower.emitting = _ash.emitting


## Ember density relative to the full eruption: ramps from a sparse trickle
## to near-full over the warning window. Quantized to steps — changing
## .amount restarts the emitter, so a smoothly varying amount would restart
## it every frame.
func _ember_intensity() -> float:
	if WeatherManager.is_volcano_active():
		return 1.0
	if WeatherManager.is_volcano_warning():
		var total: float = maxf(Constants.VOLCANO_WARNING_TIME, 0.01)
		var progress: float = 1.0 - clampf(WeatherManager.get_volcano_warning_remaining() / total, 0.0, 1.0)
		return lerpf(0.3, 0.9, floor(progress * 6.0) / 6.0)
	return 0.0


## particle_mult() can change at runtime (quality presets) — adjust amounts
## on the fly (setting .amount restarts that emitter, so only on change).
func _apply_quality_amounts() -> void:
	var mult := ArtStyle3D.particle_mult()
	_set_amount(_motes, int(MOTES_BASE_AMOUNT * mult))
	_set_amount(_storm, int(STORM_SNOW_BASE_AMOUNT * mult))
	_set_amount(_storm_near, int(STORM_NEAR_BASE_AMOUNT * mult))
	_set_amount(_embers, int(EMBERS_BASE_AMOUNT * mult * _ember_intensity()))
	_set_amount(_ash, int(ASH_BASE_AMOUNT * mult))
	_set_amount(_ash_near, int(ASH_NEAR_BASE_AMOUNT * mult))
	_set_amount(_meteor_shower, int(METEOR_SHOWER_BASE_AMOUNT * mult))
	for b in _bursts:
		_set_amount(b, int(BURST_BASE_AMOUNT * mult))


func _set_amount(p: GPUParticles3D, n: int) -> void:
	n = maxi(n, 1)  # GPUParticles3D rejects amount < 1 (idle emitters sit at 1).
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
		_particle_material(Color(1, 1, 1), 0.9), _fade_ramp(Color(0.97, 0.98, 1.0, 0.96)),
		_storm_process())
	_configure_camera_volume(_storm, STORM_VOLUME_EXTENTS)
	(_storm.draw_pass_1 as QuadMesh).size = Vector2(0.035, 0.32)
	add_child(_storm)

	_storm_near = _make_continuous(
		STORM_NEAR_NAME, STORM_NEAR_BASE_AMOUNT,
		_particle_material(Color(1, 1, 1), 0.95), _fade_ramp(Color(0.98, 0.99, 1.0, 0.98)),
		_storm_near_process())
	_storm_near.lifetime = 2.2
	_configure_camera_volume(_storm_near, NEAR_VOLUME_EXTENTS)
	(_storm_near.draw_pass_1 as QuadMesh).size = Vector2(0.035, 0.32)
	add_child(_storm_near)

	_embers = _make_continuous(
		EMBERS_NAME, EMBERS_BASE_AMOUNT,
		_particle_material(Color(1, 1, 1), 0.9), _fade_ramp(Color(0.98, 0.42, 0.1, 0.95)),
		_embers_process())
	_configure_camera_volume(_embers, ERUPTION_VOLUME_EXTENTS)
	(_embers.draw_pass_1 as QuadMesh).size = Vector2(0.09, 0.09)
	add_child(_embers)

	_ash = _make_continuous(
		ASH_NAME, ASH_BASE_AMOUNT,
		_particle_material(Color(0.62, 0.65, 0.7), 0.58), _fade_ramp(Color(0.58, 0.61, 0.67, 0.68)),
		_ash_process())
	_configure_camera_volume(_ash, ERUPTION_VOLUME_EXTENTS)
	(_ash.draw_pass_1 as QuadMesh).size = Vector2(0.05, 0.05)
	add_child(_ash)

	_ash_near = _make_continuous(
		ASH_NEAR_NAME, ASH_NEAR_BASE_AMOUNT,
		_particle_material(Color(0.68, 0.7, 0.74), 0.62), _fade_ramp(Color(0.62, 0.65, 0.7, 0.72)),
		_ash_near_process())
	_ash_near.lifetime = 3.0
	_configure_camera_volume(_ash_near, NEAR_VOLUME_EXTENTS)
	(_ash_near.draw_pass_1 as QuadMesh).size = Vector2(0.04, 0.04)
	add_child(_ash_near)

	var meteor_mat := _particle_material(Color(1.0, 0.72, 0.3), 0.95).duplicate()
	ArtStyle3D.apply_emission(meteor_mat, Color(1.0, 0.45, 0.08), 2.2)
	_meteor_shower = _make_continuous(
		METEOR_SHOWER_NAME, METEOR_SHOWER_BASE_AMOUNT,
		meteor_mat, _fade_ramp(Color(1.0, 0.72, 0.3, 0.95)),
		_meteor_shower_process())
	_configure_camera_volume(_meteor_shower, ERUPTION_VOLUME_EXTENTS)
	(_meteor_shower.draw_pass_1 as QuadMesh).size = Vector2(0.025, 0.45)
	add_child(_meteor_shower)

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


func _configure_camera_volume(p: GPUParticles3D, extents: Vector3) -> void:
	p.local_coords = true
	p.visibility_aabb = AABB(-extents - Vector3.ONE * 5.0, extents * 2.0 + Vector3.ONE * 10.0)


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
	pm.emission_box_extents = STORM_VOLUME_EXTENTS
	pm.direction = Vector3(0.75, -1.0, 0.15)
	pm.spread = 10.0
	pm.gravity = Vector3(2.8, -4.5, 0.4)
	pm.initial_velocity_min = 4.5
	pm.initial_velocity_max = 7.5
	pm.scale_min = 0.25
	pm.scale_max = 0.7
	return pm


func _embers_process() -> ParticleProcessMaterial:
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pm.emission_box_extents = ERUPTION_VOLUME_EXTENTS
	pm.direction = Vector3(0.18, 0.8, 0.25)
	pm.spread = 35.0
	pm.gravity = Vector3(0.08, 0.35, 0.08)
	pm.initial_velocity_min = 0.5
	pm.initial_velocity_max = 1.2
	pm.scale_min = 0.15
	pm.scale_max = 0.55
	return pm


func _ash_process() -> ParticleProcessMaterial:
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pm.emission_box_extents = ERUPTION_VOLUME_EXTENTS
	pm.direction = Vector3(-0.15, -0.65, 0.1)
	pm.spread = 45.0
	pm.gravity = Vector3(0.3, -0.45, 0.08)
	pm.initial_velocity_min = 0.25
	pm.initial_velocity_max = 0.7
	pm.scale_min = 0.25
	pm.scale_max = 0.65
	return pm


func _storm_near_process() -> ParticleProcessMaterial:
	var pm := _storm_process()
	pm.emission_box_extents = NEAR_VOLUME_EXTENTS
	pm.initial_velocity_min = 1.8
	pm.initial_velocity_max = 3.5
	return pm


func _ash_near_process() -> ParticleProcessMaterial:
	var pm := _ash_process()
	pm.emission_box_extents = NEAR_VOLUME_EXTENTS
	return pm


func _meteor_shower_process() -> ParticleProcessMaterial:
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pm.emission_box_extents = ERUPTION_VOLUME_EXTENTS
	pm.direction = Vector3(-0.35, -1.0, 0.1)
	pm.spread = 8.0
	pm.gravity = Vector3(-1.2, -4.0, 0.2)
	pm.initial_velocity_min = 5.0
	pm.initial_velocity_max = 8.0
	pm.scale_min = 0.35
	pm.scale_max = 0.85
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
	mat.disable_fog = true
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
	ArtStyle3D.apply_emission(mat, Color(0.85, 0.72, 0.45), 0.4)
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
