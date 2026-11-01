extends GutTest

# Plan 13 (plans/13-underground-and-sentry-vision.md §4): TerrainDetail3D
# grows fog-honest underground decoration — timber support frames on visible
# DIRT cells bordering excavated floors and sparse curated pebble rubble on
# solid rock / depleted ore. The underground_log manifest must be deterministic
# per pinned seed, visible-only, Potato-gated, inside cell bounds, and never
# mutate sim cells/A*. House boot/shutdown style from test_3d_scatter.gd.

const BOUNDS_EPS := 0.006

var _shell: Node
var _main: Node
var _saved_quality: int


func before_all() -> void:
	_saved_quality = ArtStyle3D.quality


func after_all() -> void:
	ArtStyle3D.apply_quality(_saved_quality)


func after_each() -> void:
	_shutdown()


func _boot(map_seed: int) -> void:
	seed(12345)
	GameManager.set_map_seed(map_seed)
	# No random weather/lava/cave-in rolls mid-test; forced triggers only.
	WeatherManager.set_weather_events_enabled(false)
	WeatherManager.set_volcano_events_enabled(false)
	WeatherManager.force_snowstorm_end()
	WeatherManager.force_volcano_end()
	_shell = load("res://scenes/main_3d.tscn").instantiate()
	get_tree().root.add_child(_shell)
	# The sim mounts deferred; wait for it, then adopt it as current_scene
	# (house style from test_3d_terrain_art.gd).
	for i in range(60):
		await get_tree().process_frame
		_main = get_node_or_null("/root/Main")
		if _main != null:
			break
	get_tree().current_scene = _main
	(_main.get_node("World/GridWorld") as GridWorld).set_dynamic_events_enabled(false)
	await _frames(45)


func _shutdown() -> void:
	# Restore the forced weather state and the scheduling flags the autoloads
	# keep across scene reloads, then free immediately (not queue_free) so the
	# next boot's /root/Main lookup isn't shadowed (house style).
	WeatherManager.force_snowstorm_end()
	WeatherManager.force_volcano_end()
	WeatherManager.set_weather_events_enabled(true)
	WeatherManager.set_volcano_events_enabled(true)
	var grid: GridWorld = get_node_or_null("/root/Main/World/GridWorld") as GridWorld
	if grid != null:
		grid.set_dynamic_events_enabled(true)
	if _shell != null:
		_shell.free()
		_shell = null
	_main = get_node_or_null("/root/Main")
	if _main != null:
		_main.free()
		_main = null
	GameManager.clear_map_seed()


func _frames(n: int) -> void:
	for i in range(n):
		await get_tree().process_frame


func _terrain() -> Node:
	return _shell.get_node("World3D/Terrain3D")


func _grid() -> GridWorld:
	return _main.get_node("World/GridWorld") as GridWorld


func _detail() -> TerrainDetail3D:
	return _terrain().get_node("TerrainDetail") as TerrainDetail3D


func _cell_of(xf: Transform3D) -> Vector2i:
	return _grid().world_to_grid(Vector2(xf.origin.x, xf.origin.z) / TerrainDetail3D.WORLD_SCALE)


func _cell_center(cell: Vector2i) -> Vector3:
	var c: Vector2 = _grid().grid_to_world(cell)
	return Vector3(c.x * TerrainDetail3D.WORLD_SCALE, 0.0, c.y * TerrainDetail3D.WORLD_SCALE)


func _log_entry_count(log: Dictionary) -> int:
	var n := 0
	for key in log:
		for kind in log[key]:
			n += (log[key][kind] as Array).size()
	return n


func _go_underground() -> void:
	_grid().set_reveal_all(GameManager.Team.PLAYER, true)
	_terrain().set_underground_view(true)
	await _frames(40)


func test_same_seed_rebuilds_identical_underground_log() -> void:
	await _boot(7)
	await _go_underground()
	var first: Dictionary = _detail().underground_log
	assert_gt(_log_entry_count(first), 0, "seed 7 grows underground decoration")
	_terrain().force_full_rebuild()
	await _frames(40)
	assert_eq(_detail().underground_log, first,
		"same seed → identical underground transforms across rebuilds")


func test_different_seed_grows_a_different_board() -> void:
	await _boot(7)
	await _go_underground()
	var seed_seven: Dictionary = _detail().underground_log
	assert_gt(_log_entry_count(seed_seven), 0, "seed 7 grows underground decoration")
	_shutdown()
	await _boot(11)
	await _go_underground()
	var seed_eleven: Dictionary = _detail().underground_log
	assert_gt(_log_entry_count(seed_eleven), 0, "seed 11 grows underground decoration")
	assert_ne(seed_eleven, seed_seven, "different pinned seeds decorate differently")


func test_supports_only_on_visible_dirt_adjacent_to_excavated_cells() -> void:
	await _boot(7)
	await _go_underground()
	var grid := _grid()
	var detail := _detail()
	var count := 0
	for key in detail.underground_log:
		var kinds: Dictionary = detail.underground_log[key]
		if not kinds.has("support_post"):
			continue
		count += (kinds["support_post"] as Array).size()
		for xf in kinds["support_post"]:
			var cell := _cell_of(xf)
			assert_gt(cell.y, GridWorld.Y_MIN, "support %s stays underground" % cell)
			assert_eq(grid.fog_state_at(GameManager.Team.PLAYER, cell), 2,
				"support %s sits on a fog-visible cell" % cell)
			assert_true(grid.has_cell(cell), "support %s sits on an existing cell" % cell)
			assert_eq(grid.get_cell(cell).type, GridWorld.CellType.DIRT,
				"support %s stands on a DIRT cell" % cell)
			assert_ne(detail._excavated_neighbor(cell), Vector2i.ZERO,
				"support %s is adjacent to an excavated floor" % cell)
	assert_gt(count, 0, "the revealed shafts grow at least one support frame")


func test_no_decoration_on_hidden_remembered_or_surface_cells() -> void:
	await _boot(7)
	# No reveal-all: only genuinely visible cells may carry decoration.
	_terrain().set_underground_view(true)
	await _frames(40)
	var grid := _grid()
	var detail := _detail()
	for key in detail.underground_log:
		for kind in detail.underground_log[key]:
			for xf in detail.underground_log[key][kind]:
				var cell := _cell_of(xf)
				assert_gt(cell.y, GridWorld.Y_MIN,
					"%s never lands on the surface band" % kind)
				assert_eq(grid.fog_state_at(GameManager.Team.PLAYER, cell), 2,
					"%s at %s stays off hidden/remembered cells" % [kind, cell])
	# Revealing the map grows the decoration, still entirely on visible cells.
	grid.set_reveal_all(GameManager.Team.PLAYER, true)
	_terrain().force_full_rebuild()
	await _frames(40)
	var count := 0
	for key in detail.underground_log:
		for kind in detail.underground_log[key]:
			for xf in detail.underground_log[key][kind]:
				count += 1
				var cell := _cell_of(xf)
				assert_eq(grid.fog_state_at(GameManager.Team.PLAYER, cell), 2,
					"revealed %s at %s still sits on a fog-visible cell" % [kind, cell])
	assert_gt(count, 0, "the revealed shafts grow underground decoration")


func test_pebbles_use_only_curated_keys_and_sit_on_rock_cells() -> void:
	await _boot(7)
	await _go_underground()
	var grid := _grid()
	# Cave-in rubble: nine SOLID_ROCK cells near the player shaft.
	var center := Vector2i(-30, 12)
	grid.force_cave_in(center)
	_terrain().force_full_rebuild()
	await _frames(40)
	var detail := _detail()
	var saw_pebble := false
	for key in detail.underground_log:
		var kinds: Dictionary = detail.underground_log[key]
		for kind in kinds:
			if kind == "support_post" or kind == "support_lintel":
				continue
			assert_true(TerrainDetail3D.UNDERGROUND_PEBBLE_KEYS.has(kind),
				"only the three curated pebble keys appear, found %s" % kind)
			for xf in kinds[kind]:
				saw_pebble = true
				var cell := _cell_of(xf)
				assert_true(grid.has_cell(cell),
					"pebble at %s anchors on an existing cell (never a missing floor center)" % cell)
				var t: int = grid.get_cell(cell).type
				var allowed: bool = t == GridWorld.CellType.SOLID_ROCK \
					or t == GridWorld.CellType.MAGMA_ROCK \
					or (t == GridWorld.CellType.ORE and GridMining.is_depleted(grid.get_cell(cell)))
				assert_true(allowed, "pebble at %s sits on rubble-bearing rock, found type %d" % [cell, t])
	assert_true(saw_pebble, "seed 7 cave-in rock picks up at least one rubble pebble")
	# Restoring the cave-in removes the rubble cells' decoration basis.
	grid._events._cavein_restore_left = 0.0
	await _frames(5)


func test_support_and_pebble_geometry_stays_inside_cell_bounds() -> void:
	await _boot(7)
	await _go_underground()
	var grid := _grid()
	var center := Vector2i(-30, 12)
	grid.force_cave_in(center)
	_terrain().force_full_rebuild()
	await _frames(40)
	var detail := _detail()
	for key in detail.underground_log:
		var kinds: Dictionary = detail.underground_log[key]
		for kind in kinds:
			for xf in kinds[kind]:
				var cell := _cell_of(xf)
				var c := _cell_center(cell)
				if kind == "support_post" or kind == "support_lintel":
					# Axis-aligned unit boxes: the scale is the footprint.
					var half: Vector3 = xf.basis.get_scale() * 0.5
					assert_lt(absf(xf.origin.x - c.x) + half.x, GridWorld.CELL_SIZE * 0.5 * TerrainDetail3D.WORLD_SCALE + BOUNDS_EPS,
						"%s at %s stays inside its cell (x)" % [kind, cell])
					assert_lt(absf(xf.origin.z - c.z) + half.z, GridWorld.CELL_SIZE * 0.5 * TerrainDetail3D.WORLD_SCALE + BOUNDS_EPS,
						"%s at %s stays inside its cell (z)" % [kind, cell])
				else:
					var source := TerrainDetail3D._prop_source(str(kind))
					if source.is_empty():
						continue
					var aabb := _transformed_aabb((source["mesh"] as Mesh), xf)
					assert_lt(absf((aabb.position.x + aabb.size.x * 0.5) - c.x) + aabb.size.x * 0.5,
						GridWorld.CELL_SIZE * 0.5 * TerrainDetail3D.WORLD_SCALE + BOUNDS_EPS,
						"pebble at %s stays inside its cell (x)" % cell)
					assert_lt(absf((aabb.position.z + aabb.size.z * 0.5) - c.z) + aabb.size.z * 0.5,
						GridWorld.CELL_SIZE * 0.5 * TerrainDetail3D.WORLD_SCALE + BOUNDS_EPS,
						"pebble at %s stays inside its cell (z)" % cell)
					assert_almost_eq(aabb.position.y, 0.0, 0.01,
						"pebble at %s keeps its base on the flat floor" % cell)
					assert_lt(aabb.position.y + aabb.size.y, 0.16,
						"pebble at %s stays in the debris height band" % cell)
	grid._events._cavein_restore_left = 0.0
	await _frames(5)


func test_potato_grows_no_underground_decoration() -> void:
	await _boot(7)
	await _go_underground()
	assert_gt(_log_entry_count(_detail().underground_log), 0,
		"precondition: the default quality decorates the underground")
	ArtStyle3D.apply_quality(ArtStyle3D.Quality.POTATO)
	_terrain().force_full_rebuild()
	await _frames(40)
	assert_eq(_log_entry_count(_detail().underground_log), 0,
		"Potato grows no supports or rubble (the detail_enabled gate)")


func test_underground_detail_rebuild_does_not_mutate_sim() -> void:
	await _boot(7)
	var grid := _grid()
	grid.damage_cell(Vector2i(-21, 4), 100000, 3)
	grid.force_cave_in(Vector2i(-30, 12))
	await _go_underground()
	var before := _sim_signature(grid)
	_terrain().force_full_rebuild()
	await _frames(40)
	assert_eq(_sim_signature(grid), before,
		"underground detail rebuilds leave cells and A* untouched")
	grid._events._cavein_restore_left = 0.0


## World-space AABB of a mesh under a transform (8-corner expansion; AABB has
## no built-in transform operator in GDScript).
func _transformed_aabb(mesh: Mesh, xf: Transform3D) -> AABB:
	var b := mesh.get_aabb()
	var out := AABB(xf * b.position, Vector3.ZERO)
	for i in range(8):
		var corner := b.position + Vector3(
			b.size.x * float(i & 1), b.size.y * float((i >> 1) & 1), b.size.z * float((i >> 2) & 1))
		out = out.expand(xf * corner)
	return out


func _sim_signature(grid: GridWorld) -> Dictionary:
	var signature: Dictionary = {}
	for pos: Vector2i in grid._cells:
		var cell: GridWorld.Cell = grid._cells[pos]
		signature[pos] = [cell.type, cell.hp, cell.coin_remaining, grid._astar.is_point_solid(pos)]
	return signature
