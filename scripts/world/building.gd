extends Node2D

const _Constants = preload("res://scripts/autoload/constants.gd")

const _HP_BAR_BG: Texture2D = preload("res://frost_mines_assets/ui/hp_bar_bg.png")
const _HP_BAR_GREEN: Texture2D = preload("res://frost_mines_assets/ui/hp_bar_green.png")
const _HP_BAR_RED: Texture2D = preload("res://frost_mines_assets/ui/hp_bar_red.png")

const _BUILDING_TEXTURES: Dictionary = {
	GameManager.Team.PLAYER: preload("res://frost_mines_assets/buildings/building_player.png"),
	GameManager.Team.ENEMY: preload("res://frost_mines_assets/buildings/building_enemy.png")
}

signal hp_changed(current: int, maximum: int)
signal queue_changed(entries: Array)
signal destroyed(team: GameManager.Team)
signal coin_deposited(team: GameManager.Team, amount: int)

@export var team: GameManager.Team = GameManager.Team.PLAYER
@export var max_hp: int = _Constants.PLAYER_BUILDING_HP
@export var unit_scene: PackedScene
@export var width_cells: int = 6
@export var height_cells: int = 5

var _hp: int = max_hp
var _queue: Array = []  # { id: String, data: UnitData, remaining: float }
var _resources: Dictionary = {}
var _destroyed: bool = false
var _deposit_point: Marker2D
# Collapse sequence after destruction: squash + darken over ~1.2 scaled
# seconds (stretched by the game-over slow-mo, which is the point).
var _collapsing: bool = false
var _collapse_t: float = 0.0

@onready var _grid: GridWorld = get_node("/root/Main/World/GridWorld")


func _ready() -> void:
	_hp = max_hp
	_destroyed = false
	add_to_group("buildings")
	_resources["miner"] = preload("res://scripts/resources/units/miner.tres")
	_resources["swordsman"] = preload("res://scripts/resources/units/swordsman.tres")
	_resources["archer"] = preload("res://scripts/resources/units/archer.tres")
	_resources["wizard"] = preload("res://scripts/resources/units/wizard.tres")
	_mark_footprint_solid()
	_add_deposit_point()
	_connect_view_mode()
	queue_redraw()
	call_deferred("_spawn_starting_miners")


## Each base starts with free miners so the economy runs from the first
## second. They still count toward the population cap.
func _spawn_starting_miners() -> void:
	for i in range(_Constants.STARTING_MINERS):
		_spawn_front("miner", _resources["miner"])


func _connect_view_mode() -> void:
	var pc: PlayerController = get_node_or_null("/root/Main/PlayerController")
	if pc:
		if not pc.view_mode_changed.is_connected(_on_view_mode_changed):
			pc.view_mode_changed.connect(_on_view_mode_changed)
		_on_view_mode_changed(pc.get_current_view_mode())


func _on_view_mode_changed(mode: PlayerController.ViewMode) -> void:
	# Surface and underground are shown simultaneously; keep the building visible.
	visible = true


func _mark_footprint_solid() -> void:
	if _grid == null:
		return
	var origin: Vector2i = _grid.world_to_grid(global_position)
	for x in range(-width_cells / 2, width_cells / 2):
		# Keep the surface row (y = 0) walkable so units can pass the base.
		for y in range(-1, -height_cells, -1):
			var pos: Vector2i = origin + Vector2i(x, y)
			if _grid.has_cell(pos):
				_grid._cells[pos] = GridWorld.Cell.new(GridWorld.CellType.WALL, 0, 99, 9999, 0, true)
				if _grid._astar.is_in_boundsv(pos):
					_grid._astar.set_point_solid(pos, true)


## World-space rect of the building body: its base sits at global_position and
## it extends width_cells wide and height_cells tall upward. Attack ranges are
## measured against this rect, not the center point.
func get_bounds_rect() -> Rect2:
	var size: Vector2 = Vector2(width_cells * GridWorld.CELL_SIZE, height_cells * GridWorld.CELL_SIZE)
	return Rect2(global_position - Vector2(size.x / 2.0, size.y), size)


## Grid-space rect of the cells the building body occupies.
func get_footprint_cell_rect() -> Rect2i:
	var origin: Vector2i = _grid.world_to_grid(global_position)
	return Rect2i(origin.x - width_cells / 2, origin.y - height_cells, width_cells, height_cells)


## World position where miners stand to deposit cargo: on the walkable surface
## row just outside the building's front edge (the side facing the mine).
func get_deposit_point() -> Vector2:
	return _deposit_point.global_position


func _process(delta: float) -> void:
	if _collapsing:
		_collapse_t += delta
		var t: float = clampf(_collapse_t / 1.2, 0.0, 1.0)
		scale.y = lerpf(1.0, 0.25, t)
		modulate = Color.WHITE.lerp(Color(0.25, 0.25, 0.28, 0.85), t)
		if t >= 1.0:
			_collapsing = false
		return
	if _destroyed:
		return
	if not GameManager.game_active:
		return
	if _queue.is_empty():
		return
	var current = _queue[0]
	# AI difficulty scales training speed (rates, never rules); players are 1.0.
	var train_time_mult: float = 1.0
	if team == GameManager.Team.ENEMY:
		train_time_mult = maxf(0.05, GameManager.get_ai_train_time_multiplier())
	current.remaining -= delta / train_time_mult
	if current.remaining <= 0.0:
		DebugLog.log_command("Building %d" % get_instance_id(), "training_complete", current.id)
		_spawn_front(current.id, current.data)
		_queue.pop_front()
		queue_changed.emit(_queue)


func queue_unit(unit_id: String) -> bool:
	if not _resources.has(unit_id):
		DebugLog.log_reject("Building %d" % get_instance_id(), "queue_unit", "unknown unit_id " + unit_id)
		return false
	var data: UnitData = _resources[unit_id]
	if not EconomyManager.can_afford(team, data.cost):
		DebugLog.log_reject("Building %d" % get_instance_id(), "queue_unit", "cannot afford " + unit_id)
		return false
	if not EconomyManager.can_add_population(team, data.population):
		DebugLog.log_reject("Building %d" % get_instance_id(), "queue_unit", "population cap")
		return false
	if not EconomyManager.spend_coin(team, data.cost):
		DebugLog.log_reject("Building %d" % get_instance_id(), "queue_unit", "spend failed " + unit_id)
		return false
	_queue.append({ "id": unit_id, "data": data, "remaining": data.train_time })
	DebugLog.log_command("Building %d" % get_instance_id(), "queue_unit", unit_id)
	queue_changed.emit(_queue)
	return true


func _spawn_front(_unit_id: String, data: UnitData) -> void:
	if not EconomyManager.can_add_population(team, data.population):
		# Refund if cap reached.
		EconomyManager.add_coin(team, data.cost)
		return
	EconomyManager.add_population(team, data.population)
	EconomyManager.train_unit(team)
	var unit: Node2D = unit_scene.instantiate()
	var data_copy: UnitData = data.duplicate(true)
	unit.set("data", data_copy)
	unit.set("team", team)
	unit.position = _spawn_position()
	get_node("/root/Main/Units").add_child(unit)
	# Make sure miners head straight into the shaft as soon as they spawn.
	if data_copy.is_miner and unit.has_method("climb_down_ladder"):
		unit.call("climb_down_ladder")


func _spawn_position() -> Vector2:
	var dir: float = 1.0 if team == GameManager.Team.PLAYER else -1.0
	var base: Vector2 = global_position + Vector2(dir * (width_cells * GridWorld.CELL_SIZE / 2.0 + 24), 0)
	# Phase 3.4: slight spawn offset so multiple trained units don't stack into one sprite.
	return base + Vector2(randf_range(-8, 8), randf_range(-6, 6))


func _add_deposit_point() -> void:
	_deposit_point = Marker2D.new()
	_deposit_point.name = "DepositPoint"
	var dir: float = 1.0 if team == GameManager.Team.PLAYER else -1.0
	# On the walkable surface row, just outside the front edge facing the mine.
	_deposit_point.position = Vector2(
		dir * (width_cells * GridWorld.CELL_SIZE / 2.0 + GridWorld.CELL_SIZE * 0.5),
		GridWorld.CELL_SIZE * 0.5
	)
	add_child(_deposit_point)


## Miner deposit entry point (Phase 3.1): cargo is cashed in at the building
## after the visible surface walk, not at the mine shaft.
func deposit(unit: Node2D) -> void:
	if unit == null:
		DebugLog.log_reject("Building %d" % get_instance_id(), "deposit", "null unit")
		return
	var unit_data = unit.get("data")
	if unit_data == null or not unit_data.is_miner:
		return
	var carried: int = unit.get("carried_coin")
	if carried > 0:
		# AI difficulty scales deposit income (rates, never rules); players 1.0.
		var amount: int = carried
		if team == GameManager.Team.ENEMY:
			amount = roundi(carried * GameManager.get_ai_coin_multiplier())
		DebugLog.log_command("Building %d" % get_instance_id(), "deposit", "team=%s amount=%d" % ["PLAYER" if team == GameManager.Team.PLAYER else "ENEMY", amount])
		EconomyManager.add_coin(team, amount)
		EconomyManager.mine_coin(team, amount)
		coin_deposited.emit(team, amount)
		unit.set("carried_coin", 0)
		_spawn_coin_popup(amount)
		AudioManager.play("coin", get_deposit_point(), -4.0)


func _spawn_coin_popup(amount: int) -> void:
	var popup: CoinPopup = preload("res://scenes/effects/coin_popup.tscn").instantiate()
	popup.setup(amount)
	popup.global_position = get_deposit_point() + Vector2(0, -30)
	get_tree().current_scene.add_child(popup)


func take_damage(amount: int) -> void:
	if _destroyed:
		return
	_hp -= amount
	hp_changed.emit(_hp, max_hp)
	queue_redraw()
	_spawn_damage_popup(amount)
	# Alarm once the base is critical.
	if _hp > 0 and _hp < max_hp * 0.25:
		AudioManager.play("alarm", global_position, -2.0)
	if _hp <= 0:
		_hp = 0
		_destroyed = true
		_queue.clear()
		remove_from_group("buildings")
		destroyed.emit(team)
		AudioManager.play("blast", global_position, 2.0)
		_start_collapse()
		var winner: GameManager.Team = GameManager.Team.PLAYER if team == GameManager.Team.ENEMY else GameManager.Team.ENEMY
		GameManager.declare_winner(winner)


## One-time dust explosion over the footprint as the building starts to fall.
func _start_collapse() -> void:
	_collapsing = true
	_collapse_t = 0.0
	var dust: GPUParticles2D = GPUParticles2D.new()
	dust.one_shot = true
	dust.explosiveness = 0.9
	dust.amount = 80
	dust.lifetime = 1.4
	dust.texture = _make_dot_texture()
	dust.modulate = Color(0.7, 0.65, 0.55, 0.8)
	var mat: ParticleProcessMaterial = ParticleProcessMaterial.new()
	mat.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	mat.emission_box_extents = Vector3(width_cells * GridWorld.CELL_SIZE / 2.0, height_cells * GridWorld.CELL_SIZE / 2.0, 1)
	mat.direction = Vector3(0, -1, 0)
	mat.spread = 90.0
	mat.gravity = Vector3(0, 60, 0)
	mat.initial_velocity_min = 40.0
	mat.initial_velocity_max = 120.0
	mat.scale_min = 0.4
	mat.scale_max = 1.2
	dust.process_material = mat
	# Emit from the middle of the building body.
	dust.position = Vector2(0, -height_cells * GridWorld.CELL_SIZE / 2.0)
	add_child(dust)
	dust.emitting = true


## Small soft white dot used as the particle sprite (no art dependency).
func _make_dot_texture() -> Texture2D:
	var img: Image = Image.create(8, 8, false, Image.FORMAT_RGBA8)
	for x in range(8):
		for y in range(8):
			var d: float = Vector2(x - 3.5, y - 3.5).length()
			img.set_pixel(x, y, Color(1, 1, 1, clampf(1.0 - d / 4.0, 0.0, 1.0)))
	return ImageTexture.create_from_image(img)


func _spawn_damage_popup(amount: int) -> void:
	var popup: DamagePopup = preload("res://scenes/effects/damage_popup.tscn").instantiate()
	popup.setup(amount)
	popup.global_position = global_position + Vector2(0, -100)
	get_tree().current_scene.add_child(popup)


func get_queue() -> Array:
	return _queue


func cancel_queue(index: int) -> bool:
	if _queue.is_empty() or index < 0 or index >= _queue.size():
		DebugLog.log_reject("Building %d" % get_instance_id(), "cancel_queue", "invalid index %d" % index)
		return false
	var entry = _queue[index]
	EconomyManager.add_coin(team, entry.data.cost)
	_queue.remove_at(index)
	DebugLog.log_command("Building %d" % get_instance_id(), "cancel_queue", "%s refund=%d" % [entry.id, entry.data.cost])
	queue_changed.emit(_queue)
	return true


func _draw() -> void:
	var texture: Texture2D = _BUILDING_TEXTURES[team]
	var sprite_size: Vector2 = texture.get_size()
	var sprite_rect: Rect2 = Rect2(-sprite_size.x / 2.0, -sprite_size.y, sprite_size.x, sprite_size.y)
	draw_texture(texture, sprite_rect.position)

	# Health bar (hidden once destroyed — the rubble doesn't need one).
	if _destroyed:
		return
	var hp_pct: float = float(_hp) / float(max_hp)
	var bar_w: float = sprite_size.x - 16
	var bar_h: float = 8
	var bar_pos: Vector2 = Vector2(sprite_rect.position.x + 8, sprite_rect.position.y - 16)
	var bar_rect: Rect2 = Rect2(bar_pos, Vector2(bar_w, bar_h))
	draw_texture_rect(_HP_BAR_BG, bar_rect, false)
	var fill_texture: Texture2D = _HP_BAR_GREEN if team == GameManager.Team.PLAYER else _HP_BAR_RED
	if hp_pct > 0.0:
		var fill_rect: Rect2 = Rect2(bar_pos, Vector2(bar_w * hp_pct, bar_h))
		var src_rect: Rect2 = Rect2(0, 0, fill_texture.get_width() * hp_pct, fill_texture.get_height())
		draw_texture_rect_region(fill_texture, fill_rect, src_rect)
