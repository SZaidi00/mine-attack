extends GutTest

# Stance modes: Attack/Defend/Garrison are persistent army modes on the
# PlayerController. Setting a mode works with zero fighters, and every fighter
# trained afterwards automatically receives the mode's order on spawn.

const PLAYER: int = 0

var _main: Node
var _pc: Node
var _player_building: Node2D
var _enemy_building: Node2D


func before_all() -> void:
	# Deterministic map: Constants.DEBUG is off (so GridWorld doesn't seed
	# itself), but the tests assert against specific layouts.
	seed(12345)
	_main = load("res://scenes/main.tscn").instantiate()
	get_tree().root.add_child(_main)
	get_tree().current_scene = _main
	_pc = _main.get_node("PlayerController")
	for b in get_tree().get_nodes_in_group("buildings"):
		if b.get("team") == PLAYER:
			_player_building = b
		else:
			_enemy_building = b


func after_all() -> void:
	# Free immediately, not queue_free(): a queued free can race the next
	# script's main.tscn boot and break /root/Main lookups.
	_main.free()


func after_each() -> void:
	# Leave the controller in the default mode for the next test.
	_pc.set_stance("defend")


func _count_fighters() -> int:
	var count: int = 0
	for u in get_tree().get_nodes_in_group("player"):
		var data = u.get("data")
		if data != null and not data.is_miner:
			count += 1
	return count


func _newest_fighter() -> Node2D:
	var fighters: Array = []
	for u in get_tree().get_nodes_in_group("player"):
		var data = u.get("data")
		if data != null and not data.is_miner:
			fighters.append(u)
	return fighters[-1] if not fighters.is_empty() else null


func _train_fighter() -> Node2D:
	_player_building._spawn_front("swordsman", _player_building._resources["swordsman"])
	return _newest_fighter()


func test_default_mode_is_defend() -> void:
	assert_eq(_pc.get_stance(), "defend", "matches the tscn default (Defend pressed)")


func test_mode_set_with_zero_fighters() -> void:
	_pc.set_stance("attack")
	assert_eq(_pc.get_stance(), "attack", "mode is remembered even with no army to order")


func test_attack_mode_sends_new_fighter_to_enemy_building() -> void:
	_pc.set_stance("attack")
	var fighter: Node2D = _train_fighter()
	assert_not_null(fighter, "fighter spawned")
	assert_eq(fighter.get("_target_building"), _enemy_building, "spawn order: attack the enemy building")


func test_garrison_mode_posts_new_fighter_at_base() -> void:
	_pc.set_stance("garrison")
	var fighter: Node2D = _train_fighter()
	assert_not_null(fighter, "fighter spawned")
	var post: Vector2 = fighter.get("_post_point")
	var deposit: Vector2 = _player_building.get_deposit_point()
	assert_true(post.distance_to(deposit) < 24.0, "spawn order: hold at the home deposit point")
	assert_null(fighter.get("_target_building"), "garrison does not target the enemy building")


func test_defend_mode_leaves_new_fighter_holding_spawn() -> void:
	_pc.set_stance("defend")
	var fighter: Node2D = _train_fighter()
	assert_not_null(fighter, "fighter spawned")
	assert_null(fighter.get("_target_building"), "no attack order in defend mode")
	assert_eq(fighter.get("_state"), fighter.State.IDLE, "fresh fighter idles at its spawn post")


func test_miners_ignore_stance_modes() -> void:
	_pc.set_stance("attack")
	_player_building._spawn_front("miner", _player_building._resources["miner"])
	var miners: Array = get_tree().get_nodes_in_group("player").filter(
		func(u): return u.get("data") != null and u.data.is_miner)
	var miner: Node2D = miners[-1]
	assert_null(miner.get("_target_building"), "miners still head for the mine, not the enemy building")


func test_rally_does_not_change_mode() -> void:
	_pc.set_stance("garrison")
	# Rally arming requires at least one fighter; one exists from earlier tests.
	_pc.set_stance("rally")
	assert_eq(_pc.get_stance(), "garrison", "rally is a momentary arm, not a persistent mode")
	assert_true(_pc.is_rally_armed(), "rally placement is armed")
