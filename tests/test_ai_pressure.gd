extends GutTest

# AI pressure behaviors (smarts tier 2+): mine-entry raid upkeep and retreat,
# wave hunting (engage the field army en route), wave retreat/recall, the
# post-defense counterattack, desperation lowering the launch threshold, and
# the combat predictor seeing remembered towers. Formation/tier-gating of
# raids is covered in test_ai_smarts.gd.

const PLAYER: int = 0
const ENEMY: int = 1

var _main: Node
var _units: Node
var _ai: Node
var _grid: Node


func before_all() -> void:
	# Deterministic map: Constants.DEBUG is off (so GridWorld doesn't seed
	# itself), but the tests assert against specific layouts.
	seed(12345)
	_main = load("res://scenes/main.tscn").instantiate()
	get_tree().root.add_child(_main)
	get_tree().current_scene = _main
	_units = _main.get_node("Units")
	_ai = _main.get_node("AIController")
	_grid = _main.get_node("World/GridWorld")
	# Flush the buildings' deferred starting-miner spawns so tests run against
	# the real match-start state (2 miners per side).
	await get_tree().process_frame


func after_all() -> void:
	# Free immediately, not queue_free(): a queued free could still be pending
	# when the next test script instantiates its own main.tscn and every
	# hard-coded /root/Main lookup would break.
	_main.free()


func before_each() -> void:
	EconomyManager.reset()
	ResearchManager.reset()
	_ai._raiders.clear()
	_ai._aggression_level = "balanced"
	_ai._last_wave_desperate = false
	_ai._base_threatened = false
	_ai._last_wave_launched_at = GameManager.match_time
	_grid.set_reveal_all(ENEMY, false)


func after_each() -> void:
	# GameManager is an autoload: never leak a difficulty choice into the
	# next test script.
	GameManager.set_difficulty(GameManager.Difficulty.NORMAL)
	_grid.set_reveal_all(ENEMY, false)


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


## Forms a real raid (9 fighters > threshold 7 + 2 on Normal) and returns it.
func _form_raid() -> Array:
	GameManager.set_difficulty(GameManager.Difficulty.NORMAL)
	_ai._aggression_level = "balanced"
	for i in range(9):
		_spawn_fighter(ENEMY, Vector2(700 + i * 8, 16))
	_ai._run_harassment()
	return _ai._raiders.duplicate()


func _raid_camp() -> Vector2:
	var entry: Node2D = null
	for e in get_tree().get_nodes_in_group("mine_entries"):
		if e.get("team") == PLAYER:
			entry = e
	return entry.get_surface_position().lerp(_building_for(PLAYER).global_position, 0.35)


# ─── Raid upkeep ───

func test_raid_retreats_when_outnumbered_at_camp() -> void:
	var raiders: Array = _form_raid()
	assert_eq(raiders.size(), Constants.ENEMY_RAID_SIZE, "scenario needs a formed raid")
	var camp: Vector2 = _raid_camp()
	for r in raiders:
		r.position = camp
	# The defense converges: more fighters than raiders + the slack.
	for i in range(Constants.ENEMY_RAID_SIZE + Constants.ENEMY_RAID_RETREAT_ODDS):
		_spawn_fighter(PLAYER, camp + Vector2(i * 12, 0))
	_ai._manage_raid()
	assert_true(_ai._raiders.is_empty(), "an outnumbered raid must disband")
	var home: Node2D = _building_for(ENEMY)
	for r in raiders:
		assert_lt(r.get("_post_point").distance_to(home.global_position), 400.0,
			"retreating raiders must head home, not trade 3 fighters for a miner")


func test_raid_disbands_after_max_duration() -> void:
	var raiders: Array = _form_raid()
	assert_eq(raiders.size(), Constants.ENEMY_RAID_SIZE, "scenario needs a formed raid")
	_ai._raid_started_at = GameManager.match_time - Constants.ENEMY_RAID_MAX_DURATION - 1.0
	_ai._manage_raid()
	assert_true(_ai._raiders.is_empty(), "a stale raid must come home and re-form later")


func test_raid_disbands_when_army_flips_to_defend() -> void:
	var raiders: Array = _form_raid()
	assert_eq(raiders.size(), Constants.ENEMY_RAID_SIZE, "scenario needs a formed raid")
	_ai._aggression_level = "defend"
	_ai._manage_raid()
	assert_true(_ai._raiders.is_empty(), "raiding is not a defend-mode activity")


# ─── Wave hunting ───

func test_wave_hunts_visible_field_army_en_route() -> void:
	GameManager.set_difficulty(GameManager.Difficulty.NORMAL)
	_grid.set_reveal_all(ENEMY, true)  # stand-in for scouted intel
	_ai._aggression_level = "balanced"  # threshold 7
	var wave: Array = []
	for i in range(7):
		wave.append(_spawn_fighter(ENEMY, Vector2(700 + i * 8, 16)))
	# A visible player fighter just in front of the gathering wave.
	var field_army: Node2D = _spawn_fighter(PLAYER, Vector2(600, 16))
	# An eighth AI fighter far from the action has nothing in hunt range.
	var far: Node2D = _spawn_fighter(ENEMY, Vector2(-500, 16))
	_ai._launch_wave_if_ready()
	for f in wave:
		assert_eq(f.get("_target_unit"), field_army, "the wave must fight the army it meets on the way")
	assert_eq(far.get("_target_building"), _building_for(PLAYER),
		"fighters with no visible enemy in hunt range still march on the base")


func test_wave_beelines_when_no_field_army_visible() -> void:
	GameManager.set_difficulty(GameManager.Difficulty.NORMAL)
	_ai._aggression_level = "balanced"
	var wave: Array = []
	for i in range(7):
		wave.append(_spawn_fighter(ENEMY, Vector2(700 + i * 8, 16)))
	_ai._launch_wave_if_ready()
	for f in wave:
		assert_eq(f.get("_target_building"), _building_for(PLAYER),
			"nothing visible to hunt: the wave marches on the base")


# ─── Wave retreat / recall ───

func test_losing_wave_retreats_home() -> void:
	GameManager.set_difficulty(GameManager.Difficulty.NORMAL)
	var wave: Array = []
	for i in range(4):
		wave.append(_spawn_fighter(ENEMY, Vector2(700 + i * 8, 16)))
	for f in wave:
		f.attack_building(_building_for(PLAYER))
	# The player masses far away (no base threat): the sim says the wave is
	# being wiped.
	for i in range(15):
		_spawn_fighter(PLAYER, Vector2(-400 - i * 8, 16))
	_ai._last_wave_launched_at = GameManager.match_time - 10.0  # aged past the minimum
	_ai._retreat_losing_wave()
	var home: Node2D = _building_for(ENEMY)
	for f in wave:
		assert_eq(f._state, Unit.State.MOVE, "a wiped wave must pull out, not fight to zero")
		assert_lt(f.get("_post_point").distance_to(home.global_position), 400.0,
			"retreating fighters regroup at the base")


func test_desperate_wave_never_retreats() -> void:
	GameManager.set_difficulty(GameManager.Difficulty.NORMAL)
	var wave: Array = []
	for i in range(4):
		wave.append(_spawn_fighter(ENEMY, Vector2(700 + i * 8, 16)))
	for f in wave:
		f.attack_building(_building_for(PLAYER))
	for i in range(15):
		_spawn_fighter(PLAYER, Vector2(-400 - i * 8, 16))
	_ai._last_wave_launched_at = GameManager.match_time - 10.0
	_ai._last_wave_desperate = true  # it went in knowing the odds — it commits
	_ai._retreat_losing_wave()
	for f in wave:
		assert_eq(f._state, Unit.State.ATTACK, "desperate waves deal damage and die trying")


func test_winning_wave_does_not_retreat() -> void:
	GameManager.set_difficulty(GameManager.Difficulty.NORMAL)
	var wave: Array = []
	for i in range(8):
		wave.append(_spawn_fighter(ENEMY, Vector2(700 + i * 8, 16)))
	for f in wave:
		f.attack_building(_building_for(PLAYER))
	_spawn_fighter(PLAYER, Vector2(-400, 16))
	_spawn_fighter(PLAYER, Vector2(-408, 16))
	_ai._last_wave_launched_at = GameManager.match_time - 10.0
	_ai._retreat_losing_wave()
	for f in wave:
		assert_eq(f._state, Unit.State.ATTACK, "a winning wave keeps sieging")


func test_wave_recalls_when_base_under_attack() -> void:
	GameManager.set_difficulty(GameManager.Difficulty.NORMAL)
	# The wave is already deep on the player side (>700px from home) when the
	# intruder shows up.
	var wave: Array = []
	for i in range(4):
		wave.append(_spawn_fighter(ENEMY, Vector2(-400 - i * 8, 16)))
	for f in wave:
		f.attack_building(_building_for(PLAYER))
	# A raider on mission and a home guard: recall must not strip either.
	var raider: Node2D = _spawn_fighter(ENEMY, Vector2(-450, 16))
	raider.attack_building(_building_for(PLAYER))
	_ai._raiders.append(raider)
	var guard: Node2D = _spawn_fighter(ENEMY, Vector2(720, 16))
	# Intruder next to the enemy base (within the 650 defense radius).
	_spawn_fighter(PLAYER, Vector2(800, 16))
	_ai._retreat_losing_wave()
	for f in wave:
		assert_eq(f._state, Unit.State.MOVE, "the wave comes home when the base burns")
	assert_eq(raider._state, Unit.State.ATTACK, "the raid squad keeps its mission")
	assert_eq(guard._state, Unit.State.IDLE, "units already home are the defense sweep's job")
	_ai._raiders.clear()


# ─── Post-defense counterattack ───

func test_counterattack_fires_when_threat_clears() -> void:
	GameManager.set_difficulty(GameManager.Difficulty.NORMAL)
	var fighters: Array = []
	for i in range(5):
		fighters.append(_spawn_fighter(ENEMY, Vector2(700 + i * 8, 16)))
	var attacker: Node2D = _spawn_fighter(PLAYER, Vector2(800, 16))  # inside the defense radius
	_ai._check_defense_counterattack()
	assert_true(_ai._base_threatened, "the threat must register while attackers are inside the radius")
	for f in fighters:
		assert_null(f.get("_target_building"), "no counterattack while the fight at the base is live")
	attacker.kill()  # defense won — the attackers are dead (fled reads the same)
	_ai._check_defense_counterattack()
	for f in fighters:
		assert_eq(f.get("_target_building"), _building_for(PLAYER),
			"a cleared threat must trigger an immediate counterattack")


func test_no_counterattack_without_threat() -> void:
	GameManager.set_difficulty(GameManager.Difficulty.NORMAL)
	var fighters: Array = []
	for i in range(5):
		fighters.append(_spawn_fighter(ENEMY, Vector2(700 + i * 8, 16)))
	_ai._check_defense_counterattack()
	for f in fighters:
		assert_null(f.get("_target_building"), "a quiet base opens no counterattack window")


# ─── Desperation threshold floor ───

func test_desperation_lowers_the_launch_threshold() -> void:
	GameManager.set_difficulty(GameManager.Difficulty.NORMAL)
	_ai._aggression_level = "defend"  # threshold 12 — unreachable on a bad economy
	var fighters: Array = []
	for i in range(4):
		fighters.append(_spawn_fighter(ENEMY, Vector2(700 + i * 8, 16)))
	for i in range(20):
		_spawn_fighter(PLAYER, Vector2(-400 - i * 8, 16))
	# No wave has marched for longer than the desperation delay.
	_ai._last_wave_launched_at = GameManager.match_time \
		- Constants.ENEMY_WAVE_DESPERATION_DELAY * GameManager.get_ai_wave_multiplier() - 1.0
	_ai._launch_wave_if_ready()
	for f in fighters:
		assert_eq(f.get("_target_building"), _building_for(PLAYER),
			"a desperate AI below the defend threshold must still raid with what it has")


func test_outmatched_ai_holds_below_threshold_when_not_desperate() -> void:
	GameManager.set_difficulty(GameManager.Difficulty.NORMAL)
	_ai._aggression_level = "defend"  # threshold 12
	var fighters: Array = []
	for i in range(4):
		fighters.append(_spawn_fighter(ENEMY, Vector2(700 + i * 8, 16)))
	_ai._launch_wave_if_ready()
	for f in fighters:
		assert_null(f.get("_target_building"), "4 fighters never launch against the defend threshold")


# ─── Combat predictor: towers count ───

func test_sim_counts_remembered_enemy_towers() -> void:
	GameManager.set_difficulty(GameManager.Difficulty.NORMAL)
	_grid.set_reveal_all(ENEMY, true)  # stand-in for scouted intel
	for i in range(8):
		_spawn_fighter(ENEMY, Vector2(700 + i * 8, 16))
	_spawn_fighter(PLAYER, Vector2(-400, 16))
	_spawn_fighter(PLAYER, Vector2(-408, 16))
	var before: float = _ai._simulate_combat()
	var tower: Node2D = load("res://scenes/tower.tscn").instantiate()
	tower.set("team", PLAYER)
	tower.position = Vector2(-300, 16)
	_main.get_node("Structures").add_child(tower)
	autofree(tower)
	tower.set("_is_built", true)
	var after: float = _ai._simulate_combat()
	assert_lt(after, before, "a remembered enemy tower must count against the wave in the sim")


func test_sim_ignores_unbuilt_and_unknown_towers() -> void:
	GameManager.set_difficulty(GameManager.Difficulty.NORMAL)
	for i in range(8):
		_spawn_fighter(ENEMY, Vector2(700 + i * 8, 16))
	_spawn_fighter(PLAYER, Vector2(-400, 16))
	_spawn_fighter(PLAYER, Vector2(-408, 16))
	var before: float = _ai._simulate_combat()
	# Under construction: invulnerable, no combat weight.
	var unbuilt: Node2D = load("res://scenes/tower.tscn").instantiate()
	unbuilt.set("team", PLAYER)
	unbuilt.position = Vector2(-300, 16)
	_main.get_node("Structures").add_child(unbuilt)
	autofree(unbuilt)
	# Built but never scouted (fog-honest intel rule).
	var unknown: Node2D = load("res://scenes/tower.tscn").instantiate()
	unknown.set("team", PLAYER)
	unknown.position = Vector2(-350, 16)
	_main.get_node("Structures").add_child(unknown)
	autofree(unknown)
	unknown.set("_is_built", true)
	var after: float = _ai._simulate_combat()
	assert_eq(after, before, "unbuilt and unscouted towers must not enter the sim")
