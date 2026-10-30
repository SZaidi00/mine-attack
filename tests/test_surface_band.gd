extends GutTest

# Multi-row surface battlefield: the walkable surface is a SURFACE_ROWS-deep
# band (y in [SURFACE_TOP, 0]) instead of a single row. Covers map generation,
# band pathfinding, off-row movement, band placement rules, and full-column
# wall sealing.

const PLAYER: int = 0
const ENEMY: int = 1

var _main: Node
var _grid: Node
var _pc: Node


func before_all() -> void:
	seed(12345)
	_main = load("res://scenes/main.tscn").instantiate()
	get_tree().root.add_child(_main)
	get_tree().current_scene = _main
	_grid = _main.get_node("World/GridWorld")
	_pc = _main.get_node("PlayerController")
	await wait_seconds(0.1)


func after_all() -> void:
	_main.free()


func before_each() -> void:
	EconomyManager.add_coin(PLAYER, 5000)
	ResearchManager.reset()
	for tower in get_tree().get_nodes_in_group("towers"):
		tower.free()
	for lantern in get_tree().get_nodes_in_group("lanterns"):
		lantern.free()
	for wall in get_tree().get_nodes_in_group("walls"):
		wall.free()
	for pos in _grid._wall_sealed_cells.keys():
		if _grid._astar.is_in_boundsv(pos):
			_grid._astar.set_point_solid(pos, false)
	_grid._wall_sealed_cells.clear()


func _spawn_unit(tres_path: String, team: int, pos: Vector2) -> Node2D:
	var unit: Node2D = load("res://scenes/unit.tscn").instantiate()
	unit.set("data", load(tres_path).duplicate(true))
	unit.set("team", team)
	unit.position = pos
	_main.get_node("Units").add_child(unit)
	autofree(unit)
	return unit


func _finish_construction(structure: Node2D) -> void:
	structure.set("_build_progress", structure.get("build_time"))
	await wait_seconds(0.2)


# ─── Map generation ───

func test_surface_band_is_generated_and_walkable() -> void:
	for y in range(GridWorld.SURFACE_TOP, 1):
		var cell: GridWorld.Cell = _grid.get_cell(Vector2i(-20, y))
		assert_not_null(cell, "band cell y=%d exists" % y)
		assert_eq(cell.type, GridWorld.CellType.SURFACE_GROUND, "band cell y=%d is open ground" % y)
		assert_true(_grid.is_walkable(Vector2i(-20, y)), "band cell y=%d is walkable" % y)
	assert_false(_grid.is_surface_row(1), "y=1 is the mine, not the surface")
	assert_true(_grid.is_surface_row(GridWorld.SURFACE_TOP), "band top row counts as surface")


func test_building_footprint_seals_band_rows() -> void:
	# The player base (6x5 cells above row 0) now genuinely blocks its cells.
	var rect := Rect2i()
	for b in get_tree().get_nodes_in_group("buildings"):
		if b.team == PLAYER:
			rect = b.get_footprint_cell_rect()
	assert_gt(rect.size.x, 0, "player building found")
	var solid_count: int = 0
	for x in range(rect.position.x, rect.end.x):
		for y in range(rect.position.y, rect.end.y):
			if _grid._astar.is_point_solid(Vector2i(x, y)):
				solid_count += 1
	assert_gt(solid_count, 0, "footprint cells are A*-solid")
	assert_false(_grid._astar.is_point_solid(Vector2i(rect.position.x, 0)), "row 0 in front of the base stays walkable")


# ─── Pathfinding ───

func test_find_path_uses_the_band() -> void:
	# From left of the player base to right of it on a band row: the base
	# footprint blocks the direct line, so the path must detour through row 0.
	var from: Vector2 = _grid.grid_to_world(Vector2i(-38, -3))
	var to: Vector2 = _grid.grid_to_world(Vector2i(-22, -3))
	var path: PackedVector2Array = _grid.find_path(from, to, PLAYER)
	assert_gt(path.size(), 0, "a path exists around the base")
	var dips_to_front := false
	for p in path:
		if p.y > -8.0:
			dips_to_front = true
	assert_true(dips_to_front, "the path detours in front of the base footprint")


func test_find_path_off_row_destination() -> void:
	var path: PackedVector2Array = _grid.find_path(_grid.grid_to_world(Vector2i(-20, 0)), _grid.grid_to_world(Vector2i(-14, -4)), PLAYER)
	assert_gt(path.size(), 0, "paths reach band rows above row 0")
	assert_eq(_grid.world_to_grid(path[path.size() - 1]), Vector2i(-14, -4), "path ends at the band cell")


func test_underground_path_cannot_cross_the_band() -> void:
	# The only route between the two mine shafts would be up and across the
	# surface band (the central wall blocks underground). Band sealing must
	# keep that impossible for crawlers.
	var from: Vector2 = _grid.grid_to_world(Vector2i(-15, 3))
	var to: Vector2 = _grid.grid_to_world(Vector2i(15, 3))
	var path: PackedVector2Array = _grid.find_path_underground(from, to, ENEMY)
	assert_eq(path.size(), 0, "no underground route crosses the surface band")


# ─── Movement ───

func test_unit_moves_off_row_zero() -> void:
	var unit: Node2D = _spawn_unit("res://scripts/resources/units/swordsman.tres", PLAYER, _grid.grid_to_world(Vector2i(-20, 0)))
	await wait_seconds(0.1)
	unit.move_to(_grid.grid_to_world(Vector2i(-14, -4)))
	await wait_seconds(4.0)
	assert_lt(unit.global_position.y, -32.0, "the unit left row 0 for the upper band")
	assert_lt(unit.global_position.distance_to(_grid.grid_to_world(Vector2i(-14, -4))), GridWorld.CELL_SIZE, "reached the band destination")


func test_walkable_point_covers_the_band() -> void:
	var unit: Node2D = _spawn_unit("res://scripts/resources/units/swordsman.tres", PLAYER, _grid.grid_to_world(Vector2i(-20, 0)))
	assert_true(unit._is_walkable_point(_grid.grid_to_world(Vector2i(-18, GridWorld.SURFACE_TOP))), "band top row is walkable for steering")
	assert_false(unit._is_walkable_point(_grid.grid_to_world(Vector2i(-18, GridWorld.SURFACE_TOP - 1))), "above the band is not walkable")
	assert_false(unit._is_walkable_point(_grid.grid_to_world(Vector2i(-18, 3))), "undug dirt is not walkable")


# ─── Placement ───

func test_tower_places_on_band_rows() -> void:
	assert_true(_pc.try_place_structure("tower", _grid.grid_to_world(Vector2i(-12, -3))), "tower on an upper band row")
	assert_false(_pc.try_place_structure("tower", _grid.grid_to_world(Vector2i(-12, 1))), "not underground")
	assert_false(_pc.try_place_structure("tower", _grid.grid_to_world(Vector2i(-12, GridWorld.SURFACE_TOP - 1))), "not above the band")


func test_wall_places_on_band_rows() -> void:
	assert_true(_pc.try_place_structure("wall", _grid.grid_to_world(Vector2i(-20, -2))), "wall on an upper band row")
	assert_false(_pc.try_place_structure("wall", _grid.grid_to_world(Vector2i(-20, 2))), "not underground")


func test_lantern_places_on_band_rows() -> void:
	assert_true(_pc.try_place_structure("lantern", _grid.grid_to_world(Vector2i(-25, -4))), "lantern on an upper band row")
	var lantern: Node2D = get_tree().get_nodes_in_group("lanterns")[0]
	assert_false(lantern.is_underground_lantern)


func test_surface_lantern_lights_the_band() -> void:
	_pc.try_place_structure("lantern", _grid.grid_to_world(Vector2i(-25, -3)))
	var lantern: Node2D = get_tree().get_nodes_in_group("lanterns")[0]
	await _finish_construction(lantern)
	await wait_seconds(0.6)
	assert_true(_grid.is_visible_to(PLAYER, _grid.grid_to_world(Vector2i(-25, GridWorld.SURFACE_TOP))), "lantern vision reaches the band top")
	assert_true(_grid.is_visible_to(PLAYER, _grid.grid_to_world(Vector2i(-25, 0))), "lantern vision reaches row 0")


# ─── Wall column sealing ───

func test_wall_seals_the_whole_band_column() -> void:
	_pc.try_place_structure("wall", _grid.grid_to_world(Vector2i(-20, -2)))
	var wall: Node2D = get_tree().get_nodes_in_group("walls")[0]
	await _finish_construction(wall)
	for y in range(GridWorld.SURFACE_TOP, 1):
		assert_true(_grid._astar.is_point_solid(Vector2i(-20, y)), "band row y=%d sealed" % y)
	wall.take_damage(9999)
	for y in range(GridWorld.SURFACE_TOP, 1):
		assert_false(_grid._astar.is_point_solid(Vector2i(-20, y)), "destroyed wall frees band row y=%d" % y)


func test_enemy_cannot_path_through_wall_column_anywhere_in_band() -> void:
	_pc.try_place_structure("wall", _grid.grid_to_world(Vector2i(-20, -1)))
	var wall: Node2D = get_tree().get_nodes_in_group("walls")[0]
	await _finish_construction(wall)
	# An enemy pathing past the column on any band row must detour (or fail);
	# the column itself must never appear on the path.
	var path: PackedVector2Array = _grid.find_path(_grid.grid_to_world(Vector2i(-30, -4)), _grid.grid_to_world(Vector2i(-10, -1)), ENEMY)
	for p in path:
		assert_ne(_grid.world_to_grid(p).x, -20, "path never enters the sealed column")
	# The owning team's seals lift for the query: the player paths straight
	# through the column.
	var own_path: PackedVector2Array = _grid.find_path(_grid.grid_to_world(Vector2i(-30, -4)), _grid.grid_to_world(Vector2i(-10, -1)), PLAYER)
	assert_gt(own_path.size(), 0, "the wall never blocks its owning team")
