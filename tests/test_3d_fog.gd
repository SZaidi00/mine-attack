extends GutTest

# R6 fog-of-war: opaque unexplored void, deep-shadow remembered cells,
# RGBA-feathered edges, preset-independent darkness, reveal-all, and Tab layers.

var _shell: Node
var _main: Node


func before_all() -> void:
	seed(12345)
	GameManager.set_map_seed(7)
	_shell = load("res://scenes/main_3d.tscn").instantiate()
	get_tree().root.add_child(_shell)
	# The sim mounts deferred; wait for it, then adopt it as current_scene (same
	# pattern as test_3d_port.gd).
	for i in range(60):
		await get_tree().process_frame
		_main = get_node_or_null("/root/Main")
		if _main != null:
			break
	get_tree().current_scene = _main


func after_all() -> void:
	# Free immediately (not queue_free): the next test script instantiates its
	# own scene and every hard-coded /root/Main lookup breaks otherwise.
	_shell.free()
	_main = get_node_or_null("/root/Main")
	if _main != null:
		_main.free()
	GameManager.clear_map_seed()


func _frames(n: int) -> void:
	for i in range(n):
		await get_tree().process_frame


func _fog() -> Fog3D:
	return _shell.get_node("World3D/Fog3D") as Fog3D


func _grid() -> GridWorld:
	return _main.get_node("World/GridWorld") as GridWorld


func test_fog_node_exists_and_builds_mesh() -> void:
	await _frames(30)
	var fog := _fog()
	assert_not_null(fog, "World3D has a Fog3D overlay node")
	if fog == null:
		return
	assert_not_null(fog.mesh, "fog overlay commits a mesh")
	if fog.mesh != null:
		assert_gt(fog.mesh.get_surface_count(), 0, "fog mesh has a surface")


func test_hidden_cells_are_opaque_void_and_visible_cells_are_clear() -> void:
	await _frames(30)
	var fog := _fog()
	var grid := _grid()
	var base: Node2D = _main.get_node("World/PlayerBuilding")
	var base_cell: Vector2i = grid.world_to_grid(base.global_position)
	var far_cell := Vector2i(35, 0)
	assert_eq(grid.fog_state_at(GameManager.Team.PLAYER, base_cell), 2)
	assert_eq(grid.fog_state_at(GameManager.Team.PLAYER, far_cell), 0)
	fog._rebuild()
	assert_almost_eq(fog.alpha_at_cell(base_cell), Fog3D.ALPHA_VISIBLE, 0.001)
	assert_almost_eq(fog.alpha_at_cell(far_cell), Fog3D.ALPHA_HIDDEN, 0.001)
	assert_eq(fog.color_at_cell(far_cell), Color(Fog3D.VOID_COLOR, 1.0),
		"unexplored surface uses the exact void token")


func test_remembered_cells_use_deep_shadow() -> void:
	var fog := _fog()
	var grid := _grid()
	var cell := Vector2i(35, 0)
	var ix: int = cell.x - GridWorld.X_MIN
	var iy: int = cell.y - GridWorld.SURFACE_TOP
	var previous: float = grid._memory_maps[GameManager.Team.PLAYER][ix][iy]
	grid._memory_maps[GameManager.Team.PLAYER][ix][iy] = GameManager.match_time
	assert_eq(grid.fog_state_at(GameManager.Team.PLAYER, cell), 1)
	fog._rebuild()
	assert_eq(fog.color_at_cell(cell), Color(Fog3D.SHADOW_COLOR, Fog3D.ALPHA_REMEMBERED),
		"explored-but-unlit cells use the deep-rock shadow treatment")
	grid._memory_maps[GameManager.Team.PLAYER][ix][iy] = previous
	fog._rebuild()


func test_underground_hidden_cells_use_the_same_opaque_void() -> void:
	var fog := _fog()
	var grid := _grid()
	fog.set_underground_view(true)
	var far_cell := Vector2i(35, 10)
	assert_eq(grid.fog_state_at(GameManager.Team.PLAYER, far_cell), 0)
	assert_eq(fog.color_at_cell(far_cell), Color(Fog3D.VOID_COLOR, 1.0))
	assert_not_null(fog.mesh, "underground layer still has a fog mesh")
	fog.set_underground_view(false)
	assert_false(fog.is_underground_view())


func test_corner_averaging_feathers_rgba() -> void:
	var fog := _fog()
	# Synthesize the four states around vertex (10, 10) directly in the
	# per-column state grid: visible at (9,9), remembered at (9,10), hidden
	# at (10,9) and (10,10). Columns/rows are indexed from the one-cell skirt.
	fog._states.clear()
	for x in range(GridWorld.X_MIN - 1, GridWorld.X_MAX + 2):
		var col: Array = []
		col.resize(GridWorld.Y_MAX - GridWorld.SURFACE_TOP + 3)
		col.fill(0)
		fog._states.append(col)
	var x0 := GridWorld.X_MIN - 1
	var y0 := GridWorld.SURFACE_TOP - 1
	fog._states[9 - x0][9 - y0] = 2
	fog._states[9 - x0][10 - y0] = 1
	var expected := (Color(1.0, 1.0, 1.0, 0.0)
		+ Color(Fog3D.VOID_COLOR, 1.0)
		+ Color(Fog3D.SHADOW_COLOR, Fog3D.ALPHA_REMEMBERED)
		+ Color(Fog3D.VOID_COLOR, 1.0)) * 0.25
	var actual := fog._vertex_color(10, 10)
	assert_almost_eq(actual.r, expected.r, 0.001)
	assert_almost_eq(actual.g, expected.g, 0.001)
	assert_almost_eq(actual.b, expected.b, 0.001)
	assert_almost_eq(actual.a, expected.a, 0.001)
	fog._rebuild()


func test_shader_noise_vanishes_at_clear_and_opaque_endpoints() -> void:
	assert_string_contains(Fog3D._SHADER_CODE, "sin(PI * base_alpha)",
		"edge weight is zero when alpha is zero or one")
	assert_string_contains(Fog3D._SHADER_CODE, "base_alpha + drift",
		"noise offsets only the feathered transition, never hidden-cell opacity")


func test_void_and_shadow_are_identical_on_every_quality_preset() -> void:
	var fog := _fog()
	var grid := _grid()
	var previous := ArtStyle3D.quality
	var far_cell := Vector2i(35, 0)
	for quality in [ArtStyle3D.Quality.POTATO, ArtStyle3D.Quality.STANDARD, ArtStyle3D.Quality.FANCY]:
		ArtStyle3D.apply_quality(quality)
		fog.setup(grid)
		assert_eq(fog.color_at_cell(far_cell), Color(Fog3D.VOID_COLOR, 1.0))
		var drift: float = fog._mat.get_shader_parameter("drift_enabled")
		assert_eq(drift, 0.0 if quality == ArtStyle3D.Quality.POTATO else 1.0,
			"only edge animation changes by preset")
	ArtStyle3D.apply_quality(previous)
	fog.setup(grid)


func test_reveal_all_hides_the_overlay() -> void:
	await _frames(10)
	var fog := _fog()
	var grid := _grid()
	grid.set_reveal_all(GameManager.Team.PLAYER, true)
	fog._rebuild()
	assert_null(fog.mesh, "reveal-all drops the fog overlay entirely")
	grid.set_reveal_all(GameManager.Team.PLAYER, false)
	fog._rebuild()
	assert_not_null(fog.mesh, "overlay returns when reveal-all is lifted")


# ─── Fog-diff-cap telemetry (plans/01) ───
# A reveal burst past the sim's change-accumulator cap must set the overflow
# flag (with a counted warning), and one Fog3D refresh must restore every
# cell's visual state — no stale tint after an overflowed revision.

## Two synchronous detection passes: first pins the underground half of the
## player fog maps to a known hidden baseline (prev-state bookkeeping), then
## flips it all visible — a reveal burst far past PLAYER_FOG_CHANGE_CAP, same
## as a big lantern reveal or wall breach live. Deterministic regardless of
## how many live frames ran before it (GUT can chain tests within one frame).
func _force_fog_overflow(grid: GridWorld) -> void:
	grid.consume_player_fog_changes()
	grid.consume_player_fog_overflow()
	var vision: Array = grid._vision_maps[GameManager.Team.PLAYER]
	var memory: Array = grid._memory_maps[GameManager.Team.PLAYER]
	for ix in range(vision.size()):
		for iy in range(vision[ix].size()):
			if iy + grid.SURFACE_TOP > grid.Y_MIN:
				vision[ix][iy] = false
				memory[ix][iy] = -1.0
	grid._fog._detect_player_fog_changes()
	grid.consume_player_fog_changes()
	grid.consume_player_fog_overflow()
	for ix in range(vision.size()):
		for iy in range(vision[ix].size()):
			if iy + grid.SURFACE_TOP > grid.Y_MIN:
				vision[ix][iy] = true
	grid._fog._detect_player_fog_changes()


func test_change_burst_past_cap_sets_overflow_flag_and_caps_the_list() -> void:
	var grid := _grid()
	var revision: int = grid.player_fog_revision
	_force_fog_overflow(grid)
	assert_true(grid.player_fog_overflow, "burst past the cap sets the overflow flag")
	assert_eq(grid._player_fog_changed_cells.size(), GridWorld.PLAYER_FOG_CHANGE_CAP,
		"change list holds exactly the capped amount; the rest is dropped")
	assert_gt(grid.player_fog_revision, revision, "the overflow pass still bumps the revision")
	grid.consume_player_fog_changes()
	grid.consume_player_fog_overflow()


func test_overflow_recovers_with_one_full_fog_refresh() -> void:
	var fog := _fog()
	var grid := _grid()
	_force_fog_overflow(grid)
	assert_true(grid.player_fog_overflow)
	# One refresh tick (0.5s cadence forced): drains the overflow flag and
	# lands the full rebuild — the recovery path, not a silently stale board.
	fog._process(Fog3D.REFRESH_INTERVAL)
	assert_false(grid.player_fog_overflow, "Fog3D's refresh drains the overflow flag")
	var checked: int = 0
	for x in range(GridWorld.X_MIN, GridWorld.X_MAX + 1):
		for y in range(GridWorld.SURFACE_TOP, GridWorld.Y_MAX + 1):
			var cell := Vector2i(x, y)
			var expected: Color
			match grid.fog_state_at(GameManager.Team.PLAYER, cell):
				2:
					expected = Color(1.0, 1.0, 1.0, Fog3D.ALPHA_VISIBLE)
				1:
					expected = Color(Fog3D.SHADOW_COLOR, Fog3D.ALPHA_REMEMBERED)
				_:
					expected = Color(Fog3D.VOID_COLOR, Fog3D.ALPHA_HIDDEN)
			assert_eq(fog.color_at_cell(cell), expected,
				"cell %s matches fog_state_at after one refresh" % cell)
			checked += 1
	assert_gt(checked, GridWorld.PLAYER_FOG_CHANGE_CAP,
		"samples well past the cap, including dropped cells")
