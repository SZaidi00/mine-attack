extends GutTest

# Adaptive difficulty smoothing (opt-in main-menu checkbox): GameManager holds
# a mid-match offset in tier steps that interpolates the numeric difficulty
# modifiers between adjacent tier rows (smarts flips only on a full step), and
# the AI's smoothing evaluator nudges that offset from fog-honest signals —
# believed enemy army vs own fighters, income rates, own base HP — with
# hysteresis, easing off when clearly ahead and toughening up when clearly
# behind.

const PLAYER: int = 0
const ENEMY: int = 1

var _main: Node
var _units: Node
var _ai: Node
var _grid: Node


func before_all() -> void:
	seed(12345)
	_main = load("res://scenes/main.tscn").instantiate()
	get_tree().root.add_child(_main)
	get_tree().current_scene = _main
	_units = _main.get_node("Units")
	_ai = _main.get_node("AIController")
	_grid = _main.get_node("World/GridWorld")
	WeatherManager.set_weather_events_enabled(false)
	_grid.set_dynamic_events_enabled(false)


func after_all() -> void:
	WeatherManager.set_weather_events_enabled(true)
	_grid.set_dynamic_events_enabled(true)
	# Free immediately, not queue_free(): a queued free could still be pending
	# when the next test script instantiates its own main.tscn and every
	# hard-coded /root/Main lookup would break.
	_main.free()


func before_each() -> void:
	AIBeliefSystem.reset()
	_ai._smoothing._streak = 0  # hysteresis state must not leak between tests


func after_each() -> void:
	# Autoload state persists across tests by design: never leak picks or the
	# smoothing offset into the next test script.
	GameManager.set_difficulty(GameManager.Difficulty.NORMAL)
	GameManager.set_adaptive_difficulty(false)
	GameManager.reset()
	AIBeliefSystem.reset()


func _spawn_unit(tres_path: String, team: int, pos: Vector2) -> Node2D:
	var unit: Node2D = load("res://scenes/unit.tscn").instantiate()
	unit.set("data", load(tres_path).duplicate(true))
	unit.set("team", team)
	unit.position = pos
	_units.add_child(unit)
	autofree(unit)
	return unit


func _spawn_fighter(team: int, pos: Vector2) -> Node2D:
	return _spawn_unit("res://scripts/resources/units/swordsman.tres", team, pos)


func _building_for(team: int) -> Node2D:
	for b in get_tree().get_nodes_in_group("buildings"):
		if b.get("team") == team:
			return b
	return null


## A spot covered by the enemy building's vision (its 10-cell radius).
func _enemy_view_pos() -> Vector2:
	return _building_for(ENEMY).global_position + Vector2(-120, 0)


func _believe_player_fighters(n: int) -> void:
	for i in range(n):
		_spawn_fighter(PLAYER, _enemy_view_pos() + Vector2(0, i * 4))
	await wait_seconds(0.1)  # let the fog maps refresh (GridWorld._process)
	AIBeliefSystem.update_belief_from_vision(ENEMY)


# ─── Modifier interpolation (GameManager) ───

func test_zero_offset_returns_the_base_row() -> void:
	GameManager.set_difficulty(GameManager.Difficulty.NORMAL)
	assert_eq(GameManager.get_difficulty_modifiers(),
		GameManager.DIFFICULTY_MODIFIERS[GameManager.Difficulty.NORMAL],
		"offset 0 must return the chosen tier's row exactly")


func test_interpolation_halves_the_gap_to_the_next_tier() -> void:
	GameManager.set_difficulty(GameManager.Difficulty.NORMAL)
	GameManager.nudge_difficulty(0.5)
	var mods: Dictionary = GameManager.get_difficulty_modifiers()
	assert_almost_eq(mods.coin, 1.425, 0.001, "coin halfway between Normal (1.30) and Hard (1.55)")
	assert_almost_eq(mods.train_time, 0.875, 0.001, "train time halfway between Normal (0.95) and Hard (0.80)")
	assert_almost_eq(mods.wave, 0.925, 0.001, "wave tempo halfway between Normal (1.0) and Hard (0.85)")
	# Cached: a repeat read with no nudge returns the same table.
	assert_eq(GameManager.get_difficulty_modifiers(), mods)


func test_interpolation_works_toward_easier_tiers() -> void:
	GameManager.set_difficulty(GameManager.Difficulty.NORMAL)
	GameManager.nudge_difficulty(-0.5)
	assert_almost_eq(GameManager.get_difficulty_modifiers().coin, 1.1, 0.001,
		"coin halfway between Normal (1.30) and Easy (0.90)")


func test_nudges_clamp_at_one_step() -> void:
	GameManager.set_difficulty(GameManager.Difficulty.NORMAL)
	GameManager.nudge_difficulty(1.0)
	GameManager.nudge_difficulty(0.25)
	assert_eq(GameManager.get_difficulty_offset(), 1.0, "offset saturates at +1")
	GameManager.nudge_difficulty(-2.0)
	assert_eq(GameManager.get_difficulty_offset(), -1.0, "offset saturates at -1")


func test_effective_tier_clamps_at_the_table_edges() -> void:
	GameManager.set_difficulty(GameManager.Difficulty.EASY)
	GameManager.nudge_difficulty(-1.0)
	assert_almost_eq(GameManager.get_difficulty_modifiers().coin, 0.9, 0.001,
		"Easy cannot smooth below Easy")
	GameManager.set_difficulty(GameManager.Difficulty.GODLY)
	GameManager.nudge_difficulty(1.0)
	assert_almost_eq(GameManager.get_difficulty_modifiers().coin, 2.5, 0.001,
		"Godly cannot smooth above Godly")


func test_smarts_flips_only_at_a_full_half_step() -> void:
	GameManager.set_difficulty(GameManager.Difficulty.NORMAL)
	GameManager.nudge_difficulty(0.25)
	assert_eq(GameManager.get_difficulty_modifiers().smarts, 2,
		"behavior tier unchanged at a quarter step")
	GameManager.nudge_difficulty(0.25)
	assert_eq(GameManager.get_difficulty_modifiers().smarts, 3,
		"behavior tier takes the rounded effective tier's row at the half step")


func test_reset_zeroes_the_offset() -> void:
	GameManager.set_difficulty(GameManager.Difficulty.NORMAL)
	GameManager.nudge_difficulty(0.75)
	GameManager.reset()
	assert_eq(GameManager.get_difficulty_offset(), 0.0, "reset clears the smoothing offset")
	assert_eq(GameManager.get_difficulty_modifiers(),
		GameManager.DIFFICULTY_MODIFIERS[GameManager.Difficulty.NORMAL],
		"modifiers return to the chosen tier's row after reset")


# ─── Evaluator (ai_difficulty_smoothing.gd) ───

func test_evaluator_noop_when_adaptive_off() -> void:
	GameManager.set_difficulty(GameManager.Difficulty.NORMAL)
	GameManager.match_time = 120.0
	_ai._smoothing._run_smoothing()
	_ai._smoothing._run_smoothing()
	assert_eq(GameManager.get_difficulty_offset(), 0.0, "no nudges without the opt-in")


func test_evaluator_noop_during_grace_time() -> void:
	GameManager.set_difficulty(GameManager.Difficulty.NORMAL)
	GameManager.set_adaptive_difficulty(true)
	GameManager.match_time = Constants.SMOOTHING_GRACE_TIME - 1.0
	_ai._smoothing._run_smoothing()
	_ai._smoothing._run_smoothing()
	assert_eq(GameManager.get_difficulty_offset(), 0.0, "the opener plays out on the chosen tier")


func test_evaluator_ahead_eases_difficulty() -> void:
	GameManager.set_difficulty(GameManager.Difficulty.NORMAL)
	GameManager.set_adaptive_difficulty(true)
	GameManager.match_time = 120.0
	await _believe_player_fighters(2)
	for i in range(4):
		_spawn_fighter(ENEMY, Vector2(700 + i * 4, 16))  # 4 own vs 2 believed: army ahead
	_ai._ai_income_rate = 10.0
	_ai._player_income_rate = 1.0  # enemy out-earns the player: economy ahead
	_ai._smoothing._run_smoothing()
	assert_eq(GameManager.get_difficulty_offset(), 0.0, "first eval only opens the hysteresis streak")
	_ai._smoothing._run_smoothing()
	assert_eq(GameManager.get_difficulty_offset(), -Constants.SMOOTHING_STEP,
		"second consecutive ahead eval nudges one step easier")


func test_evaluator_behind_toughens_difficulty() -> void:
	GameManager.set_difficulty(GameManager.Difficulty.NORMAL)
	GameManager.set_adaptive_difficulty(true)
	GameManager.match_time = 120.0
	await _believe_player_fighters(10)
	_ai._ai_income_rate = 1.0
	_ai._player_income_rate = 10.0  # player out-earns the AI: economy behind
	var building: Node2D = _building_for(ENEMY)
	building.set("_hp", int(float(building.max_hp) * 0.3))  # base beaten up: base behind
	_ai._smoothing._run_smoothing()
	_ai._smoothing._run_smoothing()
	assert_eq(GameManager.get_difficulty_offset(), Constants.SMOOTHING_STEP,
		"behind on army + economy + base nudges one step harder after hysteresis")


func test_evaluator_neutral_verdict_resets_the_streak() -> void:
	GameManager.set_difficulty(GameManager.Difficulty.NORMAL)
	GameManager.set_adaptive_difficulty(true)
	GameManager.match_time = 120.0
	await _believe_player_fighters(10)
	_ai._ai_income_rate = 1.0
	_ai._player_income_rate = 10.0
	var building: Node2D = _building_for(ENEMY)
	building.set("_hp", int(float(building.max_hp) * 0.3))
	_ai._smoothing._run_smoothing()
	# Threat over: match the believed army in the field, even the income race,
	# and heal the base — every signal neutral.
	for i in range(10):
		_spawn_fighter(ENEMY, Vector2(700 + i * 4, 16))
	_ai._player_income_rate = 1.0
	building.set("_hp", building.max_hp)
	_ai._smoothing._run_smoothing()
	_ai._smoothing._run_smoothing()
	assert_eq(GameManager.get_difficulty_offset(), 0.0,
		"a neutral eval breaks the streak before any nudge happened")
