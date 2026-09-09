extends GutTest

# AI crawler guard (ai_economy._try_train_crawler + ai_crawlers.gd): the AI
# keeps an underground crawler guard, shelters miners threatened by enemy
# intruders, converges the guard on visible raiders, and — once the central
# wall is breached and the army is not defending — raids the player mine with
# all but one crawler, pulling home when visibly outnumbered. Boots the real
# main.tscn; random events are disabled so nothing disturbs the fixtures.

const PLAYER: int = 0
const ENEMY: int = 1

var _main: Node
var _grid: Node
var _ai: Node


func before_all() -> void:
	seed(12345)
	_main = load("res://scenes/main.tscn").instantiate()
	get_tree().root.add_child(_main)
	get_tree().current_scene = _main
	_grid = _main.get_node("World/GridWorld")
	_ai = _main.get_node("AIController")
	WeatherManager.set_weather_events_enabled(false)
	WeatherManager.set_volcano_events_enabled(false)
	_grid.set_dynamic_events_enabled(false)
	# Flush the buildings' deferred starting-miner spawns (2 miners per side).
	await get_tree().process_frame


func after_all() -> void:
	_main.free()


func before_each() -> void:
	EconomyManager.reset()
	ResearchManager.reset()
	FactionManager.reset()
	FactionManager.enemy_faction_id = ""
	GameManager.set_difficulty(GameManager.Difficulty.NORMAL)  # smarts tier 2
	GameManager.ai_opener = "balanced"
	GameManager.game_active = true
	_ai._aggression_level = "balanced"
	_ai._crawlers._next_raid_time = 0.0
	_ai._crawlers._raiders.clear()
	for m in _ai._crawlers._sheltered_miners:
		if is_instance_valid(m):
			m.shelter_in_place = false
	_ai._crawlers._sheltered_miners.clear()
	_ai._crawlers._threat_active = false
	_drain_enemy_queue()
	_kill_live_enemy_crawlers()
	_grid.set_reveal_all(ENEMY, false)


func after_each() -> void:
	# Autoloads/fog: never leak a difficulty, opener, or reveal into the next
	# test script.
	GameManager.set_difficulty(GameManager.Difficulty.NORMAL)
	GameManager.ai_opener = "balanced"
	_grid.set_reveal_all(ENEMY, false)
	for u in get_tree().get_nodes_in_group("enemy"):
		if u.data != null and u.data.is_crawler:
			u.free()


func _spawn_unit(tres_path: String, team: int, pos: Vector2, underground := false) -> Node2D:
	var unit: Node2D = load("res://scenes/unit.tscn").instantiate()
	unit.set("data", load(tres_path).duplicate(true))
	unit.set("team", team)
	unit.position = pos
	_main.get_node("Units").add_child(unit)
	if underground:
		unit.set("is_underground", true)
	autofree(unit)
	return unit


func _spawn_miner(team: int, pos: Vector2, underground := true) -> Node2D:
	return _spawn_unit("res://scripts/resources/units/miner.tres", team, pos, underground)


func _spawn_crawler(team: int, pos: Vector2, underground := true) -> Node2D:
	return _spawn_unit("res://scripts/resources/units/crawler.tres", team, pos, underground)


func _mine_entry(team: int) -> Node2D:
	for entry in get_tree().get_nodes_in_group("mine_entries"):
		if entry.get("team") == team:
			return entry
	return null


func _building_for(team: int) -> Node2D:
	for b in get_tree().get_nodes_in_group("buildings"):
		if b.get("team") == team:
			return b
	return null


func _drain_enemy_queue() -> void:
	var building: Node2D = _building_for(ENEMY)
	while building.call("get_queue").size() > 0:
		building.call("cancel_queue", 0)


## Live-trained guards would inflate the fixture squads in the raid tests.
func _kill_live_enemy_crawlers() -> void:
	for u in get_tree().get_nodes_in_group("enemy"):
		if u.data != null and u.data.is_crawler:
			u.free()


## Pins the enemy wallet to an exact amount regardless of background income.
func _set_enemy_coin(amount: int) -> void:
	var coin: int = EconomyManager.get_coin(ENEMY)
	if coin > amount:
		EconomyManager.spend_coin(ENEMY, coin - amount)
	elif coin < amount:
		EconomyManager.add_coin(ENEMY, amount - coin)


func _queued_ids() -> Array:
	var ids: Array = []
	for entry in _building_for(ENEMY).call("get_queue"):
		ids.append(entry.id)
	return ids


## Drains the shared wall HP pool once; later calls are no-ops (the breach is
## permanent for the scene, and get_wall_cells() empties after it).
func _breach_wall() -> void:
	var cells: Array = _grid.get_wall_cells()
	if not cells.is_empty():
		_grid.damage_cell(cells[0], 100000, 3)


# ─── Guard training (ai_economy._try_train_crawler) ───

func test_ai_trains_crawler_guard_when_economy_supports_it() -> void:
	_set_enemy_coin(1000)
	# Match start fields 2 miners; the guard waits for a crew of 3.
	_spawn_miner(ENEMY, _mine_entry(ENEMY).call("get_underground_position"))
	# The live economy tick may have queued miners — drain so the queue-cap
	# check can't block the direct call (no frame runs until the assert).
	_drain_enemy_queue()
	_ai._economy._try_train_crawler()
	assert_true(_queued_ids().has("crawler"),
		"surplus coin + a real mining crew trains a crawler guard")


func test_crawler_guard_waits_for_a_mining_crew() -> void:
	_set_enemy_coin(1000)
	for u in get_tree().get_nodes_in_group("enemy"):
		if u.data != null and u.data.is_miner:
			u.free()
	_drain_enemy_queue()
	_ai._economy._try_train_crawler()
	assert_false(_queued_ids().has("crawler"),
		"no crawler while the mine has no crew to protect")
	for i in range(3):
		_spawn_miner(ENEMY, _mine_entry(ENEMY).call("get_underground_position"))
	_drain_enemy_queue()
	_ai._economy._try_train_crawler()
	assert_true(_queued_ids().has("crawler"),
		"the guard is hired once the crew is back at 3")


func test_easy_ai_never_trains_crawlers() -> void:
	GameManager.set_difficulty(GameManager.Difficulty.EASY)  # smarts tier 0
	_set_enemy_coin(1000)
	_spawn_miner(ENEMY, _mine_entry(ENEMY).call("get_underground_position"))
	_drain_enemy_queue()
	_ai._economy._try_train_crawler()
	assert_false(_queued_ids().has("crawler"), "Easy never fields crawlers")


# ─── Underground defense (ai_crawlers) ───

func test_ai_intercepts_enemy_raider_attacking_miners() -> void:
	_grid.set_reveal_all(ENEMY, true)
	var base: Vector2 = _mine_entry(ENEMY).call("get_underground_position")
	var miner: Node2D = _spawn_miner(ENEMY, base + Vector2(64, 0))
	var intruder: Node2D = _spawn_unit("res://scripts/resources/units/swordsman.tres", PLAYER, base + Vector2(32, 0), true)
	var guard: Node2D = _spawn_crawler(ENEMY, base)
	await wait_seconds(0.2)
	_ai._crawlers._run_crawlers()
	assert_gt(_ai._crawlers._detect_threats().size(), 0, "visible underground intruder detected")
	assert_eq(guard.get("_target_unit"), intruder, "guard converges on the raider")
	assert_eq(guard.get("_state"), Unit.State.ATTACK, "guard is attacking")


func test_ai_shelters_damaged_miner_and_releases_after_threat_clears() -> void:
	_grid.set_reveal_all(ENEMY, true)
	var base: Vector2 = _mine_entry(ENEMY).call("get_underground_position")
	var miner: Node2D = _spawn_miner(ENEMY, base + Vector2(64, 0))
	var intruder: Node2D = _spawn_unit("res://scripts/resources/units/swordsman.tres", PLAYER, base + Vector2(32, 0), true)
	miner.take_damage(5, intruder)
	assert_gt(miner.get_incoming_dps(), 0.0, "setup: miner under attack")
	_ai._crawlers._run_crawlers()
	assert_true(miner.get("shelter_in_place"), "damaged miner sheltered")
	assert_true(_ai._crawlers._sheltered_miners.has(miner), "miner tracked as sheltered")
	# Kill the intruder, then let its hits age out of the 3s damage window.
	intruder.free()
	await wait_seconds(3.5)
	_ai._crawlers._run_crawlers()
	assert_false(miner.get("shelter_in_place"), "miner released once the threat clears")
	assert_false(_ai._crawlers._sheltered_miners.has(miner), "sheltered list cleared")


func test_environmental_damage_does_not_shelter_miners() -> void:
	_grid.set_reveal_all(ENEMY, true)
	var base: Vector2 = _mine_entry(ENEMY).call("get_underground_position")
	var miner: Node2D = _spawn_miner(ENEMY, base + Vector2(64, 0))
	# Cave-ins/lava call take_damage with no attacker, environmental = true.
	miner.take_damage(10, null, true)
	assert_eq(miner.get_incoming_dps(), 0.0, "environmental hits never enter the damage window")
	_ai._crawlers._run_crawlers()
	assert_false(miner.get("shelter_in_place"), "a cave-in is not an attack — no shelter")
	assert_true(_ai._crawlers._sheltered_miners.is_empty(), "nobody sheltered")


func test_wandering_enemy_miner_does_not_trigger_shelter() -> void:
	_grid.set_reveal_all(ENEMY, true)
	var base: Vector2 = _mine_entry(ENEMY).call("get_underground_position")
	var miner: Node2D = _spawn_miner(ENEMY, base + Vector2(64, 0))
	# A non-Brute enemy miner on the AI's half: visible, but not combat-capable.
	_spawn_miner(PLAYER, base + Vector2(32, 0))
	_ai._crawlers._run_crawlers()
	assert_true(_ai._crawlers._detect_threats().is_empty(), "harmless enemy miner is not a threat")
	assert_false(miner.get("shelter_in_place"), "no shelter from a harmless intruder")


func test_brute_enemy_miner_is_a_threat() -> void:
	FactionManager.player_faction_id = "brute"
	_grid.set_reveal_all(ENEMY, true)
	var base: Vector2 = _mine_entry(ENEMY).call("get_underground_position")
	var miner: Node2D = _spawn_miner(ENEMY, base + Vector2(64, 0))
	_spawn_miner(PLAYER, base + Vector2(32, 0))  # Fight Back makes it combat-capable
	_ai._crawlers._run_crawlers()
	assert_eq(_ai._crawlers._detect_threats().size(), 1, "a Brute miner can fight back — it counts")
	assert_true(miner.get("shelter_in_place"), "miners near a Brute intruder shelter")


# ─── Raiding (wall-dependent: the intact-wall test runs before the breaches) ───

func test_ai_never_raids_while_wall_stands() -> void:
	assert_gt(_grid.get_wall_hp(), 0, "precondition: wall intact")
	for i in range(3):
		_spawn_crawler(ENEMY, _mine_entry(ENEMY).call("get_underground_position"))
	_ai._crawlers._manage_raid()
	assert_eq(_ai._crawlers._raiders.size(), 0, "no raid while the central wall stands")


func test_ai_holds_raid_while_defending() -> void:
	_breach_wall()
	assert_eq(_grid.get_wall_hp(), 0, "setup: wall breached")
	_ai._aggression_level = "defend"
	for i in range(3):
		_spawn_crawler(ENEMY, _mine_entry(ENEMY).call("get_underground_position"))
	_ai._crawlers._manage_raid()
	assert_eq(_ai._crawlers._raiders.size(), 0, "a defending army keeps the guard home")


func test_ai_raids_through_breached_wall() -> void:
	_breach_wall()
	_ai._aggression_level = "balanced"
	var c1: Node2D = _spawn_crawler(ENEMY, _mine_entry(ENEMY).call("get_underground_position"))
	var c2: Node2D = _spawn_crawler(ENEMY, _mine_entry(ENEMY).call("get_underground_position") + Vector2(32, 0))
	var c3: Node2D = _spawn_crawler(ENEMY, _mine_entry(ENEMY).call("get_underground_position") + Vector2(64, 0))
	_ai._crawlers._manage_raid()
	assert_eq(_ai._crawlers._raiders.size(), 2, "all but one crawler raid")
	for r in _ai._crawlers._raiders:
		var hunts_miner: bool = r.get("_target_unit") != null and r.get("_target_unit").get("team") == PLAYER
		var marches_west: bool = r.get("_target_position").x < 0.0
		assert_true(hunts_miner or marches_west, "raider ordered into the player mine")
	assert_true(c1 != null and c2 != null and c3 != null, "fixtures alive")


func test_ai_raid_retreats_when_outnumbered() -> void:
	_breach_wall()
	_ai._aggression_level = "balanced"
	_spawn_crawler(ENEMY, _mine_entry(ENEMY).call("get_underground_position"))
	_spawn_crawler(ENEMY, _mine_entry(ENEMY).call("get_underground_position") + Vector2(32, 0))
	_ai._crawlers._manage_raid()
	assert_eq(_ai._crawlers._raiders.size(), 1, "one of two crawlers raids")
	var raider: Node2D = _ai._crawlers._raiders[0]
	# Two player crawlers visible underground outnumber the lone raider.
	var player_base: Vector2 = _mine_entry(PLAYER).call("get_underground_position")
	_spawn_crawler(PLAYER, player_base + Vector2(48, 0))
	_spawn_crawler(PLAYER, player_base + Vector2(96, 0))
	_grid.set_reveal_all(ENEMY, true)
	assert_eq(_ai._crawlers._visible_enemy_crawlers(), 2, "both player crawlers visible")
	_ai._crawlers._manage_raid()
	assert_eq(_ai._crawlers._raiders.size(), 0, "outnumbered raid disbands")
	assert_gt(raider.get("_target_position").x, 0.0, "raider ordered back to the own mine")
