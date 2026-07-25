extends Node

enum Team { PLAYER, ENEMY }
enum Difficulty { EASY, NORMAL, HARD, NIGHTMARE }

# AI difficulty modifiers, keyed by Difficulty. Fair-play rule: multipliers
# modify rates, never rules — the AI uses identical unit stats, queue cap, and
# population cap at every difficulty.
#   coin:          multiplier on AI deposit income.
#   train_time:    multiplier on AI training durations (lower = faster).
#   upgrade_speed: multiplier on the AI economy decision rate.
#   push_ratio / defend_ratio: fighter-count ratios for the aggression level.
const DIFFICULTY_MODIFIERS: Dictionary = {
	Difficulty.EASY: { "coin": 0.8, "train_time": 1.0, "upgrade_speed": 0.7, "push_ratio": 2.0, "defend_ratio": 0.75 },
	Difficulty.NORMAL: { "coin": 1.0, "train_time": 1.0, "upgrade_speed": 1.0, "push_ratio": 1.5, "defend_ratio": 0.5 },
	Difficulty.HARD: { "coin": 1.2, "train_time": 0.9, "upgrade_speed": 1.2, "push_ratio": 1.3, "defend_ratio": 0.4 },
	Difficulty.NIGHTMARE: { "coin": 1.5, "train_time": 0.8, "upgrade_speed": 1.5, "push_ratio": 1.1, "defend_ratio": 0.25 },
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


func _process(delta: float) -> void:
	if game_active:
		match_time += delta


func declare_winner(winner: Team) -> void:
	if not game_active:
		return
	game_active = false
	game_over.emit(winner)


func reset() -> void:
	game_active = true
	match_time = 0.0
	# Note: difficulty is intentionally kept so Play Again preserves the choice.


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
