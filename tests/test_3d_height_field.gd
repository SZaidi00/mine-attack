extends GutTest

# R3 height-field surface (roadmap/3d-visual-revamp/03-technical-plan.md §2):
# the terrain's surface quads displace onto a deterministic, map-seeded dune
# field (value noise + ridged bands), structures/walls/mine entries stamp
# clearances so buildings sit clean, storms flatten the relief, and the
# underground floor stays flat. All presentation; the sim stays untouched
# (house style from test_3d_terrain_art.gd).

var _shell: Node
var _main: Node
var _grid: GridWorld


func before_all() -> void:
	seed(12345)
	GameManager.set_map_seed(7)
	# No random weather/lava/cave-in rolls mid-test; forced triggers only.
	WeatherManager.set_weather_events_enabled(false)
	WeatherManager.set_volcano_events_enabled(false)
	WeatherManager.force_snowstorm_end()
	WeatherManager.force_volcano_end()
	_shell = load("res://scenes/main_3d.tscn").instantiate()
	get_tree().root.add_child(_shell)
	# The sim mounts deferred; wait for it (house style from test_3d_port.gd).
	for i in range(60):
		await get_tree().process_frame
		_main = get_node_or_null("/root/Main")
		if _main != null:
			break
	get_tree().current_scene = _main
	_grid = _main.get_node("World/GridWorld") as GridWorld
	_grid.set_dynamic_events_enabled(false)


func after_all() -> void:
	WeatherManager.force_snowstorm_end()
	WeatherManager.force_volcano_end()
	WeatherManager.set_weather_events_enabled(true)
	WeatherManager.set_volcano_events_enabled(true)
	var grid: GridWorld = get_node_or_null("/root/Main/World/GridWorld") as GridWorld
	if grid != null:
		grid.set_dynamic_events_enabled(true)
	_shell.free()
	_main = get_node_or_null("/root/Main")
	if _main != null:
		_main.free()
	GameManager.clear_map_seed()


func _frames(n: int) -> void:
	for i in range(n):
		await get_tree().process_frame


func _field() -> HeightField3D:
	return (_shell.get_node("World3D/Terrain3D") as Node).height_field


## Sample a spread of open surface-band points (world units), avoiding wall
## cells, and return the [min, max] heights.
func _open_ground_range(field: HeightField3D) -> Array:
	var min_h := 1e9
	var max_h := -1e9
	for gx in range(GridWorld.X_MIN, GridWorld.X_MAX + 1):
		for gy in range(GridWorld.SURFACE_TOP, GridWorld.Y_MIN + 1):
			var cell: GridWorld.Cell = _grid.get_cell(Vector2i(gx, gy))
			if cell == null or cell.type != GridWorld.CellType.SURFACE_GROUND:
				continue
			var h: float = field.height_at_cell(gx + 0.5, gy + 0.5)
			min_h = minf(min_h, h)
			max_h = maxf(max_h, h)
	return [min_h, max_h]


func test_field_is_deterministic_for_the_same_seed() -> void:
	var a := _field()
	var b := HeightField3D.new()
	b.setup(_grid)
	for gx in range(GridWorld.X_MIN, GridWorld.X_MAX + 1, 3):
		for gy in range(GridWorld.SURFACE_TOP, GridWorld.Y_MIN + 1):
			assert_eq(a.height_at_cell(gx + 0.25, gy + 0.5), b.height_at_cell(gx + 0.25, gy + 0.5),
				"same map seed -> same dune heights at (%d, %d)" % [gx, gy])


func test_different_seed_changes_the_dunes() -> void:
	var a := _field()
	var b := HeightField3D.new()
	b.setup(_grid)
	b._seed = 1234
	var diffs := 0
	for gx in range(GridWorld.X_MIN, GridWorld.X_MAX + 1, 3):
		for gy in range(GridWorld.SURFACE_TOP, GridWorld.Y_MIN + 1):
			if not is_equal_approx(a.height_at_cell(gx + 0.25, gy + 0.5), b.height_at_cell(gx + 0.25, gy + 0.5)):
				diffs += 1
	assert_gt(diffs, 10, "a different seed reshapes the dune field")


func test_dunes_respect_the_height_budget_and_roll() -> void:
	var field := _field()
	field.set_storm_level(0.0)
	var range: Array = _open_ground_range(field)
	assert_gt(range[1] - range[0], 0.03, "open ground rolls (dunes vary across the band)")
	assert_lte(range[1], HeightField3D.DUNE_HEIGHT + 0.001, "dune peaks stay within the 0.4-cell budget")
	assert_gte(range[0], -HeightField3D.DUNE_HEIGHT * 0.6, "dune dips stay near the budget floor")


func test_structure_clearances_flatten_the_ground() -> void:
	var field := _field()
	field.refresh_clearances()
	# The mine entry stamps its clearance: the ground under and next to it is
	# trampled flat, while the far corner of the map still rolls.
	var entry: Node2D = _main.get_node("World/PlayerMineEntry")
	var at: float = field.height_at(entry.global_position.x * 0.01, entry.global_position.y * 0.01)
	assert_almost_eq(at, 0.0, 0.01, "mine entry footing is flat")
	var range: Array = _open_ground_range(field)
	assert_gt(range[1] - range[0], 0.03, "dunes still roll away from the clearances")


func test_underground_and_off_map_stay_flat() -> void:
	var field := _field()
	assert_eq(field.height_at_cell(0.5, 3.5), 0.0, "underground floor is flat")
	assert_eq(field.height_at_cell(-100.0, -50.0), 0.0, "off-map queries are flat")


func test_storm_flattens_the_dune_relief() -> void:
	var field := _field()
	field.set_storm_level(0.0)
	var calm: Array = _open_ground_range(field)
	field.set_storm_level(1.0)
	var stormy: Array = _open_ground_range(field)
	assert_lt(stormy[1] - stormy[0], (calm[1] - calm[0]) * 0.6,
		"a settled storm visibly fills the dunes")


func test_terrain_world_height_at_answers_from_the_field() -> void:
	var terrain: Node = _shell.get_node("World3D/Terrain3D")
	var field := _field()
	for gx in [-30, -10, 0, 10, 30]:
		var wx: float = (gx + 0.5) * GridWorld.CELL_SIZE * 0.01
		var wz: float = (GridWorld.SURFACE_TOP + 2.5) * GridWorld.CELL_SIZE * 0.01
		assert_almost_eq(terrain.world_height_at(wx, wz), field.height_at(wx, wz), 0.0001,
			"world_height_at matches the shared field at x=%d" % gx)
