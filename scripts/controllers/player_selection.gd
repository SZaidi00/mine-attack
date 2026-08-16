class_name PlayerSelection
extends RefCounted

var pc: PlayerController


func _init(p: PlayerController) -> void:
	pc = p


func _update_selection_box(current: Vector2) -> void:
	if pc.selection_box == null:
		return
	pc.selection_box.position = Vector2(min(pc._drag_start.x, current.x), min(pc._drag_start.y, current.y))
	pc.selection_box.size = (pc._drag_start - current).abs()


func _single_select(screen_pos: Vector2) -> void:
	var world_pos: Vector2 = pc._commands._screen_to_world(screen_pos)
	var shift: bool = Input.is_key_pressed(KEY_SHIFT)
	# Check units first.
	var clicked_unit: Unit = _unit_at(world_pos)
	if clicked_unit != null and clicked_unit.team == GameManager.Team.PLAYER:
		if shift:
			if not pc._selected_units.has(clicked_unit):
				pc._selected_units.append(clicked_unit)
			_select_units(pc._selected_units)
		else:
			_select_units([clicked_unit])
		return
	# Then own placeable structures (towers/walls/lanterns/traps).
	var clicked_structure: Node2D = _own_structure_at(world_pos)
	if clicked_structure != null:
		if shift:
			if not pc._selected_structures.has(clicked_structure):
				pc._selected_structures.append(clicked_structure)
			_select_structures(pc._selected_structures)
		else:
			_select_structures([clicked_structure])
		return
	# Then buildings.
	var clicked_building: Node2D = _building_at(world_pos)
	if clicked_building != null and clicked_building.get("team") == GameManager.Team.PLAYER:
		if not shift:
			_select_units([])
		# TODO: building selection UI.
		return
	if shift:
		return
	_select_units([])


func _box_select(start: Vector2, end: Vector2) -> void:
	var units: Array = []
	var min_p: Vector2 = Vector2(min(start.x, end.x), min(start.y, end.y))
	var max_p: Vector2 = Vector2(max(start.x, end.x), max(start.y, end.y))
	var canvas: Transform2D = pc.get_viewport().get_canvas_transform()
	for unit in pc.get_tree().get_nodes_in_group("player"):
		# Feet or combat body (flying dragons) — either inside the box counts.
		var feet_sp: Vector2 = canvas * unit.global_position
		var combat_sp: Vector2 = canvas * unit.get_combat_position()
		var feet_in: bool = feet_sp.x >= min_p.x and feet_sp.x <= max_p.x and feet_sp.y >= min_p.y and feet_sp.y <= max_p.y
		var combat_in: bool = combat_sp.x >= min_p.x and combat_sp.x <= max_p.x and combat_sp.y >= min_p.y and combat_sp.y <= max_p.y
		if feet_in or combat_in:
			units.append(unit)
	if Input.is_key_pressed(KEY_SHIFT):
		for u in units:
			if not pc._selected_units.has(u):
				pc._selected_units.append(u)
		_select_units(pc._selected_units)
	else:
		_select_units(units)


func _select_units(units: Array) -> void:
	for u in pc._selected_units:
		if is_instance_valid(u):
			u.selected = false
			u.queue_redraw()
	pc._selected_units = units
	for u in pc._selected_units:
		if is_instance_valid(u):
			u.selected = true
			u.queue_redraw()
	# Selecting units clears any selected structures.
	for s in pc._selected_structures:
		if is_instance_valid(s):
			s.selected = false
			s.queue_redraw()
	pc._selected_structures = []


func _select_structures(structures: Array) -> void:
	for s in pc._selected_structures:
		if is_instance_valid(s):
			s.selected = false
			s.queue_redraw()
	pc._selected_structures = structures
	for s in pc._selected_structures:
		if is_instance_valid(s):
			s.selected = true
			s.queue_redraw()
	# Selecting structures clears any selected units.
	for u in pc._selected_units:
		if is_instance_valid(u):
			u.selected = false
			u.queue_redraw()
	pc._selected_units = []


func _unit_at(world_pos: Vector2) -> Unit:
	var best: Unit = null
	var best_dist: float = 999999.0
	for unit in pc.get_tree().get_nodes_in_group("units"):
		var d: float = unit.get_combat_position().distance_to(world_pos)
		if d < GridWorld.CELL_SIZE / 1.5 and d < best_dist:
			best_dist = d
			best = unit
	return best


func _enemy_unit_at(world_pos: Vector2) -> Unit:
	var unit: Unit = _unit_at(world_pos)
	# Fog of War: hidden enemy units cannot be clicked (their ghost is a
	# memory, not a target).
	if unit != null and unit.team != GameManager.Team.PLAYER \
			and pc._grid.is_visible_to(GameManager.Team.PLAYER, unit.global_position):
		return unit
	return null


## Enemy structure near the click point (Fog of War: only while visible).
func _enemy_structure_at(world_pos: Vector2) -> Node2D:
	for group: String in ["lanterns", "towers", "walls"]:
		for structure in pc.get_tree().get_nodes_in_group(group):
			if structure.team == GameManager.Team.PLAYER:
				continue
			if not pc._grid.is_visible_to(GameManager.Team.PLAYER, structure.global_position):
				continue
			if structure.global_position.distance_to(world_pos) < GridWorld.CELL_SIZE:
				return structure
	return null


## Own placeable structure near the click point (lanterns/towers/walls/traps).
func _own_structure_at(world_pos: Vector2) -> Node2D:
	for group: String in ["lanterns", "towers", "walls", "traps"]:
		for structure in pc.get_tree().get_nodes_in_group(group):
			if structure.team != GameManager.Team.PLAYER:
				continue
			if structure.global_position.distance_to(world_pos) < GridWorld.CELL_SIZE:
				return structure
	return null


func _building_at(world_pos: Vector2) -> Node2D:
	# Pick against the building's full body rect (base plus sprite height)
	# instead of a radius around its base point, so clicks anywhere on the
	# building register as building clicks.
	var best: Node2D = null
	var best_dist: float = 999999.0
	for building in pc.get_tree().get_nodes_in_group("buildings"):
		var rect: Rect2 = building.call("get_bounds_rect")
		if not rect.has_point(world_pos):
			continue
		var d: float = building.global_position.distance_squared_to(world_pos)
		if d < best_dist:
			best_dist = d
			best = building
	return best


func _enemy_building_at(world_pos: Vector2) -> Node2D:
	var building: Node2D = _building_at(world_pos)
	if building != null and building.get("team") != GameManager.Team.PLAYER:
		return building
	return null


func _mine_entry_at(world_pos: Vector2) -> Node2D:
	var best: Node2D = null
	var best_dist: float = 999999.0
	for entry in pc.get_tree().get_nodes_in_group("mine_entries"):
		var d: float = entry.global_position.distance_to(world_pos)
		if d < GridWorld.CELL_SIZE * 2.0 and d < best_dist:
			best_dist = d
			best = entry
	return best


func _filter_miners(units: Array) -> Array:
	return units.filter(func(u): return u.data.is_miner)


func _filter_fighters(units: Array) -> Array:
	return units.filter(func(u): return u.data.is_fighter)


func _filter_dragons(units: Array) -> Array:
	return units.filter(func(u): return u.data != null and u.data.unit_name.to_lower() == "dragon")
