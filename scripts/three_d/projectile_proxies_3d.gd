## 3D rework Phase 1 (roadmap/3d-rework/phase-1-selection-and-combat-feedback--k3.md §3).
##
## Mirrors the live 2D projectiles (scripts/units/projectile.gd, hidden with
## the rest of the sim's canvas layers) as glowing 3D tracers: a thin bolt for
## arrows, a small emissive orb for wizard fireballs and tower magic missiles,
## a bigger flickering orb for dragon breath. Same reconcile pattern as
## EntityProxies3D, but per frame instead of on the 0.2s interval — an arrow
## lives ~0.5s, so an interval reconcile would miss a third of its flight.
## Meshes come from small pools (projectiles churn several per second in a
## fight), and tracers honor fog: a shot the player cannot see stays hidden.
extends Node3D
class_name ProjectileProxies3D

const PROJECTILE_SCRIPT: GDScript = preload("res://scripts/units/projectile.gd")

const ARROW_HEIGHT: float = 0.3
const ORB_HEIGHT: float = 0.35
const FLAME_HEIGHT: float = 0.55
const MAX_TRACERS: int = 64

enum _Kind { ARROW, ORB, FLAME }

var _grid: GridWorld
var _underground_view := false
## Cached /root/Main/Projectiles container (resolved once; the shell-mounted
## sim lives for the whole match). Re-resolved if it ever goes away.
var _container: Node = null
var _active: Dictionary = {}  # projectile instance id -> MeshInstance3D
var _pending_release: Array = []  # reused buffer; no per-frame allocs
var _pools: Dictionary = {
	_Kind.ARROW: [],
	_Kind.ORB: [],
	_Kind.FLAME: [],
}


func setup(grid: GridWorld) -> void:
	_grid = grid


func set_underground_view(underground: bool) -> void:
	_underground_view = underground


func _process(_delta: float) -> void:
	if _container == null or not is_instance_valid(_container):
		_container = get_node_or_null("/root/Main/Projectiles")
	var seen := {}
	if _container != null and not _underground_view:
		for node in _container.get_children():
			# Burning-ground patches share the container; only real projectiles
			# (identified by their script) get tracers.
			if node.get_script() != PROJECTILE_SCRIPT:
				continue
			seen[node.get_instance_id()] = true
			var tracer: MeshInstance3D = _active.get(node.get_instance_id())
			if tracer == null:
				if _active.size() >= MAX_TRACERS:
					continue
				tracer = _acquire(_kind_of(node))
				_active[node.get_instance_id()] = tracer
			_sync_tracer(tracer, node)
	# Release tracers whose projectile died (or while the underground view is
	# up — surface combat is not visible from the mine). Collected first:
	# erasing during Dictionary iteration is unsafe (ordered-hash reorder).
	for id in _active:
		if not seen.has(id):
			_pending_release.append(id)
	for id in _pending_release:
		_release(_active[id])
		_active.erase(id)
	_pending_release.clear()


func _kind_of(proj: Node2D) -> int:
	if proj.get("is_dragon_flame") == true:
		return _Kind.FLAME
	if proj.get("is_fireball") == true:
		return _Kind.ORB
	# Tinted arrows (Arcane tower magic missiles) read as colored orbs.
	if proj.get("tint") != Color.WHITE:
		return _Kind.ORB
	return _Kind.ARROW


func _acquire(kind: int) -> MeshInstance3D:
	var pool: Array = _pools[kind]
	if not pool.is_empty():
		var reused: MeshInstance3D = pool.pop_back()
		reused.visible = true
		return reused
	var tracer := _build_tracer(kind)
	add_child(tracer)
	return tracer


func _release(tracer: MeshInstance3D) -> void:
	tracer.visible = false
	_pools[int(tracer.get_meta("kind"))].append(tracer)


func _sync_tracer(tracer: MeshInstance3D, proj: Node2D) -> void:
	var kind := int(tracer.get_meta("kind"))
	var height := ARROW_HEIGHT
	if kind == _Kind.ORB:
		height = ORB_HEIGHT
	elif kind == _Kind.FLAME:
		height = FLAME_HEIGHT
	tracer.global_position = Presentation3D.to_3d(proj.global_position, height)
	# The 2D node look_at()s its target each frame; mirror that facing. The
	# bolt mesh is elongated along -Z so look_at aims it tip-first.
	var target: Vector2 = proj.get("target_position")
	var target3d := Presentation3D.to_3d(target, height)
	if not tracer.global_position.is_equal_approx(target3d):
		tracer.look_at(target3d, Vector3.UP)
	if kind == _Kind.FLAME:
		# Flicker like the 2D flame head.
		var s: float = 1.0 + 0.18 * sin(Time.get_ticks_msec() / 40.0 + float(proj.get_instance_id() % 100))
		tracer.scale = Vector3.ONE * s
	elif kind == _Kind.ORB:
		# Tint variants (Arcane missiles) recolor from a per-color cache; a
		# plain fireball resets a pooled orb back to the default material.
		# Change-guarded: set_material_override re-binds, so only swap when
		# the pooled tracer actually needs a different material.
		var tint: Color = proj.get("tint")
		var desired: Material = _tinted_orb_material(tint) if tint != Color.WHITE \
			else _tracer_material(_Kind.ORB, Color(1.0, 0.6, 0.2), 2.2)
		if tracer.get_material_override() != desired:
			tracer.set_material_override(desired)
	# Fog honesty: no tracers for combat the player cannot see.
	if _grid != null:
		tracer.visible = _grid.is_visible_to(GameManager.Team.PLAYER, proj.global_position)


func _build_tracer(kind: int) -> MeshInstance3D:
	var tracer := MeshInstance3D.new()
	tracer.name = "ProjectileTracer"
	tracer.set_meta("kind", kind)
	tracer.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	match kind:
		_Kind.ARROW:
			var bolt := BoxMesh.new()
			bolt.size = Vector3(0.025, 0.025, 0.18)
			tracer.mesh = bolt
			tracer.set_material_override(_tracer_material(kind, Color(0.85, 0.87, 0.9), 0.5))
		_Kind.ORB:
			var orb := SphereMesh.new()
			orb.radius = 0.07
			orb.height = 0.14
			orb.radial_segments = 8
			orb.rings = 4
			tracer.mesh = orb
			tracer.set_material_override(_tracer_material(kind, Color(1.0, 0.6, 0.2), 2.2))
		_:
			var flame := SphereMesh.new()
			flame.radius = 0.09
			flame.height = 0.18
			flame.radial_segments = 8
			flame.rings = 4
			tracer.mesh = flame
			tracer.set_material_override(_tracer_material(kind, Color(1.0, 0.45, 0.1), 2.6))
	return tracer


## Unshaded + emissive so tracers pop against any lighting and bloom picks
## them up on Fancy. Cached per kind; orb tint variants (Arcane missiles) get
## their own per-color cache slots so pooled tracers only swap materials.
## Nested kind -> color -> energy Dictionaries: the old "%d|%s|%f" format
## string rebuilt a key per call per tracer per frame even on cache hits.
static var _tracer_mats: Dictionary = {}


static func _tracer_material(kind: int, color: Color, energy: float) -> StandardMaterial3D:
	var by_kind: Dictionary = _tracer_mats.get(kind, {})
	var by_color: Dictionary = by_kind.get(color, {})
	var cached: Variant = by_color.get(energy)
	if cached != null:
		return cached
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = color
	ArtStyle3D.apply_emission(mat, color, energy)
	by_color[energy] = mat
	by_kind[color] = by_color
	_tracer_mats[kind] = by_kind
	return mat


static func _tinted_orb_material(tint: Color) -> StandardMaterial3D:
	return _tracer_material(_Kind.ORB, tint, 2.2)
