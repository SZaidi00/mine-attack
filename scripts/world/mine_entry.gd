extends Node2D

const _MINE_ENTRY_TEXTURE: Texture2D = preload("res://frost_mines_assets/props/mine_entry.png")

signal coin_deposited(team: GameManager.Team, amount: int)

@export var team: GameManager.Team = GameManager.Team.PLAYER
@export var underground_spawn: NodePath

var _underground_position: Vector2


func _ready() -> void:
	add_to_group("mine_entries")
	_underground_position = global_position + Vector2(0, 5 * GridWorld.CELL_SIZE)
	queue_redraw()
	if underground_spawn:
		var node = get_node_or_null(underground_spawn)
		if node:
			_underground_position = node.global_position


func get_underground_position() -> Vector2:
	return _underground_position


func get_surface_position() -> Vector2:
	return global_position


func deposit(unit: Node2D) -> void:
	if unit == null:
		return
	var data = unit.get("data")
	if data == null or not data.is_miner:
		return
	var carried: int = unit.get("carried_coin")
	if carried > 0:
		EconomyManager.add_coin(team, carried)
		EconomyManager.mine_coin(team, carried)
		coin_deposited.emit(team, carried)
		unit.set("carried_coin", 0)
		_spawn_coin_popup(carried)


func _spawn_coin_popup(amount: int) -> void:
	var popup: CoinPopup = preload("res://scenes/effects/coin_popup.tscn").instantiate()
	popup.setup(amount)
	popup.global_position = global_position + Vector2(0, -30)
	get_tree().current_scene.add_child(popup)


func enter_mine(unit: Node2D) -> void:
	if unit == null:
		return
	unit.global_position = _underground_position
	unit.set("is_underground", true)


func exit_mine(unit: Node2D) -> void:
	if unit == null:
		return
	unit.global_position = global_position
	unit.set("is_underground", false)


func _draw() -> void:
	var sprite_size: Vector2 = _MINE_ENTRY_TEXTURE.get_size()
	draw_texture(_MINE_ENTRY_TEXTURE, Vector2(-sprite_size.x / 2.0, -sprite_size.y))
