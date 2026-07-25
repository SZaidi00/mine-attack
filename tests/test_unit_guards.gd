extends GutTest

# Unit command guards: fighters can't mine, units can't enter the enemy
# mine, and unreachable mine targets are rejected with a reason (blacklist),
# never silently.

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
	_main.queue_free()


func _spawn_unit(tres_path: String, team: int, pos: Vector2) -> Node2D:
	var unit: Node2D = load("res://scenes/unit.tscn").instantiate()
	unit.set("data", load(tres_path).duplicate(true))
	unit.set("team", team)
	unit.position = pos
	_units.add_child(unit)
	autofree(unit)
	return unit


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
