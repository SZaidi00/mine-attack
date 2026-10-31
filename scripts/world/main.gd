extends Node2D

@export var map_definition: MapDefinition = preload("res://scripts/resources/maps/default.tres")


func _enter_tree() -> void:
	if map_definition == null:
		return
	_place_layout_node("World/PlayerBuilding", map_definition.player_building_cell, false)
	_place_layout_node("World/EnemyBuilding", map_definition.enemy_building_cell, false)
	_place_layout_node("World/PlayerMineEntry", map_definition.player_mine_cell, true)
	_place_layout_node("World/EnemyMineEntry", map_definition.enemy_mine_cell, true)


func _place_layout_node(node_path: String, cell: Vector2i, centered: bool) -> void:
	var node := get_node(node_path) as Node2D
	var offset := Vector2(0.5, 0.5) if centered else Vector2.ZERO
	node.position = (Vector2(cell) + offset) * GridWorld.CELL_SIZE
