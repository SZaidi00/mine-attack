class_name PlayerCommands
extends RefCounted

var pc: PlayerController


func _init(p: PlayerController) -> void:
	pc = p


func _issue_command(screen_pos: Vector2) -> void:
	# Belt and braces: a right-click while rally placement is armed cancels it
	# (normally swallowed earlier in _unhandled_input).
	if pc._rally_armed:
		pc._rally_armed = false
		return

	# Drop dead units from the selection before issuing anything.
	pc._selected_units = pc._selected_units.filter(func(u): return is_instance_valid(u))
	if pc._selected_units.is_empty():
		DebugLog.log_reject("PlayerController", "RMB command", "no selected units")
		return
	var world_pos: Vector2 = _screen_to_world(screen_pos)
	var grid_pos: Vector2i = pc._grid.world_to_grid(world_pos)

	# Resolution order is deterministic and exclusive: exactly one command (or
	# one rejection) is produced per right-click.
	# 1. Enemy unit clicked -> attack with fighters.
	var enemy_unit: Unit = pc._selection._enemy_unit_at(world_pos)
	if enemy_unit != null:
		var fighters: Array = pc._selection._filter_fighters(pc._selected_units)
		if fighters.is_empty():
			_reject_command("attack_unit", "no fighters selected", world_pos)
			return
		# Only order units that can actually hurt the target (e.g. dragons are
		# immune to swordsmen — mixed selections should still send archers).
		var capable: Array = []
		for u in fighters:
			if u.can_damage_unit(enemy_unit):
				capable.append(u)
		if capable.is_empty():
			_reject_command("attack_unit", "target immune to selected units", world_pos)
			return
		DebugLog.log_command("PlayerController", "attack_unit", "target=%d fighters=%d" % [enemy_unit.get_instance_id(), capable.size()])
		for u in capable:
			u.attack_unit(enemy_unit)
		return

	# 2. Enemy building clicked -> attack with fighters.
	var enemy_building: Node2D = pc._selection._enemy_building_at(world_pos)
	if enemy_building != null:
		var fighters: Array = pc._selection._filter_fighters(pc._selected_units)
		if fighters.is_empty():
			_reject_command("attack_building", "no fighters selected", world_pos)
			return
		DebugLog.log_command("PlayerController", "attack_building", "target=%d fighters=%d" % [enemy_building.get_instance_id(), fighters.size()])
		for u in fighters:
			u.attack_building(enemy_building)
		return

	# 2b. Enemy structure clicked (lantern/tower/wall) -> attack with fighters.
	var enemy_structure: Node2D = pc._selection._enemy_structure_at(world_pos)
	if enemy_structure != null:
		var fighters: Array = pc._selection._filter_fighters(pc._selected_units)
		if fighters.is_empty():
			_reject_command("attack_structure", "no fighters selected", world_pos)
			return
		DebugLog.log_command("PlayerController", "attack_structure", "target=%d fighters=%d" % [enemy_structure.get_instance_id(), fighters.size()])
		for u in fighters:
			u.attack_building(enemy_structure)
		return

	# 3. Central wall clicked with miners selected -> breach.
	var miners: Array = pc._selection._filter_miners(pc._selected_units)
	if pc._grid.is_central_wall(grid_pos) and not miners.is_empty():
		DebugLog.log_command("PlayerController", "breach_wall", "cell=%s miners=%d" % [str(grid_pos), miners.size()])
		for u in miners:
			u.mine_cell(grid_pos)
		return

	# 4. Diggable cell clicked with miners selected -> mine it.
	var cell: GridWorld.Cell = pc._grid.get_cell(grid_pos)
	var diggable: bool = cell != null and GridMining._is_diggable_type(cell.type)
	if diggable and not miners.is_empty():
		DebugLog.log_command("PlayerController", "mine_cell", "cell=%s miners=%d" % [str(grid_pos), miners.size()])
		for u in miners:
			u.mine_cell(grid_pos)
		return

	# 5. Own mine entry clicked -> deposit (miners with coin), enter, or exit.
	var entry: Node2D = pc._selection._mine_entry_at(world_pos)
	if entry != null and entry.get("team") == GameManager.Team.PLAYER:
		DebugLog.log_command("PlayerController", "mine_entry", "entry=%d units=%d" % [entry.get_instance_id(), pc._selected_units.size()])
		for u in pc._selected_units:
			if u.data.is_miner and u.carried_coin > 0:
				u.deposit_coin()
			elif u.is_underground:
				u.exit_mine()
			else:
				u.enter_mine()
		return

	# 6. Enemy mine entry clicked -> reject: units can never enter the enemy mine.
	if entry != null and entry.get("team") != GameManager.Team.PLAYER:
		_reject_command("mine_entry", "cannot enter the enemy mine", world_pos)
		return

	# 7. Default: move.
	DebugLog.log_command("PlayerController", "move_to", "pos=%s units=%d" % [str(world_pos), pc._selected_units.size()])
	for u in pc._selected_units:
		u.move_to(world_pos)


func _reject_command(action: String, reason: String, at: Vector2) -> void:
	DebugLog.log_reject("PlayerController", action, reason)
	var popup: Node2D = pc._REJECT_POPUP.instantiate()
	popup.global_position = at
	pc.get_tree().current_scene.add_child(popup)


func _screen_to_world(screen_pos: Vector2) -> Vector2:
	# Camera2D has no project_position() (that is a Camera3D API); convert via
	# the viewport's canvas transform, which also handles zoom and stretch.
	return pc.get_viewport().get_canvas_transform().affine_inverse() * screen_pos


func train_unit(unit_id: String) -> bool:
	if unit_id == "pigeon":
		return train_pigeon()
	for building in pc.get_tree().get_nodes_in_group("buildings"):
		if building.get("team") == GameManager.Team.PLAYER:
			return building.call("queue_unit", unit_id)
	return false


func train_pigeon() -> bool:
	# Pigeons train from the first available built player tower.
	for tower in pc.get_tree().get_nodes_in_group("towers"):
		if tower.get("team") == GameManager.Team.PLAYER and tower.is_built():
			if tower.call("queue_pigeon"):
				return true
	DebugLog.log_reject("PlayerController", "train_pigeon", "no available tower")
	return false


func upgrade_miner() -> void:
	EconomyManager.upgrade_miner(GameManager.Team.PLAYER)


func upgrade_fighter(unit_id: String) -> void:
	EconomyManager.upgrade_fighter(GameManager.Team.PLAYER, unit_id)


## Rally placement: army-wide order, so it does not need a selection. Called
## with the screen position of the confirming left-click.
func _set_rally_point(screen_pos: Vector2) -> void:
	pc._rally_armed = false
	var world_pos: Vector2 = _screen_to_world(screen_pos)
	var fighters: Array = pc._selection._filter_fighters(pc.get_tree().get_nodes_in_group("player"))
	if fighters.is_empty():
		_reject_command("rally", "no fighters", world_pos)
		return
	DebugLog.log_command("PlayerController", "rally", "point=%s fighters=%d" % [str(world_pos), fighters.size()])
	for u in fighters:
		u.rally_to(world_pos)


func _handle_rally_input(event: InputEvent) -> void:
	if event.is_action_pressed(pc._Constants.INPUT_SELECT):
		_set_rally_point(pc.get_viewport().get_mouse_position())
	elif event.is_action_pressed(pc._Constants.INPUT_COMMAND):
		pc._rally_armed = false
		DebugLog.log_command("PlayerController", "rally", "placement cancelled")


func set_stance(stance: String) -> void:
	# [DECISION] Stances are army-wide orders to every living player fighter;
	# right-click issues orders to the current selection only. Attack/Defend/
	# Garrison are also persistent modes: the choice is remembered and applied
	# to every fighter trained afterwards (see _on_fighter_spawned), so setting
	# a mode with zero fighters is valid.
	if stance in ["attack", "defend", "garrison"]:
		# Choosing any stance cancels a pending rally-point placement.
		pc._rally_armed = false
		pc._build_placement._cancel_build_mode()
		pc._current_stance = stance
	var fighters: Array = pc._selection._filter_fighters(pc.get_tree().get_nodes_in_group("player"))
	match stance:
		"rally":
			if fighters.is_empty():
				DebugLog.log_reject("PlayerController", "set_stance rally", "no fighters")
				return
			# No immediate order: the next left-click places the rally point
			# (see _set_rally_point; right-click cancels). Fighters then hunt
			# everything on the surface — enemy miners included.
			pc._rally_armed = true
			DebugLog.log_command("PlayerController", "stance rally", "armed; awaiting rally point left-click")
		"attack":
			var enemy_building: Node2D = pc._enemy_building()
			if enemy_building == null:
				DebugLog.log_reject("PlayerController", "set_stance attack", "no enemy building")
				return
			DebugLog.log_command("PlayerController", "stance attack", "fighters=%d" % fighters.size())
			for u in fighters:
				u.attack_building(enemy_building)
		"defend":
			DebugLog.log_command("PlayerController", "stance defend", "fighters=%d" % fighters.size())
			for u in fighters:
				u.stop()
		"garrison":
			# Fall back and defend the base: underground fighters climb out,
			# everyone gathers at the home building and holds there.
			DebugLog.log_command("PlayerController", "stance garrison", "fighters=%d" % fighters.size())
			for u in fighters:
				u.garrison_home()
		_:
			DebugLog.log_reject("PlayerController", "set_stance", "unknown stance " + stance)


func kill_selected() -> void:
	pc._selected_units = pc._selected_units.filter(func(u): return is_instance_valid(u))
	pc._selected_structures = pc._selected_structures.filter(func(s): return is_instance_valid(s))
	if pc._selected_units.is_empty() and pc._selected_structures.is_empty():
		DebugLog.log_reject("PlayerController", "kill_selected", "no selection")
		return
	DebugLog.log_command("PlayerController", "kill_selected", "units=%d structures=%d" % [pc._selected_units.size(), pc._selected_structures.size()])
	var victims: Array = pc._selected_units.duplicate()
	var structures: Array = pc._selected_structures.duplicate()
	pc._selection._select_units([])  # dying units must not linger in the selection
	pc._selection._select_structures([])
	for u in victims:
		u.kill()
	for s in structures:
		if s.has_method("demolish"):
			s.demolish()
