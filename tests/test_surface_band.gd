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
	for trap in get_tree().get_nodes_in_group("traps"):
		trap.free()
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
	assert_eq(GridWorld.SURFACE_ROWS, 10, "the battlefield expands to ten rows")
	assert_eq(GridWorld.SURFACE_TOP, -9, "ten rows end at y=-9 above row 0")
	var surface_cells := 0
	for pos: Vector2i in _grid._cells:
		if _grid.is_surface_row(pos.y) and pos.x >= GridWorld.X_MIN and pos.x <= GridWorld.X_MAX:
			surface_cells += 1
	assert_eq(surface_cells, 81 * GridWorld.SURFACE_ROWS, "the full grid width exists on every surface row")
	for y in range(GridWorld.SURFACE_TOP, 1):
		var cell: GridWorld.Cell = _grid.get_cell(Vector2i(-20, y))
		assert_not_null(cell, "band cell y=%d exists" % y)
		assert_eq(cell.type, GridWorld.CellType.SURFACE_GROUND, "band cell y=%d is open ground" % y)
		assert_true(_grid.is_walkable(Vector2i(-20, y)), "band cell y=%d is walkable" % y)
	assert_false(_grid.has_cell(Vector2i(-20, GridWorld.SURFACE_TOP - 1)), "no cells generate above the band")
	assert_false(_grid.is_surface_row(1), "y=1 is the mine, not the surface")
	assert_true(_grid.is_surface_row(GridWorld.SURFACE_TOP), "band top row counts as surface")


func test_building_footprint_seals_band_rows() -> void:
	# The base keeps its five-row footprint; the added rows stay open above it.
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


func test_surface_camera_bookmark_is_band_centered() -> void:
	var center_y: float = (GridWorld.SURFACE_TOP + GridWorld.SURFACE_ROWS * 0.5) * GridWorld.CELL_SIZE
	assert_almost_eq(_pc._last_surface_cam_pos.y, center_y, 0.001, "surface bookmark tracks the expanded band")
	var fresh_main: Node = load("res://scenes/main.tscn").instantiate()
	assert_almost_eq(fresh_main.get_node("Camera2D").position.y, center_y, 0.001, "the authored camera starts at the band center")
	fresh_main.free()


func test_mine_entries_use_centered_surface_cells() -> void:
	var layout: MapDefinition = _main.get("map_definition")
	assert_not_null(layout, "the main scene owns a map definition")
	var center_row: int = floori((GridWorld.SURFACE_TOP + GridWorld.Y_MIN) * 0.5)
	for entry in get_tree().get_nodes_in_group("mine_entries"):
		var expected: Vector2i = layout.player_mine_cell if entry.team == PLAYER else layout.enemy_mine_cell
		var actual: Vector2i = _grid.world_to_grid(entry.global_position)
		assert_eq(actual, expected, "map-definition cell places the %s mine" % entry.name)
		assert_eq(actual.y, center_row, "mine sits in the middle of the expanded surface band")
		assert_eq(entry.global_position, _grid.grid_to_world(actual), "entry and ladder top use the exact cell center")
		assert_eq(entry.get_ladder_top(), entry.global_position, "ladder starts at the centered entrance")
		assert_almost_eq(entry.get_ladder_bottom().x, entry.global_position.x, 0.001, "shaft stays vertically aligned")
		assert_true(_grid.is_walkable(actual), "centered surface cell remains walkable")


func test_miner_climbs_down_and_up_from_centered_entry() -> void:
	var miner: Node2D = _spawn_unit("res://scripts/resources/units/miner.tres", PLAYER, _grid.grid_to_world(Vector2i(-15, -3)))
	var entry: Node2D = _main.get_node("World/PlayerMineEntry")
	miner.climb_down_ladder()
	var reached_mine := false
	for i in range(160):
		await wait_seconds(0.05)
		if miner.is_underground:
			reached_mine = true
			break
	assert_true(reached_mine, "miner paths to the centered entrance and descends")
	if not reached_mine:
		return
	miner.climb_up_ladder()
	var reached_surface := false
	for i in range(160):
		await wait_seconds(0.05)
		if not miner.is_underground:
			reached_surface = true
			break
	assert_true(reached_surface, "miner climbs back out through the centered entrance")
	assert_lt(miner.global_position.distance_to(entry.global_position), GridWorld.CELL_SIZE, "round trip returns to the entrance cell")


func test_snow_emitters_cover_the_surface_band() -> void:
	for node_name in ["SnowParticles", "StormSnowParticles"]:
		var emitter: GPUParticles2D = _grid.get_node_or_null(node_name)
		assert_not_null(emitter, "%s exists" % node_name)
		if emitter == null:
			continue
		assert_lt(emitter.position.y, GridWorld.SURFACE_TOP * GridWorld.CELL_SIZE, "%s emits above the top row" % node_name)
		assert_gte(emitter.position.y + emitter.visibility_rect.end.y, GridWorld.CELL_SIZE, "%s visibility reaches the front lane" % node_name)


# ─── Pathfinding ───

func test_find_path_uses_the_band() -> void:
	# The base footprint blocks the direct line; either the front lane or the
	# added lanes above the base are valid detours.
	var from: Vector2 = _grid.grid_to_world(Vector2i(-38, -3))
	var to: Vector2 = _grid.grid_to_world(Vector2i(-22, -3))
	var path: PackedVector2Array = _grid.find_path(from, to, PLAYER)
	assert_gt(path.size(), 0, "a path exists around the base")
	if path.is_empty():
		return
	assert_eq(_grid.world_to_grid(path[path.size() - 1]), Vector2i(-22, -3), "path reaches the far side of the base")
	var footprint: Rect2i = _main.get_node("World/PlayerBuilding").get_footprint_cell_rect()
	for p in path:
		assert_false(footprint.has_point(_grid.world_to_grid(p)), "path never crosses the solid base footprint")


func test_find_path_above_the_base() -> void:
	var top := GridWorld.SURFACE_TOP
	var path: PackedVector2Array = _grid.find_path(_grid.grid_to_world(Vector2i(-38, top)), _grid.grid_to_world(Vector2i(-22, top)), PLAYER)
	assert_gt(path.size(), 0, "the new top lane connects across the base")
	for p in path:
		assert_eq(_grid.world_to_grid(p).y, top, "above-base route stays in the top lane")


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


func test_unit_moves_to_the_top_row() -> void:
	var unit: Node2D = _spawn_unit("res://scripts/resources/units/swordsman.tres", PLAYER, _grid.grid_to_world(Vector2i(-20, 0)))
	await wait_seconds(0.1)
	var destination: Vector2 = _grid.grid_to_world(Vector2i(-14, GridWorld.SURFACE_TOP))
	unit.move_to(destination)
	await wait_seconds(5.5)
	assert_lt(unit.global_position.distance_to(destination), GridWorld.CELL_SIZE, "the unit reaches the new top lane")


func test_units_fight_on_the_top_row() -> void:
	for unit in get_tree().get_nodes_in_group("units"):
		unit.free()
	_grid.set_reveal_all(PLAYER, true)
	_grid.set_reveal_all(ENEMY, true)
	var attacker: Node2D = _spawn_unit("res://scripts/resources/units/swordsman.tres", PLAYER, _grid.grid_to_world(Vector2i(-19, GridWorld.SURFACE_TOP)))
	var target: Node2D = _spawn_unit("res://scripts/resources/units/swordsman.tres", ENEMY, attacker.position + Vector2(16.0, 0.0))
	target.stop()
	target.set_process(false)
	attacker.attack_unit(target)
	assert_eq(attacker._target_unit, target, "explicit attack order is accepted on the top row")
	await wait_seconds(1.5)
	assert_lt(target.hp, target.data.max_hp, "surface combat reaches the added top lane")
	_grid.set_reveal_all(PLAYER, false)
	_grid.set_reveal_all(ENEMY, false)


func test_walkable_point_covers_the_band() -> void:
	var unit: Node2D = _spawn_unit("res://scripts/resources/units/swordsman.tres", PLAYER, _grid.grid_to_world(Vector2i(-20, 0)))
	assert_true(unit._is_walkable_point(_grid.grid_to_world(Vector2i(-18, GridWorld.SURFACE_TOP))), "band top row is walkable for steering")
	assert_false(unit._is_walkable_point(_grid.grid_to_world(Vector2i(-18, GridWorld.SURFACE_TOP - 1))), "above the band is not walkable")
	assert_false(unit._is_walkable_point(_grid.grid_to_world(Vector2i(-18, 3))), "undug dirt is not walkable")


# ─── Placement ───

func test_tower_places_on_band_rows() -> void:
	assert_true(_pc.try_place_structure("tower", _grid.grid_to_world(Vector2i(-12, GridWorld.SURFACE_TOP))), "tower on the top row")
	assert_false(_pc.try_place_structure("tower", _grid.grid_to_world(Vector2i(-12, 1))), "not underground")
	assert_false(_pc.try_place_structure("tower", _grid.grid_to_world(Vector2i(-12, GridWorld.SURFACE_TOP - 1))), "not above the band")


func test_wall_places_on_band_rows() -> void:
	assert_true(_pc.try_place_structure("wall", _grid.grid_to_world(Vector2i(-20, GridWorld.SURFACE_TOP))), "wall on the top row")
	assert_false(_pc.try_place_structure("wall", _grid.grid_to_world(Vector2i(-20, 2))), "not underground")


func test_lantern_places_on_band_rows() -> void:
	assert_true(_pc.try_place_structure("lantern", _grid.grid_to_world(Vector2i(-25, GridWorld.SURFACE_TOP))), "lantern on the top row")
	var lantern: Node2D = get_tree().get_nodes_in_group("lanterns")[0]
	assert_false(lantern.is_underground_lantern)


func test_trap_places_on_the_top_row() -> void:
	ResearchManager._levels[PLAYER]["guerrilla"] = 1
	assert_true(_pc.try_place_structure("trap", _grid.grid_to_world(Vector2i(-20, GridWorld.SURFACE_TOP))), "trap on the top row")
	assert_false(_pc.try_place_structure("trap", _grid.grid_to_world(Vector2i(-20, GridWorld.SURFACE_TOP - 1))), "not above the band")


func test_surface_lanterns_light_the_band_edges() -> void:
	_pc.try_place_structure("lantern", _grid.grid_to_world(Vector2i(-25, GridWorld.SURFACE_TOP)))
	var top_lantern: Node2D = get_tree().get_nodes_in_group("lanterns")[0]
	await _finish_construction(top_lantern)
	_pc.try_place_structure("lantern", _grid.grid_to_world(Vector2i(-25, 0)))
	var bottom_lantern: Node2D = get_tree().get_nodes_in_group("lanterns")[1]
	await _finish_construction(bottom_lantern)
	await wait_seconds(0.6)
	assert_true(_grid.is_visible_to(PLAYER, top_lantern.position), "top lantern lights its own top-row cell")
	assert_true(_grid.is_visible_to(PLAYER, bottom_lantern.position), "front lantern lights its own row-0 cell")


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
