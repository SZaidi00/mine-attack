extends GutTest

# AI awareness (Revamp Phase 8): faction scouting (first swordsman at 1:00,
# replacement 30s after it dies, both sides can be scouted) becoming periodic
# re-scouting once the faction is known, defensive lantern placement/upgrades,
# AI tower placement, and weather/terrain responses (snowstorm recall, lava
# evacuation).

const PLAYER: int = 0
const ENEMY: int = 1

var _main: Node
var _units: Node
var _grid: Node
var _ai: Node


func before_all() -> void:
	seed(12345)
	_main = load("res://scenes/main.tscn").instantiate()
	get_tree().root.add_child(_main)
	get_tree().current_scene = _main
	_units = _main.get_node("Units")
	_grid = _main.get_node("World/GridWorld")
	_ai = _main.get_node("AIController")
	# Deterministic: no random storms/lava unless a test forces them.
	WeatherManager.set_weather_events_enabled(false)
	_grid.set_dynamic_events_enabled(false)


func after_all() -> void:
	WeatherManager.set_weather_events_enabled(true)
	_grid.set_dynamic_events_enabled(true)
	# Free immediately, not queue_free(): these tests never await, so a queued
	# free would still be pending when the next test script instantiates its
	# own main.tscn — the old "Main" name would still be taken, the new scene
	# would be renamed, and every hard-coded /root/Main lookup would break.
	_main.free()


func before_each() -> void:
	EconomyManager.reset()
	ResearchManager.reset()
	FactionManager.reset()
	GameManager.game_active = true
	GameManager.ai_opener = "balanced"
	_ai._scout = null
	_ai._aggression_level = "balanced"
	_ai._next_scout_time = Constants.ENEMY_SCOUT_TIME
	_ai._next_rescout_time = Constants.ENEMY_RESCOUT_INTERVAL


func after_each() -> void:
	GameManager.set_difficulty(GameManager.Difficulty.NORMAL)
	GameManager.ai_opener = "balanced"
	FactionManager.set_player_faction("")
	FactionManager.enemy_faction_id = ""
	var lanterns: Array = get_tree().get_nodes_in_group("lanterns")
	for lantern in lanterns:
		if lantern.team == ENEMY:
			lantern.free()
	var towers: Array = get_tree().get_nodes_in_group("towers")
	for tower in towers:
		if tower.team == ENEMY:
			tower.free()


func _spawn_unit(tres_path: String, team: int, pos: Vector2) -> Node2D:
	var unit: Node2D = load("res://scenes/unit.tscn").instantiate()
	unit.set("data", load(tres_path).duplicate(true))
	unit.set("team", team)
	unit.position = pos
	_units.add_child(unit)
	autofree(unit)
	return unit


func _building_for(team: int) -> Node2D:
	for b in get_tree().get_nodes_in_group("buildings"):
		if b.get("team") == team:
			return b
	return null


func _enemy_lanterns() -> Array:
	var result: Array = []
	for lantern in get_tree().get_nodes_in_group("lanterns"):
		if lantern.team == ENEMY:
			result.append(lantern)
	return result


func _enemy_towers() -> Array:
	var result: Array = []
	for tower in get_tree().get_nodes_in_group("towers"):
		if tower.team == ENEMY:
			result.append(tower)
	return result


## Structure fixtures skip placement validation — they only need to exist in
## the group with the right team. after_each frees the ENEMY ones.
func _spawn_lantern(team: int, pos: Vector2) -> Node2D:
	var lantern: Node2D = load("res://scenes/lantern.tscn").instantiate()
	lantern.set("team", team)
	lantern.position = pos
	_main.get_node("Structures").add_child(lantern)
	return lantern


func _spawn_tower(team: int, pos: Vector2) -> Node2D:
	var tower: Node2D = load("res://scenes/tower.tscn").instantiate()
	tower.set("team", team)
	tower.position = pos
	_main.get_node("Structures").add_child(tower)
	return tower


# ─── Scouting ───

func test_scout_sent_at_one_minute_mark() -> void:
	GameManager.match_time = Constants.ENEMY_SCOUT_TIME + 1.0
	var swordsman: Node2D = _spawn_unit("res://scripts/resources/units/swordsman.tres", ENEMY, _building_for(ENEMY).global_position + Vector2(-80, 16))
	_ai._run_scouting()
	assert_eq(_ai._scout, swordsman, "an idle swordsman is picked as the scout")
	assert_eq(swordsman._state, Unit.State.ATTACK, "the scout attack-moves on the enemy base (waves ignore ATTACK units)")
	assert_eq(swordsman._target_building, _building_for(PLAYER), "the scout heads for the player building")


func test_no_scout_before_one_minute() -> void:
	GameManager.match_time = 10.0
	var swordsman: Node2D = _spawn_unit("res://scripts/resources/units/swordsman.tres", ENEMY, _building_for(ENEMY).global_position + Vector2(-80, 16))
	_ai._run_scouting()
	assert_null(_ai._scout, "no scout before the 1:00 mark")
	assert_eq(swordsman._state, Unit.State.IDLE, "the swordsman stays put")


func test_dead_scout_is_replaced_after_retry_delay() -> void:
	GameManager.match_time = 100.0
	var first: Node2D = _spawn_unit("res://scripts/resources/units/swordsman.tres", ENEMY, _building_for(ENEMY).global_position + Vector2(-80, 16))
	_ai._run_scouting()
	assert_eq(_ai._scout, first)
	first.kill()
	_ai._run_scouting()
	assert_null(_ai._scout, "the dead scout is cleared")
	assert_almost_eq(_ai._next_scout_time, 100.0 + Constants.ENEMY_SCOUT_RETRY_DELAY, 0.01,
		"the replacement waits out the retry delay")
	var second: Node2D = _spawn_unit("res://scripts/resources/units/swordsman.tres", ENEMY, _building_for(ENEMY).global_position + Vector2(-80, 16))
	GameManager.match_time = 100.0 + Constants.ENEMY_SCOUT_RETRY_DELAY + 1.0
	_ai._run_scouting()
	assert_eq(_ai._scout, second, "a new scout is sent once the delay expires")


func test_identified_faction_switches_to_periodic_rescouting() -> void:
	GameManager.match_time = Constants.ENEMY_SCOUT_TIME + 1.0
	FactionManager.identify_faction(PLAYER)
	var swordsman: Node2D = _spawn_unit("res://scripts/resources/units/swordsman.tres", ENEMY, _building_for(ENEMY).global_position + Vector2(-80, 16))
	_ai._run_scouting()
	assert_null(_ai._scout, "the re-scout still waits out its interval")
	assert_eq(swordsman._state, Unit.State.IDLE)
	GameManager.match_time += Constants.ENEMY_RESCOUT_INTERVAL + 1.0
	_ai._run_scouting()
	assert_eq(_ai._scout, swordsman, "once due, a swordsman re-visits to refresh tower/army intel")
	assert_eq(swordsman._target_building, _building_for(PLAYER), "the re-scout heads for the player building")
	assert_almost_eq(_ai._next_rescout_time, GameManager.match_time + Constants.ENEMY_RESCOUT_INTERVAL, 0.01,
		"the next re-scout is scheduled a full interval out")


func test_rescout_is_a_tier_two_behavior() -> void:
	GameManager.set_difficulty(GameManager.Difficulty.EASY)  # smarts 0
	FactionManager.identify_faction(PLAYER)
	_ai._next_rescout_time = 0.0  # overdue
	var swordsman: Node2D = _spawn_unit("res://scripts/resources/units/swordsman.tres", ENEMY, _building_for(ENEMY).global_position + Vector2(-80, 16))
	_ai._run_scouting()
	assert_null(_ai._scout, "the easy AI never re-scouts")
	assert_eq(swordsman._state, Unit.State.IDLE, "the swordsman stays home")


func test_rescout_skipped_while_own_pigeon_patrols() -> void:
	FactionManager.identify_faction(PLAYER)
	_ai._next_rescout_time = 0.0
	_spawn_unit("res://scripts/resources/units/pigeon.tres", ENEMY, _building_for(ENEMY).global_position + Vector2(-40, -30))
	var swordsman: Node2D = _spawn_unit("res://scripts/resources/units/swordsman.tres", ENEMY, _building_for(ENEMY).global_position + Vector2(-80, 16))
	_ai._run_scouting()
	assert_null(_ai._scout, "a patrolling pigeon already refreshes intel — no swordsman run")
	assert_eq(swordsman._state, Unit.State.IDLE)


func test_rescout_skipped_while_defending() -> void:
	FactionManager.identify_faction(PLAYER)
	_ai._next_rescout_time = 0.0
	_ai._aggression_level = "defend"
	var swordsman: Node2D = _spawn_unit("res://scripts/resources/units/swordsman.tres", ENEMY, _building_for(ENEMY).global_position + Vector2(-80, 16))
	_ai._run_scouting()
	assert_null(_ai._scout, "defend mode keeps every body at home")
	assert_eq(swordsman._state, Unit.State.IDLE)


func test_enemy_units_identify_player_faction_at_player_base() -> void:
	assert_false(FactionManager.is_faction_identified(PLAYER), "player faction starts hidden")
	_spawn_unit("res://scripts/resources/units/swordsman.tres", ENEMY, _building_for(PLAYER).global_position + Vector2(80, 0))
	_building_for(PLAYER)._check_faction_identified()
	assert_true(FactionManager.is_faction_identified(PLAYER), "an AI unit near the player base identifies the player's faction")


func test_enemy_units_far_from_player_base_identify_nothing() -> void:
	_spawn_unit("res://scripts/resources/units/swordsman.tres", ENEMY, _building_for(ENEMY).global_position)
	_building_for(PLAYER)._check_faction_identified()
	assert_false(FactionManager.is_faction_identified(PLAYER), "a scout at home reveals nothing")


# ─── Lantern placement ───

func test_ai_builds_lantern_when_affordable() -> void:
	EconomyManager.add_coin(ENEMY, 1000)  # 500 start + 1000, well past 200 + 500 reserve + 150 buffer
	_ai._run_lantern_placement()
	var lanterns: Array = _enemy_lanterns()
	assert_eq(lanterns.size(), 1, "the AI places a surface lantern")
	assert_eq(EconomyManager.get_coin(ENEMY), 1300, "the T1 cost is paid")
	var cell: Vector2i = _grid.world_to_grid(lanterns[0].global_position)
	assert_eq(cell.y, 0, "surface lanterns stand on the surface row")
	assert_true(cell.x >= 2, "the lantern is on the AI's half of the map")


func test_ai_lantern_respects_coin_buffer() -> void:
	# 200 cost + 500 L2 reserve + 150 buffer = 850 needed; 700 is not enough.
	EconomyManager.add_coin(ENEMY, 200)  # 500 start + 200 = 700
	_ai._run_lantern_placement()
	assert_eq(_enemy_lanterns().size(), 0, "no lantern while the reserve + buffer aren't met")


func test_ai_upgrades_oldest_lantern_to_t2() -> void:
	EconomyManager.add_coin(ENEMY, 5000)
	for i in range(Constants.LANTERN_MAX_COUNT):
		_ai._run_lantern_placement()
	assert_eq(_enemy_lanterns().size(), Constants.LANTERN_MAX_COUNT, "all lantern slots are filled first")
	# Upgrades only apply to finished lanterns (same rule as the player's
	# upgrade click) — construction takes 5s of game time, so finish them.
	for lantern in _enemy_lanterns():
		lantern._is_built = true
	_ai._run_lantern_placement()
	var upgraded: int = 0
	for lantern in _enemy_lanterns():
		if lantern.tier == 2:
			upgraded += 1
	assert_eq(upgraded, 1, "with full slots and a comfortable bank, one lantern is upgraded to T2")


# ─── Tower placement ───

func test_ai_builds_tower_with_vision_and_a_comfortable_bank() -> void:
	_spawn_lantern(ENEMY, Vector2(_building_for(ENEMY).global_position.x - 160, 16))
	EconomyManager.add_coin(ENEMY, 800)  # 1300 ≥ 300 cost + 400 buffer + 500 L2 reserve
	assert_true(_ai._run_tower_placement(), "with vision secured and a cushion, the AI fortifies")
	var towers: Array = _enemy_towers()
	assert_eq(towers.size(), 1, "the tower stands")
	assert_eq(EconomyManager.get_coin(ENEMY), 1000, "the 300g tower cost is paid")
	var cell: Vector2i = _grid.world_to_grid(towers[0].global_position)
	assert_eq(cell.y, 0, "towers stand on the surface row")
	assert_true(cell.x >= 2, "the tower is on the AI's half of the map")


func test_ai_tower_waits_for_lantern_vision() -> void:
	EconomyManager.add_coin(ENEMY, 5000)
	assert_false(_ai._run_tower_placement(), "non-turtle openers secure lantern vision before static defense")
	assert_eq(_enemy_towers().size(), 0)


func test_turtle_opener_builds_towers_first() -> void:
	GameManager.ai_opener = "turtle"
	EconomyManager.add_coin(ENEMY, 600)  # 1100 ≥ 300 cost + 200 early buffer + 500 L2 reserve
	assert_true(_ai._run_tower_placement(), "turtle leads with towers on a leaner buffer, no lantern needed")
	assert_eq(_enemy_towers().size(), 1)


func test_ai_tower_respects_the_coin_buffer() -> void:
	_spawn_lantern(ENEMY, Vector2(_building_for(ENEMY).global_position.x - 160, 16))
	EconomyManager.add_coin(ENEMY, 100)  # 600 - 500 reserve < 300 cost + 400 buffer
	assert_false(_ai._run_tower_placement(), "a lean bank keeps the AI saving, not turtling")
	assert_eq(_enemy_towers().size(), 0)


func test_ai_tower_count_respects_the_cap() -> void:
	_spawn_lantern(ENEMY, Vector2(_building_for(ENEMY).global_position.x - 160, 16))
	_spawn_tower(ENEMY, Vector2(800, 16))
	_spawn_tower(ENEMY, Vector2(840, 16))
	EconomyManager.add_coin(ENEMY, 5000)
	assert_false(_ai._run_tower_placement(), "TOWER_MAX_COUNT towers is enough")
	assert_eq(_enemy_towers().size(), 2)


# ─── Weather & terrain response ───

func test_snowstorm_warning_recalls_surface_miners() -> void:
	var miner: Node2D = _spawn_unit("res://scripts/resources/units/miner.tres", ENEMY, _building_for(ENEMY).global_position + Vector2(-60, 16))
	_ai._awareness._on_snowstorm_warning(5.0)
	assert_true(miner.shelter_in_place, "surface miners get shelter orders on the warning")
	assert_eq(miner._state, Unit.State.MOVE, "the miner is moving to shelter")
	_ai._awareness._on_snowstorm_ended()
	assert_false(miner.shelter_in_place, "shelter orders lift when the storm ends")


func test_snowstorm_warning_leaves_underground_miners() -> void:
	var miner: Node2D = _spawn_unit("res://scripts/resources/units/miner.tres", ENEMY, Vector2(976, 400))
	miner.is_underground = true
	_ai._awareness._on_snowstorm_warning(5.0)
	assert_false(miner.shelter_in_place, "underground miners are safe from the storm and keep digging")


func test_lava_warning_evacuates_bottom_two_layers() -> void:
	var deep: Node2D = _spawn_unit("res://scripts/resources/units/miner.tres", ENEMY, Vector2(976, 18 * 32 + 16))
	deep.is_underground = true
	var shallow: Node2D = _spawn_unit("res://scripts/resources/units/miner.tres", ENEMY, Vector2(976, 5 * 32 + 16))
	shallow.is_underground = true
	_ai._awareness._on_lava_warning(5.0)
	assert_true(deep.shelter_in_place, "miners in the bottom two layers evacuate")
	assert_false(shallow.shelter_in_place, "miners above the flood zone keep working")
	_ai._awareness._on_lava_receded()
	assert_false(deep.shelter_in_place, "evacuation lifts when the lava recedes")


func test_sheltered_miners_are_not_retasked_by_mining_tick() -> void:
	var miner: Node2D = _spawn_unit("res://scripts/resources/units/miner.tres", ENEMY, _building_for(ENEMY).global_position + Vector2(-60, 16))
	_ai._awareness._on_snowstorm_warning(5.0)
	miner.stop()  # falls IDLE, as on arrival at the shelter
	_ai._run_mining()
	assert_eq(miner._state, Unit.State.IDLE, "the mining tick leaves sheltered miners alone")
	_ai._awareness._on_snowstorm_ended()
