extends GutTest

# 3D fog-of-war mist overlay (scripts/three_d/fog_3d.gd): a translucent mist
# bank over cells the player cannot see, replacing the 2.5D port's black-cell
# terrain tint. Feathered edges via corner-averaged vertex alpha, reveal-all
# hides the overlay, and Tab switches the covered layer.

var _shell: Node
var _main: Node


func before_all() -> void:
	seed(12345)
	GameManager.set_map_seed(7)
	_shell = load("res://scenes/main_3d.tscn").instantiate()
	get_tree().root.add_child(_shell)
	# The sim mounts deferred; wait for it, then adopt it as current_scene (same
	# pattern as test_3d_port.gd).
	for i in range(60):
		await get_tree().process_frame
		_main = get_node_or_null("/root/Main")
		if _main != null:
			break
	get_tree().current_scene = _main


func after_all() -> void:
	# Free immediately (not queue_free): the next test script instantiates its
	# own scene and every hard-coded /root/Main lookup breaks otherwise.
	_shell.free()
	_main = get_node_or_null("/root/Main")
	if _main != null:
		_main.free()
	GameManager.clear_map_seed()


func _frames(n: int) -> void:
	for i in range(n):
		await get_tree().process_frame


func _fog() -> Fog3D:
	return _shell.get_node("World3D/Fog3D") as Fog3D


func _grid() -> GridWorld:
	return _main.get_node("World/GridWorld") as GridWorld


func test_fog_node_exists_and_builds_mesh() -> void:
	await _frames(30)
	var fog := _fog()
	assert_not_null(fog, "World3D has a Fog3D overlay node")
	if fog == null:
		return
	assert_not_null(fog.mesh, "fog overlay commits a mesh")
	if fog.mesh != null:
		assert_gt(fog.mesh.get_surface_count(), 0, "fog mesh has a surface")


func test_hidden_cells_have_higher_alpha_than_visible() -> void:
	await _frames(30)
	var fog := _fog()
	var grid := _grid()
	var base: Node2D = _main.get_node("World/PlayerBuilding")
	var base_cell: Vector2i = grid.world_to_grid(base.global_position)
	assert_eq(grid.fog_state_at(GameManager.Team.PLAYER, base_cell), 2,
		"precondition: the player base cell is visible")
	var far_cell := Vector2i(35, 0)
	assert_eq(grid.fog_state_at(GameManager.Team.PLAYER, far_cell), 0,
		"precondition: enemy-side surface cell is unexplored")
	# The overlay refreshes on a 0.5s real-time poll; rebuild explicitly so the
	# alphas reflect the vision state asserted above, not the setup-time state.
	fog._rebuild()
	assert_lt(fog.alpha_at_cell(base_cell), fog.alpha_at_cell(far_cell),
		"unexplored cells carry more mist than visible ones")
	assert_almost_eq(fog.alpha_at_cell(base_cell), 0.0, 0.001, "visible cells are clear")
	assert_gt(fog.alpha_at_cell(far_cell), 0.9, "unexplored cells are nearly opaque mist")


func test_reveal_all_hides_the_overlay() -> void:
	await _frames(10)
	var fog := _fog()
	var grid := _grid()
	grid.set_reveal_all(GameManager.Team.PLAYER, true)
	fog._rebuild()
	assert_null(fog.mesh, "reveal-all drops the mist overlay entirely")
	grid.set_reveal_all(GameManager.Team.PLAYER, false)
	fog._rebuild()
	assert_not_null(fog.mesh, "overlay returns when reveal-all is lifted")


func test_underground_view_switches_layer() -> void:
	await _frames(10)
	var fog := _fog()
	assert_false(fog.is_underground_view(), "starts on the surface layer")
	fog.set_underground_view(true)
	assert_true(fog.is_underground_view(), "Tab switches the mist to the mine layer")
	assert_not_null(fog.mesh, "underground layer still has a mist mesh")
	fog.set_underground_view(false)
	assert_false(fog.is_underground_view())
