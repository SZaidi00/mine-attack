## Phase 2 unit proxy (roadmap/3d-conversion/phase-2-art-pass.md §2.2).
##
## A Node3D that mirrors one live 2D unit: position, flight altitude, fog
## visibility (the sim flips unit.visible per fog — mirrored, never
## reimplemented), the sim's layer (surface vs underground), HP as a tiny
## camera-facing bar, and death (unit.died -> proxy dead; the manager frees
## it, the proxy never writes to the unit). The Phase 1 billboard Sprite3D
## is replaced by a procedural UnitModel3D rig; the ground blob shadow and
## the fog/HP mirroring are unchanged.
extends Node3D
class_name UnitProxy3D

const WORLD_SCALE: float = 0.01
const HP_BAR_WIDTH: float = 0.6
const HP_BAR_HEIGHT: float = 0.07
const HP_BAR_LIFT: float = 0.18

static var _shadow_texture: ImageTexture
static var _bg_material: StandardMaterial3D

var unit: Node2D
var dead := false
var source_id: int = 0

var _model: UnitModel3D
var _shadow: Sprite3D
var _hp_bar: Node3D
var _hp_fg: MeshInstance3D
var _hp_mat: StandardMaterial3D
var _model_height: float = 0.4
var _underground_unit: bool = false
var _delta: float = 0.0


static func create(u: Node2D) -> UnitProxy3D:
	var p := UnitProxy3D.new()
	p.unit = u
	p._underground_unit = u.is_underground

	p._model = UnitModel3D.create(u)
	p._model_height = p._model.model_height
	p.add_child(p._model)

	p._shadow = Sprite3D.new()
	p._shadow.texture = _get_shadow_texture()
	p._shadow.pixel_size = WORLD_SCALE * 2.0
	p._shadow.rotation_degrees.x = -90.0
	p._shadow.position.y = 0.02
	p._shadow.modulate = Color(0.0, 0.0, 0.0, 0.35)
	p.add_child(p._shadow)

	p._build_hp_bar()

	u.died.connect(p._on_unit_died)
	u.tree_exiting.connect(p._on_unit_died)
	return p


static func _get_shadow_texture() -> ImageTexture:
	if _shadow_texture == null:
		var size := 64
		var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
		var center := Vector2(size, size) * 0.5
		for py in range(size):
			for px in range(size):
				var d := Vector2(px, py).distance_to(center) / (size * 0.5)
				var a := clampf(1.0 - d, 0.0, 1.0)
				img.set_pixel(px, py, Color(0.0, 0.0, 0.0, a))
		_shadow_texture = ImageTexture.create_from_image(img)
	return _shadow_texture


static func _get_bg_material() -> StandardMaterial3D:
	if _bg_material == null:
		_bg_material = StandardMaterial3D.new()
		_bg_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_bg_material.albedo_color = Color(0.05, 0.06, 0.08, 0.9)
		_bg_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	return _bg_material


func _build_hp_bar() -> void:
	_hp_bar = Node3D.new()
	_hp_bar.position.y = _model_height + HP_BAR_LIFT
	var bg := MeshInstance3D.new()
	var bg_mesh := QuadMesh.new()
	bg_mesh.size = Vector2(HP_BAR_WIDTH, HP_BAR_HEIGHT)
	bg.mesh = bg_mesh
	bg.set_material_override(_get_bg_material())
	_hp_bar.add_child(bg)
	_hp_fg = MeshInstance3D.new()
	var fg_mesh := QuadMesh.new()
	fg_mesh.size = Vector2(HP_BAR_WIDTH, HP_BAR_HEIGHT)
	_hp_fg.mesh = fg_mesh
	_hp_mat = StandardMaterial3D.new()
	_hp_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_hp_fg.set_material_override(_hp_mat)
	_hp_bar.add_child(_hp_fg)
	_hp_bar.visible = false
	add_child(_hp_bar)


func _process(delta: float) -> void:
	_delta = delta


## Per-frame mirror of the live unit. underground_view is the rig's current
## Tab layer; the unit shows iff it is on that layer AND the sim considers
## it visible to the player (fog).
func sync_from_entity(underground_view: bool, camera_yaw: float) -> void:
	if dead or unit == null or not is_instance_valid(unit):
		return
	var pos: Vector2 = unit.global_position
	global_position = Vector3(pos.x * WORLD_SCALE, 0.0, pos.y * WORLD_SCALE)
	var altitude: float = float(unit.call("get_flight_altitude")) * WORLD_SCALE
	# The model's feet sit at local y=0; flying units lift the whole rig.
	_model.position.y = altitude
	visible = (unit.is_underground == underground_view) and unit.visible
	_model.sync_animation(unit, _delta)
	_hp_bar.rotation.y = camera_yaw
	var max_hp := int(unit.data.max_hp)
	if max_hp > 0:
		var ratio := clampf(float(unit.hp) / float(max_hp), 0.0, 1.0)
		_hp_bar.visible = ratio < 1.0 and ratio > 0.0
		_hp_fg.scale.x = maxf(ratio, 0.001)
		# QuadMesh scales about its center; shift left so the bar drains
		# right-to-left from a fixed left edge.
		_hp_fg.position.x = -HP_BAR_WIDTH * (1.0 - ratio) * 0.5
		_hp_mat.albedo_color = Color(1.0 - ratio, 0.75 * ratio + 0.15, 0.15, 1.0)
	else:
		_hp_bar.visible = false


func _on_unit_died(_arg: Variant = null) -> void:
	dead = true
