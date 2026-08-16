extends GutTest

# Revamp Phase 2: faction system — cost/economy modifiers, stat multipliers,
# the simple ability set, and hidden-faction scouting. Boots the real
# main.tscn with an Industrial/Industrial match (covers the starting bonuses);
# individual tests switch factions and spawn fresh units (faction is read at
# spawn). after_all restores the neutral default so later suites see base
# costs and 500 starting coin.

const PLAYER: int = 0
const ENEMY: int = 1

var _main: Node
var _units: Node
var _grid: Node


func before_all() -> void:
	seed(12345)
	FactionManager.set_player_faction("industrial")
	FactionManager.enemy_faction_id = "industrial"
	_main = load("res://scenes/main.tscn").instantiate()
	get_tree().root.add_child(_main)
	get_tree().current_scene = _main
	_units = _main.get_node("Units")
	_grid = _main.get_node("World/GridWorld")
	# Vision must not drive outcomes here (same approach as the other
	# fog-agnostic suites).
	_grid.set_reveal_all(PLAYER, true)
	_grid.set_reveal_all(ENEMY, true)
	# Let the deferred starting-miner spawns land.
	await wait_seconds(0.1)


func after_all() -> void:
	FactionManager.set_player_faction("")
	FactionManager.enemy_faction_id = ""
	FactionManager.reset()
	EconomyManager.reset()
	_main.free()


func _spawn_unit(tres_path: String, team: int, pos: Vector2) -> Node2D:
	var unit: Node2D = load("res://scenes/unit.tscn").instantiate()
	unit.set("data", load(tres_path).duplicate(true))
	unit.set("team", team)
	unit.position = pos
	_units.add_child(unit)
	autofree(unit)
	return unit


func _count_miners(team: int) -> int:
	var group: String = "player" if team == PLAYER else "enemy"
	var count: int = 0
	for unit in get_tree().get_nodes_in_group(group):
		if unit.data.is_miner:
			count += 1
	return count


func test_industrial_starting_coin() -> void:
	EconomyManager.reset()
	assert_eq(EconomyManager.get_coin(PLAYER), 700, "industrial starts with 500 + 200 bonus")
	assert_eq(EconomyManager.get_coin(ENEMY), 700, "enemy industrial also gets the bonus")


func test_industrial_starting_miners() -> void:
	assert_eq(_count_miners(PLAYER), 3, "industrial starts with 2 + 1 bonus miners")
	assert_eq(_count_miners(ENEMY), 3, "enemy industrial also gets the bonus miner")


func test_industrial_cost_overrides() -> void:
	assert_eq(FactionManager.get_unit_cost(PLAYER, "swordsman"), 75)
	assert_eq(FactionManager.get_unit_cost(PLAYER, "archer"), 120)
	assert_eq(FactionManager.get_unit_cost(PLAYER, "wizard"), 200)
	assert_eq(FactionManager.get_unit_cost(PLAYER, "miner"), 50, "miner has no override")
	assert_eq(FactionManager.get_unit_cost(PLAYER, "dragon"), 400, "dragon has no override")


func test_arcane_cost_multiplier() -> void:
	FactionManager.set_player_faction("arcane")
	assert_eq(FactionManager.get_unit_cost(PLAYER, "swordsman"), 110, "arcane units cost +10%")
	assert_eq(FactionManager.get_unit_cost(PLAYER, "miner"), 55)
	FactionManager.set_player_faction("industrial")


func test_neutral_faction_keeps_base_costs() -> void:
	var saved: String = FactionManager.enemy_faction_id
	FactionManager.enemy_faction_id = ""
	assert_eq(FactionManager.get_unit_cost(ENEMY, "swordsman"), 100, "no faction = base cost")
	assert_eq(FactionManager.get_starting_coin(ENEMY), 500, "no faction = base starting coin")
	FactionManager.enemy_faction_id = saved


func test_brute_swordsman_stats() -> void:
	FactionManager.set_player_faction("brute")
	var sw: Node2D = _spawn_unit("res://scripts/resources/units/swordsman.tres", PLAYER, Vector2(-600, 16))
	assert_eq(sw.data.max_hp, 195, "brute swordsman +30% HP")
	assert_almost_eq(sw.data.damage_per_hit, 8.25, 0.01, "brute swordsman +10% damage")
	FactionManager.set_player_faction("industrial")


func test_arcane_wizard_damage() -> void:
	FactionManager.set_player_faction("arcane")
	var wiz: Node2D = _spawn_unit("res://scripts/resources/units/wizard.tres", PLAYER, Vector2(-600, 16))
	assert_almost_eq(wiz.data.damage_per_hit, 46.875, 0.01, "arcane wizard +25% damage")
	assert_eq(wiz.data.max_hp, 54, "arcane wizard -10% HP")
	FactionManager.set_player_faction("industrial")


func test_brute_miner_stats() -> void:
	FactionManager.set_player_faction("brute")
	var miner: Node2D = _spawn_unit("res://scripts/resources/units/miner.tres", PLAYER, Vector2(-600, 16))
	assert_eq(miner.data.max_hp, 65, "brute miner +15 HP")
	assert_eq(miner.data.carry_capacity, 15, "brute miner -5 carry")
	assert_almost_eq(miner.data.mining_swings_per_sec, 1.6, 0.01, "brute miner -20% mining speed")
	FactionManager.set_player_faction("industrial")


func test_industrial_miner_stats() -> void:
	var miner: Node2D = _spawn_unit("res://scripts/resources/units/miner.tres", PLAYER, Vector2(-600, 16))
	assert_eq(miner.data.carry_capacity, 30, "industrial miner +10 carry")
	assert_almost_eq(miner.data.mining_swings_per_sec, 2.5, 0.01, "industrial miner +25% mining speed")


func test_neutral_faction_keeps_base_stats() -> void:
	FactionManager.set_player_faction("")
	var sw: Node2D = _spawn_unit("res://scripts/resources/units/swordsman.tres", PLAYER, Vector2(-600, 16))
	assert_eq(sw.data.max_hp, 150, "factionless swordsman keeps .tres HP")
	assert_almost_eq(sw.data.damage_per_hit, 7.5, 0.01, "factionless swordsman keeps .tres damage")
	FactionManager.set_player_faction("industrial")


func test_rune_blade_first_hit_bonus() -> void:
	FactionManager.set_player_faction("arcane")
	var sw: Node2D = _spawn_unit("res://scripts/resources/units/swordsman.tres", PLAYER, Vector2(-600, 16))
	var target: Node2D = _spawn_unit("res://scripts/resources/units/swordsman.tres", ENEMY, Vector2(-584, 16))
	sw.call("attack_unit", target)
	sw.set("_attack_timer", 0.0)
	sw.call("_process_attack", 0.016)
	var hp_after_first: int = target.get("hp")
	var first_hit: int = target.data.max_hp - hp_after_first
	sw.set("_attack_timer", 0.0)
	sw.call("_process_attack", 0.016)
	var second_hit: int = hp_after_first - target.get("hp")
	assert_eq(first_hit, 14, "rune blade: roundi(roundi(7.5*1.15) * 1.5)")
	assert_eq(second_hit, 9, "subsequent hits are normal: roundi(7.5*1.15)")
	FactionManager.set_player_faction("industrial")


func test_berserk_attack_speed() -> void:
	FactionManager.set_player_faction("brute")
	var sw: Node2D = _spawn_unit("res://scripts/resources/units/swordsman.tres", PLAYER, Vector2(-600, 16))
	var target: Node2D = _spawn_unit("res://scripts/resources/units/swordsman.tres", ENEMY, Vector2(-584, 16))
	sw.call("attack_unit", target)
	sw.set("hp", 50)  # below 30% of 195
	sw.set("_attack_timer", 0.0)
	sw.call("_process_attack", 0.016)
	assert_almost_eq(sw.get("_attack_timer"), 0.5 / 1.4, 0.01, "berserk: 40% faster attacks below 30% HP")
	sw.set("hp", 195)
	sw.set("_attack_timer", 0.0)
	sw.call("_process_attack", 0.016)
	assert_almost_eq(sw.get("_attack_timer"), 0.5, 0.01, "healthy swordsman uses the normal cooldown")
	FactionManager.set_player_faction("industrial")


func test_fight_back() -> void:
	FactionManager.set_player_faction("brute")
	var miner: Node2D = _spawn_unit("res://scripts/resources/units/miner.tres", PLAYER, Vector2(-600, 16))
	var attacker: Node2D = _spawn_unit("res://scripts/resources/units/swordsman.tres", ENEMY, Vector2(-584, 16))
	var before: int = attacker.get("hp")
	miner.call("take_damage", 10, attacker)
	assert_eq(attacker.get("hp"), before - 5, "brute miner deals 5 damage when attacked")
	FactionManager.set_player_faction("industrial")


func test_supply_drop() -> void:
	EconomyManager.reset()
	var dragon: Node2D = _spawn_unit("res://scripts/resources/units/dragon.tres", PLAYER, Vector2(-600, 16))
	var target: Node2D = _spawn_unit("res://scripts/resources/units/swordsman.tres", ENEMY, Vector2(-584, 16))
	var before: int = EconomyManager.get_coin(PLAYER)
	target.call("take_damage", 9999, dragon)
	assert_eq(EconomyManager.get_coin(PLAYER), before + 10, "industrial dragon kill generates 10g")


func test_mana_burn_dampens_next_attack() -> void:
	FactionManager.set_player_faction("arcane")
	var dragon: Node2D = _spawn_unit("res://scripts/resources/units/dragon.tres", PLAYER, Vector2(-700, 16))
	var burner: Node2D = _spawn_unit("res://scripts/resources/units/swordsman.tres", ENEMY, Vector2(-600, 16))
	var victim: Node2D = _spawn_unit("res://scripts/resources/units/swordsman.tres", PLAYER, Vector2(-584, 16))
	var proj: Node2D = load("res://scenes/projectile.tscn").instantiate()
	proj.set("team", PLAYER)
	proj.set("damage", 10)
	proj.set("is_fireball", true)
	proj.set("is_dragon_flame", true)
	proj.set("aoe_radius", 55.0)
	proj.set("source", dragon)
	proj.set("target_position", burner.global_position)
	proj.global_position = burner.global_position
	_main.get_node("Projectiles").add_child(proj)
	autofree(proj)
	proj.call("_impact")
	assert_almost_eq(burner.get("_next_attack_damage_mult"), 0.8, 0.001, "dragon flame applies mana burn")
	burner.call("attack_unit", victim)
	burner.set("_attack_timer", 0.0)
	burner.call("_process_attack", 0.016)
	var dealt: int = victim.data.max_hp - victim.get("hp")
	assert_eq(dealt, 5, "burned hit: roundi(7.5*0.9 industrial * 0.8)")
	assert_almost_eq(burner.get("_next_attack_damage_mult"), 1.0, 0.001, "burn is consumed after one hit")
	FactionManager.set_player_faction("industrial")


func test_swarm_speed_bonus() -> void:
	var a: Node2D = _spawn_unit("res://scripts/resources/units/swordsman.tres", PLAYER, Vector2(-600, 16))
	var b: Node2D = _spawn_unit("res://scripts/resources/units/swordsman.tres", PLAYER, Vector2(-590, 16))
	var c: Node2D = _spawn_unit("res://scripts/resources/units/swordsman.tres", PLAYER, Vector2(-580, 16))
	var lone: Node2D = _spawn_unit("res://scripts/resources/units/swordsman.tres", PLAYER, Vector2(-1200, 16))
	await wait_seconds(0.4)  # swarm check runs at 4 Hz
	assert_almost_eq(a.data.speed, 92.0, 0.5, "3+ swordsmen swarm: +15% speed")
	assert_almost_eq(b.data.speed, 92.0, 0.5)
	assert_almost_eq(c.data.speed, 92.0, 0.5)
	assert_almost_eq(lone.data.speed, 80.0, 0.5, "a lone swordsman keeps base speed")


func test_miner_reveal_scans_ore() -> void:
	FactionManager.set_player_faction("arcane")
	# Find a buried (undiscovered) ore cell to scan.
	var ore_cell: Vector2i = Vector2i(-9999, -9999)
	for x in range(-40, 41):
		for y in range(1, 22):
			var pos := Vector2i(x, y)
			var cell = _grid.get_cell(pos)
			if cell != null and cell.type == GridWorld.CellType.ORE and not cell.sonar_revealed.get(PLAYER, false) and cell.hp == cell.max_hp:
				ore_cell = pos
				break
		if ore_cell.x > -9999:
			break
	assert_ne(ore_cell.x, -9999, "map should have undiscovered ore")
	var miner: Node2D = _spawn_unit("res://scripts/resources/units/miner.tres", PLAYER, _grid.grid_to_world(ore_cell))
	miner.is_underground = true
	await wait_seconds(0.2)  # first scan fires on the first underground tick
	assert_true(_grid.get_cell(ore_cell).sonar_revealed.get(PLAYER, false), "arcane miner reveals ore in a 4-cell radius")
	FactionManager.set_player_faction("industrial")


func test_enemy_faction_hidden_until_scouted() -> void:
	FactionManager.reset()
	assert_false(FactionManager.is_faction_identified(ENEMY), "enemy faction starts hidden")
	var enemy_building: Node2D = _main.get_node("World/EnemyBuilding")
	_spawn_unit("res://scripts/resources/units/swordsman.tres", PLAYER, enemy_building.global_position + Vector2(-200, 0))
	await wait_seconds(0.8)  # the building's scout check runs at 2 Hz
	assert_true(FactionManager.is_faction_identified(ENEMY), "a scout near the enemy base identifies the faction")


func test_heavy_bolt_slows_target() -> void:
	FactionManager.set_player_faction("brute")
	var archer: Node2D = _spawn_unit("res://scripts/resources/units/archer.tres", PLAYER, Vector2(-700, 16))
	var target: Node2D = _spawn_unit("res://scripts/resources/units/swordsman.tres", ENEMY, Vector2(-600, 16))
	var proj: Node2D = load("res://scenes/projectile.tscn").instantiate()
	proj.set("team", PLAYER)
	proj.set("damage", 10)
	proj.set("source", archer)
	proj.set("target_position", target.global_position)
	proj.global_position = target.global_position
	_main.get_node("Projectiles").add_child(proj)
	autofree(proj)
	proj.call("_impact")
	assert_almost_eq(target.get("_slow_mult"), 0.7, 0.001, "heavy bolt slows by 30%")
	assert_almost_eq(target.get("_slow_timer"), 2.0, 0.001, "slow lasts 2s")
	FactionManager.set_player_faction("industrial")


func test_crush_stuns_target() -> void:
	FactionManager.set_player_faction("brute")
	var dragon: Node2D = _spawn_unit("res://scripts/resources/units/dragon.tres", PLAYER, Vector2(-700, 16))
	var target: Node2D = _spawn_unit("res://scripts/resources/units/swordsman.tres", ENEMY, Vector2(-600, 16))
	var proj: Node2D = load("res://scenes/projectile.tscn").instantiate()
	proj.set("team", PLAYER)
	proj.set("damage", 10)
	proj.set("is_fireball", true)
	proj.set("is_dragon_flame", true)
	proj.set("aoe_radius", 55.0)
	proj.set("source", dragon)
	proj.set("target_position", target.global_position)
	proj.global_position = target.global_position
	_main.get_node("Projectiles").add_child(proj)
	autofree(proj)
	proj.call("_impact")
	assert_almost_eq(target.get("_stun_timer"), 0.5, 0.001, "crush stuns for 0.5s")
	target.call("_process", 0.1)
	assert_almost_eq(target.get("_stun_timer"), 0.4, 0.001, "stun ages in _process")
	FactionManager.set_player_faction("industrial")


func test_arcane_shot_pierces_to_second_target() -> void:
	FactionManager.set_player_faction("arcane")
	var archer: Node2D = _spawn_unit("res://scripts/resources/units/archer.tres", PLAYER, Vector2(-700, 16))
	var first: Node2D = _spawn_unit("res://scripts/resources/units/swordsman.tres", ENEMY, Vector2(-600, 16))
	var second: Node2D = _spawn_unit("res://scripts/resources/units/swordsman.tres", ENEMY, Vector2(-576, 16))
	var first_hp: int = first.get("hp")
	var second_hp: int = second.get("hp")
	var proj: Node2D = load("res://scenes/projectile.tscn").instantiate()
	proj.set("team", PLAYER)
	proj.set("damage", 5)
	proj.set("pierce", true)
	proj.set("source", archer)
	proj.set("target_position", first.global_position)
	proj.global_position = first.global_position
	_main.get_node("Projectiles").add_child(proj)
	autofree(proj)
	proj.call("_impact")
	assert_eq(first.get("hp"), first_hp - 5, "piercing arrow hits the first target")
	assert_eq(second.get("hp"), second_hp - 5, "and pierces into the enemy behind it")


func test_arcane_shot_grants_pierce_on_cooldown() -> void:
	var archer: Node2D = _spawn_unit("res://scripts/resources/units/archer.tres", PLAYER, Vector2(-700, 16))
	var target: Node2D = _spawn_unit("res://scripts/resources/units/swordsman.tres", ENEMY, Vector2(-620, 16))
	var projectiles_before: int = _main.get_node("Projectiles").get_child_count()
	archer.call("attack_unit", target)
	archer.set("_attack_timer", 0.0)
	archer.set("_arcane_shot_timer", 0.0)
	archer.call("_process_attack", 0.016)
	assert_almost_eq(archer.get("_arcane_shot_timer"), 8.0, 0.01, "arcane shot has an 8s cooldown")
	var projectiles: Node = _main.get_node("Projectiles")
	assert_eq(projectiles.get_child_count(), projectiles_before + 1, "one arrow was fired")
	assert_true(projectiles.get_child(projectiles.get_child_count() - 1).get("pierce"), "the arrow pierces")
	FactionManager.set_player_faction("industrial")


func test_blink_teleports_away_from_melee() -> void:
	FactionManager.set_player_faction("")
	var wizard: Node2D = _spawn_unit("res://scripts/resources/units/wizard.tres", PLAYER, Vector2(-600, 16))
	var threat: Node2D = _spawn_unit("res://scripts/resources/units/swordsman.tres", ENEMY, Vector2(-580, 16))
	wizard.call("_try_blink")
	assert_gt(wizard.global_position.distance_to(threat.global_position), 100.0, "blink teleports the wizard away")
	assert_almost_eq(wizard.get("_blink_timer"), 15.0, 0.01, "base blink cooldown is 15s")
	FactionManager.set_player_faction("arcane")
	var arcane_wizard: Node2D = _spawn_unit("res://scripts/resources/units/wizard.tres", PLAYER, Vector2(-600, 16))
	var threat2: Node2D = _spawn_unit("res://scripts/resources/units/swordsman.tres", ENEMY, Vector2(-580, 16))
	arcane_wizard.call("_try_blink")
	assert_almost_eq(arcane_wizard.get("_blink_timer"), 10.0, 0.01, "arcane reduces the blink cooldown to 10s")
	FactionManager.set_player_faction("industrial")


func test_volley_fires_together() -> void:
	# Player faction is industrial here (suite default).
	var a: Node2D = _spawn_unit("res://scripts/resources/units/archer.tres", PLAYER, Vector2(-700, 16))
	var b: Node2D = _spawn_unit("res://scripts/resources/units/archer.tres", PLAYER, Vector2(-670, 16))
	var target: Node2D = _spawn_unit("res://scripts/resources/units/swordsman.tres", ENEMY, Vector2(-600, 16))
	var projectiles_before: int = _main.get_node("Projectiles").get_child_count()
	a.call("attack_unit", target)
	a.set("_attack_timer", 0.0)
	a.set("_volley_timer", 0.0)
	a.call("_process_attack", 0.016)
	assert_almost_eq(a.get("_volley_timer"), 12.0, 0.01, "volley has a 12s cooldown")
	assert_almost_eq(b.get("_volley_timer"), 12.0, 0.01, "participants share the cooldown")
	assert_eq(_main.get_node("Projectiles").get_child_count(), projectiles_before + 2, "both archers fired at once")
