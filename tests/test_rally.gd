extends GutTest

# Rally stance: fighters hunt every enemy on the surface (miners included)
# while the rally stays active; any explicit command cancels it. Miners drop
# their full cargo as a pickup on death so the coin is never lost.

const PLAYER: int = 0
const ENEMY: int = 1

var _main: Node
var _units: Node


func before_all() -> void:
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
