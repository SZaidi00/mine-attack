class_name GridFogOfWar
extends RefCounted

var grid: GridWorld

func _init(g: GridWorld) -> void:
	grid = g


## Fog of War: both teams' maps start fully fogged (never seen).
func _init_vision_maps() -> void:
	for team in [GameManager.Team.PLAYER, GameManager.Team.ENEMY]:
		var vision_cols: Array = []
		var memory_cols: Array = []
		for x in range(grid.X_MIN, grid.X_MAX + 1):
			var vision_col: Array = []
			var memory_col: Array = []
			for y in range(grid.Y_MIN, grid.Y_MAX + 1):
				vision_col.append(false)
				memory_col.append(-1.0)
			vision_cols.append(vision_col)
			memory_cols.append(memory_col)
		grid._vision_maps[team] = vision_cols
		grid._memory_maps[team] = memory_cols


## Recomputes one team's vision from scratch: every currently visible cell is
## demoted to memory (timestamped now), then all vision sources re-reveal
## their circles. For the PLAYER team this also maintains the frozen enemy
## silhouettes (a unit that just left vision leaves a "?" ghost behind).
func _update_vision(team: GameManager.Team) -> void:
	var vision: Array = grid._vision_maps[team]
	var memory: Array = grid._memory_maps[team]
	var now: float = GameManager.match_time

	for ix in range(vision.size()):
		for iy in range(vision[ix].size()):
			if vision[ix][iy]:
				memory[ix][iy] = now
				vision[ix][iy] = false

	for source in _get_vision_sources(team):
		_reveal_circle(team, source[0], source[1], source[2])

	if team == GameManager.Team.PLAYER:
		# Ghost tracking: an enemy that was visible last frame but is not now
		# leaves a frozen silhouette at its current position. Units that died
		# in view are skipped — a corpse fades, it does not become a "?".
		var now_visible: Dictionary = {}
		for unit in grid.get_tree().get_nodes_in_group("enemy"):
			if unit._state == Unit.State.DEAD:
				continue
			var id: int = unit.get_instance_id()
			if _is_cell_visible(team, grid.world_to_grid(unit.global_position)):
				now_visible[id] = true
			elif grid._prev_visible_enemies.has(id):
				grid._unit_ghosts[id] = {
					"pos": unit.global_position,
					"unit_name": unit.data.unit_name,
					"expires": now + grid._Constants.FOG_MEMORY_DURATION,
				}
		grid._prev_visible_enemies = now_visible
		# A ghost whose cell is visible again is redundant — the real unit shows.
		for id in grid._unit_ghosts.keys():
			if _is_cell_visible(team, grid.world_to_grid(grid._unit_ghosts[id].pos)):
				grid._unit_ghosts.erase(id)


## Every vision source for a team as [center_cell, radius_cells, layer_mask]
## triples: living units (per-type radii), the team's building, and built
## lanterns. Sentry towers no longer provide vision — only lanterns light the
## fog. A raging snowstorm (Revamp Phase 5) halves unit and lantern radius;
## buildings keep their full radius.
func _get_vision_sources(team: GameManager.Team) -> Array:
	var sources: Array = []
	for unit in grid.get_tree().get_nodes_in_group("units"):
		if unit.team != team or unit._state == Unit.State.DEAD:
			continue
		var weather_mult: float = WeatherManager.get_unit_vision_multiplier(unit)
		var radius: int = maxi(1, roundi(unit.get_vision_radius() * weather_mult))
		if radius > 0:
			sources.append([grid.world_to_grid(unit.global_position), radius, unit.get_vision_layer()])
	for b in grid.get_tree().get_nodes_in_group("buildings"):
		if b.get("team") == team:
			sources.append([grid.world_to_grid(b.global_position), grid._Constants.VISION_BUILDING, GridWorld.VISION_LAYER_BOTH])
	for lantern in grid.get_tree().get_nodes_in_group("lanterns"):
		if lantern.team == team and lantern.is_built():
			var layer: int = GridWorld.VISION_LAYER_UNDERGROUND if lantern.is_underground_lantern else GridWorld.VISION_LAYER_SURFACE
			var weather_mult: float = WeatherManager.get_lantern_vision_multiplier(team)
			var radius_cells: int = lantern.vision_radius
			# Deep Fortress: underground lanterns reveal a larger area.
			if lantern.is_underground_lantern and ResearchManager.has_branch(team, "deep_fortress"):
				radius_cells += grid._Constants.DEEP_FORTRESS_LANTERN_VISION_BONUS
			sources.append([grid.world_to_grid(lantern.global_position), maxi(1, roundi(radius_cells * weather_mult)), layer])
	return sources


func _reveal_circle(team: GameManager.Team, center: Vector2i, radius: int, layer_mask: int = GridWorld.VISION_LAYER_BOTH) -> void:
	var vision: Array = grid._vision_maps[team]
	for dx in range(-radius, radius + 1):
		for dy in range(-radius, radius + 1):
			if dx * dx + dy * dy > radius * radius:
				continue
			var x: int = center.x + dx
			var y: int = center.y + dy
			if x < grid.X_MIN or x > grid.X_MAX or y < grid.Y_MIN or y > grid.Y_MAX:
				continue
			# Layer-locked sources (lanterns, miners, dragons) only light
			# their own layer: the surface row, or everything below it.
			if layer_mask == GridWorld.VISION_LAYER_SURFACE and y != grid.Y_MIN:
				continue
			if layer_mask == GridWorld.VISION_LAYER_UNDERGROUND and y <= grid.Y_MIN:
				continue
			vision[x - grid.X_MIN][y - grid.Y_MIN] = true


func _prune_unit_ghosts() -> void:
	var now: float = GameManager.match_time
	for id in grid._unit_ghosts.keys():
		if now >= grid._unit_ghosts[id].expires:
			grid._unit_ghosts.erase(id)


func _is_cell_visible(team: GameManager.Team, grid_pos: Vector2i) -> bool:
	if grid_pos.x < grid.X_MIN or grid_pos.x > grid.X_MAX or grid_pos.y < grid.Y_MIN or grid_pos.y > grid.Y_MAX:
		return false
	if grid._reveal_all.get(team, false):
		return true
	return grid._vision_maps[team][grid_pos.x - grid.X_MIN][grid_pos.y - grid.Y_MIN]


## Debug/test hook: let a team see the whole map (see _reveal_all).
func set_reveal_all(team: GameManager.Team, enabled: bool) -> void:
	grid._reveal_all[team] = enabled


## True while the cell at world_pos is inside the team's live vision.
func is_visible_to(team: GameManager.Team, world_pos: Vector2) -> bool:
	return _is_cell_visible(team, grid.world_to_grid(world_pos))


## True while the team can see the cell OR still remembers it (seen within
## FOG_MEMORY_DURATION seconds of game time).
func is_remembered_by(team: GameManager.Team, world_pos: Vector2) -> bool:
	var grid_pos: Vector2i = grid.world_to_grid(world_pos)
	if _is_cell_visible(team, grid_pos):
		return true
	if grid._reveal_all.get(team, false):
		return true
	if grid_pos.x < grid.X_MIN or grid_pos.x > grid.X_MAX or grid_pos.y < grid.Y_MIN or grid_pos.y > grid.Y_MAX:
		return false
	var last_seen: float = grid._memory_maps[team][grid_pos.x - grid.X_MIN][grid_pos.y - grid.Y_MIN]
	if last_seen < 0.0:
		return false
	# Elapsed can go negative when match_time resets (Play Again, test
	# harnesses) — a memory from "the future" is stale, not fresh.
	var elapsed: float = GameManager.match_time - last_seen
	return elapsed >= 0.0 and elapsed < grid._Constants.FOG_MEMORY_DURATION


## 0 = fog (never seen / memory expired), 1 = remembered, 2 = visible.
## Diagnostic helper for the debug overlay and the test suite.
func fog_state_at(team: GameManager.Team, grid_pos: Vector2i) -> int:
	if _is_cell_visible(team, grid_pos):
		return 2
	return 1 if is_remembered_by(team, grid.grid_to_world(grid_pos)) else 0


## Fog of War overlay from the player's perspective: revealed cells draw
## nothing, remembered cells are darkened, never-seen cells are pitch black.
## Cells near a revealed cell get a softened edge (2-cell gradient). Full-fog
## areas get drifting decoration on top: cloud puffs on the surface, mist
## puffs underground.
func _draw_fog() -> void:
	var team: GameManager.Team = GameManager.Team.PLAYER
	if grid._reveal_all.get(team, false):
		return
	var vision: Array = grid._vision_maps[team]
	var now: float = GameManager.match_time
	var fog_color: Color = grid._Constants.FOG_COLOR
	for ix in range(vision.size()):
		for iy in range(vision[ix].size()):
			if vision[ix][iy]:
				continue
			var last_seen: float = grid._memory_maps[team][ix][iy]
			var elapsed: float = now - last_seen
			var remembered: bool = last_seen >= 0.0 and elapsed >= 0.0 and elapsed < grid._Constants.FOG_MEMORY_DURATION
			var alpha: float = grid._Constants.FOG_MEMORY_ALPHA if remembered else 1.0
			alpha *= _fog_edge_factor(ix, iy)
			var rect: Rect2 = Rect2((ix + grid.X_MIN) * grid.CELL_SIZE, (iy + grid.Y_MIN) * grid.CELL_SIZE, grid.CELL_SIZE, grid.CELL_SIZE)
			grid.draw_rect(rect, Color(fog_color, alpha), true)
			if not remembered:
				_draw_fog_puff(ix, iy, rect)


## Drifting cloud/mist sprite for a full-fog cell. The puff wanders on a slow
## per-cell phase so the fog bank reads as moving weather, not a static
## texture grid. Underground puffs are sparser and fainter (cave mist).
func _draw_fog_puff(ix: int, iy: int, rect: Rect2) -> void:
	var cell: Vector2i = Vector2i(ix + grid.X_MIN, iy + grid.Y_MIN)
	var phase: float = float(hash(cell) % 1000) / 1000.0 * TAU
	var t: float = Time.get_ticks_msec() / 1000.0
	if iy == 0:
		# Surface cloud cover: wide, slow-drifting puffs hanging over the row.
		var drift: Vector2 = Vector2(sin(t * 0.22 + phase) * 14.0, cos(t * 0.16 + phase * 1.7) * 6.0)
		var size: float = grid.CELL_SIZE * 2.6
		var center: Vector2 = rect.get_center() + drift
		grid.draw_texture_rect(grid._FOG_SURFACE_TEXTURE, Rect2(center - Vector2(size, size) / 2.0, Vector2(size, size)), false, Color(0.6, 0.66, 0.78, 0.5))
	elif hash(cell) % 3 == 0:
		# Cave mist: only every third cell, subtler and slower.
		var drift: Vector2 = Vector2(sin(t * 0.12 + phase) * 8.0, cos(t * 0.1 + phase) * 4.0)
		var size: float = grid.CELL_SIZE * 2.0
		var center: Vector2 = rect.get_center() + drift
		grid.draw_texture_rect(grid._FOG_UNDERGROUND_TEXTURE, Rect2(center - Vector2(size, size) / 2.0, Vector2(size, size)), false, Color(0.5, 0.55, 0.65, 0.25))


## Soft fog edge: cells within 2 cells of live vision fade toward clear.
func _fog_edge_factor(ix: int, iy: int) -> float:
	var vision: Array = grid._vision_maps[GameManager.Team.PLAYER]
	for r in range(1, 3):
		for dx in range(-r, r + 1):
			for dy in range(-r, r + 1):
				if maxi(absi(dx), absi(dy)) != r:
					continue
				var nx: int = ix + dx
				var ny: int = iy + dy
				if nx < 0 or nx >= vision.size() or ny < 0 or ny >= vision[nx].size():
					continue
				if vision[nx][ny]:
					return 0.45 if r == 1 else 0.75
	return 1.0


## Frozen silhouettes of enemy units that left the player's vision: a dark
## body at the last known position with a "?" overhead until the memory fades.
func _draw_unit_ghosts() -> void:
	var font: Font = ThemeDB.fallback_font
	for id in grid._unit_ghosts:
		var pos: Vector2 = grid._unit_ghosts[id].pos
		grid.draw_circle(pos + Vector2(0, -9), 9.0, Color(0.16, 0.2, 0.28, 0.85))
		grid.draw_circle(pos + Vector2(0, -9), 9.0, Color(0.5, 0.58, 0.7, 0.5), false, 1.0)
		grid.draw_string(font, pos + Vector2(0, -22), "?", HORIZONTAL_ALIGNMENT_CENTER, 16, 14, Color(0.92, 0.94, 1.0, 0.9))
