class_name Lantern
extends Node2D

## Fog of War vision structure (Revamp Phase 1). Surface lanterns come in
## three tiers (built T1, then upgraded in place T1 → T2 → T3); underground
## lanterns are single-tier and permanently reveal buried ore in their radius
## for the owning team once construction finishes. Lanterns only provide
## vision to their owning team and can be destroyed by enemy fighters; a
## destroyed lantern drops half its total build cost as a coin pickup.

signal hp_changed(current: int, maximum: int)
signal destroyed(lantern: Lantern)
signal construction_complete(lantern: Lantern)

const _Constants = preload("res://scripts/autoload/constants.gd")

const _SURFACE_TEXTURES: Dictionary = {
	1: preload("res://frost_mines_assets/props/lantern_t1.png"),
	2: preload("res://frost_mines_assets/props/lantern_t2.png"),
	3: preload("res://frost_mines_assets/props/lantern_t3.png"),
}
const _UNDERGROUND_TEXTURE: Texture2D = preload("res://frost_mines_assets/props/lantern_underground.png")

var team: GameManager.Team = GameManager.Team.PLAYER
var is_underground_lantern: bool = false
var tier: int = 1

var vision_radius: int = 0
var max_hp: int = 0
var hp: int = 0
var build_time: float = 0.0
# Total coin spent on this lantern including upgrades (salvage pays half).
var total_cost: int = 0

var _build_progress: float = 0.0
var _is_built: bool = false

# Shared soft radial texture for the glow halo (built once).
static var _glow_texture: Texture2D = null

@onready var _grid: GridWorld = get_node("/root/Main/World/GridWorld")


func _ready() -> void:
	add_to_group("lanterns")
	_apply_tier_stats()
	hp = max_hp
	queue_redraw()


## Build cost of a lantern kind/tier (for surface lanterns the tier is the
## NEXT tier to build: 1 = new T1, 2/3 = upgrade cost).
static func cost_for(underground: bool, p_tier: int) -> int:
	if underground:
		return _Constants.UNDERGROUND_LANTERN_COST
	match p_tier:
		1:
			return _Constants.LANTERN_T1_COST
		2:
			return _Constants.LANTERN_T2_COST
		_:
			return _Constants.LANTERN_T3_COST


func is_built() -> bool:
	return _is_built


func can_upgrade() -> bool:
	return not is_underground_lantern and tier < 3 and _is_built


## In-place tier upgrade: pays for the next tier and rebuilds (vision is lost
## until construction finishes again).
func upgrade() -> void:
	if not can_upgrade():
		return
	tier += 1
	_apply_tier_stats()
	_is_built = false
	_build_progress = 0.0
	queue_redraw()


func _apply_tier_stats() -> void:
	if is_underground_lantern:
		vision_radius = _Constants.UNDERGROUND_LANTERN_VISION
		max_hp = _Constants.UNDERGROUND_LANTERN_HP
		build_time = _Constants.UNDERGROUND_LANTERN_BUILD_TIME
	else:
		match tier:
			1:
				vision_radius = _Constants.LANTERN_T1_VISION
			2:
				vision_radius = _Constants.LANTERN_T2_VISION
			_:
				vision_radius = _Constants.LANTERN_T3_VISION
		max_hp = _Constants.LANTERN_HP
		build_time = _Constants.LANTERN_BUILD_TIME


func _process(delta: float) -> void:
	if not GameManager.game_active:
		return
	if not _is_built:
		_build_progress += delta
		if _build_progress >= build_time:
			_is_built = true
			if is_underground_lantern:
				_reveal_ore()
			construction_complete.emit(self)
		queue_redraw()
	elif _is_built:
		# Keep the glow halo flickering.
		queue_redraw()


## Underground lanterns reveal buried ore in their radius permanently (the
## same sonar_revealed mechanism the Ore Sonar scan uses — it never fades).
func _reveal_ore() -> void:
	if _grid != null:
		_grid.reveal_ore_in_radius(_grid.world_to_grid(global_position), vision_radius, team)


func take_damage(amount: int) -> void:
	# Invulnerable while under construction (guide rule).
	if not _is_built:
		return
	hp -= amount
	hp_changed.emit(hp, max_hp)
	queue_redraw()
	if hp <= 0:
		_destroy()


func _destroy() -> void:
	remove_from_group("lanterns")
	destroyed.emit(self)
	AudioManager.play("blast", global_position, -6.0)
	var salvage: int = roundi(total_cost * _Constants.LANTERN_SALVAGE_RATIO)
	if salvage > 0:
		var pickup: Node2D = preload("res://scenes/effects/coin_pickup.tscn").instantiate()
		pickup.global_position = global_position
		pickup.set("coin_value", salvage)
		get_tree().current_scene.add_child(pickup)
	queue_free()


## Interaction rect used by unit.attack_building(): a zero-height strip at the
## lantern's "ground line", so the stand point lands on a walkable cell —
## the surface row for surface lanterns, the lantern's own (dug-out) cell
## underground.
func get_bounds_rect() -> Rect2:
	if is_underground_lantern:
		var top: float = floorf(global_position.y / GridWorld.CELL_SIZE) * GridWorld.CELL_SIZE
		return Rect2(global_position.x - 16.0, top, 32.0, 0.0)
	return Rect2(global_position.x - 16.0, 0.0, 32.0, 0.0)


static func _make_glow_texture() -> Texture2D:
	var size: int = 64
	var img: Image = Image.create(size, size, false, Image.FORMAT_RGBA8)
	var center: float = (size - 1) / 2.0
	for x in range(size):
		for y in range(size):
			var d: float = Vector2(x - center, y - center).length() / center
			img.set_pixel(x, y, Color(1, 1, 1, clampf(1.0 - d, 0.0, 1.0) ** 2))
	return ImageTexture.create_from_image(img)


func _get_texture() -> Texture2D:
	if is_underground_lantern:
		return _UNDERGROUND_TEXTURE
	return _SURFACE_TEXTURES.get(tier, _SURFACE_TEXTURES[1])


func _draw() -> void:
	var texture: Texture2D = _get_texture()
	var tex_size: Vector2 = texture.get_size()
	var alpha: float = 1.0 if _is_built else 0.55

	# Warm glow halo once built (bigger tiers glow wider).
	if _is_built:
		if _glow_texture == null:
			_glow_texture = _make_glow_texture()
		var flicker: float = 0.25 + 0.05 * sin(Time.get_ticks_msec() / 240.0 + float(get_instance_id() % 100))
		var glow_size: float = 50.0 + tier * 20.0
		var glow_center: Vector2 = Vector2(0, -tex_size.y / 2.0) if not is_underground_lantern else Vector2.ZERO
		draw_texture_rect(_glow_texture, Rect2(glow_center - Vector2(glow_size, glow_size) / 2.0, Vector2(glow_size, glow_size)), false, Color(1.0, 0.85, 0.55, flicker * alpha))

	# Sprite: surface lanterns stand on the ground line at the bottom of the
	# surface row (local +16 = world y 32); underground lanterns hang centered
	# in their tunnel cell.
	var dest: Rect2
	if is_underground_lantern:
		dest = Rect2(-tex_size / 2.0, tex_size)
	else:
		dest = Rect2(Vector2(-tex_size.x / 2.0, 16.0 - tex_size.y), tex_size)
	draw_texture_rect(texture, dest, false, Color(1, 1, 1, alpha))

	# Team marker: a small colored ring at the base.
	var team_color: Color = GameManager.COLOR_PLAYER if team == GameManager.Team.PLAYER else GameManager.COLOR_ENEMY
	draw_arc(Vector2(0, 14.0) if not is_underground_lantern else Vector2(0, 12.0), 8.0, 0, TAU, 12, team_color, 2.0)

	# Construction progress bar.
	if not _is_built:
		var pct: float = clampf(_build_progress / build_time, 0.0, 1.0)
		var bar_rect: Rect2 = Rect2(-12, dest.position.y - 10, 24, 4)
		draw_rect(bar_rect, Color(0, 0, 0, 0.7), true)
		draw_rect(Rect2(bar_rect.position, Vector2(bar_rect.size.x * pct, bar_rect.size.y)), Color(0.5, 0.8, 1.0), true)
		return

	# HP bar once damaged.
	if hp < max_hp:
		var pct: float = clampf(float(hp) / float(max_hp), 0.0, 1.0)
		var bar_rect: Rect2 = Rect2(-12, dest.position.y - 10, 24, 4)
		draw_rect(bar_rect, Color(0, 0, 0, 0.7), true)
		draw_rect(Rect2(bar_rect.position, Vector2(bar_rect.size.x * pct, bar_rect.size.y)), Color.GREEN if pct >= 0.5 else Color.ORANGE, true)
