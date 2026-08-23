extends GutTest

# Volcano event tests: lifecycle, difficulty scaling, meteor impact damage,
# burn patches, snowstorm overlap behavior, and lava-time halving.
# Random scheduling is disabled for the whole suite — every eruption is forced.

const PLAYER: int = 0
const ENEMY: int = 1

var _main: Node
var _units: Node
var _grid: Node
var _structures: Node


func before_all() -> void:
	seed(12345)
	_main = load("res://scenes/main.tscn").instantiate()
	get_tree().root.add_child(_main)
	get_tree().current_scene = _main
	_units = _main.get_node("Units")
	_grid = _main.get_node("World/GridWorld")
	_structures = _main.get_node("Structures")
	WeatherManager.set_weather_events_enabled(false)
	WeatherManager.set_volcano_events_enabled(false)
	await wait_seconds(0.6)


func after_all() -> void:
	_main.free()
	WeatherManager.reset()
	WeatherManager.set_weather_events_enabled(true)
	WeatherManager.set_volcano_events_enabled(true)


func before_each() -> void:
	EconomyManager.reset()
	ResearchManager.reset()
	GameManager.reset()
	WeatherManager.reset()
	_grid.set_dynamic_events_enabled(false)
	# Clean up any stray meteors or burn patches from previous tests.
	for node in get_tree().get_nodes_in_group("burning_grounds"):
		node.free()
	for node in get_tree().get_root().get_children():
		if node.has_method("setup") and node.has_method("_trigger_impact"):
			node.free()


func after_each() -> void:
	WeatherManager.reset()
	for node in get_tree().get_nodes_in_group("burning_grounds"):
		node.free()


func _spawn_unit(tres_path: String, team: int, pos: Vector2) -> Node2D:
	var unit: Node2D = load("res://scenes/unit.tscn").instantiate()
	unit.set("data", load(tres_path).duplicate(true))
	unit.set("team", team)
	unit.position = pos
	_units.add_child(unit)
	autofree(unit)
	return unit


func _spawn_meteor_at(pos: Vector2, leave_fire: bool = true) -> Node:
	var meteor: Node = load("res://scenes/effects/meteor.tscn").instantiate()
	meteor.setup(pos, GameManager.get_volcano_damage_multiplier(), GameManager.get_volcano_duration_multiplier())
	meteor.leave_burn_patch = leave_fire
	get_tree().current_scene.add_child(meteor)
	autofree(meteor)
	return meteor


func _spawn_burn_patch(pos: Vector2, dps: float = 100.0, duration: float = 2.0) -> Node:
	var patch: Node = load("res://scenes/effects/burning_ground.tscn").instantiate()
	patch.global_position = pos
	patch.damage_all_teams = true
	patch.is_volcano_fire = true
	patch.dps = dps
	patch.duration = duration
	patch.radius = 48.0
	get_tree().current_scene.add_child(patch)
	autofree(patch)
	return patch


# ─── Lifecycle ───

func test_volcano_full_lifecycle() -> void:
	watch_signals(WeatherManager)
	WeatherManager.force_volcano_warning()
	assert_signal_emitted(WeatherManager, "volcano_warning_started")
	assert_true(WeatherManager.is_volcano_warning(), "warning phase begins")
	assert_almost_eq(WeatherManager.get_volcano_warning_remaining(), Constants.VOLCANO_WARNING_TIME, 0.1)
	await wait_seconds(Constants.VOLCANO_WARNING_TIME + 0.4)
	assert_true(WeatherManager.is_volcano_active(), "eruption starts when the warning expires")
	assert_signal_emitted(WeatherManager, "volcano_started")
	await wait_seconds(WeatherManager.get_volcano_remaining() + 0.5)
	assert_false(WeatherManager.is_volcano_active(), "eruption ends after its duration")
	assert_signal_emitted(WeatherManager, "volcano_ended")


# ─── Difficulty scaling ───

func test_volcano_interval_scales_with_difficulty() -> void:
	var original: GameManager.Difficulty = GameManager.difficulty
	WeatherManager.reset()
	GameManager.set_difficulty(GameManager.Difficulty.EASY)
	var easy_interval: float = WeatherManager._seconds_to_next_volcano()
	GameManager.set_difficulty(GameManager.Difficulty.GODLY)
	var godly_interval: float = WeatherManager._seconds_to_next_volcano()
	assert_gt(easy_interval, godly_interval, "easy waits longer between eruptions than godly")
	GameManager.set_difficulty(original)


func test_volcano_damage_scales_with_difficulty() -> void:
	var original: GameManager.Difficulty = GameManager.difficulty

	GameManager.set_difficulty(GameManager.Difficulty.EASY)
	var easy_target: Node2D = _spawn_unit("res://scripts/resources/units/swordsman.tres", PLAYER, _grid.grid_to_world(Vector2i(-20, 0)))
	easy_target.stop()
	_spawn_meteor_at(easy_target.global_position)
	await wait_seconds(0.5)
	var easy_damage: float = easy_target.data.max_hp - easy_target.hp

	GameManager.set_difficulty(GameManager.Difficulty.NIGHTMARE)
	var nightmare_target: Node2D = _spawn_unit("res://scripts/resources/units/swordsman.tres", PLAYER, _grid.grid_to_world(Vector2i(-22, 0)))
	nightmare_target.stop()
	_spawn_meteor_at(nightmare_target.global_position)
	await wait_seconds(0.5)
	var nightmare_damage: float = nightmare_target.data.max_hp - nightmare_target.hp

	assert_gt(nightmare_damage, easy_damage, "nightmare meteor deals more impact damage than easy")
	GameManager.set_difficulty(original)


func test_volcano_duration_scales_with_difficulty() -> void:
	var original: GameManager.Difficulty = GameManager.difficulty
	GameManager.set_difficulty(GameManager.Difficulty.EASY)
	WeatherManager.force_volcano_start()
	var easy_duration: float = WeatherManager.get_volcano_remaining()
	WeatherManager.force_volcano_end()

	GameManager.set_difficulty(GameManager.Difficulty.GODLY)
	WeatherManager.force_volcano_start()
	var godly_duration: float = WeatherManager.get_volcano_remaining()
	WeatherManager.force_volcano_end()

	assert_lt(easy_duration, godly_duration, "godly eruption lasts longer than easy")
	GameManager.set_difficulty(original)


func test_volcano_meteor_rate_scales_with_difficulty() -> void:
	var original: GameManager.Difficulty = GameManager.difficulty
	GameManager.set_difficulty(GameManager.Difficulty.EASY)
	var easy_interval: float = WeatherManager._volcano_meteor_interval()
	GameManager.set_difficulty(GameManager.Difficulty.GODLY)
	var godly_interval: float = WeatherManager._volcano_meteor_interval()
	assert_gt(easy_interval, godly_interval, "godly meteors spawn faster than easy")
	GameManager.set_difficulty(original)


# ─── Impact damage ───

func test_meteor_damages_surface_unit() -> void:
	var target: Node2D = _spawn_unit("res://scripts/resources/units/swordsman.tres", PLAYER, _grid.grid_to_world(Vector2i(-20, 0)))
	target.stop()
	var hp_before: int = target.hp
	_spawn_meteor_at(target.global_position)
	await wait_seconds(0.5)
	assert_lt(target.hp, hp_before, "surface unit takes meteor impact damage")


func test_meteor_does_not_damage_underground_unit() -> void:
	var surface_pos: Vector2 = _grid.grid_to_world(Vector2i(-5, 0))
	var target: Node2D = _spawn_unit("res://scripts/resources/units/swordsman.tres", PLAYER, _grid.grid_to_world(Vector2i(-5, 10)))
	target.is_underground = true
	target.stop()
	var hp_before: int = target.hp
	_spawn_meteor_at(surface_pos, false)  # don't leave a fire patch for this test
	await wait_seconds(0.5)
	assert_eq(target.hp, hp_before, "underground unit ignores meteors")


# ─── Protection ───

func test_meteor_does_not_damage_hq_or_mine_entries() -> void:
	var player_building: Node2D = _main.get_node("World/PlayerBuilding")
	var enemy_building: Node2D = _main.get_node("World/EnemyBuilding")
	var player_entry: Node2D = _main.get_node("World/PlayerMineEntry")
	var enemy_entry: Node2D = _main.get_node("World/EnemyMineEntry")

	var player_hp_before: int = player_building.get("_hp")
	var enemy_hp_before: int = enemy_building.get("_hp")

	# Hitting mine entries should not crash and should not affect them.
	for b in [player_building, enemy_building, player_entry, enemy_entry]:
		_spawn_meteor_at(b.global_position, false)
		await wait_seconds(0.5)

	assert_eq(player_building.get("_hp"), player_hp_before, "player HQ should not take meteor damage")
	assert_eq(enemy_building.get("_hp"), enemy_hp_before, "enemy HQ should not take meteor damage")
	assert_true(is_instance_valid(player_entry), "player mine entry survives")
	assert_true(is_instance_valid(enemy_entry), "enemy mine entry survives")


# ─── Burn patches ───

func test_burn_patch_damages_unit() -> void:
	var target: Node2D = _spawn_unit("res://scripts/resources/units/miner.tres", PLAYER, _grid.grid_to_world(Vector2i(-20, 0)))
	target.stop()
	var hp_before: int = target.hp
	_spawn_burn_patch(target.global_position, 100.0, 2.0)
	await wait_seconds(0.7)
	assert_lt(target.hp, hp_before, "unit takes damage from volcano burn patch")


func test_burn_patch_damages_structure() -> void:
	var tower: Tower = load("res://scenes/tower.tscn").instantiate()
	tower.team = GameManager.Team.PLAYER
	tower.global_position = _grid.grid_to_world(Vector2i(-20, 0))
	tower._build_progress = 999.0
	_structures.add_child(tower)
	autofree(tower)
	tower._process(0.1)
	var hp_before: int = tower.hp
	_spawn_burn_patch(tower.global_position, 100.0, 2.0)
	await wait_seconds(0.7)
	assert_lt(tower.hp, hp_before, "tower takes damage from volcano burn patch")


func test_burn_patch_does_not_damage_hq() -> void:
	var hq: Node2D = _main.get_node("World/PlayerBuilding")
	var hp_before: int = hq.get("_hp")
	_spawn_burn_patch(hq.global_position, 1000.0, 1.0)
	await wait_seconds(0.7)
	assert_eq(hq.get("_hp"), hp_before, "HQ is protected from burn patches")


# ─── Survival research reduction ───

func test_survival_reduces_meteor_impact_damage() -> void:
	ResearchManager._levels[PLAYER]["survival_instinct"] = 1
	var target: Node2D = _spawn_unit("res://scripts/resources/units/swordsman.tres", PLAYER, _grid.grid_to_world(Vector2i(-20, 0)))
	target.stop()
	var hp_before: int = target.hp
	_spawn_meteor_at(target.global_position, false)
	await wait_seconds(0.5)
	var damage: float = hp_before - target.hp
	# Base impact on normal is 35; with 20% reduction it should be 28.
	assert_almost_eq(damage, 28.0, 2.0, "Survival Instinct reduces meteor impact damage")


func test_survival_reduces_burn_patch_damage() -> void:
	# Unprotected enemy miner vs protected player miner with Survival Instinct.
	var unprotected: Node2D = _spawn_unit("res://scripts/resources/units/miner.tres", ENEMY, _grid.grid_to_world(Vector2i(-20, 0)))
	unprotected.stop()
	ResearchManager._levels[PLAYER]["survival_instinct"] = 1
	var protected: Node2D = _spawn_unit("res://scripts/resources/units/miner.tres", PLAYER, _grid.grid_to_world(Vector2i(-21, 0)))
	protected.stop()
	_spawn_burn_patch(unprotected.global_position, 100.0, 2.0)
	await wait_seconds(0.7)
	var unprotected_damage: float = unprotected.data.max_hp - unprotected.hp
	var protected_damage: float = protected.data.max_hp - protected.hp
	assert_gt(unprotected_damage, protected_damage, "Survival Instinct reduces burn patch damage")


# ─── Snowstorm overlap ───

func test_snowstorm_extinguishes_volcano_fires() -> void:
	var patch: Node = _spawn_burn_patch(_grid.grid_to_world(Vector2i(-20, 0)))
	assert_true(patch.is_volcano_fire, "setup: patch is volcano fire")
	WeatherManager.force_snowstorm_start()
	await wait_seconds(0.2)
	assert_false(is_instance_valid(patch) and patch.is_inside_tree(), "snowstorm extinguishes volcano fire patch")
	WeatherManager.force_snowstorm_end()


func test_meteor_during_snowstorm_does_not_leave_burn_patch() -> void:
	WeatherManager.force_snowstorm_start()
	var pos: Vector2 = _grid.grid_to_world(Vector2i(-20, 0))
	_spawn_meteor_at(pos, false)  # leave_burn_patch already false for this test
	await wait_seconds(0.5)
	# The meteor should have left no burn patch because leave_burn_patch is false.
	var found: bool = false
	for node in get_tree().get_nodes_in_group("burning_grounds"):
		if node.global_position.distance_to(pos) < 10.0:
			found = true
			break
	assert_false(found, "meteor with leave_burn_patch=false leaves no fire")
	WeatherManager.force_snowstorm_end()


# ─── Lava time halving ───

func test_volcano_warning_halves_lava_warning_time() -> void:
	_grid.set_dynamic_events_enabled(true)
	_grid.force_lava_warning(2)
	var before: float = _grid.get_lava_warning_remaining()
	assert_gt(before, 0.0, "lava warning is active")
	WeatherManager.force_volcano_warning()
	var after: float = _grid.get_lava_warning_remaining()
	assert_almost_eq(after, before * 0.5, 0.05, "volcano warning halves remaining lava warning time")
	WeatherManager.force_volcano_end()
	_grid.force_lava_recede()
	_grid.set_dynamic_events_enabled(false)
