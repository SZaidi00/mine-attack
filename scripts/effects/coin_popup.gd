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
	position.y -= RISE_SPEED * delta
	_timer -= delta
	modulate.a = clampf(_timer / 0.3, 0.0, 1.0)
	if _timer <= 0.0:
		queue_free()
