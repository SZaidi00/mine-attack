class_name MapDefinition
extends Resource

# World profile: the live GridWorld bounds this map describes. The wide
# defaults match Constants (the 3D board); scripts/resources/maps/legacy.tres
# carries the main-branch 81x1 profile for play_mode="2d". main.gd applies
# the profile via GridWorld.apply_world_profile() before child setup.
@export var grid_x_min: int = -50
@export var grid_x_max: int = 50
@export var surface_rows: int = 10
# Mine entries are cell-centered on the surface band (3D, mines at y=-5) when
# true; corner-origin on row 0 (the legacy main layout) when false.
@export var mine_entries_centered: bool = true
# Authored starting bookmark for the player Camera2D.
@export var camera_start: Vector2 = Vector2(0, -128)
@export var player_building_cell: Vector2i = Vector2i(-25, -2)
@export var enemy_building_cell: Vector2i = Vector2i(25, -2)
@export var player_mine_cell: Vector2i = Vector2i(-15, -5)
@export var enemy_mine_cell: Vector2i = Vector2i(15, -5)
@export var surface_regions: Array[Dictionary] = []
@export var surface_roads: Array[Rect2i] = []


func region_at(cell: Vector2i) -> Dictionary:
	for region in surface_regions:
		var rect: Rect2i = region.get("rect", Rect2i())
		if rect.has_point(cell):
			return region
	return {}


func is_road(cell: Vector2i) -> bool:
	for rect in surface_roads:
		if rect.has_point(cell):
			return true
	return false
