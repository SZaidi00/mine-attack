extends GutTest

# Plan 13 (plans/13-underground-and-sentry-vision.md §3): excavated cells gain
# presentation-only floors — cold depth-strata colors, small deterministic
# hash variation, fog tinting identical to normal cells, subtle seam strips
# under the lava-glow/fog-overlay lifts, and zero sim mutation from forced
# underground rebuilds. House boot/shutdown style from test_3d_terrain_art.gd.

var _shell: Node
var _main: Node


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
	# The sim mounts deferred; wait for it, then adopt it as current_scene
	# (house style from test_3d_port.gd).
	for i in range(60):
		await get_tree().process_frame
		_main = get_node_or_null("/root/Main")
		if _main != null:
			break
	get_tree().current_scene = _main
	(_main.get_node("World/GridWorld") as GridWorld).set_dynamic_events_enabled(false)


func after_all() -> void:
	# Restore any forced weather state and the scheduling flags the autoloads
	# keep across scene reloads, then free immediately (not queue_free) so the
	# next test script's /root/Main lookup isn't shadowed (house style).
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


func after_each() -> void:
	var grid := _grid()
	if grid != null:
		grid.set_reveal_all(GameManager.Team.PLAYER, false)
	_terrain().set_underground_view(false)


func _frames(n: int) -> void:
	for i in range(n):
		await get_tree().process_frame


func _terrain() -> Node:
	return _shell.get_node("World3D/Terrain3D")


func _grid() -> GridWorld:
	return _main.get_node("World/GridWorld") as GridWorld


func _chunk_arrays(terrain: Node, pos: Vector2i) -> Array:
	var chunk: MeshInstance3D = terrain._chunks[terrain._chunk_key_for(pos)]
	if chunk.mesh == null or chunk.mesh.get_surface_count() == 0:
		return []
	return chunk.mesh.surface_get_arrays(0)


## Component-wise color match tolerant of the mesh's 8-bit vertex-color
## quantization (1/255 per channel) plus float noise.
func _color_matches(a: Color, b: Color, tol := 0.006) -> bool:
	return absf(a.r - b.r) <= tol and absf(a.g - b.g) <= tol \
		and absf(a.b - b.b) <= tol and absf(a.a - b.a) <= tol


## True when the chunk holding `pos` renders a vertex of `color` (the flat
## floor quad) — geometry presence proof for excavated floors.
func _chunk_has_color(terrain: Node, pos: Vector2i, color: Color) -> bool:
	var arrays := _chunk_arrays(terrain, pos)
	if arrays.is_empty():
		return false
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var cols: PackedColorArray = arrays[Mesh.ARRAY_COLOR]
	for i in range(verts.size()):
		if _color_matches(cols[i], color):
			return true
	return false


## Lowest Y among the chunk vertices tinted `color` (floor quads sit at 0).
func _min_y_of_color(terrain: Node, pos: Vector2i, color: Color) -> float:
	var arrays := _chunk_arrays(terrain, pos)
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var cols: PackedColorArray = arrays[Mesh.ARRAY_COLOR]
	var best := 1e9
	for i in range(verts.size()):
		if _color_matches(cols[i], color):
			best = minf(best, verts[i].y)
	return best


func test_excavated_floor_predicate_separates_tunnels_from_absent_data() -> void:
	await _frames(20)
	var terrain := _terrain()
	var grid := _grid()
	terrain.set_underground_view(true)
	await _frames(5)
	# The two initial shafts (x=±15, y 1..6) are mined-out in-bounds cells.
	for y in range(1, 7):
		assert_true(terrain._is_excavated_floor(Vector2i(-15, y)),
			"initial player shaft cell %d is an excavated floor" % y)
		assert_true(terrain._is_excavated_floor(Vector2i(15, y)),
			"initial enemy shaft cell %d is an excavated floor" % y)
	# Surface row, out-of-bounds columns, and present cells never qualify.
	assert_false(terrain._is_excavated_floor(Vector2i(-15, GridWorld.Y_MIN)),
		"surface-band rows are never floors")
	assert_false(terrain._is_excavated_floor(Vector2i(GridWorld.X_MIN - 1, 3)),
		"out-of-bounds columns are never floors")
	assert_false(terrain._is_excavated_floor(Vector2i(-16, 3)),
		"a present underground cell is not excavated space")
	assert_false(terrain._is_excavated_floor(Vector2i(-15, GridWorld.Y_MAX + 1)),
		"the border floor row (a real wall cell) is not excavated space")
	terrain.set_underground_view(false)
	await _frames(5)
	assert_false(terrain._is_excavated_floor(Vector2i(-15, 3)),
		"the surface view never draws floors")
	terrain.set_underground_view(true)


func test_initial_shafts_grow_floor_geometry_with_depth_strata_colors() -> void:
	await _frames(20)
	var terrain := _terrain()
	var grid := _grid()
	grid.set_reveal_all(GameManager.Team.PLAYER, true)
	terrain.set_underground_view(true)
	await _frames(40)
	# Excavate one cell per depth band next to the player shaft.
	var samples: Array[Vector2i] = [Vector2i(-15, 2), Vector2i(-16, 8), Vector2i(-16, 14)]
	for pos in samples:
		if grid.has_cell(pos):
			grid.damage_cell(pos, 100000, 3)
		assert_true(terrain._is_excavated_floor(pos),
			"mined cell %s reads as excavated floor" % pos)
	await _frames(35)
	for pos in samples:
		var expected: Color = terrain._floor_color(pos)
		assert_true(_chunk_has_color(terrain, pos, expected),
			"excavated cell %s renders its floor quad" % pos)
		assert_almost_eq(_min_y_of_color(terrain, pos, expected), 0.0, 0.0001,
			"floor quad for %s sits on the flat underground plane" % pos)


func test_floor_colors_differ_from_dirt_rock_and_void() -> void:
	await _frames(10)
	var terrain := _terrain()
	var shallow: Color = terrain._floor_color(Vector2i(-15, 1))
	var mid: Color = terrain._floor_color(Vector2i(-15, 8))
	var deep: Color = terrain._floor_color(Vector2i(-15, 14))
	# Depth bands are distinct and stable.
	assert_ne(shallow, mid, "shallow and mid floors differ")
	assert_ne(mid, deep, "mid and deep floors differ")
	assert_eq(shallow, terrain._floor_color(Vector2i(-15, 1)),
		"floor colors are deterministic across calls")
	# Every band stays distinct from dirt, solid rock, and the fog void.
	for i in range(3):
		var c: Color = [shallow, mid, deep][i]
		assert_ne(c, terrain._dirt_color(1), "floor differs from shallow dirt")
		assert_ne(c, terrain._dirt_color(3), "floor differs from mid dirt")
		assert_ne(c, terrain._dirt_color(6), "floor differs from deep dirt")
		assert_ne(c, ArtStyle3D.PALETTE.rock_dark, "floor differs from solid rock")
		assert_ne(c, ArtStyle3D.PALETTE.fog_void, "floor differs from the void tint")
		assert_gt(c.b, c.r, "floors stay on the cold side of the palette")


func test_floor_fog_tinting_matches_cell_semantics() -> void:
	await _frames(10)
	var terrain := _terrain()
	var grid := _grid()
	var pos := Vector2i(-15, 2)
	# Visible: the raw strata color comes through.
	grid.set_reveal_all(GameManager.Team.PLAYER, true)
	assert_eq(grid.fog_state_at(GameManager.Team.PLAYER, pos), 2, "fixture starts visible")
	assert_eq(terrain._excavated_floor_color(pos), terrain._floor_color(pos),
		"visible floors keep their strata color")
	# Hidden: the opaque void tint (the fog overlay keeps the floor covered).
	grid.set_reveal_all(GameManager.Team.PLAYER, false)
	var hidden := Vector2i(15, 3)
	assert_eq(grid.fog_state_at(GameManager.Team.PLAYER, hidden), 0,
		"fixture: the enemy shaft starts never-seen")
	assert_eq(terrain._excavated_floor_color(hidden), ArtStyle3D.PALETTE.fog_void,
		"hidden floors take the void tint")
	# Remembered: dimmed toward the deep-rock shadow, exactly like a cell.
	var team: int = GameManager.Team.PLAYER
	var xi: int = hidden.x - GridWorld.X_MIN
	var yi: int = hidden.y - GridWorld.SURFACE_TOP
	grid._memory_maps[team][xi][yi] = GameManager.match_time
	assert_eq(grid.fog_state_at(GameManager.Team.PLAYER, hidden), 1,
		"fixture: a fresh last-seen memory reads as remembered")
	assert_eq(terrain._excavated_floor_color(hidden),
		terrain._floor_color(hidden).lerp(ArtStyle3D.PALETTE.rock_dark, 0.8),
		"remembered floors dim exactly like remembered cells")
	grid._memory_maps[team][xi][yi] = -1.0


func test_floor_seams_are_subtle_lifted_and_deterministic() -> void:
	await _frames(10)
	var terrain := _terrain()
	var grid := _grid()
	# Lift invariants: seams sit above the floor but under the lava glow (0.004)
	# and the fog overlay (0.06) — never Z-fighting either.
	assert_eq(terrain.FLOOR_SEAM_LIFT, 0.002, "seams lift exactly 0.002")
	assert_lt(terrain.FLOOR_SEAM_LIFT, terrain.GLOW_LIFT,
		"seams stay under the lava glow lift")
	assert_lt(terrain.FLOOR_SEAM_LIFT, Fog3D.UNDERGROUND_LIFT,
		"seams stay under the fog overlay lift")
	# The seam decision is a pure, stable hash.
	var pos := Vector2i(-15, 2)
	var first: bool = terrain._has_floor_seam(pos)
	for i in range(3):
		assert_eq(terrain._has_floor_seam(pos), first, "seam decision is deterministic")
	# Seeded shafts carry at least one seam cell whose chunk renders the lift.
	grid.set_reveal_all(GameManager.Team.PLAYER, true)
	terrain.set_underground_view(true)
	await _frames(40)
	var seam_found := false
	for y in range(1, 7):
		var p := Vector2i(-15, y)
		if terrain._has_floor_seam(p):
			seam_found = true
			var arrays := _chunk_arrays(terrain, p)
			var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			var at_lift := false
			for v in verts:
				if absf(v.y - terrain.FLOOR_SEAM_LIFT) < 0.0005:
					at_lift = true
			assert_true(at_lift, "seam cell %s renders geometry at the seam lift" % p)
	assert_true(seam_found, "seed 7 gives the initial shaft at least one seam cell")


func test_forced_underground_rebuilds_leave_sim_untouched() -> void:
	await _frames(20)
	var terrain := _terrain()
	var grid := _grid()
	# A sim mutation (mining) is expected; rendering must not add any more.
	grid.damage_cell(Vector2i(-16, 4), 100000, 3)
	var before := _sim_signature(grid)
	terrain.set_underground_view(true)
	await _frames(40)
	terrain.force_full_rebuild()
	await _frames(40)
	assert_eq(_sim_signature(grid), before,
		"forced underground rebuilds leave cells and A* untouched")


func test_same_seed_rebuilds_give_identical_floor_colors_and_seams() -> void:
	await _frames(20)
	var terrain := _terrain()
	var grid := _grid()
	terrain.set_underground_view(true)
	await _frames(40)
	var cells: Array[Vector2i] = []
	for x in [-15, 15]:
		for y in range(1, 7):
			cells.append(Vector2i(x, y))
	var record := func() -> Array:
		var out: Array = []
		for c in cells:
			out.append([terrain._floor_color(c), terrain._has_floor_seam(c),
				terrain._is_excavated_floor(c)])
		return out
	var first: Array = record.call()
	terrain.force_full_rebuild()
	await _frames(40)
	assert_eq(record.call(), first,
		"a forced rebuild replays identical floor colors and seam decisions")
	terrain.force_full_rebuild()
	await _frames(40)
	assert_eq(record.call(), first,
		"a second forced rebuild stays identical")


func _sim_signature(grid: GridWorld) -> Dictionary:
	var signature: Dictionary = {}
	for pos: Vector2i in grid._cells:
		var cell: GridWorld.Cell = grid._cells[pos]
		signature[pos] = [cell.type, cell.hp, cell.coin_remaining, grid._astar.is_point_solid(pos)]
	return signature
