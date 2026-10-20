## 3D rework Phase 1 (roadmap/3d-rework/phase-1-selection-and-combat-feedback--k3.md §1).
##
## Ground-projected selection feedback, replacing the 2D selection ring that
## the hidden canvas layer suppresses in 3D mode. One MultiMeshInstance3D
## draws a flat annulus under every selected unit (bright player accent, with
## the same gentle pulse as the 2D ring) plus a dimmer pre-selection ring
## under the hovered unit. Rebuilt every frame from PlayerController's
## selection (read-only; selection itself has no signal), so box-selecting 30
## units shows 30 rings with a single draw call.
##
## Hover note: the sim's Area2D mouse_entered hover flags never fire in 3D
## mode (hidden canvas items are not pickable), so the hovered unit is
## re-derived here from the mouse position via the invisible 2D camera's
## canvas transform — the same math PlayerSelection._unit_at uses for clicks.
extends Node3D
class_name SelectionRings3D

const SELECT_COLOR := Color(0.55, 0.85, 1.0, 0.95)
const HOVER_COLOR := Color(0.55, 0.85, 1.0, 0.4)
## 3D rework Phase 2: the unit proxies are scaled up by
## UnitProxy3D.PROXY_SCALE, and the rings track the model footprint so a
## selected unit's ring still hugs its silhouette.
const BASE_RADIUS: float = 0.24 * UnitProxy3D.PROXY_SCALE
const FLYER_RADIUS: float = 0.44 * UnitProxy3D.PROXY_SCALE
const PULSE_AMOUNT: float = 0.06
const PULSE_PERIOD: float = 0.8

var _pc: PlayerController
var _underground_view := false
var _multimesh: MultiMesh
var _pulse_time := 0.0


func _init() -> void:
	_multimesh = MultiMesh.new()
	_multimesh.transform_format = MultiMesh.TRANSFORM_3D
	_multimesh.use_colors = true
	_multimesh.mesh = FlatGeo3D.ring_mesh()
	var mmi := MultiMeshInstance3D.new()
	mmi.name = "Rings"
	mmi.multimesh = _multimesh
	# White base: the per-instance colors carry the actual ring color.
	mmi.set_material_override(FlatGeo3D.material(Color.WHITE))
	add_child(mmi)


func setup(pc: PlayerController) -> void:
	_pc = pc


func set_underground_view(underground: bool) -> void:
	_underground_view = underground


func _process(delta: float) -> void:
	_pulse_time += delta
	if _pc == null or not is_instance_valid(_pc):
		_multimesh.instance_count = 0
		return
	var transforms: Array[Transform3D] = []
	var colors: Array[Color] = []
	var pulse: float = 1.0 + PULSE_AMOUNT * sin(_pulse_time * TAU / PULSE_PERIOD)
	for unit in _pc.get_selected_units():
		if not _ring_eligible(unit):
			continue
		_add_ring(transforms, colors, unit, _ring_radius(unit) * pulse, SELECT_COLOR)
	var hovered: Unit = _hovered_unit()
	if hovered != null and not _pc.get_selected_units().has(hovered):
		_add_ring(transforms, colors, hovered, _ring_radius(hovered), HOVER_COLOR)
	_multimesh.instance_count = transforms.size()
	for i in range(transforms.size()):
		_multimesh.set_instance_transform(i, transforms[i])
		_multimesh.set_instance_color(i, colors[i])


## Rings follow the same visibility contract as the unit proxies: the unit
## must live on the viewed layer and be visible to the player (fog).
func _ring_eligible(unit: Variant) -> bool:
	return is_instance_valid(unit) and unit.visible \
		and unit.get("_state") != Unit.State.DEAD \
		and unit.is_underground == _underground_view


func _add_ring(transforms: Array[Transform3D], colors: Array[Color], unit: Unit, radius: float, color: Color) -> void:
	var pos: Vector2 = unit.global_position
	var origin := Vector3(pos.x * Presentation3D.WORLD_SCALE, Presentation3D.GROUND_LIFT, pos.y * Presentation3D.WORLD_SCALE)
	transforms.append(Transform3D(Basis.from_scale(Vector3(radius, 1.0, radius)), origin))
	colors.append(color)


## Ring radius from the unit's silhouette: flyers (dragon, pigeon) get a wide
## ring around their shadow spot, everything else hugs the model footprint.
func _ring_radius(unit: Unit) -> float:
	if unit.data != null and unit.data.flight_altitude > 0.0:
		return FLYER_RADIUS * maxf(unit.data.draw_scale, 0.8)
	if unit.data != null:
		return BASE_RADIUS * clampf(unit.data.draw_scale, 0.8, 1.4)
	return BASE_RADIUS


## Nearest unit under the cursor (either team, like the 2D hover HP bar) on
## the viewed layer and visible through fog. Returns null when the cursor is
## over empty ground, the HUD, or while a click-drag selection box is open.
func _hovered_unit() -> Unit:
	if _pc._is_dragging or _pc._build_mode != "":
		return null
	var viewport := _pc.get_viewport()
	if viewport == null or viewport.gui_get_hovered_control() != null:
		return null
	var world_pos: Vector2 = viewport.get_canvas_transform().affine_inverse() * viewport.get_mouse_position()
	var best: Unit = null
	var best_dist: float = GridWorld.CELL_SIZE / 1.5
	for unit in get_tree().get_nodes_in_group("units"):
		if not _ring_eligible(unit):
			continue
		var d: float = unit.get_combat_position().distance_to(world_pos)
		if d < best_dist:
			best_dist = d
			best = unit
	return best
