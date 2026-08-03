extends GutTest

# AI micro + search layer: incoming-DPS tracking, predictive retreat,
# army-wide focus fire, splash-aware targeting, bait-and-switch, the combat
# predictor (and its wave veto), and the economic timing attack.

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


# ─── Incoming DPS tracking ───

func test_incoming_dps_tracks_recent_damage() -> void:
	var unit: Node2D = _spawn_fighter(ENEMY, Vector2(430, 16))
	for i in range(3):
		unit.call("take_damage", 10)
	# 30 damage inside the floored 0.5s window span.
	assert_almost_eq(unit.get_incoming_dps(), 60.0, 0.01, "recent hits must sum into a DPS reading")


func test_incoming_dps_decays_to_zero() -> void:
	var unit: Node2D = _spawn_fighter(ENEMY, Vector2(430, 16))
	unit.call("take_damage", 10)
	assert_gt(unit.get_incoming_dps(), 0.0)
	unit._process(3.5)  # age the log past the 3s window
	assert_eq(unit.get_incoming_dps(), 0.0, "old damage must fall out of the window")


# ─── Predictive retreat (smarts >= 1) ───

func test_predictive_retreat_pulls_doomed_fighter() -> void:
	GameManager.set_difficulty(GameManager.Difficulty.NORMAL)
	var fighter: Node2D = _spawn_fighter(ENEMY, Vector2(0, 16))  # ~960px from home
	fighter.hp = 90  # 60% — the legacy 30% rule does NOT apply
	for i in range(10):
		fighter.call("take_damage", 2)  # 40 dps in the window: dead in ~1.8s, trip home is ~15s
	_ai._retreat_wounded()
	assert_eq(fighter._state, Unit.State.MOVE, "a fighter predicted to die before reaching home must retreat now")


func test_predictive_retreat_ignores_safe_fighter() -> void:
	GameManager.set_difficulty(GameManager.Difficulty.NORMAL)
	var fighter: Node2D = _spawn_fighter(ENEMY, Vector2(0, 16))
	fighter.hp = 90  # 60%, but untouched: nothing predicts its death
	_ai._retreat_wounded()
	assert_eq(fighter._state, Unit.State.IDLE, "a healthy fighter with no incoming DPS keeps fighting")


# ─── Army-wide focus fire (smarts >= 1) ───

func test_focus_fire_converges_on_one_target() -> void:
	GameManager.set_difficulty(GameManager.Difficulty.NORMAL)
	var a: Node2D = _spawn_fighter(PLAYER, Vector2(500, 16))
	var b: Node2D = _spawn_fighter(PLAYER, Vector2(520, 16))
	var f1: Node2D = _spawn_fighter(ENEMY, Vector2(700, 16))
	var f2: Node2D = _spawn_fighter(ENEMY, Vector2(710, 16))
	var f3: Node2D = _spawn_fighter(ENEMY, Vector2(720, 16))
	f1.call("attack_unit", a)
	f2.call("attack_unit", a)
	f3.call("attack_unit", b)
	_ai._run_focus_fire()
	assert_eq(f3.get("_target_unit"), a, "the odd fighter out must join the majority target")


func test_focus_fire_leaves_sieges_alone() -> void:
	GameManager.set_difficulty(GameManager.Difficulty.NORMAL)
	var a: Node2D = _spawn_fighter(PLAYER, Vector2(500, 16))
	var b: Node2D = _spawn_fighter(PLAYER, Vector2(520, 16))
	var f1: Node2D = _spawn_fighter(ENEMY, Vector2(700, 16))
	var f2: Node2D = _spawn_fighter(ENEMY, Vector2(710, 16))
	var sieger: Node2D = _spawn_fighter(ENEMY, Vector2(-440, 16))
	f1.call("attack_unit", a)
	f2.call("attack_unit", b)
	sieger.call("attack_building", _building_for(PLAYER))
	_ai._run_focus_fire()
	assert_eq(sieger.get("_target_building"), _building_for(PLAYER), "sieges belong to retaliation logic, not focus fire")


# ─── Splash-aware targeting ───

func test_wizard_prefers_splash_cluster_over_lone_target() -> void:
	# Wizard range is 120: the clustered pair is inside it, the lone swordsman
	# is not — but it is closer to the wizard's face than the pair's centroid.
	var wizard: Node2D = _spawn_unit("res://scripts/resources/units/wizard.tres", ENEMY, Vector2(700, 16))
	_spawn_fighter(PLAYER, Vector2(560, 16))  # lone, outside attack range
	var c1: Node2D = _spawn_fighter(PLAYER, Vector2(600, 16))
	var c2: Node2D = _spawn_fighter(PLAYER, Vector2(615, 16))
	var target = wizard._find_auto_attack_target()
	assert_true(target == c1 or target == c2, "fireballs must go where they splash 2+ enemies")


# ─── Bait and switch (smarts >= 2) ───

func test_bait_sends_miner_and_springs_trap() -> void:
	GameManager.set_difficulty(GameManager.Difficulty.HARD)
	_ai._aggression_level = "balanced"  # threshold 6 on Hard; bait needs 8 fighters
	var fighters: Array = []
	for i in range(8):
		fighters.append(_spawn_fighter(ENEMY, Vector2(700 + i * 8, 16)))
	_spawn_unit("res://scripts/resources/units/miner.tres", ENEMY, Vector2(900, 16))
	_ai._run_bait()
	var bait: Node2D = _ai._bait_miner
	assert_not_null(bait, "a surface miner must be sent as bait")
	assert_eq(bait._state, Unit.State.MOVE, "the bait must be walking toward the enemy base")
	var player_building: Node2D = _building_for(PLAYER)
	assert_lt(bait.get("_target_position").distance_to(player_building.global_position), 400.0,
		"the bait's destination must be near the enemy base")
	for f in fighters:
		assert_null(f.get("_target_building"), "no launch before the trap springs")
	# A defender comes out to swat the bait: the trap springs.
	_spawn_fighter(PLAYER, bait.global_position + Vector2(50, 0))
	_ai._run_bait()
	assert_null(_ai._bait_miner, "the bait is released once the trap springs")
	for f in fighters:
		assert_eq(f.get("_target_building"), player_building, "the gathered army must launch at the undefended base")


# ─── Combat predictor ───

func test_combat_predictor_favors_bigger_army() -> void:
	for i in range(8):
		_spawn_fighter(ENEMY, Vector2(700 + i * 8, 16))
	for i in range(2):
		_spawn_fighter(PLAYER, Vector2(-600 - i * 8, 16))
	assert_gt(_ai._simulate_combat(), 10.0, "8v2 must predict a decisive AI win")


func test_combat_predictor_favors_bigger_player_army() -> void:
	for i in range(2):
		_spawn_fighter(ENEMY, Vector2(700 + i * 8, 16))
	for i in range(8):
		_spawn_fighter(PLAYER, Vector2(-600 - i * 8, 16))
	assert_lt(_ai._simulate_combat(), 0.1, "2v8 must predict a decisive AI loss")


func test_combat_predictor_respects_dragon_immunity() -> void:
	# Ground-bound swordsmen can never hurt the dragon; over a long sim the
	# dragon slowly eats them.
	for i in range(2):
		_spawn_fighter(ENEMY, Vector2(700 + i * 8, 16))
	_spawn_unit("res://scripts/resources/units/dragon.tres", PLAYER, Vector2(-600, 16))
	assert_lt(_ai._simulate_combat(10.0), 1.0, "melee-only army must lose to a dragon in the sim")


# ─── Wave veto (smarts >= 2) ───

func test_wave_veto_holds_losing_army() -> void:
	GameManager.set_difficulty(GameManager.Difficulty.NORMAL)
	_ai._aggression_level = "balanced"  # threshold 7: met, but the sim is hopeless
	var fighters: Array = []
	for i in range(7):
		var f: Node2D = _spawn_fighter(ENEMY, Vector2(-440, 16))
		f.hp = 10
		fighters.append(f)
	for i in range(10):
		_spawn_fighter(PLAYER, Vector2(-600 - i * 8, 16))
	_ai._launch_wave_if_ready()
	for f in fighters:
		assert_null(f.get("_target_building"), "the predictor must veto a wave marching into a decisive loss")


# ─── Economic timing attack (smarts >= 2) ───

func test_timing_attack_fires_when_out_economied() -> void:
	GameManager.set_difficulty(GameManager.Difficulty.NORMAL)
	var fighters: Array = []
	for i in range(5):
		fighters.append(_spawn_fighter(ENEMY, Vector2(-440, 16)))
	# Pin the lookahead inputs: -1 keeps the next resample from overwriting
	# the injected rates (the guard only samples after a first reading).
	_ai._last_ai_mined = -1
	_ai._last_player_mined = -1
	_ai._last_player_fighters = -1
	_ai._player_income_rate = 100.0
	_ai._ai_income_rate = 10.0
	_ai._update_aggression_level()
	var player_building: Node2D = _building_for(PLAYER)
	for f in fighters:
		assert_eq(f.get("_target_building"), player_building, "falling behind economically must trigger a timing attack")


func test_no_timing_attack_at_parity() -> void:
	GameManager.set_difficulty(GameManager.Difficulty.NORMAL)
	var fighters: Array = []
	for i in range(5):
		fighters.append(_spawn_fighter(ENEMY, Vector2(-440, 16)))
	_ai._last_ai_mined = -1
	_ai._last_player_mined = -1
	_ai._last_player_fighters = -1
	_ai._player_income_rate = 10.0
	_ai._ai_income_rate = 10.0
	_ai._update_aggression_level()
	for f in fighters:
		assert_null(f.get("_target_building"), "no timing attack when incomes are even")
