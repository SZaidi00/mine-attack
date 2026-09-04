extends GutTest

# AI strategy: the economy tick saves for ONE purchase at a time in build
# order (first lantern → L2 miners → first tower) and holds fighter spending
# while a save goal is active — the old 60%-partial-bank rule let continuous
# fighter spending pin the wallet just under the fund forever, so the AI never
# teched or fortified. Two exemptions: miner training (miners fund the save)
# and a skeleton standing army (ENEMY_DESPERATE_WAVE_SIZE fighters) so the AI
# never teches naked. Miner upgrades wait for a real crew (blowing the 500g
# opening wallet on an upgrade for 2 miners left the AI broke for minutes).
# Miner and fighter training interleave one-per-queue-slot so the early army
# grows in parallel with the mining crew, and attacks launch as gathered waves
# — smaller and more often on higher difficulties — instead of feeding one
# fighter at a time.

const PLAYER: int = 0
const ENEMY: int = 1

var _main: Node
var _units: Node
var _ai: Node


func before_all() -> void:
	# Deterministic map: Constants.DEBUG is off (so GridWorld doesn't seed
	# itself), but the tests assert against specific layouts.
	seed(12345)
	_main = load("res://scenes/main.tscn").instantiate()
	get_tree().root.add_child(_main)
	get_tree().current_scene = _main
	_units = _main.get_node("Units")
	_ai = _main.get_node("AIController")
	# Flush the buildings' deferred starting-miner spawns so tests run against
	# the real match-start state (2 miners per side).
	await get_tree().process_frame


func after_all() -> void:
	# Free immediately, not queue_free(): these tests never await, so a queued
	# free would still be pending when the next test script instantiates its
	# own main.tscn — the old "Main" name would still be taken, the new scene
	# would be renamed, and every hard-coded /root/Main lookup would break.
	_main.free()


func before_each() -> void:
	EconomyManager.reset()
	ResearchManager.reset()


func after_each() -> void:
	# GameManager is an autoload: never leak a difficulty choice into the
	# next test script.
	GameManager.set_difficulty(GameManager.Difficulty.NORMAL)
	# Structure fixtures are added to the scene, not autofree'd.
	for lantern in get_tree().get_nodes_in_group("lanterns"):
		if lantern.team == ENEMY:
			lantern.free()
	for tower in get_tree().get_nodes_in_group("towers"):
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


func _building_for(team: int) -> Node2D:
	for b in get_tree().get_nodes_in_group("buildings"):
		if b.get("team") == team:
			return b
	return null


func test_ai_banks_and_buys_miner_upgrade() -> void:
	# A full crew (5: 2 starting + 3) — upgrades wait for bodies now.
	for i in range(3):
		_spawn_unit("res://scripts/resources/units/miner.tres", ENEMY, Vector2(430 + i * 8, 16))
	EconomyManager.add_coin(ENEMY, 600)  # 500 start + 600 = 1100, level 1
	_ai._run_economy()
	assert_eq(EconomyManager.get_miner_level(ENEMY), 2, "AI must buy the L2 miner upgrade as soon as a full crew can afford it")


func test_miner_upgrade_waits_for_a_real_crew() -> void:
	_set_enemy_coin(1500)
	_ai._run_economy()
	assert_eq(EconomyManager.get_miner_level(ENEMY), 1,
		"two miners are a crew-in-progress: the 500g upgrade waits while bodies come first")
	for i in range(3):
		_spawn_unit("res://scripts/resources/units/miner.tres", ENEMY, Vector2(430 + i * 8, 16))
	_set_enemy_coin(1500)
	_ai._run_economy()
	assert_eq(EconomyManager.get_miner_level(ENEMY), 2,
		"with a full crew the upgrade buys the moment the bank completes")


func test_miner_and_fighter_training_interleave() -> void:
	# No active save goal: both structures already stand and the crew is too
	# small for the L2 goal, so the tick spends freely.
	_spawn_lantern(ENEMY, Vector2(_building_for(ENEMY).global_position.x - 160, 16))
	_spawn_tower(ENEMY, Vector2(800, 16))
	_drain_enemy_queue()
	_set_enemy_coin(600)
	_ai._run_economy()
	var queue: Array = _building_for(ENEMY).call("get_queue")
	assert_eq(queue.size(), 1, "scenario needs exactly the miner queued")
	assert_eq(queue[0].id, "miner", "below the quota, a miner goes in first")
	_set_enemy_coin(600)  # organic upgrade/research buys may have skimmed tick 1
	_ai._run_economy()
	queue = _building_for(ENEMY).call("get_queue")
	assert_eq(queue.size(), 2, "the next tick queues a second unit")
	assert_ne(queue[1].id, "miner", "never a miner behind a miner: the army grows in parallel")


func test_fighter_training_holds_while_saving() -> void:
	# Fill the miner quota so the queue decision falls through to fighters,
	# and field the skeleton army (3) so the save-goal hold actually applies.
	for i in range(7):
		_spawn_unit("res://scripts/resources/units/miner.tres", ENEMY, Vector2(430 + i * 8, 16))
	for i in range(3):
		_spawn_unit("res://scripts/resources/units/swordsman.tres", ENEMY, Vector2(700 + i * 8, 16))
	_drain_enemy_queue()
	_set_enemy_coin(400)  # covers a fighter twice over, but the first-lantern fund is open
	_ai._run_economy()
	var queue: Array = _building_for(ENEMY).call("get_queue")
	assert_true(queue.is_empty(), "past the skeleton army, fighter spending holds while saving for the first lantern")


func test_save_goal_keeps_a_skeleton_army() -> void:
	# Same save goal, but only 2 fighters standing: the AI still trains up to
	# the raid/defense minimum so it never teches naked.
	for i in range(7):
		_spawn_unit("res://scripts/resources/units/miner.tres", ENEMY, Vector2(430 + i * 8, 16))
	for i in range(2):
		_spawn_unit("res://scripts/resources/units/swordsman.tres", ENEMY, Vector2(700 + i * 8, 16))
	_drain_enemy_queue()
	_set_enemy_coin(400)
	_ai._run_economy()
	var queue: Array = _building_for(ENEMY).call("get_queue")
	var has_fighter: bool = false
	for entry in queue:
		if entry.id != "miner":
			has_fighter = true
	assert_true(has_fighter, "below the skeleton army floor the AI keeps training fighters even mid-save")


func test_fighter_training_flows_with_no_save_goal() -> void:
	# Build order complete (lantern + tower standing, L2 miners): free spending.
	_spawn_lantern(ENEMY, Vector2(_building_for(ENEMY).global_position.x - 160, 16))
	_spawn_tower(ENEMY, Vector2(800, 16))
	for i in range(7):
		_spawn_unit("res://scripts/resources/units/miner.tres", ENEMY, Vector2(430 + i * 8, 16))
	EconomyManager.add_coin(ENEMY, 1000)
	EconomyManager.upgrade_miner(ENEMY)  # L2 — the save-goal ladder is done
	_drain_enemy_queue()
	_set_enemy_coin(400)
	_ai._run_economy()
	var queue: Array = _building_for(ENEMY).call("get_queue")
	var has_fighter: bool = false
	for entry in queue:
		if entry.id != "miner":
			has_fighter = true
	assert_true(has_fighter, "with no save goal a 400-coin wallet trains a fighter")


func test_save_goal_follows_the_build_order() -> void:
	_ai._aggression_level = "balanced"
	for i in range(3):
		_spawn_unit("res://scripts/resources/units/miner.tres", ENEMY, Vector2(430 + i * 8, 16))
	assert_eq(_ai._economy._current_save_goal(5, 1), Lantern.cost_for(false, 1),
		"vision first: the save ladder opens with the first lantern")
	_spawn_lantern(ENEMY, Vector2(_building_for(ENEMY).global_position.x - 160, 16))
	assert_eq(_ai._economy._current_save_goal(5, 1), Constants.MINER_UPGRADE_COSTS[2],
		"with vision up, a full crew saves for the L2 economy")
	assert_eq(_ai._economy._current_save_goal(5, 2), FactionManager.get_tower_cost(ENEMY),
		"with the L2 economy running, the AI fortifies")
	_spawn_tower(ENEMY, Vector2(800, 16))
	assert_eq(_ai._economy._current_save_goal(5, 2), 0,
		"build order complete: the wallet opens for fighters and tech")


## Removes everything the enemy building has queued (e.g. from the AI's own
## background ticks between tests) so queue assertions start clean.
func _drain_enemy_queue() -> void:
	var building: Node2D = _building_for(ENEMY)
	while not building.call("get_queue").is_empty():
		building.call("cancel_queue", 0)


## Normalizes the enemy wallet to an exact amount (queue cancels refund coin,
## so the wallet must be re-pinned after draining).
func _set_enemy_coin(amount: int) -> void:
	var coin: int = EconomyManager.get_coin(ENEMY)
	if coin > amount:
		EconomyManager.spend_coin(ENEMY, coin - amount)
	elif coin < amount:
		EconomyManager.add_coin(ENEMY, amount - coin)


func test_ai_eventually_affords_upgrade_while_training_miners() -> void:
	# Simulate income ticks: even while training units every tick, the bank
	# must grow to 500 and buy the upgrade (the old AI drained the wallet).
	# A full crew (5) is required for the upgrade to buy at all.
	for i in range(3):
		_spawn_unit("res://scripts/resources/units/miner.tres", ENEMY, Vector2(430 + i * 8, 16))
	EconomyManager.spend_coin(ENEMY, 450)  # 50 left
	for i in range(20):
		if EconomyManager.get_miner_level(ENEMY) >= 2:
			break
		EconomyManager.add_coin(ENEMY, 100)  # mining income
		_ai._run_economy()
	assert_eq(EconomyManager.get_miner_level(ENEMY), 2, "bank must grow to 500 despite ongoing training")


func test_army_mix_prefers_frontline_then_diversifies() -> void:
	var first: String = _ai._pick_fighter_to_train(1000)
	assert_eq(first, "swordsman", "first pick with an empty army should be frontline")
	var swordsmen: Array = []
	for i in range(4):
		swordsmen.append(_spawn_unit("res://scripts/resources/units/swordsman.tres", ENEMY, Vector2(430, 16)))
	var next: String = _ai._pick_fighter_to_train(1000)
	assert_ne(next, "swordsman", "with the swordsman share filled the AI must diversify")


func test_wave_holds_below_threshold() -> void:
	_ai._aggression_level = "balanced"  # threshold 7
	var fighters: Array = []
	for i in range(4):
		fighters.append(_spawn_unit("res://scripts/resources/units/swordsman.tres", ENEMY, Vector2(-440, 16)))
	_ai._launch_wave_if_ready()
	for f in fighters:
		assert_null(f.get("_target_building"), "small armies must hold, not trickle in")


func test_wave_launches_together_at_threshold() -> void:
	_ai._aggression_level = "balanced"  # threshold 7
	var player_building: Node2D = _building_for(PLAYER)
	var fighters: Array = []
	for i in range(7):
		fighters.append(_spawn_unit("res://scripts/resources/units/swordsman.tres", ENEMY, Vector2(-440, 16)))
	_ai._launch_wave_if_ready()
	for f in fighters:
		assert_eq(f.get("_target_building"), player_building, "at critical mass the whole wave marches together")


func test_wave_all_in_when_enemy_base_nearly_dead() -> void:
	_ai._aggression_level = "defend"  # normally threshold 12
	var player_building: Node2D = _building_for(PLAYER)
	player_building.set("_hp", int(player_building.get("max_hp") * 0.2))
	var fighters: Array = []
	for i in range(3):
		fighters.append(_spawn_unit("res://scripts/resources/units/swordsman.tres", ENEMY, Vector2(-440, 16)))
	_ai._launch_wave_if_ready()
	for f in fighters:
		assert_eq(f.get("_target_building"), player_building, "a nearly-dead enemy base triggers an all-in")
	player_building.set("_hp", player_building.get("max_hp"))


# Note: the wall-breach timing gate (_attempt_wall_breach, smarts tier 2+)
# is covered indirectly through the _simulate_combat tests in
# test_ai_micro.gd — staging "no accessible unmined tiles" on a fresh map is
# impractical, so the gate itself has no direct integration test.
func test_wave_threshold_scales_with_difficulty() -> void:
	# Hard has wave tempo 0.85: the balanced threshold becomes round(7 * 0.85) = 6.
	GameManager.set_difficulty(GameManager.Difficulty.HARD)
	_ai._aggression_level = "balanced"
	var fighters: Array = []
	for i in range(5):
		fighters.append(_spawn_unit("res://scripts/resources/units/swordsman.tres", ENEMY, Vector2(-440, 16)))
	_ai._launch_wave_if_ready()
	for f in fighters:
		assert_null(f.get("_target_building"), "5 fighters must hold on Hard (threshold 6)")
	var sixth: Node2D = _spawn_unit("res://scripts/resources/units/swordsman.tres", ENEMY, Vector2(-440, 16))
	_ai._launch_wave_if_ready()
	assert_eq(sixth.get("_target_building"), _building_for(PLAYER), "6 fighters must launch on Hard")


# ─── Anti-stall: combat-predictor veto escapes ───

func test_wave_veto_holds_when_outmatched_and_not_desperate() -> void:
	# Normal (smarts 2): the combat-predictor veto is active.
	GameManager.set_difficulty(GameManager.Difficulty.NORMAL)
	_ai._aggression_level = "balanced"  # threshold 7
	var fighters: Array = []
	for i in range(7):
		fighters.append(_spawn_unit("res://scripts/resources/units/swordsman.tres", ENEMY, Vector2(-440, 16)))
	for i in range(20):
		_spawn_unit("res://scripts/resources/units/swordsman.tres", PLAYER, Vector2(430, 16))
	_ai._last_wave_launched_at = GameManager.match_time  # fresh: no desperation
	_ai._launch_wave_if_ready()
	for f in fighters:
		assert_null(f.get("_target_building"), "a decisive-loss sim must veto the wave while the AI can still mass")


func test_desperate_wave_launches_despite_losing_sim() -> void:
	GameManager.set_difficulty(GameManager.Difficulty.NORMAL)
	_ai._aggression_level = "balanced"  # threshold 7
	var player_building: Node2D = _building_for(PLAYER)
	var fighters: Array = []
	for i in range(7):
		fighters.append(_spawn_unit("res://scripts/resources/units/swordsman.tres", ENEMY, Vector2(-440, 16)))
	for i in range(20):
		_spawn_unit("res://scripts/resources/units/swordsman.tres", PLAYER, Vector2(430, 16))
	# No wave has marched for longer than the (difficulty-scaled) desperation delay.
	_ai._last_wave_launched_at = GameManager.match_time \
		- Constants.ENEMY_WAVE_DESPERATION_DELAY * GameManager.get_ai_wave_multiplier() - 1.0
	_ai._launch_wave_if_ready()
	for f in fighters:
		assert_eq(f.get("_target_building"), player_building, "a desperate AI must march even into a losing fight")


func test_pop_cap_wave_launches_despite_losing_sim() -> void:
	GameManager.set_difficulty(GameManager.Difficulty.NORMAL)
	_ai._aggression_level = "balanced"  # threshold 7
	var player_building: Node2D = _building_for(PLAYER)
	var fighters: Array = []
	for i in range(7):
		fighters.append(_spawn_unit("res://scripts/resources/units/swordsman.tres", ENEMY, Vector2(-440, 16)))
	for i in range(20):
		_spawn_unit("res://scripts/resources/units/swordsman.tres", PLAYER, Vector2(430, 16))
	_ai._last_wave_launched_at = GameManager.match_time  # not desperate: pop cap is the escape under test
	EconomyManager.add_population(ENEMY, Constants.MAX_UNITS - 2)
	_ai._launch_wave_if_ready()
	for f in fighters:
		assert_eq(f.get("_target_building"), player_building, "a pop-capped army cannot grow — it must march despite the sim")


func test_dead_economy_skips_miner_upgrade_and_restaffs() -> void:
	for unit in get_tree().get_nodes_in_group("enemy"):
		if unit.data.is_miner and unit._state != Unit.State.DEAD:
			unit.kill()
	_drain_enemy_queue()
	_set_enemy_coin(1500)  # enough for the L2/L3 upgrade — but there is nothing to upgrade
	var level_before: int = EconomyManager.get_miner_level(ENEMY)
	_ai._run_economy()
	assert_eq(EconomyManager.get_miner_level(ENEMY), level_before,
		"with zero miners the AI must not sink coin into miner upgrades")
	var queue: Array = _building_for(ENEMY).call("get_queue")
	var has_miner: bool = false
	for entry in queue:
		if entry.id == "miner":
			has_miner = true
	assert_true(has_miner, "a wiped economy must re-staff miners before anything else")
