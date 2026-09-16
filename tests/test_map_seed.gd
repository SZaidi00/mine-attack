extends GutTest

# Map seeding: the same seed rebuilds the same map (ore layout, central wall
# pool, rolled profile), different seeds roll different maps, a user-pinned
# (locked) seed survives re-instantiation, and an unlocked match rolls a fresh
# seed that is written back to GameManager for the settings panel / match log.

var _main: Node


func before_all() -> void:
	GameManager.set_map_seed(12345)


func after_all() -> void:
	if is_instance_valid(_main):
		_main.free()
	GameManager.clear_map_seed()


func _spawn_main() -> Node:
	if is_instance_valid(_main):
		_main.free()
	_main = load("res://scenes/main.tscn").instantiate()
	get_tree().root.add_child(_main)
	get_tree().current_scene = _main
	return _main


func _ore_count(grid: Node) -> int:
	var n: int = 0
	for pos: Vector2i in grid._cells:
		if grid._cells[pos].type == GridWorld.CellType.ORE:
			n += 1
	return n


func test_same_seed_rebuilds_same_map_and_profile() -> void:
	_main = _spawn_main()
	var grid_a: Node = _main.get_node("World/GridWorld")
	var ore_a: int = _ore_count(grid_a)
	var wall_a: int = grid_a._wall_max_hp
	var profile_a: Dictionary = grid_a.map_profile.duplicate()
	var seed_a: int = grid_a.map_seed

	# Same pinned seed: free and reload — everything must match.
	_main = _spawn_main()
	var grid_b: Node = _main.get_node("World/GridWorld")
	assert_eq(grid_b.map_seed, seed_a, "pinned seed is used as-is")
	assert_eq(_ore_count(grid_b), ore_a, "same seed -> identical ore layout")
	assert_eq(grid_b._wall_max_hp, wall_a, "same seed -> identical wall pool")
	assert_eq(grid_b.map_profile, profile_a, "same seed -> identical rolled profile")
	assert_true(GameManager.map_seed_locked, "pinned seed stays locked")


func test_different_seeds_roll_different_maps() -> void:
	var counts: Array = []
	for s in range(1, 5):
		GameManager.set_map_seed(s)
		_main = _spawn_main()
		counts.append(_ore_count(_main.get_node("World/GridWorld")))
	var all_same: bool = true
	for i in range(1, counts.size()):
		if counts[i] != counts[0]:
			all_same = false
	assert_false(all_same, "seeds 1-4 do not all produce the same ore layout (%s)" % str(counts))


func test_unlocked_match_rolls_fresh_seed_and_reports_it() -> void:
	GameManager.clear_map_seed()
	_main = _spawn_main()
	var grid: Node = _main.get_node("World/GridWorld")
	assert_false(GameManager.map_seed_locked, "no user pin")
	assert_eq(grid.map_seed, GameManager.map_seed, "rolled seed is written back to GameManager")
	assert_gt(grid.map_seed, 0, "rolled seed is a positive value")


func test_wall_pool_comes_from_profile_multiplier() -> void:
	GameManager.set_map_seed(777)
	_main = _spawn_main()
	var grid: Node = _main.get_node("World/GridWorld")
	var mult: float = grid.map_profile.get("wall_hp_mult", -1.0)
	assert_true(mult in Constants.MAP_WALL_HP_MULTS, "wall multiplier comes from the tier table")
	assert_eq(grid._wall_max_hp, roundi(GridWorld.WALL_HP_BASE * mult), "wall pool = base HP x profile multiplier")
	assert_eq(grid.get_wall_hp(), grid._wall_max_hp, "pool starts full")


func test_ore_curve_comes_from_profile_table() -> void:
	GameManager.set_map_seed(777)
	_main = _spawn_main()
	var grid: Node = _main.get_node("World/GridWorld")
	assert_true(Constants.MAP_ORE_CURVES.values().has(grid.map_profile.get("ore_curve")), "ore curve is one of the table entries")
