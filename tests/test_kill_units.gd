extends GutTest

# Disbanding units: the owner can kill units they no longer want — no coin
# refund, but the population slot is freed (a miner's cargo still drops as a
# pickup like any death). The AI uses the same command to cull surplus miners
# when the population cap blocks its army growth.

const PLAYER: int = 0
const ENEMY: int = 1

var _main: Node
var _units: Node


func before_all() -> void:
	# Deterministic map: Constants.DEBUG is off (so GridWorld doesn't seed
	# itself), but the tests assert against specific layouts.
	seed(12345)
	_main = load("res://scenes/main.tscn").instantiate()
	get_tree().root.add_child(_main)
	get_tree().current_scene = _main
	_units = _main.get_node("Units")


func after_all() -> void:
	# Free immediately, not queue_free(): these tests never await, so a queued
	# free would still be pending when the next test script instantiates its
	# own main.tscn — the old "Main" name would still be taken, the new scene
	# would be renamed, and every hard-coded /root/Main lookup would break.
	_main.free()


func before_each() -> void:
	EconomyManager.reset()


func _spawn_unit(tres_path: String, team: int, pos: Vector2) -> Node2D:
	var unit: Node2D = load("res://scenes/unit.tscn").instantiate()
	unit.set("data", load(tres_path).duplicate(true))
	unit.set("team", team)
	unit.position = pos
	_units.add_child(unit)
	autofree(unit)
	return unit


func _count_live_miners(team: int) -> int:
	var group: String = "player" if team == PLAYER else "enemy"
	var n: int = 0
	for u in get_tree().get_nodes_in_group(group):
		if u.data.is_miner and u.get("_state") != 9:  # State.DEAD == 9
			n += 1
	return n


func test_kill_disbands_without_refund() -> void:
	var fighter: Node2D = _spawn_unit("res://scripts/resources/units/swordsman.tres", PLAYER, Vector2(-480, 16))
	EconomyManager.add_population(PLAYER, 1)
	var coin_before: int = EconomyManager.get_coin(PLAYER)
	fighter.call("kill")
	assert_eq(fighter.get("_state"), 9, "killed unit dies")  # State.DEAD == 9
	assert_eq(EconomyManager.get_population(PLAYER), 0, "population slot freed")
	assert_eq(EconomyManager.get_coin(PLAYER), coin_before, "no coin refund")


func test_killed_miner_drops_cargo_pickup() -> void:
	# kill() goes through _die(), so the cargo-is-never-lost rule holds for
	# disbands too: the miner drops a pickup where it died.
	var miner: Node2D = _spawn_unit("res://scripts/resources/units/miner.tres", PLAYER, Vector2(-300, 80))
	miner.set("carried_coin", 15)
	miner.call("kill")
	var found: CoinPickup = null
	for child in _main.get_children():
		if child is CoinPickup:
			found = child
	assert_not_null(found, "disbanded miner drops its cargo as a pickup")
	if found:
		assert_eq(found.coin_value, 15)
		assert_true(found.global_position.distance_to(Vector2(-300, 80)) < 1.0)
		found.free()


func test_idle_miner_collects_nearby_dropped_gold() -> void:
	# An idle underground miner with an empty bag should seek out a coin pickup
	# from a dead miner and collect it so the gold can be deposited.
	var cell_size: int = GridWorld.CELL_SIZE
	var miner_pos: Vector2 = Vector2(-15 * cell_size, 3 * cell_size + cell_size * 0.5)
	var miner: Node2D = _spawn_unit("res://scripts/resources/units/miner.tres", PLAYER, miner_pos)
	miner.is_underground = true

	var pickup: CoinPickup = preload("res://scenes/effects/coin_pickup.tscn").instantiate()
	pickup.global_position = miner_pos
	pickup.coin_value = 12
	_main.add_child(pickup)
	autofree(pickup)

	await wait_seconds(0.3)
	assert_eq(miner.carried_coin, 12, "idle miner should collect dropped gold")
	assert_true(miner.get("_deposit_requested"), "collected gold should be flagged for deposit")
	assert_false(is_instance_valid(pickup), "pickup should be consumed")


func test_kill_selected_only_kills_the_selection() -> void:
	var pc: Node = _main.get_node("PlayerController")
	var chosen: Node2D = _spawn_unit("res://scripts/resources/units/swordsman.tres", PLAYER, Vector2(-480, 16))
	var spared: Node2D = _spawn_unit("res://scripts/resources/units/swordsman.tres", PLAYER, Vector2(-460, 16))
	pc._select_units([chosen])
	pc.kill_selected()
	assert_eq(chosen.get("_state"), 9, "selected unit disbanded")  # State.DEAD == 9
	assert_ne(spared.get("_state"), 9, "unselected unit untouched")
	assert_eq(pc.get_selected_units().size(), 0, "dead units leave the selection")


func test_ai_culls_surplus_miners_at_population_cap() -> void:
	# Boxed in at the cap, the AI disbands miners beyond 3 so the freed slots
	# can become fighters.
	for i in range(5):
		_spawn_unit("res://scripts/resources/units/miner.tres", ENEMY, Vector2(440 + i * 20, 80))
	EconomyManager.add_population(ENEMY, 100)
	# The free starting miners trickle out of the training queue over the
	# first seconds of a match, so don't assume they've spawned — measure.
	var miners_before: int = _count_live_miners(ENEMY)
	assert_true(miners_before >= 5, "scenario needs surplus miners")
	_main.get_node("AIController")._run_economy()
	assert_eq(_count_live_miners(ENEMY), 3, "AI keeps 3 miners and culls the rest")
	assert_eq(EconomyManager.get_population(ENEMY), 100 - (miners_before - 3), "culled slots are freed")


func test_ai_does_not_cull_below_cap() -> void:
	for i in range(5):
		_spawn_unit("res://scripts/resources/units/miner.tres", ENEMY, Vector2(440 + i * 20, 80))
	var miners_before: int = _count_live_miners(ENEMY)
	_main.get_node("AIController")._run_economy()
	assert_eq(_count_live_miners(ENEMY), miners_before, "no culling while there is room to train")
