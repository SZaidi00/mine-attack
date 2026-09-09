extends GutTest

# Engineer support unit: building training (cost/time/pop), the repair
# channel (HP restored, coin drained continuously), the recent-damage
# lockout, the full-HP stop, and idle auto-seek. Boots the real main.tscn;
# no factions are set, so costs/stats are the neutral Constants defaults.

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
	# Random events would interfere with the HP/coin assertions.
	WeatherManager.set_weather_events_enabled(false)
	WeatherManager.set_volcano_events_enabled(false)
	_grid.set_dynamic_events_enabled(false)
	await wait_seconds(0.1)


func after_all() -> void:
	_main.free()


func before_each() -> void:
	# Free leftover engineers first (a plain free skips population removal),
	# then reset the economy so every test starts from a clean 500 coin.
	_cleanup_engineers()
	while _building.call("cancel_queue", 0):
		pass
	EconomyManager.reset()
	ResearchManager.reset()
	_cleanup_structures()
	# Heal the base and age its damage stamp so repair tests start clean.
	_building.set("_hp", _building.get("max_hp"))
	_building.set("_last_damage_time", -999.0)


func after_each() -> void:
	for proj in _main.get_node("Projectiles").get_children():
		proj.free()


func _cleanup_engineers() -> void:
	for u in get_tree().get_nodes_in_group("units"):
		if u.data != null and u.data.is_engineer:
			u.free()


func _cleanup_structures() -> void:
	for tower in get_tree().get_nodes_in_group("towers"):
		tower.free()
	for lantern in get_tree().get_nodes_in_group("lanterns"):
		lantern.free()
	for wall in get_tree().get_nodes_in_group("walls"):
		if wall.is_built():
			# Free the whole sealed column (surface cell + dug cells beneath).
			for y in range(GridWorld.Y_MIN, GridWorld.Y_MAX + 1):
				var pos := Vector2i(wall.get_cell().x, y)
				if not _grid._astar.is_in_boundsv(pos):
					continue
				var cell = _grid.get_cell(pos)
				if pos.y == wall.get_cell().y or cell == null or cell.type == GridWorld.CellType.EMPTY:
					_grid._astar.set_point_solid(pos, false)
		wall.free()


func _spawn_engineer(team: int, pos: Vector2) -> Node2D:
	var unit: Node2D = load("res://scenes/unit.tscn").instantiate()
	unit.set("data", load("res://scripts/resources/units/engineer.tres").duplicate(true))
	unit.set("team", team)
	unit.position = pos
	_main.get_node("Units").add_child(unit)
	autofree(unit)
	return unit


## Places a player tower at (-12, 0), finishes construction instantly, and
## damages it. The damage stamp is left fresh (lockout live) — callers that
## want a repairable tower must age _last_damage_time themselves.
func _build_damaged_tower(damage: int) -> Node2D:
	_pc.try_place_structure("tower", _grid.grid_to_world(Vector2i(-12, 0)))
	var tower: Node2D = get_tree().get_nodes_in_group("towers")[0]
	tower.set("_build_progress", tower.get("build_time"))
	await wait_seconds(0.2)  # finish construction without the real build time
	tower.take_damage(damage)
	return tower


func test_engineer_trains_with_correct_cost_time_and_pop() -> void:
	assert_eq(_building.call("get_train_cost", "engineer"), 75)
	assert_almost_eq(_building.call("get_train_time", "engineer"), 6.0, 0.01)
	var coin_before: int = EconomyManager.get_coin(PLAYER)
	var pop_before: int = EconomyManager.get_population(PLAYER)
	assert_true(_building.call("queue_unit", "engineer"))
	assert_eq(EconomyManager.get_coin(PLAYER), coin_before - 75, "engineer costs 75")
	await wait_seconds(6.5)
	var engineer: Node2D = null
	for u in get_tree().get_nodes_in_group("player"):
		if u.data != null and u.data.is_engineer:
			engineer = u
	assert_not_null(engineer, "engineer spawns from the building after 6s")
	assert_eq(EconomyManager.get_population(PLAYER), pop_before + 2, "engineer takes 2 population")


func test_repair_restores_hp_and_drains_coin() -> void:
	var tower: Node2D = await _build_damaged_tower(100)
	tower.set("_last_damage_time", GameManager.match_time - 10.0)  # age past the lockout
	var engineer: Node2D = _spawn_engineer(PLAYER, tower.global_position + Vector2(64, 0))
	engineer.call("repair_structure", tower)
	assert_eq(engineer.get("_state"), Unit.State.REPAIR, "repair order accepted")
	var hp_before: int = tower.get("hp")
	var coin_before: int = EconomyManager.get_coin(PLAYER)
	await wait_seconds(2.0)
	assert_gt(tower.get("hp"), hp_before, "repair restores structure HP")
	assert_lt(EconomyManager.get_coin(PLAYER), coin_before, "repair drains coin as HP lands")


func test_repair_blocked_during_recent_damage_lockout() -> void:
	var tower: Node2D = await _build_damaged_tower(100)
	# take_damage just stamped match_time — the lockout window is live.
	var engineer: Node2D = _spawn_engineer(PLAYER, tower.global_position + Vector2(64, 0))
	engineer.call("repair_structure", tower)
	var hp_damaged: int = tower.get("hp")
	var coin_before: int = EconomyManager.get_coin(PLAYER)
	await wait_seconds(1.5)
	assert_eq(tower.get("hp"), hp_damaged, "no repairs inside the 3s lockout")
	assert_eq(EconomyManager.get_coin(PLAYER), coin_before, "no coin drained while locked out")
	await wait_seconds(2.5)  # the lockout window passes
	assert_gt(tower.get("hp"), hp_damaged, "repair resumes once the lockout expires")


func test_repair_never_exceeds_max_hp_and_stops() -> void:
	var tower: Node2D = await _build_damaged_tower(10)
	tower.set("_last_damage_time", GameManager.match_time - 10.0)
	var engineer: Node2D = _spawn_engineer(PLAYER, tower.global_position + Vector2(64, 0))
	engineer.call("repair_structure", tower)
	await wait_seconds(2.0)
	assert_eq(tower.get("hp"), tower.get("max_hp"), "repair caps at max HP")
	assert_eq(engineer.get("_state"), Unit.State.IDLE, "engineer goes idle once the structure is full")
	var coin_at_full: int = EconomyManager.get_coin(PLAYER)
	await wait_seconds(1.0)
	assert_eq(EconomyManager.get_coin(PLAYER), coin_at_full, "no coin drained at full HP")


func test_idle_engineer_auto_seeks_damaged_structure() -> void:
	var tower: Node2D = await _build_damaged_tower(50)
	tower.set("_last_damage_time", GameManager.match_time - 10.0)
	var hp_damaged: int = tower.get("hp")
	var engineer: Node2D = _spawn_engineer(PLAYER, tower.global_position + Vector2(160, 0))
	await wait_seconds(1.0)
	assert_eq(engineer.get("_state"), Unit.State.REPAIR, "idle engineer seeks the damaged tower on its own")
	await wait_seconds(2.5)
	assert_gt(tower.get("hp"), hp_damaged, "the auto-seeked repair restores HP")


func test_engineer_rejects_non_structure_targets() -> void:
	var engineer: Node2D = _spawn_engineer(PLAYER, _grid.grid_to_world(Vector2i(-20, 0)))
	var ally: Node2D = load("res://scenes/unit.tscn").instantiate()
	ally.set("data", load("res://scripts/resources/units/swordsman.tres").duplicate(true))
	ally.set("team", PLAYER)
	ally.position = _grid.grid_to_world(Vector2i(-22, 0))
	_main.get_node("Units").add_child(ally)
	autofree(ally)
	engineer.call("repair_structure", ally)
	assert_eq(engineer.get("_state"), Unit.State.IDLE, "units are never repair targets")
	var tower: Node2D = await _build_damaged_tower(0)
	engineer.call("repair_structure", tower)
	assert_eq(engineer.get("_state"), Unit.State.IDLE, "full-HP structures are not repair targets")
