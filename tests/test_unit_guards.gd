extends GutTest

# Unit command guards: fighters can't mine, units can't enter the enemy
# mine, and unreachable mine targets are rejected with a reason (blacklist),
# never silently.

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
	# Free immediately: a queued free can still be pending when the next test
	# script instantiates its own main.tscn — the old "Main" name would still
	# be taken and every hard-coded /root/Main lookup would break.
	_main.free()


func _spawn_unit(tres_path: String, team: int, pos: Vector2) -> Node2D:
	var unit: Node2D = load("res://scenes/unit.tscn").instantiate()
	unit.set("data", load(tres_path).duplicate(true))
	unit.set("team", team)
	unit.position = pos
	_units.add_child(unit)
	autofree(unit)
	return unit


func test_corpse_hits_do_not_leak_population() -> void:
	# A dying unit stays valid for its 1s fade-out and in-flight projectiles
	# can still land on it. Without the DEAD guard in take_damage, each extra
	# hit re-runs _die() and removes population again — over a match the cap
	# drifts and the army grows past MAX_UNITS.
	EconomyManager.reset()
	EconomyManager.add_population(PLAYER, 2)  # this unit plus one committed slot
	var fighter: Node2D = _spawn_unit("res://scripts/resources/units/swordsman.tres", PLAYER, Vector2(-480, 80))
	fighter.call("take_damage", 100000)
	assert_eq(fighter.get("_state"), 9, "lethal hit kills (State.DEAD == 9)")  # State.DEAD == 9
	fighter.call("take_damage", 50)  # stray projectile landing on the corpse
	fighter.call("take_damage", 50)
	assert_eq(EconomyManager.get_population(PLAYER), 1, "population removed exactly once")


func test_fighter_cannot_mine() -> void:
	var fighter: Node2D = _spawn_unit("res://scripts/resources/units/swordsman.tres", PLAYER, Vector2(-480, 80))
	fighter.call("mine_cell", Vector2i(-14, 2))
	assert_ne(fighter.get("_state"), 3, "MINE state must be rejected for fighters")  # State.MINE == 3


func test_enter_mine_rejects_wrong_team() -> void:
	var fighter: Node2D = _spawn_unit("res://scripts/resources/units/swordsman.tres", PLAYER, Vector2(480, 16))
	var enemy_entry: Node2D = null
	for e in get_tree().get_nodes_in_group("mine_entries"):
		if e.get("team") == ENEMY:
			enemy_entry = e
	assert_not_null(enemy_entry)
	var before: Vector2 = fighter.global_position
	enemy_entry.call("enter_mine", fighter)
	assert_false(fighter.get("is_underground"), "player unit must not enter the enemy mine")
	assert_eq(fighter.global_position, before, "rejected unit is not teleported")


func test_unreachable_mine_target_is_blacklisted() -> void:
	# A miner underground, ordered to a deep solid cell it cannot possibly
	# reach: must go idle and blacklist the cell, never walk through dirt.
	var miner: Node2D = _spawn_unit("res://scripts/resources/units/miner.tres", PLAYER, Vector2(-464, 176))
	miner.set("is_underground", true)
	var far_cell: Vector2i = Vector2i(-30, 18)
	miner.call("mine_cell", far_cell)
	assert_ne(miner.get("_state"), 3, "no MINE state for an unreachable cell")
	assert_true(miner.call("is_cell_blacklisted", far_cell), "cell lands on the no-path blacklist")


func test_miner_deposit_requires_cargo() -> void:
	var miner: Node2D = _spawn_unit("res://scripts/resources/units/miner.tres", PLAYER, Vector2(-500, 16))
	miner.set("carried_coin", 0)
	miner.call("deposit_coin")
	assert_ne(miner.get("_state"), 4, "DEPOSIT with empty cargo must be rejected")  # State.DEPOSIT == 4


func test_miner_upgrade_applies_speed_and_mining_stats() -> void:
	EconomyManager.reset()  # 500 coin: exactly the L2 upgrade cost
	var miner: Node2D = _spawn_unit("res://scripts/resources/units/miner.tres", PLAYER, Vector2(-500, 16))
	assert_eq(miner.get("data").speed, 60.0, "L1 base speed")
	assert_true(EconomyManager.upgrade_miner(PLAYER), "L2 affordable at 500")
	miner.call("_apply_miner_upgrade")
	assert_eq(miner.get("data").speed, 70.0, "L2 speed from MINER_STATS")
	assert_eq(miner.get("data").mining_swings_per_sec, 3.0, "L2 mining rate")
	EconomyManager.add_coin(PLAYER, 1500)
	assert_true(EconomyManager.upgrade_miner(PLAYER), "L3 upgrade")
	miner.call("_apply_miner_upgrade")
	assert_eq(miner.get("data").speed, 80.0, "L3 speed from MINER_STATS")
	assert_eq(miner.get("data").mining_swings_per_sec, 5.0, "L3 mining rate")


func test_fighter_upgrade_applies_stats() -> void:
	EconomyManager.reset()
	var swordsman: Node2D = _spawn_unit("res://scripts/resources/units/swordsman.tres", PLAYER, Vector2(-500, 16))
	assert_eq(swordsman.get("data").max_hp, 150, "L1 base HP")
	EconomyManager.add_coin(PLAYER, 1000)
	assert_true(EconomyManager.upgrade_fighter(PLAYER, "swordsman"))
	swordsman.call("_apply_fighter_upgrade")
	assert_eq(swordsman.get("data").max_hp, 195, "L2 HP from FIGHTER_UPGRADES")
	assert_eq(swordsman.get("data").damage_per_hit, 9.5, "L2 damage from FIGHTER_UPGRADES")
	# Upgrading an unrelated type does not touch this unit.
	EconomyManager.upgrade_fighter(PLAYER, "archer")
	swordsman.call("_apply_fighter_upgrade")
	assert_eq(swordsman.get("data").max_hp, 195, "archer upgrade must not affect swordsman")


func test_seek_does_not_prefer_buried_ore() -> void:
	# Miners don't know where buried ore is: the seek must not beeline to
	# undiscovered ore — it digs the nearest face instead.
	var miner: Node2D = _spawn_unit("res://scripts/resources/units/miner.tres", PLAYER, Vector2(-464, 80))
	miner.set("is_underground", true)
	var c: Dictionary = _find_seek_candidates(miner)
	assert_ne(c.ore, Vector2i(-9999, -9999), "scenario needs an undiscovered ore target")
	assert_ne(c.dirt, Vector2i(-9999, -9999), "scenario needs a dirt target")
	assert_true(c.dirt_d < c.ore_d, "scenario needs dirt closer than the buried ore")
	miner.call("_find_and_mine")
	assert_ne(miner.get("_target_cell"), Vector2i(-9999, -9999), "miner found something to dig")
	assert_ne(miner.get("_target_cell"), c.ore, "buried ore must not be preferred")
	miner.call("stop")


func test_damaged_ore_is_discovered_and_preferred() -> void:
	# Once an ore tile has taken a swing (hp < max_hp = it yielded gold), the
	# miner "knows" about it and prefers it over plain dirt faces.
	var miner: Node2D = _spawn_unit("res://scripts/resources/units/miner.tres", PLAYER, Vector2(-464, 80))
	miner.set("is_underground", true)
	var c: Dictionary = _find_seek_candidates(miner)
	assert_ne(c.ore, Vector2i(-9999, -9999), "scenario needs an undiscovered ore target")
	var grid: Node = _main.get_node("World/GridWorld")
	grid.damage_cell(c.ore, 1, 1)  # first swing: gold! the ore is discovered
	miner.call("_find_and_mine")
	var target: Vector2i = miner.get("_target_cell")
	assert_ne(target, Vector2i(-9999, -9999), "miner found something to dig")
	var target_cell = grid.get_cell(target)
	assert_eq(target_cell.type, GridWorld.CellType.ORE, "discovered ore is preferred")
	assert_true(target_cell.hp < target_cell.max_hp, "target is a discovered (damaged) ore")
	miner.call("stop")


## Nearest valid diggable DIRT cell and nearest valid UNDISCOVERED ore cell
## for the given (underground, level 1) miner, replicating the seek's filters.
func _find_seek_candidates(miner: Node2D) -> Dictionary:
	var grid: Node = _main.get_node("World/GridWorld")
	var center: Vector2i = grid.world_to_grid(miner.global_position)
	var id: int = miner.get_instance_id()
	var dirt := Vector2i(-9999, -9999)
	var dirt_d := INF
	var ore := Vector2i(-9999, -9999)
	var ore_d := INF
	for x in range(-40, -1):  # player side while the wall stands (x <= -2)
		for y in range(1, 22):
			var pos := Vector2i(x, y)
			var cell = grid.get_cell(pos)
			if cell == null:
				continue
			if cell.type != GridWorld.CellType.DIRT and cell.type != GridWorld.CellType.ORE:
				continue
			if cell.miner_level_required > 1:
				continue
			if not grid.is_cell_claimable(pos, id):
				continue
			if not miner.call("_has_empty_neighbor", pos):
				continue
			var d: float = center.distance_to(pos)
			if cell.type == GridWorld.CellType.DIRT:
				if d < dirt_d:
					dirt_d = d
					dirt = pos
			elif cell.hp == cell.max_hp and d < ore_d:
				ore_d = d
				ore = pos
	return { "dirt": dirt, "dirt_d": dirt_d, "ore": ore, "ore_d": ore_d }


func test_cross_layer_attack_is_rejected() -> void:
	# Combat never crosses the surface/underground boundary: a surface dragon
	# must not be able to lock onto a miner working in the mine.
	var dragon: Node2D = _spawn_unit("res://scripts/resources/units/dragon.tres", PLAYER, Vector2(440, 16))
	var miner: Node2D = _spawn_unit("res://scripts/resources/units/miner.tres", ENEMY, Vector2(460, 80))
	miner.set("is_underground", true)
	assert_false(dragon.call("can_damage_unit", miner), "surface unit cannot damage an underground unit")
	dragon.call("attack_unit", miner)
	assert_ne(dragon.get("_state"), 2, "cross-layer attack_unit must be rejected")  # State.ATTACK == 2
	assert_null(dragon.get("_target_unit"))


func test_same_layer_underground_attack_is_allowed() -> void:
	# Sanity: the layer guard must not block legitimate underground combat.
	var fighter: Node2D = _spawn_unit("res://scripts/resources/units/swordsman.tres", PLAYER, Vector2(-460, 80))
	fighter.set("is_underground", true)
	var miner: Node2D = _spawn_unit("res://scripts/resources/units/miner.tres", ENEMY, Vector2(-440, 80))
	miner.set("is_underground", true)
	assert_true(fighter.call("can_damage_unit", miner), "same-layer underground combat still works")


func test_auto_attack_ignores_underground_units() -> void:
	# A surface dragon's auto-attack scan must not acquire underground targets.
	var dragon: Node2D = _spawn_unit("res://scripts/resources/units/dragon.tres", PLAYER, Vector2(440, 16))
	var enemy: Node2D = _spawn_unit("res://scripts/resources/units/swordsman.tres", ENEMY, Vector2(460, 80))
	enemy.set("is_underground", true)
	var found = dragon.call("_find_auto_attack_target")
	assert_true(found == null or found != enemy, "auto-attack must skip underground units")


func test_chase_drops_target_that_crosses_layers() -> void:
	# A miner fleeing down the shaft breaks the lock: the chaser goes idle
	# instead of following into the mine.
	var fighter: Node2D = _spawn_unit("res://scripts/resources/units/dragon.tres", PLAYER, Vector2(-440, 16))
	var target: Node2D = _spawn_unit("res://scripts/resources/units/miner.tres", ENEMY, Vector2(-460, 16))
	fighter.call("attack_unit", target)
	assert_eq(fighter.get("_state"), 2, "attack order accepted")  # State.ATTACK == 2
	target.set("is_underground", true)
	fighter.call("_process_attack", 0.016)
	assert_eq(fighter.get("_state"), 0, "chaser drops a target that crossed layers")  # State.IDLE == 0
	assert_null(fighter.get("_target_unit"))


func test_follow_path_arrives_at_destination_with_large_delta() -> void:
	# At 10x game speed with a low frame rate, speed * delta spans several
	# cells: the path must still carry the unit onto its final point, not
	# complete far from the destination (miners froze mid-approach).
	var unit: Node2D = _spawn_unit("res://scripts/resources/units/swordsman.tres", PLAYER, Vector2(300, 16))
	unit.set("_path", [Vector2(400, 16), Vector2(500, 16)])
	unit.set("_path_index", 0)
	unit.call("_follow_path", 3.0)  # one huge frame: step covers both points
	assert_true(unit.global_position.distance_to(Vector2(500, 16)) < 1.0,
		"unit must arrive at the final path point, pos=%s" % unit.global_position)
