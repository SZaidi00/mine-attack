class_name UnitCommands
extends RefCounted

var unit: Unit

func _init(u: Unit) -> void:
	unit = u


func move_to(world_pos: Vector2) -> void:
	if unit.data.is_fighter and unit._vision._is_enemy_underground(world_pos):
		DebugLog.log_reject("Unit %d" % unit.get_instance_id(), "move_to", "enemy underground territory")
		unit._spawn_reject_popup(world_pos)
		return
	unit._clear_target()
	unit._target_position = world_pos
	unit._navigation._repath(world_pos)
	if unit._path.is_empty():
		DebugLog.log_reject("Unit %d" % unit.get_instance_id(), "move_to", "no path to " + str(world_pos))
		unit._spawn_reject_popup(world_pos)
		unit._set_state(Unit.State.IDLE, "move target unreachable")
		return
	DebugLog.log_command("Unit %d" % unit.get_instance_id(), "move_to", str(world_pos))
	unit._post_point = world_pos
	unit._hold_post = false
	unit._set_state(Unit.State.MOVE, "move_to command")


func attack_unit(target) -> void:
	if target == null:
		DebugLog.log_reject("Unit %d" % unit.get_instance_id(), "attack_unit", "null target")
		return
	if target.team == unit.team:
		DebugLog.log_reject("Unit %d" % unit.get_instance_id(), "attack_unit", "friendly target")
		return
	if not unit._combat.can_damage_unit(target):
		DebugLog.log_reject("Unit %d" % unit.get_instance_id(), "attack_unit", "target immune")
		unit._spawn_reject_popup(target.get_combat_position() if target.has_method("get_combat_position") else target.global_position)
		return
	unit._clear_target()
	unit._navigation._repath(target.global_position)
	if unit._path.is_empty():
		DebugLog.log_reject("Unit %d" % unit.get_instance_id(), "attack_unit", "no path to target")
		unit._spawn_reject_popup(target.get_combat_position() if target.has_method("get_combat_position") else target.global_position)
		unit._set_state(Unit.State.IDLE, "attack target unreachable")
		return
	DebugLog.log_command("Unit %d" % unit.get_instance_id(), "attack_unit", "target=%d" % target.get_instance_id())
	unit._target_unit = target
	unit._hold_post = false
	unit._set_state(Unit.State.ATTACK, "attack_unit command")


func attack_building(target: Node2D) -> void:
	if target == null:
		DebugLog.log_reject("Unit %d" % unit.get_instance_id(), "attack_building", "null target")
		return
	# Path to a standing spot at the building's base; the footprint itself is
	# not a valid path target.
	var stand: Vector2 = unit._navigation._building_stand_point(target)
	unit._clear_target()
	unit._navigation._repath(stand)
	if unit._path.is_empty():
		DebugLog.log_reject("Unit %d" % unit.get_instance_id(), "attack_building", "no path to building")
		unit._spawn_reject_popup(target.global_position)
		unit._set_state(Unit.State.IDLE, "building unreachable")
		return
	DebugLog.log_command("Unit %d" % unit.get_instance_id(), "attack_building", "target=%d" % target.get_instance_id())
	unit._target_building = target
	unit._hold_post = false
	unit._set_state(Unit.State.ATTACK, "attack_building command")


func mine_cell(grid_pos: Vector2i) -> void:
	if unit.data == null or not unit.data.is_miner:
		DebugLog.log_reject("Unit %d" % unit.get_instance_id(), "mine_cell", "not a miner")
		return
	if not unit.is_underground:
		# Digging is only allowed from inside the mine. Ride the ladder down
		# first; _handle_idle_miner re-issues this cell once underground.
		# (Set after climb_down_ladder because it clears targets.)
		climb_down_ladder()
		unit._pending_mine_cell = grid_pos
		DebugLog.log_command("Unit %d" % unit.get_instance_id(), "mine_cell", str(grid_pos) + " (deferred until underground)")
		return
	unit._pending_mine_cell = Vector2i(-9999, -9999)
	DebugLog.log_command("Unit %d" % unit.get_instance_id(), "mine_cell", str(grid_pos))
	unit._clear_target()
	unit._target_cell = grid_pos
	# Reserve the tile so other auto-seeking miners pick a different one.
	unit._grid.claim_cell(grid_pos, unit.get_instance_id())
	unit._set_state(Unit.State.MINE, "mine_cell command")
	# Move adjacent. Underground an empty A* result means we can't reach this
	# tile yet — blacklist it and re-seek instead of walking through solid dirt.
	var adj: Vector2 = unit._navigation._nearest_adjacent_world(grid_pos)
	unit._navigation._repath(adj)
	if unit._path.is_empty() or not unit._navigation._path_reaches(adj):
		unit._mining._mark_cell_unreachable(grid_pos)
		unit._set_state(Unit.State.IDLE, "mine target unreachable")


func deposit_coin() -> void:
	if unit.data == null or not unit.data.is_miner:
		DebugLog.log_reject("Unit %d" % unit.get_instance_id(), "deposit_coin", "not a miner")
		return
	if unit.carried_coin <= 0:
		DebugLog.log_reject("Unit %d" % unit.get_instance_id(), "deposit_coin", "cargo empty")
		return
	unit._clear_target()
	if unit.is_underground:
		# Deposits happen at the building on the surface; climb the ladder out,
		# then _handle_idle_miner sends us to the deposit point.
		DebugLog.log_command("Unit %d" % unit.get_instance_id(), "deposit_coin", "cargo=%d" % unit.carried_coin)
		climb_up_ladder()
		unit._deposit_requested = true
		return
	var building: Node2D = unit._friendly_building()
	if building == null:
		# Base destroyed (game over); stay idle without log-spamming every tick.
		unit._set_state(Unit.State.IDLE, "no building for deposit")
		return
	DebugLog.log_command("Unit %d" % unit.get_instance_id(), "deposit_coin", "cargo=%d" % unit.carried_coin)
	unit._set_state(Unit.State.DEPOSIT, "deposit command")
	unit._target_position = building.call("get_deposit_point") + unit._movement_offset
	unit._navigation._repath(unit._target_position)


func enter_mine() -> void:
	DebugLog.log_command("Unit %d" % unit.get_instance_id(), "enter_mine")
	unit._clear_target()
	unit._set_state(Unit.State.ENTER_MINE, "enter_mine command")
	var entry: Node2D = unit._nearest_friendly_mine_entry()
	if entry:
		var entry_target: Vector2 = entry.call("get_ladder_top") + unit._movement_offset * 0.5
		unit._navigation._repath(entry_target)
		# If A* can't find a route, walk straight to the shaft instead of freezing.
		if unit._path.is_empty():
			unit._path.append(entry_target)
	else:
		unit._set_state(Unit.State.IDLE, "no mine entry")


func exit_mine() -> void:
	DebugLog.log_command("Unit %d" % unit.get_instance_id(), "exit_mine")
	unit._clear_target()
	unit._set_state(Unit.State.EXIT_MINE, "exit_mine command")
	var entry: Node2D = unit._nearest_friendly_mine_entry()
	if entry:
		var underground_target: Vector2 = entry.call("get_underground_position") + unit._movement_offset
		unit._navigation._repath(underground_target)
		if unit._path.is_empty():
			unit._path.append(underground_target)
	else:
		unit._set_state(Unit.State.IDLE, "no mine entry")


func climb_up_ladder() -> void:
	DebugLog.log_command("Unit %d" % unit.get_instance_id(), "climb_up_ladder")
	unit._clear_target()
	unit._set_state(Unit.State.CLIMB_UP, "climb_up_ladder command")
	var entry: Node2D = unit._nearest_friendly_mine_entry()
	if entry == null:
		unit._set_state(Unit.State.IDLE, "no mine entry")


func climb_down_ladder() -> void:
	DebugLog.log_command("Unit %d" % unit.get_instance_id(), "climb_down_ladder")
	unit._clear_target()
	unit._set_state(Unit.State.CLIMB_DOWN, "climb_down_ladder command")
	var entry: Node2D = unit._nearest_friendly_mine_entry()
	if entry == null:
		unit._set_state(Unit.State.IDLE, "no mine entry")


func stop() -> void:
	DebugLog.log_command("Unit %d" % unit.get_instance_id(), "stop")
	unit._clear_target()
	unit._post_point = unit.global_position  # Defend/hold means: stay right here.
	unit._hold_post = true
	unit._set_state(Unit.State.IDLE, "stop command")
	unit._path.clear()


## Disband: instant self-destruct on the owner's order. No coin refund — the
## point is freeing the population slot. Goes through _die() like any death:
## the corpse fades and a miner's cargo still drops as a pickup.
func kill() -> void:
	if unit._state == Unit.State.DEAD:
		return
	DebugLog.log_command("Unit %d" % unit.get_instance_id(), "kill", "disbanded by owner")
	unit._die()


## Garrison order (fighters): fall back and defend the home base. Underground
## fighters come out of the mine first (the idle handler walks them to the
## post once they surface); surface fighters move straight to the building's
## deposit point and hold there (it becomes their new standing point).
func garrison_home() -> void:
	if unit.data == null or not unit.data.is_fighter:
		DebugLog.log_reject("Unit %d" % unit.get_instance_id(), "garrison_home", "not a fighter")
		return
	unit._clear_target()
	var building: Node2D = unit._friendly_building()
	if building == null:
		unit._set_state(Unit.State.IDLE, "no building to garrison")
		return
	unit._post_point = building.call("get_deposit_point") + unit._movement_offset
	DebugLog.log_command("Unit %d" % unit.get_instance_id(), "garrison_home", str(unit._post_point))
	if unit.is_underground:
		exit_mine()
	else:
		move_to(unit._post_point)
	# Set after move_to (which clears it): garrisoned fighters hold the base.
	unit._hold_post = true


## Rally stance order (fighters only): move to the point while hunting every
## enemy on the surface — miners included. The rally stays active until any
## explicit command cancels it (_clear_target resets the flag). Underground
## points are rejected (the sweep is a surface hunt); underground fighters
## ride the ladder up first and resume the rally on the surface.
func rally_to(world_pos: Vector2) -> void:
	if unit.data == null or not unit.data.is_fighter:
		DebugLog.log_reject("Unit %d" % unit.get_instance_id(), "rally_to", "not a fighter")
		return
	if world_pos.y > GridWorld.CELL_SIZE:
		DebugLog.log_reject("Unit %d" % unit.get_instance_id(), "rally_to", "underground rally point")
		unit._spawn_reject_popup(world_pos)
		return
	unit._clear_target()
	unit._hold_post = false  # rally hunts the whole surface — no leash
	if unit.is_underground:
		# Climb out first; _clear_target inside climb_up_ladder would wipe the
		# rally state, so it is set below, after the climb is under way.
		climb_up_ladder()
	unit._rally_active = true
	unit._rally_point = world_pos
	if unit._state == Unit.State.CLIMB_UP:
		DebugLog.log_command("Unit %d" % unit.get_instance_id(), "rally_to", str(world_pos) + " (after climbing out)")
		return
	unit._target_position = world_pos
	unit._navigation._repath(world_pos)
	if unit._path.is_empty():
		# No route (e.g. clicked solid dirt): hold position and hunt from here.
		DebugLog.log_reject("Unit %d" % unit.get_instance_id(), "rally_to", "no path to " + str(world_pos))
		unit._rally_point = unit.global_position
		unit._set_state(Unit.State.IDLE, "rally point unreachable")
		return
	DebugLog.log_command("Unit %d" % unit.get_instance_id(), "rally_to", str(world_pos))
	unit._set_state(Unit.State.MOVE, "rally_to command")


func _process_enter_mine(delta: float) -> void:
	var entry: Node2D = unit._nearest_friendly_mine_entry()
	if entry == null:
		unit._set_state(Unit.State.IDLE, "no mine entry")
		return
	# Path to the ladder top (centered on the shaft column). A* ends on the
	# cell center below the ladder top, so accept a completed path as arrival.
	var top: Vector2 = entry.call("get_ladder_top")
	var path_completed: bool = not unit._path.is_empty() and unit._path_index >= unit._path.size()
	if unit.global_position.distance_to(top) > GridWorld.CELL_SIZE and not path_completed:
		# Repath only when there is no path in flight (see _process_climb_up).
		if unit._path.is_empty():
			unit._navigation._repath(top)
			# Fallback: walk straight to the mine entry if pathfinding fails.
			if unit._path.is_empty():
				unit._path.append(top)
		unit._navigation._follow_path(delta)
		return
	entry.call("enter_mine", unit)
	unit._refresh_visibility()
	unit._set_state(Unit.State.IDLE, "entered mine")


func _process_exit_mine(delta: float) -> void:
	var entry: Node2D = unit._nearest_friendly_mine_entry()
	if entry == null:
		unit._set_state(Unit.State.IDLE, "no mine entry")
		return
	var target: Vector2 = entry.call("get_underground_position")
	if unit.global_position.distance_to(target) > GridWorld.CELL_SIZE * 0.5:
		# Repath only when there is no path in flight (see _process_climb_up).
		if unit._path.is_empty():
			unit._navigation._repath(target)
			if unit._path.is_empty():
				unit._path.append(target)
		unit._navigation._follow_path(delta)
		return
	entry.call("exit_mine", unit)
	unit._refresh_visibility()
	unit._set_state(Unit.State.IDLE, "exited mine")


func _process_climb_up(delta: float) -> void:
	var entry: Node2D = unit._nearest_friendly_mine_entry()
	if entry == null:
		unit._set_state(Unit.State.IDLE, "no mine entry")
		return

	var ladder_bottom: Vector2 = entry.call("get_ladder_bottom") + unit._movement_offset * 0.5
	var ladder_top: Vector2 = entry.call("get_ladder_top")

	# Phase 1: path to the bottom of the ladder. Once the path completes,
	# transition to the climb even if separation nudged us slightly past the
	# arrival threshold. A unit already on the ladder column at or above the
	# bottom skips phase 1 entirely — otherwise ascending in phase 2 would
	# grow the distance to the ladder bottom and re-trigger phase 1 (ping-pong).
	var on_column: bool = absf(unit.global_position.x - ladder_bottom.x) <= 8.0 and unit.global_position.y <= ladder_bottom.y + 4.0
	var arrival_threshold: float = GridWorld.CELL_SIZE * 0.35
	var path_completed: bool = not unit._path.is_empty() and unit._path_index >= unit._path.size()
	if not on_column and not path_completed and unit.global_position.distance_to(ladder_bottom) > arrival_threshold:
		# Repath only when there is no path in flight. Repathing every frame
		# resets _path_index to the unit's own cell center, which can pull the
		# unit back and forth across a cell boundary and freeze it in place.
		if unit._path.is_empty():
			unit._navigation._repath(ladder_bottom)
			if unit._path.is_empty():
				unit._path.append(ladder_bottom)
		unit._navigation._follow_path(delta)
		return

	# Phase 2: climb straight up, sliding horizontally onto the ladder column
	# first instead of snapping.
	unit._path.clear()
	var dest: Vector2 = ladder_top
	var to_dest: Vector2 = dest - unit.global_position
	if to_dest.length() <= 8.0:
		entry.call("exit_mine_climb", unit)
		unit._refresh_visibility()
		unit._set_state(Unit.State.IDLE, "climbed out")
		return

	var climb_speed: float = unit.data.speed * 0.9
	var step: float = climb_speed * delta
	var dx: float = dest.x - unit.global_position.x
	if absf(dx) > 1.0:
		unit.global_position.x += clampf(dx, -step, step)
	else:
		unit.global_position.x = dest.x
		unit.global_position.y += clampf(dest.y - unit.global_position.y, -step, step)


func _process_climb_down(delta: float) -> void:
	var entry: Node2D = unit._nearest_friendly_mine_entry()
	if entry == null:
		unit._set_state(Unit.State.IDLE, "no mine entry")
		return
	var ladder_top: Vector2 = entry.call("get_ladder_top")
	var ladder_bottom: Vector2 = entry.call("get_ladder_bottom")

	# Phase 1: path to the top of the ladder. Once the path completes,
	# transition to the climb even if separation nudged us slightly past the
	# arrival threshold. A unit already on the ladder column at or below the
	# top skips phase 1 entirely — otherwise descending in phase 2 would grow
	# the distance to the ladder top and re-trigger phase 1 (ping-pong).
	var on_column: bool = absf(unit.global_position.x - ladder_top.x) <= 8.0 and unit.global_position.y >= ladder_top.y - 4.0
	var arrival_threshold: float = GridWorld.CELL_SIZE * 0.35
	var path_completed: bool = not unit._path.is_empty() and unit._path_index >= unit._path.size()
	if not on_column and not path_completed and unit.global_position.distance_to(ladder_top) > arrival_threshold:
		# Repath only when there is no path in flight (see _process_climb_up).
		if unit._path.is_empty():
			unit._navigation._repath(ladder_top)
			if unit._path.is_empty():
				unit._path.append(ladder_top)
		unit._navigation._follow_path(delta)
		return

	# Phase 2: climb straight down, sliding horizontally onto the ladder column
	# first instead of snapping.
	unit._path.clear()
	var dest: Vector2 = ladder_bottom
	var to_dest: Vector2 = dest - unit.global_position
	if to_dest.length() <= 8.0:
		entry.call("enter_mine_climb", unit)
		unit._refresh_visibility()
		unit._set_state(Unit.State.IDLE, "climbed in")
		return

	var climb_speed: float = unit.data.speed * 0.9
	var step: float = climb_speed * delta
	var dx: float = dest.x - unit.global_position.x
	if absf(dx) > 1.0:
		unit.global_position.x += clampf(dx, -step, step)
	else:
		unit.global_position.x = dest.x
		unit.global_position.y += clampf(dest.y - unit.global_position.y, -step, step)


func _process_deposit(delta: float) -> void:
	var building: Node2D = unit._friendly_building()
	if building == null:
		unit._set_state(Unit.State.IDLE, "no building for deposit")
		return
	var target_pos: Vector2 = building.call("get_deposit_point")
	var path_done: bool = not unit._path.is_empty() and unit._path_index >= unit._path.size()
	if unit.global_position.distance_to(target_pos) > GridWorld.CELL_SIZE and not path_done:
		# Repath only when there is no path in flight (see _process_climb_up).
		if unit._path.is_empty():
			unit._navigation._repath(target_pos)
			# Surface-only fallback: the surface row is fully walkable, so walking
			# straight to the deposit point is harmless if A* hiccups.
			if unit._path.is_empty():
				unit._path.append(target_pos)
		unit._navigation._follow_path(delta)
		return
	building.call("deposit", unit)
	unit._deposit_requested = false
	unit._set_state(Unit.State.IDLE, "deposit complete")
