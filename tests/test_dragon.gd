extends GutTest

# Dragon fighter: archer/wizard can damage it; swordsman/miner/dragon cannot.
# Auto-attack skips immune targets so melee units don't lock onto dragons.

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


func after_all() -> void:
	_main.free()


func _spawn_unit(tres_path: String, team: int, pos: Vector2) -> Node2D:
	var unit: Node2D = load("res://scenes/unit.tscn").instantiate()
	unit.set("data", load(tres_path).duplicate(true))
	unit.set("team", team)
	unit.position = pos
	_units.add_child(unit)
	autofree(unit)
	return unit


func test_dragon_damaged_by_archer() -> void:
	var dragon: Node2D = _spawn_unit("res://scripts/resources/units/dragon.tres", ENEMY, Vector2(0, 16))
	var archer: Node2D = _spawn_unit("res://scripts/resources/units/archer.tres", PLAYER, Vector2(-80, 16))
	var before: int = dragon.get("hp")
	dragon.call("take_damage", 12, archer)
	assert_eq(dragon.get("hp"), before - 12, "archer damage lands on dragon")


func test_dragon_damaged_by_wizard() -> void:
	var dragon: Node2D = _spawn_unit("res://scripts/resources/units/dragon.tres", ENEMY, Vector2(0, 16))
	var wizard: Node2D = _spawn_unit("res://scripts/resources/units/wizard.tres", PLAYER, Vector2(-80, 16))
	var before: int = dragon.get("hp")
	dragon.call("take_damage", 38, wizard)
	assert_eq(dragon.get("hp"), before - 38, "wizard damage lands on dragon")


func test_dragon_immune_to_swordsman() -> void:
	var dragon: Node2D = _spawn_unit("res://scripts/resources/units/dragon.tres", ENEMY, Vector2(0, 16))
	var swordsman: Node2D = _spawn_unit("res://scripts/resources/units/swordsman.tres", PLAYER, Vector2(-40, 16))
	var before: int = dragon.get("hp")
	dragon.call("take_damage", 50, swordsman)
	assert_eq(dragon.get("hp"), before, "swordsman cannot damage dragon")


func test_dragon_immune_to_miner() -> void:
	var dragon: Node2D = _spawn_unit("res://scripts/resources/units/dragon.tres", ENEMY, Vector2(0, 16))
	var miner: Node2D = _spawn_unit("res://scripts/resources/units/miner.tres", PLAYER, Vector2(-40, 16))
	var before: int = dragon.get("hp")
	dragon.call("take_damage", 50, miner)
	assert_eq(dragon.get("hp"), before, "miner cannot damage dragon")


func test_dragon_immune_to_dragon() -> void:
	var target: Node2D = _spawn_unit("res://scripts/resources/units/dragon.tres", ENEMY, Vector2(0, 16))
	var attacker: Node2D = _spawn_unit("res://scripts/resources/units/dragon.tres", PLAYER, Vector2(-80, 16))
	var before: int = target.get("hp")
	target.call("take_damage", 45, attacker)
	assert_eq(target.get("hp"), before, "dragon cannot damage dragon")


func test_dragon_immune_to_null_attacker() -> void:
	var dragon: Node2D = _spawn_unit("res://scripts/resources/units/dragon.tres", ENEMY, Vector2(0, 16))
	var before: int = dragon.get("hp")
	dragon.call("take_damage", 50, null)
	assert_eq(dragon.get("hp"), before, "null attacker cannot damage dragon")


func test_swordsman_auto_attack_skips_dragon() -> void:
	var dragon: Node2D = _spawn_unit("res://scripts/resources/units/dragon.tres", ENEMY, Vector2(40, 16))
	var swordsman: Node2D = _spawn_unit("res://scripts/resources/units/swordsman.tres", PLAYER, Vector2(0, 16))
	assert_false(swordsman.call("can_damage_unit", dragon))
	var target = swordsman.call("_find_auto_attack_target")
	assert_true(target == null or target != dragon, "swordsman auto-attack must skip immune dragon")


func test_archer_can_damage_and_target_dragon() -> void:
	var dragon: Node2D = _spawn_unit("res://scripts/resources/units/dragon.tres", ENEMY, Vector2(40, 16))
	var archer: Node2D = _spawn_unit("res://scripts/resources/units/archer.tres", PLAYER, Vector2(0, 16))
	assert_true(archer.call("can_damage_unit", dragon))
	assert_true(dragon.call("can_be_damaged_by", archer))


func test_wizard_fireball_splash_damages_dragon() -> void:
	var dragon: Node2D = _spawn_unit("res://scripts/resources/units/dragon.tres", ENEMY, Vector2(0, 16))
	var wizard: Node2D = _spawn_unit("res://scripts/resources/units/wizard.tres", PLAYER, Vector2(-100, 16))
	var before: int = dragon.get("hp")
	var aim: Vector2 = dragon.call("get_combat_position")
	var proj: Node2D = load("res://scenes/projectile.tscn").instantiate()
	proj.set("team", PLAYER)
	proj.set("damage", 38)
	proj.set("is_fireball", true)
	proj.set("aoe_radius", 40.0)
	proj.set("source", wizard)
	proj.set("target_position", aim)
	proj.global_position = aim
	_main.get_node("Projectiles").add_child(proj)
	autofree(proj)
	proj.call("_impact")
	assert_eq(dragon.get("hp"), before - 38, "wizard fireball splash damages dragon via source")


func test_attack_unit_rejects_immune_target() -> void:
	var dragon: Node2D = _spawn_unit("res://scripts/resources/units/dragon.tres", ENEMY, Vector2(80, 16))
	var swordsman: Node2D = _spawn_unit("res://scripts/resources/units/swordsman.tres", PLAYER, Vector2(0, 16))
	swordsman.call("attack_unit", dragon)
	assert_ne(swordsman.get("_state"), 2, "ATTACK state must be rejected vs immune dragon")  # State.ATTACK == 2


func test_building_can_queue_dragon() -> void:
	EconomyManager.reset()
	EconomyManager.add_coin(PLAYER, 400)
	var building: Node2D = null
	for b in get_tree().get_nodes_in_group("buildings"):
		if b.get("team") == PLAYER:
			building = b
			break
	assert_not_null(building)
	assert_true(building.call("queue_unit", "dragon"), "building accepts dragon train id")


func test_dragon_combat_position_surface_altitude() -> void:
	var dragon: Node2D = _spawn_unit("res://scripts/resources/units/dragon.tres", ENEMY, Vector2(0, 16))
	dragon.set("is_underground", false)
	var combat: Vector2 = dragon.call("get_combat_position")
	assert_eq(combat.x, dragon.global_position.x)
	assert_eq(combat.y, dragon.global_position.y - 40.0, "surface dragon combat pos is 40px above feet")


func test_dragon_combat_position_underground_no_altitude() -> void:
	var dragon: Node2D = _spawn_unit("res://scripts/resources/units/dragon.tres", ENEMY, Vector2(0, 80))
	dragon.set("is_underground", true)
	var combat: Vector2 = dragon.call("get_combat_position")
	assert_eq(combat, dragon.global_position, "underground dragon combat pos equals feet")


func test_archer_air_range_euclidean_gate() -> void:
	# Archer range 150, dragon altitude 40 → max ground reach ≈ 144.6.
	var archer: Node2D = _spawn_unit("res://scripts/resources/units/archer.tres", PLAYER, Vector2(0, 16))
	var far_dragon: Node2D = _spawn_unit("res://scripts/resources/units/dragon.tres", ENEMY, Vector2(147, 16))
	var near_dragon: Node2D = _spawn_unit("res://scripts/resources/units/dragon.tres", ENEMY, Vector2(140, 16))
	var range_sq: float = archer.data.attack_range * archer.data.attack_range
	assert_gt(archer.call("combat_distance_squared_to", far_dragon), range_sq, "147px ground gap fails Euclidean air range")
	assert_lt(archer.call("combat_distance_squared_to", near_dragon), range_sq, "140px ground gap is in air range")


func test_projectile_homes_to_dragon_combat_position() -> void:
	var dragon: Node2D = _spawn_unit("res://scripts/resources/units/dragon.tres", ENEMY, Vector2(0, 16))
	dragon.set("is_underground", false)
	var proj: Node2D = load("res://scenes/projectile.tscn").instantiate()
	proj.set("homing_target", dragon)
	proj.global_position = Vector2(-100, 16)
	_main.get_node("Projectiles").add_child(proj)
	autofree(proj)
	proj.call("_update_target_position")
	var combat: Vector2 = dragon.call("get_combat_position")
	assert_eq(proj.get("target_position"), combat, "homing aims at dragon combat position")


func test_filter_dragons_selects_only_dragons() -> void:
	var dragon: Node2D = _spawn_unit("res://scripts/resources/units/dragon.tres", PLAYER, Vector2(-40, 16))
	var archer: Node2D = _spawn_unit("res://scripts/resources/units/archer.tres", PLAYER, Vector2(-80, 16))
	var controller: Node = _main.get_node("PlayerController")
	var filtered: Array = controller.call("_filter_dragons", [dragon, archer])
	assert_eq(filtered.size(), 1, "filter keeps only dragons")
	assert_eq(filtered[0], dragon)
