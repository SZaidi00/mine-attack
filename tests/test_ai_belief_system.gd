extends GutTest

# AI belief system (Revamp Phase 8): the AI's picture of the map is built
# from its own vision only — unseen cells/units are unknown, stale intel
# decays, and the enemy faction can be inferred from observed army
# composition until a scout reveals it for real.

const PLAYER: int = 0
const ENEMY: int = 1

var _main: Node
var _units: Node
var _grid: Node


func before_all() -> void:
	seed(12345)
	_main = load("res://scenes/main.tscn").instantiate()
	get_tree().root.add_child(_main)
	get_tree().current_scene = _main
	_units = _main.get_node("Units")
	_grid = _main.get_node("World/GridWorld")
	# Deterministic: no random storms (vision shrink) or terrain events.
	WeatherManager.set_weather_events_enabled(false)
	_grid.set_dynamic_events_enabled(false)


func after_all() -> void:
	WeatherManager.set_weather_events_enabled(true)
	_grid.set_dynamic_events_enabled(true)
	# Free immediately, not queue_free(): a queued free could still be pending
	# when the next test script instantiates its own main.tscn — the old
	# "Main" name would still be taken, the new scene would be renamed, and
	# every hard-coded /root/Main lookup would break.
	_main.free()


func before_each() -> void:
	AIBeliefSystem.reset()
	FactionManager.reset()


func after_each() -> void:
	_grid.set_reveal_all(ENEMY, false)
	# Autoload picks persist across tests by design: never leak them.
	FactionManager.set_player_faction("")
	FactionManager.enemy_faction_id = ""


func _spawn_unit(tres_path: String, team: int, pos: Vector2) -> Node2D:
	var unit: Node2D = load("res://scenes/unit.tscn").instantiate()
	unit.set("data", load(tres_path).duplicate(true))
	unit.set("team", team)
	unit.position = pos
	_units.add_child(unit)
	autofree(unit)
	return unit


func _building_for(team: int) -> Node2D:
	for b in get_tree().get_nodes_in_group("buildings"):
		if b.get("team") == team:
			return b
	return null


## A spot covered by the enemy building's vision (its 10-cell radius).
func _enemy_view_pos() -> Vector2:
	return _building_for(ENEMY).global_position + Vector2(-120, 0)


func test_beliefs_start_empty() -> void:
	assert_eq(AIBeliefSystem.get_believed_enemy_army(ENEMY), {}, "no units believed before any vision sweep")
	assert_eq(AIBeliefSystem.get_believed_cell(ENEMY, Vector2i(10, 5)), -1, "unseen cell is unknown (-1)")
	assert_eq(AIBeliefSystem.get_believed_faction(ENEMY), "unknown", "faction starts unknown")


func test_visible_cells_are_recorded() -> void:
	var pos := Vector2i(-9999, -9999)
	for x in range(2, 30):
		if _grid.get_cell(Vector2i(x, 3)) != null:
			pos = Vector2i(x, 3)
			break
	assert_ne(pos, Vector2i(-9999, -9999), "map must have a solid cell on the enemy side")
	_grid.set_reveal_all(ENEMY, true)
	AIBeliefSystem.update_belief_from_vision(ENEMY)
	assert_eq(AIBeliefSystem.get_believed_cell(ENEMY, pos), _grid.get_cell(pos).type,
		"a visible cell's type is copied into the belief map")


func test_seen_enemy_units_are_believed() -> void:
	_spawn_unit("res://scripts/resources/units/swordsman.tres", PLAYER, _enemy_view_pos())
	await wait_seconds(0.1)  # let the fog maps refresh (GridWorld._process)
	AIBeliefSystem.update_belief_from_vision(ENEMY)
	var army: Dictionary = AIBeliefSystem.get_believed_enemy_army(ENEMY)
	assert_eq(int(army.get("swordsman", 0)), 1, "a player unit inside enemy vision is believed")


func test_unseen_enemy_units_are_not_believed() -> void:
	# Far left of the map: no enemy vision source anywhere near.
	_spawn_unit("res://scripts/resources/units/swordsman.tres", PLAYER, Vector2(-1100, 16))
	AIBeliefSystem.update_belief_from_vision(ENEMY)
	var army: Dictionary = AIBeliefSystem.get_believed_enemy_army(ENEMY)
	assert_eq(int(army.get("swordsman", 0)), 0, "a unit outside enemy vision must not be believed")


func test_stale_beliefs_drop_out_of_the_army_estimate() -> void:
	_spawn_unit("res://scripts/resources/units/swordsman.tres", PLAYER, _enemy_view_pos())
	AIBeliefSystem.update_belief_from_vision(ENEMY)
	# Simulate intel gone stale (decay runs in the autoload's _process).
	for id in AIBeliefSystem._believed_units[ENEMY]:
		AIBeliefSystem._believed_units[ENEMY][id].confidence = 0.0
	var army: Dictionary = AIBeliefSystem.get_believed_enemy_army(ENEMY)
	assert_eq(int(army.get("swordsman", 0)), 0, "beliefs under the confidence floor no longer count")


func test_infer_faction_unknown_without_enough_sightings() -> void:
	_spawn_unit("res://scripts/resources/units/wizard.tres", PLAYER, _enemy_view_pos())
	AIBeliefSystem.update_belief_from_vision(ENEMY)
	assert_eq(AIBeliefSystem.infer_enemy_faction(ENEMY), "unknown", "fewer than 3 sightings is not a read")


func test_infer_faction_arcane_from_wizard_heavy_army() -> void:
	for i in range(3):
		_spawn_unit("res://scripts/resources/units/wizard.tres", PLAYER, _enemy_view_pos() + Vector2(i * 8, 0))
	await wait_seconds(0.1)  # let the fog maps refresh (GridWorld._process)
	AIBeliefSystem.update_belief_from_vision(ENEMY)
	assert_eq(AIBeliefSystem.infer_enemy_faction(ENEMY), "arcane", "many wizards read as Arcane")


func test_infer_faction_industrial_from_miner_swarm() -> void:
	for i in range(6):
		_spawn_unit("res://scripts/resources/units/miner.tres", PLAYER, _enemy_view_pos() + Vector2(i * 8, 0))
	await wait_seconds(0.1)  # let the fog maps refresh (GridWorld._process)
	AIBeliefSystem.update_belief_from_vision(ENEMY)
	assert_eq(AIBeliefSystem.infer_enemy_faction(ENEMY), "industrial", "a miner swarm reads as Industrial")


func test_infer_faction_brute_from_swordsman_mass() -> void:
	for i in range(2):
		_spawn_unit("res://scripts/resources/units/swordsman.tres", PLAYER, _enemy_view_pos() + Vector2(i * 8, 0))
	_spawn_unit("res://scripts/resources/units/archer.tres", PLAYER, _enemy_view_pos() + Vector2(24, 0))
	await wait_seconds(0.1)  # let the fog maps refresh (GridWorld._process)
	AIBeliefSystem.update_belief_from_vision(ENEMY)
	assert_eq(AIBeliefSystem.infer_enemy_faction(ENEMY), "brute", "a swordsman mass reads as Brute")


func test_identified_faction_beats_inference() -> void:
	FactionManager.set_player_faction("industrial")
	for i in range(3):
		_spawn_unit("res://scripts/resources/units/wizard.tres", PLAYER, _enemy_view_pos() + Vector2(i * 8, 0))
	AIBeliefSystem.update_belief_from_vision(ENEMY)
	FactionManager.identify_faction(PLAYER)
	assert_eq(AIBeliefSystem.infer_enemy_faction(ENEMY), "industrial",
		"once scouted, the true faction wins over the wizard heuristic")
	assert_eq(AIBeliefSystem.get_believed_faction(ENEMY), "industrial", "the truth is cached as the belief")
