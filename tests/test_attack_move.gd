extends GutTest

# Attack-move: Q arms the order (fighter selection required), the next
# left-click sends every selected fighter attack-moving to the point (engaging
# anything in auto-attack range on the way, surface or underground), and
# right-click/Esc cancels. Any later explicit order (e.g. move_to) clears the
# attack-move flag through _clear_target.

const PLAYER: int = 0

var _main: Node
var _pc: Node
var _units: Node
var _fighter: Node2D
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
	# Fog of War: make the player's vision deterministic for the engagement test.
	_main.get_node("World/GridWorld").set_reveal_all(GameManager.Team.PLAYER, true)
	_fighter = _spawn_unit("res://scripts/resources/units/swordsman.tres", Vector2(-480, 16))
	_miner = _spawn_unit("res://scripts/resources/units/miner.tres", Vector2(-520, 16))


func after_all() -> void:
	# Free immediately, not queue_free(): a queued free can race the next
	# script's main.tscn boot and break /root/Main lookups.
	_main.free()
	GameManager.clear_map_seed()


func after_each() -> void:
	_pc._attack_move_armed = false
	_pc._select_units([])
	_fighter.stop()
	_miner.stop()


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


func _lmb_event(screen_pos: Vector2) -> InputEventMouseButton:
	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = true
	event.position = screen_pos
	return event


func _rmb_event() -> InputEventMouseButton:
	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_RIGHT
	event.pressed = true
	return event


func test_q_arms_attack_move_with_fighter_selected() -> void:
	_pc._select_units([_fighter])
	_pc._unhandled_input(_key_event(KEY_Q))
	assert_true(_pc._attack_move_armed, "Q arms attack-move when a fighter is selected")


func test_q_ignored_without_fighters() -> void:
	_pc._select_units([])
	_pc._unhandled_input(_key_event(KEY_Q))
	assert_false(_pc._attack_move_armed, "no selection: Q does nothing")
	_pc._select_units([_miner])
	_pc._unhandled_input(_key_event(KEY_Q))
	assert_false(_pc._attack_move_armed, "miner-only selection: Q does nothing")


func test_armed_left_click_issues_attack_move() -> void:
	_pc._select_units([_fighter])
	_pc._unhandled_input(_key_event(KEY_Q))
	# Pick the world destination first, then compute the matching screen
	# position through the live canvas transform (camera zoom/scroll included).
	var target_world := Vector2(-420, 16)
	var click: Vector2 = _pc.get_viewport().get_canvas_transform() * target_world
	_pc._unhandled_input(_lmb_event(click))
	assert_false(_pc._attack_move_armed, "the click disarms the order")
	assert_true(_fighter.get("_attack_move_active"), "fighter is attack-moving")
	assert_true(_fighter.get("_attack_move_point").distance_to(target_world) < 0.5, "attack-move point is the clicked world position")
	assert_eq(_fighter.get("_state"), _fighter.State.MOVE, "attack-move paths toward the point")


func test_armed_right_click_cancels() -> void:
	_pc._select_units([_fighter])
	_pc._unhandled_input(_key_event(KEY_Q))
	_pc._unhandled_input(_rmb_event())
	assert_false(_pc._attack_move_armed, "right-click cancels the armed order")
	assert_false(_fighter.get("_attack_move_active"), "no order was issued")


func test_armed_swallows_other_input() -> void:
	_pc._select_units([_fighter])
	_pc._unhandled_input(_key_event(KEY_Q))
	# While armed, the train hotkeys must not fire (event is swallowed).
	var building: Node2D = null
	for b in get_tree().get_nodes_in_group("buildings"):
		if b.get("team") == PLAYER:
			building = b
	var queued_before: int = building._queue.size()
	_pc._unhandled_input(_key_event(KEY_1))
	assert_eq(building._queue.size(), queued_before, "digits are swallowed while attack-move is armed")
	assert_true(_pc._attack_move_armed, "still armed after the swallowed key")


func test_plain_move_clears_attack_move() -> void:
	_pc._select_units([_fighter])
	_fighter.attack_move_to(Vector2(-420, 16))
	assert_true(_fighter.get("_attack_move_active"), "attack-move is active")
	_fighter.move_to(Vector2(-400, 16))
	assert_false(_fighter.get("_attack_move_active"), "a plain move order ends the attack-move")
	assert_eq(_fighter.get("_attack_move_point"), Vector2.ZERO, "attack-move point is reset")


func test_attack_move_engages_target_and_resumes() -> void:
	# An enemy in range is engaged (state ATTACK) while the attack-move flag
	# survives the engagement, and once idle again the fighter heads for the
	# point instead of its standing post.
	var enemy: Node2D = _spawn_unit("res://scripts/resources/units/swordsman.tres", Vector2(-440, 16))
	enemy.set("team", GameManager.Team.ENEMY)
	enemy.add_to_group("enemy")
	EconomyManager.add_population(GameManager.Team.ENEMY, 1)
	_fighter.attack_move_to(Vector2(-300, 16))
	assert_true(_fighter._idle._engage_attack_move_target_if_any(), "enemy in range is engaged on the way")
	assert_eq(_fighter.get("_state"), _fighter.State.ATTACK, "engagement enters ATTACK")
	assert_true(_fighter.get("_attack_move_active"), "engagement keeps the attack-move order")
	assert_true(_fighter.get("_auto_engaged"), "engagement is marked as auto (not an explicit order)")
	_fighter._target_unit = null
	_fighter._set_state(_fighter.State.IDLE, "test reset")
	# Walk the enemy out of range so the idle tick resumes the path instead of
	# re-engaging.
	enemy.global_position = Vector2(480, 16)
	_fighter._idle._handle_attack_move_idle()
	assert_eq(_fighter.get("_state"), _fighter.State.MOVE, "idle resumes the path toward the attack-move point")
	assert_eq(_fighter.get("_target_position"), Vector2(-300, 16), "resumes toward the point, not the standing post")
	enemy.kill()
