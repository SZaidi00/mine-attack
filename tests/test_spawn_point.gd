extends GutTest

# Building spawn point (plan 15): a surface cell the player picks from the
# HUD becomes the muster destination for newly trained fighters/engineers.
# Miners and crawlers always keep their auto-descend into the mine; an
# explicit stance order (attack/garrison) still overrides the point; an
# underground click is rejected. Uses the real main scene so the building,
# queue, and controller wiring are intact.

const PLAYER: int = 0

var _main: Node
var _building: Node2D
var _controller: PlayerController
var _grid: GridWorld


func before_all() -> void:
	seed(12345)
	_main = load("res://scenes/main.tscn").instantiate()
	get_tree().root.add_child(_main)
	get_tree().current_scene = _main
	_grid = _main.get_node("World/GridWorld")
	_controller = _main.get_node("PlayerController")
	for b in get_tree().get_nodes_in_group("buildings"):
		if b.get("team") == PLAYER:
			_building = b


func after_all() -> void:
	# Free immediately: a queued free can still be pending when the next test
	# script instantiates its own main.tscn — the old "Main" name would still
	# be taken and every hard-coded /root/Main lookup would break.
	_main.free()


func before_each() -> void:
	_controller.set_stance("defend")  # stop any fighters leftover from a previous test
	_building.call("clear_spawn_point")
	EconomyManager.reset()


## A surface cell a few cells in front of the building's footprint on row 0
## (row 0 in front of each base is guaranteed walkable).
func _front_dest() -> Vector2:
	var building_cell: Vector2i = _grid.world_to_grid(_building.global_position)
	return _grid.grid_to_world(Vector2i(building_cell.x + 4, 0))


func _queue_fast(unit_id: String) -> Array:
	var spawned: Array = []
	_building.unit_spawned.connect(func(u: Node2D) -> void: spawned.append(u))
	assert_true(_building.call("queue_unit", unit_id))
	# Test shortcut: collapse the train time so the suite stays fast; queue
	# mechanics themselves are covered by test_building_queue.gd.
	var queue: Array = _building.call("get_queue")
	queue[0]["remaining"] = 0.05
	return spawned


func test_defaults_to_no_spawn_point() -> void:
	assert_false(_building.call("has_spawn_point"))


func test_underground_click_rejected() -> void:
	var underground: Vector2 = _grid.grid_to_world(Vector2i(0, 3))
	_controller._commands._set_spawn_point_at(underground)
	assert_false(_building.call("has_spawn_point"), "an underground cell cannot become the spawn point")


func test_fighter_moves_to_spawn_point() -> void:
	var dest: Vector2 = _front_dest()
	_building.call("set_spawn_point", dest)
	assert_true(_building.call("has_spawn_point"))
	assert_eq(_building.call("get_spawn_point"), dest)
	var spawned: Array = _queue_fast("swordsman")
	var arrived := false
	for i in range(240):
		await wait_seconds(0.05)
		if spawned.size() > 0 and is_instance_valid(spawned[0]) \
				and spawned[0].global_position.distance_to(dest) < GridWorld.CELL_SIZE * 1.5:
			arrived = true
			break
	assert_true(arrived, "the freshly trained swordsman walks to the spawn point")


func test_miner_keeps_entering_mine() -> void:
	_building.call("set_spawn_point", _front_dest())
	var spawned: Array = _queue_fast("miner")
	await wait_seconds(1.0)
	assert_eq(spawned.size(), 1, "the miner spawned")
	assert_eq(spawned[0].get("_state"), Unit.State.CLIMB_DOWN,
		"the miner heads for the shaft, not the spawn point")


func test_attack_stance_overrides_spawn_point() -> void:
	_building.call("set_spawn_point", _front_dest())
	_controller.set_stance("attack")
	var spawned: Array = _queue_fast("swordsman")
	var charging := false
	for i in range(240):
		await wait_seconds(0.05)
		if spawned.size() > 0 and is_instance_valid(spawned[0]):
			var u: Node2D = spawned[0]
			if u.get("_state") == Unit.State.ATTACK and u.get("_target_building") != null:
				charging = true
				break
	assert_true(charging, "attack stance sends the fresh fighter at the enemy building instead")
	assert_true(_building.call("has_spawn_point"), "the spawn point itself survives the stance order")
