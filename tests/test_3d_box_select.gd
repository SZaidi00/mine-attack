extends GutTest

# Plan 02 (plans/02-3d-box-select.md): drag-box selection in the 3D shell must
# test screen-space inclusion against the rig camera's projection — the hidden
# sim Camera2D no longer tracks the rig (dolly zoom, zoom-to-cursor, and the
# 55/82.5-degree pitches exist only on the rig), so the 2D canvas transform
# selects the wrong units from the very first drag. These tests pose the rig
# with pose_camera(), build the drag rect from a first-principles Camera3D
# projection, and assert the selected set matches exactly. The standalone 2D
# path is covered by tests/test_selection_box.gd.

const PLAYER: int = 0

var _shell: Node
var _main: Node
var _pc: Node
var _grid: Node
var _start_focus: Vector3
var _start_dolly: float


func before_all() -> void:
	seed(12345)
	GameManager.set_map_seed(7)
	_shell = load("res://scenes/main_3d.tscn").instantiate()
	get_tree().root.add_child(_shell)
	# The sim mounts deferred; wait for it (same loop as tests/test_3d_port.gd).
	for i in range(60):
		await get_tree().process_frame
		_main = get_node_or_null("/root/Main")
		if _main != null:
			break
	_pc = _main.get_node("PlayerController")
	_grid = _main.get_node("World/GridWorld")
	# current_scene must BE the shell here: real play runs with the Node3D
	# shell as current_scene, which is exactly what Presentation3D.shell()
	# detects — the box-select branch under test only arms when that resolves.
	# (Other 3D tests adopt the sim as current_scene and flip per test; box
	# selection spawns nothing, so flipping once up front is enough.)
	get_tree().current_scene = _shell
	get_viewport().warp_mouse(get_viewport().get_visible_rect().size * 0.5)
	await get_tree().process_frame
	_start_focus = _shell.get("_focus")
	_start_dolly = float(_shell.get("_dolly"))


func after_all() -> void:
	# Free immediately (not queue_free): the next test script instantiates its
	# own main.tscn and every hard-coded /root/Main lookup breaks if the name is
	# still taken. The shell frees the root-mounted sim itself in _exit_tree;
	# the extra Main check is belt-and-braces.
	_shell.free()
	_main = get_node_or_null("/root/Main")
	if _main != null:
		_main.free()
	GameManager.clear_map_seed()


func before_each() -> void:
	# Starting miners spawn deferred from each building's _ready — wipe them so
	# the "player" group holds exactly the units a test spawns.
	_clear_player_units()
	_shell.set_process(false)  # Headless edge-pan must not move the posed rig.
	_pc._selection._select_units([])


func after_each() -> void:
	_shell.set_process(true)
	var pc: PlayerController = _main.get_node("PlayerController")
	pc.set_view(false)
	_shell.pose_camera(_start_focus, _start_dolly, _shell.SURFACE_PITCH_DEGREES)


func _frames(n: int) -> void:
	for i in range(n):
		await get_tree().process_frame


func _clear_player_units() -> void:
	for u in get_tree().get_nodes_in_group("player"):
		u.free()


func _spawn_unit(unit_id: String, cell: Vector2i) -> Node2D:
	var unit: Node2D = load("res://scenes/unit.tscn").instantiate()
	unit.set("data", load("res://scripts/resources/units/%s.tres" % unit_id).duplicate(true))
	unit.set("team", PLAYER)
	unit.position = (_grid as GridWorld).grid_to_world(cell)
	_main.get_node("Units").add_child(unit)
	autofree(unit)
	return unit


## First-principles rig projection for building the expected drag rect: the
## ground-snapped point the unit proxy renders (dune height included), through
## the Camera3D — deliberately NOT Presentation3D.screen_position, so the test
## validates the helper's projection rather than reusing it.
func _project_to_screen(world2: Vector2, height_2d: float = 0.0) -> Vector2:
	var cam: Camera3D = _shell.get_node("CameraRig/Camera3D")
	var s := Presentation3D.WORLD_SCALE
	var ground := Presentation3D.ground_height(get_tree(), world2.x * s, world2.y * s)
	var p3 := Vector3(world2.x * s, ground + height_2d * s, world2.y * s)
	return cam.unproject_position(p3)


func _assert_selected_exactly(units: Array) -> void:
	var sel: Array = _pc.get_selected_units()
	assert_eq(sel.size(), units.size(), "exactly %d unit(s) selected (got %d)" % [units.size(), sel.size()])
	for u in units:
		assert_true(sel.has(u), "selection contains the enclosed unit")


# ─── Shell-mode box select ───


func test_shell_box_select_matches_the_rig_projection() -> void:
	await _frames(5)
	var a := _spawn_unit("swordsman", Vector2i(-20, 0))
	var b := _spawn_unit("swordsman", Vector2i(-16, 0))
	var c := _spawn_unit("swordsman", Vector2i(-12, 0))
	_shell.pose_camera(Presentation3D.to_3d(b.global_position), 8.0)
	var sp_a := _project_to_screen(a.global_position)
	var sp_b := _project_to_screen(b.global_position)
	var sp_c := _project_to_screen(c.global_position)
	# Drag rect hugs b's projected feet; neighbors must project well outside.
	var nearest := minf(sp_b.distance_to(sp_a), sp_b.distance_to(sp_c))
	assert_gt(nearest * 0.2, 10.0,
		"neighbor units project far enough apart for a clean rect (gap %.1f px)" % nearest)
	var margin := Vector2(minf(30.0, nearest * 0.2), minf(45.0, nearest * 0.2))
	var rect := Rect2(sp_b - margin, margin * 2.0)
	_pc._selection._box_select(rect.position, rect.end)
	_assert_selected_exactly([b])


func test_shell_box_select_follows_the_rig_when_dollied_away_from_the_2d_camera() -> void:
	await _frames(5)
	var a := _spawn_unit("swordsman", Vector2i(-16, 0))
	var b := _spawn_unit("swordsman", Vector2i(-12, 0))
	# Max zoom-out shifts the rig's projection far from the 2D camera's: the
	# sim Camera2D never moved from its default bookmark, so the two
	# projections of the same unit land in different screen places. A rect
	# built from the rig projection must select a — and would NOT under the
	# old canvas-transform path (its point for a falls outside the rect).
	_shell.pose_camera(Presentation3D.to_3d(a.global_position), 16.0)
	var sp_a := _project_to_screen(a.global_position)
	var sp_b := _project_to_screen(b.global_position)
	var canvas: Transform2D = _pc.get_viewport().get_canvas_transform()
	var sp_2d_a: Vector2 = canvas * a.global_position
	var sp_2d_b: Vector2 = canvas * b.global_position
	assert_gt(sp_a.distance_to(sp_2d_a), 40.0,
		"rig and 2D-camera projections of a diverge at max dolly (got %.1f px)" % sp_a.distance_to(sp_2d_a))
	var rect := Rect2(sp_a - Vector2(14, 14), Vector2(28, 28))
	assert_false(rect.has_point(sp_2d_a),
		"the rig-built rect excludes a's 2D-canvas point — the old path would misselect here")
	assert_false(rect.has_point(sp_2d_b), "b's 2D-canvas point is outside too")
	_pc._selection._box_select(rect.position, rect.end)
	_assert_selected_exactly([a])


func test_shell_box_select_counts_a_dragons_combat_body() -> void:
	await _frames(5)
	var d := _spawn_unit("dragon", Vector2i(-16, 0))
	_shell.pose_camera(Presentation3D.to_3d(d.global_position), 5.0)
	# The combat body rides the flight altitude straight above the feet — the
	# 2D path tests both points, so a box around the body only must still grab
	# the dragon (its feet stay outside the rect).
	var feet := _project_to_screen(d.global_position)
	var body := _project_to_screen(d.global_position, d.get_flight_altitude())
	var gap := feet.distance_to(body)
	assert_gt(gap, 24.0,
		"the dragon's combat body projects clearly above its feet (gap %.1f px)" % gap)
	var margin := Vector2(12, minf(12.0, gap * 0.3))
	var rect := Rect2(body - margin, margin * 2.0)
	assert_false(rect.has_point(feet), "feet stay outside the body-only box")
	_pc._selection._box_select(rect.position, rect.end)
	_assert_selected_exactly([d])


func test_shell_box_select_behind_camera_counts_as_outside() -> void:
	await _frames(5)
	var a := _spawn_unit("swordsman", Vector2i(-16, 0))
	_shell.pose_camera(Presentation3D.to_3d(a.global_position), 8.0)
	# A rect in a screen corner the posed rig doesn't cover: everything
	# projects outside it (behind-camera points included) — no crash, no pick.
	var vp: Vector2 = get_tree().root.get_visible_rect().size
	var rect := Rect2(vp.x - 30.0, 0.0, 30.0, 30.0)
	assert_false(rect.has_point(_project_to_screen(a.global_position)),
		"precondition: the unit's rig projection is outside the corner rect")
	_pc._selection._box_select(rect.position, rect.end)
	_assert_selected_exactly([])
