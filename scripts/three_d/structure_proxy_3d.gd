## Phase 1 structure proxy (roadmap/3d-conversion/phase-1-25d-port.md §1.3).
##
## Box-mesh / billboard stand-ins for the 2D structures, mirroring the live
## node: team colors, construction alpha (is_built), fog visibility (the sim
## flips node.visible per fog — mirrored), and layer (a lantern or wall in
## the mine shows only in the underground Tab view; ladders and mine entries
## straddle the boundary and show in both). Destruction frees the proxy via
## the structure's destroyed signal when it has one; everything else is
## culled by the manager's reconcile pass. The proxy never writes to the
## structure.
extends Node3D
class_name StructureProxy3D

const WORLD_SCALE: float = 0.01
const CELL: float = 32.0 * WORLD_SCALE
const CONSTRUCTION_ALPHA: float = 0.55
const REMEMBERED_COLOR := Color(0.3, 0.3, 0.32)
const MINE_ENTRY_TEXTURE: Texture2D = preload("res://frost_mines_assets/props/mine_entry.png")

static var _lantern_head_material: StandardMaterial3D

var entity: Node2D
var dead := false
var source_id: int = 0

var _underground_structure := false
var _shows_in_both_layers := false
var _mat: StandardMaterial3D
var _grid: GridWorld
var _cell: Vector2i
var _base_color := Color.WHITE
var _enemy := false


static func create(s: Node2D, grid: GridWorld) -> StructureProxy3D:
	var p := StructureProxy3D.new()
	p.entity = s
	p._mat = StandardMaterial3D.new()
	p._mat.roughness = 0.9

	if s.is_in_group("buildings"):
		p._build_box(_team_color(s), Vector3(CELL * 6.0, 1.5, CELL * 5.0), 0.0)
	elif s.is_in_group("towers"):
		p._build_box(_team_color(s).darkened(0.25), Vector3(CELL * 1.6, 1.3, CELL * 1.6), 0.0)
	elif s.is_in_group("lanterns"):
		p._build_lantern(s)
	elif s.is_in_group("walls"):
		p._underground_structure = _is_underground_cell(s, grid)
		p._build_box(_team_color(s), Vector3(CELL * 0.4, 0.45, CELL), 0.0)
	elif s.is_in_group("traps"):
		p._underground_structure = grid.world_to_grid(s.global_position).y >= 1
		p._build_box(Color(0.35, 0.22, 0.12), Vector3(CELL * 0.8, 0.06, CELL * 0.8), -0.03)
	elif s.is_in_group("mine_entries"):
		p._build_mine_entry()
	elif s.is_in_group("ladders"):
		p._shows_in_both_layers = true
		p._build_ladder(s)
	else:
		p._build_box(Color(0.5, 0.5, 0.55), Vector3(CELL, 0.5, CELL), 0.0)

	# Local position: the proxy is not inside the tree yet, and the parent
	# container sits at the origin, so local == global here.
	var pos: Vector2 = s.global_position
	p.position = Vector3(pos.x * WORLD_SCALE, 0.0, pos.y * WORLD_SCALE)

	# Fog mirror inputs: the sim only flips .visible on enemy buildings/traps,
	# so refresh() checks the fog map itself for every enemy structure.
	p._grid = grid
	p._cell = grid.world_to_grid(pos)
	var team: Variant = s.get("team")
	p._enemy = team != null and team == GameManager.Team.ENEMY

	if s.has_signal("destroyed"):
		s.connect("destroyed", p._on_destroyed)
	s.tree_exiting.connect(p._on_destroyed)
	return p


static func _team_color(s: Node2D) -> Color:
	return GameManager.COLOR_PLAYER if s.team == GameManager.Team.PLAYER else GameManager.COLOR_ENEMY


static func _is_underground_cell(s: Node2D, grid: GridWorld) -> bool:
	if s.has_method("get_cell"):
		return (s.call("get_cell") as Vector2i).y >= 1
	return false


func _build_box(color: Color, size: Vector3, sink: float) -> void:
	_base_color = color
	_mat.albedo_color = color
	var box := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = size
	box.mesh = mesh
	box.set_material_override(_mat)
	box.position.y = size.y * 0.5 + sink
	add_child(box)


func _build_lantern(s: Node2D) -> void:
	_underground_structure = bool(s.get("is_underground_lantern"))
	_build_box(Color(0.25, 0.22, 0.18), Vector3(0.1, 0.5, 0.1), 0.0)
	var tier := clampi(int(s.get("tier")), 1, 3)
	var head := MeshInstance3D.new()
	var head_mesh := BoxMesh.new()
	head_mesh.size = Vector3(0.2, 0.14, 0.2)
	head.mesh = head_mesh
	head.position.y = 0.5 + 0.1 * tier
	head.set_material_override(_get_lantern_head_material())
	add_child(head)


static func _get_lantern_head_material() -> StandardMaterial3D:
	if _lantern_head_material == null:
		_lantern_head_material = StandardMaterial3D.new()
		_lantern_head_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_lantern_head_material.albedo_color = Color(1.0, 0.85, 0.4)
	return _lantern_head_material


func _build_mine_entry() -> void:
	_shows_in_both_layers = true
	var sprite := Sprite3D.new()
	sprite.texture = MINE_ENTRY_TEXTURE
	sprite.pixel_size = WORLD_SCALE
	sprite.billboard = BaseMaterial3D.BILLBOARD_FIXED_Y
	sprite.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	sprite.position.y = MINE_ENTRY_TEXTURE.get_height() * WORLD_SCALE * 0.5
	add_child(sprite)


func _build_ladder(s: Node2D) -> void:
	var top: Vector2 = s.get("top_position")
	var bottom: Vector2 = s.get("bottom_position")
	var top3 := Vector3(top.x * WORLD_SCALE, 0.0, top.y * WORLD_SCALE)
	var bottom3 := Vector3(bottom.x * WORLD_SCALE, 0.0, bottom.y * WORLD_SCALE)
	var length := top3.distance_to(bottom3)
	var rail := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = Vector3(0.12, 0.12, maxf(length, 0.1))
	rail.mesh = mesh
	rail.position = (top3 + bottom3) * 0.5
	add_child(rail)


## Reconcile-time refresh: fog visibility, layer visibility, construction
## alpha. underground_view is the rig's current Tab layer.
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
	var color := _base_color
	if remembered:
		color = color.lerp(REMEMBERED_COLOR, 0.7)
	color.a = 1.0 if built else CONSTRUCTION_ALPHA
	_mat.albedo_color = color
	_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA if not built else BaseMaterial3D.TRANSPARENCY_DISABLED


func _on_destroyed(_arg: Variant = null) -> void:
	dead = true
