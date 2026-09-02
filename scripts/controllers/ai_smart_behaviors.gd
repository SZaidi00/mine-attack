class_name AISmartBehaviors
extends RefCounted

const _Constants = preload("res://scripts/autoload/constants.gd")

var ai: AIController

func _init(a: AIController) -> void:
	ai = a


## Smarts tier 1+: pull wounded fighters back to the base so out-of-combat
## regen (unit.gd) heals them instead of feeding them into losing fights.
## Never retreats while the base itself is under attack (the defense needs
## every body), and leaves units already near home alone. Healed fighters go
## IDLE at base and are swept into the next wave/defense.
func _retreat_wounded() -> void:
	if GameManager.get_ai_smarts() < 1:
		return
	var building: Node2D = ai._combat._get_building()
	if building == null:
		return
	if ai._combat._nearest_enemy_unit(building.global_position, 650) != null:
		return  # base under attack: hold the line, no retreats
	for unit in ai.get_tree().get_nodes_in_group(ai._combat.team_name()):
		if not unit.data.is_fighter or unit._state == Unit.State.DEAD:
			continue
		if unit.global_position.distance_to(building.global_position) <= 400.0:
			continue  # already home (or close enough to heal in safety)
		if _is_wounded(unit, building):
			unit.garrison_home()


## Retreat check: the legacy fixed threshold (under ENEMY_WOUNDED_HP_RATIO),
## plus a predictive rule — if the unit's recent incoming DPS would kill it
## before it could walk home (with a safety buffer), pull it out now, even at
## high HP. A unit that wins the predicted race keeps fighting.
func _is_wounded(unit: Unit, building: Node2D) -> bool:
	if unit.hp < int(float(unit.data.max_hp) * _Constants.ENEMY_WOUNDED_HP_RATIO):
		return true
	var incoming: float = unit.get_incoming_dps()
	if incoming <= 0.0:
		return false
	var time_to_death: float = float(unit.hp) / incoming
	var trip_home: float = unit.global_position.distance_to(building.global_position) / maxf(unit.data.speed, 1.0)
	return time_to_death < trip_home + _Constants.ENEMY_RETREAT_PREDICT_BUFFER


## Smarts tier 1+: army-wide focus fire. The enemy unit already under attack
## by the most fighters (tiebreak: lowest HP fraction) becomes the focus;
## every other fighter duelling a unit switches to it when it can damage the
## focus and the focus isn't meaningfully farther than its current target
## (the distance rule prevents flip-flopping between two brawls). Fighters
## sieging a building are left alone — retaliation owns that decision.
func _run_focus_fire() -> void:
	if GameManager.get_ai_smarts() < 1:
		return
	var tally: Dictionary = {}  # target Unit -> attacker count
	for unit in ai.get_tree().get_nodes_in_group(ai._combat.team_name()):
		if not unit.data.is_fighter or unit._state != Unit.State.ATTACK:
			continue
		var target = unit._target_unit
		if target == null or not is_instance_valid(target) or target._state == Unit.State.DEAD:
			continue
		tally[target] = int(tally.get(target, 0)) + 1
	if tally.size() < 2:
		return  # zero or one brawl: nothing to converge
	var focus: Unit = null
	var focus_count: int = 0
	var focus_hp_fraction: float = INF
	for target in tally:
		var hp_fraction: float = float(target.hp) / maxf(1.0, float(target.data.max_hp))
		if int(tally[target]) > focus_count or (int(tally[target]) == focus_count and hp_fraction < focus_hp_fraction):
			focus = target
			focus_count = int(tally[target])
			focus_hp_fraction = hp_fraction
	for unit in ai.get_tree().get_nodes_in_group(ai._combat.team_name()):
		if not unit.data.is_fighter or unit._state != Unit.State.ATTACK:
			continue
		var current = unit._target_unit
		if current == null or current == focus or not is_instance_valid(current):
			continue
		if not unit.can_damage_unit(focus):
			continue
		# Squared distances: 1.44 = 1.2² (don't yo-yo between brawls).
		if unit.combat_distance_squared_to(focus) > unit.combat_distance_squared_to(current) * 1.44:
			continue
		unit.attack_unit(focus)


func _update_aggression_level() -> void:
	var player_fighters: int = 0
	var enemy_fighters: int = 0
	for unit in ai.get_tree().get_nodes_in_group("units"):
		if not unit.data.is_fighter or unit._state == Unit.State.DEAD:
			continue
		if unit.team == GameManager.Team.PLAYER:
			player_fighters += 1
		else:
			enemy_fighters += 1

	var my_fighters: int = enemy_fighters if ai.team == GameManager.Team.ENEMY else player_fighters
	var their_fighters: int = player_fighters if ai.team == GameManager.Team.ENEMY else enemy_fighters

	# Economic lookahead: coin-mined rates (per second) for both teams,
	# resampled from the EconomyManager totals each tick.
	var their_team: GameManager.Team = GameManager.Team.PLAYER if ai.team == GameManager.Team.ENEMY else GameManager.Team.ENEMY
	var my_mined: int = EconomyManager.get_coin_mined(ai.team)
	var their_mined: int = EconomyManager.get_coin_mined(their_team)
	if ai._last_ai_mined >= 0:
		ai._ai_income_rate = float(my_mined - ai._last_ai_mined) / ai._aggression_interval
		ai._player_income_rate = float(their_mined - ai._last_player_mined) / ai._aggression_interval
	ai._last_ai_mined = my_mined
	ai._last_player_mined = their_mined
	# Scout memory for the counter-composition army mix (tier 3 reads it).
	_sample_player_composition()

	# Difficulty sets the aggression bias: defensive AIs need a bigger lead to
	# push and give up defense sooner; aggressive ones push on a slim lead.
	var thresholds: Vector2 = GameManager.get_aggression_thresholds()
	# Brute (Revamp Phase 8): mass-swordsman factions push mid-game on a
	# slimmer lead than other factions.
	var push_bias: float = 1.0
	var faction: FactionData = FactionManager.get_faction(ai.team)
	if faction != null and faction.faction_id == "brute":
		push_bias = 0.85
	if my_fighters > their_fighters * thresholds.x * push_bias:
		ai._aggression_level = "push"
	elif my_fighters < their_fighters * thresholds.y:
		ai._aggression_level = "defend"
	else:
		ai._aggression_level = "balanced"

	# Counter-attack window (smarts tier 2+): if the enemy just lost several
	# fighters since the last sample, strike immediately with whatever is
	# gathered instead of waiting out the wave timer — the enemy is at its
	# weakest right after losing a fight.
	if GameManager.get_ai_smarts() >= 2 and ai._last_player_fighters >= 0:
		if ai._last_player_fighters - their_fighters >= _Constants.ENEMY_COUNTERATTACK_DROP:
			ai._combat._launch_wave_if_ready(4)
	ai._last_player_fighters = their_fighters

	# Timing attack (smarts tier 2+): the enemy is out-economying us — strike
	# now with whatever is gathered, before the income gap widens. When we
	# out-economy them instead, no forced launch: keep scaling.
	if GameManager.get_ai_smarts() >= 2 \
			and ai._player_income_rate > ai._ai_income_rate * _Constants.ENEMY_ECON_PRESSURE_RATIO:
		ai._combat._launch_wave_if_ready(_Constants.ENEMY_TIMING_ATTACK_ARMY)


## Scout memory: EMA (alpha 0.3 per aggression-tick sample) of the enemy
## army's composition shares. Needs 3+ fighters for a meaningful read; below
## that the memory is left untouched.
func _sample_player_composition() -> void:
	var counts: Dictionary = { "swordsman": 0, "archer": 0, "wizard": 0, "dragon": 0 }
	var total: int = 0
	var other_team_name: String = "player" if ai.team == GameManager.Team.ENEMY else "enemy"
	for unit in ai.get_tree().get_nodes_in_group(other_team_name):
		if not unit.data.is_fighter or unit._state == Unit.State.DEAD:
			continue
		var unit_id: String = unit.data.unit_name.to_lower()
		if counts.has(unit_id):
			counts[unit_id] += 1
			total += 1
	if total < 3:
		return
	for unit_id in counts:
		var share: float = float(counts[unit_id]) / float(total)
		ai._player_comp_memory[unit_id] = lerpf(float(ai._player_comp_memory.get(unit_id, share)), share, 0.3)


func _apply_aggression_behavior() -> void:
	match ai._aggression_level:
		"push":
			# While pushing, check for a launch every frame instead of waiting
			# for the 18s wave tick — a gathered army marches immediately.
			ai._combat._launch_wave_if_ready()
			# Also attempt wall breach if miners have run out of accessible tiles.
			ai._combat._attempt_wall_breach()
		"defend":
			# Recall strays: fighters idling far from home fall back to the
			# base instead of being picked off across the map. garrison_home()
			# sets their standing point at the base, so they hold there.
			var building: Node2D = ai._combat._get_building()
			if building == null:
				return
			for unit in ai.get_tree().get_nodes_in_group(ai._combat.team_name()):
				if not unit.data.is_fighter or unit._state != Unit.State.IDLE or unit.is_underground:
					continue
				if unit.global_position.distance_to(building.global_position) > 650.0:
					unit.garrison_home()


## Smarts tier 2+, 1s tactics tick: wave-level retreat and recall. Two jobs:
## 1. While the base is under attack, wave fighters still marching or sieging
##    far away come home — an army that keeps sieging while its own base burns
##    is the classic dumb-AI tell. (The scout and the raid squad keep their
##    missions; the defense sweep handles everyone already home.)
## 2. An active wave the combat predictor says is being wiped pulls back to
##    heal and remass instead of fighting to zero. Desperate waves (launched
##    knowing the sim was bad, to deal damage) and all-ins against a
##    nearly-dead enemy base commit and never retreat. The veto gates the
##    relaunch afterwards, so a retreated wave re-masses instead of yo-yoing.
func _retreat_losing_wave() -> void:
	if GameManager.get_ai_smarts() < 2:
		return
	var building: Node2D = ai._combat._get_building()
	if building == null:
		return
	if ai._combat._nearest_enemy_fighter(building.global_position, 650) != null:
		for unit in ai.get_tree().get_nodes_in_group(ai._combat.team_name()):
			if not unit.data.is_fighter or unit._state != Unit.State.ATTACK:
				continue
			if unit == ai._scout or ai._raiders.has(unit):
				continue
			if unit.global_position.distance_to(building.global_position) > 700.0:
				unit.garrison_home()
		return
	var wave_age: float = GameManager.match_time - ai._last_wave_launched_at
	if wave_age < _Constants.ENEMY_WAVE_RETREAT_MIN_AGE or wave_age > _Constants.ENEMY_WAVE_ACTIVE_WINDOW:
		return
	if ai._last_wave_desperate:
		return
	var target: Node2D = ai._combat._get_enemy_building()
	if target != null:
		var hp_ratio: float = float(target.get("_hp")) / maxf(1.0, float(target.get("max_hp")))
		if hp_ratio < 0.25:
			return  # all-in: the nearly-dead enemy base must be finished
	if ai._smart._simulate_combat() >= _Constants.ENEMY_WAVE_RETREAT_SIM_RATIO:
		return
	for unit in ai.get_tree().get_nodes_in_group(ai._combat.team_name()):
		if not unit.data.is_fighter or unit._state != Unit.State.ATTACK:
			continue
		if unit == ai._scout or ai._raiders.has(unit):
			continue
		unit.garrison_home()


## Smarts tier 2+, 1s tactics tick: post-defense counterattack. While enemy
## fighters are inside the base defense radius the flag holds; the moment the
## threat clears — attackers dead or fled, army out of position walking home —
## the gathered army strikes immediately instead of waiting out the wave timer.
func _check_defense_counterattack() -> void:
	if GameManager.get_ai_smarts() < 2:
		return
	var building: Node2D = ai._combat._get_building()
	if building == null:
		return
	if ai._combat._nearest_enemy_fighter(building.global_position, 650) != null:
		ai._base_threatened = true
		return
	if not ai._base_threatened:
		return
	ai._base_threatened = false
	ai._combat._launch_wave_if_ready(_Constants.ENEMY_TIMING_ATTACK_ARMY)


## Smarts tier 2+: miner raids. Fighters cannot enter the enemy mine, so
## instead of chasing individual deposit trips (the old harass never caught
## one — exposed miners surface for seconds), a small squad camps between the
## enemy mine entry and the enemy base and ambushes every deposit trip
## walking past. Forcing miners to hide or die is economic damage even when
## nothing gets killed. Formation runs on the slow harass tick; management
## (_manage_raid) runs on the 1s tactics tick so the squad reacts in time.
## Never runs while defending, and never strips the wave below critical mass.
## A wave launch sweeps the raiders up (they are free IDLE/MOVE fighters), so
## raiding is what the army does BETWEEN waves, not instead of them.
func _run_harassment() -> void:
	if GameManager.get_ai_smarts() < 2:
		return
	if ai._aggression_level == "defend":
		return
	if not ai._raiders.is_empty():
		return  # a raid is already out — _manage_raid owns it
	var target_building: Node2D = ai._combat._get_enemy_building()
	if target_building == null:
		return
	var free_fighters: Array = []
	var total: int = 0
	for unit in ai.get_tree().get_nodes_in_group(ai._combat.team_name()):
		if not unit.data.is_fighter or unit._state == Unit.State.DEAD:
			continue
		total += 1
		if (unit._state == Unit.State.IDLE or unit._state == Unit.State.MOVE) and not unit.is_underground:
			free_fighters.append(unit)
	if total < ai._combat._wave_threshold(target_building) + 2:
		return
	var camp: Vector2 = _raid_camp_point()
	if camp == Vector2.INF:
		return
	# Send the fighters nearest the camp (shortest walk, least time exposed),
	# fanned out a little so the squad doesn't stack on one pixel.
	free_fighters.sort_custom(func(a: Unit, b: Unit) -> bool:
		return a.global_position.distance_squared_to(camp) < b.global_position.distance_squared_to(camp))
	var raid_count: int = mini(_Constants.ENEMY_RAID_SIZE, free_fighters.size())
	var building: Node2D = ai._combat._get_building()
	var inward: float = signf(building.global_position.x - camp.x) if building != null else 1.0
	for i in range(raid_count):
		var raider: Unit = free_fighters[i]
		raider.move_to(camp + Vector2(inward * float(i) * 40.0, 0.0))
		if raider._state == Unit.State.MOVE:
			ai._raiders.append(raider)
	if not ai._raiders.is_empty():
		ai._raid_started_at = GameManager.match_time


## 1s raid upkeep (tactics tick): prune losses, pull the squad out when the
## defense converges on the camp or the raid outstays its welcome, disband it
## when the army flips to defend, and walk drifted raiders back to the camp
## (idle auto-engagement legitimately chases a kill a short way off).
func _manage_raid() -> void:
	if GameManager.get_ai_smarts() < 2:
		return
	if ai._raiders.is_empty():
		return
	for raider in ai._raiders.duplicate():
		if not is_instance_valid(raider) or raider._state == Unit.State.DEAD:
			ai._raiders.erase(raider)
	if ai._raiders.is_empty():
		return
	if ai._aggression_level == "defend":
		_disband_raid(true)
		return
	var camp: Vector2 = _raid_camp_point()
	if camp == Vector2.INF:
		_disband_raid(true)
		return
	# Local odds check from the camp (the raiders' own eyes, roughly their
	# vision radius): if the defense shows up in force, the raid goes home
	# instead of trading 3 fighters for a miner.
	var defenders: int = 0
	var other_team_name: String = "player" if ai.team == GameManager.Team.ENEMY else "enemy"
	for unit in ai.get_tree().get_nodes_in_group(other_team_name):
		if not unit.data.is_fighter or unit._state == Unit.State.DEAD or unit.is_underground:
			continue
		if unit.global_position.distance_to(camp) <= _Constants.ENEMY_RAID_RETREAT_RADIUS:
			defenders += 1
	if defenders >= ai._raiders.size() + _Constants.ENEMY_RAID_RETREAT_ODDS:
		_disband_raid(true)
		return
	if GameManager.match_time - ai._raid_started_at >= _Constants.ENEMY_RAID_MAX_DURATION:
		_disband_raid(true)
		return
	for raider in ai._raiders:
		# _hold_post marks a raider garrisoned home (wounded retreat): leave it
		# to heal and be swept into the next wave instead of walking back.
		if raider._hold_post:
			continue
		if raider._state == Unit.State.IDLE and raider.global_position.distance_to(camp) > 500.0:
			raider.move_to(camp)


## Ends the raid. send_home garrisons the squad at the base (retreat); without
## it the raiders simply become regular army again where they stand.
func _disband_raid(send_home: bool) -> void:
	if send_home:
		for raider in ai._raiders:
			if is_instance_valid(raider) and raider._state != Unit.State.DEAD:
				raider.garrison_home()
	ai._raiders.clear()


## Where the raid camps: on the deposit route between the enemy mine entry and
## the enemy base, biased toward the entry so the squad isn't parked under the
## base's defenders. Returns Vector2.INF when neither landmark exists.
func _raid_camp_point() -> Vector2:
	var entry: Node2D = null
	for e in ai.get_tree().get_nodes_in_group("mine_entries"):
		if e.get("team") != ai.team:
			entry = e
			break
	var building: Node2D = ai._combat._get_enemy_building()
	if entry != null and building != null:
		return entry.get_surface_position().lerp(building.global_position, 0.35)
	if building != null:
		# No entry landmark: hover off the enemy base toward the map center.
		var inward: float = -1.0 if building.global_position.x > 0.0 else 1.0
		return building.global_position + Vector2(inward * 400.0, 0.0)
	return Vector2.INF


## Smarts tier 2+: bait and switch. A lone surface miner is sent strolling
## toward the enemy base; the moment enemy FIGHTERS come out to swat it, the
## gathered army launches at the now-undefended base. The bait flees when hit
## (standard miner behavior), which only sells the act. One bait at a time;
## a dead or released bait is replaced on the next bait tick.
func _run_bait() -> void:
	if GameManager.get_ai_smarts() < 2:
		return
	if ai._aggression_level == "defend":
		return
	var target_building: Node2D = ai._combat._get_enemy_building()
	if target_building == null:
		return
	if ai._bait_miner != null and is_instance_valid(ai._bait_miner) and ai._bait_miner._state != Unit.State.DEAD:
		# Spring the trap once an enemy fighter engages the bait. (A local
		# fighter-only loop: _nearest_enemy_unit would also see the enemy's
		# own deposit-trip miners, which walk past bait all day.)
		var other_team_name: String = "player" if ai.team == GameManager.Team.ENEMY else "enemy"
		for unit in ai.get_tree().get_nodes_in_group(other_team_name):
			if not unit.data.is_fighter or unit._state == Unit.State.DEAD:
				continue
			if unit.global_position.distance_to(ai._bait_miner.global_position) <= 300.0:
				ai._combat._launch_wave_if_ready(4)
				ai._bait_miner = null  # released: its idle handler resumes mining
				return
		return
	# No live bait: send the emptiest-bagged surface miner (underground miners
	# can't path to the surface). The army must be above critical mass, same
	# as harassment, so the sprung trap actually has teeth.
	var total: int = 0
	var candidate: Unit = null
	for unit in ai.get_tree().get_nodes_in_group(ai._combat.team_name()):
		if unit._state == Unit.State.DEAD:
			continue
		if unit.data.is_fighter:
			total += 1
		elif unit.data.is_miner and not unit.is_underground:
			if candidate == null or unit.carried_coin < candidate.carried_coin:
				candidate = unit
	if total < ai._combat._wave_threshold(target_building) + 2 or candidate == null:
		return
	var bait_point: Vector2 = target_building.global_position
	bait_point.x += 250.0 if ai.team == GameManager.Team.ENEMY else -250.0
	candidate.move_to(bait_point)
	if candidate._state == Unit.State.MOVE:
		ai._bait_miner = candidate


## Abstract combat predictor (no pathfinding): both armies are reduced to
## {hp, dps, hits_air, air} buckets and exchange 0.1s focus-fire steps for
## `duration` seconds (default ENEMY_COMBAT_SIM_DURATION) — each side pours
## its DPS into the lowest-HP enemy it can damage (dragon immunity respected:
## only archer/wizard DPS touches dragons; their DPS still hits ground targets
## too). Built enemy towers join their owner's side (they hit air too): the
## wave veto must see a turtled defense, or waves keep suiciding into towers
## the sim pretends don't exist. Only REMEMBERED enemy towers count (fog-honest
## intel, same rule as the wave's structure peel). Returns
## ai_hp_remaining / max(player_hp_remaining, 1).
func _simulate_combat(duration: float = -1.0) -> float:
	if duration <= 0.0:
		duration = _Constants.ENEMY_COMBAT_SIM_DURATION
	var ai_army: Array = []
	var player_army: Array = []
	for unit in ai.get_tree().get_nodes_in_group("units"):
		if not unit.data.is_fighter or unit._state == Unit.State.DEAD:
			continue
		var unit_id: String = unit.data.unit_name.to_lower()
		var bucket: Dictionary = {
			"hp": float(unit.hp),
			"dps": float(unit.data.damage_per_hit) / maxf(unit.data.attack_cooldown, 0.05),
			"hits_air": unit_id == "archer" or unit_id == "wizard",
			"air": unit_id == "dragon",
		}
		if unit.team == ai.team:
			ai_army.append(bucket)
		else:
			player_army.append(bucket)
	for tower in ai.get_tree().get_nodes_in_group("towers"):
		if not tower.is_built():
			continue  # invulnerable while under construction — no combat weight
		if tower.team != ai.team:
			if ai._grid == null or not ai._grid.is_remembered_by(ai.team, tower.global_position):
				continue  # never scouted: the AI honestly doesn't know it's there
		var tower_bucket: Dictionary = {
			"hp": float(tower.hp),
			"dps": float(tower.damage) / maxf(tower.attack_cooldown, 0.05),
			"hits_air": true,  # tower targeting has no air exclusion
			"air": false,
		}
		if tower.team == ai.team:
			ai_army.append(tower_bucket)
		else:
			player_army.append(tower_bucket)
	var steps: int = maxi(1, int(duration / 0.1))
	for i in range(steps):
		_sim_focus_step(ai_army, player_army)
		_sim_focus_step(player_army, ai_army)
	return _sim_army_hp(ai_army) / maxf(_sim_army_hp(player_army), 1.0)


## One 0.1s focus-fire step for one side. Anti-air DPS (archers/wizards) can
## hit everything; all other DPS only touches ground units.
func _sim_focus_step(attackers: Array, defenders: Array) -> void:
	var aa_dps: float = 0.0
	var ground_dps: float = 0.0
	for a in attackers:
		if a.hp <= 0.0:
			continue
		if a.hits_air:
			aa_dps += a.dps
		else:
			ground_dps += a.dps
	_sim_apply_damage(defenders, aa_dps * 0.1, true)
	_sim_apply_damage(defenders, ground_dps * 0.1, false)


## Pours `pool` damage into the lowest-HP living defender of the allowed set,
## spilling over to the next on each kill.
func _sim_apply_damage(defenders: Array, pool: float, include_air: bool) -> void:
	while pool > 0.0:
		var lowest: Dictionary = {}
		for d in defenders:
			if d.hp <= 0.0:
				continue
			if d.air and not include_air:
				continue
			if lowest.is_empty() or d.hp < lowest.hp:
				lowest = d
		if lowest.is_empty():
			return
		var dealt: float = minf(pool, lowest.hp)
		lowest.hp -= dealt
		pool -= dealt


func _sim_army_hp(army: Array) -> float:
	var total: float = 0.0
	for u in army:
		total += maxf(u.hp, 0.0)
	return total
