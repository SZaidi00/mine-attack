class_name GridEvents
extends RefCounted

## Dynamic terrain & events (Revamp Phase 4): lava rising, cave-ins, and ore
## vein respawn. All timers accumulate game-time delta from GridWorld._process
## (which only ticks while GameManager.game_active), so events freeze on pause
## and game-over exactly like units and research. Random scheduling is gated
## by events_enabled — forced triggers (tests, debug) always work.

const _Constants = preload("res://scripts/autoload/constants.gd")

var grid: GridWorld
# Random event scheduling on/off; in-flight events (warning, active lava,
# pending cave-in restore) always run to completion either way.
var events_enabled: bool = true

# Game-time clock driving the schedules (seconds of active match time).
var _clock: float = 0.0

# Lava state machine: idle → warning → active → idle (then rescheduled).
var _lava_next_at: float = 0.0
var _lava_warning_left: float = 0.0
var _lava_active_left: float = 0.0
var _lava_layers: int = 0
var _lava_sweep_timer: float = 0.0
# pos -> original Cell for ore/fresh-ore tiles submerged by the current lava
# event, so their gold can be restored after the flood if they weren't mined.
var _lava_original_cells: Dictionary = {}

# Cave-in schedule and the pending restore (pos -> original cell fields).
var _cavein_next_at: float = 0.0
var _cave_in_cells: Dictionary = {}
var _cavein_restore_left: float = 0.0
var _cavein_warning_left: float = 0.0
var _cavein_warning_center: Vector2i = Vector2i(-9999, -9999)

# Ore vein respawn schedule.
var _ore_respawn_next_at: float = 0.0


func _init(g: GridWorld) -> void:
	grid = g


## Called from GridWorld._ready: the first events land inside their random
## windows after match start.
func schedule_initial() -> void:
	_lava_next_at = randf_range(_Constants.LAVA_MIN_INTERVAL, _Constants.LAVA_MAX_INTERVAL)
	_cavein_next_at = randf_range(_Constants.CAVEIN_MIN_INTERVAL, _Constants.CAVEIN_MAX_INTERVAL)
	_ore_respawn_next_at = _Constants.ORE_RESPAWN_INTERVAL


func _process_events(delta: float) -> void:
	_clock += delta

	# Lava: warning countdown → rise → active countdown (+ straggler sweep) →
	# recede → reschedule. These run regardless of events_enabled so a forced
	# event always completes.
	if _lava_warning_left > 0.0:
		_lava_warning_left -= delta
		grid.queue_redraw()  # Keep the warning glow pulsing.
		if _lava_warning_left <= 0.0:
			_lava_warning_left = 0.0
			_rise_lava(_lava_layers)
	elif _lava_active_left > 0.0:
		_lava_active_left -= delta
		_lava_sweep_timer -= delta
		if _lava_sweep_timer <= 0.0:
			_lava_sweep_timer = _Constants.LAVA_SWEEP_INTERVAL
			_kill_units_in_lava()
		if _lava_active_left <= 0.0:
			_lava_active_left = 0.0
			_recede_lava()
	elif events_enabled and _clock >= _lava_next_at:
		_start_lava_warning()

	# Cave-in: warning → collapse → rock restore. The restore always ticks;
	# only new random cave-ins are gated by events_enabled.
	if _cavein_warning_left > 0.0:
		_cavein_warning_left -= delta
		if _cavein_warning_left <= 0.0:
			_cavein_warning_left = 0.0
			_trigger_cave_in(_cavein_warning_center)
	elif _cavein_restore_left > 0.0:
		_cavein_restore_left -= delta
		if _cavein_restore_left <= 0.0:
			_cavein_restore_left = 0.0
			_restore_cave_in()
	elif events_enabled and _clock >= _cavein_next_at - _get_cavein_warning_time():
		_start_cavein_warning()
	elif events_enabled and _clock >= _cavein_next_at:
		_trigger_cave_in(_pick_cave_in_center())

	# Ore respawn.
	if events_enabled and _clock >= _ore_respawn_next_at:
		_ore_respawn_next_at = _clock + _Constants.ORE_RESPAWN_INTERVAL
		respawn_ore(false)


# ─── Lava rising ───

func is_lava_warning() -> bool:
	return _lava_warning_left > 0.0


func is_lava_active() -> bool:
	return _lava_active_left > 0.0


func get_lava_warning_remaining() -> float:
	return _lava_warning_left


func _start_lava_warning(layers: int = -1) -> void:
	if _lava_warning_left > 0.0 or _lava_active_left > 0.0:
		return
	if layers > 0:
		_lava_layers = layers
	else:
		# Pick a random flood top. Layer 1 is shallowest, layer 7 is deepest;
		# flooding more layers means a lower (more severe) top layer. The most
		# severe top layer (3) is gated behind LAVA_TOP_LAYER_UNLOCK_TIME.
		var unlock_time: float = _Constants.LAVA_TOP_LAYER_UNLOCK_TIME
		var min_top: int = _Constants.LAVA_TOP_LAYER_MIN
		if _clock < unlock_time:
			var early_min: int = _Constants.LAVA_TOP_LAYER_EARLY_MIN
			var t: float = _clock / unlock_time
			min_top = int(round(lerp(float(early_min), float(min_top), t)))
		min_top = clampi(min_top, _Constants.LAVA_TOP_LAYER_MIN, _Constants.LAVA_TOP_LAYER_MAX)
		var top: int = randi_range(min_top, _Constants.LAVA_TOP_LAYER_MAX)
		_lava_layers = _Constants.LAVA_TOP_LAYER_MAX - top + 1
	var warning: float = _Constants.LAVA_WARNING_TIME
	_lava_warning_left = warning
	DebugLog.log_command("GridEvents", "lava_warning", "layers=%d warning=%.0fs" % [_lava_layers, warning])
	AudioManager.play("rumble", Vector2.INF, -4.0)
	_shake(4.0)
	grid.lava_warning_started.emit(warning, _lava_layers)
	grid.queue_redraw()


## Top row of the lava zone for the current layer count.
func _lava_zone_top() -> int:
	return grid.Y_MAX - _lava_layers * _Constants.ROWS_PER_LAYER + 1


func _rise_lava(layers: int) -> void:
	if _lava_active_left > 0.0:
		return
	_lava_layers = layers
	_lava_warning_left = 0.0
	_lava_original_cells.clear()
	var y_from: int = _lava_zone_top()
	for y in range(y_from, grid.Y_MAX + 1):
		var layer: int = (y - 1) / _Constants.ROWS_PER_LAYER + 1
		for x in range(grid.X_MIN, grid.X_MAX + 1):
			var pos: Vector2i = Vector2i(x, y)
			var cell: GridWorld.Cell = grid._cells.get(pos)
			if cell != null and cell.is_wall:
				continue  # The central wall and borders survive the flood.
			# Preserve existing gold deposits so unmined ore survives the flood.
			if cell != null and (cell.type == GridWorld.CellType.ORE or cell.type == GridWorld.CellType.FRESH_ORE) and cell.coin_remaining > 0:
				_lava_original_cells[pos] = cell
			# Level 99 gate: lava is indestructible and undiggable.
			grid._cells[pos] = GridWorld.Cell.new(GridWorld.CellType.LAVA, layer, 99, 9999, 0)
			if grid._astar.is_in_boundsv(pos):
				grid._astar.set_point_solid(pos, true)
			grid._cell_flash[pos] = 0.6
	_kill_units_in_lava()
	_destroy_lanterns_below(y_from)
	_lava_active_left = _Constants.LAVA_DURATION
	_lava_sweep_timer = _Constants.LAVA_SWEEP_INTERVAL
	DebugLog.log_command("GridEvents", "lava_risen", "layers=%d" % layers)
	AudioManager.play("rumble", Vector2.INF, 0.0)
	_shake(8.0)
	grid.lava_risen.emit(layers)
	grid.queue_redraw()


func _recede_lava() -> void:
	var y_from: int = _lava_zone_top()
	for y in range(y_from, grid.Y_MAX + 1):
		var layer: int = (y - 1) / _Constants.ROWS_PER_LAYER + 1
		var ml_req: int = grid._map_gen._layer_miner_level(layer)
		# Fresh ore only appears on the deepest two layers; higher flooded
		# layers reset to empty magma rock.
		var can_spawn_gold: bool = layer >= 6
		for x in range(grid.X_MIN, grid.X_MAX + 1):
			var pos: Vector2i = Vector2i(x, y)
			var cell: GridWorld.Cell = grid._cells.get(pos)
			if cell == null or cell.type != GridWorld.CellType.LAVA:
				continue
			# If this tile held an unmined gold deposit before the flood,
			# restore it exactly as it was.
			var backup: GridWorld.Cell = _lava_original_cells.get(pos)
			if backup != null and backup.coin_remaining > 0:
				grid._cells[pos] = backup
				if grid._astar.is_in_boundsv(pos):
					grid._astar.set_point_solid(pos, true)
				grid._cell_flash[pos] = 0.6
				continue
			if can_spawn_gold and randf() < _Constants.MAGMA_ORE_CHANCE:
				var coin: int = randi_range(_Constants.MAGMA_ORE_MIN, _Constants.MAGMA_ORE_MAX)
				grid._cells[pos] = GridWorld.Cell.new(GridWorld.CellType.FRESH_ORE, layer, ml_req, _Constants.MAGMA_ROCK_HP, coin)
			else:
				grid._cells[pos] = GridWorld.Cell.new(GridWorld.CellType.MAGMA_ROCK, layer, ml_req, _Constants.MAGMA_ROCK_HP, 0)
			# Magma rock blocks like dirt until dug out.
			if grid._astar.is_in_boundsv(pos):
				grid._astar.set_point_solid(pos, true)
			grid._cell_flash[pos] = 0.6
	_lava_original_cells.clear()
	_lava_layers = 0
	_lava_active_left = 0.0
	DebugLog.log_command("GridEvents", "lava_receded", "")
	grid.lava_receded.emit()
	_lava_next_at = _clock + randf_range(_Constants.LAVA_MIN_INTERVAL, _Constants.LAVA_MAX_INTERVAL)
	grid.queue_redraw()


## Instantly kills every unit standing in a lava cell (no cargo drop — the
## coin melts). Runs on the rise and periodically while lava is up, catching
## stragglers whose in-flight paths carried them into the zone.
func _kill_units_in_lava() -> void:
	for unit in grid.get_tree().get_nodes_in_group("units"):
		if not unit.is_underground:
			continue
		var cell: GridWorld.Cell = grid._cells.get(grid.world_to_grid(unit.global_position))
		if cell != null and cell.type == GridWorld.CellType.LAVA:
			unit.die_in_lava()


## Lava destroys underground lanterns in the flooded rows instantly.
func _destroy_lanterns_below(y_from: int) -> void:
	for lantern in grid.get_tree().get_nodes_in_group("lanterns"):
		if not lantern.is_underground_lantern:
			continue
		if grid.world_to_grid(lantern.global_position).y >= y_from:
			lantern._destroy()


# ─── Cave-ins ───

func is_cave_in_rock(grid_pos: Vector2i) -> bool:
	var cell: GridWorld.Cell = grid._cells.get(grid_pos)
	return cell != null and cell.type == GridWorld.CellType.SOLID_ROCK


func _pick_cave_in_center() -> Vector2i:
	# Anywhere underground, clear of the central wall columns and borders.
	for _attempt in range(20):
		var x: int = randi_range(grid.X_MIN + 2, grid.X_MAX - 2)
		if absi(x) <= 2:
			continue
		return Vector2i(x, randi_range(2, grid.Y_MAX - 1))
	return Vector2i(-20, 10)


## Weather Alert (Revamp Phase 6+): seconds of heads-up before a random cave-in.
## Zero when neither team has researched the tech.
func _get_cavein_warning_time() -> float:
	var bonus: float = maxf(0.0, maxf(
		ResearchManager.get_stat_bonus(GameManager.Team.PLAYER, "weather_warning_bonus"),
		ResearchManager.get_stat_bonus(GameManager.Team.ENEMY, "weather_warning_bonus")))
	if bonus <= 0.0:
		return 0.0
	return _Constants.WEATHER_ALERT_CAVEIN_WARNING


## Start the cave-in warning phase: emit a signal and subtle audio, then the
## collapse triggers after WEATHER_ALERT_CAVEIN_WARNING seconds.
func _start_cavein_warning() -> void:
	if _cavein_warning_left > 0.0:
		return
	_cavein_warning_center = _pick_cave_in_center()
	_cavein_warning_left = _Constants.WEATHER_ALERT_CAVEIN_WARNING
	DebugLog.log_command("GridEvents", "cave_in_warning", "center=%s warning=%.0fs" % [str(_cavein_warning_center), _cavein_warning_left])
	AudioManager.play("rumble", Vector2.INF, -12.0)
	grid.cave_in_warning.emit(_cavein_warning_left, _cavein_warning_center)


func _trigger_cave_in(center: Vector2i) -> void:
	var half: int = _Constants.CAVEIN_AREA_SIZE / 2
	for dx in range(-half, half + 1):
		for dy in range(-half, half + 1):
			var pos: Vector2i = center + Vector2i(dx, dy)
			var cell: GridWorld.Cell = grid._cells.get(pos)
			if cell == null or cell.is_wall:
				continue
			if not _is_diggable_type(cell.type):
				continue
			_cave_in_cells[pos] = {
				"type": cell.type,
				"hp": cell.hp,
				"max_hp": cell.max_hp,
				"ml": cell.miner_level_required,
			}
			# Indestructible while the rock settles (level 99 gate + guard in
			# damage_cell); A* stays solid because hp > 0.
			cell.type = GridWorld.CellType.SOLID_ROCK
			cell.hp = 9999
			cell.max_hp = 9999
			cell.miner_level_required = 99
			grid._cell_flash[pos] = 0.6
	_cavein_restore_left = _Constants.CAVEIN_ROCK_DURATION

	# Units caught in the collapse take damage and are shoved to safety.
	for unit in grid.get_tree().get_nodes_in_group("units"):
		if not unit.is_underground:
			continue
		var upos: Vector2i = grid.world_to_grid(unit.global_position)
		if absi(upos.x - center.x) > half or absi(upos.y - center.y) > half:
			continue
		unit.take_damage(_Constants.CAVEIN_DAMAGE)
		if unit._state == Unit.State.DEAD:
			continue
		# Reinforced Pack (Revamp Phase 6): miners take the damage but brace
		# against the shove — no push/reposition.
		if unit.data.is_miner and ResearchManager.has_branch(unit.team, "reinforced_pack"):
			continue
		var escape: Vector2i = grid._path.nearest_walkable_cell(upos, 6)
		if grid._path.is_walkable(escape):
			unit._clear_target()
			unit._set_state(Unit.State.IDLE, "cave-in push")
			unit.global_position = grid.grid_to_world(escape)

	# Underground lanterns in the area are destroyed.
	for lantern in grid.get_tree().get_nodes_in_group("lanterns"):
		if not lantern.is_underground_lantern:
			continue
		var lpos: Vector2i = grid.world_to_grid(lantern.global_position)
		if absi(lpos.x - center.x) <= half and absi(lpos.y - center.y) <= half:
			lantern._destroy()

	DebugLog.log_command("GridEvents", "cave_in", "center=%s cells=%d" % [str(center), _cave_in_cells.size()])
	AudioManager.play("blast", grid.grid_to_world(center), -4.0)
	_shake(6.0)
	grid.cave_in_occurred.emit(center)
	_cavein_next_at = _clock + randf_range(_Constants.CAVEIN_MIN_INTERVAL, _Constants.CAVEIN_MAX_INTERVAL)
	grid.queue_redraw()


func _restore_cave_in() -> void:
	for pos in _cave_in_cells:
		var cell: GridWorld.Cell = grid._cells.get(pos)
		if cell == null or cell.type != GridWorld.CellType.SOLID_ROCK:
			continue
		var backup: Dictionary = _cave_in_cells[pos]
		cell.type = backup.type
		cell.hp = backup.hp
		cell.max_hp = backup.max_hp
		cell.miner_level_required = backup.ml
		grid._cell_flash[pos] = 0.3
	_cave_in_cells.clear()
	grid.queue_redraw()


# ─── Ore vein respawn ───

## Spawns up to ORE_RESPAWN_COUNT fresh veins on random DIRT cells in deep
## layers when the ore count is below the threshold (force skips the check —
## tests and debug hooks). Returns the number of veins spawned.
func respawn_ore(force: bool = false) -> int:
	if not force:
		var ore_count: int = 0
		for pos in grid._cells:
			var t: GridWorld.CellType = grid._cells[pos].type
			if t == GridWorld.CellType.ORE or t == GridWorld.CellType.FRESH_ORE:
				ore_count += 1
		if ore_count >= _Constants.ORE_RESPAWN_THRESHOLD:
			return 0
	var candidates: Array = []
	for pos in grid._cells:
		var cell: GridWorld.Cell = grid._cells[pos]
		if cell.type == GridWorld.CellType.DIRT and cell.layer >= _Constants.ORE_RESPAWN_MIN_LAYER:
			candidates.append(pos)
	candidates.shuffle()
	var spawned: int = 0
	for pos in candidates.slice(0, mini(_Constants.ORE_RESPAWN_COUNT, candidates.size())):
		var cell: GridWorld.Cell = grid._cells[pos]
		var coin_range: Vector2i = _Constants.LAYER_COIN_RANGES[cell.layer]
		var coin: int = randi_range(coin_range.x, coin_range.y)
		cell.type = GridWorld.CellType.ORE
		cell.coin_value = coin
		cell.coin_remaining = coin
		spawned += 1
	if spawned > 0:
		DebugLog.log_command("GridEvents", "ore_respawn", "spawned=%d" % spawned)
		grid.queue_redraw()
	return spawned


# ─── Shared ───

func _is_diggable_type(t: GridWorld.CellType) -> bool:
	return t == GridWorld.CellType.DIRT or t == GridWorld.CellType.ORE \
		or t == GridWorld.CellType.MAGMA_ROCK or t == GridWorld.CellType.FRESH_ORE


func _shake(strength: float) -> void:
	var pc: PlayerController = grid.get_node_or_null("/root/Main/PlayerController")
	if pc != null:
		pc.add_shake(strength)
