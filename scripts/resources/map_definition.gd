class_name MapDefinition
extends Resource

@export var player_building_cell: Vector2i = Vector2i(-40, 0)
@export var enemy_building_cell: Vector2i = Vector2i(40, 0)
@export var player_mine_cell: Vector2i = Vector2i(-20, -5)
@export var enemy_mine_cell: Vector2i = Vector2i(20, -5)
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
