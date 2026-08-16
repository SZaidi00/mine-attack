class_name UnitVisionTargeting
extends RefCounted

var unit: Unit

func _init(u: Unit) -> void:
	unit = u


## Fog of War vision radius in grid cells (Revamp Phase 1). Miners see less
## underground than on the surface; dragons only get their big flight radius
## above ground. Everything else uses its flat per-type radius on the surface.
func get_vision_radius() -> int:
	if unit.data == null:
		return 0
	if unit.data.is_miner:
		return Constants.VISION_MINER_UNDERGROUND if unit.is_underground else Constants.VISION_MINER_SURFACE
	match unit.data.unit_name.to_lower():
		"swordsman":
			return Constants.VISION_SWORDSMAN
		"archer":
			return Constants.VISION_ARCHER
		"wizard":
			return Constants.VISION_WIZARD
		"dragon":
			return Constants.VISION_DRAGON if not unit.is_underground else Constants.VISION_MINER_UNDERGROUND
		"pigeon":
			return Constants.VISION_PIGEON
	return 0


## Which layer(s) this unit's lamp lights (Revamp Phase 1): miners only
## reveal the layer they are on — vision no longer bleeds through the
## surface ceiling or across the central wall into the enemy mine. Surface
## fighters and flying units light only the surface; underground vision is
## reserved for underground miners and mine lanterns.
func get_vision_layer() -> int:
	if unit.data != null and unit.data.is_miner:
		return GridWorld.VISION_LAYER_UNDERGROUND if unit.is_underground else GridWorld.VISION_LAYER_SURFACE
	return GridWorld.VISION_LAYER_SURFACE


## Fog of War: true while this unit's team can currently see world_pos.
func _team_can_see(world_pos: Vector2) -> bool:
	return unit._grid.is_visible_to(unit.team, world_pos)


## Longbow (Revamp Phase 6): archers blind-fire into fog — their targeting
## skips the visibility gate.
func _has_blind_fire() -> bool:
	return unit.data.unit_name.to_lower() == "archer" and ResearchManager.has_branch(unit.team, "longbow")


func _team_dir() -> int:
	return -1 if unit.team == GameManager.Team.PLAYER else 1


func _is_enemy_underground(world_pos: Vector2) -> bool:
	if world_pos.y <= GridWorld.CELL_SIZE:
		return false
	return world_pos.x * _team_dir() < 0


## Effective defend-leash radius: normally UNIT_DEFEND_LEASH_RANGE, but while
## the team's own building is under attack it pulls in tight so defenders
## finish the fight at the base instead of being lured away by retreating
## attackers.
func _defend_leash_range() -> float:
	var building: Node2D = unit._friendly_building()
	if building != null and building.call("is_under_attack"):
		return Constants.UNIT_DEFEND_LEASH_UNDER_ATTACK
	return Constants.UNIT_DEFEND_LEASH_RANGE


func _find_auto_attack_target():
	# Defend leash: a holder only notices targets near its standing point, so
	# a defend-mode unit can't be lured across the map one fight at a time.
	var leashed: bool = unit._hold_post and not unit.is_underground and unit._post_point != Vector2.ZERO
	var leash: float = _defend_leash_range()
	var leash_d2: float = leash * leash
	# Enemy fighters: attack range first, then sight range. Closest wins —
	# except fireball users (wizard/dragon), who pick the target whose position
	# splashes the most enemies so fireballs aren't wasted on lone stragglers.
	for range_limit in [unit.data.attack_range, unit.data.sight_range]:
		if unit._combat._uses_fireball() and unit.data.aoe_radius > 0.0:
			var splash: Unit = _pick_splash_target(range_limit)
			if splash != null and not (leashed and unit._post_point.distance_squared_to(splash.global_position) > leash_d2):
				return splash
		else:
			var best: Unit = null
			var best_dist: float = range_limit * range_limit
			for u in unit.get_tree().get_nodes_in_group("units"):
				if u.team == unit.team or u._state == Unit.State.DEAD:
					continue
				if not u.data.is_fighter and not u.data.is_scout:
					continue
				if not unit._combat.can_damage_unit(u):
					continue
				# Fog of War: cannot auto-attack what the team cannot see
				# (Longbow archers blind-fire past this, Revamp Phase 6).
				if not _has_blind_fire() and not _team_can_see(u.global_position):
					continue
				if leashed and unit._post_point.distance_squared_to(u.global_position) > leash_d2:
					continue
				var d: float = unit.combat_distance_squared_to(u)
				if d <= best_dist:
					best_dist = d
					best = u
			if best != null:
				return best

	# 3. Enemy building in sight range (a static target counts if the team
	# remembers it), and enemy lanterns/towers (also valid on remembered
	# intel — structures don't move). Walls are only attacked on explicit
	# orders or the sealed-path breach fallback
	# (UnitCommands._breach_nearest_enemy_wall).
	var enemy_building: Node2D = unit._get_enemy_building()
	if enemy_building != null and unit._grid.is_remembered_by(unit.team, enemy_building.global_position):
		if leashed and unit._post_point.distance_squared_to(enemy_building.global_position) > leash_d2:
			return null  # defending means defending: never auto-siege from a held post
		var d: float = unit.get_combat_position().distance_squared_to(enemy_building.global_position)
		if d <= unit.data.sight_range * unit.data.sight_range:
			return enemy_building
	var enemy_structure: Node2D = _nearest_visible_enemy_structure()
	if enemy_structure != null:
		if not (leashed and unit._post_point.distance_squared_to(enemy_structure.global_position) > leash_d2):
			var d: float = unit.get_combat_position().distance_squared_to(enemy_structure.global_position)
			if d <= unit.data.sight_range * unit.data.sight_range:
				return enemy_structure

	# 4. Enemy miners on our side of the wall (underground only).
	if unit.is_underground:
		var best: Unit = null
		var best_dist: float = unit.data.sight_range * unit.data.sight_range
		var team_dir: int = _team_dir()
		for u in unit.get_tree().get_nodes_in_group("units"):
			if u.team == unit.team or u._state == Unit.State.DEAD:
				continue
			if not u.data.is_miner:
				continue
			if not unit._combat.can_damage_unit(u):
				continue
			# Fog of War: cannot auto-attack what the team cannot see.
			if not _team_can_see(u.global_position):
				continue
			var grid_x: int = unit._grid.world_to_grid(u.global_position).x
			if grid_x * team_dir < 2:
				continue
			var d: float = unit.combat_distance_squared_to(u)
			if d <= best_dist:
				best_dist = d
				best = u
		if best != null:
			return best
	return null


## Rally targets: any living enemy on the surface — fighters AND miners.
## Underground enemies are out of scope (the rally sweep is a surface hunt).
## Skip targets this unit cannot damage (e.g. swordsman vs dragon).
func _find_rally_target() -> Unit:
	if unit.is_underground:
		return null
	var best: Unit = null
	var best_dist: float = unit.data.sight_range * unit.data.sight_range
	for u in unit.get_tree().get_nodes_in_group("units"):
		if u.team == unit.team or u._state == Unit.State.DEAD:
			continue
		if u.is_underground:
			continue
		if not unit._combat.can_damage_unit(u):
			continue
		# Fog of War: cannot hunt what the team cannot see.
		if not _team_can_see(u.global_position):
			continue
		var d: float = unit.combat_distance_squared_to(u)
		if d <= best_dist:
			best_dist = d
			best = u
	return best


## Nearest built enemy wall segment, at any distance and regardless of fog —
## a wall sealing the route is a physical fact the unit has just discovered by
## failing to path. Used to turn an unreachable siege target into a wall
## breach instead of freezing (breaking the wall unseals its column).
func _nearest_enemy_wall() -> Node2D:
	var best: Node2D = null
	var best_d2: float = INF
	for wall in unit.get_tree().get_nodes_in_group("walls"):
		if wall.team == unit.team or not wall.is_built():
			continue
		var d2: float = unit.global_position.distance_squared_to(wall.global_position)
		if d2 < best_d2:
			best_d2 = d2
			best = wall
	return best


## Nearest built enemy lantern or tower the team remembers seeing (Fog of War
## target scan helper). Structures are static, so remembered intel stays
## actionable — fog no longer grants them free invulnerability the moment live
## vision moves on.
func _nearest_visible_enemy_structure() -> Node2D:
	var best: Node2D = null
	var best_dist: float = INF
	for group: String in ["lanterns", "towers"]:
		for structure in unit.get_tree().get_nodes_in_group(group):
			if structure.team == unit.team or not structure.is_built():
				continue
			if not unit._grid.is_remembered_by(unit.team, structure.global_position):
				continue
			var d: float = unit.get_combat_position().distance_squared_to(structure.global_position)
			if d < best_dist:
				best_dist = d
				best = structure
	return best


## Splash-aware fighter pick for fireball users: the damageable enemy fighter
## within max_dist whose position catches the most enemy units in the AoE
## (counting the target itself), closest on ties.
func _pick_splash_target(max_dist: float) -> Unit:
	var best: Unit = null
	var best_score: float = -INF
	var best_d2: float = INF
	var max_d2: float = max_dist * max_dist
	for u in unit.get_tree().get_nodes_in_group("units"):
		if u.team == unit.team or u._state == Unit.State.DEAD:
			continue
		if not u.data.is_fighter:
			continue
		if not unit._combat.can_damage_unit(u):
			continue
		# Fog of War: cannot target what the team cannot see.
		if not _team_can_see(u.global_position):
			continue
		var d2: float = unit.combat_distance_squared_to(u)
		if d2 > max_d2:
			continue
		var score: float = 1.0
		for other in unit.get_tree().get_nodes_in_group("units"):
			if other == u or other.team == unit.team or other._state == Unit.State.DEAD:
				continue
			if other.is_underground != u.is_underground:
				continue
			if other.global_position.distance_squared_to(u.global_position) <= unit.data.aoe_radius * unit.data.aoe_radius:
				score += 1.0
		if score > best_score or (score == best_score and d2 < best_d2):
			best_score = score
			best_d2 = d2
			best = u
	return best


## Nearest enemy melee fighter (attack_range <= 35) within max_dist on the
## same layer. Ranged units kite away from it even while shooting something
## else, so melee never closes for free.
func _nearest_melee_threat(max_dist: float) -> Unit:
	var best: Unit = null
	var best_d2: float = max_dist * max_dist
	for u in unit.get_tree().get_nodes_in_group("units"):
		if u.team == unit.team or u._state == Unit.State.DEAD:
			continue
		if not u.data.is_fighter or u.data.attack_range > 35.0:
			continue
		if u.is_underground != unit.is_underground:
			continue
		# Fog of War: unseen melee cannot be kited (it also cannot be fought).
		if not _team_can_see(u.global_position):
			continue
		var d2: float = unit.combat_distance_squared_to(u)
		if d2 <= best_d2:
			best_d2 = d2
			best = u
	return best
