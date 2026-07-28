extends GutTest

# AI retaliation: enemy fighters besieging a building re-evaluate when enemy
# fighters damage them — some peel off to fight back (per-hit coin flip), so
# enough hits always flip the target. Player units never auto-retaliate:
# explicit player orders stay sovereign.

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
	# free would still be pending when the next test script instantiates its
	# own main.tscn — the old "Main" name would still be taken, the new scene
	# would be renamed, and every hard-coded /root/Main lookup would break.
	_main.free()


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


func test_damaged_sieger_retaliates_against_attacker() -> void:
	var enemy: Node2D = _spawn_unit("res://scripts/resources/units/swordsman.tres", ENEMY, Vector2(-440, 16))
	var attacker: Node2D = _spawn_unit("res://scripts/resources/units/swordsman.tres", PLAYER, Vector2(-460, 16))
	var player_building: Node2D = _building_for(PLAYER)
	enemy.call("attack_building", player_building)
	assert_eq(enemy.get("_target_building"), player_building)
	enemy.set("hp", 100000)
	# Retaliation is a per-hit coin flip; 40 hits makes "never retaliates"
	# astronomically unlikely (~1e-12).
	for i in range(40):
		if enemy.get("_target_unit") != null:
			break
		enemy.call("take_damage", 1, attacker)
	assert_eq(enemy.get("_target_unit"), attacker, "sieger must eventually fight its attacker")


func test_undamaged_sieger_keeps_attacking_building() -> void:
	var enemy: Node2D = _spawn_unit("res://scripts/resources/units/swordsman.tres", ENEMY, Vector2(-440, 16))
	var player_building: Node2D = _building_for(PLAYER)
	enemy.call("attack_building", player_building)
	assert_eq(enemy.get("_target_building"), player_building)
	assert_null(enemy.get("_target_unit"), "undamaged sieger stays on the building")


func test_retaliation_chance_scales_with_difficulty() -> void:
	var before: GameManager.Difficulty = GameManager.difficulty
	GameManager.set_difficulty(GameManager.Difficulty.EASY)
	assert_eq(GameManager.get_ai_retaliation_chance(), 0.25)
	GameManager.set_difficulty(GameManager.Difficulty.NIGHTMARE)
	assert_eq(GameManager.get_ai_retaliation_chance(), 0.9)
	GameManager.set_difficulty(before)


func test_player_units_never_auto_retaliate() -> void:
	var fighter: Node2D = _spawn_unit("res://scripts/resources/units/swordsman.tres", PLAYER, Vector2(440, 16))
	var enemy_attacker: Node2D = _spawn_unit("res://scripts/resources/units/swordsman.tres", ENEMY, Vector2(460, 16))
	var enemy_building: Node2D = _building_for(ENEMY)
	fighter.call("attack_building", enemy_building)
	fighter.set("hp", 100000)
	for i in range(10):
		fighter.call("take_damage", 1, enemy_attacker)
	assert_null(fighter.get("_target_unit"), "player orders stay sovereign — no auto-retaliation")
	assert_eq(fighter.get("_target_building"), enemy_building)
