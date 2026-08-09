class_name AIEconomy
extends RefCounted

const _Constants = preload("res://scripts/autoload/constants.gd")

var ai: AIController

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
	var reserve: int = 0
	if _Constants.MINER_UPGRADE_COSTS.has(level + 1):
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

	# Research tree: one timed slot per team, bought with the same reserve
	# rule as fighter upgrades. Research time is not difficulty-scaled — the
	# difficulty multipliers already speed up the income that pays for it.
	if not ResearchManager.is_researching(ai.team):
		var tech: String = _pick_research(building)
		if tech != "":
			var data: Dictionary = ResearchManager.get_next_level_data(ai.team, tech)
			if EconomyManager.get_coin(ai.team) - reserve >= int(data.cost) + 250:
				ResearchManager.start_research(ai.team, tech)
	# The scan is free — fire it whenever the cooldown is up.
	if ResearchManager.can_scan(ai.team):
		ResearchManager.scan(ai.team)

	# Population pressure: training pauses at the cap, so when the AI is
	# boxed in it disbands surplus miners (keeping 3 for income) to free
	# slots for fighters. No refund — the population slot is the resource.
	if population >= _Constants.MAX_UNITS - 2 and miners > 3:
		_cull_miners(miners - 3)
		miners = _count_miners()

	# Queue decisions (respecting queue size and population cap). Deeper miner
	# levels justify a larger mining crew to exploit the newly unlocked layers.
	var queue_size: int = building.call("get_queue").size()
	if queue_size < 3 and population < _Constants.MAX_UNITS:
		coin = EconomyManager.get_coin(ai.team)
		var miner_target: int = 5 + level * 2
		if miners < miner_target and coin >= FactionManager.get_unit_cost(ai.team, "miner"):
			building.call("queue_unit", "miner")
		else:
			var pick: String = _pick_fighter_to_train(coin - int(reserve * 0.6))
			if pick != "":
				building.call("queue_unit", pick)


## Picks the fighter type furthest below its target share of the army that the
## budget affords, so the AI trains a combined-arms force per _ARMY_MIX.
## Smarts tier 3 counter-picks the player's composition (_effective_army_mix).
func _pick_fighter_to_train(budget: int) -> String:
	var mix: Dictionary = _effective_army_mix() if GameManager.get_ai_smarts() >= 3 else ai._ARMY_MIX
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


## Army mix for training, counter-picked against the player's composition
## (smarts tier 3 only): dragons punish an army light on archers/wizards
## (the only units that can hurt flyers), and ranged units punish a
## melee-heavy army by kiting it. Reads the EMA scout memory
## (_sample_player_composition) rather than the live count, so production
## counters the remembered army and doesn't jitter mid-fight.
func _effective_army_mix() -> Dictionary:
	var mix: Dictionary = ai._ARMY_MIX.duplicate()
	if ai._player_comp_memory.is_empty():
		return mix  # no scouting data yet
	var anti_air_share: float = float(ai._player_comp_memory.get("archer", 0.0)) \
		+ float(ai._player_comp_memory.get("wizard", 0.0))
	if anti_air_share < 0.3:
		mix["dragon"] = ai._ARMY_MIX["dragon"] * 3.0
	if float(ai._player_comp_memory.get("swordsman", 0.0)) > 0.6:
		mix["swordsman"] = ai._ARMY_MIX["swordsman"] - 0.15
		mix["archer"] = ai._ARMY_MIX["archer"] + 0.1
		mix["wizard"] = ai._ARMY_MIX["wizard"] + 0.05
	return mix


## Next research to buy, by priority: sonar first (revealed ore shortens
## every miner trip), fortify when the base is hurt, then the fighter tech
## matching the army's most numerous fighter type, then anything left.
func _pick_research(building: Node2D) -> String:
	if _research_open("ore_sonar"):
		return "ore_sonar"
	var hurt: bool = building != null and float(building.get("_hp")) < float(building.get("max_hp")) * 0.6
	if hurt and _research_open("fortify"):
		return "fortify"
	# Only count fighter types that have a matching research tech — dragons
	# have no tech row, so they must not become best_unit and index-miss.
	var counts: Dictionary = { "swordsman": 0, "archer": 0, "wizard": 0 }
	for unit in ai.get_tree().get_nodes_in_group(ai._combat.team_name()):
		if unit.data.is_fighter:
			var unit_id: String = unit.data.unit_name.to_lower()
			if counts.has(unit_id):
				counts[unit_id] += 1
	var tech_by_unit: Dictionary = { "swordsman": "bulwark", "archer": "longbow", "wizard": "inferno" }
	var best_unit: String = "swordsman"
	for unit_id in counts:
		if counts[unit_id] > counts[best_unit]:
			best_unit = unit_id
	if _research_open(tech_by_unit[best_unit]):
		return tech_by_unit[best_unit]
	for tech in ["bulwark", "longbow", "inferno", "berserk", "rapid_fire", "arcane_might", "reinforced_pack", "swift_boots", "deep_scan", "self_repair", "fortify"]:
		if _research_open(tech):
			return tech
	return ""


func _research_open(tech_id: String) -> bool:
	return not ResearchManager.get_next_level_data(ai.team, tech_id).is_empty() \
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
