## 3D rework Phase 5 (roadmap/3d-rework/phase-5-effects-and-telegraphs--k3.md §3).
##
## Attack telegraph: when the player explicitly orders fighters to attack a
## target (right-click attack, attack-move), a short-lived red dashed arc
## runs from the attacker group's centroid to the target point on the
## terrain. Pooled unshaded quads (dashes), so a burst of orders costs no
## allocations; the emissive energy sits at the top of the phase-5
## brightness hierarchy (telegraphs outshine tracers, lava, and embers).
## Spawned only when the 3D shell runs the scene; the 2D path has its order
## markers and needs no line. Telegraphs are gameplay, not decoration — they
## render on every quality preset.
extends Node3D
class_name Telegraph3D

const LIFETIME: float = 0.9
const DASH_COUNT: int = 7
const DASH_LENGTH: float = 0.18
const DASH_WIDTH: float = 0.05
const DASH_HEIGHT: float = 0.012
## Slight arc lift mid-flight so the line reads over sculpted ground.
const ARC_HEIGHT: float = 0.12
const MAX_ACTIVE: int = 12
const TELEGRAPH_COLOR := Color(1.0, 0.32, 0.18)
const TELEGRAPH_ENERGY: float = 3.2

static var _pool: Array[Telegraph3D] = []
static var _active: Array[Telegraph3D] = []
static var _dash_mesh: BoxMesh

var _timer: float = 0.0
var _mat: StandardMaterial3D
var _dashes: Array[MeshInstance3D] = []


## Spawns a telegraph arc under the shell's Effects3D container. Returns
## false when the 3D shell is not running the scene — callers skip silently
## (the 2D order marker is the fallback feedback there).
static func spawn_attack(tree: SceneTree, from2d: Vector2, to2d: Vector2) -> bool:
	var parent := Presentation3D.effects_parent(tree)
	if parent == null:
		return false
	var telegraph := _acquire(parent)
	if telegraph == null:
		return false
	telegraph._launch(Presentation3D.to_3d(from2d, 0.0), Presentation3D.to_3d(to2d, 0.0))
	return true


static func _acquire(parent: Node3D) -> Telegraph3D:
	# Prune entries a freed shell took down (the statics outlive the scene).
	for i in range(_active.size() - 1, -1, -1):
		if not is_instance_valid(_active[i]) or _active[i].get_parent() != parent:
			_active.remove_at(i)
	while not _pool.is_empty():
		var reused: Telegraph3D = _pool.pop_back()
		if is_instance_valid(reused) and reused.get_parent() == parent:
			return reused
	# Pool empty: steal the oldest active telegraph once the cap is hit.
	if _active.size() >= MAX_ACTIVE:
		if _active.is_empty():
			return null
		return _active.pop_front()
	var telegraph := Telegraph3D.new()
	telegraph.name = "AttackTelegraph"
	telegraph._build()
	parent.add_child(telegraph)
	return telegraph


func _build() -> void:
	if _dash_mesh == null:
		_dash_mesh = BoxMesh.new()
		_dash_mesh.size = Vector3(DASH_LENGTH, DASH_HEIGHT, DASH_WIDTH)
	# Per-telegraph material (alpha fades over the lifetime); energy is fixed
	# at the telegraph tier of the emission hierarchy.
	_mat = StandardMaterial3D.new()
	_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_mat.albedo_color = TELEGRAPH_COLOR
	ArtStyle3D.apply_emission(_mat, TELEGRAPH_COLOR, TELEGRAPH_ENERGY)
	for i in range(DASH_COUNT):
		var dash := MeshInstance3D.new()
		dash.name = "Dash%d" % i
		dash.mesh = _dash_mesh
		dash.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		dash.set_material_override(_mat)
		add_child(dash)
		_dashes.append(dash)


func _launch(from3d: Vector3, to3d: Vector3) -> void:
	_timer = LIFETIME
	_mat.albedo_color.a = 1.0
	visible = true
	var span: Vector3 = to3d - from3d
	var flat := Vector3(span.x, 0.0, span.z)
	if flat.length_squared() < 0.0004:
		# Attacker on top of the target: no line to draw.
		_timer = 0.0
		visible = false
		return
	var yaw: float = atan2(-flat.z, flat.x)
	for i in range(DASH_COUNT):
		var t: float = (float(i) + 0.75) / (float(DASH_COUNT) + 0.5)
		var pos: Vector3 = from3d + span * t
		# R3: each dash rides the dune surface it arcs over (flat underground).
		pos.y = Presentation3D.ground_height(get_tree(), pos.x, pos.z) \
			+ Presentation3D.GROUND_LIFT + sin(t * PI) * ARC_HEIGHT
		_dashes[i].position = pos
		_dashes[i].rotation = Vector3(0.0, yaw, 0.0)
	if not _active.has(self):
		_active.append(self)


func _process(delta: float) -> void:
	if _timer <= 0.0:
		return
	_timer -= delta
	if _timer <= 0.0:
		_recycle()
		return
	# Fast early fade: the line flashes bright then dissolves.
	var t: float = clampf(_timer / LIFETIME, 0.0, 1.0)
	_mat.albedo_color.a = t * t


func _recycle() -> void:
	visible = false
	_active.erase(self)
	_pool.append(self)
