extends GutTest

# Rally stance: fighters hunt every enemy on the surface (miners included)
# while the rally stays active; any explicit command cancels it. Miners drop
# their full cargo as a pickup on death so the coin is never lost.

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
	# Free immediately, not queue_free(): these tests never await, so a queued
	# free would race the next script's main.tscn boot and break /root/Main
	# lookups (see test_ai_retaliation.gd).
	_main.free()


func _spawn_unit(tres_path: String, team: int, pos: Vector2) -> Node2D:
	var unit: Node2D = load("res://scenes/unit.tscn").instantiate()
	unit.set("data", load(tres_path).duplicate(true))
	unit.set("team", team)
	unit.position = pos
	_units.add_child(unit)
	autofree(unit)
	return unit


func test_rally_targets_surface_miners() -> void:
	var fighter: Node2D = _spawn_unit("res://scripts/resources/units/swordsman.tres", PLAYER, Vector2(0, 16))
	var surface_miner: Node2D = _spawn_unit("res://scripts/resources/units/miner.tres", ENEMY, Vector2(60, 16))
	fighter.call("rally_to", Vector2(200, 16))
	assert_true(fighter.get("_rally_active"), "rally order activates the hunt")
	assert_eq(fighter.call("_find_rally_target"), surface_miner, "surface miners are rally targets")


func test_rally_ignores_underground_enemies() -> void:
	var fighter: Node2D = _spawn_unit("res://scripts/resources/units/swordsman.tres", PLAYER, Vector2(0, 16))
	var underground_miner: Node2D = _spawn_unit("res://scripts/resources/units/miner.tres", ENEMY, Vector2(60, 176))
	underground_miner.set("is_underground", true)
	fighter.call("rally_to", Vector2(200, 16))
	assert_null(fighter.call("_find_rally_target"), "underground enemies are out of the surface sweep")


func test_rally_engage_keeps_rally_active() -> void:
	var fighter: Node2D = _spawn_unit("res://scripts/resources/units/swordsman.tres", PLAYER, Vector2(0, 16))
	_spawn_unit("res://scripts/resources/units/miner.tres", ENEMY, Vector2(60, 16))
	fighter.call("rally_to", Vector2(200, 16))
	assert_true(fighter.call("_engage_rally_target_if_any"), "a target is found")
	assert_eq(fighter.get("_state"), 2, "engaging means ATTACK state")  # State.ATTACK == 2
	assert_true(fighter.get("_rally_active"), "engagement must not cancel the rally")


func test_explicit_command_cancels_rally() -> void:
	var fighter: Node2D = _spawn_unit("res://scripts/resources/units/swordsman.tres", PLAYER, Vector2(0, 16))
	fighter.call("rally_to", Vector2(200, 16))
	assert_true(fighter.get("_rally_active"))
	fighter.call("move_to", Vector2(-100, 16))
	assert_false(fighter.get("_rally_active"), "any explicit command cancels the rally")


func test_rally_underground_point_rejected() -> void:
	var fighter: Node2D = _spawn_unit("res://scripts/resources/units/swordsman.tres", PLAYER, Vector2(0, 16))
	fighter.call("rally_to", Vector2(0, 200))
	assert_false(fighter.get("_rally_active"), "underground rally points are rejected (surface hunt only)")


func test_fighter_returns_to_post_when_idle() -> void:
	var fighter: Node2D = _spawn_unit("res://scripts/resources/units/swordsman.tres", PLAYER, Vector2(-300, 16))
	var post: Vector2 = fighter.get("_post_point")
	assert_eq(post, fighter.global_position, "post defaults to the spawn point")
	fighter.global_position = Vector2(100, 16)  # teleported far from its post
	await wait_frames(3)
	assert_eq(fighter.get("_state"), 1, "idle fighter walks back to its post")  # State.MOVE == 1
	var path: PackedVector2Array = fighter.get("_path")
	assert_false(path.is_empty(), "has a path home")
	if not path.is_empty():
		assert_true(path[path.size() - 1].distance_to(post) < 20.0, "path ends at the post")


func test_move_to_updates_post() -> void:
	var fighter: Node2D = _spawn_unit("res://scripts/resources/units/swordsman.tres", PLAYER, Vector2(-300, 16))
	fighter.call("move_to", Vector2(100, 16))
	assert_eq(fighter.get("_post_point"), Vector2(100, 16), "explicit move sets a new post")


func test_garrison_recalls_fighters_to_base() -> void:
	var fighter: Node2D = _spawn_unit("res://scripts/resources/units/swordsman.tres", PLAYER, Vector2(-350, 16))
	fighter.call("move_to", Vector2(300, 16))  # ordered far from home first
	var pc: Node = _main.get_node("PlayerController")
	pc.set_stance("garrison")
	assert_true(fighter.get("_post_point").x < -380.0, "post becomes the home building, not the old spot")
	assert_eq(fighter.get("_state"), 1, "fighter moves home to defend")  # State.MOVE == 1


func test_garrison_exits_mine() -> void:
	var fighter: Node2D = _spawn_unit("res://scripts/resources/units/swordsman.tres", PLAYER, Vector2(-350, 176))
	fighter.set("is_underground", true)
	var pc: Node = _main.get_node("PlayerController")
	pc.set_stance("garrison")
	assert_eq(fighter.get("_state"), 6, "underground fighters climb out of the mine")  # State.EXIT_MINE == 6
	assert_true(fighter.get("_post_point").x < -380.0, "post is the home building")


func test_rally_rejected_for_miners() -> void:
	var miner: Node2D = _spawn_unit("res://scripts/resources/units/miner.tres", PLAYER, Vector2(-500, 16))
	miner.call("rally_to", Vector2(200, 16))
	assert_false(miner.get("_rally_active"), "miners cannot rally")


func test_miner_death_drops_full_cargo() -> void:
	var miner: Node2D = _spawn_unit("res://scripts/resources/units/miner.tres", ENEMY, Vector2(300, 16))
	miner.set("carried_coin", 40)
	var death_pos: Vector2 = miner.global_position
	miner.call("take_damage", 9999)
	var found: Node2D = null
	for child in get_tree().current_scene.get_children():
		if child is CoinPickup and child.global_position == death_pos:
			found = child
	assert_not_null(found, "a pickup spawns where the miner died")
	if found:
		assert_eq(found.coin_value, 40, "the full cargo is dropped, not lost")


func test_archer_kites_to_standoff_range() -> void:
	# A melee enemy inside 40% of the archer's attack range pushes the archer
	# back: it should retreat to its standoff distance while staying in ATTACK.
	var archer: Node2D = _spawn_unit("res://scripts/resources/units/archer.tres", PLAYER, Vector2(0, 16))
	var enemy: Node2D = _spawn_unit("res://scripts/resources/units/swordsman.tres", ENEMY, Vector2(40, 16))
	enemy.set_process(false)  # Freeze the melee unit so only the archer moves.
	archer.call("attack_unit", enemy)
	await wait_seconds(1.2)
	var gap: float = archer.global_position.distance_to(enemy.global_position)
	assert_true(gap > 55.0, "archer should retreat toward its standoff range, gap=%f" % gap)
	assert_eq(archer.get("_state"), 2, "still in ATTACK state while kiting")  # State.ATTACK == 2


func test_out_of_combat_regen() -> void:
	var unit: Node2D = _spawn_unit("res://scripts/resources/units/swordsman.tres", PLAYER, Vector2(0, 16))
	unit.call("take_damage", 50)
	assert_eq(unit.get("hp"), 100)
	await wait_seconds(6.0)  # 5s no-damage delay, then ~1s of regen
	assert_true(unit.get("hp") > 100, "regen kicks in after the no-damage delay")
	assert_true(unit.get("hp") < unit.get("data").max_hp, "regen is slow — not a full heal in 1s")


func test_regen_waits_for_damage_to_stop() -> void:
	var unit: Node2D = _spawn_unit("res://scripts/resources/units/swordsman.tres", PLAYER, Vector2(0, 16))
	unit.call("take_damage", 50)
	await wait_seconds(3.0)  # inside the 5s delay: no regen yet
	unit.call("take_damage", 10)  # resets the delay
	assert_eq(unit.get("hp"), 90)
	await wait_seconds(2.0)  # still inside the reset delay
	assert_eq(unit.get("hp"), 90, "taking damage keeps regen paused")
