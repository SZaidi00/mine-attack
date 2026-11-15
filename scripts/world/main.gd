extends Node2D

const DEFAULT_MAP: MapDefinition = preload("res://scripts/resources/maps/default.tres")
const LEGACY_MAP: MapDefinition = preload("res://scripts/resources/maps/legacy.tres")

# The authored wide board; a derived scene may override the export, and the
# "wide" request keeps it. Only an explicit "legacy" launch intent swaps in
# the main-style 81x1 resource.
@export var map_definition: MapDefinition = preload("res://scripts/resources/maps/default.tres")


func _enter_tree() -> void:
	# Play Mode picks the world profile before anything initializes: the main
	# menu / capture driver set GameManager.world_profile_request before the
	# scene loaded. The profile must be applied here — before any child
	# _ready — because grid generation, fog maps, A*, and camera bookmarks all
	# read the GridWorld bounds statics.
	if GameManager.world_profile_request == "legacy":
		map_definition = LEGACY_MAP
	if map_definition == null:
		map_definition = DEFAULT_MAP
	GridWorld.apply_world_profile(map_definition)
	var camera := get_node_or_null("Camera2D") as Camera2D
	if camera != null:
		camera.position = map_definition.camera_start
	# Buildings keep their cell-corner origin; mine entries honor the profile
	# (cell-centered on the surface band for wide, corner-origin row-0 cells
	# for the legacy main layout).
	_place_layout_node("World/PlayerBuilding", map_definition.player_building_cell, false)
	_place_layout_node("World/EnemyBuilding", map_definition.enemy_building_cell, false)
	var mines_centered: bool = map_definition.mine_entries_centered
	_place_layout_node("World/PlayerMineEntry", map_definition.player_mine_cell, mines_centered)
	_place_layout_node("World/EnemyMineEntry", map_definition.enemy_mine_cell, mines_centered)


func _place_layout_node(node_path: String, cell: Vector2i, centered: bool) -> void:
	var node := get_node(node_path) as Node2D
	var offset := Vector2(0.5, 0.5) if centered else Vector2.ZERO
	node.position = (Vector2(cell) + offset) * GridWorld.CELL_SIZE
