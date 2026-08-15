extends GutTest

# Dynamic terrain & events (Revamp Phase 4): lava rising (warning → flood →
# recede into magma rock / fresh ore), cave-ins (rock, damage, push, restore),
# ore depletion trickle reduction, and vein respawn. Random scheduling is
# disabled for the whole suite — every event is forced explicitly.

const PLAYER: int = 0
const ENEMY: int = 1

var _main: Node
var _units: Node
var _grid: Node


func before_all() -> void:
	# Deterministic map: Constants.DEBUG is off (so GridWorld doesn't seed
	# itself), but the tests assert against specific layouts.
	seed(12345)
	_main = load("res://scenes/main.tscn").instantiate()
	get_tree().root.add_child(_main)
	get_tree().current_scene = _main
	_units = _main.get_node("Units")
	_grid = _main.get_node("World/GridWorld")
	# No random events mid-test: all triggers below are forced.
	_grid.set_dynamic_events_enabled(false)
	# Warm-up: the first test after boot gets ~0.4s of node _process starvation
	# in the headless harness, so let the scene settle first.
	await wait_seconds(0.6)


func after_all() -> void:
	# Free immediately, not queue_free(): a queued free could still be pending
	# when the next test script instantiates its own main.tscn and every
	# hard-coded /root/Main lookup would break.
	_main.free()


func before_each() -> void:
	EconomyManager.reset()
	ResearchManager.reset()
	GameManager.reset()
	# Events persist in the scene across tests; reset the slate so one test's
	# lava flood or cave-in can't leak into the next.
	_grid._events._lava_warning_left = 0.0
	_grid._events._lava_state = GridEvents.LavaState.IDLE
	if _grid.is_lava_active():
		_grid.force_lava_recede()
	_grid._events._lava_wave_profile.clear()
	_grid._events._lava_flooded_cells.clear()
	_grid._events._lava_original_cells.clear()
	_grid._events._lava_y_tide = float(GridWorld.Y_MAX + 1)
	_grid._events._lava_top_min = GridWorld.Y_MAX + 1
	if _grid._events._cavein_restore_left > 0.0:
		_grid._events._cavein_restore_left = 0.0
		_grid._events._restore_cave_in()


func after_each() -> void:
	for lantern in get_tree().get_nodes_in_group("lanterns"):
		lantern.free()


func _spawn_unit(tres_path: String, team: int, pos: Vector2) -> Node2D:
	var unit: Node2D = load("res://scenes/unit.tscn").instantiate()
	unit.set("data", load(tres_path).duplicate(true))
	unit.set("team", team)
	unit.position = pos
	_units.add_child(unit)
	autofree(unit)
	return unit


func _lava_zone_cells(_layers: int) -> Array[Vector2i]:
	# The flood is now a cosine wave, so the "zone" is the set of cells that
	# were actually converted to LAVA by the current rise.
	return _grid.get_lava_cells()


# ─── Lava rising ───

func test_lava_rise_converts_zone_and_spares_walls() -> void:
	_grid.force_lava_rise(2)
	assert_true(_grid.is_lava_active(), "lava must be active after the rise")
	for pos in _lava_zone_cells(2):
		var cell = _grid.get_cell(pos)
		assert_not_null(cell, "lava zone cell must exist at %s" % str(pos))
		if cell == null:
			continue
		if pos.x in [-1, 0, 1]:
			assert_true(cell.is_wall, "central wall survives the flood at %s" % str(pos))
			continue
		assert_eq(cell.type, GridWorld.CellType.LAVA, "zone cell becomes lava at %s" % str(pos))
		assert_false(_grid.is_walkable(pos), "lava is A*-solid at %s" % str(pos))
		assert_eq(_grid.damage_cell(pos, 50, 3), 0, "lava is indestructible at %s" % str(pos))
	_grid.force_lava_recede()


func test_lava_recedes_into_magma_rock_and_fresh_ore() -> void:
	_grid.force_lava_rise(2)
	var flooded: Array[Vector2i] = _grid.get_lava_cells()
	_grid.force_lava_recede()
	assert_false(_grid.is_lava_active(), "lava must be gone after the recede")
	var magma: int = 0
	var fresh: int = 0
	for pos in flooded:
		var cell = _grid.get_cell(pos)
		if cell == null or pos.x in [-1, 0, 1]:
			continue
		assert_ne(cell.type, GridWorld.CellType.LAVA, "no lava remains at %s" % str(pos))
		if cell.type == GridWorld.CellType.MAGMA_ROCK:
			magma += 1
			assert_eq(cell.coin_value, 0, "empty magma rock yields no gold")
			assert_eq(cell.hp, Constants.MAGMA_ROCK_HP)
		elif cell.type == GridWorld.CellType.FRESH_ORE:
			fresh += 1
			assert_between(cell.coin_value, Constants.MAGMA_ORE_MIN, Constants.MAGMA_ORE_MAX, "fresh ore is high-value")
			assert_eq(cell.hp, Constants.MAGMA_ROCK_HP)
	assert_gt(magma, 0, "recede leaves magma rock")
	assert_gt(fresh, 0, "recede leaves fresh ore veins")


func test_magma_rock_is_diggable_and_yields_nothing() -> void:
	_grid.force_lava_rise(1)
	var flooded: Array[Vector2i] = _grid.get_lava_cells()
	_grid.force_lava_recede()
	var pos: Vector2i = Vector2i(-9999, -9999)
	for candidate in flooded:
		var cell = _grid.get_cell(candidate)
		if cell != null and cell.type == GridWorld.CellType.MAGMA_ROCK:
			pos = candidate
			break
	assert_ne(pos, Vector2i(-9999, -9999), "recede must leave magma rock")
	var swings: int = 0
	var total: int = 0
	while _grid.get_cell(pos) != null and swings < 100:
		total += _grid.damage_cell(pos, 25, 3)
		swings += 1
	assert_eq(total, 0, "magma rock pays no gold")
	assert_true(_grid.is_walkable(pos), "dug-out magma rock opens the tunnel")


func test_lava_kills_underground_units_without_cargo_drop() -> void:
	# The bottom row is always flooded, so y = Y_MAX is a guaranteed death cell.
	var miner: Node2D = _spawn_unit("res://scripts/resources/units/miner.tres", PLAYER, _grid.grid_to_world(Vector2i(-5, GridWorld.Y_MAX)))
	miner.is_underground = true
	miner.carried_coin = 30
	var fighter: Node2D = _spawn_unit("res://scripts/resources/units/swordsman.tres", ENEMY, _grid.grid_to_world(Vector2i(5, GridWorld.Y_MAX)))
	fighter.is_underground = true
	# Place the survivor well above even the highest possible wave peak.
	var survivor: Node2D = _spawn_unit("res://scripts/resources/units/miner.tres", PLAYER, _grid.grid_to_world(Vector2i(-5, 5)))
	survivor.is_underground = true
	_grid.force_lava_rise(2)
	assert_eq(miner._state, Unit.State.DEAD, "miner in the lava zone dies instantly")
	assert_eq(miner.carried_coin, 0, "lava melts the cargo — no coin pickup")
	assert_eq(fighter._state, Unit.State.DEAD, "fighters die in lava too")
	assert_ne(survivor._state, Unit.State.DEAD, "units above the zone survive")
	_grid.force_lava_recede()


func test_lava_destroys_underground_lanterns() -> void:
	var lantern: Lantern = load("res://scenes/lantern.tscn").instantiate()
	lantern.team = PLAYER
	lantern.is_underground_lantern = true
	# The bottom row is always flooded regardless of the wave shape.
	lantern.position = _grid.grid_to_world(Vector2i(-5, GridWorld.Y_MAX))
	_main.get_node("Structures").add_child(lantern)
	lantern._build_progress = 999.0
	lantern._process(0.1)
	assert_true(lantern.is_in_group("lanterns"))
	_grid.force_lava_rise(2)
	assert_false(lantern.is_in_group("lanterns"), "lava destroys underground lanterns")
	_grid.force_lava_recede()


func test_lava_warning_then_rise_on_countdown() -> void:
	watch_signals(_grid)
	_grid.force_lava_warning(1)
	assert_signal_emitted(_grid, "lava_warning_started")
	assert_true(_grid.is_lava_warning(), "warning phase begins")
	assert_almost_eq(_grid.get_lava_warning_remaining(), Constants.LAVA_WARNING_TIME, 0.1)
	await wait_seconds(Constants.LAVA_WARNING_TIME + 0.4)
	assert_true(_grid.is_lava_active(), "lava rises when the warning expires")
	assert_signal_emitted(_grid, "lava_risen")
	_grid.force_lava_recede()


func test_lava_rise_is_non_linear_cosine_wave() -> void:
	_grid.force_lava_rise(2)
	var tops: Array[int] = []
	for x in range(GridWorld.X_MIN, GridWorld.X_MAX + 1):
		var top: int = GridWorld.Y_MAX + 1
		for y in range(GridWorld.Y_MIN, GridWorld.Y_MAX + 1):
			var cell = _grid.get_cell(Vector2i(x, y))
			if cell != null and cell.type == GridWorld.CellType.LAVA:
				top = y
				break
		if top <= GridWorld.Y_MAX:
			tops.append(top)
	var unique_tops: Array[int] = []
	for t in tops:
		if not unique_tops.has(t):
			unique_tops.append(t)
	assert_gt(unique_tops.size(), 1, "lava top varies across columns (cosine wave)")
	_grid.force_lava_recede()


func test_lava_creeps_up_and_recedes_like_a_tide() -> void:
	# Manually drive the creep without waiting real time.
	_grid.force_lava_warning(2)
	var events: GridEvents = _grid._events
	assert_eq(events._lava_state, GridEvents.LavaState.WARNING)
	events._start_lava_creep()
	assert_eq(events._lava_state, GridEvents.LavaState.CREEPING_UP)
	var peak: int = events._lava_top_min
	# Halfway up: some lava exists, but the peak row is not flooded yet.
	events._lava_timer = Constants.LAVA_CREEP_UP_TIME * 0.5
	events._lava_y_tide = lerp(float(GridWorld.Y_MAX + 1), float(peak), events._smoothstep(0.5))
	events._apply_lava_tide()
	var flooded_mid: int = events._lava_flooded_cells.size()
	assert_gt(flooded_mid, 0, "tide covers some cells halfway up")
	var peak_flooded_mid: bool = false
	for pos in events._lava_flooded_cells:
		if pos.y <= peak:
			peak_flooded_mid = true
			break
	assert_false(peak_flooded_mid, "peak row is not flooded halfway up")
	# Fully up: the peak row is now flooded.
	events._lava_timer = Constants.LAVA_CREEP_UP_TIME
	events._lava_y_tide = float(peak)
	events._apply_lava_tide()
	assert_gt(events._lava_flooded_cells.size(), flooded_mid, "more cells flood at the peak")
	var flooded_peak: int = events._lava_flooded_cells.size()
	# Halfway down: some cells have receded.
	events._lava_state = GridEvents.LavaState.CREEPING_DOWN
	events._lava_timer = Constants.LAVA_CREEP_DOWN_TIME * 0.5
	events._lava_y_tide = lerp(float(peak), float(GridWorld.Y_MAX + 1), events._smoothstep(0.5))
	events._apply_lava_tide()
	assert_lt(events._lava_flooded_cells.size(), flooded_peak, "tide recedes halfway down")
	_grid.force_lava_recede()


# ─── Cave-ins ───

func test_cave_in_rocks_block_and_restore() -> void:
	var center: Vector2i = Vector2i(-20, 10)
	watch_signals(_grid)
	_grid.force_cave_in(center)
	assert_signal_emitted(_grid, "cave_in_occurred")
	var rocked: int = 0
	for dx in range(-1, 2):
		for dy in range(-1, 2):
			var pos: Vector2i = center + Vector2i(dx, dy)
			var cell = _grid.get_cell(pos)
			if cell == null or cell.type != GridWorld.CellType.SOLID_ROCK:
				continue
			rocked += 1
			assert_eq(_grid.damage_cell(pos, 50, 3), 0, "cave-in rock is indestructible at %s" % str(pos))
	assert_gt(rocked, 0, "cave-in converts diggable tiles to solid rock")
	await wait_seconds(Constants.CAVEIN_ROCK_DURATION + 0.5)
	for dx in range(-1, 2):
		for dy in range(-1, 2):
			var pos: Vector2i = center + Vector2i(dx, dy)
			var cell = _grid.get_cell(pos)
			if cell != null:
				assert_ne(cell.type, GridWorld.CellType.SOLID_ROCK, "rock settles back to dirt at %s" % str(pos))


func test_cave_in_damages_and_pushes_units() -> void:
	var fighter: Node2D = _spawn_unit("res://scripts/resources/units/swordsman.tres", PLAYER, _grid.grid_to_world(Vector2i(-20, 10)))
	fighter.is_underground = true
	var surface_unit: Node2D = _spawn_unit("res://scripts/resources/units/swordsman.tres", PLAYER, Vector2(-640, 16))
	_grid.force_cave_in(Vector2i(-20, 10))
	assert_eq(fighter.hp, fighter.data.max_hp - Constants.CAVEIN_DAMAGE, "units in the collapse take cave-in damage")
	assert_true(_grid.is_walkable(_grid.world_to_grid(fighter.global_position)), "survivors are pushed to a walkable cell")
	assert_eq(surface_unit.hp, surface_unit.data.max_hp, "surface units are unaffected")
	# Let the restore run so later tests see clean terrain.
	await wait_seconds(Constants.CAVEIN_ROCK_DURATION + 0.5)


# ─── Ore depletion & respawn ───

func test_depleted_ore_trickles_at_a_tenth() -> void:
	# Collect a few ore tiles: the trickle assertion needs a tile that
	# survives its post-depletion swing (a destroying swing pays the
	# remainder, which is correct behavior but not what is measured here).
	var ore_cells: Array[Vector2i] = []
	for x in range(-40, -2):
		for y in range(1, 22):
			var pos: Vector2i = Vector2i(x, y)
			var cell = _grid.get_cell(pos)
			if cell != null and cell.type == GridWorld.CellType.ORE:
				ore_cells.append(pos)
	assert_false(ore_cells.is_empty(), "map has ore")
	var tested: bool = false
	for pos in ore_cells.slice(0, 10):
		var cell = _grid.get_cell(pos)
		if cell == null:
			continue
		var normal_share: int = maxi(1, roundi(float(cell.coin_value) * 5.0 / float(cell.max_hp)))
		var swings: int = 0
		while not GridMining.is_depleted(cell) and _grid.get_cell(pos) != null and swings < 200:
			_grid.damage_cell(pos, 5, 3)
			swings += 1
		if _grid.get_cell(pos) == null:
			continue  # Destroyed before depleting; try the next vein.
		assert_true(GridMining.is_depleted(cell), "vein depletes after yielding 80% of its gold")
		if cell.hp <= 5:
			continue  # The next swing would destroy it and pay the remainder.
		var depleted_share: int = maxi(1, roundi(float(normal_share) * Constants.ORE_DEPLETED_YIELD_MULT))
		var got: int = _grid.damage_cell(pos, 5, 3)
		assert_lt(got, normal_share, "depleted trickle pays less than a normal swing")
		assert_true(got <= depleted_share, "depleted trickle pays at most a tenth share")
		tested = true
		break
	assert_true(tested, "found an ore vein that survives its post-depletion swing")


func test_ore_respawn_spawns_deep_veins() -> void:
	var spawned: int = _grid.force_ore_respawn()
	assert_eq(spawned, Constants.ORE_RESPAWN_COUNT, "forced respawn fills up to the count")
