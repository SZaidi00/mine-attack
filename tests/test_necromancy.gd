extends GutTest

# Necromancy (Deep Delve tier-3 capstone): surface swordsman/archer/dragon
# deaths leave raisable corpses for a short window; wizards with the raise
# toggle channel on a corpse to summon an undead copy (half HP/damage,
# population 0, no faction, no kiting) that dies when its raising wizard
# does. The capstone joins crystal_forge/earth_shield as a three-way
# mutually-exclusive Deep Delve choice.

const PLAYER: int = 0
const ENEMY: int = 1

const SWORDSMAN: String = "res://scripts/resources/units/swordsman.tres"
const WIZARD: String = "res://scripts/resources/units/wizard.tres"
const DRAGON: String = "res://scripts/resources/units/dragon.tres"
const CRAWLER: String = "res://scripts/resources/units/crawler.tres"

var _main: Node
var _grid: Node
var _units: Node


func before_all() -> void:
	seed(12345)
	_main = load("res://scenes/main.tscn").instantiate()
	get_tree().root.add_child(_main)
	get_tree().current_scene = _main
	_grid = _main.get_node("World/GridWorld")
	_units = _main.get_node("Units")
	# Random events would interfere with the position/combat assertions.
	WeatherManager.set_weather_events_enabled(false)
	WeatherManager.set_volcano_events_enabled(false)
	_grid.set_dynamic_events_enabled(false)
	await wait_seconds(0.1)


func after_all() -> void:
	_main.free()


func before_each() -> void:
	# Corpses and undead survive a test (the scene persists across tests in
	# this script) — clear them so counts start clean.
	for node in get_tree().get_nodes_in_group("corpses"):
		node.free()
	for node in get_tree().get_nodes_in_group("units"):
		if node.get("data") != null and node.get("data").is_undead:
			node.free()
	EconomyManager.reset()
	ResearchManager.reset()
	GameManager.set_difficulty(GameManager.Difficulty.EASY)
	GameManager.ai_opener = "balanced"
	GameManager.game_active = true


func after_each() -> void:
	# Difficulty survives GameManager.reset() by design — restore the default
	# so downstream test files (e.g. volcano damage scaling) see NORMAL.
	GameManager.set_difficulty(GameManager.Difficulty.NORMAL)


func test_surface_fighter_death_leaves_a_ground_corpse() -> void:
	var s: Node2D = _spawn_unit(SWORDSMAN, PLAYER, Vector2(-400, 16))
	s.kill()
	await wait_seconds(0.2)
	var corpses: Array = get_tree().get_nodes_in_group("corpses")
	assert_eq(corpses.size(), 1, "one corpse on the surface death")
	assert_eq(corpses[0].corpse_category, "ground", "swordsmen are ground corpses")


func test_underground_and_undead_deaths_leave_no_corpse() -> void:
	var crawler: Node2D = _spawn_unit(CRAWLER, PLAYER, Vector2(-400, 300), true)
	crawler.kill()
	await wait_seconds(0.2)
	assert_eq(get_tree().get_nodes_in_group("corpses").size(), 0, "underground deaths leave no corpse")


func test_corpse_expires_after_its_window() -> void:
	var s: Node2D = _spawn_unit(SWORDSMAN, PLAYER, Vector2(-400, 16))
	s.kill()
	await wait_seconds(0.2)
	var corpses: Array = get_tree().get_nodes_in_group("corpses")
	assert_eq(corpses.size(), 1)
	# Shorten the window instead of waiting the full NECRO_CORPSE_DURATION.
	corpses[0].set("_lifetime", 0.5)
	await wait_seconds(1.0)
	assert_eq(get_tree().get_nodes_in_group("corpses").size(), 0, "corpse expired")


func test_wizard_without_research_does_not_raise() -> void:
	var s: Node2D = _spawn_unit(SWORDSMAN, PLAYER, Vector2(-400, 16))
	s.kill()
	var wiz: Node2D = _spawn_unit(WIZARD, PLAYER, Vector2(-430, 16))
	wiz.call("set_raise_mode", "troops")
	await wait_seconds(4.0)
	assert_eq(_undead_count(PLAYER), 0, "no Necromancy research, no raise")
	assert_eq(get_tree().get_nodes_in_group("corpses").size(), 1, "corpse untouched")


func test_raise_toggle_off_does_not_raise() -> void:
	ResearchManager._levels[PLAYER]["necromancy"] = 1
	var s: Node2D = _spawn_unit(SWORDSMAN, PLAYER, Vector2(-400, 16))
	s.kill()
	_spawn_unit(WIZARD, PLAYER, Vector2(-430, 16))  # raise mode defaults to "off"
	await wait_seconds(4.0)
	assert_eq(_undead_count(PLAYER), 0, "toggle off means no raising")


func test_wizard_raises_undead_from_corpse() -> void:
	ResearchManager._levels[PLAYER]["necromancy"] = 1
	var s: Node2D = _spawn_unit(SWORDSMAN, PLAYER, Vector2(-400, 16))
	var base_max_hp: int = s.get("data").max_hp
	var base_damage: float = s.get("data").damage_per_hit
	var pop_before: int = EconomyManager.get_population(PLAYER)
	s.kill()
	var wiz: Node2D = _spawn_unit(WIZARD, PLAYER, Vector2(-430, 16))
	wiz.call("set_raise_mode", "troops")
	await _wait_for_undead(PLAYER, 1)
	var undead: Array = _undead(PLAYER)
	assert_eq(undead.size(), 1, "channel raised an undead")
	var data = undead[0].get("data")
	assert_true(data.is_undead, "the copy is flagged undead")
	assert_eq(data.max_hp, maxi(1, roundi(base_max_hp * Constants.NECRO_UNDEAD_HP_MULT)), "half max HP")
	assert_eq(data.damage_per_hit, base_damage * Constants.NECRO_UNDEAD_DAMAGE_MULT, "half damage")
	assert_eq(data.population, 0, "undead cost no population")
	assert_eq(EconomyManager.get_population(PLAYER), pop_before, "population unchanged by the raise")
	assert_eq(get_tree().get_nodes_in_group("corpses").size(), 0, "corpse consumed")


func test_undead_die_with_their_necromancer() -> void:
	ResearchManager._levels[PLAYER]["necromancy"] = 1
	var s: Node2D = _spawn_unit(SWORDSMAN, PLAYER, Vector2(-400, 16))
	s.kill()
	var wiz: Node2D = _spawn_unit(WIZARD, PLAYER, Vector2(-430, 16))
	wiz.call("set_raise_mode", "troops")
	await _wait_for_undead(PLAYER, 1)
	wiz.kill()
	await wait_seconds(0.5)
	assert_eq(_undead_count(PLAYER), 0, "the binding fails with the necromancer")


func test_ground_cap_is_five_undead() -> void:
	ResearchManager._levels[PLAYER]["necromancy"] = 1
	# Six corpses in a tight cluster around the wizard's post. Extend their
	# windows so the unraised sixth corpse cannot expire before the final
	# assertion (the raising sequence takes longer than NECRO_CORPSE_DURATION).
	for i in range(6):
		var s: Node2D = _spawn_unit(SWORDSMAN, PLAYER, Vector2(-400 + i * 24, 16))
		s.kill()
	for node in get_tree().get_nodes_in_group("corpses"):
		node.set("_lifetime", 120.0)
	var wiz: Node2D = _spawn_unit(WIZARD, PLAYER, Vector2(-400, 16))
	wiz.call("set_raise_mode", "troops")
	# Five channels at 3s each plus walking: poll generously.
	var raised: int = 0
	for i in range(40):
		await wait_seconds(1.0)
		raised = _undead_count(PLAYER)
		if raised >= 5:
			break
	assert_eq(raised, 5, "the per-wizard ground cap is five")
	await wait_seconds(4.0)
	assert_eq(_undead_count(PLAYER), 5, "no sixth raise past the cap")
	assert_eq(get_tree().get_nodes_in_group("corpses").size(), 1, "one corpse left unraised")


func test_dragon_mode_needs_a_dragon_corpse() -> void:
	ResearchManager._levels[PLAYER]["necromancy"] = 1
	var dragon: Node2D = _spawn_unit(DRAGON, PLAYER, Vector2(-400, 16))
	var dragon_hp: int = dragon.get("data").max_hp
	dragon.kill()
	await wait_seconds(0.2)
	# Troops mode ignores dragon corpses.
	var wiz: Node2D = _spawn_unit(WIZARD, PLAYER, Vector2(-430, 16))
	wiz.call("set_raise_mode", "troops")
	await wait_seconds(4.0)
	assert_eq(_undead_count(PLAYER), 0, "troops mode will not raise a dragon")
	# Dragon mode raises it at half HP.
	wiz.call("set_raise_mode", "dragon")
	await _wait_for_undead(PLAYER, 1)
	var undead: Array = _undead(PLAYER)
	assert_eq(undead[0].get("data").unit_name.to_lower(), "dragon", "an undead dragon rises")
	assert_eq(undead[0].get("data").max_hp, maxi(1, roundi(dragon_hp * Constants.NECRO_UNDEAD_HP_MULT)), "half max HP")


func test_dragon_mode_ignores_ground_corpses() -> void:
	ResearchManager._levels[PLAYER]["necromancy"] = 1
	var s: Node2D = _spawn_unit(SWORDSMAN, PLAYER, Vector2(-400, 16))
	s.kill()
	var wiz: Node2D = _spawn_unit(WIZARD, PLAYER, Vector2(-430, 16))
	wiz.call("set_raise_mode", "dragon")
	await wait_seconds(4.0)
	assert_eq(_undead_count(PLAYER), 0, "dragon mode only takes dragon corpses")


func test_necromancy_locks_the_other_deep_delve_capstones() -> void:
	ResearchManager._levels[PLAYER]["ore_sonar"] = 1  # prerequisite
	EconomyManager.add_coin(PLAYER, 5000)
	assert_true(ResearchManager.start_research(PLAYER, "necromancy"))
	ResearchManager._process(ResearchManager.get_active(PLAYER).total + 1.0)
	assert_true(ResearchManager.has_branch(PLAYER, "necromancy"))
	assert_true(ResearchManager.is_locked(PLAYER, "crystal_forge"), "necromancy locks crystal_forge")
	assert_true(ResearchManager.is_locked(PLAYER, "earth_shield"), "necromancy locks earth_shield")


func test_deep_delve_capstones_lock_necromancy() -> void:
	ResearchManager._levels[PLAYER]["ore_sonar"] = 1
	EconomyManager.add_coin(PLAYER, 5000)
	assert_true(ResearchManager.start_research(PLAYER, "crystal_forge"))
	ResearchManager._process(ResearchManager.get_active(PLAYER).total + 1.0)
	assert_true(ResearchManager.is_locked(PLAYER, "necromancy"), "crystal_forge locks necromancy")
	assert_false(ResearchManager.start_research(PLAYER, "necromancy"), "a locked capstone cannot be started")


# ─── Helpers ───

func _spawn_unit(tres_path: String, team: int, pos: Vector2, underground: bool = false) -> Node2D:
	var unit: Node2D = load("res://scenes/unit.tscn").instantiate()
	unit.set("data", load(tres_path).duplicate(true))
	unit.set("team", team)
	unit.position = pos
	_units.add_child(unit)
	if underground:
		unit.set("is_underground", true)
	autofree(unit)
	return unit


func _undead(team: int) -> Array:
	var result: Array = []
	for node in get_tree().get_nodes_in_group("units"):
		if node.get("data") != null and node.get("data").is_undead and node.team == team \
				and node.get("_state") != Unit.State.DEAD:
			result.append(node)
	return result


func _undead_count(team: int) -> int:
	return _undead(team).size()


func _wait_for_undead(team: int, n: int) -> void:
	for i in range(20):
		await wait_seconds(0.5)
		if _undead_count(team) >= n:
			return
