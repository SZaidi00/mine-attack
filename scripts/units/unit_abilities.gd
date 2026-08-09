class_name UnitAbilities
extends RefCounted

var unit: Unit

func _init(u: Unit) -> void:
	unit = u


## Heavy Bolt (Brute archer): slow this unit's movement for a short duration.
func apply_slow(mult: float, duration: float) -> void:
	if unit._state == Unit.State.DEAD:
		return
	unit._slow_mult = mult
	unit._slow_timer = duration


## Crush (Brute dragon): brief hard stun — no movement or attacks.
func apply_stun(duration: float) -> void:
	if unit._state == Unit.State.DEAD:
		return
	unit._stun_timer = maxf(unit._stun_timer, duration)


## Blink (wizard): when a melee enemy gets point-blank, teleport a few cells
## directly away from it. Every wizard has it on a 15s cooldown; Arcane's
## reduction shortens that to 10s. The target lock survives the teleport.
func try_blink() -> void:
	var threat: Unit = unit._vision._nearest_melee_threat(40.0)
	if threat == null:
		return
	var away: Vector2 = unit.global_position - threat.global_position
	if away.length_squared() < 0.001:
		away = Vector2.LEFT if unit.team == GameManager.Team.PLAYER else Vector2.RIGHT
	away = away.normalized()
	for dist: float in [96.0, 64.0, 32.0]:
		var dest: Vector2 = unit.global_position + away * dist
		if unit._navigation._is_walkable_point(dest):
			unit.global_position = dest
			unit._path.clear()
			unit._path_index = 0
			unit._blink_timer = 15.0 - (unit._faction.wizard_blink_reduction if unit._faction != null else 0.0)
			AudioManager.play("blast", unit.global_position, -12.0)
			return
	# Nowhere to go — retry soon instead of burning the full cooldown.
	unit._blink_timer = 1.0


## Volley (Industrial): every friendly archer within 50px joins this shot,
## firing at the same target area at once. Everyone involved shares the 12s
## cooldown so volleys can't chain into each other.
func trigger_volley(target_pos: Vector2) -> void:
	unit._volley_timer = 12.0
	for u in unit.get_tree().get_nodes_in_group("units"):
		if u == unit or u.team != unit.team or u._state == Unit.State.DEAD:
			continue
		if u.data == null or u.data.unit_name.to_lower() != "archer":
			continue
		if u.is_underground != unit.is_underground:
			continue
		if unit.global_position.distance_to(u.global_position) > 50.0:
			continue
		u._volley_timer = 12.0
		u._combat._spawn_projectile(target_pos)


## Swarm (Industrial): +15% speed while 3+ friendly swordsmen (this one
## included) are within 6 cells. Restores the captured base speed when the
## group breaks up.
func update_swarm() -> void:
	var nearby: int = 1
	var radius_sq: float = 192.0 * 192.0
	for u in unit.get_tree().get_nodes_in_group("units"):
		if u == unit or u.team != unit.team or u._state == Unit.State.DEAD:
			continue
		if u.data == null or u.data.unit_name.to_lower() != "swordsman":
			continue
		if unit.global_position.distance_squared_to(u.global_position) <= radius_sq:
			nearby += 1
	var active: bool = nearby >= 3
	if active != unit._swarm_active:
		unit._swarm_active = active
		unit.data.speed = unit._base_speed * (1.15 if active else 1.0)


## Miner Reveal (Arcane): a personal 4-cell ore scan every 30s while
## underground — same reveal mechanism as the Ore Sonar research.
func miner_reveal_scan() -> void:
	unit._grid.reveal_ore_in_radius(unit._grid.world_to_grid(unit.global_position), 4, unit.team)


## Berserk (Brute): a wounded swordsman attacks 40% faster.
func apply_berserk_cdr(cooldown: float) -> float:
	if unit._faction != null and unit._faction.swordsman_berserk and unit.data.unit_name.to_lower() == "swordsman" \
			and unit.hp * 10 < unit.data.max_hp * 3:
		return cooldown / 1.4
	return cooldown


## Rune Blade (Arcane): the first hit of each engagement deals +50%.
func apply_rune_blade(hit_damage: int) -> int:
	if unit._faction != null and unit._faction.swordsman_rune_blade and unit.data.unit_name.to_lower() == "swordsman" \
			and not unit._has_hit_this_engagement:
		return roundi(hit_damage * 1.5)
	return hit_damage


## Mana Burn debuff (Arcane dragon) dampens this hit, then wears off.
func consume_mana_burn() -> float:
	var mult: float = unit._next_attack_damage_mult
	unit._next_attack_damage_mult = 1.0
	return mult


## Arcane Shot (Arcane archer): every 8s an arrow pierces through the first
## target and strikes a second enemy behind it.
func apply_arcane_shot_to_projectile(proj: Node2D) -> void:
	if unit._faction != null and unit._faction.archer_arcane_shot and unit.data.unit_name.to_lower() == "archer" \
			and not unit._combat._uses_fireball() and unit._arcane_shot_timer <= 0.0:
		unit._arcane_shot_timer = 8.0
		proj.set("pierce", true)


## Volley trigger check + execution from _process_attack.
func try_volley(target_pos: Vector2) -> void:
	if unit._faction != null and unit._faction.archer_volley and unit.data.unit_name.to_lower() == "archer" \
			and unit._volley_timer <= 0.0:
		trigger_volley(target_pos)


## Fight Back (Brute): miners hit back when a fighter strikes them in melee.
func on_take_damage_fight_back(attacker: Node2D) -> void:
	if unit._faction != null and unit._faction.miner_fight_back and unit.data.is_miner and attacker is Unit \
			and is_instance_valid(attacker) and attacker._state != Unit.State.DEAD \
			and attacker.data != null and attacker.data.is_fighter:
		attacker.take_damage(5, unit)


## Supply Drop (Industrial): a dragon kill generates coin for its team.
func on_kill_supply_drop(attacker: Node2D) -> void:
	if attacker is Unit and is_instance_valid(attacker) and attacker.data != null \
			and attacker.data.unit_name.to_lower() == "dragon":
		var attacker_faction: FactionData = FactionManager.get_faction(attacker.team)
		if attacker_faction != null and attacker_faction.dragon_supply_drop:
			EconomyManager.add_coin(attacker.team, 10)


## Efficiency (Industrial): ore yields bonus gold per swing.
func apply_miner_ore_yield(coin: int) -> int:
	if unit._faction != null and unit._faction.miner_ore_yield_mult != 1.0:
		return roundi(coin * unit._faction.miner_ore_yield_mult)
	return coin
