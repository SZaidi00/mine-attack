extends GutTest

# Research tree (Revamp Phase 6: branch tree): 10 mutually-exclusive branch
# techs bought with coin through the ResearchManager autoload — one active
# slot per team, 100% refund on cancel, completing a branch locks its
# alternative, and a one-time 500g respec resets a team's choices. Covers
# purchase guards, timed completion, locking, prerequisites (requires /
# requires_any), respec, the Ore Sonar scan + cooldown, the stat-key effects
# (archer_range, miner_carry, building_hp, wizard_damage_mult, unit_hp_mult),
# and reset() for the Play Again / Quit to Menu flows.

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
	var cost: int = Constants.RESEARCH_TECHS["deep_delve"].levels[1].cost
	var before: int = EconomyManager.get_coin(PLAYER)
	assert_true(ResearchManager.start_research(PLAYER, "deep_delve"))
	assert_eq(EconomyManager.get_coin(PLAYER), before - cost)
	assert_true(ResearchManager.is_researching(PLAYER))
	assert_eq(ResearchManager.get_active(PLAYER).tech_id, "deep_delve")


func test_start_research_rejects_unknown_tech() -> void:
	assert_false(ResearchManager.start_research(PLAYER, "time_travel"))


func test_start_research_rejects_busy_slot() -> void:
	assert_true(ResearchManager.start_research(PLAYER, "deep_delve"))
	assert_false(ResearchManager.start_research(PLAYER, "surface_war"), "one active research per team")


func test_start_research_rejects_unaffordable() -> void:
	EconomyManager.spend_coin(PLAYER, EconomyManager.get_coin(PLAYER))
	assert_false(ResearchManager.start_research(PLAYER, "deep_delve"))


func test_start_research_rejects_maxed_tech() -> void:
	ResearchManager._levels[PLAYER]["deep_delve"] = 1
	assert_false(ResearchManager.start_research(PLAYER, "deep_delve"), "branch techs have only one level")


# ─── Timed completion ───

func test_research_completes_after_its_time() -> void:
	watch_signals(ResearchManager)
	assert_true(ResearchManager.start_research(PLAYER, "deep_delve"))
	var total: float = ResearchManager.get_active(PLAYER).total
	ResearchManager._process(total - 1.0)
	assert_eq(ResearchManager.get_level(PLAYER, "deep_delve"), 0, "not finished before the timer")
	assert_true(ResearchManager.is_researching(PLAYER))
	ResearchManager._process(2.0)
	assert_eq(ResearchManager.get_level(PLAYER, "deep_delve"), 1)
	assert_false(ResearchManager.is_researching(PLAYER))
	assert_signal_emitted(ResearchManager, "research_completed")


func test_research_freezes_when_game_inactive() -> void:
	assert_true(ResearchManager.start_research(PLAYER, "deep_delve"))
	GameManager.game_active = false
	var remaining: float = ResearchManager.get_active(PLAYER).remaining
	ResearchManager._process(5.0)
	assert_eq(ResearchManager.get_active(PLAYER).remaining, remaining, "research pauses with the game")


func test_cancel_refunds_100_percent() -> void:
	var before: int = EconomyManager.get_coin(PLAYER)
	assert_true(ResearchManager.start_research(PLAYER, "deep_delve"))
	ResearchManager._process(5.0)
	assert_true(ResearchManager.cancel_research(PLAYER))
	assert_eq(EconomyManager.get_coin(PLAYER), before, "full refund even mid-research")
	assert_eq(ResearchManager.get_level(PLAYER, "deep_delve"), 0, "no level granted on cancel")


# ─── Branch locking ───

func test_completion_locks_the_alternative_branch() -> void:
	watch_signals(ResearchManager)
	assert_true(ResearchManager.start_research(PLAYER, "deep_delve"))
	ResearchManager._process(ResearchManager.get_active(PLAYER).total + 1.0)
	assert_eq(ResearchManager.get_level(PLAYER, "deep_delve"), 1)
	assert_true(ResearchManager.is_locked(PLAYER, "surface_war"), "completing deep_delve locks surface_war")
	assert_signal_emitted(ResearchManager, "branch_locked")
	assert_false(ResearchManager.is_locked(PLAYER, "deep_delve"), "the chosen branch itself stays unlocked")


func test_locked_branch_cannot_be_started() -> void:
	assert_true(ResearchManager.start_research(PLAYER, "deep_delve"))
	ResearchManager._process(ResearchManager.get_active(PLAYER).total + 1.0)
	assert_false(ResearchManager.start_research(PLAYER, "surface_war"), "locked alternative is rejected")


func test_cancel_before_completion_does_not_lock() -> void:
	assert_true(ResearchManager.start_research(PLAYER, "deep_delve"))
	ResearchManager._process(5.0)
	assert_true(ResearchManager.cancel_research(PLAYER))
	assert_false(ResearchManager.is_locked(PLAYER, "surface_war"), "locking happens on completion, not on purchase")
	assert_true(ResearchManager.start_research(PLAYER, "surface_war"), "the alternative is still researchable")


# ─── Prerequisites (tree tiers) ───

func test_tier_two_rejected_until_tier_one_researched() -> void:
	assert_false(ResearchManager.are_prerequisites_met(PLAYER, "ore_sonar"))
	assert_false(ResearchManager.start_research(PLAYER, "ore_sonar"), "needs Deep Delve first")
	ResearchManager._levels[PLAYER]["deep_delve"] = 1
	assert_true(ResearchManager.are_prerequisites_met(PLAYER, "ore_sonar"))
	assert_true(ResearchManager.start_research(PLAYER, "ore_sonar"))


func test_requires_any_accepts_either_tier_two_branch() -> void:
	assert_false(ResearchManager.are_prerequisites_met(PLAYER, "crystal_forge"))
	assert_false(ResearchManager.are_prerequisites_met(PLAYER, "earth_shield"))
	ResearchManager._levels[PLAYER]["ore_sonar"] = 1
	assert_true(ResearchManager.are_prerequisites_met(PLAYER, "crystal_forge"), "ore_sonar satisfies requires_any")
	assert_true(ResearchManager.are_prerequisites_met(PLAYER, "earth_shield"))


func test_requires_any_accepts_the_other_tier_two_branch() -> void:
	ResearchManager._levels[PLAYER]["reinforced_pack"] = 1
	assert_true(ResearchManager.are_prerequisites_met(PLAYER, "crystal_forge"), "reinforced_pack satisfies requires_any")
	assert_true(ResearchManager.are_prerequisites_met(PLAYER, "earth_shield"))
	assert_false(ResearchManager.are_prerequisites_met(PLAYER, "siege_master"), "siege_master needs longbow or rapid_fire")
	ResearchManager._levels[PLAYER]["rapid_fire"] = 1
	assert_true(ResearchManager.are_prerequisites_met(PLAYER, "siege_master"))
	assert_true(ResearchManager.are_prerequisites_met(PLAYER, "guerrilla"))


# ─── Respec ───

func test_respec_clears_levels_and_locks_for_its_cost() -> void:
	watch_signals(ResearchManager)
	ResearchManager._levels[PLAYER]["deep_delve"] = 1
	ResearchManager._locked[PLAYER].append("surface_war")
	var before: int = EconomyManager.get_coin(PLAYER)
	assert_true(ResearchManager.can_respec(PLAYER))
	assert_true(ResearchManager.respec(PLAYER))
	assert_eq(EconomyManager.get_coin(PLAYER), before - Constants.BRANCH_RESPEC_COST)
	assert_eq(ResearchManager.get_level(PLAYER, "deep_delve"), 0, "levels reset")
	assert_false(ResearchManager.is_locked(PLAYER, "surface_war"), "locks reset")
	assert_signal_emitted(ResearchManager, "research_changed")


func test_respec_guards() -> void:
	assert_false(ResearchManager.can_respec(PLAYER), "nothing researched yet")
	assert_false(ResearchManager.respec(PLAYER))
	ResearchManager._levels[PLAYER]["deep_delve"] = 1
	EconomyManager.spend_coin(PLAYER, EconomyManager.get_coin(PLAYER))
	assert_false(ResearchManager.can_respec(PLAYER), "must afford the respec cost")
	EconomyManager.add_coin(PLAYER, Constants.BRANCH_RESPEC_COST)
	assert_true(ResearchManager.respec(PLAYER))
	assert_false(ResearchManager.can_respec(PLAYER), "one respec per team per match")
	ResearchManager._levels[PLAYER]["surface_war"] = 1
	EconomyManager.add_coin(PLAYER, Constants.BRANCH_RESPEC_COST)
	assert_false(ResearchManager.respec(PLAYER), "second respec rejected")


# ─── Ore Sonar ───

func test_scan_rejected_before_research() -> void:
	assert_eq(ResearchManager.scan(PLAYER), -1, "scan requires ore_sonar")


func test_scan_reveals_ore_and_starts_cooldown() -> void:
	ResearchManager._levels[PLAYER]["ore_sonar"] = 1
	var revealed: int = ResearchManager.scan(PLAYER)
	assert_gt(revealed, 0, "seeded map has ore near the player mine")
	assert_gt(ResearchManager.get_scan_cooldown_remaining(PLAYER), 0.0)
	assert_eq(ResearchManager.scan(PLAYER), -1, "second scan blocked by cooldown")


func test_sonar_level_and_cooldown_come_from_ore_sonar() -> void:
	assert_eq(ResearchManager.get_sonar_level(PLAYER), 0)
	ResearchManager._levels[PLAYER]["ore_sonar"] = 1
	assert_eq(ResearchManager.get_sonar_level(PLAYER), 1)
	assert_eq(ResearchManager.get_scan_cooldown_total(PLAYER), Constants.SONAR_COOLDOWN[1])


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


# ─── Stat-key effects ───

func test_longbow_raises_archer_attack_range() -> void:
	var archer: Node2D = _spawn_unit("res://scripts/resources/units/archer.tres", PLAYER, Vector2(400, 16))
	var base_range: float = archer.get("data").attack_range
	ResearchManager._levels[PLAYER]["longbow"] = 1
	archer.call("_apply_research_bonuses")
	assert_eq(archer.get("data").attack_range, base_range + 25.0)


func test_reinforced_pack_raises_miner_carry_and_hp() -> void:
	var miner: Node2D = _spawn_unit("res://scripts/resources/units/miner.tres", PLAYER, Vector2(400, 16))
	var base_carry: int = miner.get("data").carry_capacity
	var base_hp: int = miner.get("data").max_hp
	ResearchManager._levels[PLAYER]["reinforced_pack"] = 1
	miner.call("_apply_research_bonuses")
	assert_eq(miner.get("data").carry_capacity, base_carry + 20)
	assert_eq(miner.get("data").max_hp, base_hp + 10)
	assert_eq(miner.get("hp"), base_hp + 10, "the max-HP gain heals the delta")


func test_crystal_forge_raises_wizard_damage() -> void:
	var wizard: Node2D = _spawn_unit("res://scripts/resources/units/wizard.tres", PLAYER, Vector2(400, 16))
	ResearchManager._levels[PLAYER]["crystal_forge"] = 1
	wizard.call("_apply_research_bonuses")
	var base_damage: float = Constants.FIGHTER_UPGRADES["wizard"][1].damage
	assert_almost_eq(wizard.get("data").damage_per_hit, base_damage * 1.4, 0.001)


func test_earth_shield_raises_building_hp_and_heals_delta() -> void:
	var building: Node2D = _building_for(PLAYER)
	var base_max: int = building.get("max_hp")
	var base_hp: int = building.get("_hp")
	watch_signals(ResearchManager)
	ResearchManager._levels[PLAYER]["earth_shield"] = 1
	ResearchManager.research_changed.emit(PLAYER)
	assert_eq(building.get("max_hp"), base_max + 1000)
	assert_eq(building.get("_hp"), base_hp + 1000, "earth_shield heals the max-HP delta")


func test_earth_shield_raises_unit_hp_and_heals() -> void:
	var swordsman: Node2D = _spawn_unit("res://scripts/resources/units/swordsman.tres", PLAYER, Vector2(400, 16))
	var base_max: int = swordsman.get("data").max_hp
	ResearchManager._levels[PLAYER]["earth_shield"] = 1
	swordsman.call("_apply_research_bonuses")
	assert_eq(swordsman.get("data").max_hp, roundi(base_max * 1.15))
	assert_eq(swordsman.get("hp"), roundi(base_max * 1.15), "the max-HP gain heals the delta")


func test_unit_hp_shrink_clamps_current_hp() -> void:
	var swordsman: Node2D = _spawn_unit("res://scripts/resources/units/swordsman.tres", PLAYER, Vector2(400, 16))
	var base_max: int = swordsman.get("data").max_hp
	ResearchManager._levels[PLAYER]["earth_shield"] = 1
	swordsman.call("_apply_research_bonuses")
	ResearchManager._levels[PLAYER]["earth_shield"] = 0
	swordsman.call("_apply_research_bonuses")
	assert_eq(swordsman.get("data").max_hp, base_max, "respec reverts the max HP")
	assert_eq(swordsman.get("hp"), base_max, "current HP clamps to the shrunk max, it does not overheal")


func test_miner_research_bonuses_survive_miner_upgrade() -> void:
	# The miner upgrade rewrites speed/carry authoritatively; research bonuses
	# must recompute on top, not get wiped or compound.
	var miner: Node2D = _spawn_unit("res://scripts/resources/units/miner.tres", PLAYER, Vector2(400, 16))
	ResearchManager._levels[PLAYER]["reinforced_pack"] = 1
	assert_true(EconomyManager.upgrade_miner(PLAYER))  # 500 coin → level 2
	miner.call("_apply_miner_upgrade")
	miner.call("_apply_research_bonuses")
	assert_eq(miner.get("data").speed, 70.0, "L2 base speed (no speed research in the branch tree)")
	assert_eq(miner.get("data").carry_capacity, 30 + 20, "L2 base carry + reinforced pack")


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
func test_reset_clears_levels_locks_active_and_cooldowns() -> void:
	ResearchManager._levels[PLAYER]["ore_sonar"] = 1
	ResearchManager._locked[PLAYER].append("reinforced_pack")
	ResearchManager.scan(PLAYER)
	ResearchManager.start_research(PLAYER, "deep_delve")
	ResearchManager.reset()
	assert_eq(ResearchManager.get_level(PLAYER, "ore_sonar"), 0)
	assert_false(ResearchManager.is_locked(PLAYER, "reinforced_pack"))
	assert_false(ResearchManager.is_researching(PLAYER))
	assert_eq(ResearchManager.get_scan_cooldown_remaining(PLAYER), 0.0)
