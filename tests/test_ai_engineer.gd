extends GutTest

# AI engineer maintenance (ai_economy._try_train_engineer): the AI hires an
# engineer from surplus when one of its structures is damaged below
# ENEMY_ENGINEER_DAMAGE_FRACTION past the repair lockout — never as a save
# goal, never on Easy (smarts tier 0), never when the wallet is tight. The
# hired engineer needs no orders: idle auto-seek (unit_repair.gd) walks it to
# the nearest damaged own-side structure. Boots the real main.tscn; random
# events are disabled so nothing re-damages or heals the fixtures.

const PLAYER: int = 0
const ENEMY: int = 1

var _main: Node
var _ai: Node


func before_all() -> void:
	seed(12345)
	_main = load("res://scenes/main.tscn").instantiate()
	get_tree().root.add_child(_main)
	get_tree().current_scene = _main
	_ai = _main.get_node("AIController")
	WeatherManager.set_weather_events_enabled(false)
	WeatherManager.set_volcano_events_enabled(false)
	_main.get_node("World/GridWorld").set_dynamic_events_enabled(false)
	# Flush the buildings' deferred starting-miner spawns so tests run against
	# the real match-start state (2 miners per side).
	await get_tree().process_frame


func after_all() -> void:
	_main.free()


func before_each() -> void:
	EconomyManager.reset()
	ResearchManager.reset()
	FactionManager.reset()
	FactionManager.enemy_faction_id = ""
	GameManager.ai_opener = "balanced"
	GameManager.game_active = true
	_ai._aggression_level = "balanced"
	_drain_enemy_queue()
	# Heal the enemy base and age its damage stamp so repair tests start clean.
	var building: Node2D = _building_for(ENEMY)
	building.set("_hp", building.get("max_hp"))
	building.set("_last_damage_time", -999.0)


func after_each() -> void:
	# GameManager is an autoload: never leak a difficulty or opener choice into
	# the next test script.
	GameManager.set_difficulty(GameManager.Difficulty.NORMAL)
	GameManager.ai_opener = "balanced"
	# Structure and engineer fixtures are added to the scene, not autofree'd.
	for lantern in get_tree().get_nodes_in_group("lanterns"):
		if lantern.team == ENEMY:
			lantern.free()
	for u in get_tree().get_nodes_in_group("enemy"):
		if u.data != null and u.data.is_engineer:
			u.free()


func _spawn_unit(tres_path: String, team: int, pos: Vector2) -> Node2D:
	var unit: Node2D = load("res://scenes/unit.tscn").instantiate()
	unit.set("data", load(tres_path).duplicate(true))
	unit.set("team", team)
	unit.position = pos
	_main.get_node("Units").add_child(unit)
	autofree(unit)
	return unit


func _spawn_engineer(team: int, pos: Vector2) -> Node2D:
	return _spawn_unit("res://scripts/resources/units/engineer.tres", team, pos)


## Structure fixtures skip placement validation — they only need to exist in
## the group with the right team. after_each frees the ENEMY ones.
func _spawn_lantern(team: int, pos: Vector2) -> Node2D:
	var lantern: Node2D = load("res://scenes/lantern.tscn").instantiate()
	lantern.set("team", team)
	lantern.position = pos
	_main.get_node("Structures").add_child(lantern)
	return lantern


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


## Damages the enemy base to the given max-HP fraction, aging the damage stamp
## past the repair lockout so the structure is repairable.
func _damage_enemy_building(fraction: float) -> void:
	var building: Node2D = _building_for(ENEMY)
	building.set("_hp", int(building.get("max_hp") * fraction))
	building.set("_last_damage_time", GameManager.match_time - 10.0)


## A standing surface lantern clears the first-lantern save goal, so the
## economy ticks below run in free-spending mode unless a test says otherwise.
func _clear_save_goal() -> void:
	_spawn_lantern(ENEMY, Vector2(_building_for(ENEMY).global_position.x - 160, 16))


# ─── Hiring decisions ───

func test_ai_trains_engineer_for_damaged_structure_with_surplus() -> void:
	_clear_save_goal()
	_damage_enemy_building(0.5)
	_set_enemy_coin(2000)
	_ai._run_economy()
	assert_true(_queued_ids().has("engineer"),
		"damaged base + surplus coin hires an engineer")


func test_ai_skips_engineer_when_nothing_damaged() -> void:
	_clear_save_goal()
	_set_enemy_coin(2000)
	_ai._run_economy()
	assert_false(_queued_ids().has("engineer"),
		"no damaged structure — no engineer")


func test_ai_skips_engineer_when_coin_is_tight() -> void:
	_clear_save_goal()
	_damage_enemy_building(0.5)
	_set_enemy_coin(200)  # below the 75 cost + ENEMY_ENGINEER_SURPLUS cushion
	_ai._run_economy()
	assert_false(_queued_ids().has("engineer"),
		"a tight wallet never hires support over fighters")


func test_engineer_never_buys_into_a_save_goal() -> void:
	# No lantern standing: the build order is saving for the first lantern.
	_damage_enemy_building(0.5)
	_set_enemy_coin(2000)
	assert_gt(_ai._economy._current_save_goal(2, 1), 0, "sanity: a save goal is active")
	_ai._run_economy()
	assert_false(_queued_ids().has("engineer"),
		"repairs wait for the save goal — the fund must complete")


func test_easy_ai_never_trains_engineers() -> void:
	GameManager.set_difficulty(GameManager.Difficulty.EASY)  # smarts tier 0
	_clear_save_goal()
	_damage_enemy_building(0.5)
	_set_enemy_coin(2000)
	_ai._run_economy()
	assert_false(_queued_ids().has("engineer"),
		"Easy never bothers with repairs")


func test_engineer_cap_blocks_a_second_hire() -> void:
	_clear_save_goal()
	_damage_enemy_building(0.5)
	_spawn_engineer(ENEMY, Vector2(700, 16))  # one already on staff
	_set_enemy_coin(2000)
	_ai._run_economy()
	assert_false(_queued_ids().has("engineer"),
		"Normal keeps a single engineer")


func test_hard_ai_keeps_a_second_engineer_with_many_structures() -> void:
	GameManager.set_difficulty(GameManager.Difficulty.HARD)  # smarts tier 3
	var base_x: float = _building_for(ENEMY).global_position.x
	for i in range(3):
		_spawn_lantern(ENEMY, Vector2(base_x - 160 - i * 48, 16))
	_damage_enemy_building(0.5)
	_spawn_engineer(ENEMY, Vector2(700, 16))  # one already on staff
	_set_enemy_coin(2000)
	_ai._run_economy()
	assert_true(_queued_ids().has("engineer"),
		"Hard fields a second engineer once it has several structures")


# ─── The hired engineer actually repairs (idle auto-seek, AI side) ───

func test_idle_ai_engineer_seeks_damaged_own_building() -> void:
	_damage_enemy_building(0.5)
	var building: Node2D = _building_for(ENEMY)
	var engineer: Node2D = _spawn_engineer(ENEMY, building.global_position + Vector2(-160, 0))
	await wait_seconds(1.0)
	assert_eq(engineer.get("_state"), Unit.State.REPAIR,
		"an idle AI engineer seeks the damaged base on its own")


func test_idle_engineer_never_crosses_midfield_to_repair() -> void:
	# A damaged ENEMY lantern on the PLAYER half: the engineer stays home
	# rather than walking through the enemy army.
	var lantern: Node2D = _spawn_lantern(ENEMY, Vector2(-600, 16))
	lantern.set("_is_built", true)
	lantern.set("hp", int(lantern.get("max_hp") * 0.5))
	lantern.set("_last_damage_time", GameManager.match_time - 10.0)
	var engineer: Node2D = _spawn_engineer(ENEMY, Vector2(700, 16))
	await wait_seconds(1.0)
	assert_eq(engineer.get("_state"), Unit.State.IDLE,
		"structures across midfield are not worth the walk into danger")
