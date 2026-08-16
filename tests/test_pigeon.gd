extends GutTest

# Pigeon scout: trained from sentry towers, fragile, only vulnerable to anti-air
# attackers (archers, wizards, dragons, and sentry towers).

const PLAYER: int = 0
const ENEMY: int = 1

var _main: Node
var _units: Node
var _grid: Node


func before_all() -> void:
	seed(12345)
	_main = load("res://scenes/main.tscn").instantiate()
	get_tree().root.add_child(_main)
	get_tree().current_scene = _main
	_units = _main.get_node("Units")
	_grid = _main.get_node("World/GridWorld")
	WeatherManager.set_weather_events_enabled(false)
	_grid.set_dynamic_events_enabled(false)


func after_all() -> void:
	WeatherManager.set_weather_events_enabled(true)
	_grid.set_dynamic_events_enabled(true)
	_main.free()


func before_each() -> void:
	EconomyManager.reset()
	GameManager.game_active = true


func _spawn_unit(tres_path: String, team: int, pos: Vector2) -> Node2D:
	var unit: Node2D = load("res://scenes/unit.tscn").instantiate()
	unit.set("data", load(tres_path).duplicate(true))
	unit.set("team", team)
	unit.position = pos
	_units.add_child(unit)
	autofree(unit)
	return unit


func _spawn_tower(team: int, pos: Vector2) -> Node2D:
	var tower: Node2D = load("res://scenes/tower.tscn").instantiate()
	tower.set("team", team)
	tower.position = pos
	tower.set("_is_built", true)
	_main.get_node("Structures").add_child(tower)
	autofree(tower)
	return tower


func test_pigeon_damaged_by_archer() -> void:
	var pigeon: Node2D = _spawn_unit("res://scripts/resources/units/pigeon.tres", ENEMY, Vector2(0, 16))
	var archer: Node2D = _spawn_unit("res://scripts/resources/units/archer.tres", PLAYER, Vector2(-80, 16))
	var before: int = pigeon.get("hp")
	pigeon.call("take_damage", 12, archer)
	assert_eq(pigeon.get("hp"), before - 12, "archer damage lands on pigeon")


func test_pigeon_damaged_by_wizard() -> void:
	var pigeon: Node2D = _spawn_unit("res://scripts/resources/units/pigeon.tres", ENEMY, Vector2(0, 16))
	var wizard: Node2D = _spawn_unit("res://scripts/resources/units/wizard.tres", PLAYER, Vector2(-80, 16))
	var before: int = pigeon.get("hp")
	pigeon.call("take_damage", 38, wizard)
	assert_eq(pigeon.get("hp"), before - 38, "wizard damage lands on pigeon")


func test_pigeon_damaged_by_dragon() -> void:
	var pigeon: Node2D = _spawn_unit("res://scripts/resources/units/pigeon.tres", ENEMY, Vector2(0, 16))
	var dragon: Node2D = _spawn_unit("res://scripts/resources/units/dragon.tres", PLAYER, Vector2(-80, 16))
	var before: int = pigeon.get("hp")
	pigeon.call("take_damage", 45, dragon)
	assert_eq(pigeon.get("hp"), before - 45, "dragon damage lands on pigeon")


func test_pigeon_immune_to_swordsman() -> void:
	var pigeon: Node2D = _spawn_unit("res://scripts/resources/units/pigeon.tres", ENEMY, Vector2(0, 16))
	var swordsman: Node2D = _spawn_unit("res://scripts/resources/units/swordsman.tres", PLAYER, Vector2(-40, 16))
	var before: int = pigeon.get("hp")
	pigeon.call("take_damage", 50, swordsman)
	assert_eq(pigeon.get("hp"), before, "swordsman cannot damage pigeon")


func test_pigeon_immune_to_miner() -> void:
	var pigeon: Node2D = _spawn_unit("res://scripts/resources/units/pigeon.tres", ENEMY, Vector2(0, 16))
	var miner: Node2D = _spawn_unit("res://scripts/resources/units/miner.tres", PLAYER, Vector2(-40, 16))
	var before: int = pigeon.get("hp")
	pigeon.call("take_damage", 50, miner)
	assert_eq(pigeon.get("hp"), before, "miner cannot damage pigeon")


func test_pigeon_immune_to_null_attacker() -> void:
	var pigeon: Node2D = _spawn_unit("res://scripts/resources/units/pigeon.tres", ENEMY, Vector2(0, 16))
	var before: int = pigeon.get("hp")
	pigeon.call("take_damage", 50, null)
	assert_eq(pigeon.get("hp"), before, "null attacker cannot damage pigeon")


func test_swordsman_auto_attack_skips_pigeon() -> void:
	_grid.set_reveal_all(PLAYER, true)
	var pigeon: Node2D = _spawn_unit("res://scripts/resources/units/pigeon.tres", ENEMY, Vector2(40, 16))
	var swordsman: Node2D = _spawn_unit("res://scripts/resources/units/swordsman.tres", PLAYER, Vector2(0, 16))
	assert_false(swordsman.call("can_damage_unit", pigeon))
	var target = swordsman.call("_find_auto_attack_target")
	assert_true(target == null or target != pigeon, "swordsman auto-attack must skip immune pigeon")
	_grid.set_reveal_all(PLAYER, false)


func test_archer_can_damage_and_target_pigeon() -> void:
	_grid.set_reveal_all(PLAYER, true)
	var pigeon: Node2D = _spawn_unit("res://scripts/resources/units/pigeon.tres", ENEMY, Vector2(40, 16))
	var archer: Node2D = _spawn_unit("res://scripts/resources/units/archer.tres", PLAYER, Vector2(0, 16))
	assert_true(archer.call("can_damage_unit", pigeon))
	assert_true(pigeon.call("can_be_damaged_by", archer))
	_grid.set_reveal_all(PLAYER, false)


func test_tower_can_damage_pigeon() -> void:
	var pigeon: Node2D = _spawn_unit("res://scripts/resources/units/pigeon.tres", ENEMY, Vector2(0, 16))
	var tower: Node2D = _spawn_tower(PLAYER, Vector2(-80, 16))
	assert_true(pigeon.call("can_be_damaged_by", tower), "pigeon can be damaged by tower")
	var before: int = pigeon.get("hp")
	pigeon.call("take_damage", 12, tower)
	assert_eq(pigeon.get("hp"), before - 12, "tower damage lands on pigeon")


func test_tower_targets_pigeon_first() -> void:
	_grid.set_reveal_all(PLAYER, true)
	var tower: Node2D = _spawn_tower(PLAYER, Vector2(0, 16))
	var pigeon: Node2D = _spawn_unit("res://scripts/resources/units/pigeon.tres", ENEMY, Vector2(60, 16))
	var swordsman: Node2D = _spawn_unit("res://scripts/resources/units/swordsman.tres", ENEMY, Vector2(40, 16))
	var target = tower.call("_pick_target")
	assert_eq(target, pigeon, "tower prioritizes pigeon over enemy fighter")
	_grid.set_reveal_all(PLAYER, false)


func test_tower_can_queue_pigeon() -> void:
	EconomyManager.reset()
	EconomyManager.add_coin(PLAYER, 100)
	var tower: Node2D = _spawn_tower(PLAYER, Vector2(0, 16))
	assert_true(tower.call("queue_pigeon"), "tower accepts pigeon train order")
	assert_eq(tower.call("get_pigeon_queue_count"), 1, "one pigeon queued")


func test_tower_pigeon_cap_counts_queued() -> void:
	EconomyManager.reset()
	EconomyManager.add_coin(PLAYER, 300)
	var tower_a: Node2D = _spawn_tower(PLAYER, Vector2(-100, 16))
	var tower_b: Node2D = _spawn_tower(PLAYER, Vector2(100, 16))
	assert_true(tower_a.call("queue_pigeon"), "first pigeon queued at tower A")
	assert_true(tower_a.call("queue_pigeon"), "second pigeon queued at tower A")
	assert_false(tower_b.call("queue_pigeon"), "tower B cannot exceed global pigeon cap")
