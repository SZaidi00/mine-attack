extends GutTest

# Revamp Phase 3: placeable structures — sentry towers (placement rules,
# construction, vision, target priority, salvage) and walls (chain placement,
# A* blocking, projectile absorption). Boots the real main.tscn; no factions
# are set, so structure costs/stats are the neutral Constants defaults.

const PLAYER: int = 0
const ENEMY: int = 1

var _main: Node
var _grid: Node
var _pc: Node


func before_all() -> void:
	seed(12345)
	_main = load("res://scenes/main.tscn").instantiate()
	get_tree().root.add_child(_main)
	get_tree().current_scene = _main
	_grid = _main.get_node("World/GridWorld")
	_pc = _main.get_node("PlayerController")
	await wait_seconds(0.1)


func after_all() -> void:
	_main.free()


func before_each() -> void:
	EconomyManager.add_coin(PLAYER, 5000)
	# Tests place structures at fixed cells — start each test with a clean map.
	for tower in get_tree().get_nodes_in_group("towers"):
		tower.free()
	for lantern in get_tree().get_nodes_in_group("lanterns"):
		lantern.free()
	for wall in get_tree().get_nodes_in_group("walls"):
		if wall.is_built():
			# Free the whole sealed column (surface cell + dug cells beneath;
			# carved tunnels are erased from the grid, so they read as null).
			for y in range(GridWorld.Y_MIN, GridWorld.Y_MAX + 1):
				var pos := Vector2i(wall.get_cell().x, y)
				if not _grid._astar.is_in_boundsv(pos):
					continue
				var cell = _grid.get_cell(pos)
				if pos.y == wall.get_cell().y or cell == null or cell.type == GridWorld.CellType.EMPTY:
					_grid._astar.set_point_solid(pos, false)
		wall.free()


func _player_building() -> Node2D:
	for b in get_tree().get_nodes_in_group("buildings"):
		if b.team == PLAYER:
			return b
	return null


func _spawn_unit(tres_path: String, team: int, pos: Vector2) -> Node2D:
	var unit: Node2D = load("res://scenes/unit.tscn").instantiate()
	unit.set("data", load(tres_path).duplicate(true))
	unit.set("team", team)
	unit.position = pos
	_main.get_node("Units").add_child(unit)
	autofree(unit)
	return unit


## Skips construction without waiting out the real build time.
func _finish_construction(structure: Node2D) -> void:
	structure.set("_build_progress", structure.get("build_time"))
	await wait_seconds(0.2)


func _count_pickups() -> int:
	var count: int = 0
	for child in get_tree().current_scene.get_children():
		if child is CoinPickup:
			count += 1
	return count


# ─── Tower placement ───

func test_tower_placement_valid_on_own_surface_half() -> void:
	var before: int = EconomyManager.get_coin(PLAYER)
	assert_true(_pc.try_place_structure("tower", _grid.grid_to_world(Vector2i(-12, 0))))
	assert_eq(get_tree().get_nodes_in_group("towers").size(), 1, "tower spawns")
	assert_eq(EconomyManager.get_coin(PLAYER), before - 300, "tower costs 300")
	var tower: Node2D = get_tree().get_nodes_in_group("towers")[0]
	assert_false(tower.is_built(), "tower starts under construction")
	assert_eq(tower.total_cost, 300)


func test_tower_placement_rejects_bad_cells() -> void:
	assert_false(_pc.try_place_structure("tower", _grid.grid_to_world(Vector2i(-12, 4))), "no underground towers")
	assert_false(_pc.try_place_structure("tower", _grid.grid_to_world(Vector2i(8, 0))), "own half only")
	var rect: Rect2i = _player_building().get_footprint_cell_rect()
	assert_false(_pc.try_place_structure("tower", _grid.grid_to_world(Vector2i(rect.position.x - 1, 0))), "not within 2 cells of a building")
	assert_eq(get_tree().get_nodes_in_group("towers").size(), 0, "rejections must not spawn anything")


func test_tower_placement_rejects_occupied_and_caps_at_max() -> void:
	# Cells -12/-10/-8: clear of the mine entry (x=-15 ± 2) and the building.
	assert_true(_pc.try_place_structure("tower", _grid.grid_to_world(Vector2i(-12, 0))))
	assert_false(_pc.try_place_structure("tower", _grid.grid_to_world(Vector2i(-12, 0))), "cell is occupied")
	assert_true(_pc.try_place_structure("tower", _grid.grid_to_world(Vector2i(-10, 0))))
	assert_false(_pc.try_place_structure("tower", _grid.grid_to_world(Vector2i(-8, 0))), "max 2 towers")
	assert_eq(get_tree().get_nodes_in_group("towers").size(), 2)


func test_tower_invulnerable_while_building_then_vision_and_fire() -> void:
	_pc.try_place_structure("tower", _grid.grid_to_world(Vector2i(-12, 0)))
	var tower: Node2D = get_tree().get_nodes_in_group("towers")[0]
	tower.take_damage(100)
	assert_eq(tower.hp, tower.max_hp, "under-construction tower takes no damage")
	await _finish_construction(tower)
	assert_true(tower.is_built())
	# Towers are surface vision sources (18 cells).
	assert_true(_grid.is_visible_to(PLAYER, tower.global_position + Vector2(10 * 32, 0)), "built tower lights its radius")
	# Fires at a visible enemy fighter in range.
	var enemy: Node2D = _spawn_unit("res://scripts/resources/units/swordsman.tres", ENEMY, tower.global_position + Vector2(160, 16))
	await wait_seconds(2.0)
	assert_lt(enemy.get("hp"), enemy.data.max_hp, "tower shot the intruder")


func test_tower_prioritizes_fighters_over_miners() -> void:
	_pc.try_place_structure("tower", _grid.grid_to_world(Vector2i(-12, 0)))
	var tower: Node2D = get_tree().get_nodes_in_group("towers")[0]
	await _finish_construction(tower)
	var miner: Node2D = _spawn_unit("res://scripts/resources/units/miner.tres", ENEMY, tower.global_position + Vector2(96, 0))
	var fighter: Node2D = _spawn_unit("res://scripts/resources/units/swordsman.tres", ENEMY, tower.global_position + Vector2(160, 0))
	var pick = tower.call("_pick_target")
	assert_eq(pick, fighter, "fighters outrank miners even when the miner is closer")
	assert_ne(pick, miner)


func test_tower_destruction_drops_salvage() -> void:
	_pc.try_place_structure("tower", _grid.grid_to_world(Vector2i(-12, 0)))
	var tower: Node2D = get_tree().get_nodes_in_group("towers")[0]
	await _finish_construction(tower)
	var pickups_before: int = _count_pickups()
	tower.take_damage(9999)
	assert_eq(get_tree().get_nodes_in_group("towers").size(), 0, "destroyed tower leaves the towers group")
	assert_eq(_count_pickups(), pickups_before + 1, "salvage pickup drops")


func test_fighters_auto_attack_enemy_tower() -> void:
	_pc.try_place_structure("tower", _grid.grid_to_world(Vector2i(-12, 0)))
	var tower: Node2D = get_tree().get_nodes_in_group("towers")[0]
	tower.team = ENEMY  # pretend the enemy built it here
	await _finish_construction(tower)
	var swordsman: Node2D = _spawn_unit("res://scripts/resources/units/swordsman.tres", PLAYER, tower.global_position + Vector2(-128, 16))
	await wait_seconds(0.1)  # let the swordsman's vision register on the fog map
	var pick = swordsman.call("_nearest_visible_enemy_structure")
	assert_eq(pick, tower, "fighters auto-attack visible enemy towers")


# ─── Wall placement ───

func test_wall_placement_rules() -> void:
	assert_true(_pc.try_place_structure("wall", _grid.grid_to_world(Vector2i(-20, 0))), "a wall on open own-half surface ground places")
	assert_false(_pc.try_place_structure("wall", _grid.grid_to_world(Vector2i(-20, 0))), "cell is occupied")
	assert_false(_pc.try_place_structure("wall", _grid.grid_to_world(Vector2i(-22, 4))), "no underground walls")
	assert_false(_pc.try_place_structure("wall", _grid.grid_to_world(Vector2i(8, 0))), "own half only")


func test_wall_max_count() -> void:
	assert_true(_pc.try_place_structure("wall", _grid.grid_to_world(Vector2i(-20, 0))))
	assert_true(_pc.try_place_structure("wall", _grid.grid_to_world(Vector2i(-22, 0))))
	assert_false(_pc.try_place_structure("wall", _grid.grid_to_world(Vector2i(-24, 0))), "3rd wall exceeds the neutral cap of 2")


func test_wall_blocks_and_frees_astar_cell() -> void:
	var cell := Vector2i(-20, 0)
	_pc.try_place_structure("wall", _grid.grid_to_world(cell))
	var wall: Node2D = get_tree().get_nodes_in_group("walls")[0]
	assert_false(_grid._astar.is_point_solid(cell), "under construction: not solid yet")
	await _finish_construction(wall)
	assert_true(_grid._astar.is_point_solid(cell), "built wall blocks the cell")
	wall.take_damage(9999)
	assert_false(_grid._astar.is_point_solid(cell), "destroyed wall frees the cell")
	assert_eq(get_tree().get_nodes_in_group("walls").size(), 0)


func test_wall_absorbs_enemy_projectiles() -> void:
	_pc.try_place_structure("wall", _grid.grid_to_world(Vector2i(-20, 0)))
	var wall: Node2D = get_tree().get_nodes_in_group("walls")[0]
	await _finish_construction(wall)
	var proj: Node2D = load("res://scenes/projectile.tscn").instantiate()
	proj.set("team", ENEMY)
	proj.set("damage", 50)
	proj.set("speed", 300.0)
	proj.set("target_position", wall.global_position + Vector2(-200, 0))
	proj.global_position = wall.global_position + Vector2(40, 0)
	_main.get_node("Projectiles").add_child(proj)
	proj.call("_process", 0.016)  # flies 4.8px per frame; reaches the wall quickly
	var frames: int = 0
	while is_instance_valid(proj) and not proj.is_queued_for_deletion() and frames < 20:
		proj.call("_process", 0.016)
		frames += 1
	assert_true(proj.is_queued_for_deletion(), "projectile is absorbed by the wall")
	assert_eq(wall.hp, 400 - 50, "the wall takes the hit")
	autofree(proj)


func test_wall_repaths_units_crossing_its_cell() -> void:
	# Order a unit through cell (-20, 0) BEFORE the wall exists.
	var cell := Vector2i(-20, 0)
	var runner: Node2D = _spawn_unit("res://scripts/resources/units/swordsman.tres", ENEMY, _grid.grid_to_world(Vector2i(-12, 0)))
	runner.call("move_to", _grid.grid_to_world(Vector2i(-25, 0)))
	var path: PackedVector2Array = runner.get("_path")
	var crosses_before: bool = false
	for p in path:
		if _grid.world_to_grid(p) == cell:
			crosses_before = true
	assert_true(crosses_before, "the pre-wall path runs through the wall cell")
	_pc.try_place_structure("wall", _grid.grid_to_world(cell))
	var wall: Node2D = get_tree().get_nodes_in_group("walls")[0]
	await _finish_construction(wall)
	var new_path: PackedVector2Array = runner.get("_path")
	for p in new_path:
		assert_ne(_grid.world_to_grid(p), cell, "the unit re-paths around (or stops at) the finished wall")


func test_wall_cells_are_not_walkable_points() -> void:
	_pc.try_place_structure("wall", _grid.grid_to_world(Vector2i(-20, 0)))
	var wall: Node2D = get_tree().get_nodes_in_group("walls")[0]
	var checker: Node2D = _spawn_unit("res://scripts/resources/units/swordsman.tres", ENEMY, _grid.grid_to_world(Vector2i(-12, 0)))
	assert_true(checker.call("_is_walkable_point", _grid.grid_to_world(Vector2i(-20, 0))), "under construction: still walkable")
	await _finish_construction(wall)
	assert_false(checker.call("_is_walkable_point", _grid.grid_to_world(Vector2i(-20, 0))), "built wall blocks kite/blink checks")
	wall.take_damage(9999)
	assert_true(checker.call("_is_walkable_point", _grid.grid_to_world(Vector2i(-20, 0))), "destroyed wall is walkable again")


func test_wall_seals_tunnels_beneath_it() -> void:
	# Dig out two cells under the wall site before it exists.
	var below1 := Vector2i(-20, 1)
	var below2 := Vector2i(-20, 2)
	_grid.damage_cell(below1, 9999, 3)
	_grid.damage_cell(below2, 9999, 3)
	assert_false(_grid._astar.is_point_solid(below1), "dug cell is walkable before the wall")
	_pc.try_place_structure("wall", _grid.grid_to_world(Vector2i(-20, 0)))
	var wall: Node2D = get_tree().get_nodes_in_group("walls")[0]
	await _finish_construction(wall)
	assert_true(_grid._astar.is_point_solid(Vector2i(-20, 0)), "surface cell sealed")
	assert_true(_grid._astar.is_point_solid(below1), "existing tunnel beneath is sealed")
	assert_true(_grid._astar.is_point_solid(below2), "deeper tunnel beneath is sealed")
	# A fresh dig under a built wall re-seals immediately.
	var below3 := Vector2i(-20, 3)
	_grid.damage_cell(below3, 9999, 3)
	assert_true(_grid._astar.is_point_solid(below3), "freshly dug cell re-seals — no tunneling under")
	# Destruction frees the column again.
	wall.take_damage(9999)
	assert_false(_grid._astar.is_point_solid(below1), "destroyed wall frees the tunnels beneath")
	assert_false(_grid._astar.is_point_solid(below3), "and the re-sealed dig")


func test_own_wall_never_blocks_its_team() -> void:
	_pc.try_place_structure("wall", _grid.grid_to_world(Vector2i(-20, 0)))
	var wall: Node2D = get_tree().get_nodes_in_group("walls")[0]
	await _finish_construction(wall)
	# Owner: the seal is lifted for its paths — a unit paths straight through.
	var mine_unit: Node2D = _spawn_unit("res://scripts/resources/units/swordsman.tres", PLAYER, _grid.grid_to_world(Vector2i(-12, 0)))
	mine_unit.call("move_to", _grid.grid_to_world(Vector2i(-25, 0)))
	var own_path: PackedVector2Array = mine_unit.get("_path")
	assert_false(own_path.is_empty(), "the owner still paths past its own wall")
	var crosses: bool = false
	for p in own_path:
		if _grid.world_to_grid(p) == Vector2i(-20, 0):
			crosses = true
	assert_true(crosses, "the owner's path runs through its own wall")
	# Enemy: the same query is blocked (no route on this map, so no path).
	var enemy_unit: Node2D = _spawn_unit("res://scripts/resources/units/swordsman.tres", ENEMY, _grid.grid_to_world(Vector2i(-12, 0)))
	enemy_unit.call("move_to", _grid.grid_to_world(Vector2i(-25, 0)))
	for p in enemy_unit.get("_path"):
		assert_ne(_grid.world_to_grid(p), Vector2i(-20, 0), "the enemy can never path through the wall")


func test_sealed_base_path_redirects_to_wall_breach() -> void:
	# A built player wall seals column -20 completely, so the enemy can no
	# longer path to the player building. The siege order must redirect to the
	# blocking wall instead of freezing the unit (the wave-stall bug).
	_pc.try_place_structure("wall", _grid.grid_to_world(Vector2i(-20, 0)))
	var wall: Node2D = get_tree().get_nodes_in_group("walls")[0]
	await _finish_construction(wall)
	var attacker: Node2D = _spawn_unit("res://scripts/resources/units/swordsman.tres", ENEMY, _grid.grid_to_world(Vector2i(-17, 0)))
	attacker.call("attack_building", _player_building())
	assert_eq(attacker.get("_target_building"), wall, "unreachable base redirects to a wall breach")
	assert_eq(attacker.get("_state"), Unit.State.ATTACK, "the unit sieges instead of going idle")
	await wait_seconds(2.5)
	assert_lt(wall.hp, wall.max_hp, "the breach actually damages the wall")


func test_sieging_unit_retaliates_against_tower() -> void:
	# Tower fire must peel a sieging unit onto the tower — a tower is not a
	# Unit, so the normal retaliation pick can never return it.
	_pc.try_place_structure("tower", _grid.grid_to_world(Vector2i(-12, 0)))
	var tower: Node2D = get_tree().get_nodes_in_group("towers")[0]
	tower.team = ENEMY  # pretend the enemy built it
	await _finish_construction(tower)
	var swordsman: Node2D = _spawn_unit("res://scripts/resources/units/swordsman.tres", PLAYER, _grid.grid_to_world(Vector2i(-20, 0)))
	var enemy_building: Node2D = null
	for b in get_tree().get_nodes_in_group("buildings"):
		if b.team == ENEMY:
			enemy_building = b
	swordsman.call("attack_building", enemy_building)
	assert_eq(swordsman.get("_state"), Unit.State.ATTACK, "siege order accepted")
	swordsman.call("take_damage", 5, tower)
	assert_eq(swordsman.get("_target_building"), tower, "tower fire peels the sieger onto the tower")


func test_fighters_target_remembered_structure_through_fog() -> void:
	# Static structures stay targetable on remembered intel — fog must not
	# grant a tower free invulnerability once live vision moves on.
	_pc.try_place_structure("tower", _grid.grid_to_world(Vector2i(-12, 0)))
	var tower: Node2D = get_tree().get_nodes_in_group("towers")[0]
	tower.team = ENEMY  # pretend the enemy built it
	await _finish_construction(tower)
	# See it once so the team remembers it...
	var scout: Node2D = _spawn_unit("res://scripts/resources/units/swordsman.tres", PLAYER, tower.global_position + Vector2(-96, 16))
	await wait_seconds(0.2)
	assert_true(_grid.is_remembered_by(PLAYER, tower.global_position), "tower seen and remembered")
	# ...then lose live vision: the tower stays a valid target.
	scout.position = _grid.grid_to_world(Vector2i(-28, 0))
	await wait_seconds(0.2)
	assert_false(_grid.is_visible_to(PLAYER, tower.global_position), "setup: tower is back in fog")
	var pick = scout.call("_nearest_visible_enemy_structure")
	assert_eq(pick, tower, "remembered structures stay targetable")


func test_wave_peels_fighters_onto_remembered_structures() -> void:
	_pc.try_place_structure("tower", _grid.grid_to_world(Vector2i(-12, 0)))
	_pc.try_place_structure("lantern", _grid.grid_to_world(Vector2i(-10, 0)))
	var tower: Node2D = get_tree().get_nodes_in_group("towers")[0]
	var lantern: Node2D = get_tree().get_nodes_in_group("lanterns")[0]
	await _finish_construction(tower)
	await _finish_construction(lantern)
	var ai: Node = _main.get_node("AIController")
	_grid.set_reveal_all(ENEMY, true)  # stand-in for scouted intel
	var result: Dictionary = ai._combat._wave_structure_assignments(8)
	var small: Dictionary = ai._combat._wave_structure_assignments(2)
	_grid.set_reveal_all(ENEMY, false)
	var structures: Array = result["structures"]
	assert_eq(structures.size(), 2, "both remembered structures are wave targets")
	assert_eq(structures[0], lantern, "nearest to the enemy base is hit first")
	assert_eq(result["peel_count"], 4, "2 fighters per structure")
	assert_eq(small["peel_count"], 1, "the peel is capped at half the wave")
