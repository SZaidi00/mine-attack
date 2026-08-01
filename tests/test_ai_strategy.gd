extends GutTest

# AI strategy: the economy tick must bank for miner upgrades (the old free
# spending kept the wallet under 500 forever, so miners never passed level 1),
# train a mixed army, and launch attacks as gathered waves instead of feeding
# one fighter at a time.

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


func test_ai_does_not_spend_the_upgrade_bank_on_fighters() -> void:
	# 400 coin: affordable fighters exist, but the L2 upgrade costs 500 — the
	# AI must keep banking (miners are exempt: they pay for themselves).
	EconomyManager.spend_coin(ENEMY, 100)
	_ai._run_economy()
	var queue: Array = _building_for(ENEMY).call("get_queue")
	assert_eq(EconomyManager.get_miner_level(ENEMY), 1)
	for entry in queue:
		assert_eq(entry.id, "miner", "below the upgrade bank the AI may only train miners")


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
