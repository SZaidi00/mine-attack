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
#                  2: + counter-attack windows, miner raids, wave hunting and
#                     retreat, counter-composition army mix (NORMAL and up),
#                  3: currently the full suite — harder difficulties
#                     differentiate on rates, not extra behaviors.
#   wave:          attack-tempo multiplier (lower = earlier, more frequent
#                  waves); scales the wave size thresholds and the wave tick.
#   snowstorm_speed:   surface movement multiplier during snowstorms (lower on
#                  harder difficulties; the Arctic Training research can raise it).
#   snowstorm_interval: multiplier on the random snowstorm scheduling interval
#                  (lower = more frequent storms on harder difficulties).
#   snowstorm_damage:  multiplier on exposure damage dealt by active snowstorms
#                  (higher on harder difficulties).
const DIFFICULTY_MODIFIERS: Dictionary = {
	Difficulty.EASY: { "coin": 0.9, "train_time": 1.0, "upgrade_speed": 0.8, "push_ratio": 1.8, "defend_ratio": 0.8, "retaliation": 0.35, "smarts": 0, "wave": 1.15, "snowstorm_speed": 0.9, "snowstorm_interval": 1.2, "snowstorm_damage": 0.8, "volcano_interval": 1.25, "volcano_damage": 0.75, "volcano_duration": 0.9, "volcano_meteor_rate": 0.75 },
	Difficulty.NORMAL: { "coin": 1.15, "train_time": 0.95, "upgrade_speed": 1.15, "push_ratio": 1.4, "defend_ratio": 0.5, "retaliation": 0.6, "smarts": 2, "wave": 1.0, "snowstorm_speed": 0.8, "snowstorm_interval": 1.0, "snowstorm_damage": 1.0, "volcano_interval": 1.0, "volcano_damage": 1.0, "volcano_duration": 1.0, "volcano_meteor_rate": 1.0 },
	Difficulty.HARD: { "coin": 1.4, "train_time": 0.8, "upgrade_speed": 1.45, "push_ratio": 1.2, "defend_ratio": 0.35, "retaliation": 0.8, "smarts": 3, "wave": 0.85, "snowstorm_speed": 0.6, "snowstorm_interval": 0.8, "snowstorm_damage": 1.3, "volcano_interval": 0.8, "volcano_damage": 1.3, "volcano_duration": 1.15, "volcano_meteor_rate": 1.25 },
	Difficulty.NIGHTMARE: { "coin": 1.75, "train_time": 0.65, "upgrade_speed": 1.8, "push_ratio": 1.1, "defend_ratio": 0.2, "retaliation": 1.0, "smarts": 3, "wave": 0.7, "snowstorm_speed": 0.5, "snowstorm_interval": 0.65, "snowstorm_damage": 1.6, "volcano_interval": 0.65, "volcano_damage": 1.65, "volcano_duration": 1.25, "volcano_meteor_rate": 1.45 },
	Difficulty.GODLY: { "coin": 2.5, "train_time": 0.45, "upgrade_speed": 2.5, "push_ratio": 1.0, "defend_ratio": 0.15, "retaliation": 1.0, "smarts": 3, "wave": 0.55, "snowstorm_speed": 0.5, "snowstorm_interval": 0.5, "snowstorm_damage": 2.0, "volcano_interval": 0.55, "volcano_damage": 2.0, "volcano_duration": 1.35, "volcano_meteor_rate": 1.6 },
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
# Player-chosen game speed (1x/2x/3x/5x/10x). Like difficulty, survives reset()
# so Play Again keeps the choice. The win slow-mo overrides it temporarily.
var game_speed: float = 1.0
# Soft pause (separate from the tree-pausing pause menu): a temporary 0x speed
# the player can toggle from the HUD without bringing up the exit menu. It is
# cleared on match reset so Play Again does not start paused.
var soft_paused: bool = false
# Slow-mo end time (Time.get_ticks_msec()) after a win; -1 = not in slow-mo.
var _slowmo_end_msec: int = -1


func _process(delta: float) -> void:
	if game_active:
		match_time += delta
	if _slowmo_end_msec >= 0 and Time.get_ticks_msec() >= _slowmo_end_msec:
		_slowmo_end_msec = -1
		Engine.time_scale = 0.0 if soft_paused else game_speed


func declare_winner(winner: Team) -> void:
	if not game_active:
		return
	game_active = false
	# Cinematic slow-mo under the building collapse; restored after 1 real
	# second (wall clock, so it is independent of the time scale itself).
	Engine.time_scale = 0.3
	_slowmo_end_msec = Time.get_ticks_msec() + 1000
	game_over.emit(winner)


## Resets all per-match autoload state two frames after the caller's scene
## switch has completed. Resetting BEFORE the switch (while the old scene is
## still alive) emits EconomyManager/ResearchManager signals whose listeners
## queue deferred calls onto nodes the switch then frees mid-flush — which
## segfaulted macOS release builds on Quit to Menu / Restart.
## Difficulty and faction picks survive, as with the individual resets.
func reset_after_scene_switch() -> void:
	await get_tree().process_frame
	await get_tree().process_frame
	reset()
	FactionManager.reset()
	EconomyManager.reset()
	ResearchManager.reset()
	WeatherManager.reset()
	AIBeliefSystem.reset()


func reset() -> void:
	game_active = true
	match_time = 0.0
	_slowmo_end_msec = -1
	soft_paused = false
	Engine.time_scale = game_speed
	# Note: difficulty and game_speed are intentionally kept so Play Again
	# preserves both choices. soft_paused is cleared so Play Again never starts
	# in a paused state.


## Sets the player-chosen game speed. The value is always stored (so the win
## slow-mo and reset() restore it), but only applied live outside the slow-mo.
## Selecting a speed also clears a temporary soft pause.
func set_game_speed(speed: float) -> void:
	game_speed = speed
	DebugLog.log_command("GameManager", "set_game_speed", "%.2fx" % speed)
	if game_active and _slowmo_end_msec < 0:
		soft_paused = false
		Engine.time_scale = speed


## Toggles a temporary 0x pause without showing the pause menu. Cleared by
## selecting any speed, by reset(), or by toggling it off again.
func set_soft_paused(paused: bool) -> void:
	soft_paused = paused
	DebugLog.log_command("GameManager", "set_soft_paused", str(soft_paused))
	if game_active and _slowmo_end_msec < 0:
		Engine.time_scale = 0.0 if soft_paused else game_speed


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


## Attack-tempo multiplier: scales the AI's wave size thresholds and wave
## tick (lower = smaller, more frequent waves).
func get_ai_wave_multiplier() -> float:
	return get_difficulty_modifiers().wave


## Surface movement multiplier during snowstorms (lower on harder difficulties).
func get_snowstorm_speed_multiplier() -> float:
	return get_difficulty_modifiers().snowstorm_speed


## Snowstorm scheduling-interval multiplier (lower = more frequent storms).
func get_snowstorm_interval_multiplier() -> float:
	return get_difficulty_modifiers().snowstorm_interval


## Snowstorm exposure-damage multiplier (higher = more damage per second).
func get_snowstorm_damage_multiplier() -> float:
	return get_difficulty_modifiers().snowstorm_damage


## Volcano scheduling-interval multiplier (lower = more frequent eruptions).
func get_volcano_interval_multiplier() -> float:
	return get_difficulty_modifiers().volcano_interval


## Volcano meteor impact and burn-damage multiplier (higher = deadlier).
func get_volcano_damage_multiplier() -> float:
	return get_difficulty_modifiers().volcano_damage


## Volcano active-duration multiplier (higher = longer eruptions).
func get_volcano_duration_multiplier() -> float:
	return get_difficulty_modifiers().volcano_duration


## Volcano meteor spawn-rate multiplier (higher = more meteors per second).
func get_volcano_meteor_rate_multiplier() -> float:
	return get_difficulty_modifiers().volcano_meteor_rate
