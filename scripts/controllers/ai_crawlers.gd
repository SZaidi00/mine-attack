class_name AICrawlers
extends RefCounted

## Underground crawler guard / defense / raiding (see IDEAS.md "Underground
## combat: crawler unit"). Runs on the controller's 1s crawler tick.
##
## Defense (smarts tier 1+): when combat-capable enemy units show up in the
## AI's own mine (visible underground on the own half) or its underground
## miners take combat damage, threatened miners get shelter orders (they hold
## at the ladder bottom, using the same shelter_in_place machinery as weather
## recalls) and the crawler guard converges on the intruder. Shelters release
## when the threat clears. Environmental damage (cave-ins, lava) never
## triggers this — see Unit._damage_log.
##
## Offense (smarts tier 2+): once the central wall is breached, the spare
## crawlers (all but one guard) raid the enemy mine to hunt its miners. The
## raid pulls home when the enemy visibly outnumbers it underground, when a
## raider turns wounded, while the army defends, or when a home threat needs
## the guard back. Re-launch waits out ENEMY_CRAWLER_RAID_INTERVAL so a
## repelled raid doesn't yo-yo.

const _Constants = preload("res://scripts/autoload/constants.gd")

# Miners within this range of an intruder get shelter orders even before they
# are hit (the threat is coming for them anyway).
const _THREAT_SHELTER_RADIUS: float = 250.0
# A raider below this HP fraction walks home to heal (mirrors the fighter
# wounded-retreat ratio).
const _RAID_WOUNDED_HP_RATIO: float = 0.3

var ai: AIController

# Crawlers currently raiding the enemy mine. Entries are Unit refs; dead or
# freed units are pruned on each tick.
var _raiders: Array = []
# Miners sheltered by the underground-threat response (separate from the
# weather shelter list in ai_awareness — released when the threat clears).
var _sheltered_miners: Array = []
var _threat_active: bool = false
var _next_raid_time: float = 0.0


func _init(a: AIController) -> void:
	ai = a


## 1s tick from AIController._process.
func _run_crawlers() -> void:
	if GameManager.get_ai_smarts() < 1:
		return  # Easy never fields crawlers — nothing to command
	_prune()
	var threats: Array = _detect_threats()
	var distressed: Array = _distressed_miners()
	if not threats.is_empty() or not distressed.is_empty():
		_threat_active = true
		_respond_to_threat(threats, distressed)
	elif _threat_active:
		_threat_active = false
		_release_shelter()
	if not _threat_active:
		_manage_raid()


# ─── Defense ───

## Live-vision threat scan: combat-capable enemy units underground in the
## AI's half of the mine (the wall columns count — a breached doorway is the
## front line). Non-combat intruders (a wandering enemy miner without Fight
## Back) don't count — they can't hurt the crew, so sheltering would be pure
## lost mining time.
func _detect_threats() -> Array:
	var threats: Array = []
	var team_dir: int = 1 if ai.team == GameManager.Team.ENEMY else -1
	var other_team_name: String = "player" if ai.team == GameManager.Team.ENEMY else "enemy"
	for unit in ai.get_tree().get_nodes_in_group(other_team_name):
		if unit._state == Unit.State.DEAD or not unit.is_underground:
			continue
		if not _is_combat_threat(unit):
			continue
		if ai._grid.world_to_grid(unit.global_position).x * team_dir < -1:
			continue  # the enemy's own side — their business
		if not ai._grid.is_visible_to(ai.team, unit.global_position):
			continue
		threats.append(unit)
	return threats


## Fighters and crawlers are always threats; miners only when their faction
## gives them Fight Back (Brute) — otherwise they can't attack at all.
func _is_combat_threat(unit: Unit) -> bool:
	if unit.data == null:
		return false
	if unit.data.is_fighter or unit.data.is_crawler:
		return true
	var faction = unit.get("_faction")
	return unit.data.is_miner and faction != null and faction.get("miner_fight_back") == true


## Miners currently taking damage underground: the damage signal proves a
## threat even when the attacker has slipped the fog (their rolling damage
## window holds it for ~3s after the last hit).
func _distressed_miners() -> Array:
	var distressed: Array = []
	for unit in ai.get_tree().get_nodes_in_group(ai._combat.team_name()):
		if not unit.data.is_miner or unit._state == Unit.State.DEAD or not unit.is_underground:
			continue
		if unit.get_incoming_dps() > 0.0:
			distressed.append(unit)
	return distressed


func _respond_to_threat(threats: Array, distressed: Array) -> void:
	# Shelter threatened miners: under attack now, or standing next to a visible
	# intruder. They hold at the ladder bottom — the guard post — until the
	# all-clear (the ai_mining tick skips sheltered miners).
	for unit in distressed:
		_shelter_miner(unit)
	for unit in ai.get_tree().get_nodes_in_group(ai._combat.team_name()):
		if not unit.data.is_miner or unit._state == Unit.State.DEAD or not unit.is_underground:
			continue
		if _nearest_threat_distance(unit.global_position, threats) <= _THREAT_SHELTER_RADIUS:
			_shelter_miner(unit)
	# Intercept: the guard (and any recalled raider) converges on the threat.
	# Engaged crawlers keep their duel; fresh spawns still on the surface
	# descend first (their idle handler owns that walk).
	var interceptors: Array = []
	for unit in ai.get_tree().get_nodes_in_group(ai._combat.team_name()):
		if not unit.data.is_crawler or unit._state == Unit.State.DEAD or not unit.is_underground:
			continue
		if unit._state == Unit.State.IDLE or unit._state == Unit.State.MOVE:
			interceptors.append(unit)
	for crawler in interceptors:
		var target: Unit = _nearest_threat(crawler.global_position, threats)
		if target != null:
			crawler.attack_unit(target)
		elif not distressed.is_empty():
			# Unseen attacker: investigate the distress call — the crawler's own
			# lamp and auto-acquire take over once it gets close.
			crawler.move_to(_nearest_unit(crawler.global_position, distressed).global_position)


func _nearest_threat(pos: Vector2, threats: Array) -> Unit:
	var best: Unit = null
	var best_d2: float = INF
	for threat in threats:
		var d2: float = pos.distance_squared_to(threat.global_position)
		if d2 < best_d2:
			best_d2 = d2
			best = threat
	return best


func _nearest_unit(pos: Vector2, units: Array) -> Unit:
	var best: Unit = null
	var best_d2: float = INF
	for u in units:
		var d2: float = pos.distance_squared_to(u.global_position)
		if d2 < best_d2:
			best_d2 = d2
			best = u
	return best


func _nearest_threat_distance(pos: Vector2, threats: Array) -> float:
	var best: Unit = _nearest_threat(pos, threats)
	return pos.distance_to(best.global_position) if best != null else INF


func _shelter_miner(unit: Unit) -> void:
	if _sheltered_miners.has(unit):
		return
	unit.shelter_in_place = true
	_sheltered_miners.append(unit)
	if unit._state == Unit.State.IDLE:
		var entry: Node2D = _get_mine_entry()
		if entry != null:
			unit.move_to(entry.call("get_underground_position"))


## All-clear: release shelter orders; the next mining tick re-tasks the miners
## and the guard walks back to its post on its own idle handler.
func _release_shelter() -> void:
	for unit: Unit in _sheltered_miners:
		if is_instance_valid(unit):
			unit.shelter_in_place = false
	_sheltered_miners.clear()


# ─── Raiding ───

## Raid upkeep (only called with no home threat): launch through the breached
## wall, keep hunters hunting, pull out when visibly outnumbered underground
## or while the army defends. One crawler always stays home on guard.
func _manage_raid() -> void:
	if GameManager.get_ai_smarts() < 2:
		return
	if ai._grid.get_wall_hp() > 0:
		if not _raiders.is_empty():
			_disband_raid(true)  # the corridor sealed (shouldn't happen) — go home
		return
	if ai._aggression_level == "defend":
		if not _raiders.is_empty():
			_disband_raid(true)
		return
	if _raiders.is_empty():
		_try_launch_raid()
		return
	# Outnumbered underground: pull the raid home instead of feeding it.
	if _visible_enemy_crawlers() > _raiders.size():
		_disband_raid(true)
		return
	for raider in _raiders.duplicate():
		if float(raider.hp) < float(raider.data.max_hp) * _RAID_WOUNDED_HP_RATIO:
			_raiders.erase(raider)
			_send_home(raider)
			continue
		if raider._state == Unit.State.IDLE:
			_hunt_order(raider)


func _try_launch_raid() -> void:
	if GameManager.match_time < _next_raid_time:
		return
	var guards: Array = []
	for unit in ai.get_tree().get_nodes_in_group(ai._combat.team_name()):
		if not unit.data.is_crawler or unit._state == Unit.State.DEAD or not unit.is_underground:
			continue
		if unit._state == Unit.State.IDLE or unit._state == Unit.State.MOVE:
			guards.append(unit)
	if guards.size() < _Constants.ENEMY_CRAWLER_RAID_MIN_COUNT:
		return
	# All but one raid; the last stays home as the mine guard.
	for i in range(guards.size() - 1):
		_hunt_order(guards[i])
		_raiders.append(guards[i])
	_next_raid_time = GameManager.match_time + _Constants.ENEMY_CRAWLER_RAID_INTERVAL


## A raider's orders: attack a visible enemy miner underground, else march on
## the enemy mine — its own auto-acquire hunts whatever it can see on the way
## (crawler targeting has no midfield rule).
func _hunt_order(raider: Unit) -> void:
	var target: Unit = _nearest_visible_enemy_miner(raider.global_position)
	if target != null:
		raider.attack_unit(target)
		return
	for entry in ai.get_tree().get_nodes_in_group("mine_entries"):
		if entry.get("team") != ai.team:
			raider.move_to(entry.call("get_underground_position"))
			return


func _nearest_visible_enemy_miner(pos: Vector2) -> Unit:
	var best: Unit = null
	var best_d2: float = INF
	var other_team_name: String = "player" if ai.team == GameManager.Team.ENEMY else "enemy"
	for unit in ai.get_tree().get_nodes_in_group(other_team_name):
		if not unit.data.is_miner or unit._state == Unit.State.DEAD or not unit.is_underground:
			continue
		if not ai._grid.is_visible_to(ai.team, unit.global_position):
			continue
		var d2: float = pos.distance_squared_to(unit.global_position)
		if d2 < best_d2:
			best_d2 = d2
			best = unit
	return best


## Enemy crawlers the AI can currently see underground — the retreat rule reads
## live vision only (fog-honest: unknown numbers don't scare the raid off).
func _visible_enemy_crawlers() -> int:
	var n: int = 0
	var other_team_name: String = "player" if ai.team == GameManager.Team.ENEMY else "enemy"
	for unit in ai.get_tree().get_nodes_in_group(other_team_name):
		if not unit.data.is_crawler or unit._state == Unit.State.DEAD or not unit.is_underground:
			continue
		if ai._grid.is_visible_to(ai.team, unit.global_position):
			n += 1
	return n


## Ends the raid. send_home walks the squad back to the guard post at the own
## mine entry; without it they simply guard wherever they stand.
func _disband_raid(send_home: bool) -> void:
	if send_home:
		for raider in _raiders:
			if is_instance_valid(raider) and raider._state != Unit.State.DEAD:
				_send_home(raider)
	_raiders.clear()
	_next_raid_time = GameManager.match_time + _Constants.ENEMY_CRAWLER_RAID_INTERVAL


func _send_home(crawler: Unit) -> void:
	var entry: Node2D = _get_mine_entry()
	if entry != null:
		crawler.move_to(entry.call("get_underground_position"))


func _get_mine_entry() -> Node2D:
	for entry in ai.get_tree().get_nodes_in_group("mine_entries"):
		if entry.get("team") == ai.team:
			return entry
	return null


func _prune() -> void:
	for unit in _raiders.duplicate():
		if not is_instance_valid(unit) or unit._state == Unit.State.DEAD:
			_raiders.erase(unit)
	for unit in _sheltered_miners.duplicate():
		if not is_instance_valid(unit) or unit._state == Unit.State.DEAD:
			_sheltered_miners.erase(unit)
