class_name Unit
extends Node2D

signal died(unit)

enum State { IDLE, MOVE, ATTACK, MINE, DEPOSIT, ENTER_MINE, EXIT_MINE, DEAD }

const _HP_BAR_BG: Texture2D = preload("res://frost_mines_assets/ui/hp_bar_unit_bg.png")
const _HP_BAR_GREEN: Texture2D = preload("res://frost_mines_assets/ui/hp_bar_unit_green.png")
const _HP_BAR_ORANGE: Texture2D = preload("res://frost_mines_assets/ui/hp_bar_unit_orange.png")

const _MINER_TEXTURES: Dictionary = {
	GameManager.Team.PLAYER: [
		preload("res://frost_mines_assets/units/miner_l1_player.png"),
		preload("res://frost_mines_assets/units/miner_l2_player.png"),
		preload("res://frost_mines_assets/units/miner_l3_player.png")
	],
	GameManager.Team.ENEMY: [
		preload("res://frost_mines_assets/units/miner_l1_enemy.png"),
		preload("res://frost_mines_assets/units/miner_l2_enemy.png"),
		preload("res://frost_mines_assets/units/miner_l3_enemy.png")
	]
}

@export var data: UnitData
@export var team: GameManager.Team = GameManager.Team.PLAYER

var hp: int = 0
var carried_coin: int = 0
var is_underground: bool = false
var selected: bool = false
var hovered: bool = false

var _state: State = State.IDLE
var _path: PackedVector2Array = PackedVector2Array()
var _path_index: int = 0
var _target_unit = null
var _target_building: Node2D = null
var _target_cell: Vector2i = Vector2i(-9999, -9999)
var _target_position: Vector2 = Vector2.ZERO
var _attack_timer: float = 0.0
var _mine_timer: float = 0.0
var _mine_target_angle: float = 0.0
var _mine_hit_flash: float = 0.0
var _dead_timer: float = 0.0
var _flee_timer: float = 0.0
var _flee_target: Vector2 = Vector2.ZERO

@onready var _grid: GridWorld = get_node("/root/Main/World/GridWorld")


func _ready() -> void:
	if data == null:
		data = preload("res://scripts/resources/units/swordsman.tres")
	if data.is_miner:
		_apply_miner_upgrade()
	hp = data.max_hp
	add_to_group("units")
	_add_hover_area()
	add_to_group(team_name())
	queue_redraw()
	# Spawners (the building) are responsible for issuing the first command.
	# This avoids double-ordering a miner before its first _process tick.
	# Deferred safety net: if a surface miner is still idle after spawn, send it in.
	if data.is_miner:
		call_deferred("_deferred_enter_mine_check")


func _process(delta: float) -> void:
	if _state == State.DEAD:
		_dead_timer -= delta
		modulate.a = max(0, _dead_timer)
		if _dead_timer <= 0:
			queue_free()
		return

	if _flee_timer > 0:
		_flee_timer -= delta
		if _state == State.IDLE:
			_continue_flee()
		match _state:
			State.MOVE:
				_follow_path(delta)
		return

	if data.is_miner:
		_apply_miner_upgrade()
		if _state == State.IDLE:
			_handle_idle_miner()
	elif data.is_fighter and _state == State.IDLE:
		_handle_idle_fighter()
	match _state:
		State.MOVE:
			_follow_path(delta)
		State.ATTACK:
			_process_attack(delta)
		State.MINE:
			_process_mine(delta)
		State.DEPOSIT:
			_process_deposit(delta)
		State.ENTER_MINE:
			_process_enter_mine(delta)
		State.EXIT_MINE:
			_process_exit_mine(delta)


# ---------- Commands ----------

func move_to(world_pos: Vector2) -> void:
	if data.is_fighter and _is_enemy_underground(world_pos):
		return
	_clear_target()
	_target_position = world_pos
	_state = State.MOVE
	_repath(world_pos)


func attack_unit(target) -> void:
	if target == null or target.team == team:
		return
	_clear_target()
	_target_unit = target
	_state = State.ATTACK


func attack_building(target: Node2D) -> void:
	if target == null:
		return
	_clear_target()
	_target_building = target
	_state = State.ATTACK


func mine_cell(grid_pos: Vector2i) -> void:
	if data == null or not data.is_miner:
		return
	_clear_target()
	_target_cell = grid_pos
	_state = State.MINE
	# Move adjacent.
	var adj: Vector2 = _nearest_adjacent_world(grid_pos)
	_repath(adj)


func deposit_coin() -> void:
	if data == null or not data.is_miner:
		return
	_clear_target()
	_state = State.DEPOSIT
	var entry: Node2D = _nearest_friendly_mine_entry()
	if entry:
		_repath(entry.global_position)
	else:
		_state = State.IDLE


func enter_mine() -> void:
	_clear_target()
	_state = State.ENTER_MINE
	var entry: Node2D = _nearest_friendly_mine_entry()
	if entry:
		_repath(entry.global_position)
		# If A* can't find a route, walk straight to the shaft instead of freezing.
		if _path.is_empty():
			_path.append(entry.global_position)
	else:
		_state = State.IDLE


func exit_mine() -> void:
	_clear_target()
	_state = State.EXIT_MINE
	var entry: Node2D = _nearest_friendly_mine_entry()
	if entry:
		_repath(entry.call("get_underground_position"))
	else:
		_state = State.IDLE


func stop() -> void:
	_clear_target()
	_state = State.IDLE
	_path.clear()


func take_damage(amount: int) -> void:
	hp -= amount
	queue_redraw()
	_spawn_damage_popup(amount)
	if hp <= 0:
		_die()
	elif data.is_miner:
		_start_flee()


func _spawn_damage_popup(amount: int) -> void:
	var popup: DamagePopup = preload("res://scenes/effects/damage_popup.tscn").instantiate()
	popup.setup(amount)
	popup.global_position = global_position + Vector2(0, -20)
	get_tree().current_scene.add_child(popup)


# ---------- State processing ----------

func _follow_path(delta: float) -> void:
	if _path.is_empty() or _path_index >= _path.size():
		_state = State.IDLE
		return
	var target: Vector2 = _path[_path_index]
	var dir: Vector2 = target - global_position
	var dist: float = dir.length()
	if dist <= 2.0:
		_path_index += 1
		if _path_index >= _path.size():
			_state = State.IDLE
			return
		target = _path[_path_index]
		dir = target - global_position
		dist = dir.length()
	var speed: float = data.speed
	if is_underground and data.is_fighter:
		speed *= 0.6
	var step: float = speed * delta
	global_position += dir.normalized() * min(step, dist)


func _process_attack(delta: float) -> void:
	_attack_timer -= delta
	var target_pos: Vector2 = Vector2.ZERO
	var target_alive: bool = false

	if _target_unit != null and is_instance_valid(_target_unit) and _target_unit._state != State.DEAD:
		target_pos = _target_unit.global_position
		target_alive = true
	elif _target_building != null and is_instance_valid(_target_building):
		target_pos = _target_building.global_position
		target_alive = true
	else:
		_state = State.IDLE
		return

	if global_position.distance_to(target_pos) > data.attack_range:
		_repath(target_pos)
		_follow_path(delta)
		return

	_path.clear()
	if _attack_timer <= 0:
		_attack_timer = 1.0 / data.attack_speed
		if data.attack_range <= 35.0:
			# Melee
			if _target_unit != null:
				_target_unit.take_damage(data.damage)
			elif _target_building != null:
				_target_building.call("take_damage", data.damage)
		else:
			# Ranged projectile.
			_spawn_projectile(target_pos)


func _spawn_projectile(target_pos: Vector2) -> void:
	var proj: Node2D = preload("res://scenes/projectile.tscn").instantiate()
	proj.position = global_position
	proj.set("team", team)
	proj.set("damage", data.damage)
	proj.set("is_fireball", data.unit_name == "Wizard")
	proj.set("target_position", target_pos)
	# Try to find the actual target node for homing.
	if _target_unit != null and is_instance_valid(_target_unit):
		proj.set("homing_target", _target_unit)
	elif _target_building != null and is_instance_valid(_target_building):
		proj.set("homing_building", _target_building)
	get_node("/root/Main/Projectiles").add_child(proj)


func _process_mine(delta: float) -> void:
	var cell: GridWorld.Cell = _grid.get_cell(_target_cell)
	if cell == null or cell.type == GridWorld.CellType.EMPTY:
		# Already mined; idle or find next ore.
		_state = State.IDLE
		return
	if carried_coin >= data.carry_capacity:
		deposit_coin()
		return
	if data.miner_level < cell.miner_level_required:
		_state = State.IDLE
		return

	var cell_world: Vector2 = _grid.grid_to_world(_target_cell)
	if global_position.distance_to(cell_world) > GridWorld.CELL_SIZE * 1.5:
		_repath(_nearest_adjacent_world(_target_cell))
		_follow_path(delta)
		return

	_path.clear()
	_mine_target_angle = (cell_world - global_position).angle()
	_mine_timer -= delta
	_mine_hit_flash -= delta
	queue_redraw()
	if _mine_timer <= 0:
		_mine_timer = 1.0 / data.mining_rate
		_mine_hit_flash = 0.08
		var dmg: int = max(1, data.damage)
		var coin: int = _grid.damage_cell(_target_cell, dmg, data.miner_level)
		if coin > 0:
			carried_coin = min(data.carry_capacity, carried_coin + coin)
			queue_redraw()


func _process_deposit(delta: float) -> void:
	var entry: Node2D = _nearest_friendly_mine_entry()
	if entry == null:
		_state = State.IDLE
		return
	var target_pos: Vector2 = entry.global_position if not is_underground else entry.call("get_underground_position")
	if global_position.distance_to(target_pos) > GridWorld.CELL_SIZE:
		_repath(target_pos)
		_follow_path(delta)
		return
	entry.call("deposit", self)
	_state = State.IDLE


func _process_enter_mine(delta: float) -> void:
	var entry: Node2D = _nearest_friendly_mine_entry()
	if entry == null:
		_state = State.IDLE
		return
	if global_position.distance_to(entry.global_position) > GridWorld.CELL_SIZE:
		_repath(entry.global_position)
		# Fallback: walk straight to the mine entry if pathfinding fails.
		if _path.is_empty():
			_path.append(entry.global_position)
		_follow_path(delta)
		return
	entry.call("enter_mine", self)
	_state = State.IDLE


func _process_exit_mine(delta: float) -> void:
	var entry: Node2D = _nearest_friendly_mine_entry()
	if entry == null:
		_state = State.IDLE
		return
	if global_position.distance_to(entry.call("get_underground_position")) > GridWorld.CELL_SIZE:
		_repath(entry.call("get_underground_position"))
		_follow_path(delta)
		return
	entry.call("exit_mine", self)
	_state = State.IDLE


# ---------- Helpers ----------

func _clear_target() -> void:
	_target_unit = null
	_target_building = null
	_target_cell = Vector2i(-9999, -9999)
	_target_position = Vector2.ZERO
	_path.clear()
	_path_index = 0


func _repath(target_world: Vector2) -> void:
	_path = _grid.find_path(global_position, target_world)
	_path_index = 0
	# Skip the first point if it is the current cell or if moving to it would
	# send us backward relative to the overall target direction (can happen when
	# the unit spawns on a sub-cell position and A* returns the cell center).
	if _path.size() > 1:
		var to_first: Vector2 = _path[0] - global_position
		var to_target: Vector2 = target_world - global_position
		if to_first.distance_to(Vector2.ZERO) < 4.0 or to_first.dot(to_target) < 0.0:
			_path_index = 1


func _nearest_adjacent_world(grid_pos: Vector2i) -> Vector2:
	var best: Vector2 = _grid.grid_to_world(grid_pos)
	var best_dist: float = 999999.0
	for off in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
		var adj: Vector2i = grid_pos + off
		if not _grid.is_solid(adj):
			var pos: Vector2 = _grid.grid_to_world(adj)
			var d: float = global_position.distance_squared_to(pos)
			if d < best_dist:
				best_dist = d
				best = pos
	return best


func _handle_idle_miner() -> void:
	# Full miners should deposit. Surface miners should enter the shaft first.
	# Underground miners look for the next cell to dig.
	if carried_coin >= data.carry_capacity:
		deposit_coin()
	elif not is_underground:
		enter_mine()
	else:
		_find_and_mine()


func _find_and_mine() -> void:
	var center: Vector2i = _grid.world_to_grid(global_position)
	var team_dir: int = _team_dir()

	# Helper closure: score a candidate cell.
	var best: Vector2i = Vector2i(-9999, -9999)
	var best_score: float = 999999.0
	var best_reachable: bool = false

	# Scan forward into the team's own side first so ties are broken toward the
	# center wall rather than back toward the friendly building.
	var x_start: int = 16 if team_dir == -1 else -16
	var x_end: int = -17 if team_dir == -1 else 17
	var x_step: int = -1 if team_dir == -1 else 1

	var scan := func(types: Array, reachable_only: bool) -> void:
		for x in range(x_start, x_end, x_step):
			for y in range(-2, 16):
				var pos: Vector2i = center + Vector2i(x, y)
				var cell: GridWorld.Cell = _grid.get_cell(pos)
				if cell == null or not (cell.type in types):
					continue
				if cell.type == GridWorld.CellType.SURFACE_GROUND:
					continue
				if data.miner_level < cell.miner_level_required:
					continue
				# Stick to own side of the mine until the central wall is breached.
				if _grid.get_wall_hp() > 0 and pos.x * team_dir < -2:
					continue
				var reachable: bool = _has_empty_neighbor(pos)
				if reachable_only and not reachable:
					continue
				var dist: float = center.distance_to(pos)
				# Prefer reachable cells, then ore over dirt, then closer.
				var is_ore: bool = cell.type == GridWorld.CellType.ORE
				var score: float = dist - (100.0 if reachable else 0.0) - (50.0 if is_ore else 0.0)
				if score < best_score:
					best_score = score
					best = pos
					best_reachable = reachable

	# First try reachable ore.
	scan.call([GridWorld.CellType.ORE], true)
	# Then reachable dirt to keep digging forward.
	if best == Vector2i(-9999, -9999):
		best_score = 999999.0
		scan.call([GridWorld.CellType.DIRT], true)
	# Last resort: any ore.
	if best == Vector2i(-9999, -9999):
		best_score = 999999.0
		scan.call([GridWorld.CellType.ORE], false)
	# Fallback: any diggable dirt.
	if best == Vector2i(-9999, -9999):
		best_score = 999999.0
		scan.call([GridWorld.CellType.DIRT], false)

	if best != Vector2i(-9999, -9999):
		mine_cell(best)
	else:
		# No diggable target in range; regroup near the mine entry.
		var entry: Node2D = _nearest_friendly_mine_entry()
		if entry:
			if is_underground:
				move_to(entry.call("get_underground_position"))
			else:
				move_to(entry.global_position)


func _has_empty_neighbor(grid_pos: Vector2i) -> bool:
	for off in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
		if not _grid.is_solid(grid_pos + off):
			return true
	return false


func _nearest_friendly_mine_entry() -> Node2D:
	var best: Node2D = null
	var best_dist: float = 999999.0
	for entry in get_tree().get_nodes_in_group("mine_entries"):
		if entry.get("team") == team:
			var d: float = global_position.distance_squared_to(entry.global_position)
			if d < best_dist:
				best_dist = d
				best = entry
	return best


func _die() -> void:
	_state = State.DEAD
	_dead_timer = 1.0
	remove_from_group("units")
	remove_from_group(team_name())
	EconomyManager.remove_population(team, data.population)
	died.emit(self)
	queue_redraw()


func _deferred_enter_mine_check() -> void:
	if data == null or not data.is_miner:
		return
	if not is_underground and _state == State.IDLE:
		enter_mine()


func team_name() -> String:
	return "player" if team == GameManager.Team.PLAYER else "enemy"


func _team_dir() -> int:
	return -1 if team == GameManager.Team.PLAYER else 1


func _is_enemy_underground(world_pos: Vector2) -> bool:
	if world_pos.y <= GridWorld.CELL_SIZE:
		return false
	return world_pos.x * _team_dir() < 0


func _start_flee() -> void:
	_flee_timer = 3.0
	var friendly_fighter: Unit = _nearest_friendly_fighter()
	if friendly_fighter != null and global_position.distance_to(friendly_fighter.global_position) <= 300:
		_flee_target = friendly_fighter.global_position
	else:
		var entry: Node2D = _nearest_friendly_mine_entry()
		if entry == null:
			_flee_timer = 0.0
			return
		_flee_target = entry.global_position
	_clear_target()
	_target_position = _flee_target
	_state = State.MOVE
	_repath(_flee_target)


func _continue_flee() -> void:
	if _flee_target == Vector2.ZERO:
		return
	_state = State.MOVE
	_repath(_flee_target)


func _nearest_friendly_fighter() -> Unit:
	var best: Unit = null
	var best_dist: float = 999999.0
	for unit in get_tree().get_nodes_in_group(team_name()):
		if unit == self or not unit.data.is_fighter:
			continue
		if unit._state == State.DEAD:
			continue
		var d: float = global_position.distance_squared_to(unit.global_position)
		if d < best_dist:
			best_dist = d
			best = unit
	return best


func _handle_idle_fighter() -> void:
	var target = _find_auto_attack_target()
	if target != null:
		if target is Unit:
			attack_unit(target)
		else:
			attack_building(target)
		return
	if is_underground:
		_patrol_underground()


func _find_auto_attack_target():
	# 1. Enemy fighters in attack range (closest first).
	var best: Unit = null
	var best_dist: float = data.attack_range * data.attack_range
	for unit in get_tree().get_nodes_in_group("units"):
		if unit.team == team or unit._state == State.DEAD:
			continue
		if not unit.data.is_fighter:
			continue
		var d: float = global_position.distance_squared_to(unit.global_position)
		if d <= best_dist:
			best_dist = d
			best = unit
	if best != null:
		return best

	# 2. Enemy fighters in sight range.
	best = null
	best_dist = data.sight_range * data.sight_range
	for unit in get_tree().get_nodes_in_group("units"):
		if unit.team == team or unit._state == State.DEAD:
			continue
		if not unit.data.is_fighter:
			continue
		var d: float = global_position.distance_squared_to(unit.global_position)
		if d <= best_dist:
			best_dist = d
			best = unit
	if best != null:
		return best

	# 3. Enemy building in sight range.
	var enemy_building: Node2D = _get_enemy_building()
	if enemy_building != null:
		var d: float = global_position.distance_squared_to(enemy_building.global_position)
		if d <= data.sight_range * data.sight_range:
			return enemy_building

	# 4. Enemy miners on our side of the wall (underground only).
	if is_underground:
		best = null
		best_dist = data.sight_range * data.sight_range
		var team_dir: int = _team_dir()
		for unit in get_tree().get_nodes_in_group("units"):
			if unit.team == team or unit._state == State.DEAD:
				continue
			if not unit.data.is_miner:
				continue
			var grid_x: int = _grid.world_to_grid(unit.global_position).x
			if grid_x * team_dir < 2:
				continue
			var d: float = global_position.distance_squared_to(unit.global_position)
			if d <= best_dist:
				best_dist = d
				best = unit
		if best != null:
			return best
	return null


func _patrol_underground() -> void:
	var entry: Node2D = _nearest_friendly_mine_entry()
	if entry == null:
		return
	var center: Vector2 = entry.call("get_underground_position")
	var angle: float = randf() * TAU
	var radius: float = randf_range(80, 240)
	var target: Vector2 = center + Vector2(cos(angle), sin(angle)) * radius
	# Clamp within the mine bounds.
	target.x = clamp(target.x, (GridWorld.X_MIN + 1) * GridWorld.CELL_SIZE, (GridWorld.X_MAX - 1) * GridWorld.CELL_SIZE)
	target.y = clamp(target.y, GridWorld.CELL_SIZE, GridWorld.Y_MAX * GridWorld.CELL_SIZE)
	move_to(target)


func _get_enemy_building() -> Node2D:
	for b in get_tree().get_nodes_in_group("buildings"):
		if b.get("team") != team:
			return b
	return null


func _add_hover_area() -> void:
	var area: Area2D = Area2D.new()
	area.name = "HoverArea"
	area.input_pickable = true
	area.mouse_entered.connect(func(): hovered = true; queue_redraw())
	area.mouse_exited.connect(func(): hovered = false; queue_redraw())
	var shape: CollisionShape2D = CollisionShape2D.new()
	var rect: RectangleShape2D = RectangleShape2D.new()
	var sprite_texture: Texture2D = _get_unit_texture()
	if sprite_texture != null:
		rect.size = sprite_texture.get_size()
	else:
		rect.size = Vector2(22, 22)
	shape.shape = rect
	area.add_child(shape)
	add_child(area)


func _apply_miner_upgrade() -> void:
	var level: int = EconomyManager.get_miner_level(team)
	if data.miner_level == level:
		return
	data.miner_level = level
	if level >= 2:
		data.max_dig_layer = 4
		data.carry_capacity += 5
		data.max_hp += 10
		data.mining_rate += 1.0
	if level >= 3:
		data.max_dig_layer = 7
		data.carry_capacity += 10
		data.max_hp += 15
		data.mining_rate += 2.0
	hp += 10
	queue_redraw()


func _draw_pickaxe() -> void:
	# Base pose: pickaxe held at the miner's side.
	var pivot: Vector2 = Vector2(4, 4)
	var base_rotation: float = -PI / 4.0
	var swing: float = 0.0
	var lunge: Vector2 = Vector2.ZERO
	var striking: bool = false

	if _state == State.MINE:
		# Time the swing to the mining rate so the strike lands on each hit.
		var period: float = 1.0 / max(0.1, data.mining_rate)
		var t: float = clamp(1.0 - (_mine_timer / period), 0.0, 1.0)
		# Aim the pickaxe toward the target cell.
		var aim_angle: float = _mine_target_angle - global_rotation
		base_rotation = aim_angle - PI / 6.0
		# Backswing (0%..60%), then sharp strike (60%..100%).
		if t < 0.6:
			swing = -PI * 0.55 * (t / 0.6)
		else:
			var strike_t: float = (t - 0.6) / 0.4
			swing = -PI * 0.55 + PI * 0.9 * strike_t
			striking = strike_t > 0.75
		if striking:
			lunge = Vector2(cos(aim_angle), sin(aim_angle)) * 3.0

	pivot += lunge
	draw_set_transform(pivot, base_rotation + swing, Vector2.ONE)
	# Handle.
	draw_line(Vector2.ZERO, Vector2(12, -12), GameManager.COLOR_STEEL, 2.5)
	# Pick head.
	draw_rect(Rect2(7, -16, 10, 5), GameManager.COLOR_STEEL, true)
	draw_line(Vector2(8, -18), Vector2(16, -14), Color.WHITE, 2.0)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

	# Spark burst on the strike impact.
	if _state == State.MINE and (_mine_hit_flash > 0.0 or striking):
		var tip: Vector2 = pivot + Vector2(cos(base_rotation + swing), sin(base_rotation + swing)) * 16.0
		var burst_color: Color = Color.YELLOW if _mine_hit_flash > 0.0 else Color.ORANGE
		# Bright impact point.
		draw_circle(tip, 3.0, burst_color)
		draw_circle(tip, 1.5, Color.WHITE)
		# Fixed radial sparks so they do not flicker every redraw.
		var spark_count: int = 6
		for i in range(spark_count):
			var spark_angle: float = base_rotation + swing + (i / float(spark_count)) * TAU
			var spark_len: float = 5.0 if _mine_hit_flash > 0.0 else 3.0
			draw_line(tip, tip + Vector2(cos(spark_angle), sin(spark_angle)) * spark_len, burst_color, 1.5)


# ---------- Drawing ----------

func _get_unit_texture() -> Texture2D:
	if data.is_miner:
		var idx: int = clampi(data.miner_level - 1, 0, 2)
		return _MINER_TEXTURES[team][idx]
	return data.texture


func _draw() -> void:
	var color: Color = GameManager.COLOR_PLAYER if team == GameManager.Team.PLAYER else GameManager.COLOR_ENEMY
	var sprite_texture: Texture2D = _get_unit_texture()
	var body_top: float
	var body_bottom: float
	var selection_radius: float

	if sprite_texture != null:
		var sprite_size: Vector2 = sprite_texture.get_size()
		body_top = -sprite_size.y / 2.0
		body_bottom = sprite_size.y / 2.0
		selection_radius = max(sprite_size.x, sprite_size.y) / 2.0 + 4.0
	else:
		var size: float = 18.0
		body_top = -size / 2.0
		body_bottom = size / 2.0
		selection_radius = size + 4.0

	# Selection indicator.
	if selected:
		draw_arc(Vector2.ZERO, selection_radius, 0, TAU, 16, Color.WHITE, 2.0)

	# Body.
	if sprite_texture != null:
		var sprite_size: Vector2 = sprite_texture.get_size()
		draw_texture(sprite_texture, -sprite_size / 2.0)
	else:
		var size: float = 18.0
		draw_rect(Rect2(-size / 2.0, -size / 2.0, size, size), color, true)
		draw_rect(Rect2(-size / 2.0, -size / 2.0, size, size), GameManager.COLOR_SHADOW, false, 1.0)

		# Weapon / class indicator.
		if data.is_miner:
			_draw_pickaxe()
		elif data.unit_name == "Swordsman":
			draw_line(Vector2(4, 4), Vector2(16, -8), Color.WHITE, 3.0)
		elif data.unit_name == "Archer":
			draw_arc(Vector2(10, 0), 7, -PI / 2, PI / 2, 8, GameManager.COLOR_RUST, 2.0)
			draw_line(Vector2(10, -7), Vector2(10, 7), GameManager.COLOR_RUST, 2.0)
		elif data.unit_name == "Wizard":
			draw_line(Vector2(6, 6), Vector2(12, -14), GameManager.COLOR_RUST, 2.0)
			draw_circle(Vector2(12, -16), 4, Color.PURPLE)

	# HP bar when damaged, hovered, or selected.
	if selected or hovered or hp < data.max_hp:
		var hp_pct: float = float(hp) / float(data.max_hp)
		var bar_rect: Rect2 = Rect2(-10, body_top - 8, 20, 4)
		draw_texture_rect(_HP_BAR_BG, bar_rect, false)
		if hp_pct > 0.0:
			var fill_texture: Texture2D = _HP_BAR_GREEN if hp_pct >= 0.5 else _HP_BAR_ORANGE
			var fill_rect: Rect2 = Rect2(-10, body_top - 8, 20 * hp_pct, 4)
			var src_rect: Rect2 = Rect2(0, 0, fill_texture.get_width() * hp_pct, fill_texture.get_height())
			draw_texture_rect_region(fill_texture, fill_rect, src_rect)

	# Carried coin indicator for miners.
	if data.is_miner and carried_coin > 0:
		draw_rect(Rect2(-6, body_bottom + 2, 12, 6), GameManager.COLOR_RUST, true)
