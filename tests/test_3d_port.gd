extends GutTest

# Phase 1 2.5D port (roadmap/3d-conversion/phase-1-25d-port.md):
# the main_3d shell mounts the untouched sim at /root/Main, projects the
# grid as 3D terrain, and mirrors live units/structures with proxies —
# with zero changes to simulation code.

class FakeEnemyStructure:
	extends Node2D
	var team: GameManager.Team = GameManager.Team.ENEMY

var _shell: Node
var _main: Node


func before_all() -> void:
	seed(12345)
	GameManager.set_map_seed(7)
	_shell = load("res://scenes/main_3d.tscn").instantiate()
	get_tree().root.add_child(_shell)
	# The sim mounts deferred; wait for it, then adopt it as current_scene so
	# sim-spawned popups parent somewhere valid (in real play current_scene
	# is the shell, owned by the menu/game-over scene flow).
	for i in range(60):
		await get_tree().process_frame
		_main = get_node_or_null("/root/Main")
		if _main != null:
			break
	get_tree().current_scene = _main


func after_all() -> void:
	# Free immediately (not queue_free): the next test script instantiates
	# its own main.tscn and every hard-coded /root/Main lookup breaks if the
	# name is still taken. The shell frees the root-mounted sim itself in
	# _exit_tree; the extra Main check is belt-and-braces.
	_shell.free()
	_main = get_node_or_null("/root/Main")
	if _main != null:
		_main.free()
	GameManager.clear_map_seed()


func _frames(n: int) -> void:
	for i in range(n):
		await get_tree().process_frame


func test_sim_mounted_at_root_main_with_2d_layers_hidden() -> void:
	await _frames(30)
	_main = get_node_or_null("/root/Main")
	assert_not_null(_main, "shell mounts the untouched sim at /root/Main")
	if _main == null:
		return
	assert_false(_main.get_node("World").visible, "2D world drawing hidden")
	assert_false(_main.get_node("Units").visible, "2D unit sprites hidden")
	assert_true(_main.get_node("UI").visible, "HUD CanvasLayer stays visible")


func test_terrain_chunks_build_for_surface_view() -> void:
	await _frames(30)
	var terrain: Node = _shell.get_node("World3D/Terrain3D")
	var built := 0
	for chunk in terrain.get_children():
		if (chunk as MeshInstance3D).mesh != null and chunk.mesh.get_surface_count() > 0:
			built += 1
	assert_gt(built, 0, "surface-view chunks have committed meshes")


func test_tab_view_rebuilds_terrain_for_underground() -> void:
	await _frames(30)
	var terrain: Node = _shell.get_node("World3D/Terrain3D")
	terrain.set_underground_view(true)
	await _frames(10)
	var built := 0
	for chunk in terrain.get_children():
		if (chunk as MeshInstance3D).mesh != null and chunk.mesh.get_surface_count() > 0:
			built += 1
	assert_gt(built, 0, "underground-view chunks rebuild")
	terrain.set_underground_view(false)


func test_unit_proxies_mirror_live_units() -> void:
	# Starting miners spawn deferred from each building's _ready.
	await _frames(90)
	var units := get_tree().get_nodes_in_group("units")
	var proxies: int = _shell.get_node("World3D/Units3D").get_child_count()
	assert_gt(units.size(), 0, "sim has live units")
	assert_eq(proxies, units.size(), "one 3D proxy per live unit")


func test_structure_proxies_cover_base_structures() -> void:
	await _frames(30)
	var structures: int = _shell.get_node("World3D/Structures3D").get_child_count()
	# 2 buildings + 2 mine entries + 1 ladder per mine entry (runtime-spawned).
	assert_eq(structures, 6, "base structures get proxies incl. ladders")


func test_enemy_structure_proxy_respects_fog() -> void:
	await _frames(10)
	var grid: GridWorld = _main.get_node("World/GridWorld") as GridWorld
	var cell := Vector2i(35, 0)
	assert_eq(grid.fog_state_at(GameManager.Team.PLAYER, cell), 0,
		"precondition: enemy-side surface cell is unexplored")
	# No sim group: the reconcile pass must not adopt this fake; the generic
	# stand-in branch is enough to exercise the fog path.
	var fake := FakeEnemyStructure.new()
	_main.add_child(fake)
	fake.global_position = grid.grid_to_world(cell)
	var proxy := StructureProxy3D.create(fake, grid)
	_shell.get_node("World3D/Structures3D").add_child(proxy)
	proxy.refresh(false)
	assert_false(proxy.visible, "enemy structure at an unexplored cell is hidden in 3D")
	proxy.free()
	fake.free()
