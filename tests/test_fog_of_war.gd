extends GutTest

# Fog of War & vision (Revamp Phase 1): per-team vision maps, remembered
# tiles, enemy silhouettes, fog combat rules, and the lantern structures
# (placement rules, tiers, ore reveal, destruction salvage).

const PLAYER: int = 0
const ENEMY: int = 1

var _main: Node
var _units: Node
var _grid: Node
var _pc: Node


func before_all() -> void:
	# Deterministic map: Constants.DEBUG is off (so GridWorld doesn't seed
	# itself), but the tests assert against specific layouts.
	seed(12345)
	_main = load("res://scenes/main.tscn").instantiate()
	get_tree().root.add_child(_main)
	get_tree().current_scene = _main
	_units = _main.get_node("Units")
	_grid = _main.get_node("World/GridWorld")
	_pc = _main.get_node("PlayerController")
	# Warm-up: the first test after boot gets ~0.4s of node _process starvation
	# in the headless harness, so let the scene settle before any test asserts
	# on per-frame state (vision maps update in GridWorld._process).
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
	_grid.set_reveal_all(PLAYER, false)
	_grid.set_reveal_all(ENEMY, false)
	# Fog maps persist in the scene across tests; wipe them so one test's
	# revealed cells can't leak into the next as stale "remembered" tiles
	# (match_time resets to 0 each test, so old memories would never expire).
	_grid._init_vision_maps()
	_grid._unit_ghosts.clear()
	_grid._prev_visible_enemies.clear()


func after_each() -> void:
	# Lanterns persist in the scene across tests; reset the slate so max-count
	# and distance rules start clean for every test.
	for lantern in get_tree().get_nodes_in_group("lanterns"):
		lantern.free()
	GameManager.set_difficulty(GameManager.Difficulty.NORMAL)


func _spawn_unit(tres_path: String, team: int, pos: Vector2) -> Node2D:
	var unit: Node2D = load("res://scenes/unit.tscn").instantiate()
	unit.set("data", load(tres_path).duplicate(true))
	unit.set("team", team)
	unit.position = pos
	_units.add_child(unit)
	autofree(unit)
	return unit


func _spawn_fighter(team: int, pos: Vector2) -> Node2D:
	return _spawn_unit("res://scripts/resources/units/swordsman.tres", team, pos)


## Places a lantern and fast-forwards its construction to completion.
func _place_built_lantern(kind: String, cell: Vector2i) -> Node2D:
	var ok: bool = _pc.try_place_lantern(kind, _grid.grid_to_world(cell))
	assert_true(ok, "placement must succeed at %s" % str(cell))
	var lantern: Node2D = null
	for l in get_tree().get_nodes_in_group("lanterns"):
		lantern = l
	assert_not_null(lantern, "a lantern must exist after placement")
	if lantern == null:
		return null
	lantern._build_progress = 999.0
	lantern._process(0.1)
	return lantern


# ─── Vision maps ───

func test_player_base_area_visible_at_match_start() -> void:
	await wait_seconds(0.1)
	assert_eq(_grid.fog_state_at(PLAYER, Vector2i(-30, 0)), 2, "own building must light its surroundings")


func test_enemy_base_area_fogged_at_match_start() -> void:
	await wait_seconds(0.1)
	assert_eq(_grid.fog_state_at(PLAYER, Vector2i(30, 0)), 0, "enemy base must start in full fog")
	assert_false(_grid.is_visible_to(PLAYER, Vector2(960, 16)), "enemy base not visible")
	assert_false(_grid.is_remembered_by(PLAYER, Vector2(960, 16)), "never-seen cells are not remembered")


func test_vision_remembers_then_fades_to_fog() -> void:
	var fighter: Node2D = _spawn_fighter(PLAYER, Vector2(16, 16))
	await wait_seconds(0.1)
	assert_eq(_grid.fog_state_at(PLAYER, Vector2i(0, 0)), 2, "fighter must reveal its own cell")
	fighter.position = Vector2(-1200, 16)  # far corner: the mid-map cell goes dark
	await wait_seconds(0.1)
	assert_eq(_grid.fog_state_at(PLAYER, Vector2i(0, 0)), 1, "recently seen cell must be remembered")
	GameManager.match_time += Constants.FOG_MEMORY_DURATION + 1.0
	await wait_seconds(0.1)
	assert_eq(_grid.fog_state_at(PLAYER, Vector2i(0, 0)), 0, "memory must fade back to full fog")


func test_get_vision_radius_per_unit_type() -> void:
	var swordsman: Node2D = _spawn_unit("res://scripts/resources/units/swordsman.tres", PLAYER, Vector2(0, 16))
	var archer: Node2D = _spawn_unit("res://scripts/resources/units/archer.tres", PLAYER, Vector2(0, 16))
	var wizard: Node2D = _spawn_unit("res://scripts/resources/units/wizard.tres", PLAYER, Vector2(0, 16))
	var miner: Node2D = _spawn_unit("res://scripts/resources/units/miner.tres", PLAYER, Vector2(0, 16))
	var dragon: Node2D = _spawn_unit("res://scripts/resources/units/dragon.tres", PLAYER, Vector2(0, 16))
	assert_eq(swordsman.get_vision_radius(), Constants.VISION_SWORDSMAN)
	assert_eq(archer.get_vision_radius(), Constants.VISION_ARCHER)
	assert_eq(wizard.get_vision_radius(), Constants.VISION_WIZARD)
	assert_eq(dragon.get_vision_radius(), Constants.VISION_DRAGON)
	assert_eq(miner.get_vision_radius(), Constants.VISION_MINER_SURFACE)
	miner.is_underground = true
	assert_eq(miner.get_vision_radius(), Constants.VISION_MINER_UNDERGROUND)


# ─── Enemy hiding & silhouettes ───

func test_enemy_unit_hidden_in_fog_shown_in_vision() -> void:
	_spawn_fighter(PLAYER, Vector2(0, 16))
	var enemy: Node2D = _spawn_fighter(ENEMY, Vector2(1200, 16))  # deep in fog
	await wait_seconds(0.1)
	assert_false(enemy.visible, "enemy in fog must not be drawn")
	enemy.position = Vector2(100, 16)  # inside the fighter's 8-cell vision
	await wait_seconds(0.1)
	assert_true(enemy.visible, "enemy inside vision must be drawn")


func test_enemy_leaving_vision_leaves_ghost_silhouette() -> void:
	_spawn_fighter(PLAYER, Vector2(0, 16))
	var enemy: Node2D = _spawn_fighter(ENEMY, Vector2(100, 16))
	await wait_seconds(0.1)
	enemy.position = Vector2(1200, 16)  # slips into the fog
	await wait_seconds(0.1)
	assert_true(_grid._unit_ghosts.has(enemy.get_instance_id()), "lost contact must leave a frozen silhouette")
	GameManager.match_time += Constants.FOG_MEMORY_DURATION + 1.0
	await wait_seconds(0.1)
	assert_false(_grid._unit_ghosts.has(enemy.get_instance_id()), "silhouette must fade with the memory")


# ─── Fog combat rules ───

func test_attack_lock_drops_when_target_enters_fog() -> void:
	var fighter: Node2D = _spawn_fighter(PLAYER, Vector2(0, 16))
	var enemy: Node2D = _spawn_fighter(ENEMY, Vector2(40, 16))
	fighter.attack_unit(enemy)
	await wait_seconds(0.1)
	assert_eq(fighter._state, Unit.State.ATTACK, "attack must start while the target is visible")
	enemy.position = Vector2(1200, 16)  # target vanishes into the fog
	fighter._process_attack(0.016)
	assert_null(fighter._target_unit, "fog must break the target lock")
	assert_eq(fighter._state, Unit.State.IDLE, "unit must go idle when its target enters fog")


# ─── Surface lanterns ───

func test_surface_lantern_placement_spends_coin_and_spawns() -> void:
	var coin_before: int = EconomyManager.get_coin(PLAYER)
	assert_true(_pc.try_place_lantern("lantern", _grid.grid_to_world(Vector2i(-20, 0))))
	assert_eq(EconomyManager.get_coin(PLAYER), coin_before - Constants.LANTERN_T1_COST, "T1 lantern costs 200g")
	var lanterns: Array = get_tree().get_nodes_in_group("lanterns")
	assert_eq(lanterns.size(), 1, "lantern must spawn")
	assert_false(lanterns[0].is_built(), "lantern starts under construction")
	assert_eq(lanterns[0].total_cost, Constants.LANTERN_T1_COST)


func test_surface_lantern_placement_rejects_invalid_cells() -> void:
	assert_false(_pc.try_place_lantern("lantern", _grid.grid_to_world(Vector2i(20, 0))), "enemy half is off-limits")
	assert_false(_pc.try_place_lantern("lantern", _grid.grid_to_world(Vector2i(-20, 5))), "surface lanterns cannot go underground")
	assert_eq(get_tree().get_nodes_in_group("lanterns").size(), 0, "rejections must not spawn anything")


func test_lantern_min_distance_and_max_count() -> void:
	EconomyManager.add_coin(PLAYER, 10000)
	assert_true(_pc.try_place_lantern("lantern", _grid.grid_to_world(Vector2i(-20, 0))))
	assert_false(_pc.try_place_lantern("lantern", _grid.grid_to_world(Vector2i(-21, 0))), "too close to another lantern")
	assert_true(_pc.try_place_lantern("lantern", _grid.grid_to_world(Vector2i(-25, 0))))
	assert_true(_pc.try_place_lantern("lantern", _grid.grid_to_world(Vector2i(-32, 0))))
	assert_false(_pc.try_place_lantern("lantern", _grid.grid_to_world(Vector2i(-38, 0))), "4th lantern exceeds the max of 3")


func test_built_lantern_is_a_vision_source() -> void:
	var lantern: Node2D = _place_built_lantern("lantern", Vector2i(-20, 0))
	assert_true(lantern.is_built(), "construction must finish")
	var found: bool = false
	for source in _grid._get_vision_sources(PLAYER):
		if source[0] == Vector2i(-20, 0) and source[1] == Constants.LANTERN_T1_VISION:
			found = true
	assert_true(found, "built lantern must contribute its 8-cell vision")


func test_lantern_upgrade_in_place() -> void:
	EconomyManager.add_coin(PLAYER, 10000)
	var lantern: Node2D = _place_built_lantern("lantern", Vector2i(-20, 0))
	var coin_before: int = EconomyManager.get_coin(PLAYER)
	assert_true(_pc.try_place_lantern("lantern", _grid.grid_to_world(Vector2i(-20, 0))), "placing on an own lantern upgrades it")
	assert_eq(lantern.tier, 2, "upgrade must raise the tier")
	assert_eq(lantern.vision_radius, Constants.LANTERN_T2_VISION, "T2 sees 14 cells")
	assert_eq(EconomyManager.get_coin(PLAYER), coin_before - Constants.LANTERN_T2_COST, "upgrade costs 600g")
	assert_false(lantern.is_built(), "upgraded lantern rebuilds before providing vision")


func test_lantern_invulnerable_while_building() -> void:
	assert_true(_pc.try_place_lantern("lantern", _grid.grid_to_world(Vector2i(-20, 0))))
	var lantern: Node2D = get_tree().get_nodes_in_group("lanterns")[0]
	lantern.take_damage(100)
	assert_eq(lantern.hp, lantern.max_hp, "under-construction lanterns take no damage")


func test_lantern_destruction_drops_salvage_and_loses_vision() -> void:
	var lantern: Node2D = _place_built_lantern("lantern", Vector2i(-20, 0))
	lantern.take_damage(9999)
	assert_eq(get_tree().get_nodes_in_group("lanterns").size(), 0, "destroyed lantern leaves the lanterns group")
	var salvage: CoinPickup = null
	for child in _main.get_children():
		if child is CoinPickup:
			salvage = child
	assert_not_null(salvage, "destroyed lantern must drop a coin pickup")
	assert_eq(salvage.coin_value, int(Constants.LANTERN_T1_COST * Constants.LANTERN_SALVAGE_RATIO), "salvage is half the build cost")


# ─── Underground lanterns ───

func test_underground_lantern_placement_rules() -> void:
	assert_true(_pc.try_place_lantern("underground_lantern", _grid.grid_to_world(Vector2i(-15, 3))), "dug shaft cell is valid")
	assert_false(_pc.try_place_lantern("underground_lantern", _grid.grid_to_world(Vector2i(-20, 3))), "solid dirt is not a tunnel")
	assert_false(_pc.try_place_lantern("underground_lantern", _grid.grid_to_world(Vector2i(-15, 0))), "not on the surface")
	assert_false(_pc.try_place_lantern("underground_lantern", _grid.grid_to_world(Vector2i(15, 3))), "not on the enemy half")


func test_underground_lantern_max_count() -> void:
	EconomyManager.add_coin(PLAYER, 10000)
	_grid.carve_shaft(-20)  # second dug corridor for more valid cells
	assert_true(_pc.try_place_lantern("underground_lantern", _grid.grid_to_world(Vector2i(-15, 1))))
	assert_true(_pc.try_place_lantern("underground_lantern", _grid.grid_to_world(Vector2i(-15, 3))))
	assert_true(_pc.try_place_lantern("underground_lantern", _grid.grid_to_world(Vector2i(-15, 5))))
	assert_true(_pc.try_place_lantern("underground_lantern", _grid.grid_to_world(Vector2i(-20, 1))))
	assert_true(_pc.try_place_lantern("underground_lantern", _grid.grid_to_world(Vector2i(-20, 3))))
	assert_false(_pc.try_place_lantern("underground_lantern", _grid.grid_to_world(Vector2i(-20, 5))), "6th mine lantern exceeds the max of 5")


func test_underground_lantern_reveals_exposed_ore_only() -> void:
	# Place an ore vein directly next to the empty shaft so it is exposed.
	var ore_pos: Vector2i = Vector2i(-16, 3)
	_grid._cells[ore_pos] = GridWorld.Cell.new(GridWorld.CellType.ORE, 1, 1, Constants.LAYER_TILE_HP[1], 50)
	_grid._astar.set_point_solid(ore_pos, true)

	# Place a fully buried ore vein with solid dirt on all sides.
	var buried_pos: Vector2i = Vector2i(-22, 3)
	_grid._cells[buried_pos] = GridWorld.Cell.new(GridWorld.CellType.ORE, 1, 1, Constants.LAYER_TILE_HP[1], 50)
	_grid._astar.set_point_solid(buried_pos, true)
	for off in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
		var n: Vector2i = buried_pos + off
		if not _grid._cells.has(n):
			_grid._cells[n] = GridWorld.Cell.new(GridWorld.CellType.DIRT, 1, 1, Constants.LAYER_TILE_HP[1], 0)
			_grid._astar.set_point_solid(n, true)

	_place_built_lantern("underground_lantern", Vector2i(-15, 3))
	assert_true(_grid.is_ore_revealed(ore_pos, PLAYER), "a built mine lantern must reveal exposed ore in its radius")
	assert_false(_grid.is_ore_revealed(buried_pos, PLAYER), "a built mine lantern must NOT reveal fully buried ore")


# ─── Layer-locked vision ───

func test_underground_lantern_lights_only_underground() -> void:
	_place_built_lantern("underground_lantern", Vector2i(-15, 3))
	await wait_seconds(0.1)
	assert_eq(_grid.fog_state_at(PLAYER, Vector2i(-10, 3)), 2, "mine lantern must light its tunnel radius")
	assert_eq(_grid.fog_state_at(PLAYER, Vector2i(-10, 0)), 0, "mine lantern must NOT light the surface above")


func test_surface_lantern_lights_only_surface() -> void:
	_place_built_lantern("lantern", Vector2i(-20, 0))
	await wait_seconds(0.1)
	assert_eq(_grid.fog_state_at(PLAYER, Vector2i(-19, 0)), 2, "surface lantern must light the surface row")
	assert_eq(_grid.fog_state_at(PLAYER, Vector2i(-20, 1)), 0, "surface lantern must NOT light the tunnels below")


func test_miner_lights_only_current_layer() -> void:
	_spawn_unit("res://scripts/resources/units/miner.tres", PLAYER, Vector2(0, 16))
	await wait_seconds(0.1)
	assert_eq(_grid.fog_state_at(PLAYER, Vector2i(2, 0)), 2, "surface miner must light the surface around it")
	assert_eq(_grid.fog_state_at(PLAYER, Vector2i(0, 1)), 0, "surface miner must NOT light the underground below")


# ─── Lanterns as combat targets ───

func test_fighter_auto_attacks_visible_enemy_lantern() -> void:
	var fighter: Node2D = _spawn_fighter(PLAYER, Vector2(0, 16))
	fighter.stop()  # hold post: only the idle auto-attack scan may engage
	var lantern: Lantern = load("res://scenes/lantern.tscn").instantiate()
	lantern.team = ENEMY
	lantern.is_underground_lantern = false
	lantern.total_cost = Constants.LANTERN_T1_COST
	lantern.global_position = Vector2(100, 16)
	_main.get_node("Structures").add_child(lantern)
	autofree(lantern)
	lantern._build_progress = 999.0
	lantern._process(0.1)
	await wait_seconds(0.1)
	assert_eq(fighter._target_building, lantern, "fighters must auto-attack a visible enemy lantern")
