extends GutTest

# Formations: a plain (non-queued) move or attack-move order to 3+ fighters
# spreads the destinations by the current mode — "line" perpendicular to the
# travel direction, "column" single file, "spread" a shallow 3-column grid
# (F cycles the modes). Offsets are one cell apart and snapped to walkable
# spots. Miners/engineers always get the exact click; <3 fighters and queued
# (Shift) orders skip formations entirely.

const PLAYER: int = 0

var _main: Node
var _pc: Node
var _units: Node
var _hud: Node
var _fighters: Array = []
var _miner: Node2D


func before_all() -> void:
	seed(12345)
	# Pin the map so the layout is deterministic across runs.
	GameManager.set_map_seed(12345)
	_main = load("res://scenes/main.tscn").instantiate()
	get_tree().root.add_child(_main)
	get_tree().current_scene = _main
	_pc = _main.get_node("PlayerController")
	_units = _main.get_node("Units")
	_hud = _main.get_node("UI/HUD")
	for i in range(3):
		_fighters.append(_spawn_unit("res://scripts/resources/units/swordsman.tres", Vector2(-640 + i * 24, 16)))
	_miner = _spawn_unit("res://scripts/resources/units/miner.tres", Vector2(-700, 16))


func after_all() -> void:
	# Free immediately, not queue_free(): a queued free can race the next
	# script's main.tscn boot and break /root/Main lookups.
	_main.free()
	GameManager.clear_map_seed()


func after_each() -> void:
	_pc._select_units([])
	_pc._formation_mode = "line"
	for u in _fighters:
		u.stop()
	_miner.stop()
	_miner.is_underground = false


func _spawn_unit(tres_path: String, pos: Vector2) -> Node2D:
	var unit: Node2D = load("res://scenes/unit.tscn").instantiate()
	unit.set("data", load(tres_path).duplicate(true))
	unit.set("team", PLAYER)
	unit.position = pos
	_units.add_child(unit)
	# No autofree(): units spawned in before_all belong to the scene and are
	# freed wholesale by _main.free() in after_all — autofree would free them
	# after the FIRST test, leaving dangling refs (and hard crashes) later.
	EconomyManager.add_population(PLAYER, 1)
	return unit


func _key_event(keycode: int) -> InputEventKey:
	var event := InputEventKey.new()
	event.keycode = keycode
	event.pressed = true
	return event


func _screen(world: Vector2) -> Vector2:
	return _pc.get_viewport().get_canvas_transform() * world


func _fighter_targets() -> Array:
	var targets: Array = []
	for u in _fighters:
		targets.append(u.get("_target_position"))
	return targets


func _count_distinct(points: Array) -> int:
	var distinct: Array = []
	for p in points:
		if not distinct.has(p):
			distinct.append(p)
	return distinct.size()


func test_cycle_formation_action_registered() -> void:
	assert_eq(Constants.INPUT_CYCLE_FORMATION, &"cycle_formation", "constant names the action")
	assert_true(InputMap.has_action("cycle_formation"), "input action exists in the InputMap")
	var found: bool = false
	for entry in Constants.REMAPPABLE_ACTIONS:
		if entry["action"] == "cycle_formation":
			found = true
	assert_true(found, "REMAPPABLE_ACTIONS entry makes it appear in the settings panel")


func test_f_key_cycles_line_column_spread() -> void:
	assert_eq(_pc.get_formation_mode(), "line", "default formation is line")
	_pc._unhandled_input(_key_event(KEY_F))
	assert_eq(_pc.get_formation_mode(), "column", "F: line -> column")
	_pc._unhandled_input(_key_event(KEY_F))
	assert_eq(_pc.get_formation_mode(), "spread", "F: column -> spread")
	_pc._unhandled_input(_key_event(KEY_F))
	assert_eq(_pc.get_formation_mode(), "line", "F: spread -> line")


func test_f_key_shows_hud_readout() -> void:
	_pc._unhandled_input(_key_event(KEY_F))
	assert_true(_hud._formation_label.visible, "the readout appears on change")
	assert_eq(_hud._formation_label.text, "Formation: Column", "the readout names the new mode")


func test_line_formation_spreads_three_fighters() -> void:
	_pc._select_units(_fighters.duplicate())
	var click := Vector2(-400, 16)
	_pc._commands._issue_command(_screen(click), false)
	var targets: Array = _fighter_targets()
	assert_eq(_count_distinct(targets), 3, "each fighter gets its own destination")
	assert_true(targets.has(click), "the line is centred on the click")
	for t in targets:
		assert_true(_fighters[0]._is_walkable_point(t), "destinations are walkable")


func test_column_formation_single_file() -> void:
	_pc._formation_mode = "column"
	_pc._select_units(_fighters.duplicate())
	var click := Vector2(-400, 16)
	_pc._commands._issue_command(_screen(click), false)
	var targets: Array = _fighter_targets()
	assert_eq(_count_distinct(targets), 3, "single file: one slot per fighter")
	assert_true(targets.has(click), "the lead fighter takes the click")


func test_spread_formation_distinct_slots() -> void:
	_pc._formation_mode = "spread"
	_pc._select_units(_fighters.duplicate())
	var click := Vector2(-400, 16)
	_pc._commands._issue_command(_screen(click), false)
	var targets: Array = _fighter_targets()
	assert_eq(_count_distinct(targets), 3, "each fighter gets its own destination")
	assert_true(targets.has(click), "the front rank sits on the click")


func test_non_fighters_keep_exact_click_point() -> void:
	_pc._select_units(_fighters.duplicate() + [_miner])
	var click := Vector2(-400, 16)
	_pc._commands._issue_command(_screen(click), false)
	assert_true(_miner.get("_target_position").distance_to(click) < 0.5, "the miner goes to the exact click")
	assert_eq(_count_distinct(_fighter_targets()), 3, "the fighters still form up")


func test_two_fighters_skip_formation() -> void:
	_pc._select_units([_fighters[0], _fighters[1]])
	var click := Vector2(-400, 16)
	_pc._commands._issue_command(_screen(click), false)
	assert_true(_fighters[0].get("_target_position").distance_to(click) < 0.5, "fighter 1 takes the click")
	assert_true(_fighters[1].get("_target_position").distance_to(click) < 0.5, "fighter 2 takes the click")


func test_shift_queued_move_skips_formation() -> void:
	_pc._select_units(_fighters.duplicate())
	var click := Vector2(-400, 16)
	_pc._commands._issue_command(_screen(click), true)
	for u in _fighters:
		assert_eq(u.get_order_queue().size(), 1, "the order is queued, not issued")
		assert_eq(u.get_order_queue()[0]["type"], "move", "a move waypoint")
		assert_true(u.get_order_queue()[0]["pos"].distance_to(click) < 0.5, "queued waypoints keep the exact click")


func test_attack_move_uses_formation() -> void:
	_pc._select_units(_fighters.duplicate())
	var click := Vector2(-400, 16)
	_pc._commands.attack_move_order(_screen(click))
	var points: Array = []
	for u in _fighters:
		points.append(u.get("_attack_move_point"))
	assert_eq(_count_distinct(points), 3, "attack-move destinations spread by formation")
	assert_true(points.has(click), "a slot sits on the click")
