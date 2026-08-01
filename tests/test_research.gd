extends GutTest

# Research tree (Phase: research v1): timed techs bought with coin through the
# ResearchManager autoload — one active slot per team, 100% refund on cancel.
# Covers purchase guards, timed completion, per-tech effects (fortify,
# longbow, bulwark, reinforced pack), the Ore Sonar scan + cooldown, and
# reset() for the Play Again / Quit to Menu flows.

const PLAYER: int = 0
const ENEMY: int = 1

var _main: Node
var _units: Node


func before_all() -> void:
	# Deterministic map: Constants.DEBUG is off (so GridWorld doesn't seed
	# itself), but the sonar test asserts against a specific layout.
	seed(12345)
	_main = load("res://scenes/main.tscn").instantiate()
	get_tree().root.add_child(_main)
	get_tree().current_scene = _main
	_units = _main.get_node("Units")


func after_all() -> void:
	# Free immediately, not queue_free(): a queued free would still be pending
	# when the next test script instantiates its own main.tscn — the old "Main"
	# name would still be taken and every hard-coded /root/Main lookup would
	# break (flaky, timing-dependent failures).
	ResearchManager.reset()
	EconomyManager.reset()
	_main.free()


func before_each() -> void:
	# Autoload state persists across tests — start every test clean.
	ResearchManager.reset()
	EconomyManager.reset()
	GameManager.game_active = true


func _spawn_unit(tres_path: String, team: int, pos: Vector2) -> Node2D:
	var unit: Node2D = load("res://scenes/unit.tscn").instantiate()
	unit.set("data", load(tres_path).duplicate(true))
	unit.set("team", team)
	unit.position = pos
	_units.add_child(unit)
	autofree(unit)
	return unit


func _building_for(team: int) -> Node2D:
	for b in get_tree().get_nodes_in_group("buildings"):
		if b.get("team") == team:
			return b
	return null


# ─── Purchase guards ───

func test_start_research_spends_coin_and_fills_slot() -> void:
	var cost: int = Constants.RESEARCH_TECHS["ore_sonar"].levels[1].cost
	var before: int = EconomyManager.get_coin(PLAYER)
	assert_true(ResearchManager.start_research(PLAYER, "ore_sonar"))
	assert_eq(EconomyManager.get_coin(PLAYER), before - cost)
	assert_true(ResearchManager.is_researching(PLAYER))
	assert_eq(ResearchManager.get_active(PLAYER).tech_id, "ore_sonar")


func test_start_research_rejects_unknown_tech() -> void:
	assert_false(ResearchManager.start_research(PLAYER, "time_travel"))


func test_start_research_rejects_busy_slot() -> void:
	assert_true(ResearchManager.start_research(PLAYER, "ore_sonar"))
	assert_false(ResearchManager.start_research(PLAYER, "fortify"), "one active research per team")


func test_start_research_rejects_unaffordable() -> void:
	EconomyManager.spend_coin(PLAYER, EconomyManager.get_coin(PLAYER))
	assert_false(ResearchManager.start_research(PLAYER, "fortify"))


func test_start_research_rejects_maxed_tech() -> void:
	ResearchManager._levels[PLAYER]["longbow"] = 1
	assert_false(ResearchManager.start_research(PLAYER, "longbow"), "longbow has only one level")


# ─── Timed completion ───

func test_research_completes_after_its_time() -> void:
	watch_signals(ResearchManager)
	assert_true(ResearchManager.start_research(PLAYER, "ore_sonar"))
	var total: float = ResearchManager.get_active(PLAYER).total
	ResearchManager._process(total - 1.0)
	assert_eq(ResearchManager.get_level(PLAYER, "ore_sonar"), 0, "not finished before the timer")
	assert_true(ResearchManager.is_researching(PLAYER))
	ResearchManager._process(2.0)
	assert_eq(ResearchManager.get_level(PLAYER, "ore_sonar"), 1)
	assert_false(ResearchManager.is_researching(PLAYER))
	assert_signal_emitted(ResearchManager, "research_completed")


func test_research_freezes_when_game_inactive() -> void:
	assert_true(ResearchManager.start_research(PLAYER, "ore_sonar"))
	GameManager.game_active = false
	var remaining: float = ResearchManager.get_active(PLAYER).remaining
	ResearchManager._process(5.0)
	assert_eq(ResearchManager.get_active(PLAYER).remaining, remaining, "research pauses with the game")


func test_cancel_refunds_100_percent() -> void:
	EconomyManager.add_coin(PLAYER, 2000)  # fortify (600g) exceeds the 500 starting coin
	var before: int = EconomyManager.get_coin(PLAYER)
	assert_true(ResearchManager.start_research(PLAYER, "fortify"))
	ResearchManager._process(5.0)
	assert_true(ResearchManager.cancel_research(PLAYER))
	assert_eq(EconomyManager.get_coin(PLAYER), before, "full refund even mid-research")
	assert_eq(ResearchManager.get_level(PLAYER, "fortify"), 0, "no level granted on cancel")


# ─── Effects ───

func test_fortify_raises_building_hp_and_heals_delta() -> void:
	EconomyManager.add_coin(PLAYER, 2000)  # fortify (600g) exceeds the 500 starting coin
	var building: Node2D = _building_for(PLAYER)
	var base_max: int = building.get("max_hp")
	var base_hp: int = building.get("_hp")
	watch_signals(ResearchManager)
	assert_true(ResearchManager.start_research(PLAYER, "fortify"))
	ResearchManager._process(ResearchManager.get_active(PLAYER).total + 1.0)
	assert_eq(ResearchManager.get_level(PLAYER, "fortify"), 1)
	assert_eq(building.get("max_hp"), base_max + 2000)
	assert_eq(building.get("_hp"), base_hp + 2000, "fortify heals the max-HP delta")


func test_longbow_raises_archer_attack_range() -> void:
	var archer: Node2D = _spawn_unit("res://scripts/resources/units/archer.tres", PLAYER, Vector2(400, 16))
	var base_range: float = archer.get("data").attack_range
	ResearchManager._levels[PLAYER]["longbow"] = 1
	archer.call("_apply_research_bonuses")
	assert_eq(archer.get("data").attack_range, base_range + 30.0)


func test_bulwark_reduces_swordsman_damage_taken() -> void:
	var swordsman: Node2D = _spawn_unit("res://scripts/resources/units/swordsman.tres", PLAYER, Vector2(400, 16))
	ResearchManager._levels[PLAYER]["bulwark"] = 2
	swordsman.call("_apply_research_bonuses")
	assert_eq(swordsman.get("_armor"), 4, "bulwark L1+L2 stacks to 4 flat reduction")
	swordsman.set("hp", 1000)
	swordsman.call("take_damage", 10)
	assert_eq(swordsman.get("hp"), 1000 - 6, "10 damage - 4 armor = 6 taken")


func test_armor_never_reduces_a_hit_below_one() -> void:
	var swordsman: Node2D = _spawn_unit("res://scripts/resources/units/swordsman.tres", PLAYER, Vector2(400, 16))
	ResearchManager._levels[PLAYER]["bulwark"] = 2
	swordsman.call("_apply_research_bonuses")
	swordsman.set("hp", 1000)
	swordsman.call("take_damage", 2)
	assert_eq(swordsman.get("hp"), 999, "a hit always lands for at least 1")


func test_reinforced_pack_raises_miner_carry_capacity() -> void:
	var miner: Node2D = _spawn_unit("res://scripts/resources/units/miner.tres", PLAYER, Vector2(400, 16))
	var base_carry: int = miner.get("data").carry_capacity
	ResearchManager._levels[PLAYER]["reinforced_pack"] = 1
	miner.call("_apply_research_bonuses")
	assert_eq(miner.get("data").carry_capacity, base_carry + 15)


# ─── Ore Sonar ───

func test_scan_rejected_before_research() -> void:
	assert_eq(ResearchManager.scan(PLAYER), -1, "scan requires ore_sonar")


func test_scan_reveals_ore_and_starts_cooldown() -> void:
	ResearchManager._levels[PLAYER]["ore_sonar"] = 1
	var revealed: int = ResearchManager.scan(PLAYER)
	assert_gt(revealed, 0, "seeded map has ore near the player mine")
	assert_gt(ResearchManager.get_scan_cooldown_remaining(PLAYER), 0.0)
	assert_eq(ResearchManager.scan(PLAYER), -1, "second scan blocked by cooldown")


func test_scan_cooldown_expires() -> void:
	ResearchManager._levels[PLAYER]["ore_sonar"] = 1
	ResearchManager.scan(PLAYER)
	ResearchManager._process(Constants.SONAR_COOLDOWN[1] + 1.0)
	assert_eq(ResearchManager.get_scan_cooldown_remaining(PLAYER), 0.0)
	assert_true(ResearchManager.can_scan(PLAYER))


func test_revealed_ore_marks_cells_for_the_team() -> void:
	ResearchManager._levels[PLAYER]["ore_sonar"] = 1
	ResearchManager.scan(PLAYER)
	var grid: GridWorld = _main.get_node("World/GridWorld")
	var found: bool = false
	for x in range(-25, -5):
		for y in range(1, 22):
			if grid.is_ore_revealed(Vector2i(x, y), PLAYER):
				found = true
	assert_true(found, "scan marks ore cells as revealed for the scanning team")


# ─── Prerequisites (tree tiers) ───

func test_tier_two_tech_rejected_until_prerequisite_researched() -> void:
	assert_false(ResearchManager.are_prerequisites_met(PLAYER, "swift_boots"))
	assert_false(ResearchManager.start_research(PLAYER, "swift_boots"), "needs Reinforced Pack L1 first")
	ResearchManager._levels[PLAYER]["reinforced_pack"] = 1
	assert_true(ResearchManager.are_prerequisites_met(PLAYER, "swift_boots"))
	assert_true(ResearchManager.start_research(PLAYER, "swift_boots"))


func test_deep_scan_requires_full_ore_sonar() -> void:
	ResearchManager._levels[PLAYER]["ore_sonar"] = 1
	assert_false(ResearchManager.are_prerequisites_met(PLAYER, "deep_scan"), "sonar L1 is not enough")
	ResearchManager._levels[PLAYER]["ore_sonar"] = 2
	assert_true(ResearchManager.are_prerequisites_met(PLAYER, "deep_scan"))


func test_deep_scan_extends_sonar_level() -> void:
	ResearchManager._levels[PLAYER]["ore_sonar"] = 2
	ResearchManager._levels[PLAYER]["deep_scan"] = 1
	assert_eq(ResearchManager.get_sonar_level(PLAYER), 3)
	assert_eq(ResearchManager.get_scan_cooldown_total(PLAYER), Constants.SONAR_COOLDOWN[3])


# ─── Tier-2 effects ───

func test_swift_boots_raises_miner_speed() -> void:
	var miner: Node2D = _spawn_unit("res://scripts/resources/units/miner.tres", PLAYER, Vector2(400, 16))
	ResearchManager._levels[PLAYER]["swift_boots"] = 1
	miner.call("_apply_research_bonuses")
	assert_eq(miner.get("data").speed, 60.0 + 15.0)


func test_miner_research_bonuses_survive_miner_upgrade() -> void:
	# The miner upgrade rewrites speed/carry authoritatively; research bonuses
	# must recompute on top, not get wiped or compound.
	var miner: Node2D = _spawn_unit("res://scripts/resources/units/miner.tres", PLAYER, Vector2(400, 16))
	ResearchManager._levels[PLAYER]["swift_boots"] = 1
	ResearchManager._levels[PLAYER]["reinforced_pack"] = 1
	assert_true(EconomyManager.upgrade_miner(PLAYER))  # 500 coin → level 2
	miner.call("_apply_miner_upgrade")
	miner.call("_apply_research_bonuses")
	assert_eq(miner.get("data").speed, 70.0 + 15.0, "L2 base speed + swift boots")
	assert_eq(miner.get("data").carry_capacity, 30 + 15, "L2 base carry + reinforced pack")


func test_berserk_lowers_swordsman_cooldown() -> void:
	var swordsman: Node2D = _spawn_unit("res://scripts/resources/units/swordsman.tres", PLAYER, Vector2(400, 16))
	var base_cd: float = swordsman.get("data").attack_cooldown
	ResearchManager._levels[PLAYER]["berserk"] = 1
	swordsman.call("_apply_research_bonuses")
	assert_almost_eq(swordsman.get("data").attack_cooldown, base_cd * 0.8, 0.001)


func test_rapid_fire_lowers_archer_cooldown() -> void:
	var archer: Node2D = _spawn_unit("res://scripts/resources/units/archer.tres", PLAYER, Vector2(400, 16))
	var base_cd: float = archer.get("data").attack_cooldown
	ResearchManager._levels[PLAYER]["rapid_fire"] = 1
	archer.call("_apply_research_bonuses")
	assert_almost_eq(archer.get("data").attack_cooldown, base_cd * 0.75, 0.001)


func test_arcane_might_raises_wizard_damage() -> void:
	var wizard: Node2D = _spawn_unit("res://scripts/resources/units/wizard.tres", PLAYER, Vector2(400, 16))
	ResearchManager._levels[PLAYER]["arcane_might"] = 1
	wizard.call("_apply_research_bonuses")
	var base_damage: float = Constants.FIGHTER_UPGRADES["wizard"][1].damage
	assert_almost_eq(wizard.get("data").damage_per_hit, base_damage * 1.25, 0.001)


func test_self_repair_regenerates_building_hp() -> void:
	var building: Node2D = _building_for(PLAYER)
	building.set("_hp", 3000)
	ResearchManager._levels[PLAYER]["self_repair"] = 1
	building.call("_process", 1.0)
	assert_eq(building.get("_hp"), 3005, "5 HP/s regen")
	building.call("_process", 10.0)
	assert_eq(building.get("_hp"), 3055)


func test_self_repair_does_not_overheal() -> void:
	var building: Node2D = _building_for(PLAYER)
	building.set("_hp", building.get("max_hp") - 2)
	ResearchManager._levels[PLAYER]["self_repair"] = 1
	building.call("_process", 5.0)
	assert_eq(building.get("_hp"), building.get("max_hp"), "capped at max HP")


# ─── Overlay pause toggle ───

func test_overlay_pause_toggle_pauses_and_resumes() -> void:
	# The overlay never pauses by itself; the "Pause game" toggle opts in, and
	# closing the overlay releases exactly that pause. No awaits here — the
	# tree is briefly paused, and frames must not pass until it resumes.
	var hud: CanvasLayer = _main.get_node("UI/HUD")
	var panel: Control = hud.get_node("ResearchPanel")
	assert_false(get_tree().paused)
	panel.visible = true
	assert_false(get_tree().paused, "opening the overlay does not pause")
	panel._pause_while_open = true
	panel._sync_pause()
	assert_true(get_tree().paused, "toggle pauses the game")
	assert_true(panel.owns_pause())
	hud._process(0.016)
	assert_false(hud._pause_panel.visible, "pause menu stays hidden under the overlay")
	panel.visible = false
	assert_false(get_tree().paused, "closing the overlay resumes")
	assert_false(panel.owns_pause())


# ─── Reset ───
func test_reset_clears_levels_active_and_cooldowns() -> void:
	ResearchManager._levels[PLAYER]["ore_sonar"] = 1
	ResearchManager.scan(PLAYER)
	ResearchManager.start_research(PLAYER, "fortify")
	ResearchManager.reset()
	assert_eq(ResearchManager.get_level(PLAYER, "ore_sonar"), 0)
	assert_false(ResearchManager.is_researching(PLAYER))
	assert_eq(ResearchManager.get_scan_cooldown_remaining(PLAYER), 0.0)
