extends Node

# WeatherManager — surface weather events (Revamp Phase 5 + volcano event).
#
# Owns independent snowstorm and volcano state machines (each: idle → warning →
# active → idle, then rescheduled). The snowstorm applies vision/speed
# multipliers and exposure damage; the volcano rains meteors across the surface.
# All three random events (snowstorm, volcano, lava rising) can overlap.
#
# To avoid a fixed snowstorm → lava → volcano opening, reset() shuffles a shared
# deck of first-occurrence times; GridEvents reads the lava entry so all three
# events start in a random order. Recurring intervals in Constants overlap so
# the order stays unpredictable after the first wave.
#
# Like GridEvents (Phase 4), all timers accumulate game-time delta and the
# whole node is pausable, so warnings and active phases freeze on pause/game-over
# exactly like units and research. Random scheduling is gated by separate
# events_enabled flags — forced triggers (tests, debug) always work.
#
# Like the other autoloads, state survives scene reloads — hud.gd calls
# reset() on Play Again / Quit to Menu alongside GameManager/EconomyManager.

const _Constants = preload("res://scripts/autoload/constants.gd")
const _METEOR_SCENE: PackedScene = preload("res://scenes/effects/meteor.tscn")

signal weather_warning_started(seconds: float)
signal snowstorm_started
signal snowstorm_ended
signal volcano_warning_started(seconds: float)
signal volcano_started
signal volcano_ended

# Random event scheduling on/off; an in-flight warning or active phase always
# runs to completion either way.
var events_enabled: bool = true
var volcano_events_enabled: bool = true

# Game-time clock driving the schedule (seconds of active match time).
var _clock: float = 0.0
var _snow_next_at: float = 0.0
var _warning_left: float = 0.0
var _storm_left: float = 0.0

# Volcano schedule/state.
var _volcano_next_at: float = 0.0
var _volcano_warning_left: float = 0.0
var _volcano_active_left: float = 0.0
var _volcano_meteor_timer: float = 0.0
var _volcano_rumble_player: AudioStreamPlayer = null

# Exposure damage accrues fractionally and lands in 1-HP chunks; protection
# is re-evaluated on the same cadence so the frost tint follows movement.
var _tick_left: float = 0.0
var _damage_accum: Dictionary = {}  # unit instance_id -> float
# Units currently showing the frost overlay, cleared when the storm ends.
var _frosted_units: Dictionary = {}  # unit instance_id -> Unit

var _ice_crack_left: float = 0.0
var _storm_wind_player: AudioStreamPlayer = null

# Cached initial occurrence times for the three major random events. The deck
# is shuffled once per match so the first snowstorm, lava rise, and volcano
# eruption can arrive in any order instead of always snow → lava → volcano.
var _initial_event_times: Dictionary = {}


func _ready() -> void:
	reset()


func reset() -> void:
	_end_storm_wind()
	_end_volcano_rumble()
	_clear_frost()
	_clock = 0.0
	_warning_left = 0.0
	_storm_left = 0.0
	_damage_accum.clear()
	_generate_initial_event_times()
	_snow_next_at = _initial_event_times["snowstorm"]
	_volcano_next_at = _initial_event_times["volcano"]
	_volcano_warning_left = 0.0
	_volcano_active_left = 0.0
	_volcano_meteor_timer = 0.0


func _process(delta: float) -> void:
	if not GameManager.game_active:
		return
	_clock += delta

	# Snowstorm: warning countdown → storm (+ exposure damage) → reschedule.
	# These run regardless of events_enabled so a forced storm completes.
	if _warning_left > 0.0:
		_warning_left -= delta
		if _warning_left <= 0.0:
			_warning_left = 0.0
			_start_snowstorm()
	elif _storm_left > 0.0:
		_storm_left -= delta
		_tick_left -= delta
		if _tick_left <= 0.0:
			_tick_left = 0.25
			_apply_exposure_damage(0.25)
		_ice_crack_left -= delta
		if _ice_crack_left <= 0.0:
			_ice_crack_left = randf_range(2.0, 4.0)
			AudioManager.play("ice_crack", Vector2.INF, -10.0)
		if _storm_left <= 0.0:
			_storm_left = 0.0
			_end_snowstorm()
	elif events_enabled and _clock >= _snow_next_at:
		_start_snowstorm_warning()

	# Volcano: independent state machine. Can run at the same time as snowstorm
	# or lava rising.
	if _volcano_warning_left > 0.0:
		_volcano_warning_left -= delta
		if _volcano_warning_left <= 0.0:
			_volcano_warning_left = 0.0
			_start_volcano()
	elif _volcano_active_left > 0.0:
		_volcano_active_left -= delta
		_volcano_meteor_timer -= delta
		if _volcano_meteor_timer <= 0.0:
			_volcano_meteor_timer = _volcano_meteor_interval()
			_spawn_meteor()
		if _volcano_active_left <= 0.0:
			_volcano_active_left = 0.0
			_end_volcano()
	elif volcano_events_enabled and _clock >= _volcano_next_at:
		_start_volcano_warning()


# ─── Snowstorm ───

func is_snowstorm_warning() -> bool:
	return _warning_left > 0.0


func is_snowstorm_active() -> bool:
	return _storm_left > 0.0


func get_snowstorm_warning_remaining() -> float:
	return _warning_left


func get_snowstorm_remaining() -> float:
	return _storm_left


## Fog-of-war vision multiplier (Revamp Phase 5): a raging storm quarters
## every unit and lantern radius (buildings keep their full radius). Used for
## non-unit sources; unit-specific multipliers are below.
func get_vision_multiplier() -> float:
	if not is_snowstorm_active():
		return 1.0
	return clampf(_Constants.SNOWSTORM_VISION_MULT, 0.1, 1.0)


## Per-unit vision multiplier during storms. Dragons with Tempest Wings or
## Storm Dragon ignore the penalty; Storm Scout / Pathfinder raise the team's
## storm vision up to normal.
func get_unit_vision_multiplier(unit: Unit) -> float:
	if not is_snowstorm_active():
		return 1.0
	if unit.data.unit_name.to_lower() == "dragon" \
			and (ResearchManager.has_branch(unit.team, "tempest_wings") or ResearchManager.has_branch(unit.team, "storm_dragon")):
		return 1.0
	var mult: float = _Constants.SNOWSTORM_VISION_MULT + ResearchManager.get_stat_bonus(unit.team, "vision_in_storm_mult")
	return clampf(mult, 0.1, 1.0)


## Lantern vision multiplier during storms. Lanterns are affected like units,
## but Deep Fortress grants underground lanterns extra vision (handled in
## GridWorld's fog code).
func get_lantern_vision_multiplier(team: GameManager.Team) -> float:
	if not is_snowstorm_active():
		return 1.0
	var mult: float = _Constants.SNOWSTORM_VISION_MULT + ResearchManager.get_stat_bonus(team, "vision_in_storm_mult")
	return clampf(mult, 0.1, 1.0)


## True when the unit is immune to snowstorm movement, vision, and exposure
## penalties (Tempest Wings / Storm Dragon dragons).
func is_unit_weather_immune(unit: Unit) -> bool:
	if unit.data.unit_name.to_lower() != "dragon":
		return false
	return ResearchManager.has_branch(unit.team, "tempest_wings") or ResearchManager.has_branch(unit.team, "storm_dragon")


## Surface movement multiplier for the given unit/team. Underground units are
## sheltered. During a storm the base multiplier comes from the current
## difficulty and the team's Arctic Training research adds to it (capped at
## normal speed so the tech mitigates the penalty without outpacing clear weather).
## Tempest Wings / Storm Dragon dragons ignore the penalty entirely.
func get_speed_multiplier(unit = null) -> float:
	if not is_snowstorm_active():
		return 1.0
	var team: GameManager.Team = GameManager.Team.PLAYER
	if unit is Unit:
		if unit.is_underground or is_unit_weather_immune(unit):
			return 1.0
		team = unit.team
	elif unit is GameManager.Team:
		team = unit
	var mult: float = GameManager.get_snowstorm_speed_multiplier()
	mult += ResearchManager.get_stat_bonus(team, "snowstorm_speed")
	return clampf(mult, 0.1, 1.0)


## Random seconds until the next snowstorm, scaled by difficulty so storms hit
## more frequently on higher difficulties.
func _seconds_to_next_snowstorm() -> float:
	var interval_mult: float = GameManager.get_snowstorm_interval_multiplier()
	return randf_range(_Constants.SNOWSTORM_MIN_INTERVAL, _Constants.SNOWSTORM_MAX_INTERVAL) * interval_mult


## Generates one shuffled set of first-occurrence times for the three random
## events (snowstorm, lava rise, volcano eruption). Each match draws three
## staggered windows, shuffles which event lands in each window, and caches the
## result so WeatherManager and GridEvents agree on the opening order.
func _generate_initial_event_times() -> void:
	var windows: Array = [
		randf_range(45.0, 75.0),
		randf_range(70.0, 100.0),
		randf_range(95.0, 125.0),
	]
	windows.shuffle()
	_initial_event_times = {
		"snowstorm": windows[0],
		"lava": windows[1],
		"volcano": windows[2],
	}


## Returns the cached first-occurrence time for an event ("snowstorm", "lava",
## or "volcano"). GridEvents reads the lava entry during GridWorld._ready.
func get_initial_event_time(event_name: String) -> float:
	return _initial_event_times.get(event_name, -1.0)


func _start_snowstorm_warning() -> void:
	if _warning_left > 0.0 or _storm_left > 0.0:
		return
	# Weather Alert extends the warning for both teams (global forecast).
	var bonus: float = maxf(0.0, maxf(
		ResearchManager.get_stat_bonus(GameManager.Team.PLAYER, "weather_warning_bonus"),
		ResearchManager.get_stat_bonus(GameManager.Team.ENEMY, "weather_warning_bonus")))
	_warning_left = _Constants.SNOWSTORM_WARNING_TIME + bonus
	DebugLog.log_command("WeatherManager", "snowstorm_warning", "warning=%.0fs" % _warning_left)
	AudioManager.play("alarm", Vector2.INF, -6.0)
	weather_warning_started.emit(_warning_left)
	# Pathfinder: auto-recall friendly miners to the mine entry at warning time.
	if ResearchManager.has_branch(GameManager.Team.PLAYER, "pathfinder"):
		_recall_miners_to_shelter(GameManager.Team.PLAYER)
	if ResearchManager.has_branch(GameManager.Team.ENEMY, "pathfinder"):
		_recall_miners_to_shelter(GameManager.Team.ENEMY)


func _start_snowstorm() -> void:
	if _storm_left > 0.0:
		return
	_warning_left = 0.0
	# A snowstorm extinguishes any existing volcano fires.
	_extinguish_volcano_fires()
	# Stormcaller extends the storm duration if either team has it.
	var duration_bonus: float = maxf(0.0, maxf(
		ResearchManager.get_stat_bonus(GameManager.Team.PLAYER, "storm_duration_bonus"),
		ResearchManager.get_stat_bonus(GameManager.Team.ENEMY, "storm_duration_bonus")))
	_storm_left = _Constants.SNOWSTORM_DURATION + duration_bonus
	_tick_left = 0.0
	_ice_crack_left = 1.0
	DebugLog.log_command("WeatherManager", "snowstorm_started", "duration=%.0fs" % _storm_left)
	_start_storm_wind()
	snowstorm_started.emit()


func _end_snowstorm() -> void:
	_storm_left = 0.0
	_damage_accum.clear()
	DebugLog.log_command("WeatherManager", "snowstorm_ended", "")
	_end_storm_wind()
	_clear_frost()
	snowstorm_ended.emit()
	_snow_next_at = _clock + _seconds_to_next_snowstorm()


# ─── Volcano ───

func is_volcano_warning() -> bool:
	return _volcano_warning_left > 0.0


func is_volcano_active() -> bool:
	return _volcano_active_left > 0.0


func get_volcano_warning_remaining() -> float:
	return _volcano_warning_left


func get_volcano_remaining() -> float:
	return _volcano_active_left


## Random seconds until the next volcano eruption, scaled by difficulty.
func _seconds_to_next_volcano() -> float:
	var interval_mult: float = GameManager.get_volcano_interval_multiplier()
	return randf_range(_Constants.VOLCANO_MIN_INTERVAL, _Constants.VOLCANO_MAX_INTERVAL) * interval_mult


## Seconds between meteors during an eruption, scaled by difficulty.
func _volcano_meteor_interval() -> float:
	var rate_mult: float = GameManager.get_volcano_meteor_rate_multiplier()
	return _Constants.VOLCANO_METEOR_INTERVAL_BASE / maxf(0.1, rate_mult)


func _start_volcano_warning() -> void:
	if _volcano_warning_left > 0.0 or _volcano_active_left > 0.0:
		return
	_volcano_warning_left = _Constants.VOLCANO_WARNING_TIME
	DebugLog.log_command("WeatherManager", "volcano_warning", "warning=%.0fs" % _volcano_warning_left)
	AudioManager.play("volcano_warning", Vector2.INF, -6.0)
	volcano_warning_started.emit(_volcano_warning_left)
	_halve_lava_time()


func _start_volcano() -> void:
	if _volcano_active_left > 0.0:
		return
	_volcano_warning_left = 0.0
	var duration_mult: float = GameManager.get_volcano_duration_multiplier()
	_volcano_active_left = _Constants.VOLCANO_DURATION * duration_mult
	_volcano_meteor_timer = 0.0
	DebugLog.log_command("WeatherManager", "volcano_started", "duration=%.0fs" % _volcano_active_left)
	_start_volcano_rumble()
	volcano_started.emit()
	_spawn_meteor()


func _end_volcano() -> void:
	_volcano_active_left = 0.0
	DebugLog.log_command("WeatherManager", "volcano_ended", "")
	_end_volcano_rumble()
	volcano_ended.emit()
	_volcano_next_at = _clock + _seconds_to_next_volcano()


## Spawns a single meteor at a random surface x coordinate.
func _spawn_meteor() -> void:
	var grid: GridWorld = get_node_or_null("/root/Main/World/GridWorld")
	if grid == null:
		return
	var x_cell: int = randi_range(GridWorld.X_MIN, GridWorld.X_MAX)
	var target_pos: Vector2 = grid.grid_to_world(Vector2i(x_cell, 0))
	var meteor: Node = _METEOR_SCENE.instantiate()
	meteor.setup(target_pos, GameManager.get_volcano_damage_multiplier(), GameManager.get_volcano_duration_multiplier())
	# During a snowstorm, meteors deal impact damage but do not leave fire.
	meteor.leave_burn_patch = not is_snowstorm_active()
	get_tree().current_scene.add_child(meteor)


## When the volcano warning starts, accelerate any pending or current lava rise.
func _halve_lava_time() -> void:
	var grid: GridWorld = get_node_or_null("/root/Main/World/GridWorld")
	if grid != null and grid.has_method("halve_lava_remaining_time"):
		grid.halve_lava_remaining_time()


## HQ buildings are protected by default. This helper supports the commented-out
## higher-difficulty HQ damage logic.
func _should_damage_hq() -> bool:
	return false
	# Uncomment to enable HQ volcano damage on NIGHTMARE/GODLY:
	# return GameManager.difficulty == GameManager.Difficulty.NIGHTMARE or GameManager.difficulty == GameManager.Difficulty.GODLY


## Exposure damage to every surface unit. Underground units and buildings are
## unaffected. Damage scales with difficulty; Survival research reduces it;
## Stormcaller on the enemy team increases it; Tempest Wings / Storm Dragon
## dragons are immune. Exposed units also gain the frost overlay.
func _apply_exposure_damage(step: float) -> void:
	var seen: Dictionary = {}
	for unit in get_tree().get_nodes_in_group("units"):
		if unit._state == Unit.State.DEAD or unit.is_underground:
			continue
		var id: int = unit.get_instance_id()
		seen[id] = true
		if is_unit_weather_immune(unit):
			_set_frosted(unit, false)
			continue
		_set_frosted(unit, true)
		var damage_per_sec: float = _Constants.SNOWSTORM_DAMAGE_PER_SEC * GameManager.get_snowstorm_damage_multiplier()
		# Stormcaller on the *opposing* team makes this unit suffer more.
		var enemy_team: GameManager.Team = GameManager.Team.ENEMY if unit.team == GameManager.Team.PLAYER else GameManager.Team.PLAYER
		damage_per_sec *= (1.0 + ResearchManager.get_stat_bonus(enemy_team, "storm_exposure_enemy_mult"))
		# Survival research reduces environmental/snowstorm damage for the owning team.
		var reduction: float = ResearchManager.get_stat_bonus(unit.team, "environmental_damage_reduction") \
			+ ResearchManager.get_stat_bonus(unit.team, "snowstorm_damage_reduction")
		damage_per_sec *= maxf(0.0, 1.0 - reduction)
		var accum: float = _damage_accum.get(id, 0.0) + damage_per_sec * step
		var whole: int = int(accum)
		if whole > 0:
			accum -= whole
			# Environmental chip damage: no popups, no flee/retaliation reflex
			# — the unit keeps following its orders through the storm.
			unit.take_damage(whole, null, true)
		_damage_accum[id] = accum
	# Drop accumulators for units that died or left the surface.
	for id in _damage_accum.keys():
		if not seen.has(id):
			_damage_accum.erase(id)


## Pathfinder: when a storm warning begins, surface miners march to the team's
## mine entry (or building as a fallback). Underground miners are left alone
## (they are already sheltered from the storm).
func _recall_miners_to_shelter(team: GameManager.Team) -> void:
	var target: Node2D = _find_shelter_target(team)
	if target == null:
		return
	for unit in get_tree().get_nodes_in_group("units"):
		if unit.team != team or unit._state == Unit.State.DEAD or unit.is_underground:
			continue
		if not unit.data.is_miner:
			continue
		unit.call("move_to", target.global_position)


func _find_shelter_target(team: GameManager.Team) -> Node2D:
	var building: Node2D = null
	for b in get_tree().get_nodes_in_group("buildings"):
		if b.team == team:
			building = b
			break
	var entry: Node2D = null
	for e in get_tree().get_nodes_in_group("mine_entries"):
		if e.team == team:
			entry = e
			break
	if entry != null:
		return entry
	return building


func _set_frosted(unit: Unit, frosted: bool) -> void:
	if unit._frosted == frosted:
		return
	unit._frosted = frosted
	unit.queue_redraw()
	if frosted:
		_frosted_units[unit.get_instance_id()] = unit
	else:
		_frosted_units.erase(unit.get_instance_id())


func _clear_frost() -> void:
	for id in _frosted_units:
		# Units that died mid-storm linger here as freed instances. The
		# validity check must come before any typed assignment — assigning a
		# freed instance to a typed variable is itself an error.
		if not is_instance_valid(_frosted_units[id]):
			continue
		var unit: Unit = _frosted_units[id]
		unit._frosted = false
		unit.queue_redraw()
	_frosted_units.clear()


# ─── Storm audio ───

func _start_storm_wind() -> void:
	_end_storm_wind()
	_storm_wind_player = AudioStreamPlayer.new()
	_storm_wind_player.stream = AudioManager._streams.get("storm_wind")
	_storm_wind_player.bus = &"Ambient"
	# Howling wind sits above the calm ambient loop.
	_storm_wind_player.volume_db = 10.0
	add_child(_storm_wind_player)
	_storm_wind_player.play()


func _end_storm_wind() -> void:
	if _storm_wind_player != null:
		_storm_wind_player.queue_free()
		_storm_wind_player = null


# ─── Volcano audio ───

func _start_volcano_rumble() -> void:
	_end_volcano_rumble()
	_volcano_rumble_player = AudioStreamPlayer.new()
	_volcano_rumble_player.stream = AudioManager._streams.get("volcano_rumble")
	_volcano_rumble_player.bus = &"Ambient"
	_volcano_rumble_player.volume_db = 6.0
	add_child(_volcano_rumble_player)
	_volcano_rumble_player.play()


func _end_volcano_rumble() -> void:
	if _volcano_rumble_player != null:
		_volcano_rumble_player.queue_free()
		_volcano_rumble_player = null


## Free all volcano burn patches (called when a snowstorm starts).
func _extinguish_volcano_fires() -> void:
	for patch in get_tree().get_nodes_in_group("burning_grounds"):
		if patch.is_volcano_fire:
			patch.queue_free()


# ─── Test / debug hooks ───

## Random snowstorm scheduling on or off. Forced triggers below work either
## way; an in-flight warning or storm always completes.
func set_weather_events_enabled(enabled: bool) -> void:
	events_enabled = enabled


## Random volcano scheduling on or off. Forced triggers below work either way;
## an in-flight warning or eruption always completes.
func set_volcano_events_enabled(enabled: bool) -> void:
	volcano_events_enabled = enabled


func force_snowstorm_warning() -> void:
	_start_snowstorm_warning()


func force_snowstorm_start() -> void:
	_start_snowstorm()


func force_snowstorm_end() -> void:
	if _storm_left > 0.0:
		_end_snowstorm()


func force_volcano_warning() -> void:
	_start_volcano_warning()


func force_volcano_start() -> void:
	_start_volcano()


func force_volcano_end() -> void:
	if _volcano_active_left > 0.0:
		_end_volcano()
