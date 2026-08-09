class_name UnitNavigation
extends RefCounted

var unit: Unit

func _init(u: Unit) -> void:
	unit = u


func _follow_path(delta: float) -> void:
	if unit._path.is_empty() or unit._path_index >= unit._path.size():
		# Climb states handle arrival themselves; don't drop back to IDLE.
		if unit._state != Unit.State.CLIMB_UP and unit._state != Unit.State.CLIMB_DOWN:
			unit._set_state(Unit.State.IDLE, "path empty/start")
		return
	var target: Vector2 = unit._path[unit._path_index]
	var dist: float = target.distance_to(unit.global_position)
	# Arrive when within one movement step of the point (or 2px, whichever is
	# larger). Without the step-aware threshold, a large delta (lag spike, high
	# time scale) plus the separation nudge can orbit the point forever without
	# ever coming within 2px at the start of a frame.
	var step: float = unit.data.speed * unit._slow_mult * _weather_speed_mult() * delta
	if unit.is_underground and unit.data.is_fighter:
		step *= 0.6
	var arrive: float = maxf(2.0, step)
	# Advance past every point the step covers — at high game speeds with a
	# low frame rate a single step can span several cell centers.
	while dist <= arrive:
		unit._path_index += 1
		if unit._path_index >= unit._path.size():
			# Move onto the final point before transitioning. Without this a
			# large step completes the path while still far from the
			# destination (e.g. out of mining range), and the miner freezes
			# mid-approach bouncing between MINE and IDLE at 10x speed.
			unit.global_position = unit.global_position.move_toward(target, minf(step, dist))
			if unit._state != Unit.State.CLIMB_UP and unit._state != Unit.State.CLIMB_DOWN:
				unit._set_state(Unit.State.IDLE, "path completed")
			return
		target = unit._path[unit._path_index]
		dist = target.distance_to(unit.global_position)
	var dir: Vector2 = target - unit.global_position
	var move: Vector2 = dir.normalized() * minf(step, dist)
	# Phase 3.4: soft separation so same-team units don't hard-collide or stack.
	# Skip separation while walking to a ladder; it can push the unit away from
	# the exact ladder bottom/top and make it oscillate around the arrival threshold.
	if unit._state != Unit.State.CLIMB_UP and unit._state != Unit.State.CLIMB_DOWN:
		var separation: Vector2 = _compute_separation()
		if separation != Vector2.ZERO:
			move += separation.normalized() * min(step * 0.6, separation.length())
	# Revamp Phase 3: never step into a built wall's cell — A* routes around
	# it, but a large step or the separation nudge could otherwise carry the
	# unit straight through. A unit already inside the cell when the wall went
	# up is always allowed to step out.
	if not _is_wall_at(unit.global_position + move) or _is_wall_at(unit.global_position):
		unit.global_position += move


## Snowstorm slowdown (Revamp Phase 5): surface units move at
## SNOWSTORM_SPEED_MULT while a storm rages; underground units are sheltered.
func _weather_speed_mult() -> float:
	if unit.is_underground:
		return 1.0
	return WeatherManager.get_speed_multiplier()


## Phase 3.4: push away from nearby friendly units to avoid stacking and
## single-file parade artifacts. This is a soft steering nudge, not physics.
func _compute_separation() -> Vector2:
	var sep: Vector2 = Vector2.ZERO
	var radius: float = 22.0
	var radius_sq: float = radius * radius
	for u in unit.get_tree().get_nodes_in_group(unit.team_name()):
		if u == unit or u._state == Unit.State.DEAD:
			continue
		var offset: Vector2 = unit.global_position - u.global_position
		var dist_sq: float = offset.length_squared()
		if dist_sq > 0.001 and dist_sq < radius_sq:
			# Stronger repulsion as units get closer.
			sep += offset.normalized() * (radius - sqrt(dist_sq))
	return sep


## Ranged kiting: a direct steering step away from a closing threat. Deliberately
## not a path/move command — the ATTACK state (and its target) must survive, so
## the unit keeps firing on cooldown while it backs off.
func _kite_away_from(threat_pos: Vector2, delta: float) -> void:
	var away: Vector2 = unit.global_position - threat_pos
	if away.length_squared() < 0.001:
		away = Vector2.LEFT
	var step: float = unit.data.speed * unit._slow_mult * _weather_speed_mult() * delta
	if unit.is_underground and unit.data.is_fighter:
		step *= 0.6
	var next_pos: Vector2 = unit.global_position + away.normalized() * step
	if _is_walkable_point(next_pos):
		unit.global_position = next_pos


func _repath(target_world: Vector2) -> void:
	# Team is passed so own walls never block their builder (Phase 3 seals).
	unit._path = unit._grid.find_path(unit.global_position, target_world, unit.team)
	unit._path_index = 0
	# Skip the first point if it is the current cell or if moving to it would
	# send us backward relative to the overall target direction (can happen when
	# the unit spawns on a sub-cell position and A* returns the cell center).
	if unit._path.size() > 1:
		var to_first: Vector2 = unit._path[0] - unit.global_position
		var to_target: Vector2 = target_world - unit.global_position
		if to_first.distance_to(Vector2.ZERO) < 4.0 or to_first.dot(to_target) < 0.0:
			unit._path_index = 1


func _nearest_adjacent_world(grid_pos: Vector2i) -> Vector2:
	var best: Vector2 = unit._grid.grid_to_world(grid_pos)
	var best_dist: float = 999999.0
	for off in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
		var adj: Vector2i = grid_pos + off
		if not unit._grid.is_solid(adj):
			var pos: Vector2 = unit._grid.grid_to_world(adj)
			var d: float = unit.global_position.distance_squared_to(pos)
			if d < best_dist:
				best_dist = d
				best = pos
	return best


## True when the current A* path ends on the target cell or one of its
## orthogonal/diagonal neighbours. find_path() redirects blocked endpoints to
## the nearest walkable cell, so a non-empty path can stop one cell short even
## though the miner can still stand next to the tile and dig.
func _path_reaches(world_target: Vector2) -> bool:
	if unit._path.is_empty():
		return false
	var end_grid: Vector2i = unit._grid.world_to_grid(unit._path[unit._path.size() - 1])
	var target_grid: Vector2i = unit._grid.world_to_grid(world_target)
	var diff: Vector2i = (end_grid - target_grid).abs()
	return diff.x <= 1 and diff.y <= 1


func _closest_point_on_rect(rect: Rect2, point: Vector2) -> Vector2:
	return Vector2(
		clampf(point.x, rect.position.x, rect.end.x),
		clampf(point.y, rect.position.y, rect.end.y)
	)


## Where to stand to attack a building: on the walkable surface row at its
## base, horizontally clamped to the building's span.
func _building_stand_point(building: Node2D) -> Vector2:
	var rect: Rect2 = building.call("get_bounds_rect")
	var x: float = clampf(unit.global_position.x, rect.position.x, rect.end.x)
	return Vector2(x, rect.end.y + GridWorld.CELL_SIZE * 0.5)


## Cheap point walkability for kiting (no A*): the surface row is open ground;
## underground only EMPTY cells can be stood on. Built wall segments block
## their cell either way.
func _is_walkable_point(world_pos: Vector2) -> bool:
	if _is_wall_at(world_pos):
		return false
	if world_pos.y <= GridWorld.CELL_SIZE:
		return world_pos.y >= 0.0 \
			and world_pos.x >= GridWorld.X_MIN * GridWorld.CELL_SIZE \
			and world_pos.x <= (GridWorld.X_MAX + 1) * GridWorld.CELL_SIZE
	var cell: GridWorld.Cell = unit._grid.get_cell(unit._grid.world_to_grid(world_pos))
	return cell != null and cell.type == GridWorld.CellType.EMPTY


## True when a built (not under-construction) ENEMY wall segment occupies the
## cell containing world_pos. Own walls never block their team (Phase 3).
func _is_wall_at(world_pos: Vector2) -> bool:
	var cell: Vector2i = unit._grid.world_to_grid(world_pos)
	for wall in unit.get_tree().get_nodes_in_group("walls"):
		if wall.team != unit.team and wall.is_built() and wall.get_cell() == cell:
			return true
	return false


func _start_flee() -> void:
	unit._flee_timer = 3.0
	var friendly_fighter: Unit = unit._idle._nearest_friendly_fighter()
	# Only flee to a fighter on the same level; A* can't cross the
	# surface/underground boundary, so a surface fighter can't save a miner
	# underground (and vice versa).
	if friendly_fighter != null and friendly_fighter.is_underground == unit.is_underground and unit.global_position.distance_to(friendly_fighter.global_position) <= 300:
		unit._flee_target = friendly_fighter.global_position
	else:
		var entry: Node2D = unit._nearest_friendly_mine_entry()
		if entry == null:
			unit._flee_timer = 0.0
			return
		# Flee to the shaft on the level we're currently on.
		unit._flee_target = entry.call("get_underground_position") if unit.is_underground else entry.global_position
	unit._clear_target()
	unit._target_position = unit._flee_target
	unit._set_state(Unit.State.MOVE, "flee")
	_repath(unit._flee_target)


func _continue_flee() -> void:
	if unit._flee_target == Vector2.ZERO:
		return
	unit._set_state(Unit.State.MOVE, "continue flee")
	_repath(unit._flee_target)
