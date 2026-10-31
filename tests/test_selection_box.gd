extends GutTest

# Plan 02 (plans/02-3d-box-select.md): regression coverage for the standalone
# 2D drag-box path — no 3D shell, so units project through the 2D canvas
# transform (the hidden Camera2D). The shell-mode rig projection lives in
# tests/test_3d_selection.gd. Both paths must agree on the exact selected set.

const PLAYER: int = 0

var _main: Node
var _grid: Node
var _pc: Node


func before_all() -> void:
	seed(12345)
	GameManager.set_map_seed(7)
	_main = load("res://scenes/main.tscn").instantiate()
	get_tree().root.add_child(_main)
	get_tree().current_scene = _main
	_grid = _main.get_node("World/GridWorld")
	_pc = _main.get_node("PlayerController")
	await wait_seconds(0.1)


func after_all() -> void:
	_main.free()
	GameManager.clear_map_seed()


func before_each() -> void:
	# Starting miners spawn deferred from each building's _ready — wipe them so
	# the "player" group holds exactly the units a test spawns.
	for u in get_tree().get_nodes_in_group("player"):
		u.free()
	_pc._selection._select_units([])


func _spawn_unit(unit_id: String, cell: Vector2i) -> Node2D:
	var unit: Node2D = load("res://scenes/unit.tscn").instantiate()
	unit.set("data", load("res://scripts/resources/units/%s.tres" % unit_id).duplicate(true))
	unit.set("team", PLAYER)
	unit.position = (_grid as GridWorld).grid_to_world(cell)
	_main.get_node("Units").add_child(unit)
	autofree(unit)
	return unit


func _assert_selected_exactly(units: Array) -> void:
	var sel: Array = _pc.get_selected_units()
	assert_eq(sel.size(), units.size(), "exactly %d unit(s) selected (got %d)" % [units.size(), sel.size()])
	for u in units:
		assert_true(sel.has(u), "selection contains the enclosed unit")


func test_box_select_selects_exactly_the_units_in_the_rect() -> void:
	var a := _spawn_unit("swordsman", Vector2i(-20, 0))
	var b := _spawn_unit("swordsman", Vector2i(-16, 0))
	var c := _spawn_unit("swordsman", Vector2i(-12, 0))
	var canvas: Transform2D = _pc.get_viewport().get_canvas_transform()
	var sp_a: Vector2 = canvas * a.global_position
	var sp_b: Vector2 = canvas * b.global_position
	var sp_c: Vector2 = canvas * c.global_position
	# Drag rect hugs b's projected feet; neighbors must sit well outside.
	var nearest := minf(sp_b.distance_to(sp_a), sp_b.distance_to(sp_c))
	assert_gt(nearest * 0.2, 10.0,
		"neighbor units project far enough apart for a clean rect (gap %.1f px)" % nearest)
	var margin := Vector2(minf(30.0, nearest * 0.2), minf(45.0, nearest * 0.2))
	var rect := Rect2(sp_b - margin, margin * 2.0)
	_pc._selection._box_select(rect.position, rect.end)
	_assert_selected_exactly([b])


func test_box_select_counts_a_dragons_combat_body() -> void:
	var d := _spawn_unit("dragon", Vector2i(-16, 0))
	var canvas: Transform2D = _pc.get_viewport().get_canvas_transform()
	# The 2D path tests feet OR combat body — a box around the combat body
	# only (feet outside, as when boxing a flyer mid-flight) must still grab it.
	var feet: Vector2 = canvas * d.global_position
	var body: Vector2 = canvas * d.get_combat_position()
	var gap := feet.distance_to(body)
	assert_gt(gap, 24.0, "the dragon's combat body sits clearly above its feet (gap %.1f px)" % gap)
	var margin := Vector2(12, minf(12.0, gap * 0.3))
	var rect := Rect2(body - margin, margin * 2.0)
	assert_false(rect.has_point(feet), "feet stay outside the body-only box")
	_pc._selection._box_select(rect.position, rect.end)
	_assert_selected_exactly([d])


func test_box_select_empty_rect_selects_nothing() -> void:
	var a := _spawn_unit("swordsman", Vector2i(-16, 0))
	var canvas: Transform2D = _pc.get_viewport().get_canvas_transform()
	var away: Vector2 = canvas * a.global_position + Vector2(500, 0)
	_pc._selection._box_select(away, away + Vector2(20, 20))
	_assert_selected_exactly([])
