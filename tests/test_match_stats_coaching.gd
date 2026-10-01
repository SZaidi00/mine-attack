extends GutTest

# MatchStats additions for coaching: base-HP fractions in the timeline samples
# and per-team max research tier in the summary. Boots the real main.tscn so
# the group lookups run against live buildings; random events are disabled.

const PLAYER: int = 0  # GameManager.Team.PLAYER
const ENEMY: int = 1   # GameManager.Team.ENEMY

var _main: Node


func before_all() -> void:
	seed(12345)
	_main = load("res://scenes/main.tscn").instantiate()
	get_tree().root.add_child(_main)
	get_tree().current_scene = _main
	WeatherManager.set_weather_events_enabled(false)
	WeatherManager.set_volcano_events_enabled(false)
	_main.get_node("World/GridWorld").set_dynamic_events_enabled(false)
	await get_tree().process_frame


func after_all() -> void:
	_main.free()


func before_each() -> void:
	EconomyManager.reset()
	ResearchManager.reset()
	GameManager.game_active = true
	MatchStats.reset()


func after_each() -> void:
	ResearchManager.reset()
	_heal_bases()


func test_timeline_samples_include_base_hp_fractions() -> void:
	var summary: Dictionary = MatchStats.build_summary(PLAYER)
	assert_gt(summary.timeline.size(), 0)
	for sample: Dictionary in summary.timeline:
		assert_true(sample.has("player_base_hp"), "every sample carries player_base_hp: %s" % [sample])
		assert_true(sample.has("enemy_base_hp"), "every sample carries enemy_base_hp: %s" % [sample])
		assert_gte(float(sample.player_base_hp), 0.0)
		assert_lte(float(sample.player_base_hp), 1.0)
		assert_gte(float(sample.enemy_base_hp), 0.0)
		assert_lte(float(sample.enemy_base_hp), 1.0)


func test_undamaged_bases_sample_full_health() -> void:
	var summary: Dictionary = MatchStats.build_summary(PLAYER)
	assert_eq(float(summary.timeline[0].player_base_hp), 1.0)
	assert_eq(float(summary.timeline[0].enemy_base_hp), 1.0)


func test_base_hp_fraction_tracks_damage() -> void:
	var building: Node2D = _building_for(PLAYER)
	var max_hp: int = int(building.get("max_hp"))
	building.set("_hp", max_hp / 2)
	MatchStats._sample_timeline()
	var timeline: Array = MatchStats.build_summary(PLAYER).timeline
	var frac: float = float(timeline[-1].player_base_hp)
	assert_almost_eq(frac, 0.5, 0.02, "damaged base samples as a fraction of max HP")


func test_summary_includes_max_tier_keys_defaulting_to_zero() -> void:
	var summary: Dictionary = MatchStats.build_summary(PLAYER)
	assert_true(summary.has("player_max_tier"))
	assert_true(summary.has("enemy_max_tier"))
	assert_eq(int(summary.player_max_tier), 0)
	assert_eq(int(summary.enemy_max_tier), 0)


func test_max_tier_reflects_highest_completed_tree_column() -> void:
	# crystal_forge sits at tree column 2 (tier 3); deep_delve at column 0.
	ResearchManager._levels[PLAYER]["crystal_forge"] = 1
	ResearchManager._levels[ENEMY]["deep_delve"] = 1
	var summary: Dictionary = MatchStats.build_summary(PLAYER)
	assert_eq(int(summary.player_max_tier), 3)
	assert_eq(int(summary.enemy_max_tier), 1)


func test_new_keys_survive_json_log_round_trip() -> void:
	var building: Node2D = _building_for(PLAYER)
	building.set("_hp", int(building.get("max_hp")) / 2)
	MatchStats._sample_timeline()
	var summary: Dictionary = MatchStats.build_summary(PLAYER)
	var path: String = MatchStats.write_log(summary)
	assert_ne(path, "")
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(path))
	assert_not_null(parsed)
	assert_true(parsed.has("player_max_tier"))
	assert_true(parsed.timeline[-1].has("player_base_hp"))
	DirAccess.remove_absolute(path)


func _building_for(team: int) -> Node2D:
	for b in get_tree().get_nodes_in_group("buildings"):
		if b.get("team") == team:
			return b
	return null


func _heal_bases() -> void:
	for team: int in [PLAYER, ENEMY]:
		var building: Node2D = _building_for(team)
		if building != null:
			building.set("_hp", building.get("max_hp"))
