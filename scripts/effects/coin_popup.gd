class_name CoinPopup
extends Label

const _COIN_SPARKLE: Texture2D = preload("res://frost_mines_assets/effects/coin_sparkle.png")

const RISE_SPEED: float = 30.0
const LIFETIME: float = 1.2

var _timer: float = LIFETIME


func _ready() -> void:
	horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	modulate = Color.GOLD
	_add_sparkle_icon()


func setup(amount: int) -> void:
	text = "+" + str(amount)


func _add_sparkle_icon() -> void:
	var icon: TextureRect = TextureRect.new()
	icon.texture = _COIN_SPARKLE
	icon.custom_minimum_size = Vector2(12, 12)
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.expand_mode = TextureRect.EXPAND_FIT_HEIGHT
	icon.position = Vector2(-14, 4)
	icon.size = Vector2(12, 12)
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(icon)


func _process(delta: float) -> void:
	# Fog of War: a popup at a position the player cannot see must not leak
	# enemy activity (e.g. deposits at the enemy base).
	var grid: Node = get_node_or_null("/root/Main/World/GridWorld")
	if grid != null:
		visible = grid.is_visible_to(GameManager.Team.PLAYER, global_position)
	position.y -= RISE_SPEED * delta
	_timer -= delta
	modulate.a = clampf(_timer / 0.3, 0.0, 1.0)
	if _timer <= 0.0:
		queue_free()
