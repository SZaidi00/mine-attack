extends GutTest

# Threat alerts: damage to player miners / the player building reports a
# fading screen-edge arrow on the HUD with a globally throttled alert ping;
# environmental chip damage and enemy-team scuffles stay silent.

const PLAYER: int = 0
const ENEMY: int = 1

const SWORDSMAN: String = "res://scripts/resources/units/swordsman.tres"
const MINER: String = "res://scripts/resources/units/miner.tres"

var _main: Node
var _units: Node
var _hud: HUD


func before_all() -> void:
	seed(12345)
	_main = load("res://scenes/main.tscn").instantiate()
	get_tree().root.add_child(_main)
	get_tree().current_scene = _main
	_units = _main.get_node("Units")
	_hud = _main.get_node("UI/HUD")
	WeatherManager.set_weather_events_enabled(false)
	WeatherManager.set_volcano_events_enabled(false)
	_main.get_node("World/GridWorld").set_dynamic_events_enabled(false)
	await wait_seconds(0.1)


func after_all() -> void:
	_main.free()


func before_each() -> void:
	GameManager.game_active = true
	AudioManager._combat_intensity = 0.0
	_hud._threats.clear()
	_hud._ping_count = 0
	_hud._last_ping_msec = -100000


func test_report_threat_adds_arrow_and_pings() -> void:
	_hud.report_threat(Vector2(-500, 0), "miner")
	assert_eq(_hud._threats.size(), 1, "one active threat arrow")
	assert_eq(_hud._threats[0].kind, "miner", "threat keeps its kind")
	assert_eq(_hud._ping_count, 1, "the alert ping sounded")


func test_ping_is_throttled_but_arrows_accumulate() -> void:
	_hud.report_threat(Vector2(-500, 0), "miner")
	_hud.report_threat(Vector2(-600, 0), "miner")
	_hud.report_threat(Vector2(-700, 0), "base")
	assert_eq(_hud._threats.size(), 3, "every threat gets an arrow")
	assert_eq(_hud._ping_count, 1, "simultaneous threats share one ping")
	# Force the cooldown to have elapsed.
	_hud._last_ping_msec = Time.get_ticks_msec() - 10000
	_hud.report_threat(Vector2(-800, 0), "miner")
	assert_eq(_hud._ping_count, 2, "a later threat pings again")


func test_threats_fade_after_their_lifetime() -> void:
	_hud.report_threat(Vector2(-500, 0), "miner")
	assert_eq(_hud._threats.size(), 1)
	_hud._threats[0].age = HUD._THREAT_LIFETIME + 0.1
	_hud._update_threat_layer(0.1)
	assert_eq(_hud._threats.size(), 0, "expired threats are dropped")


func test_report_is_gated_on_game_active() -> void:
	GameManager.game_active = false
	_hud.report_threat(Vector2(-500, 0), "miner")
	assert_eq(_hud._threats.size(), 0, "no arrows once the match is over")
	assert_eq(_hud._ping_count, 0, "no ping once the match is over")


func test_player_miner_under_attack_reports_threat() -> void:
	var miner: Node2D = _spawn_unit(MINER, PLAYER, Vector2(-400, 16))
	var raider: Node2D = _spawn_unit(SWORDSMAN, ENEMY, Vector2(-380, 16))
	miner.take_damage(5, raider)
	assert_eq(_hud._threats.size(), 1, "miner damage raised an arrow")
	assert_eq(_hud._threats[0].kind, "miner", "miner threat kind")
	assert_gt(AudioManager.get_combat_intensity(), 0.0, "combat music pulsed")


func test_environmental_damage_reports_nothing() -> void:
	var miner: Node2D = _spawn_unit(MINER, PLAYER, Vector2(-400, 16))
	miner.take_damage(5, null, true)
	assert_eq(_hud._threats.size(), 0, "burn/storm ticks raise no arrow")
	assert_almost_eq(AudioManager.get_combat_intensity(), 0.0, 0.001,
		"environmental chip damage does not drive the combat music")


func test_enemy_miner_under_attack_reports_nothing() -> void:
	var miner: Node2D = _spawn_unit(MINER, ENEMY, Vector2(400, 16))
	var hunter: Node2D = _spawn_unit(SWORDSMAN, PLAYER, Vector2(380, 16))
	miner.take_damage(5, hunter)
	assert_eq(_hud._threats.size(), 0, "only PLAYER miners raise arrows")


func test_player_building_damage_reports_base_threat() -> void:
	var building: Node2D = null
	for b in get_tree().get_nodes_in_group("buildings"):
		if b.team == GameManager.Team.PLAYER:
			building = b
			break
	assert_not_null(building, "player building exists")
	building.take_damage(10)
	assert_eq(_hud._threats.size(), 1, "base damage raised an arrow")
	assert_eq(_hud._threats[0].kind, "base", "base threat kind")
	assert_almost_eq(AudioManager.get_combat_intensity(), 1.0, 0.001,
		"the base under attack pushes combat intensity to full")


# ─── Helpers ───

func _spawn_unit(tres_path: String, team: int, pos: Vector2) -> Node2D:
	var unit: Node2D = load("res://scenes/unit.tscn").instantiate()
	unit.set("data", load(tres_path).duplicate(true))
	unit.set("team", team)
	unit.position = pos
	_units.add_child(unit)
	autofree(unit)
	return unit
