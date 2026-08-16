class_name UnitIdle
extends RefCounted

var unit: Unit

func _init(u: Unit) -> void:
	unit = u


func _handle_idle_fighter() -> void:
	if unit._rally_active:
		if _engage_rally_target_if_any():
			return
		_return_to_rally_point()
		return
	var target = unit._vision._find_auto_attack_target()
	if target != null:
		# Auto-engagement, not an explicit order: remember that (the defend
		# leash cuts auto-chases short) and keep the hold-post flag that
		# attack_unit/attack_building clears for explicit orders.
		var hold: bool = unit._hold_post
		if target is Unit:
			unit._commands.attack_unit(target)
		else:
			unit._commands.attack_building(target)
		if unit._state == Unit.State.ATTACK:
			unit._hold_post = hold
			unit._auto_engaged = true
		return
	if unit.is_underground:
		_patrol_underground()
		return
	_return_to_post_if_needed()


## Idle on the surface with nothing to fight: drift back to the standing point
## (spawn spot, last move destination, or hold position) so the army regroups
## instead of spreading across the map after every engagement.
func _return_to_post_if_needed() -> void:
	if unit._post_point == Vector2.ZERO:
		return
	if unit.global_position.distance_to(unit._post_point) <= GridWorld.CELL_SIZE * 1.5:
		return
	unit._navigation._repath(unit._post_point + unit._movement_offset)
	if not unit._path.is_empty():
		unit._set_state(Unit.State.MOVE, "return to post")


## Rally hunt: engage the best surface target without cancelling the rally.
## Deliberately bypasses attack_unit(), because explicit commands clear the
## rally flag via _clear_target() and this engagement must keep it — after
## the kill the unit goes idle and resumes the hunt / returns to the point.
func _engage_rally_target_if_any() -> bool:
	var target: Unit = unit._vision._find_rally_target()
	if target == null:
		return false
	DebugLog.log_command("Unit %d" % unit.get_instance_id(), "rally engage", "target=%d" % target.get_instance_id())
	unit._target_unit = target
	unit._navigation._repath(target.global_position)
	unit._set_state(Unit.State.ATTACK, "rally engage")
	return true


func _return_to_rally_point() -> void:
	if unit.global_position.distance_to(unit._rally_point) <= GridWorld.CELL_SIZE:
		return
	unit._target_position = unit._rally_point
	unit._navigation._repath(unit._rally_point)
	if not unit._path.is_empty():
		unit._set_state(Unit.State.MOVE, "return to rally point")


func _patrol_underground() -> void:
	var entry: Node2D = unit._nearest_friendly_mine_entry()
	if entry == null:
		return
	var center: Vector2 = entry.call("get_underground_position")
	var angle: float = randf() * TAU
	var radius: float = randf_range(80, 240)
	var target: Vector2 = center + Vector2(cos(angle), sin(angle)) * radius
	# Clamp within the mine bounds.
	target.x = clamp(target.x, (GridWorld.X_MIN + 1) * GridWorld.CELL_SIZE, (GridWorld.X_MAX - 1) * GridWorld.CELL_SIZE)
	target.y = clamp(target.y, GridWorld.CELL_SIZE, GridWorld.Y_MAX * GridWorld.CELL_SIZE)
	unit._commands.move_to(target)


func _nearest_friendly_fighter() -> Unit:
	var best: Unit = null
	var best_dist: float = 999999.0
	for u in unit.get_tree().get_nodes_in_group(unit.team_name()):
		if u == unit or not u.data.is_fighter:
			continue
		if u._state == Unit.State.DEAD:
			continue
		var d: float = unit.global_position.distance_squared_to(u.global_position)
		if d < best_dist:
			best_dist = d
			best = u
	return best
