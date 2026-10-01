extends GutTest

# Control groups: Ctrl+1-9 snapshots the current selection under a digit,
# Alt+1-9 recalls it (dead units are filtered out on recall). Digits 1-8 are
# training hotkeys, so recall uses Alt, and the raw-key check runs before the
# InputMap action chain so Ctrl+digit can't fall through to train_*.

const PLAYER: int = 0

var _main: Node
var _pc: Node
var _units: Node
var _building: Node2D
var _fighters: Array = []


func before_all() -> void:
	seed(12345)
	# Pin the map so the layout is deterministic across runs.
	GameManager.set_map_seed(12345)
	_main = load("res://scenes/main.tscn").instantiate()
	get_tree().root.add_child(_main)
	get_tree().current_scene = _main
	_pc = _main.get_node("PlayerController")
	_units = _main.get_node("Units")
	for b in get_tree().get_nodes_in_group("buildings"):
		if b.get("team") == PLAYER:
			_building = b
	for i in range(3):
		_fighters.append(_spawn_unit(Vector2(-480 + i * 24, 16)))


func after_all() -> void:
	# Free immediately, not queue_free(): a queued free can race the next
	# script's main.tscn boot and break /root/Main lookups.
	_main.free()
	GameManager.clear_map_seed()


func after_each() -> void:
	_pc._control_groups.clear()
	_pc._select_units([])


func _spawn_unit(pos: Vector2) -> Node2D:
	var unit: Node2D = load("res://scenes/unit.tscn").instantiate()
	unit.set("data", load("res://scripts/resources/units/swordsman.tres").duplicate(true))
	unit.set("team", PLAYER)
	unit.position = pos
	_units.add_child(unit)
	# No autofree(): units spawned in before_all belong to the scene and are
	# freed wholesale by _main.free() in after_all — autofree would free them
	# after the FIRST test, leaving dangling refs (and hard crashes) later.
	EconomyManager.add_population(PLAYER, 1)
	return unit


func _key_event(keycode: int, ctrl := false, alt := false) -> InputEventKey:
	var event := InputEventKey.new()
	event.keycode = keycode
	event.pressed = true
	event.ctrl_pressed = ctrl
	event.alt_pressed = alt
	return event


func test_assign_and_recall_round_trip() -> void:
	_pc._select_units([_fighters[0], _fighters[1]])
	_pc._unhandled_input(_key_event(KEY_2, true, false))
	assert_eq(_pc._control_groups[2].size(), 2, "Ctrl+2 snapshots the selection")
	_pc._select_units([_fighters[2]])
	_pc._unhandled_input(_key_event(KEY_2, false, true))
	assert_eq(_pc.get_selected_units(), [_fighters[0], _fighters[1]], "Alt+2 recalls the group")
	assert_true(_fighters[0].selected, "recalled unit shows its ring")
	assert_false(_fighters[2].selected, "the previous selection is replaced")


func test_recall_filters_dead_units() -> void:
	_pc._select_units([_fighters[0], _fighters[1]])
	_pc._unhandled_input(_key_event(KEY_1, true, false))
	_fighters[1].kill()
	# Dead units free their node after the 1s death fade; until then the
	# instance is still valid (recall drops them via is_instance_valid).
	await wait_seconds(1.2)
	assert_false(is_instance_valid(_fighters[1]), "killed unit's node is freed")
	_pc._select_units([_fighters[2]])
	_pc._unhandled_input(_key_event(KEY_1, false, true))
	assert_eq(_pc.get_selected_units(), [_fighters[0]], "dead units are dropped from the recall")


func test_recall_missing_group_selects_nothing() -> void:
	_pc._select_units([_fighters[0]])
	_pc._unhandled_input(_key_event(KEY_5, false, true))
	assert_eq(_pc.get_selected_units().size(), 0, "recalling an unassigned group selects nothing")


func test_ctrl_digit_does_not_trigger_train_hotkey() -> void:
	# Without the control-group guard, Ctrl+1 would match the train_miner
	# action (InputMap matching is not modifier-exact) and enqueue a miner.
	var queued_before: int = _building._queue.size()
	_pc._unhandled_input(_key_event(KEY_1, true, false))
	assert_eq(_building._queue.size(), queued_before, "Ctrl+1 assigns a group instead of training")
	assert_eq(_pc._control_groups[1].size(), 0, "assigning an empty selection is still a snapshot")


func test_echo_repeat_is_ignored() -> void:
	# Key-repeat events (held key) must not re-trigger assign/recall.
	_pc._select_units([_fighters[0]])
	var event := _key_event(KEY_1, true, false)
	event.echo = true
	_pc._unhandled_input(event)
	assert_false(_pc._control_groups.has(1), "echo events do not assign a group")
	_pc._control_groups[4] = [_fighters[0]]
	var echo_recall := _key_event(KEY_4, false, true)
	echo_recall.echo = true
	_pc._select_units([])
	_pc._unhandled_input(echo_recall)
	assert_eq(_pc.get_selected_units().size(), 0, "echo events do not recall a group")
