extends GutTest

# AI openers (GameManager.roll_ai_opener): one of balanced/rush/boom/turtle is
# rolled per real match, weighted by the enemy faction's personality. The
# opener shifts the wave-size threshold (ai_combat._wave_threshold), the miner
# quota (ai_economy), and the build order (ai_awareness: towers before
# lanterns — tower tests live in test_ai_awareness.gd). "balanced" is the
# neutral default the rest of the suite relies on; these tests set ai_opener
# directly and verify each lever moves.

const PLAYER: int = 0
const ENEMY: int = 1

var _main: Node
var _units: Node
var _ai: Node


func before_all() -> void:
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
	FactionManager.reset()
	FactionManager.enemy_faction_id = ""
	GameManager.ai_opener = "balanced"
	GameManager.game_active = true
	_ai._raiders.clear()
	_ai._aggression_level = "balanced"
	_ai._last_wave_desperate = false
	_ai._last_wave_launched_at = GameManager.match_time  # never desperate


func after_each() -> void:
	# GameManager is an autoload: never leak a difficulty or opener choice into
	# the next test script.
	GameManager.set_difficulty(GameManager.Difficulty.NORMAL)
	GameManager.ai_opener = "balanced"
	FactionManager.enemy_faction_id = ""


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


func _building_for(team: int) -> Node2D:
	for b in get_tree().get_nodes_in_group("buildings"):
		if b.get("team") == team:
			return b
	return null


func _drain_enemy_queue() -> void:
	var building: Node2D = _building_for(ENEMY)
	while building.call("get_queue").size() > 0:
		building.call("cancel_queue", 0)


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


# ─── Wave thresholds ───

func test_rush_opener_marches_with_a_smaller_army() -> void:
	GameManager.set_difficulty(GameManager.Difficulty.NORMAL)
	GameManager.ai_opener = "rush"  # 7 base × 1.0 wave × 0.7 = 4.9 → threshold 5
	var wave: Array = []
	for i in range(5):
		wave.append(_spawn_fighter(ENEMY, Vector2(700 + i * 8, 16)))
	_ai._launch_wave_if_ready()
	for f in wave:
		assert_eq(f.get("_target_building"), _building_for(PLAYER),
			"rush marches at 5 where balanced waits for 7")


func test_turtle_opener_masses_longer() -> void:
	GameManager.set_difficulty(GameManager.Difficulty.NORMAL)
	GameManager.ai_opener = "turtle"  # 7 base × 1.3 = 9.1 → threshold 9
	var wave: Array = []
	for i in range(7):
		wave.append(_spawn_fighter(ENEMY, Vector2(700 + i * 8, 16)))
	_ai._launch_wave_if_ready()
	for f in wave:
		assert_null(f.get("_target_building"), "turtle holds at 7 where balanced would march")


# ─── Miner quota ───

func test_boom_opener_expands_the_miner_quota() -> void:
	# 2 starting miners + 6 spawned = 8: past the balanced quota (7), short of
	# the boom quota (9).
	for i in range(6):
		_spawn_unit("res://scripts/resources/units/miner.tres", ENEMY, Vector2(700 + i * 8, 16))
	_drain_enemy_queue()
	_set_enemy_coin(400)  # below the 500 L2 reserve: banking, not upgrading
	_ai._run_economy()
	assert_false(_queued_ids().has("miner"), "balanced stops at 7 miners — the bank goes to fighters")
	_drain_enemy_queue()
	_set_enemy_coin(400)
	GameManager.ai_opener = "boom"
	_ai._run_economy()
	assert_true(_queued_ids().has("miner"), "boom expands the mining crew first")


# ─── The roll ───

func test_roll_ai_opener_picks_a_defined_opener() -> void:
	for i in range(20):
		GameManager.roll_ai_opener()
		assert_true(GameManager.AI_OPENERS.has(GameManager.ai_opener),
			"every roll lands on a defined opener")


func test_roll_ai_opener_leans_into_the_faction_personality() -> void:
	FactionManager.enemy_faction_id = "brute"
	var counts: Dictionary = { "rush": 0, "boom": 0 }
	for i in range(40):
		GameManager.roll_ai_opener()
		if counts.has(GameManager.ai_opener):
			counts[GameManager.ai_opener] += 1
	assert_gt(counts["rush"], counts["boom"], "Brute rushes far more than it booms (45 vs 10 weight)")
