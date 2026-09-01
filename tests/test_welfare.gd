extends GutTest

# Welfare trickle (EconomyManager): a team with zero living miners and not
# enough coin to buy one gains WELFARE_COIN every WELFARE_INTERVAL seconds of
# game time, so a wiped economy can always re-staff eventually. The AI's payout
# is scaled by the difficulty coin multiplier (rates, never rules). No trickle
# while miners live or while the wallet already affords a miner.

const PLAYER: int = 0  # GameManager.Team.PLAYER
const ENEMY: int = 1   # GameManager.Team.ENEMY

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
	# Flush the buildings' deferred starting-miner spawns.
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


func _kill_all_miners(team: int) -> void:
	var group: String = "player" if team == PLAYER else "enemy"
	for unit in get_tree().get_nodes_in_group(group):
		if unit.data.is_miner and unit._state != Unit.State.DEAD:
			unit.kill()


## Pins a team's wallet to an exact amount regardless of background income.
func _set_coin(team: int, amount: int) -> void:
	var coin: int = EconomyManager.get_coin(team)
	if coin > amount:
		EconomyManager.spend_coin(team, coin - amount)
	elif coin < amount:
		EconomyManager.add_coin(team, amount - coin)


func test_welfare_pays_out_when_economy_wiped() -> void:
	_kill_all_miners(PLAYER)
	_set_coin(PLAYER, 20)  # below the 50g miner cost
	EconomyManager._process(Constants.WELFARE_INTERVAL)
	assert_eq(EconomyManager.get_coin(PLAYER), 20 + Constants.WELFARE_COIN,
		"a wiped, broke team must receive the welfare payout")


func test_welfare_waits_a_full_interval() -> void:
	_kill_all_miners(PLAYER)
	_set_coin(PLAYER, 0)
	EconomyManager._process(Constants.WELFARE_INTERVAL - 1.0)
	assert_eq(EconomyManager.get_coin(PLAYER), 0, "no payout before the interval elapses")


func test_welfare_scales_for_ai_with_difficulty() -> void:
	GameManager.set_difficulty(GameManager.Difficulty.NORMAL)  # coin x1.15
	_kill_all_miners(ENEMY)
	_set_coin(ENEMY, 0)
	EconomyManager._process(Constants.WELFARE_INTERVAL)
	assert_eq(EconomyManager.get_coin(ENEMY), roundi(Constants.WELFARE_COIN * 1.15),
		"the AI payout scales with the difficulty coin multiplier")


func test_welfare_skipped_while_miners_live() -> void:
	var miner: Node2D = load("res://scenes/unit.tscn").instantiate()
	miner.set("data", load("res://scripts/resources/units/miner.tres").duplicate(true))
	miner.set("team", PLAYER)
	miner.position = Vector2(-430, 16)
	_units.add_child(miner)
	autofree(miner)
	_set_coin(PLAYER, 0)
	EconomyManager._process(Constants.WELFARE_INTERVAL)
	assert_eq(EconomyManager.get_coin(PLAYER), 0, "a living miner means no welfare")


func test_welfare_skipped_when_miner_affordable() -> void:
	_kill_all_miners(PLAYER)
	# Default wallet after reset: 500 — already buys a 50g miner.
	EconomyManager._process(Constants.WELFARE_INTERVAL)
	assert_eq(EconomyManager.get_coin(PLAYER), 500, "a team that can afford a miner gets no welfare")
