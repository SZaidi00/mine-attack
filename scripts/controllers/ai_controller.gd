class_name AIController
extends Node

const _Constants = preload("res://scripts/autoload/constants.gd")

const AIEconomy = preload("res://scripts/controllers/ai_economy.gd")
const AIMining = preload("res://scripts/controllers/ai_mining.gd")
const AICombat = preload("res://scripts/controllers/ai_combat.gd")
const AISmartBehaviors = preload("res://scripts/controllers/ai_smart_behaviors.gd")
const AIAwareness = preload("res://scripts/controllers/ai_awareness.gd")

## Target army composition — the economy tick trains whichever type is
## furthest below its share, so the AI fields a mixed force (tanky frontline,
## ranged support, a few dragons) instead of a stream of swordsmen.
const _ARMY_MIX: Dictionary = { "swordsman": 0.4, "archer": 0.3, "wizard": 0.2, "dragon": 0.1 }

@export var team: GameManager.Team = GameManager.Team.ENEMY

var _economy_tick: float = 0.0
# True while a deferred _run_economy is queued, so rapid economy signals
# (deposits, upgrades) collapse into one tick instead of stacking up.
var _economy_tick_queued: bool = false
var _mining_tick: float = 0.0
var _mining_interval: float = 1.0
var _attack_tick: float = 0.0
var _aggression_tick: float = 0.0
var _aggression_interval: float = _Constants.ENEMY_AGGRESSION_INTERVAL
# Smart-behavior ticks (gated by the difficulty "smarts" tier).
var _tactics_tick: float = 0.0
var _harass_tick: float = 0.0
# Player fighter count at the previous aggression sample; a sharp drop opens
# a counter-attack window (smarts >= 2).
var _last_player_fighters: int = -1
# Bait-and-switch (smarts >= 2): a lone miner sent strolling toward the enemy
# base; the trap springs when enemy fighters come out to swat it.
var _bait_tick: float = 0.0
var _bait_miner: Unit = null
# Scout memory (smarts >= 3): exponential moving average of the enemy army's
# composition shares, resampled each aggression tick. The counter-composition
# mix reads the memory instead of the live count, so production counters the
# remembered army and doesn't jitter mid-fight.
var _player_comp_memory: Dictionary = {}
# Economic lookahead (smarts >= 2): coin-mined rates (per second) for both
# teams, resampled each aggression tick from EconomyManager totals.
var _player_income_rate: float = 0.0
var _ai_income_rate: float = 0.0
var _last_player_mined: int = -1
var _last_ai_mined: int = -1

# Awareness (Revamp Phase 8): scouting, lantern placement, weather response.
var _awareness_tick: float = 0.0
var _scout: Unit = null
var _next_scout_time: float = _Constants.ENEMY_SCOUT_TIME

var _aggression_level: String = "balanced"  # "defend", "balanced", "push"

@onready var _grid: GridWorld = get_node("/root/Main/World/GridWorld")

var _economy: AIEconomy
var _mining: AIMining
var _combat: AICombat
var _smart: AISmartBehaviors
var _awareness: AIAwareness


func _init() -> void:
	_economy = AIEconomy.new(self)
	_mining = AIMining.new(self)
	_combat = AICombat.new(self)
	_smart = AISmartBehaviors.new(self)
	_awareness = AIAwareness.new(self)


func _ready() -> void:
	# Pre-queued upgrades: re-run the economy the moment money lands or a
	# miner level completes instead of waiting out the decision tick.
	EconomyManager.coin_changed.connect(_on_economy_signal)
	EconomyManager.miner_level_changed.connect(_on_economy_signal)
	# Phase 8 weather/terrain response: same warnings the player gets.
	WeatherManager.weather_warning_started.connect(_awareness._on_snowstorm_warning)
	WeatherManager.snowstorm_ended.connect(_awareness._on_snowstorm_ended)
	WeatherManager.volcano_warning_started.connect(_awareness._on_volcano_warning)
	WeatherManager.volcano_ended.connect(_awareness._on_volcano_ended)
	_grid.lava_warning_started.connect(_awareness._on_lava_warning)
	_grid.lava_receded.connect(_awareness._on_lava_receded)


## Deferred economy re-tick: miner_level_changed fires from inside
## _run_economy itself (re-entrancy), and the queue shouldn't mutate mid-emit.
## The flag collapses repeat signals into one queued tick, and the tree check
## keeps a tick queued before a scene switch from running on a torn-down scene.
func _on_economy_signal(_signal_team: int) -> void:
	if GameManager.game_active and not _economy_tick_queued:
		_economy_tick_queued = true
		call_deferred("_run_economy")


func _process(delta: float) -> void:
	if not GameManager.game_active:
		return

	_economy_tick += delta
	# Upgrade speed scales the decision rate (higher difficulty = faster ticks).
	var economy_interval: float = _Constants.ENEMY_DECISION_INTERVAL / maxf(0.05, GameManager.get_ai_upgrade_speed())
	if _economy_tick >= economy_interval:
		_economy_tick = 0.0
		_economy._run_economy()

	_mining_tick += delta
	if _mining_tick >= _mining_interval:
		_mining_tick = 0.0
		_mining._run_mining()

	_attack_tick += delta
	# Wave tick scales with the difficulty attack tempo (higher difficulty
	# checks for a launch more often).
	var wave_interval: float = _Constants.ENEMY_ATTACK_WAVE_INTERVAL * GameManager.get_ai_wave_multiplier()
	if _attack_tick >= wave_interval:
		_attack_tick = 0.0
		_combat._run_attack_wave()

	_aggression_tick += delta
	if _aggression_tick >= _aggression_interval:
		_aggression_tick = 0.0
		_smart._update_aggression_level()

	_awareness_tick += delta
	if _awareness_tick >= 1.0:
		_awareness._run_awareness(_awareness_tick)
		_awareness_tick = 0.0

	var smarts: int = GameManager.get_ai_smarts()
	if smarts >= 1:
		_tactics_tick += delta
		if _tactics_tick >= 1.0:
			_tactics_tick = 0.0
			_smart._retreat_wounded()
			_smart._run_focus_fire()
	if smarts >= 2:
		_harass_tick += delta
		if _harass_tick >= _Constants.ENEMY_HARASS_INTERVAL:
			_harass_tick = 0.0
			_smart._run_harassment()
		_bait_tick += delta
		if _bait_tick >= _Constants.ENEMY_BAIT_INTERVAL:
			_bait_tick = 0.0
			_smart._run_bait()

	_combat._defend_building()
	_smart._apply_aggression_behavior()


# -----------------------------------------------------------------------------
# Thin wrappers — the public API is preserved by delegating to the helpers.
# -----------------------------------------------------------------------------

func _run_economy() -> void:
	_economy_tick_queued = false
	if not is_inside_tree():
		# Deferred tick landed after a scene switch tore the match down.
		return
	_economy._run_economy()


func _pick_fighter_to_train(budget: int) -> String:
	return _economy._pick_fighter_to_train(budget)


func _effective_army_mix() -> Dictionary:
	return _economy._effective_army_mix()


func _pick_research(_building: Node2D) -> String:
	return _economy._pick_research()


func _research_open(tech_id: String) -> bool:
	return _economy._research_open(tech_id)


func _cull_miners(n: int) -> void:
	_economy._cull_miners(n)


func _count_miners() -> int:
	return _economy._count_miners()


func _run_mining() -> void:
	_mining._run_mining()


func _find_best_ore(unit: Unit) -> Vector2i:
	return _mining._find_best_ore(unit)


func _is_busy(unit: Unit) -> bool:
	return _mining._is_busy(unit)


func _run_attack_wave() -> void:
	_combat._run_attack_wave()


func _launch_wave_if_ready(threshold_override: int = -1) -> void:
	_combat._launch_wave_if_ready(threshold_override)


func _wave_threshold(target: Node2D) -> int:
	return _combat._wave_threshold(target)


func _defend_building() -> void:
	_combat._defend_building()


func _pick_defense_target(defender: Unit) -> Unit:
	return _combat._pick_defense_target(defender)


func _attempt_wall_breach() -> void:
	_combat._attempt_wall_breach()


func _nearest_enemy_unit(pos: Vector2, max_dist: float) -> Unit:
	return _combat._nearest_enemy_unit(pos, max_dist)


func _get_building() -> Node2D:
	return _combat._get_building()


func _get_enemy_building() -> Node2D:
	return _combat._get_enemy_building()


func team_name() -> String:
	return _combat.team_name()


func _retreat_wounded() -> void:
	_smart._retreat_wounded()


func _is_wounded(unit: Unit, building: Node2D) -> bool:
	return _smart._is_wounded(unit, building)


func _run_focus_fire() -> void:
	_smart._run_focus_fire()


func _update_aggression_level() -> void:
	_smart._update_aggression_level()


func _sample_player_composition() -> void:
	_smart._sample_player_composition()


func _apply_aggression_behavior() -> void:
	_smart._apply_aggression_behavior()


func _run_harassment() -> void:
	_smart._run_harassment()


func _run_bait() -> void:
	_smart._run_bait()


func _run_awareness(delta: float = 1.0) -> void:
	_awareness._run_awareness(delta)


func _run_scouting() -> void:
	_awareness._run_scouting()


func _run_lantern_placement() -> void:
	_awareness._run_lantern_placement()


func _simulate_combat(duration: float = 2.0) -> float:
	return _smart._simulate_combat(duration)


func _sim_focus_step(attackers: Array, defenders: Array) -> void:
	_smart._sim_focus_step(attackers, defenders)


func _sim_apply_damage(defenders: Array, pool: float, include_air: bool) -> void:
	_smart._sim_apply_damage(defenders, pool, include_air)


func _sim_army_hp(army: Array) -> float:
	return _smart._sim_army_hp(army)
