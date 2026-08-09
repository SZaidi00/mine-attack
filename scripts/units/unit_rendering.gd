class_name UnitRendering
extends RefCounted

const _HP_BAR_BG: Texture2D = preload("res://frost_mines_assets/ui/hp_bar_unit_bg.png")
const _HP_BAR_GREEN: Texture2D = preload("res://frost_mines_assets/ui/hp_bar_unit_green.png")
const _HP_BAR_ORANGE: Texture2D = preload("res://frost_mines_assets/ui/hp_bar_unit_orange.png")

const _MINER_TEXTURES: Dictionary = {
	GameManager.Team.PLAYER: [
		preload("res://frost_mines_assets/units/miner_l1_player.png"),
		preload("res://frost_mines_assets/units/miner_l2_player.png"),
		preload("res://frost_mines_assets/units/miner_l3_player.png")
	],
	GameManager.Team.ENEMY: [
		preload("res://frost_mines_assets/units/miner_l1_enemy.png"),
		preload("res://frost_mines_assets/units/miner_l2_enemy.png"),
		preload("res://frost_mines_assets/units/miner_l3_enemy.png")
	]
}

const _SELECTION_RING: Texture2D = preload("res://frost_mines_assets/effects/selection_ring.png")
const _IMPACT_TEXTURE: Texture2D = preload("res://frost_mines_assets/effects/impact_hit.png")

# Shared soft radial texture for the miner lantern glow (built once).
static var _glow_texture: Texture2D = null


var unit: Unit

func _init(u: Unit) -> void:
	unit = u


static func _make_glow_texture() -> Texture2D:
	var size: int = 64
	var img: Image = Image.create(size, size, false, Image.FORMAT_RGBA8)
	var center: float = (size - 1) / 2.0
	for x in range(size):
		for y in range(size):
			var d: float = Vector2(x - center, y - center).length() / center
			img.set_pixel(x, y, Color(1, 1, 1, clampf(1.0 - d, 0.0, 1.0) ** 2))
	return ImageTexture.create_from_image(img)


func _get_unit_texture() -> Texture2D:
	var textures: Array[Texture2D]
	if unit.team == GameManager.Team.PLAYER:
		textures = unit.data.player_textures
	else:
		textures = unit.data.enemy_textures

	if unit.data.is_miner:
		var idx: int = clampi(unit.data.miner_level - 1, 0, 2)
		if textures.size() > idx and textures[idx] != null:
			return textures[idx]
		return _MINER_TEXTURES[unit.team][idx]

	if textures.size() > 0 and textures[0] != null:
		return textures[0]
	return null


func draw() -> void:
	var color: Color = GameManager.COLOR_PLAYER if unit.team == GameManager.Team.PLAYER else GameManager.COLOR_ENEMY
	var sprite_texture: Texture2D = _get_unit_texture()
	var scale_factor: float = unit.data.draw_scale if unit.data != null and unit.data.draw_scale > 0.0 else 1.0
	var altitude: float = unit.get_flight_altitude()
	var body_top: float
	var selection_radius: float

	if sprite_texture != null:
		var sprite_size: Vector2 = sprite_texture.get_size() * scale_factor
		body_top = -altitude - sprite_size.y / 2.0
		selection_radius = max(sprite_size.x, sprite_size.y) / 2.0 + 4.0
	else:
		var size: float = 18.0 * scale_factor
		body_top = -altitude - size / 2.0
		selection_radius = size + 4.0

	# Ground shadow under flying units (feet stay at local origin).
	if altitude > 0.0:
		var shadow_w: float = 18.0 * scale_factor
		var shadow_h: float = 6.0 * scale_factor
		unit.draw_set_transform(Vector2.ZERO, 0.0, Vector2(shadow_w / 10.0, shadow_h / 10.0))
		unit.draw_circle(Vector2.ZERO, 5.0, Color(0, 0, 0, 0.35))
		unit.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

	# Lantern glow: a warm halo around miners working underground (Phase 8).
	if unit.data.is_miner and unit.is_underground:
		if _glow_texture == null:
			_glow_texture = _make_glow_texture()
		var flicker: float = 0.30 + 0.05 * sin(Time.get_ticks_msec() / 220.0 + unit.get_instance_id() % 100)
		var glow_size: float = 100.0
		unit.draw_texture_rect(_glow_texture, Rect2(-glow_size / 2.0, -glow_size / 2.0, glow_size, glow_size), false, Color(1.0, 0.85, 0.55, flicker))

	# Selection indicator (gentle pulse) centered on the combat body.
	if unit.selected:
		var pulse: float = 1.0 + 0.08 * sin(Time.get_ticks_msec() / 160.0)
		var ring_radius: float = selection_radius * pulse
		unit.draw_texture_rect(_SELECTION_RING, Rect2(-ring_radius, -altitude - ring_radius, ring_radius * 2.0, ring_radius * 2.0), false)

	# Body (offset upward when flying).
	if sprite_texture != null:
		var sprite_size: Vector2 = sprite_texture.get_size() * scale_factor
		var dest := Rect2(-sprite_size / 2.0 + Vector2(0, -altitude), sprite_size)
		unit.draw_texture_rect(sprite_texture, dest, false)
	else:
		var size: float = 18.0 * scale_factor
		var body_offset := Vector2(0, -altitude)
		unit.draw_rect(Rect2(-size / 2.0 + body_offset.x, -size / 2.0 + body_offset.y, size, size), color, true)
		unit.draw_rect(Rect2(-size / 2.0 + body_offset.x, -size / 2.0 + body_offset.y, size, size), GameManager.COLOR_SHADOW, false, 1.0)

		# Weapon / class indicator (fallback body).
		if unit.data.unit_name == "Swordsman":
			unit.draw_line(Vector2(4, 4) + body_offset, Vector2(16, -8) + body_offset, Color.WHITE, 3.0)
		elif unit.data.unit_name == "Archer":
			unit.draw_arc(Vector2(10, 0) + body_offset, 7, -PI / 2, PI / 2, 8, GameManager.COLOR_RUST, 2.0)
			unit.draw_line(Vector2(10, -7) + body_offset, Vector2(10, 7) + body_offset, GameManager.COLOR_RUST, 2.0)
		elif unit.data.unit_name == "Wizard":
			unit.draw_line(Vector2(6, 6) + body_offset, Vector2(12, -14) + body_offset, GameManager.COLOR_RUST, 2.0)
			unit.draw_circle(Vector2(12, -16) + body_offset, 4, Color.PURPLE)
		elif unit.data.unit_name == "Dragon":
			unit.draw_circle(Vector2(0, -2) + body_offset, 8 * scale_factor, color.darkened(0.15))
			unit.draw_circle(Vector2(10, -6) + body_offset, 3 * scale_factor, Color(1.0, 0.45, 0.15))

	# Miner pickaxe animation and spark burst. Drawn on top of sprites as well
	# so the mining strike is readable even when textured miners are used.
	if unit.data.is_miner:
		_draw_pickaxe(sprite_texture == null)

	# Impact hit flash.
	if unit._hit_flash_timer > 0:
		var impact_size: Vector2 = _IMPACT_TEXTURE.get_size()
		unit.draw_texture(_IMPACT_TEXTURE, -impact_size / 2.0 + Vector2(0, -altitude))

	# HP bar when damaged, hovered, or selected.
	if unit.selected or unit.hovered or unit.hp < unit.data.max_hp:
		var hp_pct: float = float(unit.hp) / float(unit.data.max_hp)
		var bar_rect: Rect2 = Rect2(-10, body_top - 8, 20, 4)
		unit.draw_texture_rect(_HP_BAR_BG, bar_rect, false)
		if hp_pct > 0.0:
			var fill_texture: Texture2D = _HP_BAR_GREEN if hp_pct >= 0.5 else _HP_BAR_ORANGE
			var fill_rect: Rect2 = Rect2(-10, body_top - 8, 20 * hp_pct, 4)
			var src_rect: Rect2 = Rect2(0, 0, fill_texture.get_width() * hp_pct, fill_texture.get_height())
			unit.draw_texture_rect_region(fill_texture, fill_rect, src_rect)

	# Cargo readout above miners: carried / capacity, shown while hauling and
	# whenever the miner is hovered or selected.
	if unit.data.is_miner and (unit.carried_coin > 0 or unit.selected or unit.hovered):
		var cargo_text: String = "%d/%d" % [unit.carried_coin, unit.data.carry_capacity]
		var font: Font = ThemeDB.fallback_font
		var text_pos := Vector2(-20, body_top - 12)
		unit.draw_string(font, text_pos + Vector2(1, 1), cargo_text, HORIZONTAL_ALIGNMENT_CENTER, 40, 10, Color(0, 0, 0, 0.8))
		unit.draw_string(font, text_pos, cargo_text, HORIZONTAL_ALIGNMENT_CENTER, 40, 10, Color(0.984, 0.749, 0.141))


func _draw_pickaxe(draw_body: bool = true) -> void:
	# Base pose: pickaxe held at the miner's side.
	var pivot: Vector2 = Vector2(4, 4)
	var base_rotation: float = -PI / 4.0
	var swing: float = 0.0
	var lunge: Vector2 = Vector2.ZERO
	var striking: bool = false

	if unit._state == Unit.State.MINE:
		# Time the swing to the mining rate so the strike lands on each hit.
		var period: float = 1.0 / max(0.1, unit.data.mining_swings_per_sec)
		var t: float = clamp(1.0 - (unit._mine_timer / period), 0.0, 1.0)
		# Aim the pickaxe toward the target cell.
		var aim_angle: float = unit._mine_target_angle - unit.global_rotation
		base_rotation = aim_angle - PI / 6.0
		# Backswing (0%..60%), then sharp strike (60%..100%).
		if t < 0.6:
			swing = -PI * 0.55 * (t / 0.6)
		else:
			var strike_t: float = (t - 0.6) / 0.4
			swing = -PI * 0.55 + PI * 0.9 * strike_t
			striking = strike_t > 0.75
		if striking:
			lunge = Vector2(cos(aim_angle), sin(aim_angle)) * 3.0

	pivot += lunge
	if draw_body:
		unit.draw_set_transform(pivot, base_rotation + swing, Vector2.ONE)
		# Handle.
		unit.draw_line(Vector2.ZERO, Vector2(12, -12), GameManager.COLOR_STEEL, 2.5)
		# Pick head.
		unit.draw_rect(Rect2(7, -16, 10, 5), GameManager.COLOR_STEEL, true)
		unit.draw_line(Vector2(8, -18), Vector2(16, -14), Color.WHITE, 2.0)
		unit.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

	# Spark burst on the strike impact.
	if unit._state == Unit.State.MINE and (unit._mine_hit_flash > 0.0 or striking):
		var tip: Vector2 = pivot + Vector2(cos(base_rotation + swing), sin(base_rotation + swing)) * 16.0
		var burst_color: Color = Color.YELLOW if unit._mine_hit_flash > 0.0 else Color.ORANGE
		# Bright impact point.
		unit.draw_circle(tip, 3.0, burst_color)
		unit.draw_circle(tip, 1.5, Color.WHITE)
		# Fixed radial sparks so they do not flicker every redraw.
		var spark_count: int = 6
		for i in range(spark_count):
			var spark_angle: float = base_rotation + swing + (i / float(spark_count)) * TAU
			var spark_len: float = 5.0 if unit._mine_hit_flash > 0.0 else 3.0
			unit.draw_line(tip, tip + Vector2(cos(spark_angle), sin(spark_angle)) * spark_len, burst_color, 1.5)
