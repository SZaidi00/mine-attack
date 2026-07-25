extends GutTest

# GridWorld: ore trickle + destruction (coin, astar), wall shared-HP
# accounting, and walkability helpers around the building footprint
# (the Phase 1 "path to a solid footprint cell" bug, pinned by a test).

const PLAYER: int = 0

var _main: Node
var _grid: Node


func before_all() -> void:
	_main = load("res://scenes/main.tscn").instantiate()
	get_tree().root.add_child(_main)
	get_tree().current_scene = _main
	_grid = _main.get_node("World/GridWorld")


func after_all() -> void:
	_main.queue_free()


func _find_cell_of_type(type: int, x_from: int = -40, x_to: int = -2) -> Vector2i:
	for x in range(x_from, x_to):
		for y in range(1, 22):
			var cell = _grid.get_cell(Vector2i(x, y))
			if cell != null and cell.type == type:
				return Vector2i(x, y)
	return Vector2i(-9999, -9999)


func test_ore_trickles_every_swing_and_pays_exact_total() -> void:
	var pos: Vector2i = _find_cell_of_type(3)  # ORE
	assert_ne(pos, Vector2i(-9999, -9999), "map has ore")
	var expected: int = _grid.get_cell(pos).coin_value
	var total: int = 0
	var paying_swings: int = 0
	var swings: int = 0
	while _grid.get_cell(pos) != null and swings < 100:
		var got: int = _grid.damage_cell(pos, 5, 3)
		swings += 1
		total += got
		if got > 0:
			paying_swings += 1
	assert_eq(total, expected, "tile yields exactly coin_value")
	assert_gt(paying_swings, 1, "gold trickles per swing, not just on destruction")
	assert_true(_grid.is_walkable(pos), "destroyed tile clears its A* solid")


func test_dirt_pays_nothing_but_becomes_walkable() -> void:
	var pos: Vector2i = _find_cell_of_type(2)  # DIRT
	assert_ne(pos, Vector2i(-9999, -9999), "map has dirt")
	var swings: int = 0
	var total: int = 0
	while _grid.get_cell(pos) != null and swings < 100:
		total += _grid.damage_cell(pos, 5, 3)
		swings += 1
	assert_eq(total, 0)
	assert_true(_grid.is_walkable(pos))


func test_miner_level_gate_blocks_damage() -> void:
	# Find a layer-3+ tile (requires miner level 2).
	var pos: Vector2i = Vector2i(-9999, -9999)
	for x in range(-40, -2):
		for y in range(1, 22):
			var cell = _grid.get_cell(Vector2i(x, y))
			if cell != null and cell.type == 2 and cell.miner_level_required >= 2:
				pos = Vector2i(x, y)
				break
		if pos.x != -9999:
			break
	assert_ne(pos, Vector2i(-9999, -9999), "map has a level-gated tile")
	var hp_before: int = _grid.get_cell(pos).hp
	assert_eq(_grid.damage_cell(pos, 5, 1), 0, "level 1 miner cannot dig layer 3")
	assert_eq(_grid.get_cell(pos).hp, hp_before, "no damage dealt")


func test_wall_shared_hp_pool() -> void:
	var wall_cells: Array = _grid.get_wall_cells()
	assert_gt(wall_cells.size(), 0)
	var hp_before: int = _grid.get_wall_hp()
	_grid.damage_cell(wall_cells[0], 10, 1)
	assert_eq(_grid.get_wall_hp(), hp_before - 10, "damage scales with miner level x1")
	_grid.damage_cell(wall_cells[5], 10, 3)
	assert_eq(_grid.get_wall_hp(), hp_before - 40, "a different wall cell drains the same pool")
	assert_eq(_grid.get_cell(wall_cells[0]) != null, true, "wall cells stay until the pool hits 0")


func test_nearest_walkable_cell_around_building_footprint() -> void:
	var building: Node2D = null
	for b in get_tree().get_nodes_in_group("buildings"):
		if b.get("team") == PLAYER:
			building = b
	var rect: Rect2i = building.call("get_footprint_cell_rect")
	var ring: Array = _grid.cells_adjacent_to_rect(rect)
	assert_gt(ring.size(), 0, "walkable ring around the footprint")
	for cell in ring:
		assert_true(_grid.is_walkable(cell), "ring cell %s is walkable" % str(cell))
	# The footprint's own (solid) center must resolve to a walkable cell.
	var resolved: Vector2i = _grid.nearest_walkable_cell(rect.get_center())
	assert_true(_grid.is_walkable(resolved), "footprint center resolves to walkable")


func test_dug_tiles_never_regenerate() -> void:
	var pos: Vector2i = _find_cell_of_type(2)
	assert_ne(pos, Vector2i(-9999, -9999))
	while _grid.get_cell(pos) != null:
		_grid.damage_cell(pos, 50, 3)
	assert_eq(_grid.damage_cell(pos, 50, 3), 0, "erased cell stays erased")
	assert_false(_grid.has_cell(pos))
