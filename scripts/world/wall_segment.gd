class_name WallSegment
extends Node2D

## Placeable wall segment (Revamp Phase 3): a single-cell surface barrier.
## Once construction finishes the cell becomes A*-solid (blocking movement)
## and enemy projectiles striking it are absorbed (see projectile.gd). Walls
## do not attack and provide no vision. Invulnerable while under
## construction; a destroyed wall frees its cell and drops half its build
## cost as a coin pickup.

signal hp_changed(current: int, maximum: int)
signal destroyed(wall: WallSegment)
signal construction_complete(wall: WallSegment)

const _Constants = preload("res://scripts/autoload/constants.gd")

const _TEXTURES: Dictionary = {
	GameManager.Team.PLAYER: preload("res://frost_mines_assets/props/wall_player.png"),
	GameManager.Team.ENEMY: preload("res://frost_mines_assets/props/wall_enemy.png"),
}

var team: GameManager.Team = GameManager.Team.PLAYER

var max_hp: int = _Constants.PLACED_WALL_HP
var hp: int = 0
var build_time: float = _Constants.PLACED_WALL_BUILD_TIME
# Coin spent on this wall (salvage pays half).
var total_cost: int = 0

var _build_progress: float = 0.0
var _is_built: bool = false
var _cell: Vector2i = Vector2i(-9999, -9999)

@onready var _grid: GridWorld = get_node("/root/Main/World/GridWorld")


func _ready() -> void:
	add_to_group("walls")
	hp = max_hp
	_cell = _grid.world_to_grid(global_position)
	# A cell dug out beneath the finished wall stays blocked — the wall seals
	# its whole column, so enemies can't tunnel underneath it.
	if not _grid.cell_destroyed.is_connected(_on_cell_destroyed):
		_grid.cell_destroyed.connect(_on_cell_destroyed)
	queue_redraw()


func is_built() -> bool:
	return _is_built


func get_cell() -> Vector2i:
	return _cell


func _process(delta: float) -> void:
	if not GameManager.game_active:
		return
	if not _is_built:
		_build_progress += delta
		if _build_progress >= build_time:
			_is_built = true
			# The barrier only exists once built — block the column now.
			_seal_column()
			_repath_units_crossing_cell()
			construction_complete.emit(self)
		queue_redraw()


## Blocks the surface cell and every dug cell directly below it. Walls are
## full-depth barriers, like the central wall that spans all layers —
## otherwise A* happily routes enemies through tunnels dug beneath the
## surface row and the wall never gets attacked. Undug dirt and real wall
## cells are already A*-solid on their own.
func _seal_column() -> void:
	for y in range(GridWorld.Y_MIN, GridWorld.Y_MAX + 1):
		var pos := Vector2i(_cell.x, y)
		if _is_sealable(pos):
			_grid.seal_wall_cell(pos, team)


## A column cell the wall is responsible for sealing: the surface row, and
## dug-out cells beneath (carved tunnels are erased from the grid, so they
## read as null; EMPTY covers any cell object left behind).
func _is_sealable(pos: Vector2i) -> bool:
	if pos.y == _cell.y:
		return true
	var cell: GridWorld.Cell = _grid.get_cell(pos)
	return cell == null or cell.type == GridWorld.CellType.EMPTY


## Keeps the column sealed when a miner digs out a cell beneath the wall.
func _on_cell_destroyed(grid_pos: Vector2i) -> void:
	if _is_built and grid_pos.x == _cell.x:
		_grid.seal_wall_cell(grid_pos, team)


## Enemy units that plotted a course through the wall's column before it was
## blocked must not walk through the finished wall — force a re-path around
## it (or a stop at the wall when no route exists). The owning team is
## untouched: its paths legally pass its own walls.
func _repath_units_crossing_cell() -> void:
	for unit in get_tree().get_nodes_in_group("units"):
		if unit._state == Unit.State.DEAD or unit._path.is_empty() or unit.team == team:
			continue
		for p: Vector2 in unit._path:
			if _grid.world_to_grid(p).x == _cell.x:
				unit._repath(unit._path[unit._path.size() - 1])
				break


func take_damage(amount: int) -> void:
	# Invulnerable while under construction (guide rule, same as lanterns).
	if not _is_built:
		return
	hp -= amount
	hp_changed.emit(hp, max_hp)
	queue_redraw()
	if hp <= 0:
		_destroy()


func _destroy() -> void:
	remove_from_group("walls")
	# Free the cells this wall sealed: the surface row and dug cells beneath
	# it. Undug dirt stays A*-solid on its own.
	if _grid != null:
		for y in range(GridWorld.Y_MIN, GridWorld.Y_MAX + 1):
			var pos := Vector2i(_cell.x, y)
			if _is_sealable(pos):
				_grid.unseal_wall_cell(pos)
	destroyed.emit(self)
	AudioManager.play("blast", global_position, -6.0)
	var salvage: int = roundi(total_cost * _Constants.STRUCTURE_SALVAGE_RATIO)
	if salvage > 0:
		var pickup: Node2D = preload("res://scenes/effects/coin_pickup.tscn").instantiate()
		pickup.global_position = global_position
		pickup.set("coin_value", salvage)
		get_tree().current_scene.add_child(pickup)
	queue_free()


## Interaction rect for unit.attack_building(): a zero-height strip at the
## wall's ground line so the stand point lands on the walkable surface row.
func get_bounds_rect() -> Rect2:
	return Rect2(global_position.x - 16.0, 0.0, 32.0, 0.0)


func _draw() -> void:
	var texture: Texture2D = _TEXTURES[team]
	var tex_size: Vector2 = texture.get_size()
	var alpha: float = 1.0 if _is_built else 0.55
	# The wall fills its surface-row cell (local +16 = cell center).
	draw_texture_rect(texture, Rect2(-tex_size / 2.0, tex_size), false, Color(1, 1, 1, alpha))

	# Construction progress bar / HP bar.
	if not _is_built:
		var pct: float = clampf(_build_progress / build_time, 0.0, 1.0)
		var bar_rect := Rect2(-12, -tex_size.y / 2.0 - 8, 24, 4)
		draw_rect(bar_rect, Color(0, 0, 0, 0.7), true)
		draw_rect(Rect2(bar_rect.position, Vector2(bar_rect.size.x * pct, bar_rect.size.y)), Color(0.5, 0.8, 1.0), true)
	elif hp < max_hp:
		var pct: float = clampf(float(hp) / float(max_hp), 0.0, 1.0)
		var bar_rect := Rect2(-12, -tex_size.y / 2.0 - 8, 24, 4)
		draw_rect(bar_rect, Color(0, 0, 0, 0.7), true)
		draw_rect(Rect2(bar_rect.position, Vector2(bar_rect.size.x * pct, bar_rect.size.y)), Color.GREEN if pct >= 0.5 else Color.ORANGE, true)
