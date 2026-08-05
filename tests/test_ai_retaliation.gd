extends GutTest

# Siege retaliation: a fighter besieging a building re-evaluates when an enemy
# fighter damages it — it peels off to fight back, so a siege under fire turns
# into a real battle instead of a shooting gallery. Player units always
# retaliate; AI units roll per hit against the difficulty's retaliation
# chance, so enough hits always flip the target.

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
	# Fog-agnostic suite (retaliation mechanics): both teams see the whole map.
	_main.get_node("World/GridWorld").set_reveal_all(PLAYER, true)
	_main.get_node("World/GridWorld").set_reveal_all(ENEMY, true)


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
	assert_eq(GameManager.get_ai_retaliation_chance(), 0.35)
	GameManager.set_difficulty(GameManager.Difficulty.NIGHTMARE)
	assert_eq(GameManager.get_ai_retaliation_chance(), 1.0)
	GameManager.set_difficulty(before)


func test_player_sieger_retaliates_against_attacker() -> void:
	var fighter: Node2D = _spawn_unit("res://scripts/resources/units/swordsman.tres", PLAYER, Vector2(440, 16))
	var enemy_attacker: Node2D = _spawn_unit("res://scripts/resources/units/swordsman.tres", ENEMY, Vector2(460, 16))
	var enemy_building: Node2D = _building_for(ENEMY)
	fighter.call("attack_building", enemy_building)
	assert_eq(fighter.get("_target_building"), enemy_building)
	fighter.set("hp", 100000)
	# Player retaliation is deterministic: a single hit flips the siege onto
	# the attacker (no difficulty roll for the player's own army).
	fighter.call("take_damage", 1, enemy_attacker)
	assert_eq(fighter.get("_target_unit"), enemy_attacker, "player sieger must fight back when attacked")
	assert_null(fighter.get("_target_building"))
