extends GutTest

# Building training queue: FIFO order, uncapped length, cancel refunds.
# Uses the real main scene so the building/grid wiring is intact.

const PLAYER: int = 0

var _main: Node
var _building: Node2D


func before_all() -> void:
	_main = load("res://scenes/main.tscn").instantiate()
	get_tree().root.add_child(_main)
	get_tree().current_scene = _main
	for b in get_tree().get_nodes_in_group("buildings"):
		if b.get("team") == PLAYER:
			_building = b


func after_all() -> void:
	_main.queue_free()


func before_each() -> void:
	# Drain any leftover queue first (refunds land in the old balance),
	# then reset so every test starts from a clean 500.
	while _building.call("cancel_queue", 0):
		pass
	EconomyManager.reset()


func test_queue_fifo_order() -> void:
	assert_true(_building.call("queue_unit", "miner"))
	assert_true(_building.call("queue_unit", "swordsman"))
	var queue: Array = _building.call("get_queue")
	assert_eq(queue.size(), 2)
	assert_eq(queue[0].id, "miner", "first queued trains first")
	assert_eq(queue[1].id, "swordsman")
	await wait_seconds(3.5)
	queue = _building.call("get_queue")
	assert_eq(queue.size(), 1, "miner (3s) should be done")
	assert_eq(queue[0].id, "swordsman", "swordsman is next in line")


func test_queue_accepts_more_than_five() -> void:
	# The queue is uncapped — only coin and population limit it.
	for i in range(8):
		assert_true(_building.call("queue_unit", "miner"), "queue slot %d" % i)
	assert_eq(_building.call("get_queue").size(), 8)
	assert_eq(EconomyManager.get_coin(PLAYER), 500 - 8 * 50, "every entry spends")


func test_cancel_queued_refunds_full_cost() -> void:
	_building.call("queue_unit", "miner")
	_building.call("queue_unit", "swordsman")
	var before: int = EconomyManager.get_coin(PLAYER)
	assert_true(_building.call("cancel_queue", 1))
	assert_eq(EconomyManager.get_coin(PLAYER), before + 100, "100% refund")
	assert_eq(_building.call("get_queue").size(), 1)


func test_cancel_in_progress_refunds_full_cost() -> void:
	_building.call("queue_unit", "wizard")
	var before: int = EconomyManager.get_coin(PLAYER)
	assert_true(_building.call("cancel_queue", 0))
	assert_eq(EconomyManager.get_coin(PLAYER), before + 250, "in-progress cancel refunds 100%")
	assert_eq(_building.call("get_queue").size(), 0)


func test_cancel_invalid_index_rejected() -> void:
	assert_false(_building.call("cancel_queue", 0), "empty queue")
	_building.call("queue_unit", "miner")
	assert_false(_building.call("cancel_queue", 7), "out of range")
	assert_false(_building.call("cancel_queue", -1), "negative")


func test_queue_rejects_unaffordable() -> void:
	EconomyManager.spend_coin(PLAYER, 450)  # 50 left: miner OK, swordsman not
	assert_false(_building.call("queue_unit", "swordsman"))
	assert_true(_building.call("queue_unit", "miner"))
