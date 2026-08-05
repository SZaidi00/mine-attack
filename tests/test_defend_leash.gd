extends GutTest

# Defend leash: units holding their post (defend stance stop() / garrison)
# may chase auto-acquired targets a little — up to UNIT_DEFEND_LEASH_RANGE
# from the standing point — then drop the target and walk home. Explicit
# player attack/move orders are never leashed. Regression suite for: defend
# units chasing across the map and ending up sieging the enemy building.

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


func test_auto_engage_marks_hold_and_auto_flags() -> void:
	var fighter: Node2D = _spawn_fighter(PLAYER, Vector2(700, 16))
	fighter.call("stop")  # defend stance: hold here
	var enemy: Node2D = _spawn_fighter(ENEMY, Vector2(500, 16))  # in sight range
	fighter._handle_idle_fighter()
	assert_eq(fighter._state, Unit.State.ATTACK, "a holder must still defend itself")
	assert_true(fighter.get("_auto_engaged"), "the idle scan's pick must be marked as auto-engaged")
	assert_true(fighter.get("_hold_post"), "auto-engaging must not clear the hold")
	assert_eq(fighter.get("_target_unit"), enemy)


func test_defend_chase_drops_beyond_leash() -> void:
	var fighter: Node2D = _spawn_fighter(PLAYER, Vector2(700, 16))
	fighter.call("stop")
	_spawn_fighter(ENEMY, Vector2(500, 16))
	fighter._handle_idle_fighter()
	assert_eq(fighter._state, Unit.State.ATTACK)
	fighter.global_position = Vector2(200, 16)  # chased 500px from the post
	fighter._process_attack(0.016)
	assert_eq(fighter._state, Unit.State.IDLE, "past the leash the chase must end")
	assert_null(fighter.get("_target_unit"))


func test_defend_chase_within_leash_continues() -> void:
	var fighter: Node2D = _spawn_fighter(PLAYER, Vector2(700, 16))
	fighter.call("stop")
	_spawn_fighter(ENEMY, Vector2(500, 16))
	fighter._handle_idle_fighter()
	fighter.global_position = Vector2(400, 16)  # 300px from the post: inside the leash
	fighter._process_attack(0.016)
	assert_eq(fighter._state, Unit.State.ATTACK, "a little chase is fine")


func test_held_unit_ignores_targets_beyond_leash_from_post() -> void:
	var fighter: Node2D = _spawn_fighter(PLAYER, Vector2(700, 16))
	fighter.call("stop")
	fighter.global_position = Vector2(300, 16)  # drifted 400px from the post
	_spawn_fighter(ENEMY, Vector2(100, 16))  # in sight of the fighter, 600px from the post
	assert_null(fighter._find_auto_attack_target(),
		"a holder must not chain-engage targets far from its post")


func test_held_unit_never_auto_sieges_enemy_building() -> void:
	var fighter: Node2D = _spawn_fighter(PLAYER, Vector2(400, 16))
	fighter.call("stop")  # post at x=400 — the enemy building is ~560px away
	fighter.global_position = Vector2(750, 16)  # drifted next to the enemy building (in sight)
	assert_null(fighter._find_auto_attack_target(),
		"defend-toggled units must never wander into sieging the enemy building")


func test_explicit_attack_order_not_leashed() -> void:
	var fighter: Node2D = _spawn_fighter(PLAYER, Vector2(700, 16))
	fighter.call("stop")
	var enemy: Node2D = _spawn_fighter(ENEMY, Vector2(500, 16))
	fighter.call("attack_unit", enemy)  # explicit order: unleashed
	assert_false(fighter.get("_hold_post"))
	assert_false(fighter.get("_auto_engaged"))
	fighter.global_position = Vector2(200, 16)  # 500px from the old post
	fighter._process_attack(0.016)
	assert_eq(fighter._state, Unit.State.ATTACK, "explicit attack orders chase as far as they like")


func test_move_order_clears_hold() -> void:
	var fighter: Node2D = _spawn_fighter(PLAYER, Vector2(700, 16))
	fighter.call("stop")
	assert_true(fighter.get("_hold_post"))
	fighter.call("move_to", Vector2(600, 16))
	assert_false(fighter.get("_hold_post"), "moving re-anchors the unit — it is no longer holding")
	assert_eq(fighter._state, Unit.State.MOVE)


func test_garrison_sets_hold() -> void:
	var fighter: Node2D = _spawn_fighter(PLAYER, Vector2(700, 16))
	fighter.call("garrison_home")
	assert_true(fighter.get("_hold_post"), "garrisoned fighters hold the base")


# ─── Base under attack: the leash pulls in tight ───

func _player_building() -> Node2D:
	for b in get_tree().get_nodes_in_group("buildings"):
		if b.get("team") == PLAYER:
			return b
	return null


func test_defenders_hold_tight_while_base_under_attack() -> void:
	var fighter: Node2D = _spawn_fighter(PLAYER, Vector2(-800, 16))
	fighter.call("stop")
	_spawn_fighter(ENEMY, Vector2(-600, 16))  # 200px away: inside sight + normal leash, outside the siege leash
	_player_building().take_damage(1)
	fighter._handle_idle_fighter()
	assert_null(fighter.get("_target_unit"), "no 200px chase while the base is under attack")
	assert_eq(fighter._state, Unit.State.IDLE)


func test_defenders_still_fight_close_threats_while_base_under_attack() -> void:
	var fighter: Node2D = _spawn_fighter(PLAYER, Vector2(-800, 16))
	fighter.call("stop")
	var enemy: Node2D = _spawn_fighter(ENEMY, Vector2(-700, 16))  # 100px: inside the tight leash
	_player_building().take_damage(1)
	fighter._handle_idle_fighter()
	assert_eq(fighter.get("_target_unit"), enemy, "close attackers must still be fought")


func test_defenders_chase_normally_when_base_safe() -> void:
	_player_building().set("_last_damage_time", -999.0)  # earlier tests hit the base on purpose
	var fighter: Node2D = _spawn_fighter(PLAYER, Vector2(-800, 16))
	fighter.call("stop")
	_spawn_fighter(ENEMY, Vector2(-600, 16))  # same 200px, but the base is not under attack
	fighter._handle_idle_fighter()
	assert_eq(fighter._state, Unit.State.ATTACK, "200px chase is fine while the base is safe")
