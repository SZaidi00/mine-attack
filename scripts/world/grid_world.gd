class_name GridWorld
extends Node2D

signal cell_destroyed(grid_pos: Vector2i)
signal wall_hp_changed(current: int, maximum: int)
# Emitted by the Ore Sonar scan with the newly revealed ore cells (VFX hook).
signal cells_revealed(cells: Array)
# Revamp Phase 4 dynamic-terrain events (HUD banners, VFX hooks).
signal lava_warning_started(seconds: float)
signal lava_risen(layers: int)
signal lava_receded()
signal cave_in_occurred(center: Vector2i)

# Revamp Phase 4: LAVA is indestructible/impassable while the flood is up;
# MAGMA_ROCK is the diggable rock it leaves behind; FRESH_ORE is high-value
# ore spawned by the recede; SOLID_ROCK is temporary cave-in rubble.
enum CellType { EMPTY, SURFACE_GROUND, DIRT, ORE, WALL, LAVA, MAGMA_ROCK, FRESH_ORE, SOLID_ROCK }

class Cell:
	var type: CellType = CellType.EMPTY
	var hp: int = 0
	var max_hp: int = 0
	var layer: int = 0
	var miner_level_required: int = 1
	var coin_value: int = 0
	# Gold left in the tile: every mining swing extracts a share, destruction
	# pays out the remainder, so a tile always yields exactly coin_value total.
	var coin_remaining: int = 0
	var is_wall: bool = false
	# Instance id of the miner that reserved this cell (0 = unclaimed).
	var claimed_by: int = 0
	# Teams whose Ore Sonar scan has revealed this cell (team -> true).
	var sonar_revealed: Dictionary = {}

	func _init(t: CellType, l: int = 0, ml: int = 1, hp_val: int = 0, coin: int = 0, wall: bool = false):
		type = t
		layer = l
		miner_level_required = ml
		hp = hp_val
		max_hp = hp_val
		coin_value = coin
		coin_remaining = coin
		is_wall = wall

const _Constants = preload("res://scripts/autoload/constants.gd")

const _SKY_TEXTURE: Texture2D = preload("res://frost_mines_assets/backgrounds/surface_sky.png")
const _SURFACE_GROUND_TEXTURE: Texture2D = preload("res://frost_mines_assets/backgrounds/surface_ground.png")
const _UNDERGROUND_TEXTURE: Texture2D = preload("res://frost_mines_assets/backgrounds/underground_base.png")
const _WALL_TEXTURE: Texture2D = preload("res://frost_mines_assets/props/wall_segment.png")
# Revamp Phase 4 terrain left behind by lava events.
const _MAGMA_ROCK_TEXTURE: Texture2D = preload("res://frost_mines_assets/tiles/magma_rock.png")
const _FRESH_ORE_TEXTURE: Texture2D = preload("res://frost_mines_assets/tiles/fresh_ore.png")
# Fog of War decoration: drifting cloud puffs over fogged surface cells and
# mist puffs in the fogged underground (the flat fog color underneath still
# guarantees occlusion — these are the moving "cloud cover" on top).
const _FOG_SURFACE_TEXTURE: Texture2D = preload("res://frost_mines_assets/effects/fog_surface.png")
const _FOG_UNDERGROUND_TEXTURE: Texture2D = preload("res://frost_mines_assets/effects/fog_underground.png")
const _LAYER_TILES: Array[Texture2D] = [
	preload("res://frost_mines_assets/tiles/layer_1_tile.png"),
	preload("res://frost_mines_assets/tiles/layer_2_tile.png"),
	preload("res://frost_mines_assets/tiles/layer_3_tile.png"),
	preload("res://frost_mines_assets/tiles/layer_4_tile.png"),
	preload("res://frost_mines_assets/tiles/layer_5_tile.png"),
	preload("res://frost_mines_assets/tiles/layer_6_tile.png"),
	preload("res://frost_mines_assets/tiles/layer_7_tile.png")
]

const CELL_SIZE: int = _Constants.TILE_SIZE

# Map bounds in grid coordinates.
const X_MIN: int = _Constants.GRID_X_MIN
const X_MAX: int = _Constants.GRID_X_MAX
const Y_MIN: int = _Constants.GRID_Y_MIN
const Y_MAX: int = _Constants.GRID_Y_MAX

# Central wall is a single objective with shared HP (GDD: 2000 HP).
const WALL_HP_TOTAL: int = _Constants.WALL_HP

# Helper modules split grid responsibilities into smaller files.
const GridMapGeneration = preload("res://scripts/world/grid_map_generation.gd")
const GridPathfinding = preload("res://scripts/world/grid_pathfinding.gd")
const GridFogOfWar = preload("res://scripts/world/grid_fog_of_war.gd")
const GridDrawing = preload("res://scripts/world/grid_drawing.gd")
const GridMining = preload("res://scripts/world/grid_mining.gd")
const GridAmbience = preload("res://scripts/world/grid_ambience.gd")
const GridEvents = preload("res://scripts/world/grid_events.gd")

var _cells: Dictionary = {}  # Vector2i -> Cell
var _astar: AStarGrid2D = AStarGrid2D.new()
# Revamp Phase 3: cells sealed by placeable walls (the column beneath each
# segment), mapped to the owning team. Stored on GridWorld so both the
# pathfinding helper and wall lifecycle can read/write it in one place.
var _wall_sealed_cells: Dictionary = {}

# ─── Fog of War (Revamp Phase 1) ───
# Per-team vision: _vision_maps[team][x - X_MIN][y - Y_MIN] is true while the
# cell is inside any friendly vision source's radius; _memory_maps holds the
# GameManager.match_time when the cell was last visible (-1 = never seen).
# A remembered cell stays dimly visible for FOG_MEMORY_DURATION seconds, then
# fades back to full fog. Only the PLAYER team's fog is rendered; both teams
# get maps because combat and mining rules consult them symmetrically.
var _vision_maps: Dictionary = {}
var _memory_maps: Dictionary = {}
# Frozen silhouettes of enemy units that left the player's vision: instance id
# -> { pos, unit_name, expires }. Drawn with a "?" until the memory fades or
# the cell is seen again (then the real unit is simply visible).
var _unit_ghosts: Dictionary = {}
# Enemy unit ids inside the player's vision as of the last vision update;
# diffed frame-to-frame so a unit that slips into the fog leaves a ghost.
var _prev_visible_enemies: Dictionary = {}
# Debug/test hook: teams in this set see everything regardless of vision
# sources (is_visible_to / is_remembered_by short-circuit true and the fog
# overlay is skipped). Used by the test suite to keep fog-agnostic behavior
# tests readable; never set in gameplay.
var _reveal_all: Dictionary = {}

# Vision layer masks: whether a source lights the surface row, the
# underground, or both (lanterns, miners and dragons are layer-locked).
const VISION_LAYER_BOTH: int = 0
const VISION_LAYER_SURFACE: int = 1
const VISION_LAYER_UNDERGROUND: int = 2

var _wall_hp: int = WALL_HP_TOTAL
var _wall_max_hp: int = WALL_HP_TOTAL
var _central_wall_cells: Array[Vector2i] = []

# Backgrounds are padded this far beyond the map on every side so wide or
# tall windows (where the whole world fits in view) never show unpainted void.
const _BG_PAD: float = 3200.0

var _view_mode: PlayerController.ViewMode = PlayerController.ViewMode.SURFACE
var _cell_flash: Dictionary = {}  # Vector2i -> remaining flash time
# Drives the magma/crystal shimmer redraws on the deep layers (Phase 8).
var _shimmer_timer: float = 0.0
# Edge colors sampled from the background textures, used to fill the padded
# bands above the sky and below the deepest layer (tiling those textures
# vertically would visibly repeat the horizon/ground seam).
var _sky_top_color: Color = Color(0.02, 0.03, 0.06)
var _underground_bottom_color: Color = Color(0.02, 0.03, 0.06)

# Cohesive helper objects: each group of GridWorld responsibilities is
# delegated to a RefCounted helper that accesses grid state via `grid.`.
var _map_gen: GridMapGeneration
var _path: GridPathfinding
var _fog: GridFogOfWar
var _draw_helper: GridDrawing
var _mining: GridMining
var _ambience: GridAmbience
var _events: GridEvents


func _init() -> void:
	_map_gen = GridMapGeneration.new(self)
	_path = GridPathfinding.new(self)
	_fog = GridFogOfWar.new(self)
	_draw_helper = GridDrawing.new(self)
	_mining = GridMining.new(self)
	_ambience = GridAmbience.new(self)
	_events = GridEvents.new(self)


func _ready() -> void:
	_sky_top_color = _SKY_TEXTURE.get_image().get_pixel(0, 0)
	_underground_bottom_color = _UNDERGROUND_TEXTURE.get_image().get_pixel(0, _UNDERGROUND_TEXTURE.get_height() - 1)
	_map_gen._generate_map()
	_map_gen._init_astar()
	_fog._init_vision_maps()
	_connect_view_mode()
	_ambience._spawn_ambient_particles()
	_events.schedule_initial()
	queue_redraw()


func _process(delta: float) -> void:
	# Fog of War: recompute both teams' vision every frame (frozen once the
	# match ends, like the units). Redraw every frame so the fog edge tracks
	# moving units smoothly.
	if GameManager.game_active:
		_fog._update_vision(GameManager.Team.PLAYER)
		_fog._update_vision(GameManager.Team.ENEMY)
		_fog._prune_unit_ghosts()
		_events._process_events(delta)
		queue_redraw()
	var expired: Array[Vector2i] = []
	for pos in _cell_flash.keys():
		_cell_flash[pos] -= delta
		if _cell_flash[pos] <= 0:
			expired.append(pos)
	if not expired.is_empty():
		for pos in expired:
			_cell_flash.erase(pos)
		queue_redraw()
	# Deep-layer shimmer (magma flicker L5-6, crystal pulse L7) at ~8fps.
	_shimmer_timer += delta
	if _shimmer_timer >= 0.12:
		_shimmer_timer = 0.0
		queue_redraw()


func _connect_view_mode() -> void:
	var pc: PlayerController = get_node_or_null("/root/Main/PlayerController")
	if pc:
		if not pc.view_mode_changed.is_connected(_on_view_mode_changed):
			pc.view_mode_changed.connect(_on_view_mode_changed)
		_on_view_mode_changed(pc.get_current_view_mode())


func _on_view_mode_changed(mode: PlayerController.ViewMode) -> void:
	_view_mode = mode
	queue_redraw()


func _draw() -> void:
	# Both layers are always drawn so the player can see surface activity and the
	# underground mine at the same time.
	_draw_helper._draw_surface()
	_draw_helper._draw_underground()
	# Fog of War is drawn last so it darkens the terrain; units handle their
	# own fog visibility (enemy units hide, remembered ones leave a ghost).
	_fog._draw_fog()
	_fog._draw_unit_ghosts()


# ─── Public API wrappers ───

func get_cell(grid_pos: Vector2i) -> Cell:
	return _cells.get(grid_pos)


func is_solid(grid_pos: Vector2i) -> bool:
	var cell: Cell = _cells.get(grid_pos)
	return _map_gen._is_solid_cell(cell)


func has_cell(grid_pos: Vector2i) -> bool:
	return _cells.has(grid_pos)


func is_walkable(grid_pos: Vector2i) -> bool:
	return _path.is_walkable(grid_pos)


func world_to_grid(world_pos: Vector2) -> Vector2i:
	return Vector2i(floor(world_pos.x / CELL_SIZE), floor(world_pos.y / CELL_SIZE))


func grid_to_world(grid_pos: Vector2i, centered: bool = true) -> Vector2:
	if centered:
		return Vector2(grid_pos.x * CELL_SIZE + CELL_SIZE / 2.0, grid_pos.y * CELL_SIZE + CELL_SIZE / 2.0)
	return Vector2(grid_pos.x * CELL_SIZE, grid_pos.y * CELL_SIZE)


func is_wall(grid_pos: Vector2i) -> bool:
	var cell: Cell = _cells.get(grid_pos)
	return cell != null and cell.is_wall


func is_central_wall(grid_pos: Vector2i) -> bool:
	return _central_wall_cells.has(grid_pos)


func get_wall_cells() -> Array[Vector2i]:
	return _central_wall_cells.duplicate()


func get_wall_hp() -> int:
	return _wall_hp


func get_wall_max_hp() -> int:
	return _wall_max_hp


func get_wall_hp_ratio() -> float:
	if _wall_max_hp <= 0:
		return 0.0
	return float(_wall_hp) / float(_wall_max_hp)


func get_layer_at(grid_pos: Vector2i) -> int:
	var cell: Cell = _cells.get(grid_pos)
	if cell == null:
		return 0
	return cell.layer


func carve_shaft(x: int, y_from: int = 1, y_to: int = 6) -> void:
	_map_gen.carve_shaft(x, y_from, y_to)


func find_path(from_world: Vector2, to_world: Vector2, team: int = -1) -> PackedVector2Array:
	return _path.find_path(from_world, to_world, team)


func nearest_walkable_cell(to_cell: Vector2i, max_radius: int = 4) -> Vector2i:
	return _path.nearest_walkable_cell(to_cell, max_radius)


func cells_adjacent_to_rect(rect: Rect2i) -> Array[Vector2i]:
	return _path.cells_adjacent_to_rect(rect)


func seal_wall_cell(pos: Vector2i, team: GameManager.Team) -> void:
	_path.seal_wall_cell(pos, team)


func unseal_wall_cell(pos: Vector2i) -> void:
	_path.unseal_wall_cell(pos)


func claim_cell(grid_pos: Vector2i, unit_id: int) -> void:
	_mining.claim_cell(grid_pos, unit_id)


func release_cell(grid_pos: Vector2i, unit_id: int) -> void:
	_mining.release_cell(grid_pos, unit_id)


func is_cell_claimable(grid_pos: Vector2i, unit_id: int) -> bool:
	return _mining.is_cell_claimable(grid_pos, unit_id)


func damage_cell(grid_pos: Vector2i, damage: int, miner_level: int) -> int:
	return _mining.damage_cell(grid_pos, damage, miner_level)


func reveal_ore_in_radius(center: Vector2i, radius_cells: int, team: GameManager.Team) -> int:
	return _mining.reveal_ore_in_radius(center, radius_cells, team)


func is_ore_revealed(grid_pos: Vector2i, team: GameManager.Team) -> bool:
	return _mining.is_ore_revealed(grid_pos, team)


func count_accessible_unmined_tiles(side: int, miner_level: int) -> int:
	return _mining.count_accessible_unmined_tiles(side, miner_level)


func set_reveal_all(team: GameManager.Team, enabled: bool) -> void:
	_fog.set_reveal_all(team, enabled)


func is_visible_to(team: GameManager.Team, world_pos: Vector2) -> bool:
	return _fog.is_visible_to(team, world_pos)


func is_remembered_by(team: GameManager.Team, world_pos: Vector2) -> bool:
	return _fog.is_remembered_by(team, world_pos)


func fog_state_at(team: GameManager.Team, grid_pos: Vector2i) -> int:
	return _fog.fog_state_at(team, grid_pos)


func _get_vision_sources(team: GameManager.Team) -> Array:
	return _fog._get_vision_sources(team)


func _init_vision_maps() -> void:
	_fog._init_vision_maps()


# ─── Dynamic terrain & events (Revamp Phase 4) ───

## Test/debug hook: random lava/cave-in/ore-respawn scheduling on or off.
## Forced triggers below work either way.
func set_dynamic_events_enabled(enabled: bool) -> void:
	_events.events_enabled = enabled


func is_lava_warning() -> bool:
	return _events.is_lava_warning()


func is_lava_active() -> bool:
	return _events.is_lava_active()


func get_lava_warning_remaining() -> float:
	return _events.get_lava_warning_remaining()


func is_cave_in_rock(grid_pos: Vector2i) -> bool:
	return _events.is_cave_in_rock(grid_pos)


func force_lava_warning(layers: int = -1) -> void:
	_events._start_lava_warning(layers)


func force_lava_rise(layers: int = 1) -> void:
	_events._rise_lava(layers)


func force_lava_recede() -> void:
	_events._recede_lava()


func force_cave_in(center: Vector2i) -> void:
	_events._trigger_cave_in(center)


func force_ore_respawn() -> int:
	return _events.respawn_ore(true)
