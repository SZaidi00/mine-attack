extends Node2D

const _MINE_ENTRY_TEXTURE: Texture2D = preload("res://frost_mines_assets/props/mine_entry.png")
const _LADDER_SCENE: PackedScene = preload("res://scenes/ladder.tscn")

signal coin_deposited(team: GameManager.Team, amount: int)

@export var team: GameManager.Team = GameManager.Team.PLAYER
@export var underground_spawn: NodePath

var _underground_position: Vector2
var _ladder: Node2D = null


func _ready() -> void:
	add_to_group("mine_entries")
	_underground_position = global_position + Vector2(0, 5 * GridWorld.CELL_SIZE)
	queue_redraw()
	if underground_spawn:
		var node = get_node_or_null(underground_spawn)
		if node:
			_underground_position = node.global_position
	_spawn_ladder()
	_connect_view_mode()


func _connect_view_mode() -> void:
	var pc: PlayerController = get_node_or_null("/root/Main/PlayerController")
	if pc:
		if not pc.view_mode_changed.is_connected(_on_view_mode_changed):
			pc.view_mode_changed.connect(_on_view_mode_changed)
		_on_view_mode_changed(pc.get_current_view_mode())


func _on_view_mode_changed(mode: PlayerController.ViewMode) -> void:
	# Surface and underground are shown simultaneously; keep the entry visible.
	visible = true


func _spawn_ladder() -> void:
	_ladder = _LADDER_SCENE.instantiate()
	_ladder.top_position = global_position
	_ladder.bottom_position = _underground_position
	# Add the ladder to the dedicated Ladders container (or the World node as a
	# fallback) so it remains visible in both surface and underground views.
	var container: Node = get_node_or_null("/root/Main/World/Ladders")
	if container:
		container.add_child(_ladder)
	else:
		var world: Node = get_node_or_null("/root/Main/World")
		if world:
			world.add_child(_ladder)
		else:
			add_child(_ladder)


func _refresh_unit_visibility(unit: Node2D) -> void:
	var pc: PlayerController = get_node_or_null("/root/Main/PlayerController")
	if pc == null or not unit.has_method("_on_view_mode_changed"):
		return
	unit.call("_on_view_mode_changed", pc.get_current_view_mode())


func get_underground_position() -> Vector2:
	return _underground_position


func get_surface_position() -> Vector2:
	return global_position


func get_ladder_top() -> Vector2:
	return _ladder.get_top_position() if _ladder != null else global_position


func get_ladder_bottom() -> Vector2:
	return _ladder.get_bottom_position() if _ladder != null else _underground_position


## Legacy fallback: deposits cargo at the shaft. The main economy loop
## (Phase 3.1) deposits at the team building after a visible surface walk —
## see unit.deposit_coin() and building.deposit(). Kept for any direct caller
## that needs a quick at-shaft cash-in.
func deposit(unit: Node2D) -> void:
	if unit == null:
		DebugLog.log_reject("MineEntry %d" % get_instance_id(), "deposit", "null unit")
		return
	var data = unit.get("data")
	if data == null or not data.is_miner:
		return
	var carried: int = unit.get("carried_coin")
	if carried > 0:
		DebugLog.log_command("MineEntry %d" % get_instance_id(), "deposit", "team=%s amount=%d" % ["PLAYER" if team == GameManager.Team.PLAYER else "ENEMY", carried])
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
		DebugLog.log_reject("MineEntry %d" % get_instance_id(), "enter_mine", "null unit")
		return
	DebugLog.log_command("MineEntry %d" % get_instance_id(), "enter_mine", "unit=%d" % unit.get_instance_id())
	unit.global_position = _underground_position
	unit.set("is_underground", true)
	_refresh_unit_visibility(unit)


func exit_mine(unit: Node2D) -> void:
	if unit == null:
		DebugLog.log_reject("MineEntry %d" % get_instance_id(), "exit_mine", "null unit")
		return
	DebugLog.log_command("MineEntry %d" % get_instance_id(), "exit_mine", "unit=%d" % unit.get_instance_id())
	unit.global_position = global_position
	unit.set("is_underground", false)
	_refresh_unit_visibility(unit)


## Ladder-based entry/exit. These are the preferred paths for the auto-mining
## loop; the teleport methods above are kept as fallback for direct commands.
func enter_mine_climb(unit: Node2D) -> void:
	if unit == null:
		return
	unit.global_position = _underground_position
	unit.set("is_underground", true)
	_refresh_unit_visibility(unit)


func exit_mine_climb(unit: Node2D) -> void:
	if unit == null:
		return
	unit.global_position = global_position
	unit.set("is_underground", false)
	_refresh_unit_visibility(unit)


func _draw() -> void:
	var sprite_size: Vector2 = _MINE_ENTRY_TEXTURE.get_size()
	draw_texture(_MINE_ENTRY_TEXTURE, Vector2(-sprite_size.x / 2.0, -sprite_size.y))
