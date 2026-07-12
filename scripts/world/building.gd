extends Node2D

signal hp_changed(current: int, maximum: int)
signal queue_changed(entries: Array)
signal destroyed(team: GameManager.Team)

@export var team: GameManager.Team = GameManager.Team.PLAYER
@export var max_hp: int = 2500
@export var unit_scene: PackedScene
@export var width_cells: int = 6
@export var height_cells: int = 5

var _hp: int = max_hp
var _queue: Array = []  # { id: String, data: UnitData, remaining: float }
var _resources: Dictionary = {}

@onready var _grid: GridWorld = get_node("/root/Main/World/GridWorld")


func _ready() -> void:
	_hp = max_hp
	add_to_group("buildings")
	_resources["miner"] = preload("res://scripts/resources/units/miner.tres")
	_resources["swordsman"] = preload("res://scripts/resources/units/swordsman.tres")
	_resources["archer"] = preload("res://scripts/resources/units/archer.tres")
	_resources["wizard"] = preload("res://scripts/resources/units/wizard.tres")
	_mark_footprint_solid()
	queue_redraw()


func _mark_footprint_solid() -> void:
	if _grid == null:
		return
	var origin: Vector2i = _grid.world_to_grid(global_position)
	for x in range(-width_cells / 2, width_cells / 2):
		for y in range(0, -height_cells, -1):
			var pos: Vector2i = origin + Vector2i(x, y)
			# Replace surface cells with building cells so units path around.
			if _grid.has_cell(pos):
				_grid._cells[pos] = GridWorld.Cell.new(GridWorld.CellType.WALL, 0, 99, 9999, 0, true)
				_grid._astar.set_point_solid(pos, true)


func _process(delta: float) -> void:
	if _queue.is_empty():
		return
	var current = _queue[0]
	current.remaining -= delta
	if current.remaining <= 0.0:
		_spawn_front(current.id, current.data)
		_queue.pop_front()
		queue_changed.emit(_queue)


func queue_unit(unit_id: String) -> bool:
	if not _resources.has(unit_id):
		return false
	var data: UnitData = _resources[unit_id]
	if not EconomyManager.can_afford(team, data.cost):
		return false
	if not EconomyManager.can_add_population(team, data.population):
		return false
	if not EconomyManager.spend_coin(team, data.cost):
		return false
	_queue.append({ "id": unit_id, "data": data, "remaining": data.train_time })
	queue_changed.emit(_queue)
	return true


func _spawn_front(unit_id: String, data: UnitData) -> void:
	if not EconomyManager.can_add_population(team, data.population):
		# Refund if cap reached.
		EconomyManager.add_coin(team, data.cost)
		return
	EconomyManager.add_population(team, data.population)
	var unit: Node2D = unit_scene.instantiate()
	var data_copy: UnitData = data.duplicate(true)
	unit.set("data", data_copy)
	unit.set("team", team)
	unit.position = _spawn_position()
	get_node("/root/Main/Units").add_child(unit)


func _spawn_position() -> Vector2:
	var dir: float = 1.0 if team == GameManager.Team.PLAYER else -1.0
	return global_position + Vector2(dir * (width_cells * GridWorld.CELL_SIZE / 2.0 + 24), 0)


func take_damage(amount: int) -> void:
	_hp -= amount
	hp_changed.emit(_hp, max_hp)
	queue_redraw()
	if _hp <= 0:
		_hp = 0
		destroyed.emit(team)
		var winner: GameManager.Team = GameManager.Team.PLAYER if team == GameManager.Team.ENEMY else GameManager.Team.ENEMY
		GameManager.declare_winner(winner)


func get_queue() -> Array:
	return _queue


func _draw() -> void:
	var w: float = width_cells * GridWorld.CELL_SIZE
	var h: float = height_cells * GridWorld.CELL_SIZE
	var rect: Rect2 = Rect2(-w / 2.0, -h, w, h)
	var color: Color = GameManager.COLOR_PLAYER if team == GameManager.Team.PLAYER else GameManager.COLOR_ENEMY
	draw_rect(rect, GameManager.COLOR_STEEL, true)
	draw_rect(rect, color, false, 3.0)
	# Roof / greeble details.
	draw_rect(Rect2(rect.position.x + 8, rect.position.y + 8, w - 16, 12), color.darkened(0.3), true)
	draw_rect(Rect2(rect.position.x + 12, rect.position.y + h - 20, 16, 20), GameManager.COLOR_SHADOW, true)
	draw_rect(Rect2(rect.position.x + w - 28, rect.position.y + h - 20, 16, 20), GameManager.COLOR_SHADOW, true)
