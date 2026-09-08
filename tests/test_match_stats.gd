extends GutTest

# MatchStats: per-match counters, summary building, timeline, and JSON log
# writing. Also covers MatchGraph's non-visual helpers.

const MatchGraph = preload("res://scripts/ui/match_graph.gd")

const PLAYER: int = 0  # GameManager.Team.PLAYER
const ENEMY: int = 1   # GameManager.Team.ENEMY


func before_each() -> void:
	EconomyManager.reset()
	MatchStats.reset()


func test_reset_zeroes_counters() -> void:
	MatchStats.record_unit_death(PLAYER)
	MatchStats.record_damage(ENEMY, 25)
	MatchStats.reset()
	assert_eq(MatchStats.get_units_lost(PLAYER), 0)
	assert_eq(MatchStats.get_damage_dealt(ENEMY), 0)


func test_unit_deaths_counted_per_team() -> void:
	MatchStats.record_unit_death(PLAYER)
	MatchStats.record_unit_death(PLAYER)
	MatchStats.record_unit_death(ENEMY)
	assert_eq(MatchStats.get_units_lost(PLAYER), 2)
	assert_eq(MatchStats.get_units_lost(ENEMY), 1)


func test_damage_credited_to_attacker_team() -> void:
	MatchStats.record_damage(PLAYER, 30)
	MatchStats.record_damage(PLAYER, 20)
	MatchStats.record_damage(ENEMY, 15)
	assert_eq(MatchStats.get_damage_dealt(PLAYER), 50)
	assert_eq(MatchStats.get_damage_dealt(ENEMY), 15)


func test_summary_pulls_economy_totals() -> void:
	EconomyManager.train_unit(PLAYER)
	EconomyManager.train_unit(PLAYER)
	EconomyManager.mine_coin(PLAYER, 120)
	MatchStats.record_unit_death(ENEMY)
	MatchStats.record_damage(PLAYER, 40)
	var summary: Dictionary = MatchStats.build_summary(PLAYER)
	assert_eq(summary.winner, "player")
	assert_eq(summary.teams.player.units_trained, 2)
	assert_eq(summary.teams.player.coin_mined, 120)
	assert_eq(summary.teams.player.damage_dealt, 40)
	assert_eq(summary.teams.enemy.units_lost, 1)


func test_summary_captures_metadata() -> void:
	GameManager.set_difficulty(GameManager.Difficulty.HARD)
	MatchStats.reset()
	var summary: Dictionary = MatchStats.build_summary(ENEMY)
	assert_eq(summary.winner, "enemy")
	assert_eq(summary.difficulty, "HARD")
	assert_eq(summary.ai_opener, "balanced", "tests keep the neutral opener")
	GameManager.set_difficulty(GameManager.Difficulty.NORMAL)


func test_write_log_produces_valid_json() -> void:
	var summary: Dictionary = MatchStats.build_summary(PLAYER)
	var path: String = MatchStats.write_log(summary)
	assert_ne(path, "", "log path expected")
	assert_true(FileAccess.file_exists(path))
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(path))
	assert_not_null(parsed, "log file must parse as JSON")
	assert_eq(parsed.winner, "player")
	assert_eq(parsed.teams.player.units_trained, 0)
	DirAccess.remove_absolute(path)


func test_game_over_finalizes_summary_and_log() -> void:
	# declare_winner guards on game_active; ensure a clean active match.
	GameManager.game_active = true
	MatchStats.record_unit_death(ENEMY)
	GameManager.declare_winner(PLAYER)
	assert_eq(MatchStats.last_summary.get("winner"), "player")
	assert_eq(MatchStats.last_summary.teams.enemy.units_lost, 1)
	assert_true(MatchStats.last_log_path != "", "log should be written on game over")
	assert_true(FileAccess.file_exists(MatchStats.last_log_path))
	DirAccess.remove_absolute(MatchStats.last_log_path)
	# declare_winner leaves the game inactive and the engine in win slow-mo;
	# reset() restores both for the next test.
	GameManager.reset()


func test_timeline_has_t_zero_baseline() -> void:
	var summary: Dictionary = MatchStats.build_summary(PLAYER)
	assert_gt(summary.timeline.size(), 0, "reset() records a t=0 baseline")
	assert_eq(int(summary.timeline[0].t), 0)


func test_timeline_and_duration_are_relative_to_match_start() -> void:
	# match_time accumulates through the main menu, so a match that starts at
	# t=100 and ends at t=165 lasted 65 seconds — not 165.
	var saved_time: float = GameManager.match_time
	GameManager.match_time = 100.0
	MatchStats.reset()
	GameManager.match_time = 165.0
	var summary: Dictionary = MatchStats.build_summary(PLAYER)
	assert_eq(summary.duration_sec, 65)
	assert_eq(int(summary.timeline[-1].t), 65, "final sample at match end")
	GameManager.match_time = saved_time


func test_build_summary_appends_match_end_point() -> void:
	var saved_time: float = GameManager.match_time
	GameManager.match_time = 200.0
	MatchStats.reset()
	GameManager.match_time = 237.0
	var summary: Dictionary = MatchStats.build_summary(PLAYER)
	assert_eq(summary.timeline.size(), 2, "t=0 baseline plus the match-end point")
	assert_eq(int(summary.timeline[1].t), 37)
	GameManager.match_time = saved_time


func test_match_graph_formats_axis_values() -> void:
	var graph := MatchGraph.new()
	assert_eq(graph._format_value(500), "500")
	assert_eq(graph._format_value(1234), "1.2k")
	graph.free()


func test_match_graph_ignores_mouse() -> void:
	var graph := MatchGraph.new([])
	assert_eq(graph.mouse_filter, Control.MOUSE_FILTER_IGNORE)
	graph.free()
