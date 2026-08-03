extends GutTest

# AI smarts: the difficulty "smarts" tier gates behavior quality (rates stay
# fair-play below GODLY). Tier 1 = focus-fire defense + wounded retreat,
# tier 2 = + counter-attack windows + miner harassment, tier 3 = +
# counter-composition army mix. GODLY gets everything plus stacked rates.

const PLAYER: int = 0
const ENEMY: int = 1

var _main: Node
var _units: Node
var _ai: Node


func before_all() -> void:
	# Deterministic map: Constants.DEBUG is off (so GridWorld doesn't seed
	# itself), but the tests assert against specific layouts.
	seed(12345)
	_main = load("res://scenes/main.tscn").instantiate()
	get_tree().root.add_child(_main)
	get_tree().current_scene = _main
	_units = _main.get_node("Units")
	_ai = _main.get_node("AIController")


func after_all() -> void:
	# Free immediately, not queue_free(): a queued free could still be pending
	# when the next test script instantiates its own main.tscn and every
	# hard-coded /root/Main lookup would break.
	_main.free()


func before_each() -> void:
	EconomyManager.reset()
	ResearchManager.reset()


func after_each() -> void:
	# GameManager is an autoload: never leak a difficulty choice into the
	# next test script.
	GameManager.set_difficulty(GameManager.Difficulty.NORMAL)


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


# ─── Focus-fire defense (smarts >= 1) ───

func test_defense_easy_picks_nearest_threat() -> void:
	GameManager.set_difficulty(GameManager.Difficulty.EASY)
	var defender: Node2D = _spawn_fighter(ENEMY, Vector2(700, 16))
	var near_full: Node2D = _spawn_fighter(PLAYER, Vector2(640, 16))
	var far_wounded: Node2D = _spawn_fighter(PLAYER, Vector2(400, 16))
	far_wounded.hp = int(far_wounded.data.max_hp * 0.1)
	_ai._defend_building()
	assert_eq(defender.get("_target_unit"), near_full, "tier 0 defense must pick the nearest threat")


func test_defense_normal_focuses_wounded_threat() -> void:
	GameManager.set_difficulty(GameManager.Difficulty.NORMAL)
	var defender: Node2D = _spawn_fighter(ENEMY, Vector2(700, 16))
	_spawn_fighter(PLAYER, Vector2(640, 16))  # nearer, but full HP
	var far_wounded: Node2D = _spawn_fighter(PLAYER, Vector2(400, 16))
	far_wounded.hp = int(far_wounded.data.max_hp * 0.1)
	_ai._defend_building()
	assert_eq(defender.get("_target_unit"), far_wounded, "tier 1+ defense must focus-fire the wounded intruder")


# ─── Wounded retreat (smarts >= 1) ───

func test_wounded_fighter_retreats_when_base_safe() -> void:
	GameManager.set_difficulty(GameManager.Difficulty.NORMAL)
	var fighter: Node2D = _spawn_fighter(ENEMY, Vector2(0, 16))  # 960px from home
	fighter.hp = int(fighter.data.max_hp * 0.2)
	_ai._retreat_wounded()
	assert_eq(fighter._state, Unit.State.MOVE, "wounded fighter must be ordered home")
	var building: Node2D = _building_for(ENEMY)
	assert_lt(fighter.get("_post_point").distance_to(building.global_position), 400.0,
		"retreat must set the standing point at the home base")


func test_wounded_fighter_holds_when_base_under_attack() -> void:
	GameManager.set_difficulty(GameManager.Difficulty.NORMAL)
	var fighter: Node2D = _spawn_fighter(ENEMY, Vector2(0, 16))
	fighter.hp = int(fighter.data.max_hp * 0.2)
	_spawn_fighter(PLAYER, Vector2(700, 16))  # intruder next to the enemy base
	_ai._retreat_wounded()
	assert_eq(fighter._state, Unit.State.IDLE, "no retreats while the base needs every defender")


func test_wounded_retreat_skipped_on_easy() -> void:
	GameManager.set_difficulty(GameManager.Difficulty.EASY)
	var fighter: Node2D = _spawn_fighter(ENEMY, Vector2(0, 16))
	fighter.hp = int(fighter.data.max_hp * 0.2)
	_ai._retreat_wounded()
	assert_eq(fighter._state, Unit.State.IDLE, "tier 0 never retreats")


# ─── Miner harassment (smarts >= 2) ───

func test_harassment_raids_exposed_surface_miners() -> void:
	GameManager.set_difficulty(GameManager.Difficulty.HARD)
	_ai._aggression_level = "balanced"  # wave threshold 7, raid needs 9 fighters
	var raiders: Array = []
	for i in range(9):
		raiders.append(_spawn_fighter(ENEMY, Vector2(700 + i * 8, 16)))
	var miner: Node2D = _spawn_unit("res://scripts/resources/units/miner.tres", PLAYER, Vector2(600, 16))
	_ai._run_harassment()
	var hunting: int = 0
	for r in raiders:
		if r.get("_target_unit") == miner:
			hunting += 1
	assert_eq(hunting, 2, "two raiders must be sent after the exposed miner")


func test_harassment_skipped_on_easy() -> void:
	GameManager.set_difficulty(GameManager.Difficulty.EASY)
	_ai._aggression_level = "balanced"
	for i in range(9):
		_spawn_fighter(ENEMY, Vector2(700 + i * 8, 16))
	_spawn_unit("res://scripts/resources/units/miner.tres", PLAYER, Vector2(600, 16))
	_ai._run_harassment()
	for unit in get_tree().get_nodes_in_group("enemy"):
		if unit.data.is_fighter:
			assert_null(unit.get("_target_unit"), "tier 0/1 never raids the economy")


func test_harassment_ignores_underground_miners() -> void:
	GameManager.set_difficulty(GameManager.Difficulty.HARD)
	_ai._aggression_level = "balanced"
	for i in range(9):
		_spawn_fighter(ENEMY, Vector2(700 + i * 8, 16))
	var miner: Node2D = _spawn_unit("res://scripts/resources/units/miner.tres", PLAYER, Vector2(600, 16))
	miner.is_underground = true
	_ai._run_harassment()
	for unit in get_tree().get_nodes_in_group("enemy"):
		if unit.data.is_fighter:
			# Other surface miners (e.g. the starting crew) may legitimately be
			# raided — the assertion is that the underground one never is.
			assert_ne(unit.get("_target_unit"), miner, "combat cannot cross layers — underground miners are safe from raids")


# ─── Counter-attack window (smarts >= 2) ───

func test_counterattack_launches_after_enemy_losses() -> void:
	GameManager.set_difficulty(GameManager.Difficulty.HARD)
	var fighters: Array = []
	for i in range(5):
		fighters.append(_spawn_fighter(ENEMY, Vector2(700 + i * 8, 16)))
	for i in range(5):
		_spawn_fighter(PLAYER, Vector2(-600 - i * 8, 16))
	# The previous sample saw 8 player fighters; now 5 -> drop of 3 opens the
	# window, launching with override threshold 4 (below the balanced 7).
	_ai._last_player_fighters = 8
	_ai._update_aggression_level()
	var player_building: Node2D = _building_for(PLAYER)
	for f in fighters:
		assert_eq(f.get("_target_building"), player_building, "a sharp enemy loss must trigger an immediate counter-attack")


func test_no_counterattack_without_losses() -> void:
	GameManager.set_difficulty(GameManager.Difficulty.HARD)
	var fighters: Array = []
	for i in range(5):
		fighters.append(_spawn_fighter(ENEMY, Vector2(700 + i * 8, 16)))
	for i in range(5):
		_spawn_fighter(PLAYER, Vector2(-600 - i * 8, 16))
	_ai._last_player_fighters = 5  # no drop since the last sample
	_ai._update_aggression_level()
	for f in fighters:
		assert_null(f.get("_target_building"), "no losses, no counter-attack — the wave keeps gathering")


# ─── Counter-composition army mix (smarts >= 3) ───

func test_counter_mix_punishes_missing_anti_air() -> void:
	GameManager.set_difficulty(GameManager.Difficulty.NIGHTMARE)
	_ai._player_comp_memory.clear()
	for i in range(4):
		_spawn_fighter(PLAYER, Vector2(-600 - i * 8, 16))  # all melee, zero anti-air
	_ai._sample_player_composition()  # feed the scout memory the mix reads
	var mix: Dictionary = _ai._effective_army_mix()
	assert_gt(mix["dragon"], _ai._ARMY_MIX["dragon"], "no player anti-air must spike the dragon share")
	assert_lt(mix["swordsman"], _ai._ARMY_MIX["swordsman"], "a melee-heavy player army must shift the mix toward ranged")


func test_counter_mix_default_against_anti_air() -> void:
	GameManager.set_difficulty(GameManager.Difficulty.NIGHTMARE)
	_ai._player_comp_memory.clear()
	_spawn_fighter(PLAYER, Vector2(-600, 16))
	_spawn_unit("res://scripts/resources/units/archer.tres", PLAYER, Vector2(-610, 16))
	_spawn_unit("res://scripts/resources/units/archer.tres", PLAYER, Vector2(-620, 16))
	_spawn_unit("res://scripts/resources/units/wizard.tres", PLAYER, Vector2(-630, 16))
	_ai._sample_player_composition()
	var mix: Dictionary = _ai._effective_army_mix()
	assert_eq(mix, _ai._ARMY_MIX, "a balanced player army with anti-air gets the default mix")


func test_counter_mix_ignored_below_tier_3() -> void:
	GameManager.set_difficulty(GameManager.Difficulty.NORMAL)
	for i in range(4):
		_spawn_fighter(PLAYER, Vector2(-600 - i * 8, 16))
	# _pick_fighter_to_train only counter-picks at tier 3; the mix helper is
	# still callable, but the trainer must use the base mix at tier 2.
	var first: String = _ai._pick_fighter_to_train(1000)
	assert_eq(first, "swordsman", "tier 2 training must follow the base mix, not the counter-pick")


# ─── Godly difficulty ───

func test_godly_breaks_fair_play_and_gets_every_behavior() -> void:
	GameManager.set_difficulty(GameManager.Difficulty.GODLY)
	assert_eq(GameManager.get_ai_smarts(), 3, "godly gets every smart behavior")
	assert_gt(GameManager.get_ai_coin_multiplier(), 1.5, "godly income exceeds nightmare")
	assert_lt(GameManager.get_ai_train_time_multiplier(), 0.8, "godly trains faster than nightmare")
	assert_eq(GameManager.get_ai_retaliation_chance(), 1.0, "godly always retaliates")
