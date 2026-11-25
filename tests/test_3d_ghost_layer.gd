extends GutTest

# Ghost-surface x-ray layer (GhostLayer3D): underground view shows a frozen,
## translucent hologram of the surface band — fog-known cells and structure
## marks as they stood when the view left the surface. Hidden cells stay
## empty, so the ghost never leaks unexplored information.

var _shell: Node
var _main: Node


func before_all() -> void:
	seed(12345)
	GameManager.set_map_seed(7)
	_shell = load("res://scenes/main_3d.tscn").instantiate()
	get_tree().root.add_child(_shell)
	# The sim mounts deferred; adopt it as current_scene (test_3d_port pattern).
	for i in range(60):
		await get_tree().process_frame
		_main = get_node_or_null("/root/Main")
		if _main != null:
			break
	get_tree().current_scene = _main


func after_all() -> void:
	_shell.free()
	_main = get_node_or_null("/root/Main")
	if _main != null:
		_main.free()
	GameManager.clear_map_seed()


func _frames(n: int) -> void:
	for i in range(n):
		await get_tree().process_frame


func _ghost() -> GhostLayer3D:
	return _shell.get_node("World3D/GhostLayer3D") as GhostLayer3D


func _grid() -> GridWorld:
	return _main.get_node("World/GridWorld") as GridWorld


func test_hidden_on_the_surface_view() -> void:
	await _frames(20)
	var ghost := _ghost()
	assert_not_null(ghost, "World3D stubs a GhostLayer3D node")
	if ghost == null:
		return
	assert_false(ghost.is_underground_view(), "shell starts on the surface")
	assert_null(ghost.mesh, "no ghost mesh while the live surface is showing")


func test_underground_freezes_a_surface_snapshot() -> void:
	var ghost := _ghost()
	var grid := _grid()
	ghost.set_underground_view(true)
	assert_not_null(ghost.mesh, "underground view commits a ghost mesh")
	if ghost.mesh != null:
		assert_gt(ghost.mesh.get_surface_count(), 0, "ghost mesh has a surface")
	var base: Node2D = _main.get_node("World/PlayerBuilding")
	var base_cell: Vector2i = grid.world_to_grid(base.global_position)
	assert_eq(ghost.snapshot_state_at(base_cell), 2,
		"the own base area enters the snapshot as visible")
	var far_cell := Vector2i(35, 0)
	assert_eq(ghost.snapshot_state_at(far_cell), 0,
		"a never-seen surface cell stays out of the ghost (no info leak)")
	# Frozen means frozen: flipping the live fog after the switch must not
	# change what the ghost shows.
	grid.set_reveal_all(GameManager.Team.PLAYER, true)
	assert_eq(ghost.snapshot_state_at(far_cell), 0,
		"the snapshot ignores fog changes after the freeze")
	grid.set_reveal_all(GameManager.Team.PLAYER, false)
	ghost.set_underground_view(false)


func test_structure_marks_respect_snapshot_fog() -> void:
	var ghost := _ghost()
	ghost.set_underground_view(true)
	assert_gt(ghost.mark_count(), 0, "known surface structures leave marks")
	assert_true(ghost.mark_teams().has(GameManager.Team.PLAYER),
		"the own base is marked")
	assert_false(ghost.mark_teams().has(GameManager.Team.ENEMY),
		"the unrevealed enemy base is NOT marked")
	ghost.set_underground_view(false)


func test_ghost_colors_read_as_hologram() -> void:
	var ghost := _ghost()
	assert_almost_eq(ghost.ghost_alpha_for_state(2), GhostLayer3D.ALPHA_VISIBLE, 0.001)
	assert_almost_eq(ghost.ghost_alpha_for_state(1), GhostLayer3D.ALPHA_REMEMBERED, 0.001)
	assert_eq(ghost.ghost_alpha_for_state(0), 0.0, "hidden cells contribute nothing")
	var remembered: Color = ghost.ghost_color_for_state(1)
	var visible: Color = ghost.ghost_color_for_state(2)
	assert_true(remembered.v < visible.v,
		"remembered cells sit darker than visible ones")
	assert_true(visible.b >= visible.r,
		"the ghost grades cool (ice), never warm like live terrain")


func test_surfacing_drops_the_ghost() -> void:
	var ghost := _ghost()
	ghost.set_underground_view(true)
	assert_not_null(ghost.mesh)
	ghost.set_underground_view(false)
	assert_null(ghost.mesh, "surface view clears the ghost mesh")
	assert_eq(ghost.snapshot_state_at(Vector2i(-25, 0)), -1,
		"the snapshot is dropped with the view")
	assert_eq(ghost.mark_count(), 0, "structure marks are dropped too")
