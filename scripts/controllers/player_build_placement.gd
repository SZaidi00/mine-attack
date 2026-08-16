class_name PlayerBuildPlacement
extends RefCounted

const _TOWER_SCENE: PackedScene = preload("res://scenes/tower.tscn")
const _WALL_SCENE: PackedScene = preload("res://scenes/wall_segment.tscn")
const _TRAP_SCENE: PackedScene = preload("res://scenes/trap.tscn")


## Code-drawn placement marker for traps (no texture asset exists); drawn in
## white so the ghost's green/red validity modulate tints it like the sprites.
class _TrapGhostMarker:
	extends Node2D

	func _draw() -> void:
		draw_arc(Vector2.ZERO, 10.0, 0, TAU, 12, Color(1, 1, 1, 0.9), 2.0)
		for i in 5:
			var dir: Vector2 = Vector2.RIGHT.rotated(i * TAU / 5.0)
			draw_line(dir * 4.0, dir * 9.0, Color(1, 1, 1, 0.9), 2.0)

var pc: PlayerController


func _init(p: PlayerController) -> void:
	pc = p


func _update_ghost() -> void:
	# Lantern placement ghost: snap to the cell under the cursor and tint it
	# by placement validity (green = valid, red = invalid).
	if pc._build_mode != "" and pc._build_ghost != null:
		var world: Vector2 = pc._commands._screen_to_world(pc.get_viewport().get_mouse_position())
		var cell: Vector2i = pc._grid.world_to_grid(world)
		pc._build_ghost.global_position = pc._grid.grid_to_world(cell)
		var err: String = _placement_error(pc._build_mode, cell)
		pc._build_ghost.modulate = Color(0.4, 1.0, 0.4, 0.55) if err == "" else Color(1.0, 0.35, 0.35, 0.55)


func _handle_input(event: InputEvent) -> void:
	# Lantern placement mode: left-click confirms (stays active on an invalid
	# spot so the player can adjust), right-click or Esc cancels. Swallowed
	# either way so no selection/command leaks through.
	if event.is_action_pressed(pc._Constants.INPUT_SELECT):
		var world: Vector2 = pc._commands._screen_to_world(pc.get_viewport().get_mouse_position())
		if try_place_structure(pc._build_mode, world):
			_cancel_build_mode()
	elif event.is_action_pressed(pc._Constants.INPUT_COMMAND) or event.is_action_pressed(pc._Constants.INPUT_PAUSE):
		_cancel_build_mode()
		DebugLog.log_command("PlayerController", "build", "placement cancelled")


## Enters placement mode: a ghost follows the cursor until left-click
## confirms or right-click/Esc cancels. kind is "lantern" (surface),
## "underground_lantern", "tower", "wall", or "trap".
func start_build_placement(kind: String) -> void:
	_cancel_build_mode()
	pc._rally_armed = false
	pc._build_mode = kind
	pc._build_ghost = Node2D.new()
	pc._build_ghost.name = "BuildGhost"
	var texture: Texture2D
	var ring_radius_cells: int = 0
	match kind:
		"underground_lantern":
			texture = preload("res://frost_mines_assets/props/lantern_underground.png")
		"tower":
			texture = preload("res://frost_mines_assets/props/tower_player.png")
			ring_radius_cells = pc._Constants.TOWER_RANGE_CELLS
		"wall":
			texture = preload("res://frost_mines_assets/props/wall_player.png")
		"trap":
			pass  # no texture asset — code-drawn marker added below
		_:
			texture = preload("res://frost_mines_assets/props/lantern_t1.png")
			ring_radius_cells = pc._Constants.LANTERN_T1_VISION
	var sprite: Sprite2D = Sprite2D.new()
	sprite.texture = texture
	if kind == "lantern" or kind == "tower":
		# Surface structures stand on the ground line at the bottom of the row.
		sprite.position = Vector2(0, 16.0 - texture.get_height() / 2.0)
	pc._build_ghost.add_child(sprite)
	if kind == "trap":
		pc._build_ghost.add_child(_TrapGhostMarker.new())
	if ring_radius_cells > 0:
		# Faint ring showing the vision/attack radius the structure provides.
		var ring: Sprite2D = Sprite2D.new()
		ring.texture = pc._GHOST_RING
		var diameter: float = ring_radius_cells * GridWorld.CELL_SIZE * 2.0
		ring.scale = Vector2.ONE * (diameter / pc._GHOST_RING.get_width())
		ring.modulate = Color(1.0, 0.85, 0.4, 0.3)
		pc._build_ghost.add_child(ring)
	pc.add_child(pc._build_ghost)
	DebugLog.log_command("PlayerController", "build", "placement mode: " + kind)


func _cancel_build_mode() -> void:
	if pc._build_mode == "":
		return
	pc._build_mode = ""
	if pc._build_ghost != null:
		pc._build_ghost.queue_free()
		pc._build_ghost = null


func is_build_mode_active() -> bool:
	return pc._build_mode != ""


## Validates a placement cell for any build kind. Returns "" when valid,
## otherwise a human-readable reason (also used to tint the placement ghost).
func _placement_error(kind: String, cell: Vector2i) -> String:
	match kind:
		"tower":
			return _tower_placement_error(cell)
		"wall":
			return _wall_placement_error(cell)
		"trap":
			return _trap_placement_error(cell)
		_:
			return _lantern_placement_error(kind, cell)


## Any placed structure standing on the given cell (any team — occupancy is
## physical).
func _structure_at_cell(cell: Vector2i) -> Node2D:
	for group: String in ["lanterns", "towers", "walls", "traps"]:
		for structure in pc.get_tree().get_nodes_in_group(group):
			if pc._grid.world_to_grid(structure.global_position) == cell:
				return structure
	return null


## Tower rules (Revamp Phase 3): own half's surface row, not within 2 cells of
## a building or mine entry, max TOWER_MAX_COUNT per team plus research bonuses.
func _tower_placement_error(cell: Vector2i) -> String:
	if cell.y != 0:
		return "must be placed on the surface"
	if cell.x > -2:
		return "own half of the map only"
	if _structure_at_cell(cell) != null:
		return "cell is occupied"
	for b in pc.get_tree().get_nodes_in_group("buildings"):
		if b.get_footprint_cell_rect().grow(pc._Constants.TOWER_MIN_BUILDING_DISTANCE).has_point(cell):
			return "too close to a building"
	for entry in pc.get_tree().get_nodes_in_group("mine_entries"):
		var entry_cell: Vector2i = pc._grid.world_to_grid(entry.global_position)
		if Vector2(entry_cell - cell).length() < pc._Constants.TOWER_MIN_BUILDING_DISTANCE:
			return "too close to the mine entry"
	var team: GameManager.Team = GameManager.Team.PLAYER
	var count: int = 0
	for tower in pc.get_tree().get_nodes_in_group("towers"):
		if tower.team == team:
			count += 1
	var max_count: int = pc._Constants.TOWER_MAX_COUNT + int(ResearchManager.get_stat_bonus(team, "tower_max_count_bonus"))
	if count >= max_count:
		return "max towers reached"
	return ""


## Wall rules (Revamp Phase 3): own half's surface row, unoccupied cell, at
## most a couple of segments per team (faction-modified) plus research bonuses.
func _wall_placement_error(cell: Vector2i) -> String:
	if cell.y != 0:
		return "must be placed on the surface"
	if cell.x > -2:
		return "own half of the map only"
	if _structure_at_cell(cell) != null:
		return "cell is occupied"
	var team: GameManager.Team = GameManager.Team.PLAYER
	var count: int = 0
	for wall in pc.get_tree().get_nodes_in_group("walls"):
		if wall.team == team:
			count += 1
	var max_count: int = FactionManager.get_wall_max_count(team) + int(ResearchManager.get_stat_bonus(team, "wall_max_count_bonus"))
	if count >= max_count:
		return "max walls reached"
	return ""


## Trap rules (Revamp Phase 6, Guerrilla Tactics branch): any walkable cell,
## unoccupied, at most TRAP_MAX_COUNT per team. Requires the branch research.
func _trap_placement_error(cell: Vector2i) -> String:
	var team: GameManager.Team = GameManager.Team.PLAYER
	if not ResearchManager.has_branch(team, "guerrilla"):
		return "requires Guerrilla Tactics research"
	if not pc._grid.is_walkable(cell):
		return "must be placed on a walkable cell"
	if _structure_at_cell(cell) != null:
		return "cell is occupied"
	var count: int = 0
	for trap in pc.get_tree().get_nodes_in_group("traps"):
		if trap.team == team:
			count += 1
	if count >= pc._Constants.TRAP_MAX_COUNT:
		return "max traps reached"
	return ""


## Validates and executes a tower/wall/trap placement (lanterns route to
## try_place_lantern). Spends the coin and spawns the structure on success.
## Public so the HUD, tests, and (later) the AI can share one code path.
func try_place_structure(kind: String, world_pos: Vector2) -> bool:
	if kind == "lantern" or kind == "underground_lantern":
		return try_place_lantern(kind, world_pos)
	var cell: Vector2i = pc._grid.world_to_grid(world_pos)
	var err: String = _placement_error(kind, cell)
	if err != "":
		pc._commands._reject_command("build", err, world_pos)
		return false
	var team: GameManager.Team = GameManager.Team.PLAYER
	var cost: int
	var scene: PackedScene
	match kind:
		"tower":
			cost = FactionManager.get_tower_cost(team)
			# Siege Master (Revamp Phase 6): towers cost half.
			if ResearchManager.has_branch(team, "siege_master"):
				cost = roundi(cost * pc._Constants.SIEGE_MASTER_TOWER_COST_MULT)
			scene = _TOWER_SCENE
		"wall":
			cost = FactionManager.get_wall_cost(team)
			# Stone Masonry (Fortification branch): walls cost less.
			var wall_cost_mult: float = maxf(0.1, 1.0 - ResearchManager.get_stat_bonus(team, "wall_cost_mult"))
			cost = maxi(1, roundi(cost * wall_cost_mult))
			scene = _WALL_SCENE
		_:
			cost = pc._Constants.TRAP_COST
			scene = _TRAP_SCENE
	if not EconomyManager.spend_coin(team, cost):
		pc._commands._reject_command("build", "not enough coin (%d needed)" % cost, world_pos)
		return false
	var structure: Node2D = scene.instantiate()
	structure.team = team
	structure.total_cost = cost
	structure.global_position = pc._grid.grid_to_world(cell)
	pc.get_node("/root/Main/Structures").add_child(structure)
	DebugLog.log_command("PlayerController", "build", "%s at %s" % [kind, str(cell)])
	return true


## Validates a lantern placement cell. Returns "" when valid, otherwise a
## human-readable reason (also used to tint the placement ghost).
func _lantern_placement_error(kind: String, cell: Vector2i) -> String:
	var underground: bool = kind == "underground_lantern"
	var team: GameManager.Team = GameManager.Team.PLAYER
	var same_kind: Array = []
	for lantern in pc.get_tree().get_nodes_in_group("lanterns"):
		if lantern.team == team and lantern.is_underground_lantern == underground:
			same_kind.append(lantern)
	if underground:
		if cell.y < 1:
			return "must be placed underground"
		if cell.x > -2:
			return "own half of the mine only"
		# Carved tunnel cells are erased from the grid; anything still present
		# (dirt/ore/wall) is solid and cannot hold a lantern.
		if pc._grid.get_cell(cell) != null:
			return "needs a dug-out tunnel cell"
		if same_kind.size() >= pc._Constants.UNDERGROUND_LANTERN_MAX_COUNT:
			return "max underground lanterns reached"
		for lantern in same_kind:
			if Vector2(pc._grid.world_to_grid(lantern.global_position) - cell).length() < pc._Constants.UNDERGROUND_LANTERN_MIN_DISTANCE:
				return "too close to another lantern"
	else:
		if cell.y != 0:
			return "must be placed on the surface"
		if cell.x > -2:
			return "own half of the map only"
		for lantern in same_kind:
			if pc._grid.world_to_grid(lantern.global_position) == cell:
				return "" if lantern.can_upgrade() else "lantern fully upgraded"
		if same_kind.size() >= pc._Constants.LANTERN_MAX_COUNT:
			return "max lanterns reached"
		for lantern in same_kind:
			if Vector2(pc._grid.world_to_grid(lantern.global_position) - cell).length() < pc._Constants.LANTERN_MIN_DISTANCE:
				return "too close to another lantern"
	return ""


## Own surface lantern standing on the given cell (upgrade target), if any.
func _surface_lantern_at_cell(cell: Vector2i) -> Node2D:
	for lantern in pc.get_tree().get_nodes_in_group("lanterns"):
		if lantern.team == GameManager.Team.PLAYER and not lantern.is_underground_lantern \
				and pc._grid.world_to_grid(lantern.global_position) == cell:
			return lantern
	return null


## Validates and executes a lantern placement (or in-place tier upgrade when
## the cell already holds an own surface lantern). Spends the coin and spawns
## the structure on success. Public so the HUD, tests, and (later) the AI can
## share one code path.
func try_place_lantern(kind: String, world_pos: Vector2) -> bool:
	var cell: Vector2i = pc._grid.world_to_grid(world_pos)
	var err: String = _lantern_placement_error(kind, cell)
	if err != "":
		pc._commands._reject_command("build", err, world_pos)
		return false
	var team: GameManager.Team = GameManager.Team.PLAYER
	# In-place upgrade: T1 -> T2 -> T3 at the same location.
	if kind == "lantern":
		var existing: Node2D = _surface_lantern_at_cell(cell)
		if existing != null:
			var upgrade_cost: int = Lantern.cost_for(false, existing.tier + 1)
			if not EconomyManager.spend_coin(team, upgrade_cost):
				pc._commands._reject_command("build", "not enough coin (%d needed)" % upgrade_cost, world_pos)
				return false
			existing.total_cost += upgrade_cost
			existing.upgrade()
			DebugLog.log_command("PlayerController", "build", "lantern upgraded to T%d at %s" % [existing.tier, str(cell)])
			return true
	var underground: bool = kind == "underground_lantern"
	var cost: int = Lantern.cost_for(underground, 1)
	if not EconomyManager.spend_coin(team, cost):
		pc._commands._reject_command("build", "not enough coin (%d needed)" % cost, world_pos)
		return false
	var lantern: Lantern = pc._LANTERN_SCENE.instantiate()
	lantern.team = team
	lantern.is_underground_lantern = underground
	lantern.total_cost = cost
	lantern.global_position = pc._grid.grid_to_world(cell)
	pc.get_node("/root/Main/Structures").add_child(lantern)
	DebugLog.log_command("PlayerController", "build", "%s at %s" % [kind, str(cell)])
	return true
