extends Node

enum Team { PLAYER, ENEMY }
enum Difficulty { EASY, NORMAL, HARD, NIGHTMARE, GODLY }

# AI difficulty modifiers, keyed by Difficulty. Fair-play rule (EASY through
# NIGHTMARE): multipliers modify rates, never rules — the AI uses identical
# unit stats and population cap. GODLY deliberately abandons fair play: it
# gets every smart behavior plus openly stacked rates (double income, 40%
# faster training, near-constant aggression) to win by any means.
#   coin:          multiplier on AI deposit income.
#   train_time:    multiplier on AI training durations (lower = faster).
#   upgrade_speed: multiplier on the AI economy decision rate.
#   push_ratio / defend_ratio: fighter-count ratios for the aggression level.
#   retaliation:   chance a damaged AI sieger peels off to fight back.
#   smarts:        behavior tier (0-3) gating the AI's smart behaviors —
#                  1: focus-fire defense + wounded retreat,
#                  2: + counter-attack windows + miner harassment,
#                  3: + counter-composition army mix.
const DIFFICULTY_MODIFIERS: Dictionary = {
	Difficulty.EASY: { "coin": 0.8, "train_time": 1.0, "upgrade_speed": 0.7, "push_ratio": 2.0, "defend_ratio": 0.75, "retaliation": 0.25, "smarts": 0 },
	Difficulty.NORMAL: { "coin": 1.0, "train_time": 1.0, "upgrade_speed": 1.0, "push_ratio": 1.5, "defend_ratio": 0.5, "retaliation": 0.5, "smarts": 1 },
	Difficulty.HARD: { "coin": 1.2, "train_time": 0.9, "upgrade_speed": 1.2, "push_ratio": 1.3, "defend_ratio": 0.4, "retaliation": 0.7, "smarts": 2 },
	Difficulty.NIGHTMARE: { "coin": 1.5, "train_time": 0.8, "upgrade_speed": 1.5, "push_ratio": 1.1, "defend_ratio": 0.25, "retaliation": 0.9, "smarts": 3 },
	Difficulty.GODLY: { "coin": 2.0, "train_time": 0.6, "upgrade_speed": 2.0, "push_ratio": 1.0, "defend_ratio": 0.15, "retaliation": 1.0, "smarts": 3 },
}

const COLOR_PLAYER: Color = Color("#3B82F6")
const COLOR_ENEMY: Color = Color("#B91C1C")
const COLOR_ICE: Color = Color("#DCECF5")
const COLOR_STEEL: Color = Color("#5A6570")
const COLOR_RUST: Color = Color("#C45C26")
const COLOR_DEEP_ICE: Color = Color("#3E5A6E")
const COLOR_SHADOW: Color = Color("#1E252B")
const COLOR_DIRT_1: Color = Color("#8B6F47")
const COLOR_DIRT_2: Color = Color("#6B5637")
const COLOR_DIRT_3: Color = Color("#4A3B26")

signal game_over(winner: Team)

var game_active: bool = true
var match_time: float = 0.0
# AI difficulty for the current match. Set from the debug dropdown (Phase 6)
# or the main menu (Phase 7); survives reset() so Play Again keeps the choice.
var difficulty: Difficulty = Difficulty.NORMAL
# Player-chosen game speed (1x/2x/3x). Like difficulty, survives reset() so
# Play Again keeps the choice. The win slow-mo overrides it temporarily.
var game_speed: float = 1.0
# Slow-mo end time (Time.get_ticks_msec()) after a win; -1 = not in slow-mo.
var _slowmo_end_msec: int = -1


func _process(delta: float) -> void:
	if game_active:
		match_time += delta
	if _slowmo_end_msec >= 0 and Time.get_ticks_msec() >= _slowmo_end_msec:
		_slowmo_end_msec = -1
		Engine.time_scale = game_speed


func declare_winner(winner: Team) -> void:
	if not game_active:
		return
	game_active = false
	# Cinematic slow-mo under the building collapse; restored after 1 real
	# second (wall clock, so it is independent of the time scale itself).
	Engine.time_scale = 0.3
	_slowmo_end_msec = Time.get_ticks_msec() + 1000
	game_over.emit(winner)


func reset() -> void:
	game_active = true
	match_time = 0.0
	_slowmo_end_msec = -1
	Engine.time_scale = game_speed
	# Note: difficulty and game_speed are intentionally kept so Play Again
	# preserves both choices.


## Sets the player-chosen game speed. The value is always stored (so the win
## slow-mo and reset() restore it), but only applied live outside the slow-mo.
func set_game_speed(speed: float) -> void:
	game_speed = speed
	DebugLog.log_command("GameManager", "set_game_speed", "%gx" % speed)
	if game_active and _slowmo_end_msec < 0:
		Engine.time_scale = speed


func set_difficulty(d: Difficulty) -> void:
	difficulty = d
	DebugLog.log_command("GameManager", "set_difficulty", Difficulty.keys()[d])


func get_difficulty_modifiers() -> Dictionary:
	return DIFFICULTY_MODIFIERS[difficulty]


## AI deposit income multiplier (applied at the AI building's deposit point).
func get_ai_coin_multiplier() -> float:
	return get_difficulty_modifiers().coin


## AI training duration multiplier (lower = faster training).
func get_ai_train_time_multiplier() -> float:
	return get_difficulty_modifiers().train_time


## AI economy decision-rate multiplier (higher = faster decisions/upgrades).
func get_ai_upgrade_speed() -> float:
	return get_difficulty_modifiers().upgrade_speed


## Aggression thresholds: x = push ratio, y = defend ratio (fighter counts).
func get_aggression_thresholds() -> Vector2:
	var mods: Dictionary = get_difficulty_modifiers()
	return Vector2(mods.push_ratio, mods.defend_ratio)


## Per-hit chance a damaged AI sieger retaliates (see unit._maybe_retaliate).
func get_ai_retaliation_chance() -> float:
	return get_difficulty_modifiers().retaliation


## AI behavior tier (0-3) gating the smart behaviors in AIController.
func get_ai_smarts() -> int:
	return int(get_difficulty_modifiers().smarts)
