## 3D rework Phase 5 (roadmap/3d-rework/phase-5-effects-and-telegraphs--k3.md).
##
## Mirrors the sim's surface/underground hazard events into the 3D world —
## none of these are visible in 3D mode otherwise (the 2D effects live on
## hidden canvas layers). Pure sim -> render: every proxy reads sim state
## (meteor fall phase, burn-patch lifetime, the GridEvents lava schedule) and
## nothing is tracked separately, so e.g. a snowstorm extinguishing the sim's
## burn patches clears the 3D decals on the next reconcile.
##
##   - Meteors: per-frame reconcile against Meteor nodes (they parent to
##     current_scene). A falling emissive streak follows the 2D fall height;
##     the impact phase projects an expanding ring at exactly the sim's
##     impact_radius. Pooled; fog-honest like the projectile tracers.
##   - Burning ground: per-frame reconcile against the "burning_grounds"
##     group. Each patch gets a dark scorch disc + a pulsing emissive danger
##     ring at exactly the sim's damage radius, fading with the patch's
##     remaining lifetime. Visibility mirrors the sim's own fog gate.
##   - Lava-rise warning: while GridEvents is in its warning phase, an
##     emissive orange shimmer covers exactly the cells the wave profile will
##     flood (visible-to-player cells only). Rebuilt on a slow interval as
##     vision changes; hidden the moment the tide starts rising (the
##     terrain's own lava glow pass takes over).
##   - Cave-in warning: a shadow-darkened 3x3 zone decal plus a dust trickle
##     over the target cells for the warning window, hidden on the drop.
##
## Emission hierarchy (phase 5 retune, brightest wins bloom):
##   telegraph lines 3.2 > meteor/impact 2.8-3.0 ~ event-zone warnings
##   2.4-3.0 > combat tracers 2.2-2.6 > burn rings 2.0 > ambient
##   lava/lanterns 0.7-1.8 > decorative embers 0.9.
##
## Quality presets: Potato keeps the gameplay telegraphs (burn ring, zone
## decals) but drops the decorative shimmer pulse and the cave-in dust
## trickle; attack telegraph lines live in telegraph_3d.gd.
extends Node3D
class_name EventProxies3D

const WORLD_SCALE: float = Presentation3D.WORLD_SCALE

const MAX_METEORS: int = 12
const METEOR_STREAK_ENERGY: float = 2.8
const IMPACT_RING_ENERGY: float = 3.0
const BURN_RING_ENERGY: float = 2.0
const LAVA_SHIMMER_MIN_ENERGY: float = 2.4
const LAVA_SHIMMER_MAX_ENERGY: float = 3.0
const LAVA_SHIMMER_PERIOD: float = 0.7
const LAVA_REBUILD_INTERVAL: float = 0.5
const CAVEIN_DUST_AMOUNT: int = 24

const METEOR_COLOR := Color(1.0, 0.55, 0.12)
const IMPACT_COLOR := Color(1.0, 0.62, 0.15)
const BURN_RING_COLOR := Color(1.0, 0.42, 0.08)
const SCORCH_COLOR := Color(0.1, 0.05, 0.03, 0.55)
const LAVA_SHIMMER_COLOR := Color(1.0, 0.5, 0.1, 0.5)
const CAVEIN_SHADOW_COLOR := Color(0.02, 0.015, 0.01, 0.5)

var _grid: GridWorld
var _underground_view := false

# Meteor proxies (per-frame reconcile; a fall lasts only ~0.4s).
var _meteor_proxies: Dictionary = {}  # meteor instance id -> Node3D
var _meteor_pool: Array[Node3D] = []

# Burning-ground decals, keyed by the sim patch.
var _burn_decals: Dictionary = {}  # patch instance id -> Node3D
var _burn_pool: Array[Node3D] = []

# Lava-rise warning shimmer (single MultiMesh covering the flood zone).
var _lava_shimmer: MultiMeshInstance3D
var _lava_shimmer_mesh: MultiMesh
var _lava_shimmer_mat: StandardMaterial3D
var _lava_rebuild_accum := 0.0
var _shimmer_time := 0.0

# Cave-in warning zone.
var _cavein_zone: Node3D
var _cavein_zone_mat: StandardMaterial3D
var _cavein_dust: GPUParticles3D
var _cavein_warning_left := 0.0


func setup(grid: GridWorld) -> void:
	set_process(true)
	_grid = grid
	_build_lava_shimmer()
	_build_cavein_zone()
	if not _grid.cave_in_warning.is_connected(_on_cave_in_warning):
		_grid.cave_in_warning.connect(_on_cave_in_warning)
	if not _grid.cave_in_occurred.is_connected(_on_cave_in_occurred):
		_grid.cave_in_occurred.connect(_on_cave_in_occurred)


func set_underground_view(underground: bool) -> void:
	_underground_view = underground


func _process(delta: float) -> void:
	if _grid == null:
		return
	_reconcile_meteors()
	_reconcile_burn_patches()
	_update_lava_shimmer(delta)
	_update_cavein_zone(delta)


# ─── Meteors ───

func _reconcile_meteors() -> void:
	var seen := {}
	var scene: Node = get_tree().current_scene
	if scene != null and not _underground_view:
		for node in scene.get_children():
			var meteor := node as Meteor
			if meteor == null:
				continue
			seen[meteor.get_instance_id()] = true
			var proxy: Node3D = _meteor_proxies.get(meteor.get_instance_id())
			if proxy == null:
				if _meteor_proxies.size() >= MAX_METEORS:
					continue
				proxy = _acquire_meteor_proxy()
				_meteor_proxies[meteor.get_instance_id()] = proxy
			_sync_meteor(proxy, meteor)
	for id in _meteor_proxies.keys():
		if not seen.has(id):
			_release_meteor_proxy(_meteor_proxies[id])
			_meteor_proxies.erase(id)


func _sync_meteor(proxy: Node3D, meteor: Meteor) -> void:
	var target: Vector2 = meteor._target_pos
	var streak: MeshInstance3D = proxy.get_node("Streak")
	var ring: MeshInstance3D = proxy.get_node("ImpactRing")
	if meteor._impacted:
		# Impact flash phase: the streak dies, the shockwave ring expands to
		# exactly the sim's damage radius over the flash window.
		streak.visible = false
		ring.visible = true
		var t: float = clampf(meteor._impact_elapsed / Meteor.IMPACT_FLASH_DURATION, 0.0, 1.0)
		var radius: float = meteor.impact_radius * WORLD_SCALE * (0.15 + 0.85 * t)
		ring.scale = Vector3(radius, 1.0, radius)
		proxy.position = Presentation3D.to_3d(target, 0.0)
	else:
		ring.visible = false
		streak.visible = true
		# The 2D fall runs downward onto the target; in 3D it drops from the
		# sky, with the streak leaning along the fall direction.
		var height: float = maxf(0.0, target.y - meteor.global_position.y) * WORLD_SCALE
		proxy.position = Presentation3D.to_3d(Vector2(target.x, target.y), maxf(height, 0.02))
		streak.rotation_degrees.x = -20.0  # slight lean, reads as a dive
	# Fog honesty: no meteor the player cannot see (same rule as tracers).
	proxy.visible = _grid.is_visible_to(GameManager.Team.PLAYER, target)


func _acquire_meteor_proxy() -> Node3D:
	while not _meteor_pool.is_empty():
		var reused: Node3D = _meteor_pool.pop_back()
		if is_instance_valid(reused):
			reused.visible = true
			return reused
	var proxy := Node3D.new()
	proxy.name = "MeteorProxy"
	var streak := MeshInstance3D.new()
	streak.name = "Streak"
	var bolt := BoxMesh.new()
	bolt.size = Vector3(0.06, 0.3, 0.06)
	streak.mesh = bolt
	streak.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	streak.set_material_override(ArtStyle3D.get_material(METEOR_COLOR, METEOR_COLOR, METEOR_STREAK_ENERGY))
	proxy.add_child(streak)
	var ring := FlatGeo3D.make_ring(1.0, IMPACT_COLOR, Presentation3D.GROUND_LIFT, 0.8)
	ring.name = "ImpactRing"
	ring.visible = false
	ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# The flat-geo material is vertex-colored/unshaded; a dedicated emissive
	# material puts the ring in the meteor brightness class.
	ring.set_material_override(ArtStyle3D.get_material(IMPACT_COLOR, IMPACT_COLOR, IMPACT_RING_ENERGY, 0.85))
	proxy.add_child(ring)
	add_child(proxy)
	return proxy


func _release_meteor_proxy(proxy: Node3D) -> void:
	proxy.visible = false
	_meteor_pool.append(proxy)


# ─── Burning ground ───

func _reconcile_burn_patches() -> void:
	var seen := {}
	if not _underground_view:
		for node in get_tree().get_nodes_in_group("burning_grounds"):
			var patch := node as BurningGround
			if patch == null:
				continue
			seen[patch.get_instance_id()] = true
			var decal: Node3D = _burn_decals.get(patch.get_instance_id())
			if decal == null:
				decal = _acquire_burn_decal()
				_burn_decals[patch.get_instance_id()] = decal
			_sync_burn_decal(decal, patch)
	for id in _burn_decals.keys():
		if not seen.has(id):
			_release_burn_decal(_burn_decals[id])
			_burn_decals.erase(id)


func _sync_burn_decal(decal: Node3D, patch: BurningGround) -> void:
	decal.position = Presentation3D.to_3d(patch.global_position, 0.0)
	var radius: float = patch.radius * WORLD_SCALE
	var life_left: float = clampf(1.0 - patch._elapsed / maxf(patch.duration, 0.01), 0.0, 1.0)
	var pulse: float = 0.75 + 0.25 * sin(patch._flicker * 9.0)
	var ring: MeshInstance3D = decal.get_node("Ring")
	var scorch: MeshInstance3D = decal.get_node("Scorch")
	ring.scale = Vector3(radius, 1.0, radius)
	scorch.scale = Vector3(radius, 1.0, radius)
	var ring_mat := ring.get_material_override() as StandardMaterial3D
	ring_mat.emission_energy_multiplier = BURN_RING_ENERGY * pulse * maxf(life_left, 0.15)
	var scorch_mat := scorch.get_material_override() as StandardMaterial3D
	scorch_mat.albedo_color.a = SCORCH_COLOR.a * life_left
	# The sim already fog-gates the 2D patch's visibility; mirror it.
	decal.visible = patch.visible


func _acquire_burn_decal() -> Node3D:
	while not _burn_pool.is_empty():
		var reused: Node3D = _burn_pool.pop_back()
		if is_instance_valid(reused):
			reused.visible = true
			return reused
	var decal := Node3D.new()
	decal.name = "BurnDecal"
	var scorch := FlatGeo3D.make_disc(1.0, SCORCH_COLOR, Presentation3D.GROUND_LIFT)
	scorch.name = "Scorch"
	scorch.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# Per-decal materials: lifetime fade/pulse is per patch.
	var scorch_mat := ArtStyle3D.get_material(SCORCH_COLOR, Color(0, 0, 0), 0.0, SCORCH_COLOR.a).duplicate()
	scorch.set_material_override(scorch_mat)
	decal.add_child(scorch)
	var ring := FlatGeo3D.make_ring(1.0, BURN_RING_COLOR, Presentation3D.GROUND_LIFT + 0.002, 0.85)
	ring.name = "Ring"
	ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	ring.set_material_override(ArtStyle3D.get_material(BURN_RING_COLOR, BURN_RING_COLOR, BURN_RING_ENERGY).duplicate())
	decal.add_child(ring)
	add_child(decal)
	return decal


func _release_burn_decal(decal: Node3D) -> void:
	decal.visible = false
	_burn_pool.append(decal)


# ─── Lava-rise warning shimmer ───

func _build_lava_shimmer() -> void:
	_lava_shimmer_mat = StandardMaterial3D.new()
	_lava_shimmer_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_lava_shimmer_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_lava_shimmer_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	_lava_shimmer_mat.vertex_color_use_as_albedo = true
	_lava_shimmer_mat.albedo_color = LAVA_SHIMMER_COLOR
	_lava_shimmer_mat.emission_enabled = true
	_lava_shimmer_mat.emission = Color(1.0, 0.45, 0.08)
	_lava_shimmer_mat.emission_energy_multiplier = LAVA_SHIMMER_MIN_ENERGY
	_lava_shimmer_mesh = MultiMesh.new()
	_lava_shimmer_mesh.transform_format = MultiMesh.TRANSFORM_3D
	_lava_shimmer_mesh.use_colors = true
	_lava_shimmer_mesh.mesh = _cell_quad_mesh()
	_lava_shimmer = MultiMeshInstance3D.new()
	_lava_shimmer.name = "LavaShimmer"
	_lava_shimmer.multimesh = _lava_shimmer_mesh
	_lava_shimmer.set_material_override(_lava_shimmer_mat)
	_lava_shimmer.visible = false
	add_child(_lava_shimmer)


## Flat 1x1 quad in the XZ plane; instance transforms scale it to a cell.
static var _cell_quad: ArrayMesh


static func _cell_quad_mesh() -> ArrayMesh:
	if _cell_quad != null:
		return _cell_quad
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for v in [Vector3(-0.5, 0, -0.5), Vector3(0.5, 0, -0.5), Vector3(0.5, 0, 0.5),
			Vector3(-0.5, 0, -0.5), Vector3(0.5, 0, 0.5), Vector3(-0.5, 0, 0.5)]:
		st.set_color(Color.WHITE)
		st.add_vertex(v)
	_cell_quad = st.commit()
	return _cell_quad


func _update_lava_shimmer(delta: float) -> void:
	var warning: bool = _grid.is_lava_warning() and _underground_view
	if not warning:
		if _lava_shimmer.visible:
			_lava_shimmer.visible = false
			_lava_shimmer_mesh.instance_count = 0
		return
	_lava_rebuild_accum += delta
	if not _lava_shimmer.visible or _lava_rebuild_accum >= LAVA_REBUILD_INTERVAL:
		_lava_rebuild_accum = 0.0
		_rebuild_lava_shimmer()
	# The shimmer pulse is the decorative layer — Potato holds a static glow.
	if ArtStyle3D.detail_enabled():
		_shimmer_time += delta
		var pulse: float = 0.5 + 0.5 * sin(_shimmer_time * TAU / LAVA_SHIMMER_PERIOD)
		_lava_shimmer_mat.emission_energy_multiplier = lerpf(LAVA_SHIMMER_MIN_ENERGY, LAVA_SHIMMER_MAX_ENERGY, pulse)


## One flat quad per cell the current wave profile will flood and the player
## can currently see (fog honesty, same as the terrain glow pass).
func _rebuild_lava_shimmer() -> void:
	var events: GridEvents = _grid._events
	var cell_size: float = GridWorld.CELL_SIZE * WORLD_SCALE
	var xforms: Array[Transform3D] = []
	var colors: Array[Color] = []
	for x in range(GridWorld.X_MIN, GridWorld.X_MAX + 1):
		var top: int = events._lava_top_at_x(x)
		for y in range(top, GridWorld.Y_MAX + 1):
			var pos := Vector2i(x, y)
			if _grid.fog_state_at(GameManager.Team.PLAYER, pos) != 2:
				continue
			var cell: GridWorld.Cell = _grid.get_cell(pos)
			if cell == null or cell.type == GridWorld.CellType.EMPTY or cell.is_wall:
				continue
			var center: Vector2 = _grid.grid_to_world(pos, true)
			var origin := Vector3(center.x * WORLD_SCALE, Presentation3D.GROUND_LIFT, center.y * WORLD_SCALE)
			xforms.append(Transform3D(Basis.from_scale(Vector3(cell_size, 1.0, cell_size)), origin))
			colors.append(Color.WHITE)
	_lava_shimmer_mesh.instance_count = xforms.size()
	for i in range(xforms.size()):
		_lava_shimmer_mesh.set_instance_transform(i, xforms[i])
		_lava_shimmer_mesh.set_instance_color(i, colors[i])
	_lava_shimmer.visible = not xforms.is_empty()


# ─── Cave-in warning zone ───

func _build_cavein_zone() -> void:
	_cavein_zone_mat = StandardMaterial3D.new()
	_cavein_zone_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_cavein_zone_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_cavein_zone_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	_cavein_zone_mat.albedo_color = CAVEIN_SHADOW_COLOR
	_cavein_zone = Node3D.new()
	_cavein_zone.name = "CaveInWarning"
	_cavein_zone.visible = false
	var cell_size: float = GridWorld.CELL_SIZE * WORLD_SCALE
	for dy in range(-1, 2):
		for dx in range(-1, 2):
			var quad := MeshInstance3D.new()
			quad.name = "Shadow_%d_%d" % [dx, dy]
			quad.mesh = _cell_quad_mesh()
			quad.scale = Vector3(cell_size, 1.0, cell_size)
			quad.position = Vector3(dx * cell_size, Presentation3D.GROUND_LIFT, dy * cell_size)
			quad.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			quad.set_material_override(_cavein_zone_mat)
			_cavein_zone.add_child(quad)
	# Dust trickle over the zone (decorative — skipped on Potato).
	_cavein_dust = GPUParticles3D.new()
	_cavein_dust.name = "DustTrickle"
	_cavein_dust.amount = CAVEIN_DUST_AMOUNT
	_cavein_dust.lifetime = 1.2
	_cavein_dust.emitting = false
	var quad_mesh := QuadMesh.new()
	quad_mesh.size = Vector2(0.05, 0.05)
	var dust_mat := StandardMaterial3D.new()
	dust_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	dust_mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	dust_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	dust_mat.albedo_color = Color(0.5, 0.44, 0.36, 0.7)
	quad_mesh.material = dust_mat
	_cavein_dust.draw_pass_1 = quad_mesh
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pm.emission_box_extents = Vector3(cell_size, 0.6, cell_size)
	pm.direction = Vector3(0.0, -1.0, 0.0)
	pm.spread = 12.0
	pm.gravity = Vector3(0.0, -0.5, 0.0)
	pm.initial_velocity_min = 0.15
	pm.initial_velocity_max = 0.4
	pm.scale_min = 0.4
	pm.scale_max = 1.0
	_cavein_dust.process_material = pm
	_cavein_zone.add_child(_cavein_dust)
	add_child(_cavein_zone)


func _on_cave_in_warning(seconds: float, center: Vector2i) -> void:
	_cavein_warning_left = seconds
	var ground: Vector2 = _grid.grid_to_world(center) * WORLD_SCALE
	_cavein_zone.position = Vector3(ground.x, 0.0, ground.y)


func _on_cave_in_occurred(_center: Vector2i) -> void:
	_cavein_warning_left = 0.0
	_cavein_zone.visible = false
	_cavein_dust.emitting = false


func _update_cavein_zone(delta: float) -> void:
	if _cavein_warning_left <= 0.0:
		if _cavein_zone.visible:
			_cavein_zone.visible = false
			_cavein_dust.emitting = false
		return
	_cavein_warning_left -= delta
	var show: bool = _underground_view
	_cavein_zone.visible = show
	# The dust trickle is decoration; the shadow decal is the telegraph.
	_cavein_dust.emitting = show and ArtStyle3D.detail_enabled()
	# The darkening pulses gently as the drop nears (alpha on the shared mat).
	var urgency: float = 1.0 - clampf(_cavein_warning_left / Constants.WEATHER_ALERT_CAVEIN_WARNING, 0.0, 1.0)
	_cavein_zone_mat.albedo_color.a = CAVEIN_SHADOW_COLOR.a * (0.5 + 0.5 * urgency)
