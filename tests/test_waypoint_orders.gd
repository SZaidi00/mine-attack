extends GutTest

# Shift-queued waypoints: Shift+right-click appends a context order (move /
# attack unit / attack building / mine cell) to the unit's queue instead of
# replacing the current order. Queued orders execute one per IDLE tick, before
# any idle handler grabs the unit. Any plain explicit order, stop(), kill(),
# or _clear_target() drops the whole queue.
# NOTE: the player mine entry sits at (-480, 0) with a 64px pick radius, so
# right-click test points must stay at least ~80px away from it or the
# mine-entry branch (deposit/enter) wins over the move default.

const PLAYER: int = 0

var _main: Node
var _pc: Node
var _units: Node
var _grid: Node
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
	_grid = _main.get_node("World/GridWorld")
	# Fog of War: make the player's vision deterministic for the click tests.
	_grid.set_reveal_all(GameManager.Team.PLAYER, true)
	_fighter = _spawn_unit("res://scripts/resources/units/swordsman.tres", Vector2(-640, 16))
	_miner = _spawn_unit("res://scripts/resources/units/miner.tres", Vector2(-700, 16))


func after_all() -> void:
	# Free immediately, not queue_free(): a queued free can race the next
	# script's main.tscn boot and break /root/Main lookups.
	_main.free()
	GameManager.clear_map_seed()


func after_each() -> void:
	_pc._select_units([])
	_fighter.stop()
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


func _rmb_event(shift := false) -> InputEventMouseButton:
	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_RIGHT
	event.pressed = true
	event.shift_pressed = shift
	return event


func _screen(world: Vector2) -> Vector2:
	return _pc.get_viewport().get_canvas_transform() * world


func test_shift_rmb_queues_move_without_replacing_current_order() -> void:
	_pc._select_units([_fighter])
	_fighter.move_to(Vector2(-400, 16))
	assert_eq(_fighter.get("_state"), _fighter.State.MOVE, "plain order runs first")
	assert_eq(_fighter.get_order_queue().size(), 0, "plain order leaves the queue empty")
	# Shift+right-click appends behind the running order.
	_pc._commands._issue_command(_screen(Vector2(-360, 16)), true)
	assert_eq(_fighter.get_order_queue().size(), 1, "Shift+right-click appends one order")
	assert_eq(_fighter.get("_state"), _fighter.State.MOVE, "the running order is not replaced")
	assert_true(_fighter.get("_target_position").distance_to(Vector2(-400, 16)) < 0.5, \
			"the unit still heads for the first point")


func test_shift_parameter_queues_and_plain_parameter_clears() -> void:
	# The Shift state is threaded from the InputEvent in _unhandled_input;
	# headless warp_mouse is a no-op, so exercise the parameter path directly
	# (the derivation line itself is `event.shift_pressed` on the RMB event).
	_pc._select_units([_fighter])
	_pc._commands._issue_command(_screen(Vector2(-400, 16)), true)
	assert_eq(_fighter.get_order_queue().size(), 1, "shift=true queues the order")
	assert_eq(_fighter.get("_state"), _fighter.State.IDLE, "a queued order does not interrupt an idle unit yet")
	_pc._commands._issue_command(_screen(Vector2(-360, 16)), false)
	assert_eq(_fighter.get_order_queue().size(), 0, "shift=false drops the queue")
	assert_eq(_fighter.get("_state"), _fighter.State.MOVE, "plain order issues immediately")
	assert_true(_fighter.get("_target_position").distance_to(Vector2(-360, 16)) < 0.5, \
			"the plain order goes to the click point")


func test_queued_moves_execute_in_order() -> void:
	_fighter.stop()
	var point_b := Vector2(-400, 16)
	var point_c := Vector2(-360, 16)
	_fighter.queue_order({"type": "move", "pos": point_b})
	_fighter.queue_order({"type": "move", "pos": point_c})
	assert_eq(_fighter.get_order_queue().size(), 2, "two waypoints queued")
	# The IDLE hook pops the first order on the next process tick.
	await wait_seconds(0.2)
	assert_eq(_fighter.get_order_queue().size(), 1, "first waypoint popped")
	assert_eq(_fighter.get("_state"), _fighter.State.MOVE, "unit walks the first waypoint")
	assert_true(_fighter.get("_target_position").distance_to(point_b) < 0.5, "heading for B")
	# Teleport onto B and clear the now-stale path: the path completes, and the
	# second waypoint pops.
	_fighter.global_position = point_b
	_fighter._path.clear()
	await wait_seconds(0.5)
	assert_eq(_fighter.get_order_queue().size(), 0, "second waypoint popped")
	assert_true(_fighter.get("_target_position").distance_to(point_c) < 0.5, "heading for C")


func test_plain_rmb_clears_pending_queue() -> void:
	_pc._select_units([_fighter])
	_pc._commands._issue_command(_screen(Vector2(-400, 16)), true)
	_pc._commands._issue_command(_screen(Vector2(-360, 16)), true)
	assert_eq(_fighter.get_order_queue().size(), 2, "two orders queued")
	_pc._commands._issue_command(_screen(Vector2(-340, 16)), false)
	assert_eq(_fighter.get_order_queue().size(), 0, "plain right-click drops the queue")
	assert_true(_fighter.get("_target_position").distance_to(Vector2(-340, 16)) < 0.5, \
			"the plain order replaces everything")


func test_stop_clears_queue() -> void:
	_fighter.queue_order({"type": "move", "pos": Vector2(-400, 16)})
	assert_eq(_fighter.get_order_queue().size(), 1, "order queued")
	_fighter.stop()
	assert_eq(_fighter.get_order_queue().size(), 0, "stop() drops the queue")


func test_queued_attack_unit_executes_when_idle() -> void:
	var enemy: Node2D = _spawn_unit("res://scripts/resources/units/swordsman.tres", Vector2(-320, 16))
	enemy.set("team", GameManager.Team.ENEMY)
	enemy.add_to_group("enemy")
	EconomyManager.add_population(GameManager.Team.ENEMY, 1)
	_fighter.stop()
	_fighter.queue_order({"type": "attack_unit", "target": enemy})
	await wait_seconds(0.2)
	assert_eq(_fighter.get("_state"), _fighter.State.ATTACK, "queued attack executes on idle")
	assert_eq(_fighter.get("_target_unit"), enemy, "the queued target is engaged")
	enemy.kill()


func test_queued_attack_unit_with_dead_target_is_skipped() -> void:
	var enemy: Node2D = _spawn_unit("res://scripts/resources/units/swordsman.tres", Vector2(-320, 16))
	enemy.set("team", GameManager.Team.ENEMY)
	enemy.add_to_group("enemy")
	EconomyManager.add_population(GameManager.Team.ENEMY, 1)
	var point_c := Vector2(-400, 16)
	_fighter.stop()
	_fighter.queue_order({"type": "attack_unit", "target": enemy})
	_fighter.queue_order({"type": "move", "pos": point_c})
	enemy.kill()
	await wait_seconds(0.2)
	assert_eq(_fighter.get_order_queue().size(), 0, "stale attack is consumed, then the move runs")
	assert_true(_fighter.get("_target_position").distance_to(point_c) < 0.5, "falls through to the move")


func test_queued_attack_building_executes_when_idle() -> void:
	var enemy_building: Node2D = null
	for b in get_tree().get_nodes_in_group("buildings"):
		if b.get("team") != PLAYER:
			enemy_building = b
	_fighter.stop()
	_fighter.queue_order({"type": "attack_building", "target": enemy_building})
	await wait_seconds(0.2)
	assert_eq(_fighter.get("_state"), _fighter.State.ATTACK, "queued siege executes on idle")
	assert_eq(_fighter.get("_target_building"), enemy_building, "the queued building is engaged")
	_fighter.stop()


func test_queued_mine_cell_defers_until_underground() -> void:
	var entry: Node2D = null
	for e in get_tree().get_nodes_in_group("mine_entries"):
		if e.get("team") == PLAYER:
			entry = e
	var ug: Vector2 = entry.call("get_underground_position")
	var cell: Vector2i = _grid.world_to_grid(ug + Vector2(64, 0))
	# Force a surface state: the miner auto-climbs at spawn.
	_miner.global_position = Vector2(-700, 16)
	_miner.is_underground = false
	_miner.stop()
	_miner.queue_order({"type": "mine_cell", "cell": cell})
	await wait_seconds(0.2)
	assert_eq(_miner.get("_pending_mine_cell"), cell, "surface miner defers the dig until underground")
	assert_eq(_miner.get_order_queue().size(), 0, "the queued mine order was consumed")


func test_queued_mine_cell_underground_starts_digging() -> void:
	var entry: Node2D = null
	for e in get_tree().get_nodes_in_group("mine_entries"):
		if e.get("team") == PLAYER:
			entry = e
	var ug: Vector2 = entry.call("get_underground_position")
	var cell: Vector2i = _grid.world_to_grid(ug + Vector2(32, 0))
	_miner.stop()
	_miner.global_position = ug
	_miner.is_underground = true
	_miner.queue_order({"type": "mine_cell", "cell": cell})
	await wait_seconds(0.2)
	assert_eq(_miner.get_order_queue().size(), 0, "the queued mine order was consumed")
	assert_eq(_miner.get("_target_cell"), cell, "the miner digs the queued cell")
	assert_eq(_miner.get("_state"), _miner.State.MINE, "digging starts")
