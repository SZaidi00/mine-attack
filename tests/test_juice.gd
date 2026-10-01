extends GutTest

# Juice pass: (1) GameManager.hit_stop briefly drops Engine.time_scale for a
# signature impact and restores game_speed (or the soft pause), yielding to the
# win slow-mo and the reduced-motion setting; a landed Brute dragon Crush
# (UnitAbilities.apply_stun) triggers it. (2) A raise-dead channel shows a
# sickly-green NecroChannelFX over the corpse and frees it when the channel
# ends (completion or interruption).

const PLAYER: int = 0
const ENEMY: int = 1

const SWORDSMAN: String = "res://scripts/resources/units/swordsman.tres"
const WIZARD: String = "res://scripts/resources/units/wizard.tres"
const DRAGON: String = "res://scripts/resources/units/dragon.tres"

var _main: Node
var _units: Node

var _prev_reduced_motion: bool = false
var _prev_faction: String = ""


func before_all() -> void:
	seed(12345)
	_prev_reduced_motion = SettingsManager.get_reduced_motion()
	_main = load("res://scenes/main.tscn").instantiate()
	get_tree().root.add_child(_main)
	get_tree().current_scene = _main
	_units = _main.get_node("Units")
	WeatherManager.set_weather_events_enabled(false)
	WeatherManager.set_volcano_events_enabled(false)
	_main.get_node("World/GridWorld").set_dynamic_events_enabled(false)
	var faction: FactionData = FactionManager.get_faction(GameManager.Team.PLAYER)
	_prev_faction = faction.faction_id if faction != null else ""
	await wait_seconds(0.1)


func after_all() -> void:
	SettingsManager.set_reduced_motion(_prev_reduced_motion)
	FactionManager.set_player_faction(_prev_faction)
	GameManager.set_game_speed(1.0)
	_main.free()


func before_each() -> void:
	GameManager.game_active = true
	GameManager._slowmo_end_msec = -1
	GameManager._hitstop_end_msec = -1
	GameManager.set_soft_paused(false)
	GameManager.set_game_speed(1.0)
	SettingsManager.set_reduced_motion(false)
	Engine.time_scale = 1.0
	for node in get_tree().get_nodes_in_group("corpses"):
		node.free()
	for node in get_tree().get_nodes_in_group("units"):
		if node.get("data") != null and node.get("data").is_undead:
			node.free()
	EconomyManager.reset()
	ResearchManager.reset()


# ─── Hit-stop ───

func test_hit_stop_drops_and_restores_time_scale() -> void:
	GameManager.hit_stop(0.3, 60.0)
	assert_almost_eq(Engine.time_scale, 0.3, 0.001, "time scale dropped")
	GameManager._hitstop_end_msec = Time.get_ticks_msec() - 1
	GameManager._process(0.0)
	assert_almost_eq(Engine.time_scale, 1.0, 0.001, "restored to game speed")


func test_hit_stop_restores_the_chosen_game_speed() -> void:
	GameManager.set_game_speed(2.0)
	GameManager.hit_stop(0.3, 60.0)
	assert_almost_eq(Engine.time_scale, 0.3, 0.001)
	GameManager._hitstop_end_msec = Time.get_ticks_msec() - 1
	GameManager._process(0.0)
	assert_almost_eq(Engine.time_scale, 2.0, 0.001, "restores the player's game speed")


func test_hit_stop_earliest_expiry_wins() -> void:
	GameManager.hit_stop(0.3, 60.0)
	GameManager.hit_stop(0.1, 120.0)
	assert_almost_eq(Engine.time_scale, 0.3, 0.001,
		"a longer-expiring hit-stop cannot override an active one")
	# A sooner-expiring one tightens the freeze.
	GameManager.hit_stop(0.5, 0.01)
	assert_almost_eq(Engine.time_scale, 0.5, 0.001, "an earlier-expiring hit-stop is adopted")


func test_hit_stop_skipped_under_reduced_motion() -> void:
	SettingsManager.set_reduced_motion(true)
	GameManager.hit_stop(0.3, 60.0)
	assert_almost_eq(Engine.time_scale, 1.0, 0.001, "reduced motion disables hit-stop")
	assert_eq(GameManager._hitstop_end_msec, -1, "no hit-stop scheduled")


func test_hit_stop_inactive_after_game_over() -> void:
	GameManager.game_active = false
	GameManager.hit_stop(0.3, 60.0)
	assert_almost_eq(Engine.time_scale, 1.0, 0.001, "no hit-stop once the match ended")
	GameManager.game_active = true


func test_crush_lands_a_hit_stop() -> void:
	FactionManager.set_player_faction("brute")
	var target: Node2D = _spawn_unit(SWORDSMAN, ENEMY, Vector2(-600, 16))
	# The Crush stun is UnitAbilities.apply_stun (called from the projectile
	# impact on a Brute dragon flame hit).
	target.call("apply_stun", 0.5)
	assert_almost_eq(target.get("_stun_timer"), 0.5, 0.001, "the stun applied")
	assert_almost_eq(Engine.time_scale, 0.35, 0.001, "the Crush hit-stop fired")
	GameManager._hitstop_end_msec = Time.get_ticks_msec() - 1
	GameManager._process(0.0)


# ─── Necro channel VFX ───

func test_channel_spawns_vfx_and_frees_on_completion() -> void:
	ResearchManager._levels[PLAYER]["necromancy"] = 1
	var s: Node2D = _spawn_unit(SWORDSMAN, PLAYER, Vector2(-400, 16))
	s.kill()
	var wiz: Node2D = _spawn_unit(WIZARD, PLAYER, Vector2(-430, 16))
	wiz.call("set_raise_mode", "troops")
	await _wait_for_fx(1)
	assert_eq(_fx_count(), 1, "channel VFX spawns over the corpse")
	await _wait_for_undead(PLAYER, 1)
	await wait_seconds(0.3)
	assert_eq(_fx_count(), 0, "VFX freed once the raise completes")


func test_channel_vfx_freed_on_interruption() -> void:
	ResearchManager._levels[PLAYER]["necromancy"] = 1
	var s: Node2D = _spawn_unit(SWORDSMAN, PLAYER, Vector2(-400, 16))
	s.kill()
	var wiz: Node2D = _spawn_unit(WIZARD, PLAYER, Vector2(-430, 16))
	wiz.call("set_raise_mode", "troops")
	await _wait_for_fx(1)
	assert_eq(_fx_count(), 1, "channel VFX spawned")
	wiz.call("move_to", Vector2(-700, 16))
	await _wait_for_fx(0)
	assert_eq(_fx_count(), 0, "VFX freed when the channel breaks")
	assert_eq(_undead_count(PLAYER), 0, "no raise from an interrupted channel")


# ─── Helpers ───

func _spawn_unit(tres_path: String, team: int, pos: Vector2) -> Node2D:
	var unit: Node2D = load("res://scenes/unit.tscn").instantiate()
	unit.set("data", load(tres_path).duplicate(true))
	unit.set("team", team)
	unit.position = pos
	_units.add_child(unit)
	autofree(unit)
	return unit


func _fx_count() -> int:
	var n: int = 0
	for node in get_tree().get_nodes_in_group("necro_channel_fx"):
		if not node.is_queued_for_deletion():
			n += 1
	return n


func _wait_for_fx(n: int) -> void:
	for i in range(30):
		await wait_seconds(0.2)
		if _fx_count() == n:
			return


func _undead_count(team: int) -> int:
	var n: int = 0
	for node in get_tree().get_nodes_in_group("units"):
		if node.get("data") != null and node.get("data").is_undead and node.team == team \
				and node.get("_state") != Unit.State.DEAD:
			n += 1
	return n


func _wait_for_undead(team: int, n: int) -> void:
	for i in range(30):
		await wait_seconds(0.5)
		if _undead_count(team) >= n:
			return
