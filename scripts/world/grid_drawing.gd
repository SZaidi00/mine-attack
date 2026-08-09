class_name GridDrawing
extends RefCounted

var grid: GridWorld

func _init(g: GridWorld) -> void:
	grid = g


func _draw_surface() -> void:
	var world_left: float = (grid.X_MIN - 1) * grid.CELL_SIZE - grid._BG_PAD
	var world_right: float = (grid.X_MAX + 2) * grid.CELL_SIZE + grid._BG_PAD
	var world_width: float = world_right - world_left

	# Sky background, plus a solid band above it in its top-edge color so tall
	# windows never show void (tiling it vertically would repeat the horizon).
	var sky_height: float = grid._SKY_TEXTURE.get_height()
	grid.draw_texture_rect(grid._SKY_TEXTURE, Rect2(world_left, -sky_height, world_width, sky_height), true)
	grid.draw_rect(Rect2(world_left, -grid._BG_PAD, world_width, grid._BG_PAD - sky_height), grid._sky_top_color, true)

	# Surface ground background.
	var ground_height: float = grid._SURFACE_GROUND_TEXTURE.get_height()
	grid.draw_texture_rect(grid._SURFACE_GROUND_TEXTURE, Rect2(world_left, 0, world_width, ground_height), true)

	# Surface row only.
	for pos in grid._cells.keys():
		if pos.y != 0:
			continue
		var cell: GridWorld.Cell = grid._cells[pos]
		var rect: Rect2 = Rect2(pos.x * grid.CELL_SIZE, pos.y * grid.CELL_SIZE, grid.CELL_SIZE, grid.CELL_SIZE)
		if cell.type == GridWorld.CellType.SURFACE_GROUND:
			grid.draw_rect(rect, GameManager.COLOR_ICE, true)
			grid.draw_rect(rect, GameManager.COLOR_STEEL, false, 1.0)


func _draw_underground() -> void:
	var world_left: float = (grid.X_MIN - 1) * grid.CELL_SIZE - grid._BG_PAD
	var world_right: float = (grid.X_MAX + 2) * grid.CELL_SIZE + grid._BG_PAD
	var world_width: float = world_right - world_left

	# Surface ceiling.
	var ground_height: float = grid._SURFACE_GROUND_TEXTURE.get_height()
	grid.draw_texture_rect(grid._SURFACE_GROUND_TEXTURE, Rect2(world_left, 0, world_width, ground_height), true)

	# Underground background, plus a solid band below the deepest layer in its
	# bottom-edge color so tall windows never show void.
	var underground_y: float = grid.CELL_SIZE
	var underground_height: float = grid.Y_MAX * grid.CELL_SIZE
	grid.draw_texture_rect(grid._UNDERGROUND_TEXTURE, Rect2(world_left, underground_y, world_width, underground_height), true)
	var underground_bottom: float = underground_y + underground_height
	grid.draw_rect(Rect2(world_left, underground_bottom, world_width, grid._BG_PAD), grid._underground_bottom_color, true)

	for pos in grid._cells.keys():
		if pos.y < 1:
			continue
		var cell: GridWorld.Cell = grid._cells[pos]
		var rect: Rect2 = Rect2(pos.x * grid.CELL_SIZE, pos.y * grid.CELL_SIZE, grid.CELL_SIZE, grid.CELL_SIZE)
		match cell.type:
			GridWorld.CellType.SURFACE_GROUND:
				grid.draw_rect(rect, GameManager.COLOR_ICE, true)
				grid.draw_rect(rect, GameManager.COLOR_STEEL, false, 1.0)
			GridWorld.CellType.DIRT:
				var dirt_texture: Texture2D = _layer_tile(cell.layer)
				if dirt_texture != null:
					grid.draw_texture_rect(dirt_texture, rect, false)
				else:
					grid.draw_rect(rect, _dirt_color(cell.layer), true)
			GridWorld.CellType.ORE:
				var ore_texture: Texture2D = _layer_tile(cell.layer)
				if ore_texture != null:
					grid.draw_texture_rect(ore_texture, rect, false)
				else:
					grid.draw_rect(rect, _dirt_color(cell.layer), true)
				# Ore nugget.
				var inner: Rect2 = rect.grow(-8)
				grid.draw_rect(inner, GameManager.COLOR_RUST, true)
			GridWorld.CellType.WALL:
				grid.draw_texture_rect(grid._WALL_TEXTURE, rect, true)
				grid.draw_rect(rect, GameManager.COLOR_SHADOW, false, 2.0)

		# Mining feedback: flash, dust puffs, and a small HP bar for partially
		# damaged cells so active mining is readable at a glance.
		if pos in grid._cell_flash:
			var flash_alpha: float = clampf(grid._cell_flash[pos] / 0.2, 0.0, 1.0)
			grid.draw_rect(rect, Color(1.0, 1.0, 1.0, flash_alpha * 0.35), true)
			_draw_dust_puffs(rect, flash_alpha)
		if cell.hp > 0 and cell.hp < cell.max_hp:
			_draw_cell_hp_bar(rect, float(cell.hp) / float(cell.max_hp))

		# Deep-layer ambience: magma flicker on layers 5-6, crystal pulse on 7.
		if cell.layer >= 5 and (cell.type == GridWorld.CellType.DIRT or cell.type == GridWorld.CellType.ORE):
			var wave: float = 0.5 + 0.5 * sin(Time.get_ticks_msec() / 350.0 + float(hash(pos) % 100))
			if cell.layer >= 7:
				grid.draw_rect(rect, Color(0.4, 0.9, 1.0, 0.05 + 0.08 * wave), true)
			else:
				grid.draw_rect(rect, Color(1.0, 0.45, 0.15, 0.04 + 0.07 * wave), true)

		# Ore Sonar glimmer: pulsing gold marker on ore revealed to the player
		# (redrawn at the shimmer cadence, so the pulse animates for free).
		if cell.type == GridWorld.CellType.ORE and cell.sonar_revealed.get(GameManager.Team.PLAYER, false):
			var pulse: float = 0.5 + 0.5 * sin(Time.get_ticks_msec() / 300.0 + float(hash(pos) % 100))
			grid.draw_rect(rect, Color(1.0, 0.85, 0.3, 0.10 + 0.10 * pulse), true)
			grid.draw_rect(rect, Color(1.0, 0.85, 0.3, 0.35 + 0.35 * pulse), false, 2.0)

	# Dust burst for cells destroyed since the last redraw (already erased
	# from _cells, so the main loop above skips them).
	for pos in grid._cell_flash.keys():
		if pos.y < 1 or grid._cells.has(pos):
			continue
		var burst_rect: Rect2 = Rect2(pos.x * grid.CELL_SIZE, pos.y * grid.CELL_SIZE, grid.CELL_SIZE, grid.CELL_SIZE)
		var burst_alpha: float = clampf(grid._cell_flash[pos] / 0.2, 0.0, 1.0)
		_draw_dust_puffs(burst_rect, burst_alpha)

	# Central wall HP bar (only once the wall has taken damage).
	if grid._wall_hp > 0 and grid._wall_hp < grid._wall_max_hp:
		var bar_w: float = 200
		var bar_h: float = 12
		var bar_x: float = -bar_w / 2.0
		var bar_y: float = 16
		grid.draw_rect(Rect2(bar_x, bar_y, bar_w, bar_h), Color.BLACK, true)
		var wall_pct: float = grid.get_wall_hp_ratio()
		grid.draw_rect(Rect2(bar_x, bar_y, bar_w * wall_pct, bar_h), Color.ORANGE_RED, true)
		grid.draw_rect(Rect2(bar_x, bar_y, bar_w, bar_h), Color.WHITE, false, 1.0)


func _draw_dust_puffs(rect: Rect2, alpha: float) -> void:
	var center: Vector2 = rect.get_center()
	var dust_color: Color = Color(0.75, 0.7, 0.6, alpha * 0.7)
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(center)
	for i in range(5):
		var angle: float = rng.randf() * TAU
		var dist: float = 4.0 + rng.randf() * 8.0
		var radius: float = 2.0 + rng.randf() * 3.0
		grid.draw_circle(center + Vector2(cos(angle), sin(angle)) * dist, radius, dust_color)


func _draw_cell_hp_bar(rect: Rect2, ratio: float) -> void:
	var bar_w: float = rect.size.x - 6
	var bar_h: float = 4
	var bar_pos: Vector2 = Vector2(rect.position.x + 3, rect.position.y + 3)
	grid.draw_rect(Rect2(bar_pos, Vector2(bar_w, bar_h)), Color(0, 0, 0, 0.7), true)
	if ratio > 0:
		var fill_color: Color = Color.GREEN if ratio >= 0.5 else Color.ORANGE
		grid.draw_rect(Rect2(bar_pos, Vector2(bar_w * ratio, bar_h)), fill_color, true)


func _dirt_color(layer: int) -> Color:
	if layer <= 2:
		return GameManager.COLOR_DIRT_1
	if layer <= 4:
		return GameManager.COLOR_DIRT_2
	return GameManager.COLOR_DIRT_3


func _layer_tile(layer: int) -> Texture2D:
	var idx: int = clampi(layer - 1, 0, grid._LAYER_TILES.size() - 1)
	return grid._LAYER_TILES[idx]
