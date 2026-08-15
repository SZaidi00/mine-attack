class_name UnitCombat
extends RefCounted

const _DAMAGE_POPUP_SCENE: PackedScene = preload("res://scenes/effects/damage_popup.tscn")
const _PROJECTILE_SCENE: PackedScene = preload("res://scenes/projectile.tscn")

var unit: Unit

func _init(u: Unit) -> void:
	unit = u


## environmental = weather/terrain chip damage (Revamp Phase 5 snowstorm
## exposure): no popup, no hit flash, and no combat reflexes (miner flee,
## retaliation, Fight Back) — the storm is an attrition effect, not an
## attacker, so units keep following their current orders through it.
func take_damage(amount: int, attacker: Node2D = null, environmental: bool = false) -> void:
	# Corpses take no damage: a dying unit stays valid for its 1s fade-out and
	# in-flight projectiles can still land on it — without this guard each
	# extra hit re-runs _die() and leaks a population slot (army grows past
	# MAX_UNITS over a long match).
	if unit._state == Unit.State.DEAD:
		return
	if not can_be_damaged_by(attacker):
		_spawn_immune_popup()
		return
	# Bulwark research: flat damage reduction, but a hit always lands for 1+.
	if unit._armor > 0:
		amount = maxi(1, amount - unit._armor)
	unit.hp -= amount
	unit._regen_delay = Constants.UNIT_REGEN_DELAY
	unit._damage_log.append([0.0, amount])
	if not environmental:
		unit._hit_flash_timer = 0.15
		_spawn_damage_popup(amount)
		# Fight Back (Brute): miners hit back when a fighter strikes them in melee.
		unit._abilities.on_take_damage_fight_back(attacker)
	unit.queue_redraw()
	if unit.hp <= 0:
		# Supply Drop (Industrial): a dragon kill generates coin for its team.
		unit._abilities.on_kill_supply_drop(attacker)
		unit._die()
	elif not environmental:
		if unit.data.is_miner:
			unit._navigation._start_flee()
		else:
			_maybe_retaliate(attacker)


## Damage per second taken over the rolling 3s window (0 when untouched).
## The window span is measured from the oldest entry still in it, floored at
## 0.5s so a single fresh hit doesn't spike to infinity.
func get_incoming_dps() -> float:
	if unit._damage_log.is_empty():
		return 0.0
	var total: float = 0.0
	var span: float = 0.0
	for entry in unit._damage_log:
		total += entry[1]
		span = maxf(span, entry[0])
	return total / maxf(span, 0.5)


## Dragons only take damage from Archers and Wizards. All other units are
## fully vulnerable to any attacker (including null for legacy call sites).
func can_be_damaged_by(attacker: Node2D) -> bool:
	if unit.data == null or unit.data.unit_name.to_lower() != "dragon":
		return true
	if attacker == null or not is_instance_valid(attacker):
		return false
	if not (attacker is Unit):
		return false
	var atk_data: UnitData = attacker.data
	if atk_data == null:
		return false
	var unit_id: String = atk_data.unit_name.to_lower()
	return unit_id == "archer" or unit_id == "wizard"


## Combat never crosses the surface/underground boundary — flying dragons
## included. A* can't path between layers, so cross-layer locks only ever
## produced free hits on units (e.g. dragons sniping miners in the mine).
func can_damage_unit(target: Node2D) -> bool:
	if target == null or not is_instance_valid(target):
		return false
	if target is Unit and target.is_underground != unit.is_underground:
		return false
	if target.has_method("can_be_damaged_by"):
		return target.can_be_damaged_by(unit)
	return true


## Target re-evaluation while sieging: a fighter locked onto a building
## ignores nothing forever — when an enemy fighter damages it, it peels off
## to fight back, so a siege under fire turns into a real battle instead of a
## shooting gallery. Player units always retaliate; AI units roll per hit
## against the difficulty's retaliation chance. Units already engaging units
## are left alone, so a retaliate decision never flip-flops mid-duel.
func _maybe_retaliate(attacker: Node2D) -> void:
	if unit._state != Unit.State.ATTACK or unit._target_building == null:
		return
	if unit.team == GameManager.Team.ENEMY and randf() > GameManager.get_ai_retaliation_chance():
		return
	var target: Unit = _pick_retaliation_target(attacker)
	if target != null:
		DebugLog.log_command("Unit %d" % unit.get_instance_id(), "retaliate", "target=%d" % target.get_instance_id())
		unit._commands.attack_unit(target)


## Best unit to fight back against: the attacker itself when it is a reachable
## fighter nearby, otherwise the closest enemy fighter in sight on the same
## level (A* can't cross the surface/underground boundary).
func _pick_retaliation_target(attacker: Node2D) -> Unit:
	if attacker is Unit and is_instance_valid(attacker) and attacker._state != Unit.State.DEAD \
			and attacker.data.is_fighter and attacker.is_underground == unit.is_underground \
			and unit._vision._team_can_see(attacker.global_position) \
			and unit.combat_distance_squared_to(attacker) <= (unit.data.sight_range * 1.5) * (unit.data.sight_range * 1.5):
		return attacker
	var best: Unit = null
	var best_dist: float = unit.data.sight_range * unit.data.sight_range
	for u in unit.get_tree().get_nodes_in_group("units"):
		if u.team == unit.team or u._state == Unit.State.DEAD:
			continue
		if not u.data.is_fighter or u.is_underground != unit.is_underground:
			continue
		if not unit._vision._team_can_see(u.global_position):
			continue
		var d: float = unit.combat_distance_squared_to(u)
		if d <= best_dist:
			best_dist = d
			best = u
	return best


func _spawn_damage_popup(amount: int) -> void:
	var popup: DamagePopup = _DAMAGE_POPUP_SCENE.instantiate()
	popup.setup(amount)
	popup.global_position = unit.get_combat_position() + Vector2(0, -20)
	unit.get_tree().current_scene.add_child(popup)


func _spawn_immune_popup() -> void:
	var popup: DamagePopup = _DAMAGE_POPUP_SCENE.instantiate()
	popup.setup_immune()
	popup.global_position = unit.get_combat_position() + Vector2(0, -20)
	unit.get_tree().current_scene.add_child(popup)


func _spawn_heal_popup(amount: int) -> void:
	var popup: DamagePopup = _DAMAGE_POPUP_SCENE.instantiate()
	popup.setup(amount, true)
	popup.global_position = unit.get_combat_position() + Vector2(0, -20)
	unit.get_tree().current_scene.add_child(popup)


func _uses_fireball() -> bool:
	if unit.data == null:
		return false
	var unit_id: String = unit.data.unit_name.to_lower()
	return unit_id == "wizard" or unit_id == "dragon"


func _process_attack(delta: float) -> void:
	unit._attack_timer -= delta
	var path_pos: Vector2 = Vector2.ZERO  # Ground feet / stand point for A*.
	var range_pos: Vector2 = Vector2.ZERO  # Combat aim point for range + shots.
	var target_alive: bool = false

	if unit._target_unit != null and is_instance_valid(unit._target_unit) and unit._target_unit._state != Unit.State.DEAD:
		if unit._target_unit.is_underground != unit.is_underground:
			# The target crossed the surface/underground boundary mid-chase
			# (a miner escaped down the shaft) — the chase can't follow.
			unit._clear_target()
			unit._set_state(Unit.State.IDLE, "target crossed layers")
			return
		path_pos = unit._target_unit.global_position
		range_pos = unit._target_unit.get_combat_position() if unit._target_unit.has_method("get_combat_position") else path_pos
		target_alive = true
	elif unit._target_building != null and is_instance_valid(unit._target_building) \
			and (unit._target_building.is_in_group("buildings") or unit._target_building.is_in_group("lanterns") \
			or unit._target_building.is_in_group("towers") or unit._target_building.is_in_group("walls")):
		# Measure range to the closest point on the building's body rect, not
		# its center, so melee units engage at the edge of the footprint.
		var rect: Rect2 = unit._target_building.call("get_bounds_rect")
		range_pos = unit._navigation._closest_point_on_rect(rect, unit.get_combat_position())
		path_pos = unit._navigation._building_stand_point(unit._target_building)
		target_alive = true
	else:
		unit._set_state(Unit.State.IDLE, "target lost")
		return

	# Fog of War: a unit target that slipped out of the team's vision breaks
	# the lock — you cannot chase what you cannot see (Revamp Phase 1).
	# Longbow archers (Revamp Phase 6) keep the lock and blind-fire into fog.
	if unit._target_unit != null and target_alive and not unit._vision._has_blind_fire() and not unit._vision._team_can_see(unit._target_unit.global_position):
		unit._clear_target()
		unit._set_state(Unit.State.IDLE, "target lost to fog")
		return

	# Defend leash: an auto-engaged holder that chased too far from its
	# standing point lets go and heads home. Explicit orders are never
	# leashed (_auto_engaged is only set by the idle auto-attack scan).
	if unit._auto_engaged and unit._hold_post and not unit.is_underground and unit._post_point != Vector2.ZERO:
		if unit.global_position.distance_to(unit._post_point) > unit._vision._defend_leash_range():
			unit._clear_target()
			unit._set_state(Unit.State.IDLE, "defend leash reached")
			return

	if unit.get_combat_position().distance_to(range_pos) > unit.data.attack_range:
		# Re-path only when there is no path or the destination has moved
		# significantly (moving unit targets), not every physics frame.
		if unit._path.is_empty() or unit._path[unit._path.size() - 1].distance_to(path_pos) > GridWorld.CELL_SIZE * 0.75:
			unit._navigation._repath(path_pos)
		if unit._path.is_empty():
			unit._set_state(Unit.State.IDLE, "attack target unreachable")
			return
		unit._navigation._follow_path(delta)
		return

	unit._path.clear()
	# Ranged standoff: step back to re-establish distance before the next shot
	# whenever a threat slips inside the kite fraction of the attack range —
	# the current target, or any enemy melee unit closing in (so ranged units
	# never let melee reach them while firing at something else). Melee units
	# (attack_range <= 35) and building sieges are unaffected. Gaps use combat
	# positions (air vs ground); kite steering still moves feet on the ground.
	if unit.data.attack_range > 35.0:
		var kite_limit: float = unit.data.attack_range * Constants.UNIT_KITE_RANGE_FRACTION
		var threat_pos: Vector2 = Vector2.INF
		var threat_d2: float = INF
		if unit._target_unit != null:
			var target_d2: float = unit.combat_distance_squared_to(unit._target_unit)
			if target_d2 < kite_limit * kite_limit:
				threat_pos = path_pos
				threat_d2 = target_d2
		var melee: Unit = unit._vision._nearest_melee_threat(kite_limit)
		if melee != null and unit.combat_distance_squared_to(melee) < threat_d2:
			threat_pos = melee.global_position
		if threat_pos != Vector2.INF:
			unit._navigation._kite_away_from(threat_pos, delta)
	if unit._attack_timer <= 0:
		var cooldown: float = unit.data.attack_cooldown
		# Berserk (Brute): a wounded swordsman attacks 40% faster.
		cooldown = unit._abilities.apply_berserk_cdr(cooldown)
		unit._attack_timer = cooldown
		# Mana Burn debuff (Arcane dragon) dampens this hit, then wears off.
		var hit_damage: int = roundi(unit.data.damage_per_hit * unit._abilities.consume_mana_burn())
		# Rune Blade (Arcane): the first hit of each engagement deals +50%.
		hit_damage = unit._abilities.apply_rune_blade(hit_damage)
		unit._has_hit_this_engagement = true
		# Surface War (Revamp Phase 6): fighters deal bonus damage on the surface.
		if unit.data.is_fighter and not unit.is_underground and ResearchManager.has_branch(unit.team, "surface_war"):
			hit_damage = roundi(hit_damage * Constants.SURFACE_WAR_DMG_MULT)
		# Siege Master (Revamp Phase 6): swordsmen deal bonus damage to buildings.
		if unit._target_building != null and unit.data.unit_name.to_lower() == "swordsman" and ResearchManager.has_branch(unit.team, "siege_master"):
			hit_damage = roundi(hit_damage * Constants.SIEGE_MASTER_BUILDING_DMG_MULT)
		if unit.data.attack_range <= 35.0:
			# Melee
			AudioManager.play("sword", unit.global_position, -8.0)
			if unit._target_unit != null:
				unit._target_unit.take_damage(hit_damage, unit)
			elif unit._target_building != null:
				unit._target_building.call("take_damage", hit_damage)
		else:
			# Ranged projectile: aim at the point the range was measured to
			# (the enemy unit, or the closest point on the building's rect).
			_spawn_projectile(range_pos, hit_damage)
			# Volley (Industrial archer): nearby archers join the shot.
			unit._abilities.try_volley(range_pos)


func _spawn_projectile(target_pos: Vector2, hit_damage: int = -1) -> void:
	var fireball: bool = _uses_fireball()
	var spawn_pos: Vector2 = unit.get_combat_position()
	AudioManager.play("blast" if fireball else "bow", spawn_pos, -6.0)
	var proj: Node2D = _PROJECTILE_SCENE.instantiate()
	proj.position = spawn_pos
	proj.set("team", unit.team)
	proj.set("damage", hit_damage if hit_damage >= 0 else roundi(unit.data.damage_per_hit))
	proj.set("is_fireball", fireball)
	# Dragons breathe fire: same splash as a fireball, flame-breath visuals.
	proj.set("is_dragon_flame", unit.data.unit_name.to_lower() == "dragon")
	proj.set("speed", unit.data.projectile_speed)
	proj.set("aoe_radius", unit.data.aoe_radius)
	proj.set("target_position", target_pos)
	proj.set("source", unit)
	# Arcane Shot (Arcane archer): every 8s an arrow pierces through the first
	# target and strikes a second enemy behind it.
	unit._abilities.apply_arcane_shot_to_projectile(proj)
	# Try to find the actual target node for homing.
	if unit._target_unit != null and is_instance_valid(unit._target_unit):
		proj.set("homing_target", unit._target_unit)
	elif unit._target_building != null and is_instance_valid(unit._target_building):
		proj.set("homing_building", unit._target_building)
	unit.get_node("/root/Main/Projectiles").add_child(proj)
