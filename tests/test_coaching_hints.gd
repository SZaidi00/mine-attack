extends GutTest

# CoachingHints.generate: pure-function coaching hints over the MatchStats
# summary shape. Synthetic summaries exercise each rule, the cap, and
# missing-key safety.

const CoachingHintsScript = preload("res://scripts/ui/coaching_hints.gd")


func _make_summary(overrides: Dictionary = {}) -> Dictionary:
	var summary: Dictionary = {
		"winner": "player",
		"duration_sec": 400,
		"player_max_tier": 3,
		"enemy_max_tier": 2,
		"teams": {
			"player": {"units_trained": 20, "units_lost": 6, "coin_mined": 1000, "damage_dealt": 5000},
			"enemy": {"units_trained": 18, "units_lost": 10, "coin_mined": 900, "damage_dealt": 3000},
		},
		"timeline": [
			{"t": 0, "player_base_hp": 1.0, "enemy_base_hp": 1.0},
			{"t": 200, "player_base_hp": 0.9, "enemy_base_hp": 0.5},
			{"t": 400, "player_base_hp": 1.0, "enemy_base_hp": 0.2},
		],
	}
	summary.merge(overrides, true)
	return summary


func _has(hints: Array[String], fragment: String) -> bool:
	for hint: String in hints:
		if hint.contains(fragment):
			return true
	return false


func test_balanced_match_returns_fallback_hint() -> void:
	var summary: Dictionary = _make_summary({
		"duration_sec": 100,
		"player_max_tier": 2,
		"teams": {
			"player": {"units_lost": 2, "coin_mined": 500, "damage_dealt": 100},
			"enemy": {"units_lost": 2, "coin_mined": 520, "damage_dealt": 100},
		},
		"timeline": [{"t": 0, "player_base_hp": 1.0, "enemy_base_hp": 1.0}],
	})
	var hints: Array[String] = CoachingHintsScript.generate(summary)
	assert_eq(hints.size(), 1, "no rule fires on a quiet match; fallback keeps one hint")
	assert_true(_has(hints, "log"), "fallback hint expected")


func test_out_mined_hint_shows_ratio() -> void:
	var summary: Dictionary = _make_summary({
		"winner": "enemy",
		"duration_sec": 500,
		"teams": {
			"player": {"units_lost": 5, "coin_mined": 1000},
			"enemy": {"units_lost": 4, "coin_mined": 2300},
		},
	})
	var hints: Array[String] = CoachingHintsScript.generate(summary)
	assert_true(_has(hints, "The enemy out-mined you 2.3:1"), "ratio text expected, got %s" % [hints])


func test_player_out_mined_hint_shows_ratio() -> void:
	var summary: Dictionary = _make_summary({
		"teams": {
			"player": {"units_lost": 4, "coin_mined": 3000},
			"enemy": {"units_lost": 5, "coin_mined": 1000},
		},
	})
	var hints: Array[String] = CoachingHintsScript.generate(summary)
	assert_true(_has(hints, "You out-mined the enemy 3.0:1"), "ratio text expected, got %s" % [hints])


func test_close_economy_skips_hint() -> void:
	var hints: Array[String] = CoachingHintsScript.generate(_make_summary())
	assert_false(_has(hints, "out-mined"), "1000 vs 900 is below the 1.5x threshold")


func test_base_damage_hint_shows_percent_and_time() -> void:
	var summary: Dictionary = _make_summary({
		"winner": "enemy",
		"duration_sec": 500,
		"player_max_tier": 3,
		"teams": {
			"player": {"units_lost": 5, "coin_mined": 1000},
			"enemy": {"units_lost": 4, "coin_mined": 900},
		},
		"timeline": [
			{"t": 0, "player_base_hp": 1.0, "enemy_base_hp": 1.0},
			{"t": 380, "player_base_hp": 0.34, "enemy_base_hp": 1.0},
			{"t": 500, "player_base_hp": 0.0, "enemy_base_hp": 1.0},
		],
	})
	var hints: Array[String] = CoachingHintsScript.generate(summary)
	assert_true(_has(hints, "Your base dropped to 0% HP at 8:20"), "final sample is the lowest, got %s" % [hints])


func test_base_damage_hint_uses_first_lowest_when_undefeated() -> void:
	# Player survived at 34% then recovered: the hint quotes the drop, not 0%.
	var summary: Dictionary = _make_summary({
		"winner": "enemy",
		"duration_sec": 500,
		"player_max_tier": 3,
		"teams": {
			"player": {"units_lost": 5, "coin_mined": 1000},
			"enemy": {"units_lost": 4, "coin_mined": 900},
		},
		"timeline": [
			{"t": 0, "player_base_hp": 1.0, "enemy_base_hp": 1.0},
			{"t": 380, "player_base_hp": 0.34, "enemy_base_hp": 1.0},
			{"t": 500, "player_base_hp": 0.8, "enemy_base_hp": 1.0},
		],
	})
	var hints: Array[String] = CoachingHintsScript.generate(summary)
	assert_true(_has(hints, "Your base dropped to 34% HP at 6:20"), "got %s" % [hints])


func test_winning_match_praises_base_pressure() -> void:
	var hints: Array[String] = CoachingHintsScript.generate(_make_summary())
	assert_true(_has(hints, "You had the enemy base down to 20% HP at 6:40"), "got %s" % [hints])


func test_healthy_bases_skip_hint() -> void:
	var summary: Dictionary = _make_summary({
		"timeline": [
			{"t": 0, "player_base_hp": 1.0, "enemy_base_hp": 1.0},
			{"t": 400, "player_base_hp": 0.95, "enemy_base_hp": 0.85},
		],
	})
	var hints: Array[String] = CoachingHintsScript.generate(summary)
	assert_false(_has(hints, "base"), "bases above 70% warrant no base hint")


func test_army_trade_hint_when_notably_negative() -> void:
	var summary: Dictionary = _make_summary({
		"winner": "enemy",
		"duration_sec": 500,
		"player_max_tier": 3,
		"teams": {
			"player": {"units_lost": 12, "coin_mined": 1000},
			"enemy": {"units_lost": 5, "coin_mined": 900},
		},
		"timeline": [{"t": 0, "player_base_hp": 1.0, "enemy_base_hp": 1.0}],
	})
	var hints: Array[String] = CoachingHintsScript.generate(summary)
	assert_true(_has(hints, "You traded 12 units for 5"), "got %s" % [hints])


func test_army_trade_hint_when_enemy_lost_none() -> void:
	var summary: Dictionary = _make_summary({
		"winner": "enemy",
		"duration_sec": 500,
		"player_max_tier": 3,
		"teams": {
			"player": {"units_lost": 4, "coin_mined": 1000},
			"enemy": {"units_lost": 0, "coin_mined": 900},
		},
		"timeline": [{"t": 0, "player_base_hp": 1.0, "enemy_base_hp": 1.0}],
	})
	var hints: Array[String] = CoachingHintsScript.generate(summary)
	assert_true(_has(hints, "You lost 4 units for none in return"), "got %s" % [hints])


func test_even_trades_skip_hint() -> void:
	var hints: Array[String] = CoachingHintsScript.generate(_make_summary())
	assert_false(_has(hints, "traded"), "6 for 10 is a winning trade")


func test_max_tier_hint_on_long_low_tech_match() -> void:
	var summary: Dictionary = _make_summary({
		"player_max_tier": 1,
		"duration_sec": 700,
		"teams": {
			"player": {"units_lost": 4, "coin_mined": 1000},
			"enemy": {"units_lost": 4, "coin_mined": 900},
		},
		"timeline": [{"t": 0, "player_base_hp": 1.0, "enemy_base_hp": 1.0}],
	})
	var hints: Array[String] = CoachingHintsScript.generate(summary)
	assert_true(_has(hints, "never researched past tier 1"), "got %s" % [hints])


func test_max_tier_hint_skipped_on_short_match() -> void:
	var summary: Dictionary = _make_summary({
		"player_max_tier": 1,
		"duration_sec": 200,
		"teams": {
			"player": {"units_lost": 4, "coin_mined": 1000},
			"enemy": {"units_lost": 4, "coin_mined": 900},
		},
		"timeline": [{"t": 0, "player_base_hp": 1.0, "enemy_base_hp": 1.0}],
	})
	var hints: Array[String] = CoachingHintsScript.generate(summary)
	assert_false(_has(hints, "researched"), "a 3-minute match is too short for the tech hint")


func test_fast_loss_hint() -> void:
	var summary: Dictionary = _make_summary({
		"winner": "enemy",
		"duration_sec": 180,
		"player_max_tier": 1,
		"teams": {
			"player": {"units_lost": 8, "coin_mined": 100},
			"enemy": {"units_lost": 2, "coin_mined": 150},
		},
		"timeline": [{"t": 0, "player_base_hp": 1.0, "enemy_base_hp": 1.0}],
	})
	var hints: Array[String] = CoachingHintsScript.generate(summary)
	assert_true(_has(hints, "You fell in under 5 minutes"), "got %s" % [hints])
	# The fast-loss hint is first: most impactful ordering.
	assert_true(hints[0].contains("fell in under 5 minutes"), "got %s" % [hints])


func test_missing_keys_do_not_crash() -> void:
	var hints: Array[String] = CoachingHintsScript.generate({})
	assert_eq(hints.size(), 1, "fallback covers the empty summary")
	var partial: Dictionary = _make_summary()
	partial.erase("timeline")
	partial.erase("player_max_tier")
	var hints2: Array[String] = CoachingHintsScript.generate(partial)
	assert_gt(hints2.size(), 0, "partial summary still yields hints")


func test_never_more_than_three_hints() -> void:
	# Every rule fires at once; the cap must hold and keep the first three.
	var summary: Dictionary = _make_summary({
		"winner": "enemy",
		"duration_sec": 200,
		"player_max_tier": 1,
		"teams": {
			"player": {"units_lost": 12, "coin_mined": 200},
			"enemy": {"units_lost": 3, "coin_mined": 1000},
		},
		"timeline": [{"t": 0, "player_base_hp": 1.0, "enemy_base_hp": 1.0}],
	})
	var hints: Array[String] = CoachingHintsScript.generate(summary)
	assert_lte(hints.size(), 3, "got %s" % [hints])
	assert_true(hints.size() >= 1)
	assert_true(_has(hints, "fell in under 5 minutes"), "most impactful first, got %s" % [hints])
