extends GutTest

# Weather system (Revamp Phase 5): snowstorm warning → storm → end lifecycle,
# the vision/speed multipliers, lantern-shelter exposure damage with the frost
# overlay, and the Meteorological Array (weather_alert) warning extension.
# Random scheduling is disabled for the whole suite — every storm is forced.

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
	# No random weather mid-test: all storms below are forced.
	WeatherManager.set_weather_events_enabled(false)
	# Warm-up: the first test after boot gets ~0.4s of node _process starvation
	# in the headless harness, so let the scene settle first.
	await wait_seconds(0.6)


func after_all() -> void:
	# Free immediately, not queue_free(): a queued free could still be pending
	# when the next test script instantiates its own main.tscn and every
	# hard-coded /root/Main lookup would break.
	_main.free()
	WeatherManager.reset()
	WeatherManager.set_weather_events_enabled(true)


func before_each() -> void:
	EconomyManager.reset()
	ResearchManager.reset()
	GameManager.reset()
	# Clears any in-flight warning/storm, the frost overlays, and the wind.
	WeatherManager.reset()


func after_each() -> void:
	for lantern in get_tree().get_nodes_in_group("lanterns"):
		lantern.free()
	WeatherManager.reset()


func _spawn_unit(tres_path: String, team: int, pos: Vector2) -> Node2D:
	var unit: Node2D = load("res://scenes/unit.tscn").instantiate()
	unit.set("data", load(tres_path).duplicate(true))
	unit.set("team", team)
	unit.position = pos
	_units.add_child(unit)
	autofree(unit)
	return unit


func _build_surface_lantern(team: int, pos: Vector2) -> Lantern:
	var lantern: Lantern = load("res://scenes/lantern.tscn").instantiate()
	lantern.team = team
	lantern.position = pos
	_main.get_node("Structures").add_child(lantern)
	lantern._build_progress = 999.0
	lantern._process(0.1)
	return lantern


# ─── Storm lifecycle ───

func test_snowstorm_full_lifecycle() -> void:
	watch_signals(WeatherManager)
	WeatherManager.force_snowstorm_warning()
	assert_signal_emitted(WeatherManager, "weather_warning_started")
	assert_true(WeatherManager.is_snowstorm_warning(), "warning phase begins")
	assert_almost_eq(WeatherManager.get_snowstorm_warning_remaining(), Constants.SNOWSTORM_WARNING_TIME, 0.1)
	await wait_seconds(Constants.SNOWSTORM_WARNING_TIME + 0.4)
	assert_true(WeatherManager.is_snowstorm_active(), "storm starts when the warning expires")
	assert_signal_emitted(WeatherManager, "snowstorm_started")
	await wait_seconds(Constants.SNOWSTORM_DURATION + 0.5)
	assert_false(WeatherManager.is_snowstorm_active(), "storm ends after its duration")
	assert_signal_emitted(WeatherManager, "snowstorm_ended")


func test_weather_alert_research_extends_warning() -> void:
	ResearchManager._levels[PLAYER]["weather_alert"] = 1
	WeatherManager.force_snowstorm_warning()
	assert_almost_eq(WeatherManager.get_snowstorm_warning_remaining(), Constants.SNOWSTORM_WARNING_TIME_RESEARCH, 0.1)


func test_multipliers_only_during_storm() -> void:
	assert_eq(WeatherManager.get_vision_multiplier(), 1.0)
	assert_eq(WeatherManager.get_speed_multiplier(), 1.0)
	WeatherManager.force_snowstorm_start()
	assert_eq(WeatherManager.get_vision_multiplier(), Constants.SNOWSTORM_VISION_MULT)
	assert_eq(WeatherManager.get_speed_multiplier(), Constants.SNOWSTORM_SPEED_MULT)
	WeatherManager.force_snowstorm_end()
	assert_eq(WeatherManager.get_vision_multiplier(), 1.0)
	assert_eq(WeatherManager.get_speed_multiplier(), 1.0)


# ─── Vision reduction ───

func test_storm_halves_unit_and_lantern_vision() -> void:
	var swordsman: Node2D = _spawn_unit("res://scripts/resources/units/swordsman.tres", PLAYER, _grid.grid_to_world(Vector2i(-20, 0)))
	swordsman.stop()
	var lantern: Lantern = _build_surface_lantern(PLAYER, _grid.grid_to_world(Vector2i(-24, 0)))
	var unit_cell: Vector2i = _grid.world_to_grid(swordsman.global_position)
	var lantern_cell: Vector2i = _grid.world_to_grid(lantern.global_position)

	var base: Dictionary = {}
	for source in _grid._get_vision_sources(PLAYER):
		base[source[0]] = source[1]
	assert_eq(base.get(unit_cell), Constants.VISION_SWORDSMAN, "clear-weather swordsman radius")
	assert_eq(base.get(lantern_cell), Constants.LANTERN_T1_VISION, "clear-weather lantern radius")

	WeatherManager.force_snowstorm_start()
	var stormed: Dictionary = {}
	for source in _grid._get_vision_sources(PLAYER):
		stormed[source[0]] = source[1]
	assert_eq(stormed.get(unit_cell), int(Constants.VISION_SWORDSMAN * Constants.SNOWSTORM_VISION_MULT), "storm halves the swordsman radius")
	assert_eq(stormed.get(lantern_cell), int(Constants.LANTERN_T1_VISION * Constants.SNOWSTORM_VISION_MULT), "storm halves the lantern radius")
	WeatherManager.force_snowstorm_end()


# ─── Exposure damage ───

func test_storm_damages_exposed_surface_units_only() -> void:
	var exposed: Node2D = _spawn_unit("res://scripts/resources/units/swordsman.tres", PLAYER, _grid.grid_to_world(Vector2i(-20, 0)))
	exposed.stop()
	var sheltered_miner: Node2D = _spawn_unit("res://scripts/resources/units/miner.tres", PLAYER, _grid.grid_to_world(Vector2i(-5, 10)))
	sheltered_miner.is_underground = true
	WeatherManager.force_snowstorm_start()
	await wait_seconds(1.5)
	assert_lt(exposed.hp, exposed.data.max_hp, "exposed surface unit takes storm damage")
	assert_gt(exposed.hp, exposed.data.max_hp - 6, "storm damage is ~2 HP/s, not a burst")
	assert_true(exposed._frosted, "exposed unit shows the frost overlay")
	assert_eq(sheltered_miner.hp, sheltered_miner.data.max_hp, "underground units are unaffected")
	assert_false(sheltered_miner._frosted, "underground units get no frost overlay")
	WeatherManager.force_snowstorm_end()
	assert_false(exposed._frosted, "frost overlay clears when the storm ends")


func test_friendly_lantern_shelters_units_from_storm() -> void:
	_build_surface_lantern(PLAYER, _grid.grid_to_world(Vector2i(-20, 0)))
	var unit: Node2D = _spawn_unit("res://scripts/resources/units/swordsman.tres", PLAYER, _grid.grid_to_world(Vector2i(-19, 0)))
	unit.stop()
	WeatherManager.force_snowstorm_start()
	await wait_seconds(1.5)
	assert_eq(unit.hp, unit.data.max_hp, "a unit inside a friendly lantern's radius takes no storm damage")
	assert_false(unit._frosted, "sheltered unit shows no frost overlay")
	WeatherManager.force_snowstorm_end()


func test_storm_damage_does_not_make_miners_flee() -> void:
	# Regression: exposure damage went through the combat damage path, so every
	# tick re-triggered the miner flee reflex and miners froze at the mine
	# instead of just moving slower through the storm.
	var miner: Node2D = _spawn_unit("res://scripts/resources/units/miner.tres", PLAYER, _grid.grid_to_world(Vector2i(-20, 0)))
	miner.stop()
	WeatherManager.force_snowstorm_start()
	await wait_seconds(1.5)
	assert_lt(miner.hp, miner.data.max_hp, "exposed miner still takes storm damage")
	assert_eq(miner._flee_timer, 0.0, "storm damage never triggers the flee reflex")
	assert_false(miner._state == Unit.State.MOVE and miner._flee_target != Vector2.ZERO, "miner keeps its orders during the storm")
	WeatherManager.force_snowstorm_end()
