extends GutTest

# Production/completion toast wiring in hud.gd: base buildings connect at
# HUD._ready, runtime lanterns connect via SceneTree.node_added, miner spawns
# are filtered out, and enemy-side events never toast. Boots the real
# main.tscn; random events are disabled.

const PLAYER: int = 0  # GameManager.Team.PLAYER
const ENEMY: int = 1   # GameManager.Team.ENEMY

var _main: Node
var _hud: HUD


# The toast handler reads unit.team/unit.data reflectively; a plain Node2D
# would swallow set("data"), so the fake carries typed members.
class SpawnFake:
	extends Node2D
	var team: int = 0
	var data: UnitData = null


func before_all() -> void:
	seed(12345)
	_main = load("res://scenes/main.tscn").instantiate()
	get_tree().root.add_child(_main)
	get_tree().current_scene = _main
	_hud = _main.get_node("UI/HUD")
	WeatherManager.set_weather_events_enabled(false)
	WeatherManager.set_volcano_events_enabled(false)
	_main.get_node("World/GridWorld").set_dynamic_events_enabled(false)
	await get_tree().process_frame


func after_all() -> void:
	_main.free()


func before_each() -> void:
	GameManager.game_active = true
	for lantern in get_tree().get_nodes_in_group("lanterns"):
		if lantern.get("_upgrade_pending"):
			lantern.free()


func test_buildings_unit_spawned_wired_at_ready() -> void:
	for team: int in [PLAYER, ENEMY]:
		var building: Node2D = _building_for(team)
		assert_gt(building.unit_spawned.get_connections().size(), 0, "building %d wired" % team)


func test_unit_spawn_toasts_non_miners_only() -> void:
	var before: int = _live_toast_count()
	_emit_spawn("res://scripts/resources/units/miner.tres")
	assert_eq(_live_toast_count(), before, "miner spam is filtered out")
	_emit_spawn("res://scripts/resources/units/swordsman.tres")
	assert_eq(_live_toast_count(), before + 1, "swordsman spawn toasts")
	assert_true(_last_toast_text().contains("Swordsman ready"), "got %s" % _last_toast_text())


func test_enemy_unit_spawn_does_not_toast() -> void:
	var before: int = _live_toast_count()
	var unit: Node2D = _fake_unit("res://scripts/resources/units/swordsman.tres", ENEMY)
	_building_for(PLAYER).unit_spawned.emit(unit)
	assert_eq(_live_toast_count(), before, "enemy unit arriving at the player base is not a thing, but a mis-set team must not toast")
	unit.free()


func test_runtime_lantern_wires_via_node_added() -> void:
	var lantern: Lantern = Lantern.new()
	lantern.team = GameManager.Team.PLAYER
	_main.add_child(lantern)
	assert_gt(lantern.upgraded.get_connections().size(), 0, "node_added wiring connects the upgraded signal")
	lantern.free()


func test_lantern_upgrade_completion_toasts() -> void:
	var before: int = _live_toast_count()
	var lantern: Lantern = Lantern.new()
	lantern.team = GameManager.Team.PLAYER
	_main.add_child(lantern)
	lantern._is_built = true
	lantern.upgrade()
	assert_eq(lantern.tier, 2)
	lantern._build_progress = lantern.build_time
	await get_tree().process_frame
	assert_gt(_live_toast_count(), before, "upgrade completion toasts")
	assert_true(_last_toast_text().contains("Lantern upgraded to T2"), "got %s" % _last_toast_text())
	lantern.free()


func test_fresh_lantern_construction_does_not_toast_upgraded() -> void:
	var before: int = _live_toast_count()
	var lantern: Lantern = Lantern.new()
	lantern.team = GameManager.Team.PLAYER
	_main.add_child(lantern)
	lantern._build_progress = lantern.build_time
	await get_tree().process_frame
	assert_eq(_live_toast_count(), before, "fresh placement emits construction_complete, not upgraded")
	lantern.free()


func test_enemy_lantern_upgrade_does_not_toast() -> void:
	var before: int = _live_toast_count()
	var lantern: Lantern = Lantern.new()
	lantern.team = GameManager.Team.ENEMY
	_main.add_child(lantern)
	lantern._is_built = true
	lantern.upgrade()
	lantern._build_progress = lantern.build_time
	await get_tree().process_frame
	assert_eq(_live_toast_count(), before, "enemy upgrades never toast")
	lantern.free()


func _emit_spawn(tres_path: String) -> void:
	var unit: Node2D = _fake_unit(tres_path, PLAYER)
	_building_for(PLAYER).unit_spawned.emit(unit)
	unit.free()


func _fake_unit(tres_path: String, team: int) -> Node2D:
	var unit: SpawnFake = SpawnFake.new()
	unit.team = team
	unit.data = load(tres_path).duplicate(true)
	return unit


func _building_for(team: int) -> Node2D:
	for b in get_tree().get_nodes_in_group("buildings"):
		if b.get("team") == team:
			return b
	return null


func _toast_container() -> VBoxContainer:
	return _hud.get_node("ToastContainer")


func _live_toast_count() -> int:
	var n: int = 0
	for child in _toast_container().get_children():
		if not child.is_queued_for_deletion():
			n += 1
	return n


func _last_toast_text() -> String:
	var children: Array[Node] = _toast_container().get_children()
	if children.is_empty():
		return ""
	var labels: Array[Node] = children[-1].get_child(0).get_children()
	return labels[-1].text if not labels.is_empty() else ""
