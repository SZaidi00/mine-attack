class_name AIDifficultySmoothing
extends RefCounted

## Adaptive difficulty smoothing (opt-in main-menu checkbox, bidirectional
## rubber band). Every SMOOTHING_EVAL_INTERVAL seconds past a grace time the
## evaluator scores how the match is going from intel the AI legitimately has:
##   army    — own live fighters vs the fog-honest believed enemy army
##             (AIBeliefSystem, confidence-flooded),
##   economy — own vs enemy coin-mined rates (the aggression tick's lookahead
##             samples, same true-totals precedent as the tier-2 timing attack),
##   base    — own building HP fraction.
## When at least SMOOTHING_SIGNAL_MIN of the 3 signals agree the AI is clearly
## ahead or behind, the verdict feeds a hysteresis streak; once the streak
## reaches SMOOTHING_HYSTERESIS evals the offset nudges one SMOOTHING_STEP per
## eval toward easier/harder (GameManager interpolates the numeric difficulty
## modifiers between adjacent tier rows; the smarts behavior tier only flips on
## a full step). The result: a match that would snowball either way instead
## ramps smoothly — fixed tiers become a starting point, not a straitjacket.

const _Constants = preload("res://scripts/autoload/constants.gd")

# Believed-enemy unit ids that count as army strength (matches data.is_fighter).
const _FIGHTER_IDS: Array = ["swordsman", "archer", "wizard", "dragon"]

var ai: AIController

# Consecutive same-direction verdicts: positive = ahead streak, negative =
# behind streak. Reset by a neutral eval or an opposite verdict.
var _streak: int = 0


func _init(a: AIController) -> void:
	ai = a


func _run_smoothing() -> void:
	if not GameManager.adaptive_difficulty:
		return
	if GameManager.match_time < _Constants.SMOOTHING_GRACE_TIME:
		return

	var ahead_signals: int = 0
	var behind_signals: int = 0

	# Army signal: own live fighters vs the believed enemy army.
	var own_fighters: int = 0
	for unit in ai.get_tree().get_nodes_in_group(ai._combat.team_name()):
		if unit.data.is_fighter and unit._state != Unit.State.DEAD:
			own_fighters += 1
	var believed_fighters: int = 0
	var believed: Dictionary = AIBeliefSystem.get_believed_enemy_army(ai.team)
	for unit_id in believed:
		if unit_id in _FIGHTER_IDS:
			believed_fighters += int(believed[unit_id])
	if believed_fighters <= 0:
		if own_fighters > 0:
			ahead_signals += 1
	elif float(own_fighters) >= float(believed_fighters) * _Constants.SMOOTHING_ARMY_AHEAD_RATIO:
		ahead_signals += 1
	elif float(own_fighters) <= float(believed_fighters) * _Constants.SMOOTHING_ARMY_BEHIND_RATIO:
		behind_signals += 1

	# Economy signal: enemy income rate over own (same shape as the tier-2
	# economic lookahead's ENEMY_ECON_PRESSURE_RATIO).
	var own_income: float = ai._ai_income_rate
	var their_income: float = ai._player_income_rate
	if own_income <= 0.0 and their_income <= 0.0:
		pass  # no read yet: neither side has mined since the last sample
	elif own_income <= 0.0 or their_income / own_income >= _Constants.SMOOTHING_INCOME_BEHIND_RATIO:
		behind_signals += 1
	elif their_income <= 0.0 or their_income / own_income <= _Constants.SMOOTHING_INCOME_AHEAD_RATIO:
		ahead_signals += 1

	# Base signal: own building beaten below the HP fraction reads as behind.
	# Winning is covered by the army + economy signals; no symmetric "ahead".
	var building: Node2D = ai._combat._get_building()
	if building != null:
		var hp_fraction: float = float(building.get("_hp")) / maxf(1.0, float(building.get("max_hp")))
		if hp_fraction < _Constants.SMOOTHING_BASE_HP_FRACTION:
			behind_signals += 1

	var verdict: int = 0  # +1 ahead (ease off), -1 behind (toughen up)
	if ahead_signals >= _Constants.SMOOTHING_SIGNAL_MIN:
		verdict = 1
	elif behind_signals >= _Constants.SMOOTHING_SIGNAL_MIN:
		verdict = -1

	if verdict == 0:
		_streak = 0
		return
	_streak = _streak + verdict if signi(_streak) == verdict else verdict
	if absi(_streak) < _Constants.SMOOTHING_HYSTERESIS:
		return
	DebugLog.log_command(
		"AIDifficultySmoothing",
		"eval",
		"ahead=%d behind=%d streak=%+d" % [ahead_signals, behind_signals, _streak]
	)
	# Ahead -> easier (negative offset); behind -> harder (positive offset).
	GameManager.nudge_difficulty(-_Constants.SMOOTHING_STEP * float(verdict))
