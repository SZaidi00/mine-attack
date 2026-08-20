extends GutTest

# Revamp Phase 6 branch-specific behaviors that live outside ResearchManager:
# Deep Delve / Surface War miner-level gates and speed multipliers, Reinforced
# Pack cave-in push immunity, Longbow blind fire into fog, Rapid Fire cooldown
# + swordsman speed, Siege Master building damage + tower discount, Guerrilla
# lone-unit speed flag + traps, Crystal Forge burning ground, and Earth Shield
# building HP + respec revert. Branch state is forced by writing
# ResearchManager._levels directly and calling the apply functions by hand.

const PLAYER: int = 0
const ENEMY: int = 1

var _main: Node
var _units: Node
var _grid: Node
var _pc: Node


func before_all() -> void:
	seed(12345)
	_main = load("res://scenes/main.tscn").instantiate()
	get_tree().root.add_child(_main)
	get_tree().current_scene = _main
	_units = _main.get_node("Units")
	_grid = _main.get_node("World/GridWorld")
	_pc = _main.get_node("PlayerController")
	# No random events mid-test: the cave-in below is forced explicitly.
	_grid.set_dynamic_events_enabled(false)
	# Warm-up: the first test after boot gets ~0.4s of node _process starvation
	# in the headless harness, so let the scene settle first.
	await wait_seconds(0.6)


func after_all() -> void:
	# Free immediately, not queue_free(): a queued free could still be pending
	# when the next test script instantiates its own main.tscn and every
	# hard-coded /root/Main lookup would break.
	_main.free()


func before_each() -> void:
	EconomyManager.reset()
	ResearchManager.reset()
	GameManager.reset()
	GameManager.game_active = true
	# Structures placed by a test must not leak into the next.
	for tower in get_tree().get_nodes_in_group("towers"):
		tower.free()
	for wall in get_tree().get_nodes_in_group("walls"):
		wall.free()
	for trap in get_tree().get_nodes_in_group("traps"):
		trap.free()
	for lantern in get_tree().get_nodes_in_group("lanterns"):
		lantern.free()
	# Settle any forced cave-in so later tests see clean terrain.
	if _grid._events._cavein_restore_left > 0.0:
		_grid._events._cavein_restore_left = 0.0
		_grid._events._restore_cave_in()


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


# ─── Deep Delve / Surface War: miner-level gates ───

func test_effective_miner_level_passthrough_without_branch() -> void:
	var miner: Node2D = _spawn_unit("res://scripts/resources/units/miner.tres", PLAYER, Vector2(400, 16))
	assert_eq(miner.get_effective_miner_level(), 1, "default miner level passes through")
	miner.get("data").miner_level = 3
	assert_eq(miner.get_effective_miner_level(), 3, "upgraded level passes through")


func test_deep_delve_grants_effective_miner_level_3() -> void:
	var miner: Node2D = _spawn_unit("res://scripts/resources/units/miner.tres", PLAYER, Vector2(400, 16))
	ResearchManager._levels[PLAYER]["deep_delve"] = 1
	assert_eq(miner.get_effective_miner_level(), 3, "deep_delve unlocks layers 5-7 immediately")


func test_surface_war_caps_effective_miner_level_at_2() -> void:
	var miner: Node2D = _spawn_unit("res://scripts/resources/units/miner.tres", PLAYER, Vector2(400, 16))
	ResearchManager._levels[PLAYER]["surface_war"] = 1
	miner.get("data").miner_level = 3
	assert_eq(miner.get_effective_miner_level(), 2, "surface_war caps miners at layer 4")
	miner.get("data").miner_level = 1
	assert_eq(miner.get_effective_miner_level(), 1, "levels below the cap are untouched")


func test_deep_delve_speeds_up_underground_miners() -> void:
	var miner: Node2D = _spawn_unit("res://scripts/resources/units/miner.tres", PLAYER, Vector2(400, 16))
	miner.is_underground = true
	assert_eq(miner._navigation._research_speed_mult(), 1.0)
	ResearchManager._levels[PLAYER]["deep_delve"] = 1
	assert_almost_eq(miner._navigation._research_speed_mult(), Constants.DEEP_DELVE_UG_SPEED_MULT, 0.001)
	miner.is_underground = false
	assert_eq(miner._navigation._research_speed_mult(), 1.0, "the bonus is underground-only")


func test_surface_war_speeds_up_surface_fighters() -> void:
	var swordsman: Node2D = _spawn_unit("res://scripts/resources/units/swordsman.tres", PLAYER, Vector2(400, 16))
	ResearchManager._levels[PLAYER]["surface_war"] = 1
	assert_almost_eq(swordsman._navigation._research_speed_mult(), Constants.SURFACE_WAR_SPEED_MULT, 0.001)
	swordsman.is_underground = true
	assert_eq(swordsman._navigation._research_speed_mult(), 1.0, "the bonus is surface-only")


# ─── Reinforced Pack: cave-in push immunity ───

func test_reinforced_pack_miner_braces_against_cave_in_push() -> void:
	var center: Vector2i = Vector2i(-20, 10)
	var packed: Node2D = _spawn_unit("res://scripts/resources/units/miner.tres", PLAYER, _grid.grid_to_world(center))
	packed.is_underground = true
	packed.set("hp", 500)  # survive the collapse damage for the assertion
	var plain: Node2D = _spawn_unit("res://scripts/resources/units/miner.tres", ENEMY, _grid.grid_to_world(center))
	plain.is_underground = true
	plain.set("hp", 500)
	ResearchManager._levels[PLAYER]["reinforced_pack"] = 1
	_grid.force_cave_in(center)
	assert_eq(packed.get("hp"), 500 - Constants.CAVEIN_DAMAGE, "packed miners still take the damage")
	assert_eq(_grid.world_to_grid(packed.global_position), center, "packed miners are NOT pushed")
	assert_eq(plain.get("hp"), 500 - Constants.CAVEIN_DAMAGE)
	assert_ne(_grid.world_to_grid(plain.global_position), center, "miners without the branch are shoved to safety")
	# Let the rock restore so later tests see clean terrain.
	_grid._events._cavein_restore_left = 0.0
	_grid._events._restore_cave_in()


# ─── Longbow: blind fire ───

func test_longbow_archer_acquires_target_in_fog() -> void:
	# Wipe the vision maps so the enemy stands in full fog; no frames pass
	# inside this test, so the maps stay wiped until the assertions are done.
	_grid._init_vision_maps()
	var archer: Node2D = _spawn_unit("res://scripts/resources/units/archer.tres", PLAYER, Vector2(0, 16))
	var enemy: Node2D = _spawn_unit("res://scripts/resources/units/swordsman.tres", ENEMY, Vector2(120, 16))
	assert_false(_grid.is_visible_to(PLAYER, enemy.global_position), "precondition: the enemy is in fog")
	assert_null(archer.call("_find_auto_attack_target"), "normal archers cannot target what they cannot see")
	ResearchManager._levels[PLAYER]["longbow"] = 1
	assert_eq(archer.call("_find_auto_attack_target"), enemy, "longbow archers blind-fire into fog")


func test_longbow_keeps_attack_lock_when_target_enters_fog() -> void:
	var archer: Node2D = _spawn_unit("res://scripts/resources/units/archer.tres", PLAYER, Vector2(0, 16))
	var enemy: Node2D = _spawn_unit("res://scripts/resources/units/swordsman.tres", ENEMY, Vector2(100, 16))
	archer.attack_unit(enemy)
	enemy.position = Vector2(1200, 16)  # deep in the enemy backfield fog
	assert_false(_grid.is_visible_to(PLAYER, enemy.global_position), "precondition: the target slipped into fog")
	archer.call("_process_attack", 0.016)
	assert_null(archer.get("_target_unit"), "baseline: fog breaks the lock without the branch")
	archer.attack_unit(enemy)  # explicit orders are allowed regardless of fog
	ResearchManager._levels[PLAYER]["longbow"] = 1
	archer.call("_process_attack", 0.016)
	assert_not_null(archer.get("_target_unit"), "longbow archers keep the lock and blind-fire")


# ─── Rapid Fire: cooldown + swordsman speed ───

func test_rapid_fire_lowers_all_fighter_cooldowns() -> void:
	var swordsman: Node2D = _spawn_unit("res://scripts/resources/units/swordsman.tres", PLAYER, Vector2(400, 16))
	var archer: Node2D = _spawn_unit("res://scripts/resources/units/archer.tres", PLAYER, Vector2(400, 16))
	var sw_cd: float = swordsman.get("data").attack_cooldown
	var ar_cd: float = archer.get("data").attack_cooldown
	ResearchManager._levels[PLAYER]["rapid_fire"] = 1
	swordsman.call("_apply_research_bonuses")
	archer.call("_apply_research_bonuses")
	assert_almost_eq(swordsman.get("data").attack_cooldown, sw_cd * 0.8, 0.001)
	assert_almost_eq(archer.get("data").attack_cooldown, ar_cd * 0.8, 0.001, "fighter_cdr applies to every fighter")


func test_rapid_fire_raises_swordsman_speed() -> void:
	var swordsman: Node2D = _spawn_unit("res://scripts/resources/units/swordsman.tres", PLAYER, Vector2(400, 16))
	var base_speed: float = swordsman.get("data").speed
	ResearchManager._levels[PLAYER]["rapid_fire"] = 1
	swordsman.call("_apply_research_bonuses")
	assert_almost_eq(swordsman.get("data").speed, base_speed * 1.1, 0.001)


# ─── Siege Master: building damage + tower discount ───

func test_siege_master_swordsman_bonus_damage_vs_building() -> void:
	var building: Node2D = _building_for(ENEMY)
	var rect: Rect2 = building.call("get_bounds_rect")
	# Stand one cell left of the footprint, on the surface row.
	var stand: Vector2 = _grid.grid_to_world(_grid.world_to_grid(Vector2(rect.position.x - 1.0, 0.0)))
	var swordsman: Node2D = _spawn_unit("res://scripts/resources/units/swordsman.tres", PLAYER, stand)
	swordsman.attack_building(building)
	swordsman.set("_attack_timer", 0.0)
	var hp_before: int = building.get("_hp")
	swordsman.call("_process_attack", 0.016)
	assert_eq(hp_before - building.get("_hp"), 8, "baseline hit: roundi(7.5)")
	ResearchManager._levels[PLAYER]["siege_master"] = 1
	swordsman.set("_attack_timer", 0.0)
	hp_before = building.get("_hp")
	swordsman.call("_process_attack", 0.016)
	assert_eq(hp_before - building.get("_hp"), 10, "siege_master hit: roundi(8 * 1.3)")


func test_siege_master_halves_tower_cost() -> void:
	EconomyManager.add_coin(PLAYER, 1000)
	ResearchManager._levels[PLAYER]["siege_master"] = 1
	var before: int = EconomyManager.get_coin(PLAYER)
	assert_true(_pc.try_place_structure("tower", _grid.grid_to_world(Vector2i(-12, 0))))
	assert_eq(before - EconomyManager.get_coin(PLAYER), roundi(300 * Constants.SIEGE_MASTER_TOWER_COST_MULT), "towers cost half with siege_master")
	var tower: Node2D = get_tree().get_nodes_in_group("towers")[0]
	assert_eq(tower.total_cost, roundi(300 * Constants.SIEGE_MASTER_TOWER_COST_MULT))


# ─── Guerrilla: lone-unit speed flag + traps ───

func test_guerrilla_flag_on_for_lone_unit() -> void:
	ResearchManager._levels[PLAYER]["guerrilla"] = 1
	var lone: Node2D = _spawn_unit("res://scripts/resources/units/swordsman.tres", PLAYER, Vector2(0, 16))
	lone.call("_update_guerrilla")
	assert_true(lone.get("_guerrilla_active"), "no ally within 6 cells → guerrilla speed")


func test_guerrilla_flag_off_when_ally_near_and_without_branch() -> void:
	ResearchManager._levels[PLAYER]["guerrilla"] = 1
	var a: Node2D = _spawn_unit("res://scripts/resources/units/swordsman.tres", PLAYER, Vector2(0, 16))
	var b: Node2D = _spawn_unit("res://scripts/resources/units/swordsman.tres", PLAYER, Vector2(64, 16))
	a.call("_update_guerrilla")
	b.call("_update_guerrilla")
	assert_false(a.get("_guerrilla_active"), "an ally within 6 cells breaks the bonus")
	assert_false(b.get("_guerrilla_active"))
	ResearchManager._levels[PLAYER]["guerrilla"] = 0
	var far: Node2D = _spawn_unit("res://scripts/resources/units/swordsman.tres", PLAYER, Vector2(-400, 16))
	# a/b stand 400px away, so `far` would be lone — but the branch is gone.
	a.free()
	b.free()
	far.call("_update_guerrilla")
	assert_false(far.get("_guerrilla_active"), "no bonus without the branch research")


func test_guerrilla_trap_placement_rules_and_cost() -> void:
	assert_false(_pc.try_place_structure("trap", _grid.grid_to_world(Vector2i(-20, 0))), "traps require the guerrilla branch")
	ResearchManager._levels[PLAYER]["guerrilla"] = 1
	EconomyManager.add_coin(PLAYER, 1000)
	var before: int = EconomyManager.get_coin(PLAYER)
	assert_true(_pc.try_place_structure("trap", _grid.grid_to_world(Vector2i(-20, 0))))
	assert_eq(before - EconomyManager.get_coin(PLAYER), Constants.TRAP_COST)
	assert_eq(get_tree().get_nodes_in_group("traps").size(), 1)
	assert_false(_pc.try_place_structure("trap", _grid.grid_to_world(Vector2i(-20, 0))), "cell is occupied")
	for x in [-22, -24, -26, -28]:
		assert_true(_pc.try_place_structure("trap", _grid.grid_to_world(Vector2i(x, 0))), "trap %d places" % x)
	assert_false(_pc.try_place_structure("trap", _grid.grid_to_world(Vector2i(-30, 0))), "6th trap exceeds TRAP_MAX_COUNT")


func test_trap_triggers_on_enemy_and_is_consumed() -> void:
	ResearchManager._levels[PLAYER]["guerrilla"] = 1
	EconomyManager.add_coin(PLAYER, 1000)
	assert_true(_pc.try_place_structure("trap", _grid.grid_to_world(Vector2i(-20, 0))))
	var trap: Node2D = get_tree().get_nodes_in_group("traps")[0]
	var enemy: Node2D = _spawn_unit("res://scripts/resources/units/swordsman.tres", ENEMY, trap.global_position)
	var hp_before: int = enemy.get("hp")
	trap._process(0.016)
	assert_eq(enemy.get("hp"), hp_before - roundi(Constants.TRAP_DAMAGE), "trap deals its damage")
	assert_true(trap.is_queued_for_deletion(), "the trap is consumed by the trigger")


# ─── Crystal Forge: burning ground ───

func test_burning_ground_ticks_enemies_and_frees_itself() -> void:
	var enemy: Node2D = _spawn_unit("res://scripts/resources/units/swordsman.tres", ENEMY, Vector2(0, 16))
	var ally: Node2D = _spawn_unit("res://scripts/resources/units/swordsman.tres", PLAYER, Vector2(0, 16))
	var bg: Node2D = load("res://scenes/effects/burning_ground.tscn").instantiate()
	bg.set("team", PLAYER)
	_main.add_child(bg)
	autofree(bg)
	bg.global_position = Vector2(0, 16)
	var enemy_hp: int = enemy.get("hp")
	var ally_hp: int = ally.get("hp")
	bg._process(0.5)  # one tick
	assert_lt(enemy.get("hp"), enemy_hp, "burning ground ticks damage onto enemies")
	assert_eq(ally.get("hp"), ally_hp, "friendly units are unaffected")
	for i in range(8):
		if not is_instance_valid(bg) or bg.is_queued_for_deletion():
			break
		bg._process(0.5)
	assert_true(bg.is_queued_for_deletion(), "the patch frees itself after its duration")


func test_burn_lingers_after_leaving_the_fire() -> void:
	# Ignite: a unit that takes a fire tick keeps burning at reduced dps for
	# BURN_LINGER_DURATION after it walks out of the patch.
	var enemy: Node2D = _spawn_unit("res://scripts/resources/units/swordsman.tres", ENEMY, Vector2(0, 16))
	var bg: Node2D = load("res://scenes/effects/burning_ground.tscn").instantiate()
	bg.set("team", PLAYER)
	_main.add_child(bg)
	bg.global_position = Vector2(0, 16)
	bg._process(0.5)  # one in-fire tick: damages and ignites
	assert_true(enemy.is_burning(), "a fire tick ignites the unit")
	bg.free()  # the unit walks out of the fire
	var hp_after_ignite: int = enemy.get("hp")
	enemy._combat._process_burn(0.5)  # first lingering tick
	assert_lt(enemy.get("hp"), hp_after_ignite, "the burn keeps ticking after leaving the fire")
	# Burn out the remaining linger duration (3.0s at 0.5s ticks).
	for i in range(8):
		enemy._combat._process_burn(0.5)
	assert_false(enemy.is_burning(), "the burn expires after the linger duration")
	var hp_settled: int = enemy.get("hp")
	enemy._combat._process_burn(0.5)
	assert_eq(enemy.get("hp"), hp_settled, "no further ticks once the burn is out")


# ─── Earth Shield: building HP + respec revert ───

func test_earth_shield_building_hp_reverts_on_respec() -> void:
	var building: Node2D = _building_for(PLAYER)
	var base_max: int = building.get("max_hp")
	ResearchManager._levels[PLAYER]["earth_shield"] = 1
	ResearchManager.research_changed.emit(PLAYER)
	assert_eq(building.get("max_hp"), base_max + 1000)
	assert_eq(building.get("_hp"), base_max + 1000, "the gain heals the delta")
	EconomyManager.add_coin(PLAYER, Constants.BRANCH_RESPEC_COST)
	assert_true(ResearchManager.respec(PLAYER))
	assert_eq(building.get("max_hp"), base_max, "respec reverts the building bonus")
	assert_eq(building.get("_hp"), base_max, "current HP clamps to the reverted max")


# ─── Surface War: tower range ───

func test_surface_war_extends_tower_range() -> void:
	var tower: Node2D = load("res://scenes/tower.tscn").instantiate()
	tower.team = PLAYER
	_main.get_node("Structures").add_child(tower)
	autofree(tower)
	var base: float = Constants.TOWER_RANGE_CELLS * GridWorld.CELL_SIZE
	assert_almost_eq(tower.attack_range, base, 0.001, "no branch: base range")
	ResearchManager._levels[PLAYER]["surface_war"] = 1
	ResearchManager.research_changed.emit(PLAYER)
	assert_almost_eq(tower.attack_range, base * Constants.SURFACE_WAR_TOWER_RANGE_MULT, 0.001, "surface_war widens tower range")
	ResearchManager._levels[PLAYER]["surface_war"] = 0
	ResearchManager.research_changed.emit(PLAYER)
	assert_almost_eq(tower.attack_range, base, 0.001, "losing the branch reverts the range")


# ─── Fortification discipline ───

func test_fortification_raises_building_hp() -> void:
	var building: Node2D = _building_for(PLAYER)
	var base_max: int = building.get("max_hp")
	ResearchManager._levels[PLAYER]["fortification"] = 1
	ResearchManager.research_changed.emit(PLAYER)
	assert_eq(building.get("max_hp"), roundi(base_max * 1.1), "fortification adds +10% building HP")
	assert_eq(building.get("_hp"), building.get("max_hp"), "the HP delta heals")


func test_fortification_buffs_tower_hp_and_build_speed() -> void:
	var tower: Node2D = load("res://scenes/tower.tscn").instantiate()
	tower.team = PLAYER
	_main.get_node("Structures").add_child(tower)
	autofree(tower)
	var base_hp: int = tower.max_hp
	var base_build: float = tower.build_time
	ResearchManager._levels[PLAYER]["fortification"] = 1
	ResearchManager.research_changed.emit(PLAYER)
	assert_eq(tower.max_hp, roundi(base_hp * 1.15), "fortification adds +15% tower HP")
	assert_almost_eq(tower.build_time, base_build * 0.8, 0.001, "fortification builds 20% faster")


func test_stone_masonry_buffs_walls() -> void:
	EconomyManager.add_coin(PLAYER, 1000)
	assert_true(_pc.try_place_structure("wall", _grid.grid_to_world(Vector2i(-20, 0))), "baseline wall places")
	var wall: Node2D = get_tree().get_nodes_in_group("walls")[0]
	var base_hp: int = wall.max_hp
	ResearchManager._levels[PLAYER]["stone_masonry"] = 1
	ResearchManager.research_changed.emit(PLAYER)
	assert_eq(wall.max_hp, roundi(base_hp * (1.0 + Constants.STONE_MASONRY_WALL_HP_MULT)), "stone_masonry adds +30% wall HP on top of fortification")
	EconomyManager.add_coin(PLAYER, 1000)
	assert_true(_pc.try_place_structure("wall", _grid.grid_to_world(Vector2i(-22, 0))), "second wall places")
	var wall2: Node2D = get_tree().get_nodes_in_group("walls")[1]
	var expected_cost: int = roundi(Constants.PLACED_WALL_COST * (1.0 - Constants.STONE_MASONRY_WALL_COST_MULT))
	assert_eq(wall2.total_cost, expected_cost, "stone_masonry discounts wall cost")


func test_sentry_network_extends_tower_range_and_max_count() -> void:
	EconomyManager.add_coin(PLAYER, 3000)
	assert_true(_pc.try_place_structure("tower", _grid.grid_to_world(Vector2i(-12, 0))), "tower 1 places")
	var tower: Node2D = get_tree().get_nodes_in_group("towers")[0]
	var base_range: float = tower.attack_range
	ResearchManager._levels[PLAYER]["sentry_network"] = 1
	ResearchManager.research_changed.emit(PLAYER)
	assert_almost_eq(tower.attack_range, base_range * (1.0 + Constants.SENTRY_NETWORK_TOWER_RANGE_MULT), 0.001, "sentry_network extends tower range")
	assert_true(_pc.try_place_structure("tower", _grid.grid_to_world(Vector2i(-22, 0))), "tower 2 places")
	assert_true(_pc.try_place_structure("tower", _grid.grid_to_world(Vector2i(-38, 0))), "tower 3 places with +1 max count")


# ─── Dragon Mastery discipline ───

func test_dragon_mastery_buffs_dragon_stats() -> void:
	var dragon: Node2D = _spawn_unit("res://scripts/resources/units/dragon.tres", PLAYER, Vector2(0, 16))
	var base_hp: int = dragon.get("data").max_hp
	var base_dmg: float = dragon.get("data").damage_per_hit
	ResearchManager._levels[PLAYER]["dragon_mastery"] = 1
	dragon.call("_apply_research_bonuses")
	assert_eq(dragon.get("data").max_hp, roundi(base_hp * (1.0 + Constants.DRAGON_MASTERY_HP_MULT)))
	assert_almost_eq(dragon.get("data").damage_per_hit, base_dmg * (1.0 + Constants.DRAGON_MASTERY_DMG_MULT), 0.001)


func test_broodmother_discounts_dragon_cost_and_train_time() -> void:
	ResearchManager._levels[PLAYER]["dragon_mastery"] = 1
	ResearchManager._levels[PLAYER]["broodmother"] = 1
	EconomyManager.add_coin(PLAYER, 10000)
	var building: Node2D = _building_for(PLAYER)
	building.call("queue_unit", "dragon")
	var entry: Dictionary = building.call("get_queue")[0]
	var expected_cost: int = roundi(Constants.COSTS["dragon"] * (1.0 - Constants.BROODMOTHER_COST_MULT))
	var expected_time: float = Constants.TRAIN_TIMES["dragon"] * (1.0 - Constants.DRAGON_MASTERY_TRAIN_TIME_MULT - Constants.BROODMOTHER_TRAIN_TIME_MULT)
	assert_eq(entry.cost, expected_cost)
	assert_almost_eq(entry.train_time, expected_time, 0.001)


# ─── Weather discipline ───

func test_weather_alert_extends_snowstorm_warning() -> void:
	ResearchManager._levels[PLAYER]["weather_alert"] = 1
	WeatherManager.force_snowstorm_warning()
	assert_almost_eq(WeatherManager.get_snowstorm_warning_remaining(), Constants.SNOWSTORM_WARNING_TIME + Constants.WEATHER_ALERT_WARNING_BONUS, 0.1)


func test_storm_scout_improves_unit_vision_in_storm() -> void:
	var swordsman: Node2D = _spawn_unit("res://scripts/resources/units/swordsman.tres", PLAYER, Vector2(0, 16))
	WeatherManager.force_snowstorm_start()
	assert_almost_eq(WeatherManager.get_unit_vision_multiplier(swordsman), Constants.SNOWSTORM_VISION_MULT, 0.001)
	ResearchManager._levels[PLAYER]["storm_scout"] = 1
	assert_almost_eq(WeatherManager.get_unit_vision_multiplier(swordsman), Constants.SNOWSTORM_VISION_MULT + Constants.STORM_SCOUT_VISION_MULT, 0.001)
	WeatherManager.force_snowstorm_end()


func test_pathfinder_improves_lantern_vision_in_storm() -> void:
	ResearchManager._levels[PLAYER]["pathfinder"] = 1
	WeatherManager.force_snowstorm_start()
	assert_almost_eq(WeatherManager.get_lantern_vision_multiplier(PLAYER), Constants.SNOWSTORM_VISION_MULT + Constants.PATHFINDER_VISION_MULT, 0.001)
	WeatherManager.force_snowstorm_end()


# ─── Cross-path capstones ───

func test_total_war_raises_fighter_damage_and_structure_counts() -> void:
	var swordsman: Node2D = _spawn_unit("res://scripts/resources/units/swordsman.tres", PLAYER, Vector2(0, 16))
	var base_dmg: float = swordsman.get("data").damage_per_hit
	ResearchManager._levels[PLAYER]["total_war"] = 1
	swordsman.call("_apply_research_bonuses")
	assert_almost_eq(swordsman.get("data").damage_per_hit, base_dmg * (1.0 + Constants.TOTAL_WAR_FIGHTER_DMG_MULT), 0.001)
	EconomyManager.add_coin(PLAYER, 3000)
	# Default max is 2; Total War grants +1 tower and +1 wall.
	assert_true(_pc.try_place_structure("tower", _grid.grid_to_world(Vector2i(-12, 0))), "tower 1")
	assert_true(_pc.try_place_structure("tower", _grid.grid_to_world(Vector2i(-22, 0))), "tower 2")
	assert_true(_pc.try_place_structure("tower", _grid.grid_to_world(Vector2i(-38, 0))), "tower 3 with total_war bonus")
	EconomyManager.add_coin(PLAYER, 1000)
	assert_true(_pc.try_place_structure("wall", _grid.grid_to_world(Vector2i(-24, 0))), "wall 1")
	assert_true(_pc.try_place_structure("wall", _grid.grid_to_world(Vector2i(-26, 0))), "wall 2")
	assert_true(_pc.try_place_structure("wall", _grid.grid_to_world(Vector2i(-28, 0))), "wall 3 with total_war bonus")


func test_deep_fortress_extends_underground_lantern_vision() -> void:
	EconomyManager.add_coin(PLAYER, 1000)
	assert_true(_pc.try_place_lantern("underground_lantern", _grid.grid_to_world(Vector2i(-15, 3))), "underground lantern places")
	var lantern: Node2D = get_tree().get_nodes_in_group("lanterns")[0]
	lantern._build_progress = 999.0
	lantern._process(0.1)
	ResearchManager._levels[PLAYER]["deep_fortress"] = 1
	var found: bool = false
	for source in _grid._get_vision_sources(PLAYER):
		if source[0] == Vector2i(-15, 3):
			found = true
			assert_eq(source[1], Constants.UNDERGROUND_LANTERN_VISION + Constants.DEEP_FORTRESS_LANTERN_VISION_BONUS)
	assert_true(found, "underground lantern is a vision source")


func test_storm_dragon_makes_dragons_weather_immune() -> void:
	var dragon: Node2D = _spawn_unit("res://scripts/resources/units/dragon.tres", PLAYER, Vector2(0, 16))
	WeatherManager.force_snowstorm_start()
	assert_lt(WeatherManager.get_speed_multiplier(dragon), 1.0, "normal dragon is slowed by the storm")
	assert_almost_eq(WeatherManager.get_unit_vision_multiplier(dragon), Constants.SNOWSTORM_VISION_MULT, 0.001)
	ResearchManager._levels[PLAYER]["storm_dragon"] = 1
	assert_eq(WeatherManager.get_speed_multiplier(dragon), 1.0, "storm dragon ignores storm speed penalty")
	assert_eq(WeatherManager.get_unit_vision_multiplier(dragon), 1.0, "storm dragon ignores storm vision penalty")
	WeatherManager.force_snowstorm_end()
