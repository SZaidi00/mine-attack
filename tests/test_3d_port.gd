extends GutTest

# Phase 1 2.5D port (roadmap/3d-conversion/phase-1-25d-port.md):
# the main_3d shell mounts the untouched sim at /root/Main, projects the
# grid as 3D terrain, and mirrors live units/structures with proxies —
# with zero changes to simulation code.

var _shell: Node
var _main: Node


func before_all() -> void:
	seed(12345)
	GameManager.set_map_seed(7)
	_shell = load("res://scenes/main_3d.tscn").instantiate()
	get_tree().root.add_child(_shell)


func after_all() -> void:
	# Free immediately (not queue_free): the next test script instantiates
	# its own main.tscn and every hard-coded /root/Main lookup breaks if the
	# name is still taken — the sim is a child of the tree root, NOT of the
	# shell, so it must be freed explicitly.
	_main = get_node_or_null("/root/Main")
	if _main != null:
		_main.free()
	_shell.free()
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
