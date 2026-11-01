extends GutTest

# Chained walls (plan 16): adjacent same-team walls link into a post-and-rail
# chain (4-adjacent cells, built state irrelevant), mixed teams never link,
# destruction/demolition refreshes the neighbors, and the 3D proxy mirrors
# the connection set at reconcile time. Boots the real main.tscn.

const PLAYER: int = 0
const ENEMY: int = 1

var _main: Node
var _grid: GridWorld
var _pc: PlayerController
var _structures: Node


func before_all() -> void:
	seed(12345)
	_main = load("res://scenes/main.tscn").instantiate()
	get_tree().root.add_child(_main)
	get_tree().current_scene = _main
	_grid = _main.get_node("World/GridWorld")
	_pc = _main.get_node("PlayerController")
	_structures = _main.get_node("Structures")
	await wait_seconds(0.1)


func after_all() -> void:
	_main.free()


func before_each() -> void:
	EconomyManager.add_coin(PLAYER, 5000)
	for wall in get_tree().get_nodes_in_group("walls"):
		wall.free()
	for pos in _grid._wall_sealed_cells.keys():
		if _grid._astar.is_in_boundsv(pos):
			_grid._astar.set_point_solid(pos, false)
	_grid._wall_sealed_cells.clear()


func _wall_at(cell: Vector2i) -> WallSegment:
	for wall in get_tree().get_nodes_in_group("walls"):
		if wall.get_cell() == cell:
			return wall
	return null


func _place(cell: Vector2i) -> void:
	assert_true(_pc.try_place_structure("wall", _grid.grid_to_world(cell)), "wall places at %s" % str(cell))


## Walls are invulnerable while under construction — jump the build so
## take_damage can actually destroy them.
func _finish(wall: WallSegment) -> void:
	wall.set("_build_progress", wall.get("build_time"))
	await wait_seconds(0.2)


func test_adjacent_row_walls_link() -> void:
	_place(Vector2i(-20, 0))
	_place(Vector2i(-19, 0))
	_place(Vector2i(-18, 0))
	assert_eq(_wall_at(Vector2i(-19, 0)).get_connections(),
		{"left": true, "right": true, "up": false, "down": false}, "the middle links both ways")
	assert_eq(_wall_at(Vector2i(-20, 0)).get_connections(),
		{"left": false, "right": true, "up": false, "down": false}, "the left end links inward only")
	assert_eq(_wall_at(Vector2i(-18, 0)).get_connections(),
		{"left": true, "right": false, "up": false, "down": false}, "the right end links inward only")


func test_band_row_neighbors_link() -> void:
	_place(Vector2i(-20, 0))
	_place(Vector2i(-20, -1))
	assert_eq(_wall_at(Vector2i(-20, 0)).get_connections()["up"], true, "the row above links")
	assert_eq(_wall_at(Vector2i(-20, -1)).get_connections()["down"], true, "the row below links back")


func test_diagonal_and_gap_do_not_link() -> void:
	_place(Vector2i(-20, 0))
	_place(Vector2i(-19, -1))
	_place(Vector2i(-17, 0))
	assert_eq(_wall_at(Vector2i(-20, 0)).get_connections(),
		{"left": false, "right": false, "up": false, "down": false}, "a diagonal neighbor does not chain")
	assert_eq(_wall_at(Vector2i(-17, 0)).get_connections(),
		{"left": false, "right": false, "up": false, "down": false}, "a one-cell gap does not chain")


func test_mixed_teams_do_not_link() -> void:
	_place(Vector2i(-20, 0))
	var enemy_wall: WallSegment = load("res://scenes/wall_segment.tscn").instantiate()
	enemy_wall.team = GameManager.Team.ENEMY
	enemy_wall.global_position = _grid.grid_to_world(Vector2i(-19, 0))
	_structures.add_child(enemy_wall)
	autofree(enemy_wall)
	assert_false(_wall_at(Vector2i(-20, 0)).get_connections()["right"],
		"an enemy wall next door never becomes part of the chain")


func test_destroy_updates_neighbors() -> void:
	_place(Vector2i(-20, 0))
	_place(Vector2i(-19, 0))
	_place(Vector2i(-18, 0))
	var left: WallSegment = _wall_at(Vector2i(-20, 0))
	var right: WallSegment = _wall_at(Vector2i(-18, 0))
	await _finish(_wall_at(Vector2i(-19, 0)))
	_wall_at(Vector2i(-19, 0)).take_damage(9999)
	assert_false(left.get_connections()["right"], "the left neighbor unlinks")
	assert_false(right.get_connections()["left"], "the right neighbor unlinks")


func test_demolish_updates_neighbors() -> void:
	_place(Vector2i(-20, 0))
	_place(Vector2i(-19, 0))
	_wall_at(Vector2i(-20, 0)).demolish()
	assert_eq(_wall_at(Vector2i(-19, 0)).get_connections(),
		{"left": false, "right": false, "up": false, "down": false}, "the survivor stands alone")


func test_3d_proxy_links_follow_connections() -> void:
	_place(Vector2i(-20, 0))
	var wall: WallSegment = _wall_at(Vector2i(-20, 0))
	var proxy := StructureProxy3D.create(wall, _grid)
	autofree(proxy)
	proxy.refresh(false)
	assert_eq(proxy._wall_links.get_child_count(), 2, "a lone wall renders two x-side stubs")
	assert_almost_eq(proxy._wall_links.get_child(0).mesh.size.x, StructureProxy3D.CELL * 0.2, 0.001,
		"stubs are short")

	_place(Vector2i(-19, 0))
	proxy.refresh(false)
	var rails: float = 0.0
	var stubs: float = 0.0
	for child in proxy._wall_links.get_children():
		if child.mesh.size.x > StructureProxy3D.CELL * 0.3:
			rails += 1
		else:
			stubs += 1
	assert_eq(rails, 1, "the connected side renders one full half-rail")
	assert_eq(stubs, 1, "the open side keeps its stub")

	var neighbor: WallSegment = _wall_at(Vector2i(-19, 0))
	await _finish(neighbor)
	neighbor.take_damage(9999)
	proxy.refresh(false)
	assert_eq(proxy._wall_links.get_child_count(), 2, "the neighbor's fall restores both stubs")
	assert_almost_eq(proxy._wall_links.get_child(1).mesh.size.x, StructureProxy3D.CELL * 0.2, 0.001)
