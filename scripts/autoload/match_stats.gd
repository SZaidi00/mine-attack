extends Node

## MatchStats records per-match counters and a coarse coin/population timeline
## for the post-match summary (HUD game-over panel) and the JSON match log
## written at game over. It feeds balance analysis: every match leaves a file
## under user://match_logs/ that can be diffed across difficulties, factions,
## and AI openers.
##
## Lifecycle: HUD._ready calls reset() at the start of every match (mirroring
## the WeatherManager/AIBeliefSystem resets — GameManager.match_time has been
## accumulating through the main menu, so match start is the only honest
## zero point). The log is written once from GameManager.game_over. The
## finished summary stays in last_summary/last_log_path until the next reset()
## so the game-over panel can read it after the match ends.

const SAMPLE_INTERVAL: float = 5.0
const LOG_DIR: String = "user://match_logs"

# Match metadata captured at reset() (match start), after the main menu has
# set the difficulty, both factions, and the AI opener.
var difficulty: String = ""
var player_faction: String = ""
var enemy_faction: String = ""
var ai_opener: String = ""
# Adaptive difficulty smoothing: whether the main-menu checkbox was on, and
# the final smoothing offset (tier steps from the chosen difficulty) reached
# by match end — both feed the balance-analysis logs.
var adaptive_difficulty: bool = false

# Result of the last finalized match; empty until the first game over.
var last_summary: Dictionary = {}
var last_log_path: String = ""

var _units_lost: Dictionary = {}
var _damage_dealt: Dictionary = {}
var _timeline: Array = []
var _sample_elapsed: float = 0.0
# GameManager.match_time at reset(). The clock accumulates through the main
# menu (the menu's Play flow does not reset it), so durations and timeline
# timestamps are always relative to match start, never absolute.
var _start_time: float = 0.0


func _ready() -> void:
	GameManager.game_over.connect(_on_game_over)
	reset()


func _process(delta: float) -> void:
	if not GameManager.game_active:
		return
	# Only sample during a live match (same guard as EconomyManager: the main
	# menu has no Main node and no meaningful economy state).
	if get_tree().root.get_node_or_null("Main") == null:
		return
	_sample_elapsed += delta
	if _sample_elapsed >= SAMPLE_INTERVAL:
		_sample_elapsed = 0.0
		_sample_timeline()


func _sample_timeline() -> void:
	_timeline.append({
		"t": int(GameManager.match_time - _start_time),
		"player_coin": EconomyManager.get_coin(GameManager.Team.PLAYER),
		"enemy_coin": EconomyManager.get_coin(GameManager.Team.ENEMY),
		"player_pop": EconomyManager.get_population(GameManager.Team.PLAYER),
		"enemy_pop": EconomyManager.get_population(GameManager.Team.ENEMY),
	})


## Starts a fresh match's recording. Called from HUD._ready when the Main
## scene loads (match start), after the menu has made its picks.
func reset() -> void:
	difficulty = GameManager.Difficulty.keys()[GameManager.difficulty]
	adaptive_difficulty = GameManager.adaptive_difficulty
	ai_opener = GameManager.ai_opener
	var pf: FactionData = FactionManager.get_faction(GameManager.Team.PLAYER)
	var ef: FactionData = FactionManager.get_faction(GameManager.Team.ENEMY)
	player_faction = pf.faction_id if pf != null else ""
	enemy_faction = ef.faction_id if ef != null else ""
	_units_lost = {
		GameManager.Team.PLAYER: 0,
		GameManager.Team.ENEMY: 0,
	}
	_damage_dealt = {
		GameManager.Team.PLAYER: 0,
		GameManager.Team.ENEMY: 0,
	}
	_timeline = []
	_sample_elapsed = 0.0
	_start_time = GameManager.match_time
	_sample_timeline()  # t=0 baseline, so even short matches have a graph
	last_summary = {}
	last_log_path = ""


## Called from Unit._die() for every unit death, any cause (combat, lava,
## cave-in, disband). Disbands count as losses: the population slot is gone.
func record_unit_death(team: GameManager.Team) -> void:
	if _units_lost.is_empty():
		return
	_units_lost[team] += 1


## Called from unit take_damage with the post-armor damage amount. The
## attacker's team is credited; environmental chip damage passes no attacker.
func record_damage(attacker_team: GameManager.Team, amount: int) -> void:
	if _damage_dealt.is_empty():
		return
	_damage_dealt[attacker_team] += amount


func get_units_lost(team: GameManager.Team) -> int:
	return _units_lost.get(team, 0)


func get_damage_dealt(team: GameManager.Team) -> int:
	return _damage_dealt.get(team, 0)


## Builds the final per-match summary. Totals that EconomyManager already
## tracks (units trained, coin mined) are read at finalize time rather than
## double-counted here.
func build_summary(winner: GameManager.Team) -> Dictionary:
	var teams: Dictionary = {}
	for team: GameManager.Team in [GameManager.Team.PLAYER, GameManager.Team.ENEMY]:
		var key: String = "player" if team == GameManager.Team.PLAYER else "enemy"
		teams[key] = {
			"units_trained": EconomyManager.get_units_trained(team),
			"units_lost": get_units_lost(team),
			"coin_mined": EconomyManager.get_coin_mined(team),
			"damage_dealt": get_damage_dealt(team),
		}
	# Final data point at the moment of game over so the graphs always end at
	# the true match end, not up to SAMPLE_INTERVAL before it.
	var end_t: int = int(GameManager.match_time - _start_time)
	if _timeline.is_empty() or int(_timeline[-1].get("t", -1)) < end_t:
		_sample_timeline()
	return {
		"winner": "player" if winner == GameManager.Team.PLAYER else "enemy",
		"duration_sec": int(GameManager.match_time - _start_time),
		"difficulty": difficulty,
		"adaptive_difficulty": adaptive_difficulty,
		"difficulty_offset": GameManager.get_difficulty_offset(),
		"player_faction": player_faction,
		"enemy_faction": enemy_faction,
		"ai_opener": ai_opener,
		"teams": teams,
		"timeline": _timeline.duplicate(),
	}


## Writes the summary as JSON to user://match_logs/ and returns the path
## (empty string on failure — logging must never break the game-over flow).
func write_log(summary: Dictionary) -> String:
	var err: Error = DirAccess.make_dir_recursive_absolute(LOG_DIR)
	if err != OK:
		push_warning("MatchStats: could not create %s (error %d)" % [LOG_DIR, err])
		return ""
	var path: String = "%s/match_%d.json" % [LOG_DIR, Time.get_unix_time_from_system()]
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		push_warning("MatchStats: could not write %s (error %d)" % [path, FileAccess.get_open_error()])
		return ""
	file.store_string(JSON.stringify(summary, "  "))
	file.close()
	DebugLog.log_command("MatchStats", "write_log", path)
	return path


func _on_game_over(winner: GameManager.Team) -> void:
	last_summary = build_summary(winner)
	last_log_path = write_log(last_summary)
