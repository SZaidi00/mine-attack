extends GutTest

# Build-placement fix: while the 3D shell runs the scene, the placement
# preview is a BuildGhost3D at the snapped cell (centered in the gold range
# disc) with the green/red validity tint — the old 2D GhostVisual sprite drew
# in the sim's stale 2D camera space, floating off the disc. Also covers the
# construction grow: an unbuilt tower's proxy rises out of the ground instead
# of standing full height at construction alpha.

const PLAYER: int = 0

var _shell: Node
var _main: Node


func before_all() -> void:
	seed(12345)
	GameManager.set_map_seed(7)
	_shell = load("res://scenes/main_3d.tscn").instantiate()
	get_tree().root.add_child(_shell)
	# The sim mounts deferred; wait for it. Real 3D play keeps the shell as
	# current_scene — required here so Presentation3D.shell() resolves and the
	# placement code takes its 3D branch.
	for i in range(60):
		await get_tree().process_frame
		_main = get_node_or_null("/root/Main")
		if _main != null:
			break
	get_tree().current_scene = _shell


func after_all() -> void:
	get_tree().current_scene = null
	_shell.free()
	_main = get_node_or_null("/root/Main")
	if _main != null:
		_main.free()
	GameManager.clear_map_seed()
	EconomyManager.reset()


func before_each() -> void:
	GameManager.game_active = true


func _frames(n: int) -> void:
	for i in range(n):
		await get_tree().process_frame


func _pc() -> PlayerController:
	return _main.get_node("PlayerController")


# ─── Ghost model unit behavior ───


func test_ghost_validity_swaps_material() -> void:
	var ghost := BuildGhost3D.create("tower")
	assert_true(ghost.is_valid, "ghost starts valid (green)")
	ghost.set_valid(false)
	assert_false(ghost.is_valid)
	var mat := (ghost.get_child(0) as MeshInstance3D).get_material_override() as StandardMaterial3D
	assert_not_null(mat)
	assert_true(mat.albedo_color.r > mat.albedo_color.g, "invalid ghost tints red")
	assert_true(mat.albedo_color.a < 1.0, "ghost stays translucent")
	ghost.free()


# ─── Shell-mode placement ghost ───


func test_shell_placement_uses_3d_ghost_not_2d_sprite() -> void:
	var pc: PlayerController = _pc()
	pc.start_build_placement("tower")
	await _frames(2)
	assert_not_null(pc._build_ghost, "2D ghost node still tracks state")
	assert_null(pc._build_ghost.get_node_or_null("GhostVisual"),
		"no 2D sprite while the 3D shell runs")
	assert_not_null(pc._build_placement._ghost_3d, "3D ghost created")
	assert_not_null(pc._build_placement._range_disc_3d, "range disc created")
	assert_eq(pc._build_placement._ghost_3d.get_parent(), _shell.get_node("World3D/Effects3D"))
	pc.cancel_build_mode()
	await _frames(2)
	assert_null(pc._build_placement._ghost_3d, "cancel frees the 3D ghost")
	assert_null(pc._build_placement._range_disc_3d, "cancel frees the disc")


func test_ghost_sits_at_the_disc_center_cell() -> void:
	var pc: PlayerController = _pc()
	get_viewport().warp_mouse(get_viewport().get_visible_rect().size * 0.5)
	pc.start_build_placement("tower")
	await _frames(2)
	var ghost: BuildGhost3D = pc._build_placement._ghost_3d
	assert_not_null(ghost)
	if ghost == null:
		pc.cancel_build_mode()
		return
	# Same snapped ground point as the disc and the sim-side ghost node.
	assert_lt(ghost.position.distance_to(pc._build_placement._range_disc_3d.position), 0.001,
		"ghost is centered in the range disc")
	var cell: Vector2i = pc._grid.world_to_grid(pc._build_ghost.global_position)
	var expected := Presentation3D.to_3d(pc._grid.grid_to_world(cell))
	assert_lt(ghost.position.distance_to(expected), 0.001,
		"ghost sits at the snapped cell's 3D point")
	pc.cancel_build_mode()


func test_ghost_validity_tracks_placement_error() -> void:
	var pc: PlayerController = _pc()
	get_viewport().warp_mouse(get_viewport().get_visible_rect().size * 0.5)
	pc.start_build_placement("tower")
	await _frames(2)
	var ghost: BuildGhost3D = pc._build_placement._ghost_3d
	assert_not_null(ghost)
	if ghost == null:
		pc.cancel_build_mode()
		return
	var cell: Vector2i = pc._grid.world_to_grid(pc._build_ghost.global_position)
	var err: String = pc._build_placement._placement_error("tower", cell)
	assert_eq(ghost.is_valid, err == "", "ghost tint mirrors _placement_error")
	pc.cancel_build_mode()


# ─── Construction grow ───


func _find_valid_tower_cell(pc: PlayerController) -> Vector2i:
	for x in range(-2, -40, -1):
		for y in range(GridWorld.SURFACE_TOP, 1):
			var cell := Vector2i(x, y)
			if pc._build_placement._placement_error("tower", cell) == "":
				return cell
	return Vector2i(-999, -999)


func _find_tower_proxy() -> StructureProxy3D:
	for child in _shell.get_node("World3D/Structures3D").get_children():
		if child is StructureProxy3D and child.entity is Tower:
			return child
	return null


func test_unbuilt_tower_proxy_grows_out_of_the_ground() -> void:
	var pc: PlayerController = _pc()
	EconomyManager.add_coin(PLAYER, 1000)
	var cell := _find_valid_tower_cell(pc)
	assert_true(cell.x > -100, "precondition: a valid tower cell exists")
	if cell.x <= -100:
		return
	assert_true(pc.try_place_structure("tower", pc._grid.grid_to_world(cell)), "placement accepted")
	var proxy: StructureProxy3D = null
	for i in range(30):
		await get_tree().process_frame
		proxy = _find_tower_proxy()
		if proxy != null:
			break
	assert_not_null(proxy, "tower proxy spawned on reconcile")
	if proxy == null:
		return
	assert_lt(proxy.scale.y, proxy._root_scale * 0.9,
		"unbuilt tower is squashed (growing), not a full-height hologram")
	# Finish construction instantly; the proxy must restore full height.
	var tower: Tower = proxy.entity
	tower._build_progress = tower.build_time
	await _frames(4)
	assert_true(tower.is_built())
	assert_almost_eq(proxy.scale.y, proxy._root_scale, 0.001,
		"built tower restored to full height")
	tower.demolish()
	await _frames(2)
