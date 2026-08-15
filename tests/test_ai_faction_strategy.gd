extends GutTest

# Faction-specific AI strategy (Revamp Phase 8, revamp.md 9.2): Arcane rushes
# wizards and techs Crystal Forge, Brute masses swordsmen toward Siege
# Master, Industrial fast-expands with a bigger mining crew and prefers
# Guerrilla Tactics.

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


func after_each() -> void:
	GameManager.set_difficulty(GameManager.Difficulty.NORMAL)
	# Autoload picks persist across tests by design: never leak them.
	FactionManager.set_player_faction("")
	FactionManager.enemy_faction_id = ""


func test_arcane_ai_rushes_wizards() -> void:
	FactionManager.enemy_faction_id = "arcane"
	assert_eq(_ai._pick_fighter_to_train(10000), "wizard", "Arcane opens with wizards")


func test_brute_ai_masses_swordsmen() -> void:
	FactionManager.enemy_faction_id = "brute"
	assert_eq(_ai._pick_fighter_to_train(10000), "swordsman", "Brute opens with swordsmen")


func test_factionless_ai_keeps_balanced_mix() -> void:
	assert_eq(_ai._pick_fighter_to_train(10000), "swordsman", "the default mix leads with swordsmen (0.4 share)")


func test_arcane_ai_climbs_to_crystal_forge() -> void:
	FactionManager.enemy_faction_id = "arcane"
	assert_eq(_ai._pick_research(null), "deep_delve", "Arcane takes the deep side of tier 1")
	ResearchManager._levels[ENEMY]["deep_delve"] = 1
	assert_eq(_ai._pick_research(null), "arctic_training", "Arcane picks Arctic Training after committing to a side")
	ResearchManager._levels[ENEMY]["arctic_training"] = 1
	assert_eq(_ai._pick_research(null), "ore_sonar", "Arcane climbs the deep side tier 2")
	ResearchManager._levels[ENEMY]["ore_sonar"] = 1
	assert_eq(_ai._pick_research(null), "crystal_forge", "Arcane heads for Crystal Forge")


func test_brute_ai_climbs_to_siege_master() -> void:
	FactionManager.enemy_faction_id = "brute"
	assert_eq(_ai._pick_research(null), "surface_war", "Brute takes the war side of tier 1")
	ResearchManager._levels[ENEMY]["surface_war"] = 1
	ResearchManager._levels[ENEMY]["arctic_training"] = 1
	ResearchManager._levels[ENEMY]["longbow"] = 1
	assert_eq(_ai._pick_research(null), "siege_master", "Brute heads for Siege Master")


func test_industrial_ai_prefers_guerrilla_tactics() -> void:
	FactionManager.enemy_faction_id = "industrial"
	assert_eq(_ai._pick_research(null), "surface_war", "Industrial takes the war side of tier 1")
	ResearchManager._levels[ENEMY]["surface_war"] = 1
	ResearchManager._levels[ENEMY]["arctic_training"] = 1
	ResearchManager._levels[ENEMY]["longbow"] = 1
	assert_eq(_ai._pick_research(null), "guerrilla", "Industrial prefers Guerrilla Tactics over Siege Master")


func test_industrial_ai_fields_a_bigger_mining_crew() -> void:
	_drain_enemy_queue()
	_set_enemy_coin(50)  # below the L2 reserve: no upgrade, miner level stays 1
	# Pin the crew at the DEFAULT quota (5 + level*2 = 7): a factionless AI
	# stops here, Industrial keeps going (target 9).
	while _ai._count_miners() < 7:
		_spawn_unit("res://scripts/resources/units/miner.tres", ENEMY, Vector2(430 + _ai._count_miners() * 8, 16))
	FactionManager.enemy_faction_id = "industrial"
	_ai._run_economy()
	assert_eq(_queued_miner_count(), 1, "Industrial keeps training miners past the default quota")
	_drain_enemy_queue()
	_set_enemy_coin(50)
	FactionManager.enemy_faction_id = ""
	_ai._run_economy()
	assert_eq(_queued_miner_count(), 0, "a factionless AI stops at the default quota")


func _queued_miner_count() -> int:
	var n: int = 0
	for entry in _building_for(ENEMY).call("get_queue"):
		if entry.id == "miner":
			n += 1
	return n


func _spawn_unit(tres_path: String, team: int, pos: Vector2) -> Node2D:
	var unit: Node2D = load("res://scenes/unit.tscn").instantiate()
	unit.set("data", load(tres_path).duplicate(true))
	unit.set("team", team)
	unit.position = pos
	_units.add_child(unit)
	autofree(unit)
	return unit


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


func _building_for(team: int) -> Node2D:
	for b in get_tree().get_nodes_in_group("buildings"):
		if b.get("team") == team:
			return b
	return null
