class_name CoinPickup
extends Node2D

## Dropped cargo from a killed enemy miner. Any miner that touches it collects
## the coin into their carried cargo (up to capacity).

const _COIN_TEXTURE: Texture2D = preload("res://frost_mines_assets/effects/coin_sparkle.png")
const LIFETIME: float = 30.0
const PICKUP_RADIUS: float = 14.0

var coin_value: int = 0

var _timer: float = LIFETIME


func _ready() -> void:
	_add_pickup_area()
	queue_redraw()


func _process(delta: float) -> void:
	_timer -= delta
	if _timer <= 0.0:
		queue_free()


func _add_pickup_area() -> void:
	var area: Area2D = Area2D.new()
	area.name = "PickupArea"
	# Make the pickup detectable by unit hover areas, but do not block movement.
	area.collision_layer = 0
	area.collision_mask = 1  # Default physics layer where unit hover areas live.
	area.monitorable = true
	area.monitoring = true
	var shape: CollisionShape2D = CollisionShape2D.new()
	var circle: CircleShape2D = CircleShape2D.new()
	circle.radius = PICKUP_RADIUS
	shape.shape = circle
	area.add_child(shape)
	area.area_entered.connect(_on_area_entered)
	add_child(area)


func _on_area_entered(area: Area2D) -> void:
	if area == null:
		return
	var body: Node2D = area.get_parent()
	if body == null or body == self:
		return
	var data = body.get("data")
	if data == null or not data.is_miner:
		return
	var capacity: int = data.carry_capacity
	var carried: int = body.get("carried_coin")
	var space: int = capacity - carried
	if space <= 0:
		return
	var taken: int = mini(coin_value, space)
	body.set("carried_coin", carried + taken)
	coin_value -= taken
	body.queue_redraw()
	_spawn_collected_popup(taken)
	if coin_value <= 0:
		queue_free()


func _spawn_collected_popup(amount: int) -> void:
	var popup: CoinPopup = preload("res://scenes/effects/coin_popup.tscn").instantiate()
	popup.setup(amount)
	popup.global_position = global_position + Vector2(0, -20)
	get_tree().current_scene.add_child(popup)


func _draw() -> void:
	if _COIN_TEXTURE != null:
		var size: Vector2 = _COIN_TEXTURE.get_size()
		draw_texture(_COIN_TEXTURE, -size / 2.0)
	else:
		draw_circle(Vector2.ZERO, 6.0, Color.GOLD)
	var label: String = str(coin_value)
	draw_string(ThemeDB.fallback_font, Vector2(-6, -10), label, HORIZONTAL_ALIGNMENT_CENTER, -1, 10, Color.WHITE)
