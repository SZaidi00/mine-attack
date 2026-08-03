extends GutTest

# AI strategy: the economy tick must bank for miner upgrades (the old free
# spending kept the wallet under 500 forever, so miners never passed level 1),
# while fighter training trickles on against a 60% partial bank so the army
# never stalls, and attacks launch as gathered waves — smaller and more often
# on higher difficulties — instead of feeding one fighter at a time.

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


func test_ai_banks_and_buys_miner_upgrade() -> void:
	EconomyManager.add_coin(ENEMY, 600)  # 500 start + 600 = 1100, level 1
	_ai._run_economy()
	assert_eq(EconomyManager.get_miner_level(ENEMY), 2, "AI must buy the L2 miner upgrade as soon as it can afford it")


func test_fighter_training_dips_into_partial_bank() -> void:
	# Fill the miner quota so the queue decision falls through to fighters.
	for i in range(7):
		_spawn_unit("res://scripts/resources/units/miner.tres", ENEMY, Vector2(430 + i * 8, 16))
	_drain_enemy_queue()
	_set_enemy_coin(400)  # below the 500 L2 reserve, above the 300 partial bank
	_ai._run_economy()
	var queue: Array = _building_for(ENEMY).call("get_queue")
	var has_fighter: bool = false
	for entry in queue:
		if entry.id != "miner":
			has_fighter = true
	assert_true(has_fighter, "a 100-coin fighter must fit a 400-coin wallet via the 60% partial bank")


func test_fighter_training_holds_below_partial_bank() -> void:
	for i in range(7):
		_spawn_unit("res://scripts/resources/units/miner.tres", ENEMY, Vector2(430 + i * 8, 16))
	_drain_enemy_queue()
	_set_enemy_coin(200)  # below the 300 partial bank: banking takes priority
	_ai._run_economy()
	var queue: Array = _building_for(ENEMY).call("get_queue")
	assert_true(queue.is_empty(), "below the partial bank (and at miner quota) nothing is queued")


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
	# Simulate income ticks: even while training miners every tick, the bank
	# must grow to 500 and buy the upgrade (the old AI drained the wallet).
	EconomyManager.spend_coin(ENEMY, 450)  # 50 left
	for i in range(20):
		if EconomyManager.get_miner_level(ENEMY) >= 2:
			break
		EconomyManager.add_coin(ENEMY, 100)  # mining income
		_ai._run_economy()
	assert_eq(EconomyManager.get_miner_level(ENEMY), 2, "bank must grow to 500 despite ongoing miner training")


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
