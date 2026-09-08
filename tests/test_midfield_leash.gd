extends GutTest

# Midfield rule: idle auto-engagement only defends the home half of the map
# (the central line is world x=0; the player half is x<0, the enemy half x>0).
# Auto-acquired chases break when the chaser crosses the line, and the idle
# scan never acquires surface targets already on the enemy half. Explicit
# attack orders, stance marches, and rally hunts are exempt.

const PLAYER: int = 0
const ENEMY: int = 1

var _main: Node
var _units: Node


func before_all() -> void:
	seed(12345)
	_main = load("res://scenes/main.tscn").instantiate()
	get_tree().root.add_child(_main)
	get_tree().current_scene = _main
	_units = _main.get_node("Units")
	# Fog-agnostic suite (leash mechanics): both teams see the whole map.
	_main.get_node("World/GridWorld").set_reveal_all(PLAYER, true)
	_main.get_node("World/GridWorld").set_reveal_all(ENEMY, true)


func after_all() -> void:
	# Free immediately, not queue_free(): a queued free could still be pending
	# when the next test script instantiates its own main.tscn and every
	# hard-coded /root/Main lookup would break.
	_main.free()


func _spawn_fighter(team: int, pos: Vector2) -> Node2D:
	var unit: Node2D = load("res://scenes/unit.tscn").instantiate()
	unit.set("data", load("res://scripts/resources/units/swordsman.tres").duplicate(true))
	unit.set("team", team)
	unit.position = pos
	_units.add_child(unit)
	autofree(unit)
	return unit


func test_idle_scan_engages_target_on_own_half() -> void:
	var fighter: Node2D = _spawn_fighter(PLAYER, Vector2(-120, 16))
	var enemy: Node2D = _spawn_fighter(ENEMY, Vector2(-60, 16))
	assert_eq(fighter._find_auto_attack_target(), enemy, "own-half invaders are fair game")


func test_idle_scan_ignores_target_across_midfield() -> void:
	var fighter: Node2D = _spawn_fighter(PLAYER, Vector2(-120, 16))
	_spawn_fighter(ENEMY, Vector2(120, 16))  # 240px away: inside sight range (250)
	assert_null(fighter._find_auto_attack_target(),
		"enemies on the enemy half must not trigger auto-engagement")


func test_midfield_rule_is_symmetric_for_the_enemy() -> void:
	var fighter: Node2D = _spawn_fighter(ENEMY, Vector2(120, 16))
	_spawn_fighter(PLAYER, Vector2(-120, 16))  # on the player half: out of bounds for the AI's idle scan
	assert_null(fighter._find_auto_attack_target())


func test_auto_chase_breaks_at_midfield() -> void:
	var fighter: Node2D = _spawn_fighter(PLAYER, Vector2(-120, 16))
	var enemy: Node2D = _spawn_fighter(ENEMY, Vector2(-60, 16))
	fighter._handle_idle_fighter()
	assert_eq(fighter._state, Unit.State.ATTACK)
	assert_true(fighter.get("_auto_engaged"))
	enemy.global_position = Vector2(300, 16)  # fled deep into the enemy half
	fighter.global_position = Vector2(10, 16)  # the chase crossed the central line
	fighter._process_attack(0.016)
	assert_eq(fighter._state, Unit.State.IDLE, "the chase must end at midfield")
	assert_null(fighter.get("_target_unit"))


func test_auto_chase_continues_on_own_half() -> void:
	var fighter: Node2D = _spawn_fighter(PLAYER, Vector2(-120, 16))
	var enemy: Node2D = _spawn_fighter(ENEMY, Vector2(-60, 16))
	fighter._handle_idle_fighter()
	enemy.global_position = Vector2(60, 16)
	fighter.global_position = Vector2(-60, 16)  # chasing, but still on the home half
	fighter._process_attack(0.016)
	assert_eq(fighter._state, Unit.State.ATTACK, "chases inside the home half keep going")


func test_in_range_fight_at_the_line_is_not_interrupted() -> void:
	var fighter: Node2D = _spawn_fighter(PLAYER, Vector2(-120, 16))
	var enemy: Node2D = _spawn_fighter(ENEMY, Vector2(-60, 16))
	fighter._handle_idle_fighter()
	fighter.global_position = Vector2(10, 16)  # a step past the line...
	enemy.global_position = Vector2(30, 16)    # ...but already in melee range (28)
	fighter._process_attack(0.016)
	assert_eq(fighter._state, Unit.State.ATTACK, "the leash cuts chases, not active fights")


func test_explicit_attack_order_crosses_midfield() -> void:
	var fighter: Node2D = _spawn_fighter(PLAYER, Vector2(-120, 16))
	var enemy: Node2D = _spawn_fighter(ENEMY, Vector2(-60, 16))
	fighter.call("attack_unit", enemy)  # explicit order: unleashed
	assert_false(fighter.get("_auto_engaged"))
	enemy.global_position = Vector2(300, 16)
	fighter.global_position = Vector2(10, 16)
	fighter._process_attack(0.016)
	assert_eq(fighter._state, Unit.State.ATTACK, "explicit attack orders chase as far as they like")


func test_longbow_blind_fire_is_exempt_from_midfield_rule() -> void:
	# Longbow (Revamp Phase 6) exists to shoot across the line into fog; the
	# midfield rule must not take that away.
	ResearchManager._levels[PLAYER]["longbow"] = 1
	var archer: Node2D = load("res://scenes/unit.tscn").instantiate()
	archer.set("data", load("res://scripts/resources/units/archer.tres").duplicate(true))
	archer.set("team", PLAYER)
	archer.position = Vector2(-120, 16)
	_units.add_child(archer)
	autofree(archer)
	var enemy: Node2D = _spawn_fighter(ENEMY, Vector2(120, 16))  # enemy half, in archer sight
	assert_eq(archer._find_auto_attack_target(), enemy)
	ResearchManager.reset()
