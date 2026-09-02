class_name AIEconomy
extends RefCounted

const _Constants = preload("res://scripts/autoload/constants.gd")

var ai: AIController

# Research purchase order for the expanded Phase 6+ tree. Tier-2 siblings are
# not mutually exclusive, but the plan prioritises each faction's signature
# capstone as soon as its first tier-2 prerequisite is available and backfills
# the sibling later. Cross-path capstones are attempted after the plan.
const _RESEARCH_PLANS: Dictionary = {
	"arcane": [
		"deep_delve", "arctic_training", "survival_instinct",
		"ore_sonar", "crystal_forge", "reinforced_pack",
		"arctic_gear", "volcano_wards", "storm_refuge", "eruption_drills",
		"fortification", "stone_masonry", "sentry_network", "citadel",
		"dragon_mastery", "broodmother", "sky_raiders", "inferno",
		"weather_alert", "storm_scout", "stormcaller",
		"deep_fortress", "total_war", "storm_dragon", "pathfinder", "artillery",
	],
	"brute": [
		"surface_war", "arctic_training", "survival_instinct",
		"longbow", "siege_master", "rapid_fire",
		"arctic_gear", "volcano_wards", "storm_refuge", "eruption_drills",
		"fortification", "stone_masonry", "sentry_network", "artillery",
		"dragon_mastery", "broodmother", "sky_raiders", "inferno",
		"weather_alert", "storm_scout", "stormcaller",
		"total_war", "deep_fortress", "storm_dragon", "pathfinder", "citadel",
	],
	"industrial": [
		"surface_war", "arctic_training", "survival_instinct",
		"longbow", "guerrilla", "rapid_fire",
		"arctic_gear", "volcano_wards", "storm_refuge", "eruption_drills",
		"fortification", "stone_masonry", "sentry_network", "citadel",
		"dragon_mastery", "broodmother", "sky_raiders", "tempest_wings",
		"weather_alert", "storm_scout", "pathfinder",
		"total_war", "deep_fortress", "storm_dragon", "stormcaller", "artillery", "siege_master",
	],
}
const _CROSS_PATH_CAPSTONES: Array[String] = ["deep_fortress", "total_war", "storm_dragon"]

func _init(a: AIController) -> void:
	ai = a


func _run_economy() -> void:
	var building: Node2D = ai._combat._get_building()
	if building == null:
		return

	var miners: int = _count_miners()
	var coin: int = EconomyManager.get_coin(ai.team)
	var level: int = EconomyManager.get_miner_level(ai.team)
	var population: int = EconomyManager.get_population(ai.team)

	# Bank for the next miner upgrade: without a reserve the training drain
	# keeps the wallet under 500/1500 forever and miners never advance past
	# level 1. Fighter upgrades and research may only spend coin on top of the
	# full reserve. Fighter *training* budgets against a partial bank (60%) —
	# otherwise army production stalls completely for the whole time the AI
	# saves up 1500 for miner level 3. Miner training is fully exempt (miners
	# pay for themselves).
	# Dead-miner triage: with no miners alive there is nothing to upgrade, and
	# every coin must flow into re-staffing the mine (the welfare trickle in
	# EconomyManager guarantees this eventually succeeds).
	var reserve: int = 0
	if miners > 0 and _Constants.MINER_UPGRADE_COSTS.has(level + 1):
		reserve = _Constants.MINER_UPGRADE_COSTS[level + 1]
	if reserve > 0 and coin >= reserve:
		EconomyManager.upgrade_miner(ai.team)

	# Fighter upgrades once the economy is comfortable (keep a coin reserve so
	# training never stalls); cheapest first so the army scales steadily.
	coin = EconomyManager.get_coin(ai.team)
	for unit_id in ["swordsman", "archer", "wizard", "dragon"]:
		var upgrade_cost: int = EconomyManager.get_fighter_upgrade_cost(ai.team, unit_id)
		if upgrade_cost > 0 and coin - reserve >= upgrade_cost + 250:
			EconomyManager.upgrade_fighter(ai.team, unit_id)
			coin -= upgrade_cost

	# Research tree: one timed slot per team plus a FIFO queue, bought with the
	# same reserve rule as fighter upgrades. Research time is not difficulty-scaled
	# — the difficulty multipliers already speed up the income that pays for it.
	if ResearchManager.get_queue_size(ai.team) < _Constants.RESEARCH_QUEUE_MAX:
		var tech: String = _pick_research()
		if tech != "":
			var data: Dictionary = ResearchManager.get_next_level_data(ai.team, tech)
			if EconomyManager.get_coin(ai.team) - reserve >= int(data.cost) + 250:
				ResearchManager.start_research(ai.team, tech)
	# The scan is free — fire it whenever the cooldown is up.
	if ResearchManager.can_scan(ai.team):
		ResearchManager.scan(ai.team)

	# Population pressure: training pauses at the cap, so when the AI is
	# boxed in it disbands surplus miners (keeping 5 for income) to free
	# slots for fighters. No refund — the population slot is the resource.
	# The floor is 5, not bare subsistence: a culled-to-nothing economy
	# rebuilds a wiped wave far too slowly (welfare needs ZERO living miners,
	# so a broke AI with idle miners gets nothing) and stalls the late game.
	if population >= _Constants.MAX_UNITS - 2 and miners > 5:
		_cull_miners(miners - 5)
		miners = _count_miners()

	# Queue decisions (respecting queue size and population cap). Deeper miner
	# levels justify a larger mining crew to exploit the newly unlocked layers.
	# The match's rolled opener shifts the quota (boom expands first, rush
	# skimps on miners to field fighters sooner).
	var queue_size: int = building.call("get_queue").size()
	if queue_size < 3 and population < _Constants.MAX_UNITS:
		coin = EconomyManager.get_coin(ai.team)
		var miner_target: int = 5 + level * 2 + int(GameManager.get_ai_opener_data().miner_delta)
		miner_target = maxi(3, miner_target)
		# Industrial (Revamp Phase 8): fast expand — a bigger mining crew.
		var faction: FactionData = FactionManager.get_faction(ai.team)
		if faction != null and faction.faction_id == "industrial":
			miner_target += 2
		if miners < miner_target and coin >= FactionManager.get_unit_cost(ai.team, "miner"):
			building.call("queue_unit", "miner")
		else:
			var pick: String = _pick_fighter_to_train(coin - int(reserve * 0.6))
			if pick != "":
				building.call("queue_unit", pick)

	# Pigeon scouts: train from towers when affordable and under the cap.
	_try_train_pigeon(reserve)


## Picks the fighter type furthest below its target share of the army that the
## budget affords, so the AI trains a combined-arms force per _ARMY_MIX.
## Smarts tier 2+ counter-picks the player's composition (_effective_army_mix).
func _pick_fighter_to_train(budget: int) -> String:
	var mix: Dictionary = _effective_army_mix() if GameManager.get_ai_smarts() >= 2 else _faction_army_mix()
	var counts: Dictionary = {}
	for unit_id in mix:
		counts[unit_id] = 0
	var total: int = 0
	for unit in ai.get_tree().get_nodes_in_group(ai._combat.team_name()):
		if unit.data.is_fighter and unit._state != Unit.State.DEAD:
			var unit_id: String = unit.data.unit_name.to_lower()
			if counts.has(unit_id):
				counts[unit_id] += 1
				total += 1
	var best: String = ""
	var best_deficit: float = 0.0
	for unit_id in mix:
		if FactionManager.get_unit_cost(ai.team, unit_id) > budget:
			continue
		# Score against a floor of a 10-unit army so the first picks already
		# follow the mix instead of training one of each.
		var desired: float = mix[unit_id] * maxf(10.0, float(total))
		var deficit: float = desired - counts[unit_id]
		if deficit > best_deficit:
			best_deficit = deficit
			best = unit_id
	return best


## Faction-flavored target composition (Revamp Phase 8, revamp.md 9.2):
## Arcane rushes wizards, Brute masses swordsmen, Industrial floods cheap
## bodies. Factionless AIs (tests, sandbox) keep the balanced default mix.
func _faction_army_mix() -> Dictionary:
	var faction: FactionData = FactionManager.get_faction(ai.team)
	if faction == null:
		return ai._ARMY_MIX
	match faction.faction_id:
		"arcane":
			return { "swordsman": 0.25, "archer": 0.2, "wizard": 0.45, "dragon": 0.1 }
		"brute":
			return { "swordsman": 0.6, "archer": 0.2, "wizard": 0.1, "dragon": 0.1 }
		"industrial":
			return { "swordsman": 0.4, "archer": 0.35, "wizard": 0.15, "dragon": 0.1 }
	return ai._ARMY_MIX


## Army mix for training, counter-picked against the player's composition
## (smarts tier 2+): dragons punish an army light on archers/wizards
## (the only units that can hurt flyers), and ranged units punish a
## melee-heavy army by kiting it. Reads the EMA scout memory
## (_sample_player_composition) rather than the live count, so production
## counters the remembered army and doesn't jitter mid-fight.
func _effective_army_mix() -> Dictionary:
	var mix: Dictionary = _faction_army_mix().duplicate()
	if ai._player_comp_memory.is_empty():
		return mix  # no scouting data yet
	var anti_air_share: float = float(ai._player_comp_memory.get("archer", 0.0)) \
		+ float(ai._player_comp_memory.get("wizard", 0.0))
	if anti_air_share < 0.3:
		mix["dragon"] = float(mix["dragon"]) * 3.0
	if float(ai._player_comp_memory.get("swordsman", 0.0)) > 0.6:
		mix["swordsman"] = float(mix["swordsman"]) - 0.15
		mix["archer"] = float(mix["archer"]) + 0.1
		mix["wizard"] = float(mix["wizard"]) + 0.05
	return mix


## Next research to buy in the expanded branch tree (Revamp Phase 6+):
## faction strategy follows a deterministic purchase order across the five
## discipline roots and their tier-2/capstone children. Tier-2 siblings are not
## mutually exclusive, so the plan grabs a faction's signature capstone as soon
## as its first tier-2 prerequisite is available and backfills the sibling
## later. After the faction plan is exhausted the AI tries cross-path tier-4
## capstones. Returns "" when nothing is pickable.
func _pick_research() -> String:
	var faction: FactionData = FactionManager.get_faction(ai.team)
	var faction_id: String = faction.faction_id if faction != null else ""
	var plan: Array = _RESEARCH_PLANS.get(faction_id, [])

	# Factionless AIs must commit to Deep Delve or Surface War first.
	if plan.is_empty():
		var has_deep: bool = ResearchManager.has_branch(ai.team, "deep_delve")
		var has_war: bool = ResearchManager.has_branch(ai.team, "surface_war")
		if not has_deep and not has_war:
			return "surface_war" if _count_fighters() > _count_miners() else "deep_delve"
		# Build a generic plan now that a side is committed.
		if has_war:
			plan = [
				"arctic_training", "survival_instinct", "longbow", "rapid_fire", "siege_master", "guerrilla",
				"arctic_gear", "volcano_wards", "storm_refuge", "eruption_drills",
				"fortification", "stone_masonry", "sentry_network", "citadel", "artillery",
				"dragon_mastery", "broodmother", "sky_raiders", "inferno", "tempest_wings",
				"weather_alert", "storm_scout", "stormcaller", "pathfinder",
			]
		else:
			plan = [
				"arctic_training", "survival_instinct", "ore_sonar", "reinforced_pack", "crystal_forge", "earth_shield",
				"arctic_gear", "volcano_wards", "storm_refuge", "eruption_drills",
				"fortification", "stone_masonry", "sentry_network", "citadel", "artillery",
				"dragon_mastery", "broodmother", "sky_raiders", "inferno", "tempest_wings",
				"weather_alert", "storm_scout", "stormcaller", "pathfinder",
			]

	for tech_id in plan:
		if _research_open(tech_id):
			return tech_id

	for tech_id in _CROSS_PATH_CAPSTONES:
		if _research_open(tech_id):
			return tech_id

	return ""


func _research_open(tech_id: String) -> bool:
	return ResearchManager.get_level(ai.team, tech_id) == 0 \
		and not ResearchManager.is_locked(ai.team, tech_id) \
		and not ResearchManager.get_next_level_data(ai.team, tech_id).is_empty() \
		and ResearchManager.are_prerequisites_met(ai.team, tech_id)


## Disbands n miners (emptiest bags first) to free population slots when the
## cap is blocking army growth. Death drops any carried coin as a pickup, so
## culling miners with cargo wastes nothing the AI can still collect.
func _cull_miners(n: int) -> void:
	var miners_by_cargo: Array = []
	for unit in ai.get_tree().get_nodes_in_group(ai._combat.team_name()):
		if unit.data.is_miner and unit._state != Unit.State.DEAD:
			miners_by_cargo.append(unit)
	miners_by_cargo.sort_custom(func(a: Unit, b: Unit) -> bool: return a.carried_coin < b.carried_coin)
	for i in range(mini(n, miners_by_cargo.size())):
		miners_by_cargo[i].kill()


func _count_miners() -> int:
	var n: int = 0
	for unit in ai.get_tree().get_nodes_in_group(ai._combat.team_name()):
		if unit.data.is_miner and unit._state != Unit.State.DEAD:
			n += 1
	return n


func _count_fighters() -> int:
	var n: int = 0
	for unit in ai.get_tree().get_nodes_in_group(ai._combat.team_name()):
		if unit.data.is_fighter and unit._state != Unit.State.DEAD:
			n += 1
	return n


func _count_pigeons() -> int:
	var n: int = 0
	for unit in ai.get_tree().get_nodes_in_group(ai._combat.team_name()):
		if unit.data.is_scout and unit._state != Unit.State.DEAD:
			n += 1
	for tower in ai.get_tree().get_nodes_in_group("towers"):
		if tower.team == ai.team:
			n += tower.call("get_pigeon_queue_count")
	return n


func _try_train_pigeon(reserve: int) -> void:
	var pigeons: int = _count_pigeons()
	if pigeons >= _Constants.PIGEON_MAX_COUNT:
		return
	var cost: int = FactionManager.get_unit_cost(ai.team, "pigeon")
	if EconomyManager.get_coin(ai.team) - reserve < cost:
		return
	if not EconomyManager.can_add_population(ai.team, 1):
		return
	for tower in ai.get_tree().get_nodes_in_group("towers"):
		if tower.team == ai.team and tower.is_built():
			if tower.call("queue_pigeon"):
				return
