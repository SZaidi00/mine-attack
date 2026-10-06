## Phase 2 structure models (roadmap/3d-conversion/phase-2-art-pass.md §2.3).
##
## Procedural flat-shaded low-poly stand-ins for the 2D structures, composed
## from ArtStyle3D primitives: the building as a multi-tier faction-trimmed
## keep (accent colors re-tint when the enemy faction is identified), squat
## towers and chunky walls with damage states (tilt + darkening + rubble),
## lanterns as dynamic-light heroes (tier-scaled OmniLight3D), a modeled
## mine-entry headframe, rail-and-rung ladders, and a low trap plate. The
## Phase 1 contract is unchanged: fog mirroring via the grid's fog map,
## construction alpha from is_built(), layer (Tab) visibility, and death via
## the destroyed signal / tree_exiting. The proxy never writes to the sim.
extends Node3D
class_name StructureProxy3D

const WORLD_SCALE: float = 0.01
const CELL: float = 32.0 * WORLD_SCALE
const CONSTRUCTION_ALPHA: float = 0.55
const REMEMBERED_COLOR := Color(0.3, 0.3, 0.32)

enum _Kind { GENERIC, BUILDING, TOWER, LANTERN, WALL, TRAP, MINE_ENTRY, LADDER }

const _DAMAGE_TILTS: Array[float] = [0.0, 0.07, 0.17]
const _DAMAGE_DARKEN: Array[float] = [0.0, 0.25, 0.45]

var entity: Node2D
var dead := false
var source_id: int = 0

var _kind: int = _Kind.GENERIC
var _underground_structure := false
var _shows_in_both_layers := false
var _grid: GridWorld
var _cell: Vector2i
var _enemy := false
var _team: int = GameManager.Team.PLAYER

# Parts that follow construction alpha, fog-memory lerp and damage darkening
# (one per-proxy material each, tinted in refresh()).
var _body_meshes: Array[MeshInstance3D] = []
var _body_mats: Array[StandardMaterial3D] = []
var _body_colors: Array[Color] = []
# Faction-accent parts (building trims/ridge, re-tinted on identification).
var _accent_meshes: Array[MeshInstance3D] = []
var _accent_mats: Array[StandardMaterial3D] = []
var _faction_connected := false

var _damage_darken := 0.0
var _damage_pivot: Node3D
var _rubble: Node3D
var _tilt_sign := 1.0
var _last_remembered := false
var _last_built := true

var _lantern_light: OmniLight3D
var _lantern_head: MeshInstance3D
var _lantern_underground := false


static func create(s: Node2D, grid: GridWorld) -> StructureProxy3D:
	var p := StructureProxy3D.new()
	p.entity = s

	var team_v: Variant = s.get("team")
	p._team = GameManager.Team.ENEMY if team_v == GameManager.Team.ENEMY else GameManager.Team.PLAYER
	p._enemy = p._team == GameManager.Team.ENEMY

	# Local position: the proxy is not inside the tree yet, and the parent
	# container sits at the origin, so local == global here.
	var pos: Vector2 = s.global_position
	p.position = Vector3(pos.x * WORLD_SCALE, 0.0, pos.y * WORLD_SCALE)

	# Fog mirror inputs: the sim only flips .visible on enemy buildings/traps,
	# so refresh() checks the fog map itself for every enemy structure.
	p._grid = grid
	p._cell = grid.world_to_grid(pos)

	if s.is_in_group("buildings"):
		p._kind = _Kind.BUILDING
		p._build_keep()
		p._connect_faction_reveal()
	elif s.is_in_group("towers"):
		p._kind = _Kind.TOWER
		p._build_tower()
	elif s.is_in_group("lanterns"):
		p._kind = _Kind.LANTERN
		p._build_lantern(s)
	elif s.is_in_group("walls"):
		p._kind = _Kind.WALL
		p._underground_structure = _is_underground_cell(s, grid)
		p._build_wall()
	elif s.is_in_group("traps"):
		p._kind = _Kind.TRAP
		p._underground_structure = grid.world_to_grid(s.global_position).y >= 1
		p._build_trap()
	elif s.is_in_group("mine_entries"):
		p._kind = _Kind.MINE_ENTRY
		p._shows_in_both_layers = true
		p._build_mine_entry()
	elif s.is_in_group("ladders"):
		p._kind = _Kind.LADDER
		p._shows_in_both_layers = true
		p._build_ladder(s)
	else:
		p._kind = _Kind.GENERIC
		p._add_body(ArtStyle3D.make_box(Vector3(CELL, 0.5, CELL), Color(0.5, 0.5, 0.55)), Color(0.5, 0.5, 0.55))

	if p._kind == _Kind.TOWER or p._kind == _Kind.WALL:
		p._tilt_sign = -1.0 if p._enemy else 1.0
		if s.has_signal("hp_changed"):
			s.connect("hp_changed", p._on_hp_changed)
		p._read_damage()
	if p._kind == _Kind.LANTERN and s.has_signal("upgraded"):
		s.connect("upgraded", p._on_lantern_upgraded)

	if s.has_signal("destroyed"):
		s.connect("destroyed", p._on_destroyed)
	s.tree_exiting.connect(p._on_destroyed)
	return p


static func _is_underground_cell(s: Node2D, grid: GridWorld) -> bool:
	if s.has_method("get_cell"):
		return (s.call("get_cell") as Vector2i).y >= 1
	return false


# ─── Part helpers ───


## Register a mesh whose material is tinted per refresh() (construction
## alpha, fog-memory lerp, damage darkening).
func _add_body(part: MeshInstance3D, base: Color, parent: Node3D = null) -> MeshInstance3D:
	var mat := StandardMaterial3D.new()
	mat.roughness = 1.0
	mat.albedo_color = base
	part.name = "Body"
	part.set_material_override(mat)
	_body_meshes.append(part)
	_body_mats.append(mat)
	_body_colors.append(base)
	if parent == null:
		add_child(part)
	else:
		parent.add_child(part)
	return part


## Register a faction-accent part (re-tinted when the enemy faction is
## identified; neutral "???" grey until then).
func _add_accent(part: MeshInstance3D, parent: Node3D = null) -> MeshInstance3D:
	var mat := StandardMaterial3D.new()
	mat.roughness = 1.0
	mat.albedo_color = ArtStyle3D.faction_accent_color(_team, false)
	part.name = "Accent"
	part.set_material_override(mat)
	_accent_meshes.append(part)
	_accent_mats.append(mat)
	if parent == null:
		add_child(part)
	else:
		parent.add_child(part)
	return part


func _tint_accents() -> void:
	var accent := ArtStyle3D.faction_accent_color(_team, false)
	for mat in _accent_mats:
		mat.albedo_color = accent


func _connect_faction_reveal() -> void:
	if not FactionManager.faction_identified.is_connected(_on_faction_identified):
		FactionManager.faction_identified.connect(_on_faction_identified)
	_faction_connected = true


func _on_faction_identified(team: GameManager.Team) -> void:
	if team == _team:
		_tint_accents()


# ─── Building: multi-tier faction keep ───


func _build_keep() -> void:
	var stone: Color = ArtStyle3D.PALETTE.rock
	var wood: Color = ArtStyle3D.PALETTE.wood
	var wood_dark: Color = ArtStyle3D.PALETTE.wood_dark
	var team := ArtStyle3D.team_color(_team)
	var w := CELL * 6.0
	var d := CELL * 5.0

	# Stone base tier.
	_add_body(ArtStyle3D.make_box(Vector3(w, 0.7, d), stone, Vector3(0.0, 0.35, 0.0)), stone)
	# Faction trim ring where the stone meets the timber.
	_add_accent(ArtStyle3D.make_box(Vector3(w + 0.04, 0.07, d + 0.04), Color.WHITE, Vector3(0.0, 0.72, 0.0)))
	# Timber upper tier, set toward the back of the footprint.
	var upper_h := 0.55
	var upper_pos := Vector3(-w * 0.08, 0.7 + upper_h * 0.5, -d * 0.05)
	_add_body(ArtStyle3D.make_box(Vector3(w * 0.62, upper_h, d * 0.62), wood, upper_pos), wood)
	# Pitched pyramid roof.
	var roof := ArtStyle3D.make_cone(CELL * 2.2, 0.5, wood_dark, 4, upper_pos + Vector3(0.0, upper_h * 0.5 + 0.25, 0.0))
	roof.rotation.y = PI * 0.25
	_add_body(roof, wood_dark)
	# Faction roof ridge along the apex.
	_add_accent(ArtStyle3D.make_box(Vector3(0.06, 0.07, CELL * 2.6), Color.WHITE,
		upper_pos + Vector3(0.0, upper_h * 0.5 + 0.5, 0.0)))
	# Corner finials pick up the accent on the base tier's front corners.
	for side in [-1.0, 1.0]:
		_add_accent(ArtStyle3D.make_cone(0.09, 0.22, Color.WHITE, 4,
			Vector3(side * (w * 0.5 - 0.06), 0.7 + 0.11, d * 0.5 - 0.06)))
	# Team-colored banner planes hanging off the timber tier's front face.
	for side in [-1.0, 1.0]:
		var pole := ArtStyle3D.make_cylinder(0.015, 0.5, wood_dark, 4,
			Vector3(side * w * 0.18, 0.7 + upper_h + 0.1, d * 0.26))
		_add_body(pole, wood_dark)
		_add_body(ArtStyle3D.make_box(Vector3(0.16, 0.3, 0.02), team,
			Vector3(side * w * 0.18, 0.7 + upper_h - 0.05, d * 0.26 + 0.06)), team)


# ─── Tower: squat cylinder + crenellated cap, damage states ───


func _build_tower() -> void:
	var team := ArtStyle3D.team_color(_team)
	var accent := team.lightened(0.15)
	var r := CELL * 0.8

	# Shaft.
	_add_body(ArtStyle3D.make_cylinder(r, 0.9, team, 8, Vector3(0.0, 0.45, 0.0)), team)
	# Doorway accent strip at the base.
	_add_body(ArtStyle3D.make_box(Vector3(r * 0.7, 0.3, 0.05), accent, Vector3(0.0, 0.15, r - 0.01)), accent)

	# Crenellated cap on a damage pivot (tilts as HP drops).
	_damage_pivot = Node3D.new()
	_damage_pivot.name = "CapPivot"
	_damage_pivot.position.y = 0.9
	add_child(_damage_pivot)
	_add_body(ArtStyle3D.make_box(Vector3(r * 2.4, 0.12, r * 2.4), accent, Vector3(0.0, 0.06, 0.0)), accent, _damage_pivot)
	for sx in [-1.0, 1.0]:
		for sz in [-1.0, 1.0]:
			_add_body(ArtStyle3D.make_box(Vector3(0.1, 0.14, 0.1), accent,
				Vector3(sx * r * 0.95, 0.19, sz * r * 0.95)), accent, _damage_pivot)

	# Broken rubble, hidden until the lowest damage state.
	_rubble = Node3D.new()
	_rubble.name = "Rubble"
	_rubble.visible = false
	add_child(_rubble)
	for i in range(4):
		var h := ArtStyle3D.cell_hash(_cell, 40 + i)
		var off := Vector3((h - 0.5) * r * 2.4, 0.0, (ArtStyle3D.cell_hash(_cell, 50 + i) - 0.5) * r * 2.4)
		var rock := ArtStyle3D.make_box(Vector3(0.12 + h * 0.1, 0.08 + h * 0.08, 0.1 + h * 0.08),
			ArtStyle3D.PALETTE.rock_dark, off + Vector3(0.0, 0.05, 0.0))
		rock.rotation.y = h * PI
		_rubble.add_child(rock)


# ─── Wall: chunky stone segment, damage states ───


func _build_wall() -> void:
	var stone: Color = ArtStyle3D.PALETTE.rock.lightened(0.06)
	var team := ArtStyle3D.team_color(_team)
	var sink := -0.14 if _underground_structure else 0.0

	# Lean pivot for the low-HP tilt.
	_damage_pivot = Node3D.new()
	_damage_pivot.name = "WallPivot"
	add_child(_damage_pivot)

	_add_body(ArtStyle3D.make_box(Vector3(CELL * 0.9, 0.5, CELL * 0.42), stone,
		Vector3(0.0, 0.25 + sink, 0.0)), stone, _damage_pivot)
	# Team-colored capstone.
	_add_body(ArtStyle3D.make_box(Vector3(CELL * 0.92, 0.08, CELL * 0.46), team,
		Vector3(0.0, 0.54 + sink, 0.0)), team, _damage_pivot)
	if ArtStyle3D.detail_enabled():
		for i in range(3):
			var h := ArtStyle3D.cell_hash(_cell, 60 + i)
			_add_body(ArtStyle3D.make_box(Vector3(CELL * 0.26, 0.2, CELL * 0.44),
				stone.darkened(0.08 + h * 0.08),
				Vector3((float(i) - 1.0) * CELL * 0.3, 0.32 + sink, 0.0)), stone, _damage_pivot)

	_rubble = Node3D.new()
	_rubble.name = "Rubble"
	_rubble.visible = false
	add_child(_rubble)
	for i in range(3):
		var h := ArtStyle3D.cell_hash(_cell, 70 + i)
		var rock := ArtStyle3D.make_box(Vector3(0.1 + h * 0.08, 0.06 + h * 0.06, 0.08 + h * 0.06),
			ArtStyle3D.PALETTE.rock_dark,
			Vector3((h - 0.5) * CELL * 0.8, 0.04, (ArtStyle3D.cell_hash(_cell, 80 + i) - 0.5) * CELL * 0.4))
		rock.rotation.y = h * TAU
		_rubble.add_child(rock)


# ─── Lantern: the dynamic-light hero ───


func _build_lantern(s: Node2D) -> void:
	_lantern_underground = bool(s.get("is_underground_lantern"))
	_underground_structure = _lantern_underground
	var wood_dark: Color = ArtStyle3D.PALETTE.wood_dark

	# Thin wood post + small arm holding the head.
	_add_body(ArtStyle3D.make_cylinder(0.03, 0.6, wood_dark, 5, Vector3(0.0, 0.3, 0.0)), wood_dark)
	_add_body(ArtStyle3D.make_box(Vector3(0.16, 0.03, 0.03), wood_dark, Vector3(0.07, 0.6, 0.0)), wood_dark)

	_lantern_head = ArtStyle3D.make_box(Vector3(0.15, 0.15, 0.15), Color.WHITE, Vector3(0.13, 0.52, 0.0))
	_lantern_head.name = "Head"
	add_child(_lantern_head)

	_lantern_light = OmniLight3D.new()
	_lantern_light.name = "LanternLight"
	_lantern_light.light_color = ArtStyle3D.PALETTE.lamp_warm
	_lantern_light.position = Vector3(0.13, 0.52, 0.0)
	add_child(_lantern_light)

	_apply_lantern_tier(clampi(int(s.get("tier")), 1, 3))


static func _lantern_head_material(built: bool) -> StandardMaterial3D:
	if built:
		return ArtStyle3D.get_material(ArtStyle3D.PALETTE.lamp_warm, ArtStyle3D.PALETTE.lamp_warm, 1.4)
	return ArtStyle3D.get_material(Color(0.3, 0.26, 0.2), ArtStyle3D.PALETTE.lamp_warm, 0.05)


## Tier drives light radius/energy: the vision upgrade now looks like an
## upgrade. Underground lanterns burn smaller, warmer, and never cast shadows.
func _apply_lantern_tier(tier: int) -> void:
	if _lantern_light == null:
		return
	var cells: int
	var energy: float
	if _lantern_underground:
		cells = Constants.UNDERGROUND_LANTERN_VISION
		energy = 0.9
	else:
		match tier:
			1:
				cells = Constants.LANTERN_T1_VISION
				energy = 0.8
			2:
				cells = Constants.LANTERN_T2_VISION
				energy = 1.2
			_:
				cells = Constants.LANTERN_T3_VISION
				energy = 1.6
	_lantern_light.omni_range = cells * GridWorld.CELL_SIZE * WORLD_SCALE
	_lantern_light.omni_attenuation = 1.4
	_lantern_light.light_energy = energy
	_lantern_light.shadow_enabled = ArtStyle3D.shadows_enabled() and not _lantern_underground
	if _lantern_head != null and not _lantern_underground:
		_lantern_head.scale = Vector3.ONE * (1.0 + 0.18 * float(tier - 1))


func _on_lantern_upgraded(tier: int) -> void:
	_apply_lantern_tier(clampi(tier, 1, 3))


# ─── Mine entry: wooden A-frame headframe over a dark shaft ───


func _build_mine_entry() -> void:
	var wood: Color = ArtStyle3D.PALETTE.wood
	var wood_dark: Color = ArtStyle3D.PALETTE.wood_dark
	var team := ArtStyle3D.team_color(_team)
	# The node origin sits on a cell corner; the shaft column center is half a
	# cell over, so the headframe straddles the hole.
	var cx := CELL * 0.5
	var cz := CELL * 0.5

	# Dark recessed shaft hole, sunk into the ground.
	_add_body(ArtStyle3D.make_cylinder(CELL * 0.62, 0.08, ArtStyle3D.PALETTE.coal, 8,
		Vector3(cx, -0.015, cz)), ArtStyle3D.PALETTE.coal)
	# A-frame legs leaning together over the hole.
	for side in [-1.0, 1.0]:
		var leg := ArtStyle3D.make_box(Vector3(0.07, 0.95, 0.07), wood,
			Vector3(cx + side * 0.24, 0.42, cz))
		leg.rotation.z = -side * 0.28
		_add_body(leg, wood)
	# Crossbar + team trim band.
	_add_body(ArtStyle3D.make_box(Vector3(0.62, 0.07, 0.07), wood_dark, Vector3(cx, 0.72, cz)), wood_dark)
	_add_body(ArtStyle3D.make_box(Vector3(0.2, 0.075, 0.075), team, Vector3(cx, 0.72, cz)), team)
	# Pulley wheel under the apex.
	_add_body(ArtStyle3D.make_cylinder(0.07, 0.04, wood_dark, 8, Vector3(cx, 0.62, cz)), wood_dark)


# ─── Ladder: two rails + detail-gated rungs ───


func _build_ladder(s: Node2D) -> void:
	var top: Vector2 = s.get("top_position")
	var bottom: Vector2 = s.get("bottom_position")
	var top3 := Vector3(top.x * WORLD_SCALE, 0.0, top.y * WORLD_SCALE)
	var bottom3 := Vector3(bottom.x * WORLD_SCALE, 0.0, bottom.y * WORLD_SCALE)
	var dir := bottom3 - top3
	var length := maxf(dir.length(), 0.1)
	var dir_n := dir / length if dir.length() > 0.0001 else Vector3.FORWARD
	var yaw := atan2(dir_n.x, dir_n.z)
	var wood_dark: Color = ArtStyle3D.PALETTE.wood_dark

	for side: float in [-1.0, 1.0]:
		var perp := Vector3(dir_n.z, 0.0, -dir_n.x) * side * 0.1
		var rail := ArtStyle3D.make_box(Vector3(0.05, 0.06, length + 0.08), wood_dark,
			(top3 + bottom3) * 0.5 + perp)
		rail.rotation.y = yaw
		_add_body(rail, wood_dark)
	if ArtStyle3D.detail_enabled():
		var t := 0.18
		while t < length - 0.1:
			var rung := ArtStyle3D.make_box(Vector3(0.24, 0.03, 0.03), wood_dark, top3 + dir_n * t)
			rung.rotation.y = yaw
			_add_body(rung, wood_dark)
			t += 0.3


# ─── Trap: low dark plate with a pressure-spikes hint ───


func _build_trap() -> void:
	var coal: Color = ArtStyle3D.PALETTE.coal
	_add_body(ArtStyle3D.make_box(Vector3(CELL * 0.8, 0.05, CELL * 0.8), coal, Vector3(0.0, -0.005, 0.0)), coal)
	if ArtStyle3D.detail_enabled():
		for i in range(4):
			var off := Vector2((i % 2) - 0.5, (i / 2) - 0.5) * CELL * 0.4
			_add_body(ArtStyle3D.make_cone(0.025, 0.06, ArtStyle3D.PALETTE.rock_dark, 4,
				Vector3(off.x, 0.03, off.y)), ArtStyle3D.PALETTE.rock_dark)


# ─── Damage states (towers and walls) ───


func _read_damage() -> void:
	if entity == null or not is_instance_valid(entity):
		return
	var hp_v: Variant = entity.get("hp")
	var max_v: Variant = entity.get("max_hp")
	if hp_v == null or max_v == null:
		return
	var max_hp := maxf(float(max_v), 1.0)
	var ratio := clampf(float(hp_v) / max_hp, 0.0, 1.0)
	var state := 0
	if ratio < 0.3:
		state = 2
	elif ratio < 0.6:
		state = 1
	_damage_darken = _DAMAGE_DARKEN[state]
	if _damage_pivot != null:
		_damage_pivot.rotation.z = _DAMAGE_TILTS[state] * _tilt_sign
	if _rubble != null:
		_rubble.visible = state == 2


func _on_hp_changed(_current: int, _maximum: int) -> void:
	_read_damage()
	_tint_bodies(_last_remembered, _last_built)


# ─── Refresh ───


func _tint_bodies(remembered: bool, built: bool) -> void:
	_last_remembered = remembered
	_last_built = built
	var alpha := 1.0 if built else CONSTRUCTION_ALPHA
	for i in range(_body_meshes.size()):
		var c: Color = _body_colors[i]
		if remembered:
			c = c.lerp(REMEMBERED_COLOR, 0.7)
		c = c.darkened(_damage_darken)
		c.a = alpha
		var mat := _body_mats[i]
		mat.albedo_color = c
		mat.transparency = BaseMaterial3D.TRANSPARENCY_DISABLED if built else BaseMaterial3D.TRANSPARENCY_ALPHA


## Reconcile-time refresh: fog visibility, layer visibility, construction
## alpha, damage states. underground_view is the rig's current Tab layer.
func refresh(underground_view: bool) -> void:
	if dead or entity == null or not is_instance_valid(entity):
		return
	var layer_ok := true
	if not _shows_in_both_layers:
		layer_ok = (_underground_structure == underground_view)
	# The 2D sim only flips .visible per fog on enemy buildings/traps; every
	# other enemy structure stays visible and is merely covered by the fog
	# overlay. Mirror the fog honestly here: unexplored hides, remembered
	# dims (like building.gd's gray modulate), visible shows.
	var fog_ok := true
	var remembered := false
	if _enemy and _grid != null and is_instance_valid(_grid):
		match _grid.fog_state_at(GameManager.Team.PLAYER, _cell):
			0:
				fog_ok = false
			1:
				remembered = true
	visible = layer_ok and fog_ok and entity.visible
	var built := true
	if entity.has_method("is_built"):
		built = bool(entity.call("is_built"))
	if _kind == _Kind.TOWER or _kind == _Kind.WALL:
		_read_damage()
	_tint_bodies(remembered, built)
	if _kind == _Kind.LANTERN and _lantern_light != null:
		# Unbuilt lanterns give no light and wear a dim head.
		_lantern_light.visible = built
		_lantern_head.set_material_override(_lantern_head_material(built))


func _on_destroyed(_arg: Variant = null) -> void:
	dead = true
	if _faction_connected and is_instance_valid(FactionManager) \
			and FactionManager.faction_identified.is_connected(_on_faction_identified):
		FactionManager.faction_identified.disconnect(_on_faction_identified)
	_faction_connected = false
