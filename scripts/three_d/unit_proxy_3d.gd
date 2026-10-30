## Phase 2 unit proxy (roadmap/3d-conversion/phase-2-art-pass.md §2.2).
##
## A Node3D that mirrors one live 2D unit: position, flight altitude, fog
## visibility (the sim flips unit.visible per fog — mirrored, never
## reimplemented), the sim's layer (surface vs underground), HP as a tiny
## camera-facing bar (counter-scaled, so the Phase 2 proxy-root scale-up
## doesn't grow it), and death (unit.died -> proxy dead; the manager frees
## it, the proxy never writes to the unit). The Phase 1 billboard Sprite3D
## is replaced by an R7 imported UnitModel3D rig (procedural on Potato); the
## ground blob shadow and the fog/HP mirroring are unchanged.
extends Node3D
class_name UnitProxy3D

const WORLD_SCALE: float = 0.01
## 3D rework Phase 2: proxy-root scale-up so units read at RTS distance — the
## models themselves stay untouched (unit_model_3d.gd). The blob shadow is a
## child and scales along; the HP bar is counter-scaled so it keeps its
## world size, and the selection rings track the scale via this constant.
const PROXY_SCALE: float = 1.4
## Phase 1 3D-rework sizing: ~half the old bar, so a selected army reads as
## neat ticks instead of a stripe band; the dark plate behind is the border.
## All sizes are world-space (pre-proxy-scale); _build_hp_bar counter-scales.
const HP_BAR_WIDTH: float = 0.28
const HP_BAR_HEIGHT: float = 0.04
const HP_BAR_BORDER: float = 0.015
const HP_BAR_LIFT: float = 0.16

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
## Change-detection cache: the sync below runs every frame from the proxy
## manager, but only re-derives/writes what actually changed. Surface units
## re-sample the dune field when they move past _GROUND_RESAMPLE_DIST or when
## the field itself changes (storm flattening, structure clearances).
var _last_ground_pos := Vector2(1e9, 1e9)
var _last_height_revision := -1
var _ground_y := 0.0
var _last_hp := -1
var _last_max_hp := -1
var _last_bar_shown := false
var _last_camera_yaw := 0.0
const _GROUND_RESAMPLE_DIST: float = 8.0  # px; 1/4 cell keeps snap error tiny
## R3: cached shell terrain for dune ground-snap (null in standalone 2D and
## in tests that never sync — both stay flat).
var _terrain: Node = null


static func create(u: Node2D) -> UnitProxy3D:
	var p := UnitProxy3D.new()
	p.unit = u
	p._underground_unit = u.is_underground
	p.scale = Vector3.ONE * PROXY_SCALE

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
	# Counter the proxy-root scale: the bar keeps its authored world size and
	# still crowns the scaled silhouette (model_height is pre-scale, so the
	# lift is divided back out of the scaled parent space).
	_hp_bar.scale = Vector3.ONE / PROXY_SCALE
	_hp_bar.position.y = (_model_height + HP_BAR_LIFT) / PROXY_SCALE
	# Dark border plate: slightly larger than the fill so it frames it.
	var bg := MeshInstance3D.new()
	var bg_mesh := QuadMesh.new()
	bg_mesh.size = Vector2(HP_BAR_WIDTH + HP_BAR_BORDER * 2.0, HP_BAR_HEIGHT + HP_BAR_BORDER * 2.0)
	bg.mesh = bg_mesh
	bg.set_material_override(_get_bg_material())
	_hp_bar.add_child(bg)
	_hp_fg = MeshInstance3D.new()
	var fg_mesh := QuadMesh.new()
	fg_mesh.size = Vector2(HP_BAR_WIDTH, HP_BAR_HEIGHT)
	_hp_fg.mesh = fg_mesh
	# Sit a hair in front of the border plate so the frame never z-fights.
	_hp_fg.position.z = 0.002
	_hp_mat = StandardMaterial3D.new()
	_hp_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_hp_fg.set_material_override(_hp_mat)
	_hp_bar.add_child(_hp_fg)
	_hp_bar.visible = false
	add_child(_hp_bar)


## Per-frame mirror of the live unit, driven from EntityProxies3D with the
## frame delta (the proxy keeps no _process of its own). underground_view is
## the rig's current Tab layer; the unit shows iff it is on that layer AND
## the sim considers it visible to the player (fog). Change-detected: a
## proxy that is already off-layer or fog-hidden returns after the cheap
## visibility read, and visible proxies re-sample the dune field / rewrite
## the HP bar only on real changes — at army scale the no-op fast path is
## the common case. `delta` defaults so existing two-arg test callers keep
## working (animation just advances a standstill tick).
func sync_from_entity(underground_view: bool, camera_yaw: float, delta: float = 0.016) -> void:
	if dead or unit == null or not is_instance_valid(unit):
		return
	var now_visible: bool = (unit.is_underground == underground_view) and unit.visible
	if not now_visible and not visible:
		# Off the active layer or fog-hidden: nothing renders, so no pose,
		# ground-snap, or HP-bar work is needed. A visibility flip, a move,
		# or an hp/selection change drops through to the full sync below.
		return
	visible = now_visible
	var pos: Vector2 = unit.global_position
	# R3: surface units ground-snap to the dune field (underground floor is
	# flat 0, flyers lift the model from the snapped base).
	if not _underground_unit and is_inside_tree():
		if pos.distance_squared_to(_last_ground_pos) > _GROUND_RESAMPLE_DIST * _GROUND_RESAMPLE_DIST:
			_resample_ground(pos)
		else:
			var rev := _height_revision()
			if rev != _last_height_revision:
				_resample_ground(pos)
	global_position = Vector3(pos.x * WORLD_SCALE, _ground_y, pos.y * WORLD_SCALE)
	var altitude: float = float(unit.call("get_flight_altitude")) * WORLD_SCALE
	# The model's feet sit at local y=0; flying units lift the whole rig.
	_model.position.y = altitude
	_model.sync_animation(unit, delta, pos)
	if camera_yaw != _last_camera_yaw:
		_last_camera_yaw = camera_yaw
		_hp_bar.rotation.y = camera_yaw
	var max_hp := int(unit.data.max_hp)
	if max_hp > 0:
		var hp := int(unit.hp)
		# Selected or hovered units always show their bar (2D parity:
		# unit_rendering.gd); otherwise only while damaged. get() so test
		# doubles without those properties keep working.
		var bar_shown: bool = unit.get("selected") == true or unit.get("hovered") == true \
				or hp < max_hp
		if hp != _last_hp or max_hp != _last_max_hp or bar_shown != _last_bar_shown:
			_last_hp = hp
			_last_max_hp = max_hp
			_last_bar_shown = bar_shown
			var ratio := clampf(float(hp) / float(max_hp), 0.0, 1.0)
			_hp_bar.visible = ratio > 0.0 and bar_shown
			_hp_fg.scale.x = maxf(ratio, 0.001)
			# QuadMesh scales about its center; shift left so the bar drains
			# right-to-left from a fixed left edge.
			_hp_fg.position.x = -HP_BAR_WIDTH * (1.0 - ratio) * 0.5
			_hp_mat.albedo_color = Color(1.0 - ratio, 0.75 * ratio + 0.15, 0.15, 1.0)
	else:
		if _hp_bar.visible:
			_hp_bar.visible = false


func _resample_ground(pos: Vector2) -> void:
	_last_ground_pos = pos
	if _terrain == null or not is_instance_valid(_terrain):
		_terrain = Presentation3D.terrain(get_tree())
		_last_height_revision = -1
	if _terrain == null:
		return
	if _terrain.has_method("ground_height_revision"):
		_last_height_revision = int(_terrain.call("ground_height_revision"))
	_ground_y = float(_terrain.call("world_height_at", pos.x * WORLD_SCALE, pos.y * WORLD_SCALE))


func _height_revision() -> int:
	if _terrain != null and is_instance_valid(_terrain) \
			and _terrain.has_method("ground_height_revision"):
		return int(_terrain.call("ground_height_revision"))
	return _last_height_revision


func _on_unit_died(_arg: Variant = null) -> void:
	dead = true
