## Phase 2 unit models (roadmap/3d-conversion/phase-2-art-pass.md §2.2).
##
## Procedural flat-shaded low-poly rig for one 2D unit, built from
## ArtStyle3D primitives (≤60 per unit). Team-colored bodies with faction
## accent trims; every type reads by silhouette per the style guide:
## miner = pickaxe + glowing helmet lamp + backpack, swordsman = sword +
## shield, archer = bow arc + quiver, wizard = wide-brim pointed hat + staff,
## dragon = big body + two flapping wing planes + tail, pigeon = tiny body +
## flapping wings, engineer = backpack + wrench (no weapon), crawler = low
## long spiky body. Undead get a post-build material pass toward
## ArtStyle3D.UNDEAD_TINT.
##
## Pure presentation: `sync_animation` reads the live unit's state/timers
## and poses the rig; it never writes sim state. The rig faces -Z (Godot
## forward); yaw is derived from the sim's actual movement (or its attack
## target), falling back to the team march direction.

class_name UnitModel3D
extends Node3D

const TOPPLE_TIME: float = 0.5
const SINK_TIME: float = 0.6

const MOVE_STATES: Array[int] = [
	Unit.State.MOVE, Unit.State.CLIMB_UP, Unit.State.CLIMB_DOWN,
	Unit.State.ENTER_MINE, Unit.State.EXIT_MINE,
]

static var _flash_material: StandardMaterial3D = null

## Overall model height (feet at local y=0); the proxy uses it to lift the
## HP bar above the silhouette.
var model_height: float = 0.34

var _kind: StringName = &"swordsman"
var _flyer: bool = false

var _rig: Node3D    # yaw facing
var _body: Node3D   # death topple pivot + idle bob
var _body_base_y: float = 0.0

# Animation pivots (null when the silhouette has no such part).
var _arm_l: Node3D = null
var _arm_r: Node3D = null
var _leg_l: Node3D = null
var _leg_r: Node3D = null
var _tool: Node3D = null
var _wing_l: Node3D = null
var _wing_r: Node3D = null
var _tail: Node3D = null

var _meshes: Array[MeshInstance3D] = []
var _orig_materials: Dictionary = {}  # MeshInstance3D -> Material

var _idle_time: float = 0.0
var _walk_phase: float = 0.0
var _last_pos: Vector2 = Vector2.ZERO
var _last_dir: Vector2 = Vector2(1.0, 0.0)
var _has_last_pos: bool = false
var _target_yaw: float = -PI * 0.5

var _flashing: bool = false
var _dead: bool = false
var _dead_t: float = 0.0


static func create(u: Node2D) -> UnitModel3D:
	var m := UnitModel3D.new()
	var data: UnitData = u.data
	m._kind = _resolve_kind(data)
	m._flyer = data.flight_altitude > 0.0
	var team: int = int(u.get("team"))
	var body: Color = ArtStyle3D.team_color(team)
	var accent: Color = ArtStyle3D.faction_accent_color(team)
	m._target_yaw = -PI * 0.5 if team == GameManager.Team.PLAYER else PI * 0.5
	m._rig = Node3D.new()
	m.add_child(m._rig)
	m._body = Node3D.new()
	m._body.rotation.y = m._target_yaw
	m._rig.add_child(m._body)
	match m._kind:
		&"miner":
			m._build_miner(body, accent)
		&"archer":
			m._build_archer(body, accent)
		&"wizard":
			m._build_wizard(body, accent)
		&"dragon":
			m._build_dragon(body, accent)
		&"pigeon":
			m._build_pigeon(body, accent)
		&"engineer":
			m._build_engineer(body, accent)
		&"crawler":
			m._build_crawler(body, accent)
		_:
			m._build_swordsman(body, accent)
	m._collect_meshes()
	if data.is_undead:
		m._apply_undead_tint()
	return m


static func _resolve_kind(data: UnitData) -> StringName:
	if data.is_scout:
		return &"pigeon"
	if data.is_crawler:
		return &"crawler"
	if data.is_engineer:
		return &"engineer"
	if data.is_miner:
		return &"miner"
	var unit_id: String = data.unit_name.to_lower()
	if unit_id == "dragon" or data.flight_altitude > 0.0:
		return &"dragon"
	if unit_id == "archer":
		return &"archer"
	if unit_id == "wizard":
		return &"wizard"
	return &"swordsman"


# ---------- Primitive helpers (all flat-shaded via ArtStyle3D) ----------

func _box(parent: Node, size: Vector3, color: Color, pos := Vector3.ZERO) -> MeshInstance3D:
	var mi := ArtStyle3D.make_box(size, color, pos)
	parent.add_child(mi)
	return mi


func _cone(parent: Node, radius: float, height: float, color: Color, sides := 5, pos := Vector3.ZERO) -> MeshInstance3D:
	var mi := ArtStyle3D.make_cone(radius, height, color, sides, pos)
	parent.add_child(mi)
	return mi


func _cyl(parent: Node, radius: float, height: float, color: Color, sides := 6, pos := Vector3.ZERO) -> MeshInstance3D:
	var mi := ArtStyle3D.make_cylinder(radius, height, color, sides, pos)
	parent.add_child(mi)
	return mi


func _glow(parent: Node, size: Vector3, color: Color, energy: float, pos := Vector3.ZERO) -> MeshInstance3D:
	var mi := ArtStyle3D.make_box(size, color, pos)
	mi.set_material_override(ArtStyle3D.get_material(color, color, energy))
	parent.add_child(mi)
	return mi


## Shoulder/hip pivot with a limb hanging below it, so rotation.x swings it.
func _limb(parent: Node, pos: Vector3, size: Vector3, color: Color, len: float) -> Node3D:
	var pivot := Node3D.new()
	pivot.position = pos
	parent.add_child(pivot)
	_box(pivot, size, color, Vector3(0.0, -len * 0.5, 0.0))
	return pivot


# ---------- Humanoid base (miner/swordsman/archer/wizard/engineer) ----------

## Legs + torso + head; returns the torso-height center used for shoulders.
func _humanoid_base(body: Color, cloth: Color, skin: Color, height := 0.34) -> float:
	_leg_l = _limb(_body, Vector3(-0.035, 0.1, 0.0), Vector3(0.05, 0.1, 0.05), cloth, 0.1)
	_leg_r = _limb(_body, Vector3(0.035, 0.1, 0.0), Vector3(0.05, 0.1, 0.05), cloth, 0.1)
	_box(_body, Vector3(0.13, 0.14, 0.085), body, Vector3(0.0, 0.17, 0.0))
	_box(_body, Vector3(0.09, 0.085, 0.085), skin, Vector3(0.0, 0.275, 0.0))
	model_height = height
	return 0.215


func _build_miner(body: Color, accent: Color) -> void:
	var p: Color = ArtStyle3D.PALETTE["wood"]
	var steel: Color = ArtStyle3D.PALETTE["steel"]
	var shoulder := _humanoid_base(body, ArtStyle3D.PALETTE["cloth_dark"], ArtStyle3D.PALETTE["skin"])
	# Backpack + bedroll — the miner's read-behind silhouette.
	_box(_body, Vector3(0.1, 0.12, 0.05), p, Vector3(0.0, 0.18, 0.065))
	if ArtStyle3D.detail_enabled():
		_cyl(_body, 0.025, 0.11, accent, 5, Vector3(0.0, 0.255, 0.065)).rotation.z = PI * 0.5
	# Helmet + glowing lamp (the signature).
	_cone(_body, 0.075, 0.06, steel, 6, Vector3(0.0, 0.33, 0.0))
	_glow(_body, Vector3(0.03, 0.03, 0.02), ArtStyle3D.PALETTE["lamp_warm"], 2.2, Vector3(0.0, 0.315, -0.055))
	# Belt trim in the faction accent.
	_box(_body, Vector3(0.135, 0.02, 0.09), accent, Vector3(0.0, 0.115, 0.0))
	# Pickaxe in the right hand.
	_tool = Node3D.new()
	_tool.position = Vector3(0.085, shoulder, 0.0)
	_body.add_child(_tool)
	_cyl(_tool, 0.012, 0.2, p, 5, Vector3(0.0, -0.07, -0.03)).rotation.x = 0.5
	_box(_tool, Vector3(0.15, 0.03, 0.02), steel, Vector3(0.0, 0.025, -0.115))
	_arm_l = _limb(_body, Vector3(-0.075, shoulder, 0.0), Vector3(0.04, 0.1, 0.04), body, 0.09)
	_arm_r = _limb(_body, Vector3(0.075, shoulder, 0.0), Vector3(0.04, 0.1, 0.04), body, 0.09)


func _build_swordsman(body: Color, accent: Color) -> void:
	var steel: Color = ArtStyle3D.PALETTE["steel"]
	var shoulder := _humanoid_base(body, ArtStyle3D.PALETTE["cloth_dark"], ArtStyle3D.PALETTE["skin"], 0.36)
	model_height = 0.36
	_cone(_body, 0.08, 0.09, steel, 6, Vector3(0.0, 0.335, 0.0))
	# Small shield on the left arm (accent face).
	_box(_body, Vector3(0.02, 0.14, 0.11), accent, Vector3(-0.095, 0.18, -0.01))
	# Long sword blade in the right hand.
	_tool = Node3D.new()
	_tool.position = Vector3(0.085, shoulder, 0.0)
	_body.add_child(_tool)
	_box(_tool, Vector3(0.025, 0.26, 0.01), steel, Vector3(0.0, 0.14, -0.02))
	_box(_tool, Vector3(0.07, 0.02, 0.02), accent, Vector3(0.0, 0.02, -0.02))
	_arm_l = _limb(_body, Vector3(-0.075, shoulder, 0.0), Vector3(0.04, 0.1, 0.04), body, 0.09)
	_arm_r = _limb(_body, Vector3(0.075, shoulder, 0.0), Vector3(0.04, 0.1, 0.04), body, 0.09)


func _build_archer(body: Color, accent: Color) -> void:
	var p: Color = ArtStyle3D.PALETTE["wood"]
	var shoulder := _humanoid_base(body, ArtStyle3D.PALETTE["cloth"], ArtStyle3D.PALETTE["skin"], 0.35)
	model_height = 0.35
	# Hood instead of a helmet.
	_cone(_body, 0.08, 0.12, ArtStyle3D.PALETTE["cloth"], 5, Vector3(0.0, 0.34, 0.005))
	# Quiiver on the back with accent fletching.
	_cyl(_body, 0.028, 0.13, ArtStyle3D.PALETTE["cloth_dark"], 5, Vector3(-0.03, 0.2, 0.06)).rotation.x = -0.35
	if ArtStyle3D.detail_enabled():
		_box(_body, Vector3(0.02, 0.05, 0.02), accent, Vector3(-0.055, 0.265, 0.085))
	# Bow arc held vertically in the left hand.
	_tool = Node3D.new()
	_tool.position = Vector3(-0.085, shoulder, 0.0)
	_body.add_child(_tool)
	_cyl(_tool, 0.014, 0.26, p, 5, Vector3(-0.02, -0.04, -0.02))
	_arm_l = _limb(_body, Vector3(-0.075, shoulder, 0.0), Vector3(0.035, 0.1, 0.035), body, 0.09)
	_arm_r = _limb(_body, Vector3(0.075, shoulder, 0.0), Vector3(0.035, 0.1, 0.035), body, 0.09)


func _build_wizard(body: Color, accent: Color) -> void:
	var p: Color = ArtStyle3D.PALETTE["wood"]
	# Robe instead of legs.
	_cone(_body, 0.105, 0.26, body, 6, Vector3(0.0, 0.13, 0.0))
	_box(_body, Vector3(0.085, 0.08, 0.08), ArtStyle3D.PALETTE["skin"], Vector3(0.0, 0.28, 0.0))
	model_height = 0.38
	# Wide-brim pointed hat — the signature (brim in team color, cone accent).
	_cyl(_body, 0.14, 0.02, body, 8, Vector3(0.0, 0.325, 0.0))
	_cone(_body, 0.085, 0.19, accent, 6, Vector3(0.0, 0.425, 0.0))
	# Staff with a glowing arcane orb.
	_tool = Node3D.new()
	_tool.position = Vector3(0.095, 0.22, 0.0)
	_body.add_child(_tool)
	_cyl(_tool, 0.011, 0.34, p, 5, Vector3(0.0, 0.03, -0.01))
	_glow(_tool, Vector3(0.045, 0.045, 0.045), accent, 1.8, Vector3(0.0, 0.22, -0.01))
	_arm_l = _limb(_body, Vector3(-0.075, 0.225, 0.0), Vector3(0.04, 0.1, 0.04), body, 0.09)
	_arm_r = _limb(_body, Vector3(0.075, 0.225, 0.0), Vector3(0.04, 0.1, 0.04), body, 0.09)


func _build_engineer(body: Color, accent: Color) -> void:
	var p: Color = ArtStyle3D.PALETTE["wood"]
	var steel: Color = ArtStyle3D.PALETTE["steel"]
	var shoulder := _humanoid_base(body, ArtStyle3D.PALETTE["cloth"], ArtStyle3D.PALETTE["skin"], 0.34)
	model_height = 0.34
	# Hard hat.
	_cone(_body, 0.075, 0.055, ArtStyle3D.PALETTE["ore_bright"], 6, Vector3(0.0, 0.325, 0.0))
	# Oversized tool backpack — no weapon.
	_box(_body, Vector3(0.12, 0.15, 0.06), accent, Vector3(0.0, 0.185, 0.07))
	if ArtStyle3D.detail_enabled():
		_cyl(_body, 0.03, 0.12, p, 5, Vector3(0.0, 0.275, 0.07)).rotation.z = PI * 0.5
	# Wrench: handle + jaw.
	_tool = Node3D.new()
	_tool.position = Vector3(0.085, shoulder, 0.0)
	_body.add_child(_tool)
	_box(_tool, Vector3(0.025, 0.14, 0.015), steel, Vector3(0.0, -0.05, -0.02))
	_cyl(_tool, 0.028, 0.015, steel, 6, Vector3(0.0, 0.035, -0.02))
	_arm_l = _limb(_body, Vector3(-0.075, shoulder, 0.0), Vector3(0.04, 0.1, 0.04), body, 0.09)
	_arm_r = _limb(_body, Vector3(0.075, shoulder, 0.0), Vector3(0.04, 0.1, 0.04), body, 0.09)


# ---------- Non-humanoid silhouettes ----------

func _build_dragon(body: Color, accent: Color) -> void:
	var belly: Color = ArtStyle3D.PALETTE["cloth_dark"]
	# Big body along the facing axis (-Z forward).
	_box(_body, Vector3(0.26, 0.22, 0.48), body, Vector3(0.0, 0.36, 0.02))
	_box(_body, Vector3(0.2, 0.06, 0.4), belly, Vector3(0.0, 0.26, 0.0))
	# Neck + head + snout + horns.
	_box(_body, Vector3(0.12, 0.12, 0.16), body, Vector3(0.0, 0.5, -0.3))
	_box(_body, Vector3(0.09, 0.07, 0.12), body, Vector3(0.0, 0.47, -0.42))
	_glow(_body, Vector3(0.025, 0.02, 0.015), accent, 1.6, Vector3(-0.045, 0.51, -0.37))
	_glow(_body, Vector3(0.025, 0.02, 0.015), accent, 1.6, Vector3(0.045, 0.51, -0.37))
	_cone(_body, 0.02, 0.08, ArtStyle3D.PALETTE["steel"], 4, Vector3(-0.045, 0.585, -0.28)).rotation.x = -0.4
	_cone(_body, 0.02, 0.08, ArtStyle3D.PALETTE["steel"], 4, Vector3(0.045, 0.585, -0.28)).rotation.x = -0.4
	# Stubby legs.
	for sx in [-0.09, 0.09]:
		for sz in [-0.14, 0.16]:
			_box(_body, Vector3(0.07, 0.14, 0.08), body, Vector3(sx, 0.07, sz))
	# Two flapping wing planes (accent tips).
	_wing_l = Node3D.new()
	_wing_l.position = Vector3(0.12, 0.46, 0.05)
	_body.add_child(_wing_l)
	_box(_wing_l, Vector3(0.44, 0.015, 0.24), body, Vector3(0.24, 0.0, 0.03))
	if ArtStyle3D.detail_enabled():
		_box(_wing_l, Vector3(0.12, 0.017, 0.2), accent, Vector3(0.42, 0.0, 0.03))
	_wing_r = Node3D.new()
	_wing_r.position = Vector3(-0.12, 0.46, 0.05)
	_body.add_child(_wing_r)
	_box(_wing_r, Vector3(0.44, 0.015, 0.24), body, Vector3(-0.24, 0.0, 0.03))
	if ArtStyle3D.detail_enabled():
		_box(_wing_r, Vector3(0.12, 0.017, 0.2), accent, Vector3(-0.42, 0.0, 0.03))
	# Tail tapering behind.
	_tail = Node3D.new()
	_tail.position = Vector3(0.0, 0.34, 0.26)
	_body.add_child(_tail)
	var tail_mi := _cone(_tail, 0.06, 0.4, body, 5, Vector3(0.0, 0.0, 0.2))
	tail_mi.rotation.x = PI * 0.5
	model_height = 0.7


func _build_pigeon(body: Color, accent: Color) -> void:
	# Tiny body; the flapping wings carry the read.
	_box(_body, Vector3(0.055, 0.05, 0.09), body, Vector3(0.0, 0.07, 0.0))
	_box(_body, Vector3(0.035, 0.035, 0.035), body, Vector3(0.0, 0.11, -0.045))
	_cone(_body, 0.01, 0.025, ArtStyle3D.PALETTE["ore_bright"], 4, Vector3(0.0, 0.105, -0.075)).rotation.x = -PI * 0.5
	_box(_body, Vector3(0.04, 0.012, 0.05), accent, Vector3(0.0, 0.075, 0.055))
	_wing_l = Node3D.new()
	_wing_l.position = Vector3(0.03, 0.085, 0.0)
	_body.add_child(_wing_l)
	_box(_wing_l, Vector3(0.08, 0.008, 0.05), ArtStyle3D.PALETTE["cloth"], Vector3(0.045, 0.0, 0.0))
	_wing_r = Node3D.new()
	_wing_r.position = Vector3(-0.03, 0.085, 0.0)
	_body.add_child(_wing_r)
	_box(_wing_r, Vector3(0.08, 0.008, 0.05), ArtStyle3D.PALETTE["cloth"], Vector3(-0.045, 0.0, 0.0))
	model_height = 0.12


func _build_crawler(body: Color, accent: Color) -> void:
	var rock: Color = ArtStyle3D.PALETTE["rock_dark"]
	# Low, long body — the underground read.
	_box(_body, Vector3(0.16, 0.09, 0.4), rock, Vector3(0.0, 0.07, 0.0))
	_box(_body, Vector3(0.13, 0.07, 0.12), rock, Vector3(0.0, 0.06, -0.24))
	_glow(_body, Vector3(0.02, 0.015, 0.01), accent, 1.8, Vector3(-0.035, 0.07, -0.3))
	_glow(_body, Vector3(0.02, 0.015, 0.01), accent, 1.8, Vector3(0.035, 0.07, -0.3))
	# Dorsal spikes.
	for i in range(4):
		_cone(_body, 0.025, 0.08 - i * 0.012, body, 4, Vector3(0.0, 0.145, 0.1 - i * 0.1))
	# Side legs (skittering nubs).
	if ArtStyle3D.detail_enabled():
		for i in range(3):
			for sx in [-0.09, 0.09]:
				_box(_body, Vector3(0.05, 0.02, 0.03), rock, Vector3(sx, 0.03, 0.12 - i * 0.12))
	model_height = 0.16


# ---------- Material passes ----------

func _collect_meshes() -> void:
	for node in _body.find_children("*", "MeshInstance3D", true, false):
		var mi := node as MeshInstance3D
		_meshes.append(mi)
		_orig_materials[mi] = mi.get_material_override()


## Necromancy: pull every body material toward the sickly green tint
## (albedo lerp; emissive accents keep their glow).
func _apply_undead_tint() -> void:
	for mi in _meshes:
		var mat := _orig_materials[mi] as StandardMaterial3D
		if mat == null:
			continue
		var tinted: Color = mat.albedo_color.lerp(ArtStyle3D.UNDEAD_TINT, 0.55)
		var emission := Color(0, 0, 0)
		var energy := 0.0
		if mat.emission_enabled:
			emission = mat.emission.lerp(ArtStyle3D.UNDEAD_TINT, 0.55)
			energy = mat.emission_energy_multiplier
		var replacement := ArtStyle3D.get_material(tinted, emission, energy, mat.albedo_color.a)
		mi.set_material_override(replacement)
		_orig_materials[mi] = replacement


static func _get_flash_material() -> StandardMaterial3D:
	if _flash_material == null:
		_flash_material = ArtStyle3D.get_material(Color(1, 1, 1), Color(1, 1, 1), 1.6)
	return _flash_material


func _set_flashing(on: bool) -> void:
	_flashing = on
	for mi in _meshes:
		mi.set_material_override(_get_flash_material() if on else _orig_materials[mi])


# ---------- Animation driver ----------

## Per-frame pose sync, driven entirely by the live unit's state. `unit` is
## duck-typed (the real Unit in game, a fake in tests): it exposes _state,
## _attack_timer, _mine_timer, _mine_target_angle, _hit_flash_timer,
## _target_unit/_target_building/_target_position, global_position and
## get_flight_altitude().
func sync_animation(unit: Node2D, delta: float) -> void:
	delta = clampf(delta, 0.0, 0.1)
	if _dead:
		_advance_death(delta)
		return
	var state: int = int(unit.get("_state"))
	if state == Unit.State.DEAD:
		_dead = true
		_advance_death(delta)
		return
	# Hit flash: shared emissive white override while the sim's flash runs.
	var want_flash: bool = float(unit.get("_hit_flash_timer")) > 0.0
	if want_flash != _flashing:
		_set_flashing(want_flash)
	# Facing: actual movement wins; an attack target steers a stationary unit.
	var pos: Vector2 = unit.global_position
	var moved: float = pos.distance_to(_last_pos)
	if moved > 0.4:
		_last_dir = (pos - _last_pos) / moved
		_last_pos = pos
		_target_yaw = atan2(-_last_dir.x, -_last_dir.y)
	elif state == Unit.State.ATTACK:
		var aim := _attack_aim(unit, pos)
		if aim.length_squared() > 0.001:
			var n := aim.normalized()
			_target_yaw = atan2(-n.x, -n.y)
	_rig.rotation.y = lerp_angle(_rig.rotation.y, _target_yaw, minf(delta * 10.0, 1.0))
	_idle_time += delta
	# Wings: flap while airborne, glide-still on the ground.
	if _flyer:
		_animate_flight(unit, delta, state)
	if MOVE_STATES.has(state):
		_walk_phase += moved * 0.11
		_animate_move(state)
	elif state == Unit.State.ATTACK:
		_animate_attack(unit)
	elif state == Unit.State.MINE:
		_animate_mine(unit)
	else:
		_animate_idle()


func _attack_aim(unit: Node2D, pos: Vector2) -> Vector2:
	var t: Variant = unit.get("_target_unit")
	if t is Node2D and is_instance_valid(t) and t.global_position.distance_squared_to(pos) > 0.01:
		return t.global_position - pos
	var b: Variant = unit.get("_target_building")
	if b is Node2D and is_instance_valid(b) and b.global_position.distance_squared_to(pos) > 0.01:
		return b.global_position - pos
	var tp: Vector2 = unit.get("_target_position")
	if tp.length_squared() > 0.01:
		return tp - pos
	return Vector2.ZERO


func _animate_flight(unit: Node2D, _delta: float, state: int) -> void:
	var altitude: float = float(unit.call("get_flight_altitude"))
	if altitude > 0.0:
		# Airborne: wing flap + gentle body bob.
		if _wing_l != null:
			var flap := sin(_idle_time * 7.0) * 0.7
			_wing_l.rotation.z = flap
			_wing_r.rotation.z = -flap
		_body.position.y = _body_base_y + sin(_idle_time * 3.1) * 0.03
	else:
		if _wing_l != null:
			_wing_l.rotation.z = lerpf(_wing_l.rotation.z, 0.9, 0.1)
			_wing_r.rotation.z = lerpf(_wing_r.rotation.z, -0.9, 0.1)
		_body.position.y = _body_base_y
	if _tail != null:
		_tail.rotation.y = sin(_idle_time * 3.0) * 0.2
	if state == Unit.State.MOVE:
		_walk_phase += 0.05


func _swing(pivot: Node3D, phase: float, amp: float) -> void:
	if pivot != null:
		pivot.rotation.x = sin(phase) * amp


func _animate_move(_state: int) -> void:
	_swing(_arm_l, _walk_phase, 0.55)
	_swing(_arm_r, _walk_phase + PI, 0.55)
	_swing(_leg_l, _walk_phase + PI, 0.5)
	_swing(_leg_r, _walk_phase, 0.5)
	if _tool != null:
		_tool.rotation.x = sin(_walk_phase) * 0.15
	if _kind == &"crawler":
		_body.rotation.z = sin(_walk_phase) * 0.07
	else:
		_body.position.y = _body_base_y + absf(sin(_walk_phase)) * 0.012


func _animate_attack(unit: Node2D) -> void:
	var cooldown := maxf(float(unit.data.attack_cooldown), 0.05)
	# _attack_timer counts down to 0 and resets to cooldown; phase 0 = just
	# struck, phase 1 = next strike about to land.
	var phase := 1.0 - clampf(float(unit.get("_attack_timer")) / cooldown, 0.0, 1.0)
	var strike := sin(phase * PI)
	if _tool != null:
		# Chop/thrust forward (-Z is the facing axis).
		_tool.rotation.x = -strike * (1.2 if _kind == &"wizard" else 0.9)
	if _arm_r != null:
		_arm_r.rotation.x = -strike * 0.8
	if _arm_l != null:
		# Archer "draw": the bow arm pulls back as the strike lands.
		_arm_l.rotation.x = strike * 0.4
	if _kind == &"crawler":
		_body.position.z = -strike * 0.05
	else:
		# Body lunge keyed on the same timer.
		_body.position.z = -strike * 0.03
	_body.position.y = _body_base_y


func _animate_mine(unit: Node2D) -> void:
	var period := 1.0 / maxf(float(unit.data.mining_swings_per_sec), 0.1)
	var phase := 1.0 - clampf(float(unit.get("_mine_timer")) / period, 0.0, 1.0)
	var swing := sin(phase * PI)
	# Aim the rig at the cell being dug.
	var angle: float = float(unit.get("_mine_target_angle"))
	_target_yaw = atan2(-cos(angle), -sin(angle))
	_rig.rotation.y = _target_yaw
	if _tool != null:
		_tool.rotation.x = -1.3 * swing
	if _arm_r != null:
		_arm_r.rotation.x = -swing * 0.7


func _animate_idle() -> void:
	var breathe := sin(_idle_time * 2.2) * 0.008
	_body.position.y = _body_base_y + breathe
	_body.position.z = lerpf(_body.position.z, 0.0, 0.2)
	_body.rotation.z = lerpf(_body.rotation.z, 0.0, 0.2)
	_swing(_arm_l, _idle_time * 2.2, 0.06)
	_swing(_arm_r, _idle_time * 2.2 + PI, 0.06)
	_swing(_leg_l, 0.0, 0.0)
	_swing(_leg_r, 0.0, 0.0)
	if _tool != null:
		_tool.rotation.x = lerpf(_tool.rotation.x, 0.0, 0.1)


func _advance_death(delta: float) -> void:
	_dead_t += delta
	var k := minf(_dead_t / TOPPLE_TIME, 1.0)
	_body.rotation.x = -PI * 0.5 * k
	if _dead_t > TOPPLE_TIME:
		_body.position.y = _body_base_y - 0.06 * minf((_dead_t - TOPPLE_TIME) / SINK_TIME, 1.0)
