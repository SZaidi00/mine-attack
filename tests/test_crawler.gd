extends GutTest

# Crawler unit: underground-only melee attacker. Covers training (cost/time/
# pop), the spawn->descend lifecycle, the no-surfacing and no-digging rules,
# movement through carved tunnels, central-wall blocking before the breach and
# pathing through after it, killing enemy miners underground, and the
# midfield-rule exception (auto-acquire engages on EITHER side underground).
# Boots the real main.tscn; no factions are set, so costs/stats are the
# neutral Constants defaults.

const PLAYER: int = 0
const ENEMY: int = 1

var _main: Node
var _grid: Node
var _pc: Node
var _building: Node2D


func before_all() -> void:
	seed(12345)
	_main = load("res://scenes/main.tscn").instantiate()
	get_tree().root.add_child(_main)
	get_tree().current_scene = _main
	_grid = _main.get_node("World/GridWorld")
	_pc = _main.get_node("PlayerController")
	for b in get_tree().get_nodes_in_group("buildings"):
		if b.get("team") == PLAYER:
			_building = b
	# Random events would interfere with the position/combat assertions.
	WeatherManager.set_weather_events_enabled(false)
	WeatherManager.set_volcano_events_enabled(false)
	_grid.set_dynamic_events_enabled(false)
	await wait_seconds(0.1)


func after_all() -> void:
	_main.free()


func before_each() -> void:
	# Free leftover crawlers first (a plain free skips population removal),
	# then reset the economy so every test starts from a clean 500 coin.
	_cleanup_crawlers()
	while _building.call("cancel_queue", 0):
		pass
	EconomyManager.reset()
	ResearchManager.reset()
	# Autoload pins: never inherit a difficulty/opener from another script.
	# Easy (smarts tier 0) keeps the live AI from training its own crawler
	# guard, which could steal target locks in the combat assertions.
	GameManager.set_difficulty(GameManager.Difficulty.EASY)
	GameManager.ai_opener = "balanced"
	GameManager.game_active = true


func after_each() -> void:
	for proj in _main.get_node("Projectiles").get_children():
		proj.free()
	# Autoloads: never leak a difficulty or opener choice into the next script.
	GameManager.set_difficulty(GameManager.Difficulty.NORMAL)
	GameManager.ai_opener = "balanced"


func _cleanup_crawlers() -> void:
	for u in get_tree().get_nodes_in_group("units"):
		if u.data != null and (u.data.is_crawler or u.data.unit_name.to_lower() == "crawler"):
			u.free()


func _spawn_crawler(team: int, pos: Vector2, underground: bool = false) -> Node2D:
	var unit: Node2D = load("res://scenes/unit.tscn").instantiate()
	unit.set("data", load("res://scripts/resources/units/crawler.tres").duplicate(true))
	unit.set("team", team)
	unit.position = pos
	_main.get_node("Units").add_child(unit)
	if underground:
		unit.set("is_underground", true)
	autofree(unit)
	return unit


func _spawn_enemy_miner(pos: Vector2, underground: bool = true) -> Node2D:
	var unit: Node2D = load("res://scenes/unit.tscn").instantiate()
	unit.set("data", load("res://scripts/resources/units/miner.tres").duplicate(true))
	unit.set("team", ENEMY)
	unit.position = pos
	_main.get_node("Units").add_child(unit)
	if underground:
		unit.set("is_underground", true)
	autofree(unit)
	return unit


func _mine_entry(team: int) -> Node2D:
	for entry in get_tree().get_nodes_in_group("mine_entries"):
		if entry.get("team") == team:
			return entry
	return null


## Carves a horizontal tunnel of EMPTY cells (as if dug out) so crawlers can
## path through it; bypasses mining time by erasing the cells outright.
func _carve(cells: Array) -> void:
	for pos in cells:
		var swings: int = 0
		while _grid.get_cell(pos) != null and swings < 50:
			_grid.damage_cell(pos, 9999, 3)
			swings += 1


func _carve_row(y: int, x_from: int, x_to: int) -> void:
	var cells: Array = []
	var step: int = 1 if x_to >= x_from else -1
	var x: int = x_from
	while true:
		cells.append(Vector2i(x, y))
		if x == x_to:
			break
		x += step
	_carve(cells)


# ─── Training ───

func test_crawler_trains_with_correct_cost_time_and_pop() -> void:
	assert_eq(_building.call("get_train_cost", "crawler"), 120)
	assert_almost_eq(_building.call("get_train_time", "crawler"), 8.0, 0.01)
	var coin_before: int = EconomyManager.get_coin(PLAYER)
	var pop_before: int = EconomyManager.get_population(PLAYER)
	assert_true(_building.call("queue_unit", "crawler"))
	assert_eq(EconomyManager.get_coin(PLAYER), coin_before - 120, "crawler costs 120")
	await wait_seconds(8.5)
	var crawler: Node2D = null
	for u in get_tree().get_nodes_in_group("player"):
		if u.data != null and u.data.is_crawler:
			crawler = u
	assert_not_null(crawler, "crawler spawns from the building after 8s")
	assert_eq(EconomyManager.get_population(PLAYER), pop_before + 2, "crawler takes 2 population")


# ─── Lifecycle ───

func test_crawler_spawn_descends_into_mine() -> void:
	var crawler: Node2D = _spawn_crawler(PLAYER, _building.global_position + Vector2(220, 16))
	# Walk to the mine entry plus the ladder climb takes a few seconds.
	var descended: bool = false
	for i in range(20):
		await wait_seconds(0.5)
		if crawler.get("is_underground"):
			descended = true
			break
	assert_true(descended, "crawler walks to the own mine entry and descends on its own")


func test_idle_crawler_guards_the_mine_entry() -> void:
	var entry: Node2D = _mine_entry(PLAYER)
	var crawler: Node2D = _spawn_crawler(PLAYER, _building.global_position + Vector2(220, 16))
	var descended: bool = false
	for i in range(20):
		await wait_seconds(0.5)
		if crawler.get("is_underground"):
			descended = true
			break
	assert_true(descended, "crawler descended")
	await wait_seconds(2.0)
	var post: Vector2 = entry.call("get_underground_position")
	assert_lt(crawler.global_position.distance_to(post), GridWorld.CELL_SIZE * 3.0,
		"idle crawler holds a post near the own mine entry underground")


func test_crawler_cannot_exit_mine() -> void:
	var entry: Node2D = _mine_entry(PLAYER)
	var crawler: Node2D = _spawn_crawler(PLAYER, entry.call("get_underground_position"), true)
	crawler.call("exit_mine")
	assert_true(crawler.get("is_underground"), "exit_mine is rejected for crawlers")
	crawler.call("climb_up_ladder")
	assert_true(crawler.get("is_underground"), "climb_up_ladder is rejected for crawlers")
	await wait_seconds(0.5)
	assert_true(crawler.get("is_underground"), "crawler stays underground")


func test_crawler_cannot_dig() -> void:
	var entry: Node2D = _mine_entry(PLAYER)
	var crawler: Node2D = _spawn_crawler(PLAYER, entry.call("get_underground_position"), true)
	var wall_cell: Vector2i = _grid.get_wall_cells()[0]
	crawler.call("mine_cell", wall_cell)
	assert_ne(crawler.get("_state"), Unit.State.MINE, "crawlers never mine (breaching stays miner-only)")


# ─── Movement / central wall ───

func test_crawler_moves_through_carved_tunnels() -> void:
	var entry: Node2D = _mine_entry(PLAYER)
	var shaft: Vector2i = _grid.world_to_grid(entry.call("get_underground_position"))
	_carve_row(shaft.y, shaft.x - 4, shaft.x - 1)
	var crawler: Node2D = _spawn_crawler(PLAYER, _grid.grid_to_world(shaft), true)
	var target: Vector2 = _grid.grid_to_world(Vector2i(shaft.x - 4, shaft.y))
	crawler.call("move_to", target)
	assert_eq(crawler.get("_state"), Unit.State.MOVE, "move order into a carved tunnel is accepted")
	var arrived: bool = false
	for i in range(10):
		await wait_seconds(0.5)
		if crawler.global_position.distance_to(target) < GridWorld.CELL_SIZE:
			arrived = true
			break
	assert_true(arrived, "crawler walks the carved tunnel")


func test_crawler_blocked_by_central_wall_until_breached() -> void:
	var player_entry: Node2D = _mine_entry(PLAYER)
	var enemy_entry: Node2D = _mine_entry(ENEMY)
	var y: int = 2
	# Carve both sides of a level-1 row right up to the wall columns.
	_carve_row(y, -14, -2)
	_carve_row(y, 2, 14)
	var crawler: Node2D = _spawn_crawler(PLAYER, _grid.grid_to_world(Vector2i(-4, y)), true)
	var enemy_side: Vector2 = _grid.grid_to_world(Vector2i(6, y))
	crawler.call("move_to", enemy_side)
	assert_ne(crawler.get("_state"), Unit.State.MOVE, "no route through the intact central wall")
	assert_gt(_grid.get_wall_hp(), 0, "sanity: wall still standing")
	# Breach the wall (shared pool) and order the crossing again.
	_grid.damage_cell(_grid.get_wall_cells()[0], 100000, 3)
	assert_eq(_grid.get_wall_hp(), 0, "wall pool drained")
	crawler.call("move_to", enemy_side)
	assert_eq(crawler.get("_state"), Unit.State.MOVE, "breached corridor opens the route")
	var crossed: bool = false
	for i in range(20):
		await wait_seconds(0.5)
		if crawler.global_position.distance_to(enemy_side) < GridWorld.CELL_SIZE:
			crossed = true
			break
	assert_true(crossed, "crawler paths through the breach into the enemy mine")
	assert_lt(crawler.global_position.x, enemy_entry.global_position.x + GridWorld.CELL_SIZE, "sanity: still near the enemy side")
	assert_true(crawler.global_position.x > player_entry.global_position.x, "crawler crossed midfield underground")


# ─── Combat ───

func test_crawler_kills_enemy_miner_underground() -> void:
	var entry: Node2D = _mine_entry(PLAYER)
	var base: Vector2 = entry.call("get_underground_position")
	var shaft: Vector2i = _grid.world_to_grid(base)
	# Carve standable cells around the shaft (fixtures placed inside solid
	# dirt can't path to each other, so attack orders would be rejected).
	_carve_row(shaft.y, shaft.x - 2, shaft.x + 2)
	var crawler: Node2D = _spawn_crawler(PLAYER, _grid.grid_to_world(shaft), true)
	var miner: Node2D = _spawn_enemy_miner(_grid.grid_to_world(Vector2i(shaft.x + 2, shaft.y)))
	var dead: bool = false
	for i in range(24):
		await wait_seconds(0.5)
		if not is_instance_valid(miner) or miner.get("_state") == Unit.State.DEAD:
			dead = true
			break
	assert_true(dead, "crawler hunts down the enemy miner (12 dmg / 1s vs 50 hp)")


func test_crawler_engages_across_midfield_underground() -> void:
	# Midfield-rule exception: auto-acquire works on the ENEMY side of the mine.
	# Both units stand in carved cells of the enemy half's shaft area.
	var enemy_entry: Node2D = _mine_entry(ENEMY)
	var base: Vector2 = enemy_entry.call("get_underground_position")
	assert_gt(base.x, 0.0, "sanity: enemy shaft is on the right half")
	var shaft: Vector2i = _grid.world_to_grid(base)
	_carve_row(shaft.y, shaft.x - 2, shaft.x + 2)
	var crawler: Node2D = _spawn_crawler(PLAYER, _grid.grid_to_world(Vector2i(shaft.x - 1, shaft.y)), true)
	_spawn_enemy_miner(_grid.grid_to_world(Vector2i(shaft.x + 1, shaft.y)))  # bait next to the crawler
	await wait_seconds(1.5)
	assert_eq(crawler.get("_state"), Unit.State.ATTACK,
		"crawler auto-engages on the enemy side (the midfield exception)")
	var lock = crawler.get("_target_unit")
	assert_not_null(lock, "the raider has a target lock")
	if lock != null:
		assert_eq(lock.get("team"), ENEMY, "the lock is an enemy unit")
		assert_true(lock.get("is_underground"), "the lock is underground")
		assert_gt(lock.global_position.x, 0.0, "the lock is on the enemy half")


func test_crawler_never_targets_structures() -> void:
	var entry: Node2D = _mine_entry(PLAYER)
	var base: Vector2 = entry.call("get_underground_position")
	var crawler: Node2D = _spawn_crawler(PLAYER, base, true)
	await wait_seconds(1.0)
	assert_eq(crawler.get("_target_building"), null, "crawlers ignore structures")
